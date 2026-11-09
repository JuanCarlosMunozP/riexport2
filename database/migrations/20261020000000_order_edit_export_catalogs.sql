-- PLAT-556/557: la edicion solo se permite mientras el pedido siga en borrador.
-- PLAT-561-565: catalogos y registro transaccional de exportaciones.

alter table public.customer_order
  add column if not exists updated_at timestamptz not null default now();

insert into public.permission(code, description) values
  ('orders.update', 'Editar pedidos en borrador.')
on conflict (code) do nothing;

insert into public.role_permission(role_id, permission_code)
select r.id, p.code
from public.role r
cross join public.permission p
where r.name in ('administrador', 'usuario_comercial')
  and p.code in (
    'orders.read','orders.create','orders.update','orders.transition',
    'exports.read','exports.create'
  )
on conflict do nothing;

create table if not exists public.export_destination (
  code text primary key check (code ~ '^[A-Z]{2}$'),
  name text not null unique,
  is_active boolean not null default true
);

insert into public.export_destination(code, name) values
  ('AR','Argentina'),('AU','Australia'),('AT','Austria'),('BE','Bélgica'),
  ('BO','Bolivia'),('BR','Brasil'),('CA','Canadá'),('CL','Chile'),
  ('CN','China'),('CO','Colombia'),('CR','Costa Rica'),('CZ','Chequia'),
  ('DK','Dinamarca'),('EC','Ecuador'),('EG','Egipto'),('SV','El Salvador'),
  ('AE','Emiratos Árabes Unidos'),('SK','Eslovaquia'),('SI','Eslovenia'),
  ('ES','España'),('US','Estados Unidos'),('EE','Estonia'),('FI','Finlandia'),
  ('FR','Francia'),('DE','Alemania'),('GR','Grecia'),('GT','Guatemala'),
  ('HN','Honduras'),('HK','Hong Kong'),('HU','Hungría'),('IN','India'),
  ('ID','Indonesia'),('IE','Irlanda'),('IS','Islandia'),('IL','Israel'),
  ('IT','Italia'),('JP','Japón'),('KR','Corea del Sur'),('LV','Letonia'),
  ('LT','Lituania'),('LU','Luxemburgo'),('MY','Malasia'),('MT','Malta'),
  ('MA','Marruecos'),('MX','México'),('NI','Nicaragua'),('NO','Noruega'),
  ('NZ','Nueva Zelanda'),('NL','Países Bajos'),('PA','Panamá'),('PY','Paraguay'),
  ('PE','Perú'),('PL','Polonia'),('PT','Portugal'),('GB','Reino Unido'),
  ('DO','República Dominicana'),('RO','Rumanía'),('SG','Singapur'),
  ('ZA','Sudáfrica'),('SE','Suecia'),('CH','Suiza'),('TH','Tailandia'),
  ('TW','Taiwán'),('TR','Turquía'),('UA','Ucrania'),('UY','Uruguay'),
  ('VN','Vietnam')
on conflict (code) do update set name = excluded.name;

create table if not exists public.incoterm (
  code text primary key check (code in
    ('EXW','FCA','CPT','CIP','DAP','DPU','DDP','FAS','FOB','CFR','CIF')),
  name text not null,
  is_active boolean not null default true
);

insert into public.incoterm(code, name) values
  ('EXW','En fábrica'),('FCA','Franco transportista'),
  ('CPT','Transporte pagado hasta'),('CIP','Transporte y seguro pagados hasta'),
  ('DAP','Entregada en lugar'),('DPU','Entregada en lugar descargada'),
  ('DDP','Entregada derechos pagados'),('FAS','Franco al costado del buque'),
  ('FOB','Franco a bordo'),('CFR','Coste y flete'),
  ('CIF','Coste, seguro y flete')
on conflict (code) do update set name = excluded.name;

alter table public.export
  add column if not exists incoterm_code text references public.incoterm(code);
alter table public.export
  drop constraint if exists export_destination_country_code_fkey;
insert into public.export_destination(code, name)
select distinct destination_country_code, destination_country_code
from public.export
where destination_country_code ~ '^[A-Z]{2}$'
on conflict (code) do nothing;
alter table public.export
  add constraint export_destination_country_code_fkey
  foreign key (destination_country_code) references public.export_destination(code);

alter table public.inventory_movement
  drop constraint if exists inventory_movement_order_shape;
alter table public.inventory_movement
  add constraint inventory_movement_order_shape check
    ((movement_type = 'order' and order_id is not null and quantity_delta < 0)
      or (movement_type = 'order_cancel' and order_id is not null and quantity_delta > 0)
      or (movement_type = 'order_edit' and order_id is not null)
      or (movement_type = 'adjustment' and order_id is null));
alter table public.inventory_movement
  drop constraint if exists inventory_movement_movement_type_check;
alter table public.inventory_movement
  add constraint inventory_movement_movement_type_check
  check (movement_type in ('adjustment', 'order', 'order_cancel', 'order_edit'));

create or replace function public.update_customer_order(p jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_order_id bigint;
  v_order public.customer_order;
  v_customer public.customer;
  v_line jsonb;
  v_lot_id bigint;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
  v_hs_code text;
  v_old_quantity numeric(18,3);
  v_new_quantity numeric(18,3);
  v_available numeric(18,3);
  v_note text;
  v_key text;
  v_profile_id bigint;
begin
  if not public.has_permission('orders.update') or not public.has_permission('orders.read') then
    raise exception 'No tienes permiso para editar pedidos.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['order_id','customer_id','note','lines']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'order_id') is distinct from 'number'
     or (p->>'order_id') !~ '^[1-9][0-9]*$'
     or jsonb_typeof(p->'customer_id') is distinct from 'number'
     or (p->>'customer_id') !~ '^[1-9][0-9]*$' then
    raise exception 'Pedido, cliente o líneas no válidos.' using errcode = '22023';
  end if;
  if jsonb_typeof(p->'lines') is distinct from 'array' then
    raise exception 'Las líneas del pedido deben ser una lista.' using errcode = '22023';
  end if;
  if jsonb_array_length(p->'lines') not between 1 and 50 then
    raise exception 'Agrega entre 1 y 50 líneas.' using errcode = '22023';
  end if;
  begin
    v_order_id := (p->>'order_id')::bigint;
  exception when others then
    raise exception 'El pedido no es válido.' using errcode = '22023';
  end;
  select * into v_order from public.customer_order where id = v_order_id for update;
  if not found then raise exception 'El pedido no existe.' using errcode = 'P0002'; end if;
  if v_order.status <> 'draft' then
    raise exception 'Solo se pueden editar pedidos en borrador.' using errcode = 'P0001';
  end if;
  begin
    select * into v_customer from public.customer
      where id = (p->>'customer_id')::bigint and is_active for share;
  exception when others then
    raise exception 'El cliente seleccionado no es válido.' using errcode = '22023';
  end;
  if not found then raise exception 'El cliente no existe o está inactivo.' using errcode = 'P0002'; end if;
  if p ? 'note' and p->'note' <> 'null'::jsonb and jsonb_typeof(p->'note') is distinct from 'string' then
    raise exception 'La nota debe ser texto.' using errcode = '22023';
  end if;
  v_note := nullif(btrim(p->>'note'), '');
  if char_length(v_note) > 1000 then raise exception 'La nota admite hasta 1000 caracteres.' using errcode = '22023'; end if;

  for v_line in select value from jsonb_array_elements(p->'lines') loop
    if jsonb_typeof(v_line) <> 'object' then raise exception 'Cada línea debe ser un objeto.' using errcode = '22023'; end if;
    for v_key in select jsonb_object_keys(v_line) loop
      if v_key <> all(array['product_lot_id','quantity','unit_price']) then raise exception 'Campo no permitido en una línea: %.', v_key using errcode = '22023'; end if;
    end loop;
    if jsonb_typeof(v_line->'product_lot_id') is distinct from 'number'
       or (v_line->>'product_lot_id') !~ '^[1-9][0-9]*$'
       or jsonb_typeof(v_line->'quantity') is distinct from 'number'
       or jsonb_typeof(v_line->'unit_price') is distinct from 'number' then
      raise exception 'Lote, cantidad y precio no válidos.' using errcode = '22023';
    end if;
    begin
      v_lot_id := (v_line->>'product_lot_id')::bigint;
      v_quantity := (v_line->>'quantity')::numeric;
      v_price := (v_line->>'unit_price')::numeric;
    exception when others then raise exception 'Lote, cantidad o precio no válidos.' using errcode = '22023';
    end;
    if v_quantity <= 0 or v_price < 0
       or v_quantity <> (v_line->>'quantity')::numeric
       or v_price <> (v_line->>'unit_price')::numeric then
      raise exception 'La cantidad debe ser positiva y el precio no puede ser negativo con máximo 3 y 2 decimales.' using errcode = '22023';
    end if;
    select pr.hs_code into v_hs_code
      from public.product_lot l
      join public.product pr on pr.id = l.product_id and pr.is_active
      join public.farm f on f.id = l.farm_id and f.is_active
     where l.id = v_lot_id;
    if not found then raise exception 'El lote no existe o su producto o finca está inactivo.' using errcode = 'P0002'; end if;
  end loop;

  perform l.id
    from public.product_lot l
   where l.id in (
     select product_lot_id from public.order_line where order_id=v_order_id
     union
     select (value->>'product_lot_id')::bigint from jsonb_array_elements(p->'lines')
   )
   order by l.id
   for update;

  for v_lot_id in
    select distinct lot_id from (
      select product_lot_id as lot_id from public.order_line where order_id = v_order_id
      union
      select (value->>'product_lot_id')::bigint from jsonb_array_elements(p->'lines')
    ) lots order by lot_id
  loop
    select coalesce(sum(quantity),0) into v_old_quantity
      from public.order_line where order_id = v_order_id and product_lot_id = v_lot_id;
    select coalesce(sum((value->>'quantity')::numeric),0) into v_new_quantity
      from jsonb_array_elements(p->'lines') where (value->>'product_lot_id')::bigint = v_lot_id;
    if v_new_quantity > v_old_quantity then
      select coalesce(sum(quantity_delta),0) into v_available
        from public.inventory_movement where product_lot_id = v_lot_id;
      if v_new_quantity - v_old_quantity > v_available then
        raise exception 'No hay existencias suficientes para el lote %.', v_lot_id using errcode = '23514';
      end if;
    end if;
    if v_old_quantity <> v_new_quantity then
      insert into public.inventory_movement(product_lot_id,quantity_delta,movement_type,order_id,performed_by_id)
      values(v_lot_id,v_old_quantity-v_new_quantity,'order_edit',v_order_id,public.current_profile_id());
    end if;
  end loop;

  delete from public.order_line where order_id = v_order_id;
  for v_line in select value from jsonb_array_elements(p->'lines') loop
    v_lot_id := (v_line->>'product_lot_id')::bigint;
    v_quantity := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    select pr.hs_code into v_hs_code from public.product_lot l join public.product pr on pr.id=l.product_id where l.id=v_lot_id;
    insert into public.order_line(order_id,product_lot_id,quantity,unit_price,currency_code,hs_code_snapshot)
    values(v_order_id,v_lot_id,v_quantity,v_price,v_customer.preferred_currency_code,v_hs_code);
  end loop;
  update public.customer_order
     set customer_id=v_customer.id,currency_code=v_customer.preferred_currency_code,note=v_note,updated_at=now()
   where id=v_order_id;
  v_profile_id := public.current_profile_id();
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata)
  values(v_profile_id,'customer_order.updated','customer_order',v_order_id,
         jsonb_build_object('customer_id',v_customer.id,'line_count',jsonb_array_length(p->'lines')));
  return jsonb_build_object('id',v_order.id,'order_number',v_order.order_number,'status','draft','updated_at',now());
end $$;
revoke all on function public.update_customer_order(jsonb) from public, anon;
grant execute on function public.update_customer_order(jsonb) to authenticated;

create or replace function public.create_customer_export(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_order_id bigint;
  v_export_id bigint;
  v_country text;
  v_incoterm text;
  v_date date;
  v_line jsonb;
  v_order_line_id bigint;
  v_order_line public.order_line;
  v_quantity numeric(18,3);
  v_allocated numeric(18,3);
  v_profile_id bigint;
  v_key text;
begin
  if not public.has_permission('exports.create') or not public.has_permission('orders.read') then raise exception 'No tienes permiso para registrar exportaciones.' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'La solicitud no es válida.' using errcode = '22023'; end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['order_id','destination_country_code','incoterm_code','export_date','lines']) then raise exception 'Campo no permitido: %.', v_key using errcode = '22023'; end if;
  end loop;
  if jsonb_typeof(p->'order_id') is distinct from 'number' or (p->>'order_id') !~ '^[1-9][0-9]*$' then raise exception 'El pedido no es válido.' using errcode = '22023'; end if;
  begin
    v_order_id := (p->>'order_id')::bigint;
  exception when others then
    raise exception 'El pedido no es válido.' using errcode = '22023';
  end;
  v_country := upper(btrim(coalesce(p->>'destination_country_code','')));
  if not exists(select 1 from public.export_destination where code=v_country and is_active) then raise exception 'Selecciona un país de destino válido.' using errcode = '22023'; end if;
  v_incoterm := nullif(upper(btrim(p->>'incoterm_code')), '');
  if v_incoterm is not null and not exists(select 1 from public.incoterm where code=v_incoterm and is_active) then raise exception 'Selecciona un Incoterm válido.' using errcode = '22023'; end if;
  begin v_date := coalesce((p->>'export_date')::date, current_date); exception when others then raise exception 'La fecha de exportación no es válida.' using errcode = '22023'; end;
  if jsonb_typeof(p->'lines') is distinct from 'array' then
    raise exception 'Las líneas de exportación deben ser una lista.' using errcode = '22023';
  end if;
  if jsonb_array_length(p->'lines') not between 1 and 100 then
    raise exception 'Agrega entre 1 y 100 líneas.' using errcode = '22023';
  end if;
  perform 1 from public.customer_order where id=v_order_id and status='confirmed' for update;
  if not found then raise exception 'El pedido no existe o no está confirmado.' using errcode = 'P0002'; end if;
  if (select count(*) from jsonb_array_elements(p->'lines')) <> (select count(distinct value->>'order_line_id') from jsonb_array_elements(p->'lines')) then
    raise exception 'No repitas líneas del pedido.' using errcode = '22023';
  end if;
  v_profile_id := public.current_profile_id();
  insert into public.export(order_id,destination_country_code,incoterm_code,export_date,created_by_id)
  values(v_order_id,v_country,v_incoterm,v_date,v_profile_id) returning id into v_export_id;
  for v_line in select value from jsonb_array_elements(p->'lines') loop
    if jsonb_typeof(v_line) <> 'object'
       or jsonb_typeof(v_line->'order_line_id') is distinct from 'number'
       or (v_line->>'order_line_id') !~ '^[1-9][0-9]*$'
       or jsonb_typeof(v_line->'quantity') is distinct from 'number' then
      raise exception 'Cada línea requiere order_line_id y quantity válidos.' using errcode = '22023';
    end if;
    for v_key in select jsonb_object_keys(v_line) loop
      if v_key <> all(array['order_line_id','quantity']) then
        raise exception 'Campo no permitido en una línea de exportación: %.', v_key using errcode = '22023';
      end if;
    end loop;
    begin
      v_order_line_id := (v_line->>'order_line_id')::bigint;
    exception when others then
      raise exception 'La línea del pedido no es válida.' using errcode = '22023';
    end;
    select * into v_order_line from public.order_line where id=v_order_line_id and order_id=v_order_id for update;
    if not found then raise exception 'La línea no pertenece al pedido.' using errcode = '22023'; end if;
    begin
      v_quantity := (v_line->>'quantity')::numeric;
    exception when others then
      raise exception 'La cantidad exportada no es válida.' using errcode = '22023';
    end;
    if v_quantity <= 0 or v_quantity <> (v_line->>'quantity')::numeric then
      raise exception 'La cantidad exportada debe ser positiva y admitir máximo 3 decimales.' using errcode = '22023';
    end if;
    select coalesce(sum(el.quantity),0) into v_allocated from public.export_line el join public.export e on e.id=el.export_id where el.order_line_id=v_order_line.id and e.status <> 'cancelled';
    if v_allocated + v_quantity > v_order_line.quantity then raise exception 'La cantidad supera el saldo disponible de la línea del pedido.' using errcode = '23514'; end if;
    insert into public.export_line(export_id,order_line_id,product_lot_id,quantity,hs_code_snapshot)
    values(v_export_id,v_order_line.id,v_order_line.product_lot_id,v_quantity,v_order_line.hs_code_snapshot);
  end loop;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata)
  values(v_profile_id,'customer_export.created','export',v_export_id,
         jsonb_build_object('order_id',v_order_id,'line_count',jsonb_array_length(p->'lines')));
  return jsonb_build_object('id',v_export_id,'order_id',v_order_id,'status','draft',
    'destination_country_code',v_country,'incoterm_code',v_incoterm,'export_date',v_date);
end $$;
revoke all on function public.create_customer_export(jsonb) from public, anon;
grant execute on function public.create_customer_export(jsonb) to authenticated;

create or replace function public.transition_customer_order(p jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_order_id bigint;
  v_target text;
  v_order public.customer_order;
  v_profile_id bigint;
  v_key text;
  v_movement record;
begin
  if not public.has_permission('orders.transition') then
    raise exception 'No tienes permiso para cambiar el estado de pedidos.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['order_id','status','note']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'order_id') is distinct from 'number'
     or (p->>'order_id') !~ '^[1-9][0-9]*$'
     or jsonb_typeof(p->'status') is distinct from 'string' then
    raise exception 'Pedido o estado no válidos.' using errcode = '22023';
  end if;
  v_order_id := (p->>'order_id')::bigint;
  v_target := p->>'status';
  if v_target not in ('confirmed','cancelled') then
    raise exception 'El estado solicitado no es válido.' using errcode = '22023';
  end if;
  if p ? 'note' and p->'note' <> 'null'::jsonb
     and jsonb_typeof(p->'note') is distinct from 'string' then
    raise exception 'La nota debe ser texto.' using errcode = '22023';
  end if;
  if char_length(coalesce(p->>'note','')) > 500 then
    raise exception 'La nota admite hasta 500 caracteres.' using errcode = '22023';
  end if;
  select * into v_order from public.customer_order where id=v_order_id for update;
  if not found then raise exception 'El pedido no existe.' using errcode = 'P0002'; end if;
  if v_order.status=v_target then raise exception 'El pedido ya tiene ese estado.' using errcode = 'P0001'; end if;
  if v_order.status='cancelled' or (v_order.status='confirmed' and v_target<>'cancelled') then
    raise exception 'La transición de estado no está permitida.' using errcode = 'P0001';
  end if;
  v_profile_id := (select id from public.profile where auth_user_id=auth.uid());
  if v_target='cancelled' then
    for v_movement in
      select product_lot_id, -sum(quantity_delta) as quantity_to_restore
      from public.inventory_movement
      where order_id=v_order_id and movement_type in ('order','order_edit')
      group by product_lot_id
      having sum(quantity_delta)<0
    loop
      insert into public.inventory_movement(
        product_lot_id,quantity_delta,movement_type,order_id,performed_by_id
      )
      values(
        v_movement.product_lot_id,v_movement.quantity_to_restore,
        'order_cancel',v_order_id,v_profile_id
      );
    end loop;
  end if;
  update public.customer_order set status=v_target,updated_at=now() where id=v_order_id;
  insert into public.order_status_history(order_id,from_status,to_status,changed_by_id,note)
  values(v_order_id,v_order.status,v_target,v_profile_id,nullif(btrim(p->>'note'),''));
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata)
  values(v_profile_id,'customer_order.status_changed','customer_order',v_order_id,
         jsonb_build_object('from_status',v_order.status,'to_status',v_target));
  return jsonb_build_object(
    'id',v_order_id,'order_number',v_order.order_number,
    'status',v_target,'updated_at',now()
  );
end $$;
revoke all on function public.transition_customer_order(jsonb) from public, anon;
grant execute on function public.transition_customer_order(jsonb) to authenticated;

drop policy if exists export_insert on public.export;
drop policy if exists export_line_insert on public.export_line;
revoke insert on public.export,public.export_line from authenticated;

alter table public.export_destination enable row level security;
alter table public.incoterm enable row level security;
drop policy if exists export_destination_select on public.export_destination;
create policy export_destination_select on public.export_destination for select to authenticated
  using (public.has_permission('exports.create') or public.has_permission('exports.read'));
drop policy if exists incoterm_select on public.incoterm;
create policy incoterm_select on public.incoterm for select to authenticated
  using (public.has_permission('exports.create') or public.has_permission('exports.read'));
revoke all on public.export_destination,public.incoterm from public,anon,authenticated;
grant select on public.export_destination,public.incoterm to authenticated;

create or replace view public.customer_order_details
with (security_barrier = true) as
select
  o.id,
  o.order_number,
  o.customer_id,
  c.name as customer_name,
  o.status,
  o.currency_code,
  o.note,
  o.created_at,
  count(ol.id)::integer as line_count,
  coalesce(sum(ol.quantity * ol.unit_price), 0)::numeric(18,2) as order_total,
  coalesce(
    jsonb_agg(jsonb_build_object(
      'id', ol.id,
      'order_line_id', ol.id,
      'product_lot_id', ol.product_lot_id,
      'lot_code', l.lot_code,
      'product_name', concat_ws(' ', p.type, p.variety, p.quality_grade),
      'quantity', ol.quantity,
      'unit_price', ol.unit_price,
      'line_total', (ol.quantity * ol.unit_price)::numeric(18,2),
      'remaining_quantity', greatest(ol.quantity - coalesce((
        select sum(el.quantity) from public.export_line el
        join public.export e on e.id=el.export_id
        where el.order_line_id=ol.id and e.status <> 'cancelled'
      ),0),0),
      'currency_code', ol.currency_code
    ) order by ol.id) filter (where ol.id is not null),
    '[]'::jsonb
  ) as lines,
  o.updated_at
from public.customer_order o
join public.customer c on c.id = o.customer_id
left join public.order_line ol on ol.order_id = o.id
left join public.product_lot l on l.id = ol.product_lot_id
left join public.product p on p.id = l.product_id
where public.has_permission('orders.read')
group by o.id, c.name;

create or replace view public.export_catalog with (security_barrier=true) as
select e.id,e.order_id,o.order_number,o.customer_id,c.name as customer_name,
       e.destination_country_code,e.export_date,e.status,e.created_at,
       coalesce(lines.line_count,0)::integer as line_count,
       coalesce(lines.total_quantity,0)::numeric(18,3) as total_quantity,
       coalesce(shipments.shipment_count,0)::integer as shipment_count,
       d.name as destination_country_name,e.incoterm_code,i.name as incoterm_name
from public.export e
join public.customer_order o on o.id=e.order_id
join public.customer c on c.id=o.customer_id
join public.export_destination d on d.code=e.destination_country_code
left join public.incoterm i on i.code=e.incoterm_code
left join lateral (select count(*) as line_count,sum(el.quantity) as total_quantity from public.export_line el where el.export_id=e.id) lines on true
left join lateral (select count(*) as shipment_count from public.shipment sh where sh.export_id=e.id) shipments on true
where public.has_permission('exports.read');

revoke all on public.export_catalog from public,anon,authenticated;
grant select on public.export_catalog to authenticated;
