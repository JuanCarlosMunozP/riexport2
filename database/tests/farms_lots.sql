-- Pruebas de fincas, lotes y validacion de coordenadas (PLAT-513/514/515). Todo se revierte al final.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/farms_lots.sql
-- Requiere las migraciones 20261008000700, 20261009000000 y 20261010000000 aplicadas.
-- Usuarios: fw (todo lo necesario), fr (solo farms.read y lots.read), fn (sin permisos), fo (desactivado).

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

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default '') returns void
language sql as $$
  insert into resultados(prueba, resultado)
  values (p_name, case when p_ok then 'OK' else 'FALLA: ' || p_detail end);
$$;

-- ------------------------------------------------------------------------ usuarios y roles ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'fw@farm.test', '{"first_name":"Escribe","last_name":"Fincas"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'fr@farm.test', '{"first_name":"Lee","last_name":"Fincas"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'fn@farm.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a4', 'authenticated', 'authenticated', 'fo@farm.test', '{"first_name":"Desactivado","last_name":"Fincas"}', now(), now());

insert into public.role(name) values ('f_write'), ('f_read');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['farms.read','farms.create','farms.update','lots.read','lots.create',
  'suppliers.read','suppliers.create','suppliers.update','products.read','products.create','products.update']) p
 where r.name = 'f_write';
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['farms.read','lots.read']) p where r.name = 'f_read';
update public.profile set role_id = (select id from public.role where name = 'f_write') where email in ('fw@farm.test', 'fo@farm.test');
update public.profile set role_id = (select id from public.role where name = 'f_read') where email = 'fr@farm.test';
update public.profile set is_active = false where email = 'fo@farm.test';

select pg_temp.check('semilla: 5 permisos de fincas y lotes',
  (select count(*) from public.permission where code like 'farms.%' or code like 'lots.%') = 5);

-- ------------------------------------------------------------------ datos base (como fw) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select public.create_supplier('{"business_name":"Proveedor Uno","tax_id":"NIT-0001"}');
select public.create_supplier('{"business_name":"Proveedor Dos","tax_id":"NIT-0002"}');
select public.create_supplier('{"business_name":"Proveedor Inactivo","tax_id":"NIT-0003"}');
select public.set_supplier_active((select id from public.supplier where tax_id = 'NIT-0003'), false);
select public.create_product('{"type":"coffee","variety":"Caturra","quality_grade":"Excelso","base_unit_code":"kg","humidity_percent":11}');
select public.create_product('{"type":"cacao","variety":"Criollo","quality_grade":"Premium","base_unit_code":"kg","bean_type":"Fino","fermentation_percent":80}');
select public.set_product_active((select id from public.product where variety = 'Criollo'), false);

-- ------------------------------------------------------------------------ sin permisos (fn) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: no ve fincas', $q$select * from public.farm$q$, 0);
select pg_temp.rows('sin permisos: el catalogo de fincas no devuelve nada', $q$select * from public.farm_catalog$q$, 0);
select pg_temp.rows('sin permisos: el catalogo de lotes no devuelve nada', $q$select * from public.lot_catalog$q$, 0);
select pg_temp.attempt('sin permisos: no registra fincas', $q$select public.create_farm('{"supplier_id":1,"country_code":"CO","name":"X"}')$q$, 'No tienes permiso');
select pg_temp.attempt('sin permisos: no registra lotes', $q$select public.create_lot('{"product_id":1,"farm_id":1,"lot_code":"L1"}')$q$, 'No tienes permiso');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
select pg_temp.attempt('desactivado: no registra fincas', $q$select public.create_farm('{"supplier_id":1,"country_code":"CO","name":"X"}')$q$, 'No tienes permiso');

-- ----------------------------------------------------------------------------- con permisos (fw) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select pg_temp.attempt('registra una finca con coordenadas', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'co', 'name', '  La Esperanza ', 'address', 'Vereda Alta, Huila', 'latitude', 2.535, 'longitude', -75.527))$q$, 'ok');
select pg_temp.attempt('registra una finca sin coordenadas', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'Sin punto'))$q$, 'ok');
select pg_temp.attempt('coordenadas como texto con coma decimal', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0002'), 'country_code', 'EC', 'name', 'Texto', 'latitude', '-1,5', 'longitude', '-78,25'))$q$, 'ok');
select pg_temp.check('se guardan limpias: pais en mayusculas, nombre recortado y punto exacto',
  (select country_code = 'CO' and name = 'La Esperanza' and latitude = 2.535 and longitude = -75.527 and is_active
     from public.farm where name = 'La Esperanza'));
select pg_temp.check('la coma decimal se interpreta bien',
  (select latitude = -1.5 and longitude = -78.25 from public.farm where name = 'Texto'));
select pg_temp.check('el catalogo une el proveedor y cuenta lotes',
  (select supplier_name = 'Proveedor Uno' and lot_count = 0 from public.farm_catalog where name = 'La Esperanza'));

-- coordenadas (PLAT-515)
select pg_temp.attempt('latitud mayor a 90', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A1', 'latitude', 90.5, 'longitude', 10))$q$, 'latitud debe estar entre -90 y 90');
select pg_temp.attempt('latitud menor a -90', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A2', 'latitude', -91, 'longitude', 10))$q$, 'latitud debe estar entre');
select pg_temp.attempt('longitud mayor a 180', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A3', 'latitude', 10, 'longitude', 180.1))$q$, 'longitud debe estar entre -180 y 180');
select pg_temp.attempt('longitud menor a -180', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A4', 'latitude', 10, 'longitude', -181))$q$, 'longitud debe estar entre');
select pg_temp.attempt('los limites exactos son validos', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0002'), 'country_code', 'CO', 'name', 'Limite', 'latitude', 90, 'longitude', -180))$q$, 'ok');
select pg_temp.attempt('solo latitud', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A5', 'latitude', 10))$q$, 'juntas, o ninguna');
select pg_temp.attempt('solo longitud', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A6', 'longitude', 10))$q$, 'juntas, o ninguna');
select pg_temp.attempt('punto (0, 0) rechazado', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A7', 'latitude', 0, 'longitude', 0))$q$, '(0, 0)');
select pg_temp.attempt('latitud 0 con longitud distinta de 0 es valida', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0002'), 'country_code', 'EC', 'name', 'Ecuador', 'latitude', 0, 'longitude', -78.5))$q$, 'ok');
select pg_temp.attempt('mas de 6 decimales', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A8', 'latitude', 2.1234567, 'longitude', 10))$q$, 'máximo 6 decimales');
select pg_temp.attempt('latitud no numerica', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'A9', 'latitude', 'abc', 'longitude', 10))$q$, 'número válido');
select pg_temp.attempt('latitud booleana', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'B1', 'latitude', true, 'longitude', 10))$q$, 'debe ser un número');

-- otros datos de la finca
select pg_temp.attempt('proveedor obligatorio', $q$select public.create_farm('{"country_code":"CO","name":"C1"}')$q$, 'proveedor es obligatorio');
select pg_temp.attempt('proveedor inexistente', $q$select public.create_farm('{"supplier_id":99999,"country_code":"CO","name":"C2"}')$q$, 'proveedor no existe');
select pg_temp.attempt('proveedor inactivo', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0003'), 'country_code', 'CO', 'name', 'C3'))$q$, 'proveedor está inactivo');
select pg_temp.attempt('pais obligatorio', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'name', 'C4'))$q$, 'país es obligatorio');
select pg_temp.attempt('pais invalido', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'Col', 'name', 'C5'))$q$, 'país');
select pg_temp.attempt('nombre obligatorio', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', '  '))$q$, 'nombre de la finca es obligatorio');
select pg_temp.attempt('nombre duplicado en el mismo proveedor', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'LA ESPERANZA'))$q$, 'ya tiene una finca con ese nombre');
select pg_temp.attempt('el mismo nombre en otro proveedor es valido', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0002'), 'country_code', 'CO', 'name', 'La Esperanza'))$q$, 'ok');
select pg_temp.attempt('campo ajeno rechazado', $q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'C6', 'is_active', false))$q$, 'Campo no permitido');
select pg_temp.attempt('direccion demasiado larga', format($q$select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0001'), 'country_code', 'CO', 'name', 'C7', 'address', '%s'))$q$, repeat('x', 301)), 'máximo 300');
select pg_temp.rows('los intentos rechazados no dejan filas', $q$select * from public.farm$q$, 6);

-- los CHECK de la tabla protegen aunque se escriba sin pasar por las funciones
reset role;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('CHECK: latitud fuera de rango por SQL', $q$insert into public.farm(supplier_id, country_code, name, latitude, longitude) values ((select min(id) from public.supplier), 'CO', 'Directa1', 95, 10)$q$, 'violates check');
select pg_temp.attempt('CHECK: longitud fuera de rango por SQL', $q$insert into public.farm(supplier_id, country_code, name, latitude, longitude) values ((select min(id) from public.supplier), 'CO', 'Directa2', 10, 200)$q$, 'violates check');
select pg_temp.attempt('CHECK: par incompleto por SQL', $q$insert into public.farm(supplier_id, country_code, name, latitude) values ((select min(id) from public.supplier), 'CO', 'Directa3', 10)$q$, 'farm_point_complete');
select pg_temp.attempt('CHECK: punto (0, 0) por SQL', $q$insert into public.farm(supplier_id, country_code, name, latitude, longitude) values ((select min(id) from public.supplier), 'CO', 'Directa4', 0, 0)$q$, 'farm_point_not_origin');
select pg_temp.attempt('CHECK: pais invalido por SQL', $q$insert into public.farm(supplier_id, country_code, name) values ((select min(id) from public.supplier), 'col', 'Directa5')$q$, 'violates check');
select pg_temp.attempt('la precision de NUMERIC(9,6) no admite mas enteros', $q$insert into public.farm(supplier_id, country_code, name, latitude, longitude) values ((select min(id) from public.supplier), 'CO', 'Directa6', 1000, 10)$q$, 'numeric field overflow');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

-- edicion
select pg_temp.attempt('edita nombre y coordenadas', $q$select public.update_farm((select id from public.farm where name = 'Sin punto'), '{"name":"Con punto","latitude":4.5,"longitude":-74.1}')$q$, 'ok');
select pg_temp.check('la edicion se guarda', (select latitude = 4.5 and longitude = -74.1 from public.farm where name = 'Con punto'));
select pg_temp.attempt('quitar el punto: ambos nulos', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), '{"latitude":null,"longitude":null}')$q$, 'ok');
select pg_temp.check('el punto queda ausente', (select latitude is null and longitude is null from public.farm where name = 'Con punto'));
select pg_temp.attempt('quitar solo una coordenada', $q$select public.update_farm((select id from public.farm where name = 'La Esperanza' and supplier_id = (select id from public.supplier where tax_id = 'NIT-0001')), '{"latitude":null}')$q$, 'juntas, o ninguna');
select pg_temp.attempt('edicion con latitud fuera de rango', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), '{"latitude":100,"longitude":10}')$q$, 'latitud debe estar entre');
select pg_temp.attempt('edicion al punto (0, 0)', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), '{"latitude":0,"longitude":0}')$q$, '(0, 0)');
select pg_temp.check('los rechazos no cambiaron la finca', (select latitude is null from public.farm where name = 'Con punto'));
select pg_temp.attempt('nombre duplicado al editar', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), '{"name":"la esperanza"}')$q$, 'ya tiene una finca con ese nombre');
select pg_temp.attempt('no cambia de proveedor (funcion)', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-0002')))$q$, 'otro proveedor');
select pg_temp.attempt('sin campos', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), '{}')$q$, 'al menos un campo');
select pg_temp.attempt('finca inexistente', $q$select public.update_farm(99999, '{"name":"X"}')$q$, 'No se encontró');
select pg_temp.attempt('editar sin cambios no falla', $q$select public.update_farm((select id from public.farm where name = 'Con punto'), '{"name":"Con punto"}')$q$, 'ok');

-- inactivacion
select pg_temp.attempt('inactiva una finca', $q$select public.set_farm_active((select id from public.farm where name = 'Con punto'), false)$q$, 'ok');
select pg_temp.check('la finca inactiva sigue consultable', (select not is_active from public.farm_catalog where name = 'Con punto'));
select pg_temp.attempt('estado nulo', $q$select public.set_farm_active((select id from public.farm where name = 'Con punto'), null)$q$, 'debe quedar activa');
select pg_temp.attempt('finca inexistente al inactivar', $q$select public.set_farm_active(99999, false)$q$, 'No se encontró');

-- lotes
select pg_temp.attempt('registra un lote', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'La Esperanza' and supplier_id = (select id from public.supplier where tax_id = 'NIT-0001')), 'lot_code', '  L-2026-01 '))$q$, 'ok');
select pg_temp.check('el catalogo de lotes trae la geolocalizacion de la finca',
  (select lot_code = 'L-2026-01' and latitude = 2.535 and longitude = -75.527 and product_variety = 'Caturra' and supplier_name = 'Proveedor Uno'
     from public.lot_catalog));
select pg_temp.check('la finca cuenta su lote', (select lot_count = 1 from public.farm_catalog where name = 'La Esperanza' and supplier_id = (select id from public.supplier where tax_id = 'NIT-0001')));
select pg_temp.attempt('codigo de lote duplicado en la finca', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'La Esperanza' and supplier_id = (select id from public.supplier where tax_id = 'NIT-0001')), 'lot_code', 'l-2026-01'))$q$, 'ya tiene un lote con ese código');
select pg_temp.attempt('el mismo codigo en otra finca es valido', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'Texto'), 'lot_code', 'L-2026-01'))$q$, 'ok');
select pg_temp.attempt('lote en una finca inactiva', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'Con punto'), 'lot_code', 'L-X'))$q$, 'finca está inactiva');
select pg_temp.attempt('lote con un producto inactivo', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Criollo'), 'farm_id', (select id from public.farm where name = 'Texto'), 'lot_code', 'L-Y'))$q$, 'producto está inactivo');
select pg_temp.attempt('lote con producto inexistente', $q$select public.create_lot(jsonb_build_object('product_id', 99999, 'farm_id', (select id from public.farm where name = 'Texto'), 'lot_code', 'L-Z'))$q$, 'producto no existe');
select pg_temp.attempt('lote con finca inexistente', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', 99999, 'lot_code', 'L-Z'))$q$, 'finca no existe');
select pg_temp.attempt('codigo de lote obligatorio', $q$select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra'), 'farm_id', (select id from public.farm where name = 'Texto'), 'lot_code', ' '))$q$, 'código del lote es obligatorio');
select pg_temp.attempt('producto obligatorio', $q$select public.create_lot('{"farm_id":1,"lot_code":"A"}')$q$, 'producto es obligatorio');
select pg_temp.attempt('finca obligatoria', $q$select public.create_lot('{"product_id":1,"lot_code":"A"}')$q$, 'finca es obligatoria');
select pg_temp.attempt('campo ajeno en el lote', $q$select public.create_lot('{"product_id":1,"farm_id":1,"lot_code":"A","latitude":1}')$q$, 'Campo no permitido');
select pg_temp.rows('los lotes rechazados no dejan filas', $q$select * from public.product_lot$q$, 2);

-- ------------------------------------------------------------------------- solo lectura (fr) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
select pg_temp.rows('lectura: ve las fincas', $q$select * from public.farm_catalog$q$, 6);
select pg_temp.rows('lectura: ve los lotes', $q$select * from public.lot_catalog$q$, 2);
select pg_temp.rows('lectura: lee la tabla de fincas', $q$select * from public.farm$q$, 6);
select pg_temp.rows('lectura: no ve proveedores (sin suppliers.read) pero si el nombre en el catalogo', $q$select * from public.supplier$q$, 0);
select pg_temp.attempt('lectura: no registra fincas', $q$select public.create_farm('{"supplier_id":1,"country_code":"CO","name":"X"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no edita fincas', $q$select public.update_farm(1, '{"name":"X"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no inactiva fincas', $q$select public.set_farm_active(1, false)$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no registra lotes', $q$select public.create_lot('{"product_id":1,"farm_id":1,"lot_code":"A"}')$q$, 'No tienes permiso');
select pg_temp.attempt('escritura directa denegada: insert de finca', $q$insert into public.farm(supplier_id, country_code, name) values (1, 'CO', 'X')$q$, 'permission denied');
select pg_temp.attempt('escritura directa denegada: update de finca', $q$update public.farm set name = 'X'$q$, 'permission denied');
select pg_temp.attempt('escritura directa denegada: insert de lote', $q$insert into public.product_lot(product_id, farm_id, lot_code) values (1, 1, 'X')$q$, 'permission denied');
select pg_temp.attempt('borrado directo denegado: finca', $q$delete from public.farm$q$, 'permission denied');
select pg_temp.attempt('borrado directo denegado: lote', $q$delete from public.product_lot$q$, 'permission denied');

reset role;
set local role anon;
select pg_temp.attempt('anonimo: no lee fincas', $q$select * from public.farm$q$, 'permission denied');
select pg_temp.attempt('anonimo: no lee el catalogo de lotes', $q$select * from public.lot_catalog$q$, 'permission denied');
select pg_temp.attempt('anonimo: no ejecuta create_farm', $q$select public.create_farm('{}')$q$, 'permission denied');
reset role;

-- el propietario tampoco borra ni modifica lotes: lo impiden los triggers
select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('nadie borra fincas (ni el propietario)', $q$delete from public.farm$q$, 'no se borran');
select pg_temp.attempt('nadie borra lotes (ni el propietario)', $q$delete from public.product_lot$q$, 'no se borran');
select pg_temp.attempt('un lote no se modifica (ni el propietario)', $q$update public.product_lot set lot_code = 'OTRO'$q$, 'no se modifica');
select pg_temp.attempt('la finca no cambia de proveedor ni por SQL', $q$update public.farm set supplier_id = (select max(id) from public.supplier) where supplier_id = (select min(id) from public.supplier)$q$, 'otro proveedor');

-- ----------------------------------------------------------------------------------- auditoria ---
select pg_temp.check('auditoria: altas de finca', (select count(*) = 6 from public.audit_log where action = 'farm.created'));
select pg_temp.check('auditoria: la alta no guarda las coordenadas, solo si hay geolocalizacion',
  (select count(*) = 0 from public.audit_log where action = 'farm.created' and metadata::text ~ '2\.535|75\.527')
  and (select count(*) = 2 from public.audit_log where action = 'farm.created' and (metadata ->> 'geolocated') = 'false'));
select pg_temp.check('auditoria: ediciones con los campos cambiados',
  (select count(*) = 2 from public.audit_log where action = 'farm.updated' and metadata ? 'fields'));
select pg_temp.check('auditoria: inactivacion', (select count(*) = 1 from public.audit_log where action = 'farm.inactivated'));
select pg_temp.check('auditoria: altas de lote', (select count(*) = 2 from public.audit_log where action = 'lot.created'));

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select (select count(*) from public.farm) as fincas_tras_rollback, (select count(*) from public.product_lot) as lotes_tras_rollback;
