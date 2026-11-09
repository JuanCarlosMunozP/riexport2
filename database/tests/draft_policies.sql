-- Valida database/drafts/domain_policies.sql sobre TABLAS DE PRUEBA (solo con las columnas que usan
-- las politicas). Todo se revierte al final: no queda ninguna tabla ni dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/draft_policies.sql
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

-- ------------------------------------------------------------ tablas de prueba ---
-- `customer` es una tabla real: se reinicia su identidad dentro de la transaccion (se revierte al final).
alter table public.customer alter column id restart with 1;
create table public.customer_order(id bigint generated always as identity primary key, nota text);
create table public.order_line(id bigint generated always as identity primary key);
create table public.export(id bigint generated always as identity primary key);
create table public.export_line(id bigint generated always as identity primary key);
create table public.export_document(id bigint generated always as identity primary key, created_by_id bigint);
create table public.stored_file(id bigint generated always as identity primary key, uploaded_by_id bigint);
create table public.inventory_movement(id bigint generated always as identity primary key, performed_by_id bigint);
create table public.payment_obligation(id bigint generated always as identity primary key);
create table public.payment_transaction(id bigint generated always as identity primary key, recorded_by_id bigint);
create table public.exchange_rate(id bigint generated always as identity primary key);
create table public.shipment(id bigint generated always as identity primary key, nota text);
create table public.shipment_event(id bigint generated always as identity primary key, nota text);
create table public.notification(id bigint generated always as identity primary key,
  recipient_user_id bigint, title text, read_at timestamptz);

\i database/drafts/domain_policies.sql

-- ------------------------------------------------------------------ usuarios ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated', 'full@dom.test', '{"first_name":"Full","last_name":"Uno"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f2', 'authenticated', 'authenticated', 'read@dom.test', '{"first_name":"Read","last_name":"Dos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f3', 'authenticated', 'authenticated', 'none@dom.test', '{"first_name":"None","last_name":"Tres"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f4', 'authenticated', 'authenticated', 'off@dom.test', '{"first_name":"Off","last_name":"Cuatro"}', now(), now());

insert into public.role(name) values ('d_full'), ('d_read');
insert into public.role_permission(role_id, permission_code)
select r.id, p.code from public.role r cross join public.permission p
where r.name = 'd_full' and p.code ~ '^(customers|orders|exports|documents|inventory|payments|logistics)\.';
insert into public.role_permission(role_id, permission_code)
select r.id, p.code from public.role r cross join public.permission p
where r.name = 'd_read' and p.code ~ '^(customers|orders|exports|documents|inventory|payments|logistics)\.read$';

update public.profile set role_id = (select id from public.role where name = 'd_full') where email in ('full@dom.test', 'off@dom.test');
update public.profile set role_id = (select id from public.role where name = 'd_read') where email = 'read@dom.test';
update public.profile set is_active = false where email = 'off@dom.test';

-- una fila en cada tabla de prueba (como superusuario)
insert into public.customer(name, country_code, preferred_currency_code) values ('C1', 'US', 'USD');
insert into public.customer_order default values;
insert into public.order_line default values;
insert into public.export default values;
insert into public.export_line default values;
insert into public.export_document default values;
insert into public.stored_file default values;
insert into public.inventory_movement default values;
insert into public.payment_obligation default values;
insert into public.payment_transaction default values;
insert into public.exchange_rate default values;
insert into public.shipment default values;
insert into public.shipment_event default values;
insert into public.notification(recipient_user_id, title)
  select id, 'para read' from public.profile where email = 'read@dom.test';
insert into public.notification(recipient_user_id, title)
  select id, 'para none' from public.profile where email = 'none@dom.test';

-- ------------------------------------------------- lectura: rol solo lectura (read) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);

select pg_temp.rows('lectura: ve clientes', $q$select * from public.customer$q$, 1);
select pg_temp.rows('lectura: ve pedidos y lineas', $q$select * from public.customer_order c, public.order_line l$q$, 1);
select pg_temp.rows('lectura: ve exportaciones, lineas, documentos', $q$select * from public.export e, public.export_line l, public.export_document d$q$, 1);
select pg_temp.rows('lectura: ve inventario', $q$select * from public.inventory_movement$q$, 1);
select pg_temp.rows('lectura: ve pagos y tasas', $q$select * from public.payment_obligation o, public.payment_transaction t, public.exchange_rate r$q$, 1);
select pg_temp.rows('lectura: ve envios y eventos', $q$select * from public.shipment s, public.shipment_event e$q$, 1);
select pg_temp.rows('lectura: ve solo sus notificaciones', $q$select * from public.notification$q$, 1);
select pg_temp.rows('lectura: ve metadatos de archivos (documents.read)', $q$select * from public.stored_file$q$, 1);

select pg_temp.attempt('lectura: no crea clientes', $q$select public.create_customer('{"name":"X","country_code":"US","preferred_currency_code":"USD"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no crea pedidos', $q$insert into public.customer_order default values$q$, 'row-level security');
select pg_temp.rows('lectura: no edita pedidos', $q$update public.customer_order set nota = 'x'$q$, 0);
select pg_temp.attempt('lectura: no registra ajustes de inventario', $q$insert into public.inventory_movement(performed_by_id) values (1)$q$, 'row-level security');
select pg_temp.attempt('lectura: no registra pagos', $q$insert into public.payment_obligation default values$q$, 'row-level security');
select pg_temp.attempt('lectura: no registra envios', $q$insert into public.shipment default values$q$, 'row-level security');
select pg_temp.attempt('lectura: no registra eventos', $q$insert into public.shipment_event default values$q$, 'row-level security');

-- notificaciones: solo las propias, y solo read_at
select pg_temp.rows('notificacion: marca como leida la propia', $q$update public.notification set read_at = now() where title = 'para read'$q$, 1);
select pg_temp.rows('notificacion: no toca la ajena', $q$update public.notification set read_at = now() where title = 'para none'$q$, 0);
select pg_temp.attempt('notificacion: no cambia el titulo (solo read_at)', $q$update public.notification set title = 'x' where title = 'para read'$q$, 'permission denied');
select pg_temp.attempt('notificacion: no se crean desde la API', $q$insert into public.notification(recipient_user_id) values (1)$q$, 'permission denied');

-- ----------------------------------------------- escritura: rol con todos los permisos ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);

select pg_temp.attempt('completo: crea cliente (por la funcion)', $q$select public.create_customer('{"name":"X","country_code":"US","preferred_currency_code":"USD"}')$q$, 'ok');
select pg_temp.attempt('completo: edita cliente (por la funcion)', $q$select public.update_customer(1, '{"name":"Y"}')$q$, 'ok');
select pg_temp.attempt('completo: no inserta cliente directo', $q$insert into public.customer(name, country_code, preferred_currency_code) values ('Z', 'US', 'USD')$q$, 'permission denied');
select pg_temp.attempt('completo: no borra clientes', $q$delete from public.customer$q$, 'permission denied');
select pg_temp.attempt('completo: crea pedido', $q$insert into public.customer_order default values$q$, 'ok');
select pg_temp.rows('completo: borra una linea de pedido (se reemplazan al editar)', $q$delete from public.order_line$q$, 1);
select pg_temp.attempt('completo: no borra pedidos', $q$delete from public.customer_order$q$, 'permission denied');
select pg_temp.attempt('completo: crea exportacion', $q$insert into public.export default values$q$, 'ok');
select pg_temp.attempt('completo: adjunta documento firmado por si mismo', $q$insert into public.export_document(created_by_id) values (public.current_profile_id())$q$, 'ok');
select pg_temp.attempt('completo: no firma documentos como otro', $q$insert into public.export_document(created_by_id) values (-1)$q$, 'row-level security');
select pg_temp.attempt('documentos inmutables: no se editan', $q$update public.export_document set created_by_id = 1$q$, 'permission denied');
select pg_temp.attempt('completo: sube metadatos de su archivo', $q$insert into public.stored_file(uploaded_by_id) values (public.current_profile_id())$q$, 'ok');
select pg_temp.attempt('completo: no sube metadatos a nombre de otro', $q$insert into public.stored_file(uploaded_by_id) values (-1)$q$, 'row-level security');
select pg_temp.attempt('completo: ajuste de inventario firmado por si mismo', $q$insert into public.inventory_movement(performed_by_id) values (public.current_profile_id())$q$, 'ok');
select pg_temp.attempt('completo: no ajusta a nombre de otro', $q$insert into public.inventory_movement(performed_by_id) values (-1)$q$, 'row-level security');
select pg_temp.attempt('libro de inventario inmutable: no se edita', $q$update public.inventory_movement set performed_by_id = 1$q$, 'permission denied');
select pg_temp.attempt('libro de inventario inmutable: no se borra', $q$delete from public.inventory_movement$q$, 'permission denied');
select pg_temp.attempt('completo: crea obligacion de pago', $q$insert into public.payment_obligation default values$q$, 'ok');
select pg_temp.attempt('completo: registra un pago firmado por si mismo', $q$insert into public.payment_transaction(recorded_by_id) values (public.current_profile_id())$q$, 'ok');
select pg_temp.attempt('pagos inmutables: no se editan', $q$update public.payment_transaction set recorded_by_id = 1$q$, 'permission denied');
select pg_temp.attempt('tasas de cambio: no las escribe un usuario', $q$insert into public.exchange_rate default values$q$, 'permission denied');
select pg_temp.attempt('completo: registra envio', $q$insert into public.shipment default values$q$, 'ok');
select pg_temp.rows('completo: actualiza envio', $q$update public.shipment set nota = 'x' where id = 1$q$, 1);
select pg_temp.attempt('completo: registra evento logistico', $q$insert into public.shipment_event default values$q$, 'ok');
select pg_temp.attempt('eventos inmutables: no se editan', $q$update public.shipment_event set nota = 'x'$q$, 'permission denied');

-- ----------------------------------------------------- sin permisos y desactivado ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f3","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: no ve clientes', $q$select * from public.customer$q$, 0);
select pg_temp.rows('sin permisos: no ve pedidos', $q$select * from public.customer_order$q$, 0);
select pg_temp.rows('sin permisos: no ve inventario ni pagos', $q$select * from public.inventory_movement m, public.payment_obligation p$q$, 0);
select pg_temp.rows('sin permisos: ve solo su notificacion', $q$select * from public.notification$q$, 1);
select pg_temp.attempt('sin permisos: no crea clientes', $q$select public.create_customer('{"name":"X","country_code":"US","preferred_currency_code":"USD"}')$q$, 'No tienes permiso');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f4","role":"authenticated"}', true);
select pg_temp.rows('desactivado (con rol completo): no ve clientes', $q$select * from public.customer$q$, 0);
select pg_temp.attempt('desactivado: no crea pedidos', $q$insert into public.customer_order default values$q$, 'row-level security');
select pg_temp.rows('desactivado: no ve notificaciones', $q$select * from public.notification$q$, 0);

-- ------------------------------------------------------------------- anonimo ---
reset role;
set local role anon;
select pg_temp.attempt('anonimo no lee clientes', $q$select * from public.customer$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee notificaciones', $q$select * from public.notification$q$, 'permission denied');
select pg_temp.attempt('anonimo no escribe', $q$insert into public.customer default values$q$, 'permission denied');

reset role;
select n, prueba, resultado from resultados order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

-- politicas sobre las 14 tablas y todas con RLS
select count(*) as tablas_de_prueba_con_rls,
       count(*) filter (where c.relrowsecurity) as con_rls
from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
  and c.relname in ('customer','customer_order','order_line','export','export_line','export_document',
                    'stored_file','inventory_movement','payment_obligation','payment_transaction',
                    'exchange_rate','shipment','shipment_event','notification');

rollback;

select count(*) as tablas_de_prueba_tras_rollback from pg_class
where relnamespace = 'public'::regnamespace and relname in ('customer', 'notification');
