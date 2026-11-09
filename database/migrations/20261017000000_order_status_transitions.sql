-- PLAT-547/548/549: historial de estado y transiciones controladas de pedidos.

create table if not exists public.order_status_history (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.customer_order(id),
  from_status text check (from_status in ('draft', 'confirmed', 'cancelled')),
  to_status text not null check (to_status in ('draft', 'confirmed', 'cancelled')),
  changed_by_id bigint references public.profile(id) on delete set null,
  note text check (note is null or char_length(note) <= 500),
  changed_at timestamptz not null default now()
);
create index if not exists order_status_history_order_idx
  on public.order_status_history(order_id, changed_at desc);

insert into public.order_status_history(order_id, from_status, to_status, changed_by_id, changed_at)
select id, null, status, created_by_id, created_at
from public.customer_order o
where not exists (
  select 1 from public.order_status_history h where h.order_id = o.id
);

create or replace function public.record_initial_order_status()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.order_status_history(order_id, from_status, to_status, changed_by_id)
  values (new.id, null, new.status, new.created_by_id);
  return new;
end;
$$;
revoke all on function public.record_initial_order_status() from public, anon, authenticated;
drop trigger if exists customer_order_initial_status on public.customer_order;
create trigger customer_order_initial_status
  after insert on public.customer_order
  for each row execute function public.record_initial_order_status();

alter table public.inventory_movement
  drop constraint if exists inventory_movement_order_shape;
alter table public.inventory_movement
  add constraint inventory_movement_order_shape check
    ((movement_type = 'order' and order_id is not null and quantity_delta < 0)
      or (movement_type = 'order_cancel' and order_id is not null and quantity_delta > 0)
      or (movement_type = 'adjustment' and order_id is null));
alter table public.inventory_movement
  drop constraint if exists inventory_movement_movement_type_check;
alter table public.inventory_movement
  add constraint inventory_movement_movement_type_check
  check (movement_type in ('adjustment', 'order', 'order_cancel'));
drop index if exists public.inventory_movement_order_lot_uq;
create unique index inventory_movement_order_lot_uq
  on public.inventory_movement(order_id, product_lot_id)
  where movement_type = 'order';
create unique index if not exists inventory_movement_cancel_order_lot_uq
  on public.inventory_movement(order_id, product_lot_id)
  where movement_type = 'order_cancel';

alter table public.order_status_history enable row level security;
drop policy if exists order_status_history_select on public.order_status_history;
create policy order_status_history_select on public.order_status_history
  for select to authenticated using (public.has_permission('orders.read'));
revoke all on public.order_status_history from public, anon, authenticated;
grant select on public.order_status_history to authenticated;

insert into public.permission(code, description)
values ('orders.transition', 'Cambiar el estado de los pedidos.')
on conflict (code) do nothing;

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
    raise exception 'La solicitud no es valida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all(array['order_id', 'status', 'note']) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p->'order_id') is distinct from 'number'
     or (p->>'order_id') !~ '^[1-9][0-9]*$'
     or jsonb_typeof(p->'status') is distinct from 'string' then
    raise exception 'Pedido o estado no validos.' using errcode = '22023';
  end if;
  begin
    v_order_id := (p->>'order_id')::bigint;
  exception when others then
    raise exception 'El pedido no es valido.' using errcode = '22023';
  end;
  v_target := p->>'status';
  if v_target not in ('confirmed', 'cancelled') then
    raise exception 'El estado solicitado no es valido.' using errcode = '22023';
  end if;
  if p ? 'note' and p->'note' <> 'null'::jsonb and jsonb_typeof(p->'note') is distinct from 'string' then
    raise exception 'La nota debe ser texto.' using errcode = '22023';
  end if;
  if char_length(coalesce(p->>'note', '')) > 500 then
    raise exception 'La nota admite hasta 500 caracteres.' using errcode = '22023';
  end if;
  select * into v_order from public.customer_order where id = v_order_id for update;
  if not found then raise exception 'El pedido no existe.' using errcode = 'P0002'; end if;
  if v_order.status = v_target then
    raise exception 'El pedido ya tiene ese estado.' using errcode = 'P0001';
  end if;
  if v_order.status = 'cancelled' or (v_order.status = 'confirmed' and v_target <> 'cancelled') then
    raise exception 'La transicion de estado no esta permitida.' using errcode = 'P0001';
  end if;
  v_profile_id := (select id from public.profile where auth_user_id = auth.uid());
  if v_target = 'cancelled' then
    for v_movement in
      select product_lot_id, -quantity_delta as quantity_to_restore
      from public.inventory_movement
      where order_id = v_order_id and movement_type = 'order'
    loop
      insert into public.inventory_movement(product_lot_id, quantity_delta, movement_type, order_id, performed_by_id)
      values (v_movement.product_lot_id, v_movement.quantity_to_restore,
              'order_cancel', v_order_id, v_profile_id);
    end loop;
  end if;
  update public.customer_order set status = v_target where id = v_order_id;
  insert into public.order_status_history(order_id, from_status, to_status, changed_by_id, note)
  values (v_order_id, v_order.status, v_target, v_profile_id, nullif(btrim(p->>'note'), ''));
  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (v_profile_id, 'customer_order.status_changed', 'customer_order', v_order_id,
          jsonb_build_object('from_status', v_order.status, 'to_status', v_target));
  return jsonb_build_object('id', v_order_id, 'order_number', v_order.order_number,
                            'status', v_target, 'updated_at', now());
end;
$$;
revoke all on function public.transition_customer_order(jsonb) from public, anon;
grant execute on function public.transition_customer_order(jsonb) to authenticated;
