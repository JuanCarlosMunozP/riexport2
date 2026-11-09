-- Valida database/drafts/export_traceability.sql sobre TABLAS DE PRUEBA `export` y `export_line` (las reales
-- aun no existen). Todo se revierte al final: no queda ninguna tabla ni dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/draft_export_traceability.sql
-- Ejecutar desde la raiz del repositorio (usa \i con ruta relativa).

begin;

-- Si algun dia existen las tablas reales, este borrador ya es una migracion: no pisarlas.
do $$
begin
  if to_regclass('public.export') is not null or to_regclass('public.export_line') is not null then
    raise exception 'Las tablas export/export_line ya existen: convierte el borrador en migracion y adapta esta prueba.';
  end if;
end $$;

create table public.export(id bigint generated always as identity primary key, order_id bigint);
create table public.export_line(
  id bigint generated always as identity primary key,
  export_id bigint not null references public.export(id),
  order_line_id bigint,
  product_lot_id bigint not null references public.product_lot(id),
  quantity numeric(18, 3) not null check (quantity > 0),
  hs_code_snapshot text not null
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

\i database/drafts/export_traceability.sql

-- ------------------------------------------------------------------------ usuarios y roles ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'tw@trace.test', '{"first_name":"Todo","last_name":"Origen"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'te@trace.test', '{"first_name":"Solo","last_name":"Exportaciones"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b3', 'authenticated', 'authenticated', 'tf@trace.test', '{"first_name":"Solo","last_name":"Fincas"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b4', 'authenticated', 'authenticated', 'tn@trace.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b5', 'authenticated', 'authenticated', 'to@trace.test', '{"first_name":"Desactivado","last_name":"Origen"}', now(), now());

insert into public.role(name) values ('t_all'), ('t_exp'), ('t_farm');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['exports.read','farms.read','farms.create','lots.create','lots.read','suppliers.create','suppliers.read','products.create','products.read']) p where r.name = 't_all';
insert into public.role_permission(role_id, permission_code)
select r.id, 'exports.read' from public.role r where r.name = 't_exp';
insert into public.role_permission(role_id, permission_code)
select r.id, 'farms.read' from public.role r where r.name = 't_farm';
update public.profile set role_id = (select id from public.role where name = 't_all') where email in ('tw@trace.test', 'to@trace.test');
update public.profile set role_id = (select id from public.role where name = 't_exp') where email = 'te@trace.test';
update public.profile set role_id = (select id from public.role where name = 't_farm') where email = 'tf@trace.test';
update public.profile set is_active = false where email = 'to@trace.test';

-- ------------------------------------------------------------------ datos de origen (como tw) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select public.create_supplier('{"business_name":"Proveedor Uno","tax_id":"NIT-0001"}');
select public.create_supplier('{"business_name":"Proveedor Dos","tax_id":"NIT-0002"}');
select public.create_product('{"type":"coffee","variety":"Caturra","quality_grade":"Excelso","base_unit_code":"kg","humidity_percent":11}');
select public.create_product('{"type":"cacao","variety":"Criollo","quality_grade":"Premium","base_unit_code":"kg","bean_type":"Fino","fermentation_percent":80}');
select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'Finca Norte', 'latitude', 6.2, 'longitude', -75.5));
select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'Finca Sur', 'latitude', 1.2, 'longitude', -77.3));
select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0002'), 'country_code', 'EC', 'name', 'Finca Sin Punto'));
select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'Finca Norte'), 'lot_code', 'N-1'));
select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'Finca Norte'), 'lot_code', 'N-2'));
select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'Finca Sur'), 'lot_code', 'S-1'));
select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Criollo'), 'farm_id', (select id from public.farm where name = 'Finca Sin Punto'), 'lot_code', 'X-1'));

-- Exportaciones (las escribe el propietario: las tablas reales aun no existen ni tienen funciones).
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into public.export default values;
insert into public.export default values;
insert into public.export default values;
-- Exportacion 1: dos lotes de Finca Norte + uno de Finca Sur
insert into public.export_line (export_id, product_lot_id, quantity, hs_code_snapshot) values
  ((select min(id) from public.export), (select id from public.product_lot where lot_code = 'N-1'), 100, '0901.11'),
  ((select min(id) from public.export), (select id from public.product_lot where lot_code = 'N-2'), 50.5, '0901.11'),
  ((select min(id) from public.export), (select id from public.product_lot where lot_code = 'S-1'), 200, '0901.11');
-- Exportacion 2: el mismo lote N-1 otra vez, y un lote de la finca sin punto
insert into public.export_line (export_id, product_lot_id, quantity, hs_code_snapshot) values
  ((select min(id) + 1 from public.export), (select id from public.product_lot where lot_code = 'N-1'), 25, '0901.11'),
  ((select min(id) + 1 from public.export), (select id from public.product_lot where lot_code = 'X-1'), 10, '1801.00');
-- Exportacion 3: sin lineas

-- --------------------------------------------------------------------- con exports.read y farms.read ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select pg_temp.rows('lee la trazabilidad completa (5 lineas)', $q$select * from public.export_traceability$q$, 5);
select pg_temp.rows('trazabilidad de la exportacion 1: 3 lineas', $q$select * from public.export_traceability where export_id = (select min(id) from public.export)$q$, 3);
select pg_temp.check('cada linea llega hasta el proveedor y trae la geolocalizacion de la finca',
  (select count(*) = 3 and bool_and(supplier_name is not null and farm_name is not null and latitude is not null and longitude is not null)
     from public.export_traceability where export_id = (select min(id) from public.export)));
select pg_temp.check('conserva cantidad y codigo HS de la linea',
  (select quantity = 50.5 and hs_code_snapshot = '0901.11' and lot_code = 'N-2' and product_variety = 'Caturra' and supplier_name = 'Proveedor Uno'
     from public.export_traceability where lot_code = 'N-2'));
select pg_temp.check('la finca sin punto aparece con coordenadas nulas',
  (select latitude is null and longitude is null and country_code = 'EC' from public.export_traceability where lot_code = 'X-1'));
select pg_temp.check('una exportacion sin lineas no aparece', (select count(*) = 0 from public.export_traceability where export_id = (select max(id) from public.export)));

select pg_temp.rows('fincas de origen de la exportacion 1: 2', $q$select * from public.export_origin_farms where export_id = (select min(id) from public.export)$q$, 2);
select pg_temp.check('suma de cantidades y lotes por finca (exportacion 1)',
  (select total_quantity = 150.5 and lot_count = 2 from public.export_origin_farms where export_id = (select min(id) from public.export) and farm_name = 'Finca Norte')
  and (select total_quantity = 200 and lot_count = 1 from public.export_origin_farms where export_id = (select min(id) from public.export) and farm_name = 'Finca Sur'));
select pg_temp.check('un mismo lote en dos exportaciones cuenta en cada una',
  (select total_quantity = 25 and lot_count = 1 from public.export_origin_farms where export_id = (select min(id) + 1 from public.export) and farm_name = 'Finca Norte'));
select pg_temp.rows('fincas de origen de la exportacion 2: 2 (una sin punto)', $q$select * from public.export_origin_farms where export_id = (select min(id) + 1 from public.export)$q$, 2);
select pg_temp.rows('inverso: exportaciones donde participa un lote', $q$select distinct export_id from public.export_traceability where lot_code = 'N-1'$q$, 2);

-- ------------------------------------------------------------------------------- otros permisos ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select pg_temp.rows('solo exports.read: no ve la trazabilidad', $q$select * from public.export_traceability$q$, 0);
select pg_temp.rows('solo exports.read: no ve las fincas de origen', $q$select * from public.export_origin_farms$q$, 0);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
select pg_temp.rows('solo farms.read: no ve la trazabilidad', $q$select * from public.export_traceability$q$, 0);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b4","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: no ve la trazabilidad', $q$select * from public.export_traceability$q$, 0);
select pg_temp.rows('sin permisos: no ve las fincas de origen', $q$select * from public.export_origin_farms$q$, 0);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b5","role":"authenticated"}', true);
select pg_temp.rows('desactivado: no ve la trazabilidad', $q$select * from public.export_traceability$q$, 0);

-- solo lectura
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select pg_temp.attempt('no se inserta por la vista', $q$insert into public.export_traceability(export_id) values (1)$q$, 'cannot insert into view');
select pg_temp.attempt('no se actualiza por la vista', $q$update public.export_traceability set quantity = 1$q$, 'cannot update view');
select pg_temp.attempt('no se borra por la vista', $q$delete from public.export_origin_farms$q$, 'cannot delete from view');
reset role;
set local role anon;
select pg_temp.attempt('anonimo: no lee la trazabilidad', $q$select * from public.export_traceability$q$, 'permission denied');
select pg_temp.attempt('anonimo: no lee las fincas de origen', $q$select * from public.export_origin_farms$q$, 'permission denied');
reset role;

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select to_regclass('public.export') as export_tras_rollback, to_regclass('public.export_traceability') as vista_tras_rollback;
