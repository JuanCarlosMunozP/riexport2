-- EP-3 trazabilidad, EP-4 historial comercial y EP-1 permisos de exportaciones,
-- documentos, logística, notificaciones y aislamiento del portal.
-- Una exportación divide líneas de un pedido confirmado; un envío pertenece a
-- una exportación. Un archivo queda privado en Storage y su expediente se
-- vincula mediante stored_file/export_document.

-- id numerico del perfil del usuario actual (null si no hay sesion o la cuenta esta desactivada).
-- Antes solo existia en database/drafts/domain_policies.sql; las politicas e disparadores de abajo lo usan.
create or replace function public.current_profile_id()
returns bigint
language sql stable security definer set search_path = public
as $$
  select pr.id
  from public.profile pr
  join public.role r on r.id = pr.role_id
  where pr.auth_user_id = auth.uid() and pr.is_active and r.is_active;
$$;
revoke all on function public.current_profile_id() from public, anon;
grant execute on function public.current_profile_id() to authenticated;

create table if not exists public.export (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.customer_order(id),
  destination_country_code text not null check (destination_country_code ~ '^[A-Z]{2}$'),
  export_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','formalized','cancelled')),
  created_by_id bigint references public.profile(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists export_order_idx on public.export(order_id, export_date desc);

create table if not exists public.export_line (
  id bigint generated always as identity primary key,
  export_id bigint not null references public.export(id),
  order_line_id bigint not null references public.order_line(id),
  product_lot_id bigint not null references public.product_lot(id),
  quantity numeric(18,3) not null check (quantity > 0),
  hs_code_snapshot text check (hs_code_snapshot is null or hs_code_snapshot ~ '^[0-9]{4}(\.[0-9]{2}){0,3}$'),
  created_at timestamptz not null default now(),
  unique(export_id, order_line_id)
);
create index if not exists export_line_export_idx on public.export_line(export_id);
create index if not exists export_line_lot_idx on public.export_line(product_lot_id);

create table if not exists public.shipment (
  id bigint generated always as identity primary key,
  export_id bigint not null references public.export(id),
  carrier text check (carrier is null or char_length(carrier) <= 120),
  tracking_number text check (tracking_number is null or char_length(tracking_number) <= 160),
  status text not null default 'planned' check (status in ('planned','in_transit','delivered','cancelled')),
  shipped_at timestamptz,
  estimated_delivery_at date,
  delivered_at timestamptz,
  created_by_id bigint references public.profile(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (delivered_at is null or shipped_at is null or delivered_at >= shipped_at)
);
create index if not exists shipment_export_idx on public.shipment(export_id, created_at desc);

create table if not exists public.shipment_event (
  id bigint generated always as identity primary key,
  shipment_id bigint not null references public.shipment(id),
  event_type text not null check (char_length(event_type) between 1 and 80),
  description text check (description is null or char_length(description) <= 1000),
  location text check (location is null or char_length(location) <= 240),
  latitude numeric(9,6) check (latitude is null or latitude between -90 and 90),
  longitude numeric(9,6) check (longitude is null or longitude between -180 and 180),
  event_at timestamptz not null default now(),
  recorded_by_id bigint references public.profile(id) on delete set null,
  check ((latitude is null) = (longitude is null))
);
create index if not exists shipment_event_timeline_idx on public.shipment_event(shipment_id, event_at desc);

create or replace function public.stamp_export_shipment_actor()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='export' then
    if tg_op='INSERT' then
      new.created_by_id := public.current_profile_id();
      new.status := 'draft';
    else
      new.updated_at := now();
    end if;
  elsif tg_op='INSERT' then
    new.created_by_id := public.current_profile_id();
  else
    new.updated_at := now();
  end if;
  return new;
end $$;
revoke all on function public.stamp_export_shipment_actor() from public,anon,authenticated;
drop trigger if exists export_actor_stamp on public.export;
create trigger export_actor_stamp before insert on public.export for each row execute function public.stamp_export_shipment_actor();
drop trigger if exists shipment_actor_stamp on public.shipment;
create trigger shipment_actor_stamp before insert or update on public.shipment for each row execute function public.stamp_export_shipment_actor();

create or replace function public.stamp_shipment_event_actor()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  new.recorded_by_id := public.current_profile_id();
  return new;
end $$;
revoke all on function public.stamp_shipment_event_actor() from public,anon,authenticated;
drop trigger if exists shipment_event_actor_stamp on public.shipment_event;
create trigger shipment_event_actor_stamp before insert on public.shipment_event for each row execute function public.stamp_shipment_event_actor();

create or replace function public.prevent_order_cancel_after_export()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.status='cancelled' and old.status <> 'cancelled'
     and exists(select 1 from public.export e where e.order_id=old.id and e.status <> 'cancelled') then
    raise exception 'No se puede cancelar un pedido con exportaciones activas.' using errcode='P0001';
  end if;
  return new;
end $$;
revoke all on function public.prevent_order_cancel_after_export() from public,anon,authenticated;
drop trigger if exists customer_order_export_guard on public.customer_order;
create trigger customer_order_export_guard before update of status on public.customer_order for each row execute function public.prevent_order_cancel_after_export();

create table if not exists public.stored_file (
  id bigint generated always as identity primary key,
  bucket_id text not null check (bucket_id = 'export-documents'),
  object_path text not null unique,
  original_name text not null check (char_length(original_name) between 1 and 255),
  mime_type text not null check (mime_type in ('application/pdf','image/png','image/jpeg')),
  byte_size bigint not null check (byte_size between 1 and 20971520),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by_id bigint not null references public.profile(id),
  uploaded_at timestamptz not null default now()
);

create table if not exists public.export_document (
  id bigint generated always as identity primary key,
  export_id bigint not null references public.export(id),
  stored_file_id bigint not null references public.stored_file(id),
  document_type text not null check (char_length(document_type) between 1 and 80),
  version integer not null default 1 check (version > 0),
  notes text check (notes is null or char_length(notes) <= 1000),
  created_by_id bigint not null references public.profile(id),
  created_at timestamptz not null default now(),
  unique(export_id, document_type, version),
  unique(stored_file_id)
);
create index if not exists export_document_export_idx on public.export_document(export_id, document_type, version desc);

create table if not exists public.notification (
  id bigint generated always as identity primary key,
  recipient_user_id bigint not null references public.profile(id) on delete cascade,
  notification_type text not null check (char_length(notification_type) between 1 and 80),
  title text not null check (char_length(title) between 1 and 180),
  body text check (body is null or char_length(body) <= 1000),
  entity_type text,
  entity_id bigint,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notification_recipient_idx on public.notification(recipient_user_id, created_at desc);

-- Registro financiero mínimo: obligaciones por exportación y pagos parciales
-- inmutables en la moneda de la obligación. No convierte divisas automáticamente.
create table if not exists public.payment_obligation (
  id bigint generated always as identity primary key,
  export_id bigint not null references public.export(id),
  amount_due numeric(18,2) not null check (amount_due > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  due_date date,
  reference text check (reference is null or char_length(reference) <= 160),
  created_by_id bigint not null references public.profile(id),
  created_at timestamptz not null default now()
);
create index if not exists payment_obligation_export_idx on public.payment_obligation(export_id);

create table if not exists public.payment_transaction (
  id bigint generated always as identity primary key,
  obligation_id bigint not null references public.payment_obligation(id),
  amount numeric(18,2) not null check (amount > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  reference text check (reference is null or char_length(reference) <= 160),
  paid_at timestamptz not null default now(),
  recorded_by_id bigint not null references public.profile(id),
  created_at timestamptz not null default now()
);
create index if not exists payment_transaction_obligation_idx on public.payment_transaction(obligation_id, paid_at desc);

create table if not exists public.exchange_rate (
  id bigint generated always as identity primary key,
  base_currency_code text not null check (base_currency_code ~ '^[A-Z]{3}$'),
  quote_currency_code text not null check (quote_currency_code ~ '^[A-Z]{3}$'),
  rate numeric(20,10) not null check (rate > 0),
  effective_at timestamptz not null,
  source text not null check (char_length(source) between 1 and 160),
  created_at timestamptz not null default now(),
  check (base_currency_code <> quote_currency_code),
  unique(base_currency_code,quote_currency_code,effective_at,source)
);
create index if not exists exchange_rate_latest_idx on public.exchange_rate(base_currency_code,quote_currency_code,effective_at desc);

create or replace function public.guard_payment_transaction()
returns trigger language plpgsql set search_path=public as $$
declare v_obligation public.payment_obligation; v_paid numeric(18,2);
begin
  select * into v_obligation from public.payment_obligation where id=new.obligation_id for update;
  if not found then raise exception 'La obligación de pago no existe.' using errcode='P0002'; end if;
  if new.currency_code <> v_obligation.currency_code then raise exception 'El pago debe registrarse en la moneda de la obligación.' using errcode='22023'; end if;
  select coalesce(sum(amount),0) into v_paid from public.payment_transaction where obligation_id=new.obligation_id;
  if v_paid + new.amount > v_obligation.amount_due then raise exception 'El pago supera el saldo de la obligación.' using errcode='23514'; end if;
  new.recorded_by_id := public.current_profile_id();
  return new;
end $$;
revoke all on function public.guard_payment_transaction() from public,anon,authenticated;
drop trigger if exists payment_transaction_guard on public.payment_transaction;
create trigger payment_transaction_guard before insert on public.payment_transaction for each row execute function public.guard_payment_transaction();

create or replace function public.stamp_payment_obligation_actor()
returns trigger language plpgsql security definer set search_path=public as $$
begin new.created_by_id := public.current_profile_id(); return new; end $$;
revoke all on function public.stamp_payment_obligation_actor() from public,anon,authenticated;
drop trigger if exists payment_obligation_actor_stamp on public.payment_obligation;
create trigger payment_obligation_actor_stamp before insert on public.payment_obligation for each row execute function public.stamp_payment_obligation_actor();

-- Permisos asignables por el administrador desde la pantalla de roles.
insert into public.permission(code, description) values
  ('exports.read','Consultar exportaciones.'),
  ('exports.create','Registrar exportaciones.'),
  ('exports.update','Editar y formalizar exportaciones.'),
  ('documents.read','Consultar documentos de exportación.'),
  ('documents.generate','Generar documentos de exportación.'),
  ('documents.upload','Adjuntar documentos de exportación.'),
  ('logistics.read','Consultar envíos y su línea de tiempo.'),
  ('logistics.create','Registrar envíos.'),
  ('logistics.update','Actualizar envíos y registrar eventos logísticos.'),
  ('payments.read','Consultar obligaciones, pagos y tasas de cambio.'),
  ('payments.create','Registrar obligaciones y pagos.')
on conflict(code) do nothing;

-- Reglas de edición: una exportación formalizada es inmutable; líneas solo en borrador.
create or replace function public.guard_export_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.status = 'formalized' then raise exception 'Una exportación formalizada es inmutable.' using errcode = 'P0001'; end if;
  if old.status = 'cancelled' and new.status <> 'cancelled' then raise exception 'Una exportación cancelada no se puede reabrir.' using errcode = 'P0001'; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists export_guard on public.export;
create trigger export_guard before update on public.export for each row execute function public.guard_export_update();

create or replace function public.guard_export_line()
returns trigger language plpgsql set search_path = public as $$
declare
  v_export_id bigint;
  v_order_id bigint;
  v_line public.order_line;
  v_allocated numeric(18,3);
  v_current_line_id bigint;
begin
  v_export_id := case when tg_op = 'DELETE' then old.export_id else new.export_id end;
  if tg_op = 'UPDATE' then v_current_line_id := old.id; end if;
  select e.order_id into v_order_id from public.export e where e.id = v_export_id and e.status = 'draft';
  if not found then
    raise exception 'Solo se pueden modificar líneas de una exportación en borrador.' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select * into v_line from public.order_line where id=new.order_line_id and order_id=v_order_id;
  if not found or v_line.product_lot_id <> new.product_lot_id then
    raise exception 'La línea y el lote deben pertenecer al pedido de la exportación.' using errcode = '22023';
  end if;
  select coalesce(sum(el.quantity),0) into v_allocated
    from public.export_line el join public.export e on e.id=el.export_id
    where el.order_line_id=new.order_line_id and e.status <> 'cancelled'
      and (v_current_line_id is null or el.id <> v_current_line_id);
  if v_allocated + new.quantity > v_line.quantity then
    raise exception 'La cantidad supera el saldo disponible de la línea del pedido.' using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists export_line_guard on public.export_line;
create trigger export_line_guard before insert or update or delete on public.export_line for each row execute function public.guard_export_line();

-- Creación atómica: exige pedido confirmado y no permite exportar más cantidad
-- que la pedida. El código HS y lote se copian desde la línea original.
create or replace function public.create_customer_export(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_order_id bigint;
  v_export_id bigint;
  v_country text;
  v_date date;
  v_line jsonb;
  v_order_line public.order_line;
  v_quantity numeric(18,3);
  v_allocated numeric(18,3);
  v_profile_id bigint;
  v_key text;
begin
  if not public.has_permission('exports.create') then raise exception 'No tienes permiso para registrar exportaciones.' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'La solicitud no es válida.' using errcode = '22023'; end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['order_id','destination_country_code','export_date','lines']) then raise exception 'Campo no permitido: %.', v_key using errcode = '22023'; end if;
  end loop;
  if jsonb_typeof(p->'order_id') is distinct from 'number' or (p->>'order_id') !~ '^[1-9][0-9]*$' then raise exception 'El pedido no es válido.' using errcode = '22023'; end if;
  v_order_id := (p->>'order_id')::bigint;
  v_country := upper(btrim(coalesce(p->>'destination_country_code','')));
  if v_country !~ '^[A-Z]{2}$' then raise exception 'Indica el país de destino con código ISO de dos letras.' using errcode = '22023'; end if;
  begin v_date := coalesce((p->>'export_date')::date, current_date); exception when others then raise exception 'La fecha de exportación no es válida.' using errcode = '22023'; end;
  if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines') not between 1 and 100 then raise exception 'Agrega entre 1 y 100 líneas.' using errcode = '22023'; end if;
  perform 1 from public.customer_order where id = v_order_id and status = 'confirmed' for update;
  if not found then raise exception 'El pedido no existe o no está confirmado.' using errcode = 'P0002'; end if;
  v_profile_id := public.current_profile_id();
  insert into public.export(order_id,destination_country_code,export_date,created_by_id)
  values(v_order_id,v_country,v_date,v_profile_id) returning id into v_export_id;
  for v_line in select value from jsonb_array_elements(p->'lines') loop
    if jsonb_typeof(v_line) <> 'object' or (v_line->>'order_line_id') !~ '^[1-9][0-9]*$' or jsonb_typeof(v_line->'quantity') is distinct from 'number' then raise exception 'Cada línea requiere order_line_id y quantity válidos.' using errcode = '22023'; end if;
    select * into v_order_line from public.order_line where id = (v_line->>'order_line_id')::bigint and order_id = v_order_id for update;
    if not found then raise exception 'La línea no pertenece al pedido.' using errcode = '22023'; end if;
    v_quantity := (v_line->>'quantity')::numeric;
    if v_quantity <= 0 then raise exception 'La cantidad exportada debe ser positiva.' using errcode = '22023'; end if;
    select coalesce(sum(el.quantity),0) into v_allocated from public.export_line el join public.export e on e.id=el.export_id where el.order_line_id=v_order_line.id and e.status <> 'cancelled';
    if v_allocated + v_quantity > v_order_line.quantity then raise exception 'La cantidad supera el saldo disponible de la línea del pedido.' using errcode = '23514'; end if;
    insert into public.export_line(export_id,order_line_id,product_lot_id,quantity,hs_code_snapshot)
    values(v_export_id,v_order_line.id,v_order_line.product_lot_id,v_quantity,v_order_line.hs_code_snapshot);
  end loop;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata)
  values(v_profile_id,'customer_export.created','export',v_export_id,jsonb_build_object('order_id',v_order_id,'line_count',jsonb_array_length(p->'lines')));
  return jsonb_build_object('id',v_export_id,'order_id',v_order_id,'status','draft','destination_country_code',v_country,'export_date',v_date);
end $$;
revoke all on function public.create_customer_export(jsonb) from public, anon;
grant execute on function public.create_customer_export(jsonb) to authenticated;

-- RLS y privilegios: denegar por defecto y sin borrado de cabeceras/libros.
alter table public.export enable row level security;
alter table public.export_line enable row level security;
alter table public.shipment enable row level security;
alter table public.shipment_event enable row level security;
alter table public.stored_file enable row level security;
alter table public.export_document enable row level security;
alter table public.notification enable row level security;
alter table public.payment_obligation enable row level security;
alter table public.payment_transaction enable row level security;
alter table public.exchange_rate enable row level security;

drop policy if exists export_select on public.export;
create policy export_select on public.export for select to authenticated using (public.has_permission('exports.read'));
drop policy if exists export_insert on public.export;
create policy export_insert on public.export for insert to authenticated with check (public.has_permission('exports.create'));
drop policy if exists export_update on public.export;
create policy export_update on public.export for update to authenticated using (public.has_permission('exports.update')) with check (public.has_permission('exports.update'));
drop policy if exists export_line_select on public.export_line;
create policy export_line_select on public.export_line for select to authenticated using (public.has_permission('exports.read'));
drop policy if exists export_line_insert on public.export_line;
create policy export_line_insert on public.export_line for insert to authenticated with check (public.has_permission('exports.create') or public.has_permission('exports.update'));
drop policy if exists export_line_update on public.export_line;
create policy export_line_update on public.export_line for update to authenticated using (public.has_permission('exports.update')) with check (public.has_permission('exports.update'));
drop policy if exists export_line_delete on public.export_line;
create policy export_line_delete on public.export_line for delete to authenticated using (public.has_permission('exports.update'));

drop policy if exists shipment_select on public.shipment;
create policy shipment_select on public.shipment for select to authenticated using (public.has_permission('logistics.read'));
drop policy if exists shipment_insert on public.shipment;
create policy shipment_insert on public.shipment for insert to authenticated with check (public.has_permission('logistics.create') and created_by_id=public.current_profile_id());
drop policy if exists shipment_update on public.shipment;
create policy shipment_update on public.shipment for update to authenticated using (public.has_permission('logistics.update')) with check (public.has_permission('logistics.update'));
drop policy if exists shipment_event_select on public.shipment_event;
create policy shipment_event_select on public.shipment_event for select to authenticated using (public.has_permission('logistics.read'));
drop policy if exists shipment_event_insert on public.shipment_event;
create policy shipment_event_insert on public.shipment_event for insert to authenticated with check (public.has_permission('logistics.update') and recorded_by_id = public.current_profile_id());

drop policy if exists export_document_select on public.export_document;
create policy export_document_select on public.export_document for select to authenticated using (public.has_permission('documents.read'));
drop policy if exists export_document_insert on public.export_document;
create policy export_document_insert on public.export_document for insert to authenticated with check ((public.has_permission('documents.upload') or public.has_permission('documents.generate')) and created_by_id = public.current_profile_id());
drop policy if exists stored_file_select on public.stored_file;
create policy stored_file_select on public.stored_file for select to authenticated using (uploaded_by_id = public.current_profile_id() or public.has_permission('documents.read'));
drop policy if exists stored_file_insert on public.stored_file;
create policy stored_file_insert on public.stored_file for insert to authenticated with check ((public.has_permission('documents.upload') or public.has_permission('documents.generate')) and uploaded_by_id = public.current_profile_id());

drop policy if exists notification_select on public.notification;
create policy notification_select on public.notification for select to authenticated using (recipient_user_id = public.current_profile_id());
drop policy if exists notification_update on public.notification;
create policy notification_update on public.notification for update to authenticated using (recipient_user_id = public.current_profile_id()) with check (recipient_user_id = public.current_profile_id());

drop policy if exists payment_obligation_select on public.payment_obligation;
create policy payment_obligation_select on public.payment_obligation for select to authenticated using (public.has_permission('payments.read'));
drop policy if exists payment_obligation_insert on public.payment_obligation;
create policy payment_obligation_insert on public.payment_obligation for insert to authenticated with check (public.has_permission('payments.create') and created_by_id=public.current_profile_id());
drop policy if exists payment_transaction_select on public.payment_transaction;
create policy payment_transaction_select on public.payment_transaction for select to authenticated using (public.has_permission('payments.read'));
drop policy if exists payment_transaction_insert on public.payment_transaction;
create policy payment_transaction_insert on public.payment_transaction for insert to authenticated with check (public.has_permission('payments.create') and recorded_by_id=public.current_profile_id());
drop policy if exists exchange_rate_select on public.exchange_rate;
create policy exchange_rate_select on public.exchange_rate for select to authenticated using (public.has_permission('payments.read'));

revoke all on public.export,public.export_line,public.shipment,public.shipment_event,public.stored_file,public.export_document,public.notification,public.payment_obligation,public.payment_transaction,public.exchange_rate from public,anon,authenticated;
grant select,insert,update on public.export to authenticated;
grant select,insert,update,delete on public.export_line to authenticated;
grant select,insert,update on public.shipment to authenticated;
grant select,insert on public.shipment_event to authenticated;
grant select,insert on public.stored_file,public.export_document to authenticated;
grant select on public.notification to authenticated;
grant update(read_at) on public.notification to authenticated;
grant select,insert on public.payment_obligation,public.payment_transaction to authenticated;
grant select on public.exchange_rate to authenticated;
grant all on public.exchange_rate to service_role;
revoke delete,truncate,references,trigger on public.export,public.shipment,public.shipment_event,public.stored_file,public.export_document,public.notification from authenticated;
revoke truncate,references,trigger on public.export_line from authenticated;
revoke update,delete on public.shipment_event,public.stored_file,public.export_document,public.notification from authenticated;
revoke update,delete,truncate,references,trigger on public.payment_obligation,public.payment_transaction,public.exchange_rate from authenticated;
revoke truncate,references,trigger on public.payment_obligation,public.payment_transaction,public.exchange_rate from service_role;
grant usage,select on sequence public.payment_obligation_id_seq,public.payment_transaction_id_seq,public.exchange_rate_id_seq to authenticated,service_role;

create or replace view public.customer_order_history with (security_barrier=true) as
select o.customer_id,o.id as order_id,o.order_number,o.status,o.currency_code,o.created_at,
       coalesce((select sum(l.quantity*l.unit_price) from public.order_line l where l.order_id=o.id),0)::numeric(18,2) as order_total,
       (select count(*) from public.export e where e.order_id=o.id and e.status <> 'cancelled')::integer as export_count,
       (select max(e.export_date) from public.export e where e.order_id=o.id and e.status <> 'cancelled') as last_export_date
from public.customer_order o
where public.has_permission('customers.read') and public.has_permission('orders.read');

create or replace view public.customer_export_history with (security_barrier=true) as
select o.customer_id,e.id as export_id,e.order_id,o.order_number,e.destination_country_code,e.export_date,e.status
from public.export e join public.customer_order o on o.id=e.order_id
where e.status <> 'cancelled' and public.has_permission('customers.read') and public.has_permission('orders.read') and public.has_permission('exports.read');

create or replace view public.export_traceability with (security_barrier=true) as
select el.export_id,el.id as export_line_id,el.order_line_id,el.quantity,el.hs_code_snapshot,
       l.id as lot_id,l.lot_code,p.id as product_id,p.type as product_type,p.variety as product_variety,p.quality_grade as product_quality,
       f.id as farm_id,f.name as farm_name,f.country_code,f.latitude,f.longitude,s.id as supplier_id,s.business_name as supplier_name
from public.export_line el join public.product_lot l on l.id=el.product_lot_id
join public.product p on p.id=l.product_id join public.farm f on f.id=l.farm_id join public.supplier s on s.id=f.supplier_id
join public.export e on e.id=el.export_id
where e.status <> 'cancelled' and public.has_permission('exports.read') and public.has_permission('farms.read');

create or replace view public.export_origin_farms with (security_barrier=true) as
select t.export_id,t.farm_id,t.farm_name,t.country_code,t.latitude,t.longitude,t.supplier_id,t.supplier_name,
       sum(t.quantity)::numeric(18,3) as total_quantity,count(distinct t.lot_id)::integer as lot_count
from public.export_traceability t
group by t.export_id,t.farm_id,t.farm_name,t.country_code,t.latitude,t.longitude,t.supplier_id,t.supplier_name;

create or replace view public.shipment_origin_farms with (security_barrier=true) as
select sh.id as shipment_id,sh.export_id,o.farm_id,o.farm_name,o.country_code,o.latitude,o.longitude,o.supplier_id,o.supplier_name,o.total_quantity,o.lot_count
from public.shipment sh join public.export_origin_farms o on o.export_id=sh.export_id
where public.has_permission('logistics.read') and public.has_permission('exports.read') and public.has_permission('farms.read');

create or replace view public.export_catalog with (security_barrier=true) as
select e.id,e.order_id,o.order_number,o.customer_id,c.name as customer_name,
       e.destination_country_code,e.export_date,e.status,e.created_at,
       coalesce(lines.line_count,0)::integer as line_count,
       coalesce(lines.total_quantity,0)::numeric(18,3) as total_quantity,
       coalesce(shipments.shipment_count,0)::integer as shipment_count
from public.export e join public.customer_order o on o.id=e.order_id
join public.customer c on c.id=o.customer_id
left join lateral (select count(*) as line_count,sum(el.quantity) as total_quantity from public.export_line el where el.export_id=e.id) lines on true
left join lateral (select count(*) as shipment_count from public.shipment sh where sh.export_id=e.id) shipments on true
where public.has_permission('exports.read');

create or replace view public.shipment_catalog with (security_barrier=true) as
select sh.id,sh.export_id,e.order_id,o.order_number,o.customer_id,c.name as customer_name,
       sh.carrier,sh.tracking_number,sh.status,sh.shipped_at,sh.estimated_delivery_at,
       sh.delivered_at,sh.created_at
from public.shipment sh join public.export e on e.id=sh.export_id
join public.customer_order o on o.id=e.order_id join public.customer c on c.id=o.customer_id
where public.has_permission('logistics.read');

revoke all on public.customer_order_history,public.customer_export_history,public.export_traceability,public.export_origin_farms,public.shipment_origin_farms,public.export_catalog,public.shipment_catalog from public,anon,authenticated;
grant select on public.customer_order_history,public.customer_export_history,public.export_traceability,public.export_origin_farms,public.shipment_origin_farms,public.export_catalog,public.shipment_catalog to authenticated;

-- Aislamiento de lectura del portal: la vinculación N:M ya vive en customer_user.
create or replace function public.my_customer_ids() returns setof bigint language sql stable security definer set search_path=public as $$
  select cu.customer_id from public.customer_user cu where cu.profile_id=public.current_profile_id();
$$;
create or replace function public.my_order_ids() returns setof bigint language sql stable security definer set search_path=public as $$
  select o.id from public.customer_order o where o.customer_id in (select public.my_customer_ids());
$$;
create or replace function public.my_export_ids() returns setof bigint language sql stable security definer set search_path=public as $$
  select e.id from public.export e where e.order_id in (select public.my_order_ids()) and e.status <> 'cancelled';
$$;
create or replace function public.my_shipment_ids() returns setof bigint language sql stable security definer set search_path=public as $$
  select sh.id from public.shipment sh where sh.export_id in (select public.my_export_ids());
$$;
revoke all on function public.my_customer_ids(),public.my_order_ids(),public.my_export_ids(),public.my_shipment_ids() from public,anon;
grant execute on function public.my_customer_ids(),public.my_order_ids(),public.my_export_ids(),public.my_shipment_ids() to authenticated;

drop policy if exists customer_select_own on public.customer;
create policy customer_select_own on public.customer for select to authenticated using (public.has_permission('portal.read') and id in (select public.my_customer_ids()));
drop policy if exists customer_order_select_own on public.customer_order;
create policy customer_order_select_own on public.customer_order for select to authenticated using (public.has_permission('portal.read') and customer_id in (select public.my_customer_ids()));
drop policy if exists order_line_select_own on public.order_line;
create policy order_line_select_own on public.order_line for select to authenticated using (public.has_permission('portal.read') and order_id in (select public.my_order_ids()));
drop policy if exists export_select_own on public.export;
create policy export_select_own on public.export for select to authenticated using (public.has_permission('portal.read') and id in (select public.my_export_ids()));
drop policy if exists export_line_select_own on public.export_line;
create policy export_line_select_own on public.export_line for select to authenticated using (public.has_permission('portal.read') and export_id in (select public.my_export_ids()));
drop policy if exists export_document_select_own on public.export_document;
create policy export_document_select_own on public.export_document for select to authenticated using (public.has_permission('portal.read') and export_id in (select public.my_export_ids()));
drop policy if exists shipment_select_own on public.shipment;
create policy shipment_select_own on public.shipment for select to authenticated using (public.has_permission('portal.read') and id in (select public.my_shipment_ids()));
drop policy if exists shipment_event_select_own on public.shipment_event;
create policy shipment_event_select_own on public.shipment_event for select to authenticated using (public.has_permission('portal.read') and shipment_id in (select public.my_shipment_ids()));

-- Storage: paths use <export_id>/<uuid>_<filename>; never public URLs.
drop policy if exists export_documents_select on storage.objects;
create policy export_documents_select on storage.objects for select to authenticated using (
  bucket_id='export-documents' and exists(
    select 1 from public.stored_file sf join public.export_document d on d.stored_file_id=sf.id
    where sf.bucket_id=storage.objects.bucket_id and sf.object_path=storage.objects.name
      and (public.has_permission('documents.read') or (public.has_permission('portal.read') and d.export_id in (select public.my_export_ids())))
  )
);
drop policy if exists export_documents_insert on storage.objects;
create policy export_documents_insert on storage.objects for insert to authenticated with check (
  bucket_id='export-documents' and (public.has_permission('documents.upload') or public.has_permission('documents.generate'))
  and (storage.foldername(name))[1] ~ '^[1-9][0-9]*$'
  and exists(select 1 from public.export e where e.id=((storage.foldername(name))[1])::bigint and public.has_permission('exports.read'))
);
-- El esquema financiero anterior es una base técnica mínima, no define facturación,
-- conciliación bancaria ni conversión automática; esas reglas requieren validación.
