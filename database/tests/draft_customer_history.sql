-- Valida database/drafts/customer_history.sql sobre TABLAS DE PRUEBA `customer_order`, `order_line` y `export`
-- (las reales aun no existen). Todo se revierte al final: no queda ninguna tabla ni dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/draft_customer_history.sql
-- Ejecutar desde la raiz del repositorio (usa \i con ruta relativa).

begin;

do $$
begin
  if to_regclass('public.customer_order') is not null or to_regclass('public.order_line') is not null
     or to_regclass('public.export') is not null then
    raise exception 'Las tablas de pedidos/exportaciones ya existen: convierte el borrador en migracion y adapta esta prueba.';
  end if;
end $$;

create table public.customer_order(
  id bigint generated always as identity primary key,
  order_number text not null,
  customer_id bigint not null references public.customer(id),
  status text not null,
  currency_code text not null,
  created_at timestamptz not null default now()
);
create table public.order_line(
  id bigint generated always as identity primary key,
  order_id bigint not null references public.customer_order(id),
  quantity numeric(18, 3) not null,
  unit_price numeric(18, 4) not null
);
create table public.export(
  id bigint generated always as identity primary key,
  order_id bigint not null references public.customer_order(id),
  destination_country_code text not null,
  export_date date not null,
  status text not null
);

create temp table resultados(n serial, prueba text, resultado text);
grant all on resultados to authenticated, anon;
grant usage on sequence resultados_n_seq to authenticated, anon;

create function pg_temp.attempt(p_name text, p_sql text, p_expect text) returns void
language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
    insert into resultados(prueba, resultado)
      values (p_name, case when p_expect = 'ok' then 'OK' else 'FALLA: se permitio' end);
  exception when others then
    v_msg := sqlerrm;
    insert into resultados(prueba, resultado) values (p_name,
      case when p_expect <> 'ok' and v_msg ilike '%' || p_expect || '%' then 'OK'
           else 'FALLA: ' || v_msg end);
  end;
end $$;

create function pg_temp.rows(p_name text, p_sql text, p_expected int) returns void
language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  insert into resultados(prueba, resultado) values (p_name,
    case when n = p_expected then 'OK' else 'FALLA: filas ' || n || ', esperadas ' || p_expected end);
exception when others then
  insert into resultados(prueba, resultado) values (p_name, 'FALLA: ' || sqlerrm);
end $$;

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default '') returns void
language sql as $$
  insert into resultados(prueba, resultado)
  values (p_name, case when p_ok then 'OK' else 'FALLA: ' || p_detail end);
$$;

\i database/drafts/customer_history.sql

-- ------------------------------------------------------------------------ usuarios y roles ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'ha@hist.test', '{"first_name":"Todo","last_name":"Historial"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'ho@hist.test', '{"first_name":"Solo","last_name":"Pedidos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'hc@hist.test', '{"first_name":"Solo","last_name":"Clientes"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e4', 'authenticated', 'authenticated', 'hn@hist.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e5', 'authenticated', 'authenticated', 'hx@hist.test', '{"first_name":"Desactivado","last_name":"Historial"}', now(), now());

insert into public.role(name) values ('h_all'), ('h_orders'), ('h_cust');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['customers.read','orders.read','exports.read']) p where r.name = 'h_all';
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['customers.read','orders.read']) p where r.name = 'h_orders';
insert into public.role_permission(role_id, permission_code)
select r.id, 'customers.read' from public.role r where r.name = 'h_cust';
update public.profile set role_id = (select id from public.role where name = 'h_all') where email in ('ha@hist.test', 'hx@hist.test');
update public.profile set role_id = (select id from public.role where name = 'h_orders') where email = 'ho@hist.test';
update public.profile set role_id = (select id from public.role where name = 'h_cust') where email = 'hc@hist.test';
update public.profile set is_active = false where email = 'hx@hist.test';

-- ------------------------------------------------------------------------------- datos ---
alter table public.customer alter column id restart with 1;
insert into public.customer(name, country_code, preferred_currency_code) values ('Cliente Uno', 'US', 'USD'), ('Cliente Dos', 'US', 'USD');
insert into public.customer_order(order_number, customer_id, status, currency_code, created_at) values
  ('PO-0001', 1, 'exported', 'USD', '2026-01-10'),
  ('PO-0002', 1, 'pending', 'USD', '2026-02-10'),
  ('PO-0003', 2, 'confirmed', 'EUR', '2026-03-10'),
  ('PO-0004', 1, 'confirmed', 'USD', '2026-04-10');   -- sin lineas
insert into public.order_line(order_id, quantity, unit_price) values
  (1, 100, 2.5), (1, 50, 4), (2, 10, 3), (3, 7, 1.5);
insert into public.export(order_id, destination_country_code, export_date, status) values
  (1, 'DE', '2026-01-20', 'shipped'),
  (1, 'FR', '2026-02-01', 'draft'),
  (3, 'NL', '2026-03-20', 'draft');

-- ------------------------------------------------------------ con todos los permisos (ha) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select pg_temp.rows('pedidos del cliente 1: 3', $q$select * from public.customer_order_history where customer_id = 1$q$, 3);
select pg_temp.rows('pedidos del cliente 2: 1', $q$select * from public.customer_order_history where customer_id = 2$q$, 1);
select pg_temp.check('el total del pedido es la suma de cantidad x precio de sus lineas (100*2.5 + 50*4 = 450)',
  (select order_total = 450 from public.customer_order_history where order_number = 'PO-0001'));
select pg_temp.check('un pedido sin lineas tiene total 0',
  (select order_total = 0 from public.customer_order_history where order_number = 'PO-0004'));
select pg_temp.check('cuenta las exportaciones y la fecha de la ultima',
  (select export_count = 2 and last_export_date = date '2026-02-01' from public.customer_order_history where order_number = 'PO-0001')
  and (select export_count = 0 and last_export_date is null from public.customer_order_history where order_number = 'PO-0002'));
select pg_temp.check('conserva estado, moneda y fecha del pedido',
  (select status = 'confirmed' and currency_code = 'EUR' and created_at::date = date '2026-03-10'
     from public.customer_order_history where order_number = 'PO-0003'));
select pg_temp.check('no mezcla los pedidos de otro cliente',
  (select count(*) = 0 from public.customer_order_history where customer_id = 1 and order_number = 'PO-0003'));
select pg_temp.rows('exportaciones del cliente 1: 2', $q$select * from public.customer_export_history where customer_id = 1$q$, 2);
select pg_temp.rows('exportaciones del cliente 2: 1', $q$select * from public.customer_export_history where customer_id = 2$q$, 1);
select pg_temp.check('la exportacion trae el numero del pedido, destino, fecha y estado',
  (select order_number = 'PO-0001' and destination_country_code = 'FR' and export_date = date '2026-02-01' and status = 'draft'
     from public.customer_export_history where customer_id = 1 and destination_country_code = 'FR'));

-- ------------------------------------------------------------------------ otros permisos ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
select pg_temp.rows('customers.read + orders.read: ve los pedidos', $q$select * from public.customer_order_history$q$, 4);
select pg_temp.rows('sin exports.read: no ve las exportaciones', $q$select * from public.customer_export_history$q$, 0);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
select pg_temp.rows('solo customers.read: no ve pedidos', $q$select * from public.customer_order_history$q$, 0);
select pg_temp.rows('solo customers.read: no ve exportaciones', $q$select * from public.customer_export_history$q$, 0);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: no ve pedidos', $q$select * from public.customer_order_history$q$, 0);
select pg_temp.rows('sin permisos: no ve exportaciones', $q$select * from public.customer_export_history$q$, 0);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
select pg_temp.rows('desactivado: no ve pedidos', $q$select * from public.customer_order_history$q$, 0);

-- solo lectura
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select pg_temp.attempt('no se inserta por la vista', $q$insert into public.customer_order_history(customer_id) values (1)$q$, 'permission denied');
select pg_temp.attempt('no se actualiza por la vista', $q$update public.customer_order_history set status = 'x'$q$, 'permission denied');
select pg_temp.attempt('no se borra por la vista', $q$delete from public.customer_export_history$q$, 'cannot delete from view');
reset role;
set local role anon;
select pg_temp.attempt('anonimo: no lee los pedidos', $q$select * from public.customer_order_history$q$, 'permission denied');
select pg_temp.attempt('anonimo: no lee las exportaciones', $q$select * from public.customer_export_history$q$, 'permission denied');
reset role;

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select to_regclass('public.customer_order') as pedidos_tras_rollback, to_regclass('public.customer_order_history') as vista_tras_rollback;
