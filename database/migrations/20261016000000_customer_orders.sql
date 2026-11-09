-- Pedidos comerciales (PLAT-540/541). Una cabecera por cliente y una o mas
-- lineas vinculadas a lotes para conservar la trazabilidad del producto.

create table if not exists public.customer_order (
  id bigint generated always as identity primary key,
  customer_id bigint not null references public.customer(id),
  order_number text not null unique,
  status text not null default 'draft'
    check (status in ('draft', 'confirmed', 'cancelled')),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  note text check (char_length(note) <= 1000),
  created_by_id bigint references public.profile(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists customer_order_customer_idx
  on public.customer_order(customer_id, created_at desc);

create table if not exists public.order_line (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.customer_order(id),
  product_lot_id bigint not null references public.product_lot(id),
  quantity numeric(18,3) not null check (quantity > 0),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  hs_code_snapshot text check (hs_code_snapshot is null or hs_code_snapshot ~ '^[0-9]{4}(\.[0-9]{2}){0,3}$'),
  created_at timestamptz not null default now()
);
create index if not exists order_line_order_idx on public.order_line(order_id);
create index if not exists order_line_lot_idx on public.order_line(product_lot_id);

create table if not exists public.inventory_movement (
  id bigint generated always as identity primary key,
  product_lot_id bigint not null references public.product_lot(id),
  quantity_delta numeric(18,3) not null check (quantity_delta <> 0),
  movement_type text not null check (movement_type in ('adjustment', 'order')),
  order_id bigint references public.customer_order(id),
  performed_by_id bigint references public.profile(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint inventory_movement_order_shape check
    ((movement_type = 'order' and order_id is not null and quantity_delta < 0)
      or (movement_type = 'adjustment' and order_id is null))
);
create index if not exists inventory_movement_lot_idx
  on public.inventory_movement(product_lot_id, created_at);
create unique index if not exists inventory_movement_order_lot_uq
  on public.inventory_movement(order_id, product_lot_id) where movement_type = 'order';

create or replace view public.lot_inventory_availability
with (security_invoker = true) as
select l.id as product_lot_id,
       coalesce(sum(m.quantity_delta), 0)::numeric(18,3) as available_quantity
from public.product_lot l
left join public.inventory_movement m on m.product_lot_id = l.id
group by l.id;

create or replace function public.assign_customer_order_number()
returns trigger language plpgsql set search_path = public
as $$
begin
  if new.order_number is null then
    new.order_number := 'PED-' || to_char(current_date, 'YYYY') || '-' || lpad(new.id::text, 6, '0');
  end if;
  return new;
end;
$$;
revoke all on function public.assign_customer_order_number() from public, anon, authenticated;
drop trigger if exists customer_order_number on public.customer_order;
create trigger customer_order_number
  before insert on public.customer_order
  for each row execute function public.assign_customer_order_number();

alter table public.customer_order enable row level security;
alter table public.order_line enable row level security;
alter table public.inventory_movement enable row level security;
drop policy if exists customer_order_select on public.customer_order;
create policy customer_order_select on public.customer_order
  for select to authenticated using (public.has_permission('orders.read'));
drop policy if exists order_line_select on public.order_line;
create policy order_line_select on public.order_line
  for select to authenticated using (public.has_permission('orders.read'));
drop policy if exists inventory_movement_select on public.inventory_movement;
create policy inventory_movement_select on public.inventory_movement
  for select to authenticated using (public.has_permission('inventory.read'));
revoke all on public.customer_order, public.order_line from public, anon, authenticated;
grant select on public.customer_order, public.order_line to authenticated;
revoke all on public.inventory_movement, public.lot_inventory_availability from public, anon, authenticated;
grant select on public.inventory_movement, public.lot_inventory_availability to authenticated;

insert into public.permission(code, description) values
  ('orders.read', 'Consultar pedidos.'),
  ('orders.create', 'Registrar pedidos.'),
  ('inventory.read', 'Consultar inventario y sus movimientos.'),
  ('inventory.adjust', 'Registrar ajustes manuales de inventario.')
on conflict (code) do nothing;

create or replace function public._customer_order_audit(p_order_id bigint, p_meta jsonb)
returns void language sql security definer set search_path = public
as $$
  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values ((select id from public.profile where auth_user_id = auth.uid()),
          'customer_order.created', 'customer_order', p_order_id, p_meta);
$$;
revoke all on function public._customer_order_audit(bigint, jsonb) from public, anon, authenticated;

create or replace function public.create_customer_order(p jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_customer_id bigint;
  v_customer public.customer;
  v_order_id bigint;
  v_order_number text;
  v_created_by bigint;
  v_line jsonb;
  v_key text;
  v_lot_id bigint;
  v_quantity numeric(18,3);
  v_price numeric(18,2);
  v_hs_code text;
  v_lines jsonb;
  v_note text;
  v_available numeric(18,3);
begin
  if not public.has_permission('orders.create') then
    raise exception 'No tienes permiso para esta operacion.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es valida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['customer_id', 'note', 'lines']) then
      raise exception 'Campo no permitido en el pedido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'customer_id') is distinct from 'number' then
    raise exception 'Selecciona un cliente.' using errcode = '22023';
  end if;
  begin
    v_customer_id := (p->>'customer_id')::bigint;
  exception when others then
    raise exception 'El cliente seleccionado no es valido.' using errcode = '22023';
  end;
  select * into v_customer from public.customer
   where id = v_customer_id and is_active;
  if not found then
    raise exception 'El cliente no existe o esta inactivo.' using errcode = 'P0002';
  end if;
  v_lines := p->'lines';
  if jsonb_typeof(v_lines) is distinct from 'array' or
     jsonb_array_length(v_lines) not between 1 and 50 then
    raise exception 'El pedido debe tener entre 1 y 50 lineas.' using errcode = '22023';
  end if;
  v_note := nullif(btrim(p->>'note'), '');
  if p ? 'note' and p->'note' <> 'null'::jsonb and jsonb_typeof(p->'note') is distinct from 'string' then
    raise exception 'La nota debe ser texto.' using errcode = '22023';
  end if;
  if char_length(v_note) > 1000 then
    raise exception 'La nota admite hasta 1000 caracteres.' using errcode = '22023';
  end if;

  v_created_by := (select id from public.profile where auth_user_id = auth.uid());
  insert into public.customer_order(customer_id, currency_code, note, created_by_id)
  values (v_customer_id, v_customer.preferred_currency_code, v_note, v_created_by)
  returning id, order_number into v_order_id, v_order_number;

  for v_line in select value from jsonb_array_elements(v_lines) loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Cada linea debe ser un objeto.' using errcode = '22023';
    end if;
    for v_key in select jsonb_object_keys(v_line) loop
      if v_key <> all(array['product_lot_id', 'quantity', 'unit_price']) then
        raise exception 'Campo no permitido en una linea: %.', v_key using errcode = '22023';
      end if;
    end loop;
    if jsonb_typeof(v_line->'product_lot_id') is distinct from 'number' or
       (v_line->>'product_lot_id') !~ '^[1-9][0-9]*$' or
       jsonb_typeof(v_line->'quantity') is distinct from 'number' or
       jsonb_typeof(v_line->'unit_price') is distinct from 'number' then
      raise exception 'Lote, cantidad y precio deben tener un formato numerico valido.' using errcode = '22023';
    end if;
    begin
      v_lot_id := (v_line->>'product_lot_id')::bigint;
      v_quantity := (v_line->>'quantity')::numeric;
      v_price := (v_line->>'unit_price')::numeric;
    exception when others then
      raise exception 'Lote, cantidad o precio no valido.' using errcode = '22023';
    end;
    if v_lot_id <= 0 or v_quantity <= 0 or v_quantity > 999999999999999.999 or
       v_price < 0 or v_price > 9999999999999999.99 then
      raise exception 'La cantidad debe ser positiva y el precio no puede ser negativo.' using errcode = '22023';
    end if;
    perform 1 from public.product_lot where id = v_lot_id for update;
    select pr.hs_code into v_hs_code
      from public.product_lot l
      join public.product pr on pr.id = l.product_id and pr.is_active
      join public.farm f on f.id = l.farm_id and f.is_active
     where l.id = v_lot_id;
    if not found then
      raise exception 'El lote no existe o su producto o finca esta inactivo.' using errcode = 'P0002';
    end if;
    select coalesce(sum(quantity_delta), 0) into v_available
      from public.inventory_movement where product_lot_id = v_lot_id;
    if v_quantity > v_available then
      raise exception 'Existencias insuficientes para el lote %. Disponibles: %, solicitadas: %.',
        v_lot_id, v_available, v_quantity using errcode = '23514';
    end if;
    insert into public.order_line(order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
    values (v_order_id, v_lot_id, v_quantity, v_price, v_customer.preferred_currency_code, v_hs_code);
    insert into public.inventory_movement(product_lot_id, quantity_delta, movement_type, order_id, performed_by_id)
    values (v_lot_id, -v_quantity, 'order', v_order_id, v_created_by);
  end loop;

  perform public._customer_order_audit(v_order_id,
    jsonb_build_object('customer_id', v_customer_id, 'line_count', jsonb_array_length(v_lines)));

  return jsonb_build_object(
    'id', v_order_id,
    'order_number', v_order_number,
    'customer_id', v_customer_id,
    'status', 'draft',
    'currency_code', v_customer.preferred_currency_code,
    'created_at', now()
  );
end;
$$;
revoke all on function public.create_customer_order(jsonb) from public, anon;
grant execute on function public.create_customer_order(jsonb) to authenticated;


create or replace function public.adjust_lot_inventory(p jsonb)
returns bigint language plpgsql security definer set search_path = public
as $$
declare
  v_lot_id bigint;
  v_delta numeric(18,3);
  v_profile_id bigint;
  v_movement_id bigint;
  v_key text;
begin
  if not public.has_permission('inventory.adjust') then
    raise exception 'No tienes permiso para ajustar inventario.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es valida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['product_lot_id', 'quantity_delta']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'product_lot_id') is distinct from 'number'
     or (p->>'product_lot_id') !~ '^[1-9][0-9]*$'
     or jsonb_typeof(p->'quantity_delta') is distinct from 'number' then
    raise exception 'Lote y cantidad deben ser numericos.' using errcode = '22023';
  end if;
  begin
    v_lot_id := (p->>'product_lot_id')::bigint;
    v_delta := (p->>'quantity_delta')::numeric;
  exception when others then
    raise exception 'Lote o cantidad no validos.' using errcode = '22023';
  end;
  if v_delta = 0 or abs(v_delta) > 999999999999999.999 then
    raise exception 'El ajuste debe ser distinto de cero y tener un valor valido.' using errcode = '22023';
  end if;
  perform 1 from public.product_lot where id = v_lot_id for update;
  if not found then raise exception 'El lote no existe.' using errcode = 'P0002'; end if;
  if (select coalesce(sum(quantity_delta), 0) from public.inventory_movement where product_lot_id = v_lot_id) + v_delta < 0 then
    raise exception 'El ajuste no puede dejar existencias negativas.' using errcode = '23514';
  end if;
  v_profile_id := (select id from public.profile where auth_user_id = auth.uid());
  insert into public.inventory_movement(product_lot_id, quantity_delta, movement_type, performed_by_id)
  values (v_lot_id, v_delta, 'adjustment', v_profile_id) returning id into v_movement_id;
  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (v_profile_id, 'inventory.adjusted', 'product_lot', v_lot_id,
          jsonb_build_object('movement_id', v_movement_id, 'quantity_delta', v_delta));
  return v_movement_id;
end;
$$;
revoke all on function public.adjust_lot_inventory(jsonb) from public, anon;
grant execute on function public.adjust_lot_inventory(jsonb) to authenticated;
