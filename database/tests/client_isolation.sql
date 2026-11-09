-- Valida database/drafts/client_isolation.sql (aislamiento del cliente externo) sobre tablas de
-- prueba. Todo se revierte al final: no queda ninguna tabla ni dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/client_isolation.sql
-- Ejecutar desde la raiz del repositorio (usa \i con ruta relativa).

begin;

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

\i database/tests/_domain_stubs.sql
\i database/drafts/domain_policies.sql
\i database/drafts/client_isolation.sql

-- ------------------------------------------------------------------ usuarios y roles ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'a@iso.test', '{"first_name":"Cliente","last_name":"A"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'b@iso.test', '{"first_name":"Cliente","last_name":"B"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b3', 'authenticated', 'authenticated', 'c@iso.test', '{"first_name":"Sin","last_name":"Vinculo"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b4', 'authenticated', 'authenticated', 'd@iso.test', '{"first_name":"Sin","last_name":"Permiso"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b5', 'authenticated', 'authenticated', 'off@iso.test', '{"first_name":"Desactivado","last_name":"Cliente"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b6', 'authenticated', 'authenticated', 'staff@iso.test', '{"first_name":"Personal","last_name":"Interno"}', now(), now());

insert into public.role(name) values ('i_portal'), ('i_none'), ('i_staff');
insert into public.role_permission(role_id, permission_code)
select r.id, 'portal.read' from public.role r where r.name = 'i_portal';
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['orders.read','customers.read','exports.read','logistics.read','documents.read']) p
where r.name = 'i_staff';

update public.profile set role_id = (select id from public.role where name = 'i_portal')
 where email in ('a@iso.test', 'b@iso.test', 'c@iso.test', 'off@iso.test');
update public.profile set role_id = (select id from public.role where name = 'i_none')  where email = 'd@iso.test';
update public.profile set role_id = (select id from public.role where name = 'i_staff') where email = 'staff@iso.test';
update public.profile set is_active = false where email = 'off@iso.test';

-- ----------------------------------------------------------------------- datos ---
alter table public.customer alter column id restart with 1;                -- real: se revierte al final
insert into public.customer(name, country_code, preferred_currency_code) values ('C1', 'US', 'USD'), ('C2', 'US', 'USD');  -- ids 1, 2
insert into public.customer_order(customer_id) values (1), (2), (1);             -- O1, O2, O3
insert into public.order_line(order_id) values (1), (2), (3);
insert into public.export(order_id) values (1), (2);                             -- E1 (O1), E2 (O2)
insert into public.export_line(export_id) values (1), (2);
insert into public.export_document(export_id) values (1), (2);
insert into public.shipment(export_id) values (1), (2);                          -- S1 (E1), S2 (E2)
insert into public.shipment_event(shipment_id) values (1), (1), (2);
insert into public.payment_obligation(order_id) values (1), (2);
insert into public.inventory_movement default values;

insert into public.customer_user(customer_id, profile_id)
select 1, id from public.profile where email in ('a@iso.test', 'd@iso.test', 'off@iso.test');
insert into public.customer_user(customer_id, profile_id)
select 2, id from public.profile where email = 'b@iso.test';

-- ------------------------------------------------- cliente A (vinculado a C1) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);

select pg_temp.rows('A ve solo su cliente', $q$select * from public.customer$q$, 1);
select pg_temp.rows('A ve solo sus pedidos (O1, O3)', $q$select * from public.customer_order$q$, 2);
select pg_temp.rows('A no ve el pedido de otro cliente', $q$select * from public.customer_order where customer_id = 2$q$, 0);
select pg_temp.rows('A ve las lineas de sus pedidos', $q$select * from public.order_line$q$, 2);
select pg_temp.rows('A ve solo su exportacion (E1)', $q$select * from public.export$q$, 1);
select pg_temp.rows('A ve las lineas y documentos de su exportacion', $q$select * from public.export_line l, public.export_document d$q$, 1);
select pg_temp.rows('A ve solo su envio (S1)', $q$select * from public.shipment$q$, 1);
select pg_temp.rows('A ve los eventos de su envio (2)', $q$select * from public.shipment_event$q$, 2);
select pg_temp.rows('A no ve pagos', $q$select * from public.payment_obligation$q$, 0);
select pg_temp.rows('A no ve inventario', $q$select * from public.inventory_movement$q$, 0);
select pg_temp.rows('A ve solo su vinculo', $q$select * from public.customer_user$q$, 1);

select pg_temp.attempt('A no crea pedidos', $q$insert into public.customer_order(customer_id) values (1)$q$, 'row-level security');
select pg_temp.rows('A no edita sus pedidos', $q$update public.customer_order set nota = 'x'$q$, 0);
select pg_temp.attempt('A no borra pedidos', $q$delete from public.customer_order$q$, 'permission denied');
select pg_temp.attempt('A no se vincula a otro cliente', $q$insert into public.customer_user(customer_id, profile_id) values (2, (select id from public.profile where email = 'a@iso.test'))$q$, 'permission denied');
select pg_temp.attempt('A no desvincula', $q$delete from public.customer_user$q$, 'permission denied');
select pg_temp.rows('A (tras intentar desvincular) conserva su acceso', $q$select * from public.customer_order$q$, 2);

-- ------------------------------------------------- cliente B (vinculado a C2) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select pg_temp.rows('B ve solo su cliente', $q$select * from public.customer$q$, 1);
select pg_temp.rows('B ve solo su pedido (O2)', $q$select * from public.customer_order$q$, 1);
select pg_temp.rows('B ve solo su exportacion y envio', $q$select * from public.export e, public.shipment s$q$, 1);
select pg_temp.rows('B ve solo el evento de su envio', $q$select * from public.shipment_event$q$, 1);

-- ------------------------------------------------ sin vinculo / sin permiso / desactivado ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
select pg_temp.rows('con portal.read pero sin vinculo: no ve pedidos', $q$select * from public.customer_order$q$, 0);
select pg_temp.rows('con portal.read pero sin vinculo: no ve envios', $q$select * from public.shipment$q$, 0);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b4","role":"authenticated"}', true);
select pg_temp.rows('vinculado pero sin portal.read: no ve pedidos', $q$select * from public.customer_order$q$, 0);
select pg_temp.rows('vinculado pero sin portal.read: no ve su cliente', $q$select * from public.customer$q$, 0);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b5","role":"authenticated"}', true);
select pg_temp.rows('desactivado y vinculado: no ve pedidos', $q$select * from public.customer_order$q$, 0);
select pg_temp.rows('desactivado y vinculado: no ve envios', $q$select * from public.shipment$q$, 0);

-- ------------------------------------------------------------ personal interno ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b6","role":"authenticated"}', true);
select pg_temp.rows('personal interno: sigue viendo todos los pedidos', $q$select * from public.customer_order$q$, 3);
select pg_temp.rows('personal interno: sigue viendo todos los envios', $q$select * from public.shipment$q$, 2);
select pg_temp.rows('personal interno: ve todos los vinculos', $q$select * from public.customer_user$q$, 4);
select pg_temp.attempt('personal sin customers.update no vincula a nadie', $q$select public.link_customer_user(1, 'staff@iso.test')$q$, 'No tienes permiso');

-- ------------------------------------------------------------------- anonimo ---
reset role;
set local role anon;
select pg_temp.attempt('anonimo no lee el vinculo', $q$select * from public.customer_user$q$, 'permission denied');
select pg_temp.attempt('anonimo no ejecuta las funciones auxiliares', $q$select public.my_customer_ids()$q$, 'permission denied');

reset role;
select n, prueba, resultado from resultados order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select count(*) as tablas_de_prueba_tras_rollback from pg_class
where relnamespace = 'public'::regnamespace and relname in ('customer_order', 'export');
