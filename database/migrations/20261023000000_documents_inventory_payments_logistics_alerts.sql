-- EP-7 documentos, EP-8 inventario, EP-9 pagos, EP-10 logística y EP-11 notificaciones.
-- Completa lo que dejó la migración 20261019: políticas de Storage corregidas, numeración
-- consecutiva, datos y registro de documentos, vistas de expediente, cartera, conversión de
-- monedas, estados logísticos controlados y alertas con tarea programada.

-- ---------------------------------------------------------------- permisos ---
insert into public.role_permission(role_id, permission_code)
select r.id, p.code
from public.role r
cross join public.permission p
where (r.name in ('administrador', 'usuario_comercial') and p.code in (
        'documents.read','documents.generate','documents.upload',
        'inventory.read','inventory.adjust',
        'logistics.read','logistics.create','logistics.update',
        'payments.read','payments.create'))
   or (r.name = 'encargado_logistico' and p.code in (
        'exports.read','documents.read','inventory.read',
        'logistics.read','logistics.create','logistics.update'))
on conflict do nothing;

-- ------------------------------------------------- PLAT-584: Storage (documentos) ---
-- Rutas: exports/<export_id>/<tipo>/v<n>.pdf (generados) y
--        uploads/<export_id>/<uuid>_<archivo> (adjuntados). Nunca URLs públicas.
drop policy if exists export_documents_insert on storage.objects;
create policy export_documents_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'export-documents'
  and (storage.foldername(name))[2] ~ '^[1-9][0-9]{0,17}$'
  and exists(select 1 from public.export e where e.id = ((storage.foldername(name))[2])::bigint)
  and (
    ((storage.foldername(name))[1] = 'exports' and public.has_permission('documents.generate'))
    or ((storage.foldername(name))[1] = 'uploads' and public.has_permission('documents.upload'))
  )
);

-- Quien subió un objeto aún no registrado en el expediente puede retirarlo (limpieza ante fallos).
drop policy if exists export_documents_delete_unregistered on storage.objects;
create policy export_documents_delete_unregistered on storage.objects for delete to authenticated using (
  bucket_id = 'export-documents'
  and owner_id = auth.uid()::text
  and (public.has_permission('documents.generate') or public.has_permission('documents.upload'))
  and not exists(select 1 from public.stored_file sf where sf.bucket_id = storage.objects.bucket_id and sf.object_path = storage.objects.name)
);

-- ------------------------------------------- PLAT-587: numeración consecutiva ---
alter table public.export_document add column if not exists document_number text
  check (document_number is null or char_length(document_number) <= 40);

create table if not exists public.document_sequence (
  document_type text not null,
  series_year integer not null,
  last_value integer not null check (last_value > 0),
  primary key (document_type, series_year)
);

create table if not exists public.document_number (
  document_number text primary key,
  document_type text not null check (document_type in ('commercial_invoice','packing_list','eur1_certificate')),
  series_year integer not null,
  sequence integer not null check (sequence > 0),
  export_id bigint not null references public.export(id),
  status text not null default 'reserved' check (status in ('reserved','issued')),
  reserved_by_id bigint not null references public.profile(id),
  created_at timestamptz not null default now(),
  issued_at timestamptz,
  unique (document_type, series_year, sequence),
  unique (export_id, document_type)
);

alter table public.document_sequence enable row level security;
alter table public.document_number enable row level security;
drop policy if exists document_number_select on public.document_number;
create policy document_number_select on public.document_number for select to authenticated
  using (public.has_permission('documents.read'));
revoke all on public.document_sequence, public.document_number from public, anon, authenticated;
grant select on public.document_number to authenticated;

-- Reserva (o recupera) el número de un documento. Un mismo documento conserva su número
-- aunque se regenere, y una reserva no usada se reutiliza: la serie no deja huecos.
create or replace function public.reserve_document_number(p_export_id bigint, p_type text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_profile bigint := public.current_profile_id();
  v_year integer := extract(year from now())::integer;
  v_seq integer;
  v_prefix text;
  v_number text;
begin
  if not public.has_permission('documents.generate') then
    raise exception 'No tienes permiso para generar documentos.' using errcode = '42501';
  end if;
  v_prefix := case p_type when 'commercial_invoice' then 'FAC' when 'packing_list' then 'PL' when 'eur1_certificate' then 'EUR1' end;
  if v_prefix is null then raise exception 'Este tipo de documento no usa numeración.' using errcode = '22023'; end if;
  if not exists(select 1 from public.export where id = p_export_id) then
    raise exception 'La exportación no existe.' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('document_number:' || p_export_id || ':' || p_type));
  select dn.document_number into v_number from public.document_number dn
   where dn.export_id = p_export_id and dn.document_type = p_type;
  if found then return v_number; end if;
  insert into public.document_sequence(document_type, series_year, last_value)
  values (p_type, v_year, 1)
  on conflict (document_type, series_year) do update set last_value = public.document_sequence.last_value + 1
  returning last_value into v_seq;
  v_number := v_prefix || '-' || v_year || '-' || lpad(v_seq::text, 6, '0');
  insert into public.document_number(document_number, document_type, series_year, sequence, export_id, reserved_by_id)
  values (v_number, p_type, v_year, v_seq, p_export_id, v_profile);
  return v_number;
end $$;
revoke all on function public.reserve_document_number(bigint, text) from public, anon;
grant execute on function public.reserve_document_number(bigint, text) to authenticated;

-- ------------------------------- datos para las plantillas (factura, packing, EUR.1) ---
create or replace function public.export_document_data(p_export_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_result jsonb;
begin
  if not public.has_permission('documents.generate') then
    raise exception 'No tienes permiso para generar documentos.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'export', jsonb_build_object(
      'id', e.id, 'status', e.status, 'export_date', e.export_date,
      'destination_country_code', e.destination_country_code,
      'destination_name', d.name, 'incoterm_code', e.incoterm_code,
      'order_number', o.order_number, 'currency_code', o.currency_code),
    'customer', jsonb_build_object(
      'name', c.name, 'contact_name', c.contact_name, 'email', c.email,
      'country_code', c.country_code, 'eori_number', c.eori_number),
    'shipment', (select to_jsonb(s) - 'created_by_id' from (
        select sh.carrier, sh.tracking_number, sh.status, sh.transport_mode, sh.container_number
        from public.shipment sh where sh.export_id = e.id and sh.status <> 'cancelled'
        order by sh.created_at desc, sh.id desc limit 1) s),
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'export_line_id', el.id, 'quantity', el.quantity,
        'unit', coalesce(u.name, p.base_unit_code), 'unit_code', p.base_unit_code,
        'unit_price', ol.unit_price, 'currency_code', ol.currency_code,
        'line_total', round(el.quantity * ol.unit_price, 2),
        'hs_code', el.hs_code_snapshot,
        'product_type', p.type, 'variety', p.variety, 'quality_grade', p.quality_grade,
        'lot_code', l.lot_code, 'farm_name', f.name, 'farm_country_code', f.country_code,
        'supplier_name', s.business_name) order by el.id)
      from public.export_line el
      join public.order_line ol on ol.id = el.order_line_id
      join public.product_lot l on l.id = el.product_lot_id
      join public.product p on p.id = l.product_id
      left join public.unit_of_measure u on u.code = p.base_unit_code
      join public.farm f on f.id = l.farm_id
      join public.supplier s on s.id = f.supplier_id
      where el.export_id = e.id), '[]'::jsonb)
  ) into v_result
  from public.export e
  join public.customer_order o on o.id = e.order_id
  join public.customer c on c.id = o.customer_id
  left join public.export_destination d on d.code = e.destination_country_code
  where e.id = p_export_id;
  if v_result is null then raise exception 'La exportación no existe.' using errcode = 'P0002'; end if;
  return v_result;
end $$;
revoke all on function public.export_document_data(bigint) from public, anon;
grant execute on function public.export_document_data(bigint) to authenticated;

-- --------------------- PLAT-579/601: registro atómico de documentos y archivos ---
-- Un solo RPC crea stored_file + export_document (y marca el número emitido). Para archivos
-- adjuntados valida tipo y tamaño en la base, además del bucket.
create or replace function public.register_export_document(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_profile bigint := public.current_profile_id();
  v_export_id bigint;
  v_type text := p->>'document_type';
  v_path text := p->>'object_path';
  v_name text := p->>'original_name';
  v_mime text := p->>'mime_type';
  v_size bigint;
  v_sha text := p->>'sha256';
  v_number text := p->>'document_number';
  v_notes text := nullif(p->>'notes', '');
  v_generated boolean;
  v_version integer;
  v_file_id bigint;
  v_doc public.export_document;
  v_key text;
begin
  if v_profile is null then raise exception 'La sesión no es válida.' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'La solicitud no es válida.' using errcode = '22023'; end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['export_id','document_type','object_path','original_name','mime_type','byte_size','sha256','document_number','notes']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'export_id') is distinct from 'number' or jsonb_typeof(p->'byte_size') is distinct from 'number' then
    raise exception 'La exportación y el tamaño deben ser numéricos.' using errcode = '22023';
  end if;
  v_export_id := (p->>'export_id')::bigint;
  v_size := (p->>'byte_size')::bigint;
  if v_type = any(array['export_summary','commercial_invoice','packing_list','eur1_certificate']) then
    v_generated := true;
    if not public.has_permission('documents.generate') then
      raise exception 'No tienes permiso para generar documentos.' using errcode = '42501';
    end if;
    if v_path is null or v_path !~ ('^exports/' || v_export_id || '/') then
      raise exception 'La ruta del archivo no corresponde a la exportación.' using errcode = '22023';
    end if;
  elsif v_type = any(array['phytosanitary_certificate','other_attachment']) then
    v_generated := false;
    if not public.has_permission('documents.upload') then
      raise exception 'No tienes permiso para adjuntar documentos.' using errcode = '42501';
    end if;
    if v_path is null or v_path !~ ('^uploads/' || v_export_id || '/') then
      raise exception 'La ruta del archivo no corresponde a la exportación.' using errcode = '22023';
    end if;
    if v_mime is null or v_mime <> all(array['application/pdf','image/png','image/jpeg']) then
      raise exception 'Solo se aceptan archivos PDF, PNG o JPEG.' using errcode = '22023';
    end if;
    if v_size is null or v_size < 1 or v_size > 10485760 then
      raise exception 'El archivo debe pesar entre 1 byte y 10 MB.' using errcode = '22023';
    end if;
    if v_name is null or v_name !~* '\.(pdf|png|jpe?g)$' then
      raise exception 'La extensión del archivo debe ser .pdf, .png, .jpg o .jpeg.' using errcode = '22023';
    end if;
  else
    raise exception 'El tipo de documento no es válido.' using errcode = '22023';
  end if;
  if not exists(select 1 from public.export where id = v_export_id) then
    raise exception 'La exportación no existe.' using errcode = 'P0002';
  end if;
  if v_number is not null and not exists(
      select 1 from public.document_number dn where dn.document_number = v_number and dn.export_id = v_export_id and dn.document_type = v_type) then
    raise exception 'El número de documento no corresponde a la exportación.' using errcode = '22023';
  end if;
  if not exists(select 1 from storage.objects o where o.bucket_id = 'export-documents' and o.name = v_path) then
    raise exception 'El archivo no se encuentra en el almacenamiento.' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('export_document:' || v_export_id || ':' || v_type));
  select coalesce(max(version), 0) + 1 into v_version from public.export_document where export_id = v_export_id and document_type = v_type;
  insert into public.stored_file(bucket_id, object_path, original_name, mime_type, byte_size, sha256, uploaded_by_id)
  values ('export-documents', v_path, v_name, v_mime, v_size, v_sha, v_profile) returning id into v_file_id;
  insert into public.export_document(export_id, stored_file_id, document_type, version, document_number, notes, created_by_id)
  values (v_export_id, v_file_id, v_type, v_version, v_number, v_notes, v_profile) returning * into v_doc;
  if v_number is not null then
    update public.document_number set status = 'issued', issued_at = coalesce(issued_at, now()) where document_number = v_number;
  end if;
  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (v_profile, case when v_generated then 'document.generated' else 'document.uploaded' end, 'export', v_export_id,
          jsonb_build_object('document_id', v_doc.id, 'document_type', v_type, 'version', v_version, 'document_number', v_number));
  return jsonb_build_object('id', v_doc.id, 'export_id', v_doc.export_id, 'document_type', v_doc.document_type,
                            'version', v_doc.version, 'document_number', v_doc.document_number,
                            'object_path', v_path, 'created_at', v_doc.created_at);
end $$;
revoke all on function public.register_export_document(jsonb) from public, anon;
grant execute on function public.register_export_document(jsonb) to authenticated;

-- Los INSERT directos se sustituyen por el RPC (también para el certificado fitosanitario).
drop policy if exists export_document_insert on public.export_document;
drop policy if exists stored_file_insert on public.stored_file;
revoke insert on public.export_document, public.stored_file from authenticated;

-- ---------------------------------------- PLAT-603: expediente documental ---
create or replace view public.export_dossier with (security_barrier = true) as
select d.id, d.export_id, d.document_type, d.version, d.document_number, d.notes, d.created_at,
       sf.original_name, sf.mime_type, sf.byte_size, sf.object_path,
       nullif(trim(coalesce(pr.first_name, '') || ' ' || coalesce(pr.last_name, '')), '') as created_by_name
from public.export_document d
join public.stored_file sf on sf.id = d.stored_file_id
left join public.profile pr on pr.id = d.created_by_id
where public.has_permission('documents.read')
   or (public.has_permission('portal.read') and d.export_id in (select public.my_export_ids()));
revoke all on public.export_dossier from public, anon, authenticated;
grant select on public.export_dossier to authenticated;

-- ============================================================= EP-8 inventario ===
-- PLAT-608: inventario consolidado por producto con la bandera de stock bajo.
create or replace view public.inventory_overview with (security_barrier = true) as
select p.id as product_id, p.type as product_type, p.variety, p.quality_grade, p.base_unit_code,
       p.low_stock_threshold,
       count(l.id)::integer as lot_count,
       coalesce(sum(a.available_quantity), 0)::numeric(18,3) as available_quantity,
       (p.low_stock_threshold is not null
        and coalesce(sum(a.available_quantity), 0) <= p.low_stock_threshold) as is_low_stock
from public.product p
left join public.product_lot l on l.product_id = p.id
left join (select m.product_lot_id, sum(m.quantity_delta) as available_quantity
           from public.inventory_movement m group by m.product_lot_id) a on a.product_lot_id = l.id
where p.is_active and public.has_permission('inventory.read')
group by p.id;
revoke all on public.inventory_overview from public, anon, authenticated;
grant select on public.inventory_overview to authenticated;

-- PLAT-613: defensa en profundidad frente a operaciones simultáneas. Cualquier movimiento
-- bloquea el lote y rechaza dejar existencias negativas, sin depender del RPC que lo origina.
create or replace function public.guard_inventory_movement()
returns trigger language plpgsql set search_path = public as $$
begin
  perform 1 from public.product_lot where id = new.product_lot_id for update;
  if (select coalesce(sum(quantity_delta), 0) from public.inventory_movement where product_lot_id = new.product_lot_id) + new.quantity_delta < 0 then
    raise exception 'No hay existencias suficientes para el lote solicitado.' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public.guard_inventory_movement() from public, anon, authenticated;
drop trigger if exists inventory_movement_guard on public.inventory_movement;
create trigger inventory_movement_guard before insert on public.inventory_movement
  for each row execute function public.guard_inventory_movement();

-- ============================================================== EP-9 pagos ===
-- PLAT-625: cartera = obligaciones con lo pagado, el saldo y su estado.
create or replace view public.payment_portfolio with (security_barrier = true) as
select o.id as obligation_id, o.export_id, e.order_id, ord.order_number, ord.customer_id, c.name as customer_name,
       o.amount_due, o.currency_code, o.due_date, o.reference, o.created_at,
       coalesce(t.amount_paid, 0)::numeric(18,2) as amount_paid,
       (o.amount_due - coalesce(t.amount_paid, 0))::numeric(18,2) as balance,
       t.last_paid_at,
       case when o.amount_due - coalesce(t.amount_paid, 0) <= 0 then 'paid'
            when o.due_date is not null and o.due_date < current_date then 'overdue'
            when coalesce(t.amount_paid, 0) > 0 then 'partial'
            else 'pending' end as status,
       case when o.due_date is not null and o.due_date < current_date and o.amount_due - coalesce(t.amount_paid, 0) > 0
            then current_date - o.due_date else 0 end as days_overdue
from public.payment_obligation o
join public.export e on e.id = o.export_id
join public.customer_order ord on ord.id = e.order_id
join public.customer c on c.id = ord.customer_id
left join lateral (select sum(pt.amount) as amount_paid, max(pt.paid_at) as last_paid_at
                   from public.payment_transaction pt where pt.obligation_id = o.id) t on true
where public.has_permission('payments.read');
revoke all on public.payment_portfolio from public, anon, authenticated;
grant select on public.payment_portfolio to authenticated;

-- PLAT-621: el trigger bloquea la obligación (FOR UPDATE) para validar el saldo sin carreras;
-- quien registra pagos solo tiene SELECT/INSERT, así que debe ejecutarse con privilegios del dueño.
create or replace function public.guard_payment_transaction()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_obligation public.payment_obligation; v_paid numeric(18,2);
begin
  select * into v_obligation from public.payment_obligation where id = new.obligation_id for update;
  if not found then raise exception 'La obligación de pago no existe.' using errcode = 'P0002'; end if;
  if new.currency_code <> v_obligation.currency_code then
    raise exception 'El pago debe registrarse en la moneda de la obligación.' using errcode = '22023';
  end if;
  select coalesce(sum(amount), 0) into v_paid from public.payment_transaction where obligation_id = new.obligation_id;
  if v_paid + new.amount > v_obligation.amount_due then
    raise exception 'El pago supera el saldo de la obligación.' using errcode = '23514';
  end if;
  new.recorded_by_id := public.current_profile_id();
  return new;
end $$;
revoke all on function public.guard_payment_transaction() from public, anon, authenticated;

-- Las obligaciones solo se crean sobre exportaciones vigentes.
create or replace function public.guard_payment_obligation()
returns trigger language plpgsql set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.export where id = new.export_id;
  if v_status is null then raise exception 'La exportación no existe.' using errcode = 'P0002'; end if;
  if v_status = 'cancelled' then
    raise exception 'No se pueden registrar obligaciones de una exportación cancelada.' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.guard_payment_obligation() from public, anon, authenticated;
drop trigger if exists payment_obligation_guard on public.payment_obligation;
create trigger payment_obligation_guard before insert on public.payment_obligation
  for each row execute function public.guard_payment_obligation();

-- PLAT-628/630: tasa vigente (directa, inversa o cruzada vía USD) y conversión de montos.
create or replace function public.latest_exchange_rate(p_from text, p_to text, p_at timestamptz default now())
returns table(rate numeric, effective_at timestamptz, source text)
language plpgsql stable set search_path = public as $$
declare v_a record; v_b record;
begin
  if p_from = p_to then return query select 1::numeric, p_at, 'identity'::text; return; end if;
  select r.rate, r.effective_at, r.source into v_a from public.exchange_rate r
   where r.base_currency_code = p_from and r.quote_currency_code = p_to and r.effective_at <= p_at
   order by r.effective_at desc limit 1;
  if found then return query select v_a.rate, v_a.effective_at, v_a.source; return; end if;
  select r.rate, r.effective_at, r.source into v_a from public.exchange_rate r
   where r.base_currency_code = p_to and r.quote_currency_code = p_from and r.effective_at <= p_at
   order by r.effective_at desc limit 1;
  if found then return query select (1 / v_a.rate)::numeric, v_a.effective_at, v_a.source; return; end if;
  if p_from <> 'USD' and p_to <> 'USD' then
    select x.rate, x.effective_at, x.source into v_a from public.latest_exchange_rate(p_from, 'USD', p_at) x;
    select x.rate, x.effective_at, x.source into v_b from public.latest_exchange_rate('USD', p_to, p_at) x;
    if v_a.rate is not null and v_b.rate is not null then
      return query select (v_a.rate * v_b.rate)::numeric, least(v_a.effective_at, v_b.effective_at), (v_a.source || ' + ' || v_b.source)::text;
    end if;
  end if;
end $$;
revoke all on function public.latest_exchange_rate(text, text, timestamptz) from public, anon;
grant execute on function public.latest_exchange_rate(text, text, timestamptz) to authenticated;

create or replace function public.convert_amount(p_amount numeric, p_from text, p_to text, p_at timestamptz default now())
returns jsonb language plpgsql stable set search_path = public as $$
declare v_rate record;
begin
  if not public.has_permission('payments.read') then
    raise exception 'No tienes permiso para consultar tasas de cambio.' using errcode = '42501';
  end if;
  if p_amount is null or p_from !~ '^[A-Z]{3}$' or p_to !~ '^[A-Z]{3}$' then
    raise exception 'Monto o moneda no válidos.' using errcode = '22023';
  end if;
  select * into v_rate from public.latest_exchange_rate(p_from, p_to, p_at);
  if v_rate.rate is null then
    raise exception 'No hay tasa de cambio disponible de % a %.', p_from, p_to using errcode = 'P0002';
  end if;
  return jsonb_build_object('amount', p_amount, 'from', p_from, 'to', p_to, 'rate', v_rate.rate,
                            'converted', round(p_amount * v_rate.rate, 2),
                            'rate_effective_at', v_rate.effective_at, 'source', v_rate.source);
end $$;
revoke all on function public.convert_amount(numeric, text, text, timestamptz) from public, anon;
grant execute on function public.convert_amount(numeric, text, text, timestamptz) to authenticated;

-- Cartera expresada en otra moneda: una fila por obligación con tasa conocida.
create or replace function public.payment_portfolio_in(p_currency text)
returns table(obligation_id bigint, amount_due_converted numeric, balance_converted numeric, rate numeric, rate_effective_at timestamptz)
language sql stable set search_path = public as $$
  select pp.obligation_id, round(pp.amount_due * x.rate, 2), round(pp.balance * x.rate, 2), x.rate, x.effective_at
  from public.payment_portfolio pp
  cross join lateral public.latest_exchange_rate(pp.currency_code, p_currency) x
  where x.rate is not null and p_currency ~ '^[A-Z]{3}$';
$$;
revoke all on function public.payment_portfolio_in(text) from public, anon;
grant execute on function public.payment_portfolio_in(text) to authenticated;

-- Alta manual de una tasa (la integración externa usa service_role desde la Edge Function).
create or replace function public.register_exchange_rate(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not public.has_permission('payments.create') then
    raise exception 'No tienes permiso para registrar tasas de cambio.' using errcode = '42501';
  end if;
  insert into public.exchange_rate(base_currency_code, quote_currency_code, rate, effective_at, source)
  values (p->>'base_currency_code', p->>'quote_currency_code', (p->>'rate')::numeric,
          coalesce((p->>'effective_at')::timestamptz, now()), coalesce(nullif(p->>'source', ''), 'manual'))
  on conflict (base_currency_code, quote_currency_code, effective_at, source) do update set rate = excluded.rate
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.register_exchange_rate(jsonb) from public, anon;
grant execute on function public.register_exchange_rate(jsonb) to authenticated;

-- ============================================================ EP-10 logística ===
-- PLAT-633: catálogo de estados y transiciones permitidas.
create table if not exists public.shipment_status (
  code text primary key,
  label text not null,
  sort_order integer not null,
  is_terminal boolean not null default false
);
insert into public.shipment_status(code, label, sort_order, is_terminal) values
  ('planned', 'Planificado', 1, false),
  ('in_transit', 'En tránsito', 2, false),
  ('in_customs', 'En aduana', 3, false),
  ('delivered', 'Entregado', 4, true),
  ('cancelled', 'Cancelado', 5, true)
on conflict (code) do update set label = excluded.label, sort_order = excluded.sort_order, is_terminal = excluded.is_terminal;

create table if not exists public.shipment_status_transition (
  from_status text not null references public.shipment_status(code),
  to_status text not null references public.shipment_status(code),
  primary key (from_status, to_status)
);
insert into public.shipment_status_transition(from_status, to_status) values
  ('planned', 'in_transit'), ('planned', 'cancelled'),
  ('in_transit', 'in_customs'), ('in_transit', 'delivered'), ('in_transit', 'cancelled'),
  ('in_customs', 'in_transit'), ('in_customs', 'delivered'), ('in_customs', 'cancelled')
on conflict do nothing;

alter table public.shipment_status enable row level security;
alter table public.shipment_status_transition enable row level security;
drop policy if exists shipment_status_select on public.shipment_status;
create policy shipment_status_select on public.shipment_status for select to authenticated using (public.is_active_user());
drop policy if exists shipment_status_transition_select on public.shipment_status_transition;
create policy shipment_status_transition_select on public.shipment_status_transition for select to authenticated using (public.is_active_user());
revoke all on public.shipment_status, public.shipment_status_transition from public, anon, authenticated;
grant select on public.shipment_status, public.shipment_status_transition to authenticated;

alter table public.shipment drop constraint if exists shipment_status_check;
alter table public.shipment drop constraint if exists shipment_status_fk;
alter table public.shipment add constraint shipment_status_fk foreign key (status) references public.shipment_status(code);

-- PLAT-642: modalidad de transporte y contenedor (transportista y guía ya existen).
alter table public.shipment add column if not exists transport_mode text
  check (transport_mode is null or transport_mode in ('sea','air','road','rail'));
alter table public.shipment add column if not exists container_number text
  check (container_number is null or char_length(container_number) <= 40);

-- El estado solo cambia por update_shipment_status; los datos de transporte sí son editables.
create or replace function public.prepare_shipment_insert()
returns trigger language plpgsql set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.export where id = new.export_id;
  if v_status is null then raise exception 'La exportación no existe.' using errcode = 'P0002'; end if;
  if v_status = 'cancelled' then raise exception 'No se puede enviar una exportación cancelada.' using errcode = 'P0001'; end if;
  new.status := 'planned';
  new.shipped_at := null;
  new.delivered_at := null;
  return new;
end $$;
revoke all on function public.prepare_shipment_insert() from public, anon, authenticated;
drop trigger if exists shipment_prepare_insert on public.shipment;
create trigger shipment_prepare_insert before insert on public.shipment
  for each row execute function public.prepare_shipment_insert();

revoke update on public.shipment from authenticated;
grant update (carrier, tracking_number, estimated_delivery_at, transport_mode, container_number, updated_at) on public.shipment to authenticated;
revoke insert on public.shipment_event from authenticated;

-- Notificación para las cuentas del cliente dueño del envío (se define en la sección EP-11).
alter table public.notification add column if not exists dedupe_key text;
create unique index if not exists notification_dedupe_uq on public.notification(recipient_user_id, dedupe_key) where dedupe_key is not null;

create or replace function public.notify_permission_holders(
  p_permission text, p_type text, p_title text, p_body text, p_entity_type text, p_entity_id bigint, p_dedupe text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  insert into public.notification(recipient_user_id, notification_type, title, body, entity_type, entity_id, dedupe_key)
  select pr.id, p_type, p_title, p_body, p_entity_type, p_entity_id, p_dedupe
  from public.profile pr
  join public.role r on r.id = pr.role_id and r.is_active
  join public.role_permission rp on rp.role_id = r.id and rp.permission_code = p_permission
  where pr.is_active
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke all on function public.notify_permission_holders(text, text, text, text, text, bigint, text) from public, anon, authenticated;

-- PLAT-635: cambio de estado logístico atómico, con historial y aviso al cliente.
create or replace function public.update_shipment_status(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_profile bigint := public.current_profile_id();
  v_id bigint;
  v_to text := p->>'status';
  v_ship public.shipment;
  v_label text;
  v_lat numeric;
  v_lon numeric;
  v_key text;
  v_customer bigint;
  v_order text;
begin
  if not public.has_permission('logistics.update') then
    raise exception 'No tienes permiso para actualizar envíos.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'La solicitud no es válida.' using errcode = '22023'; end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['shipment_id','status','description','location','latitude','longitude']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'shipment_id') is distinct from 'number' then
    raise exception 'El envío es obligatorio.' using errcode = '22023';
  end if;
  v_id := (p->>'shipment_id')::bigint;
  select * into v_ship from public.shipment where id = v_id for update;
  if not found then raise exception 'El envío no existe.' using errcode = 'P0002'; end if;
  select label into v_label from public.shipment_status where code = v_to;
  if v_label is null then raise exception 'El estado del envío no es válido.' using errcode = '22023'; end if;
  if not exists(select 1 from public.shipment_status_transition t where t.from_status = v_ship.status and t.to_status = v_to) then
    raise exception 'No se puede pasar el envío de % a %.', v_ship.status, v_to using errcode = 'P0001';
  end if;
  if (p->>'latitude') is not null or (p->>'longitude') is not null then
    if (p->>'latitude') is null or (p->>'longitude') is null then
      raise exception 'Indica latitud y longitud juntas.' using errcode = '22023';
    end if;
    v_lat := (p->>'latitude')::numeric; v_lon := (p->>'longitude')::numeric;
  end if;
  update public.shipment set
    status = v_to,
    shipped_at = case when v_to = 'in_transit' and shipped_at is null then now() else shipped_at end,
    delivered_at = case when v_to = 'delivered' then now() else delivered_at end,
    updated_at = now()
  where id = v_id;
  insert into public.shipment_event(shipment_id, event_type, description, location, latitude, longitude, recorded_by_id)
  values (v_id, v_to, nullif(p->>'description', ''), nullif(p->>'location', ''), v_lat, v_lon, v_profile);
  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (v_profile, 'shipment.status_changed', 'shipment', v_id, jsonb_build_object('from', v_ship.status, 'to', v_to));
  -- Aviso a las cuentas del cliente dueño del pedido.
  select ord.customer_id, ord.order_number into v_customer, v_order
    from public.export e join public.customer_order ord on ord.id = e.order_id where e.id = v_ship.export_id;
  insert into public.notification(recipient_user_id, notification_type, title, body, entity_type, entity_id, dedupe_key)
  select cu.profile_id, 'shipment_status', 'Tu envío cambió a «' || v_label || '»',
         'Pedido ' || v_order || coalesce(' · ' || nullif(p->>'location', ''), ''), 'shipment', v_id,
         'shipment_status:' || v_id || ':' || v_to
  from public.customer_user cu
  join public.profile pr on pr.id = cu.profile_id and pr.is_active
  where cu.customer_id = v_customer
  on conflict do nothing;
  return jsonb_build_object('id', v_id, 'status', v_to, 'previous_status', v_ship.status);
end $$;
revoke all on function public.update_shipment_status(jsonb) from public, anon;
grant execute on function public.update_shipment_status(jsonb) to authenticated;

-- Registro de un evento libre (sin cambiar el estado): hito, incidencia, ubicación.
create or replace function public.add_shipment_event(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_lat numeric; v_lon numeric; v_event bigint; v_key text;
begin
  if not public.has_permission('logistics.update') then
    raise exception 'No tienes permiso para registrar eventos logísticos.' using errcode = '42501';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['shipment_id','event_type','description','location','latitude','longitude']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'shipment_id') is distinct from 'number' or coalesce(char_length(p->>'event_type'), 0) not between 1 and 80 then
    raise exception 'Indica el envío y el tipo de evento.' using errcode = '22023';
  end if;
  v_id := (p->>'shipment_id')::bigint;
  perform 1 from public.shipment where id = v_id;
  if not found then raise exception 'El envío no existe.' using errcode = 'P0002'; end if;
  if (p->>'latitude') is not null then v_lat := (p->>'latitude')::numeric; v_lon := (p->>'longitude')::numeric; end if;
  insert into public.shipment_event(shipment_id, event_type, description, location, latitude, longitude, recorded_by_id)
  values (v_id, p->>'event_type', nullif(p->>'description', ''), nullif(p->>'location', ''), v_lat, v_lon, public.current_profile_id())
  returning id into v_event;
  return v_event;
end $$;
revoke all on function public.add_shipment_event(jsonb) from public, anon;
grant execute on function public.add_shipment_event(jsonb) to authenticated;

-- PLAT-638: seguimiento para el cliente externo (solo sus envíos).
create or replace view public.customer_shipment_tracking with (security_barrier = true) as
select sh.id as shipment_id, sh.export_id, ord.order_number, e.destination_country_code,
       sh.status, ss.label as status_label, sh.carrier, sh.tracking_number, sh.transport_mode,
       sh.shipped_at, sh.estimated_delivery_at, sh.delivered_at,
       last_ev.event_type as last_event_type, last_ev.location as last_location, last_ev.event_at as last_event_at
from public.shipment sh
join public.shipment_status ss on ss.code = sh.status
join public.export e on e.id = sh.export_id
join public.customer_order ord on ord.id = e.order_id
left join lateral (select ev.event_type, ev.location, ev.event_at from public.shipment_event ev
                   where ev.shipment_id = sh.id order by ev.event_at desc, ev.id desc limit 1) last_ev on true
where public.has_permission('portal.read') and sh.id in (select public.my_shipment_ids());
revoke all on public.customer_shipment_tracking from public, anon, authenticated;
grant select on public.customer_shipment_tracking to authenticated;

-- El catálogo de envíos expone los datos de transporte nuevos (columnas al final).
create or replace view public.shipment_catalog with (security_barrier = true) as
select sh.id, sh.export_id, e.order_id, o.order_number, o.customer_id, c.name as customer_name,
       sh.carrier, sh.tracking_number, sh.status, sh.shipped_at, sh.estimated_delivery_at,
       sh.delivered_at, sh.created_at, sh.transport_mode, sh.container_number
from public.shipment sh join public.export e on e.id = sh.export_id
join public.customer_order o on o.id = e.order_id join public.customer c on c.id = o.customer_id
where public.has_permission('logistics.read');
grant select on public.shipment_catalog to authenticated;

-- ======================================================== EP-11 notificaciones ===
-- PLAT-650: alerta de stock bajo por producto (existencias totales <= umbral).
create or replace function public.check_low_stock(p_product_id bigint default null)
returns integer language plpgsql security definer set search_path = public as $$
declare r record; v_total integer := 0; v_n integer;
begin
  for r in
    select p.id, p.variety, p.quality_grade, p.base_unit_code, p.low_stock_threshold,
           coalesce(sum(m.quantity_delta), 0) as available
    from public.product p
    left join public.product_lot l on l.product_id = p.id
    left join public.inventory_movement m on m.product_lot_id = l.id
    where p.is_active and p.low_stock_threshold is not null and (p_product_id is null or p.id = p_product_id)
    group by p.id
    having coalesce(sum(m.quantity_delta), 0) <= p.low_stock_threshold
  loop
    v_n := public.notify_permission_holders(
      'inventory.read', 'low_stock', 'Stock bajo: ' || r.variety || ' (' || r.quality_grade || ')',
      'Quedan ' || trim(to_char(r.available, 'FM999999999990.999'), '.') || ' ' || r.base_unit_code
        || '; el umbral mínimo es ' || trim(to_char(r.low_stock_threshold, 'FM999999999990.999'), '.') || '.',
      'product', r.id, 'low_stock:' || r.id || ':' || current_date);
    v_total := v_total + v_n;
  end loop;
  return v_total;
end $$;
revoke all on function public.check_low_stock(bigint) from public, anon, authenticated;

create or replace function public.alert_low_stock_after_movement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.check_low_stock((select product_id from public.product_lot where id = new.product_lot_id));
  return null;
end $$;
revoke all on function public.alert_low_stock_after_movement() from public, anon, authenticated;
drop trigger if exists inventory_movement_low_stock on public.inventory_movement;
create trigger inventory_movement_low_stock after insert on public.inventory_movement
  for each row when (new.quantity_delta < 0) execute function public.alert_low_stock_after_movement();

-- PLAT-653: pagos por vencer (en 3 días o menos) o vencidos con saldo.
create or replace function public.check_payment_alerts()
returns integer language plpgsql security definer set search_path = public as $$
declare r record; v_total integer := 0;
begin
  for r in
    select o.id, o.due_date, o.currency_code, ord.order_number, c.name as customer_name,
           o.amount_due - coalesce((select sum(t.amount) from public.payment_transaction t where t.obligation_id = o.id), 0) as balance
    from public.payment_obligation o
    join public.export e on e.id = o.export_id
    join public.customer_order ord on ord.id = e.order_id
    join public.customer c on c.id = ord.customer_id
    where o.due_date is not null and o.due_date <= current_date + 3
  loop
    continue when r.balance <= 0;
    if r.due_date < current_date then
      v_total := v_total + public.notify_permission_holders(
        'payments.read', 'payment_overdue', 'Pago vencido: pedido ' || r.order_number,
        r.customer_name || ' debe ' || r.balance || ' ' || r.currency_code || ' desde el ' || r.due_date || '.',
        'payment_obligation', r.id, 'payment_overdue:' || r.id || ':' || current_date);
    else
      v_total := v_total + public.notify_permission_holders(
        'payments.read', 'payment_due', 'Pago por vencer: pedido ' || r.order_number,
        r.customer_name || ' debe ' || r.balance || ' ' || r.currency_code || ' el ' || r.due_date || '.',
        'payment_obligation', r.id, 'payment_due:' || r.id);
    end if;
  end loop;
  return v_total;
end $$;
revoke all on function public.check_payment_alerts() from public, anon, authenticated;

-- PLAT-647: ejecución programada. run_scheduled_alerts la invoca pg_cron (cada hora) y, como
-- respaldo, la app al abrir el centro de notificaciones (como máximo cada 5 minutos).
create table if not exists public.alert_run (
  id smallint primary key check (id = 1),
  last_run_at timestamptz not null
);
alter table public.alert_run enable row level security;
revoke all on public.alert_run from public, anon, authenticated;

create or replace function public.run_scheduled_alerts(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_last timestamptz; v_stock integer; v_pay integer;
begin
  perform pg_advisory_xact_lock(hashtext('run_scheduled_alerts'));
  select last_run_at into v_last from public.alert_run where id = 1;
  if not p_force and v_last is not null and v_last > now() - interval '5 minutes' then
    return jsonb_build_object('skipped', true, 'last_run_at', v_last);
  end if;
  v_stock := public.check_low_stock();
  v_pay := public.check_payment_alerts();
  insert into public.alert_run(id, last_run_at) values (1, now())
  on conflict (id) do update set last_run_at = excluded.last_run_at;
  return jsonb_build_object('skipped', false, 'low_stock', v_stock, 'payments', v_pay);
end $$;
revoke all on function public.run_scheduled_alerts(boolean) from public, anon;
grant execute on function public.run_scheduled_alerts(boolean) to authenticated;

-- Con pg_cron disponible (Supabase hospedado) se programa cada hora; sin él, queda el respaldo.
do $$
begin
  if exists(select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'riexport-alerts';
    perform cron.schedule('riexport-alerts', '0 * * * *', 'select public.run_scheduled_alerts(true)');
  end if;
exception when others then
  raise notice 'pg_cron no está configurado: %', sqlerrm;
end $$;

-- El REVOKE UPDATE de la migración 20261019 también retiró el permiso por columna: se restituye.
grant update (read_at) on public.notification to authenticated;

-- PLAT-654: centro de notificaciones (la lectura es propia; marcar todas como leídas).
create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  update public.notification set read_at = now()
   where recipient_user_id = public.current_profile_id() and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke all on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.mark_all_notifications_read() to authenticated;
