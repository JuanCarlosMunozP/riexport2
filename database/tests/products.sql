-- Pruebas del modulo de productos (EP-2). Todo se revierte al final: no queda ningun dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/products.sql
-- Requiere la migracion 20261008000700 aplicada (o ejecutada dentro de la misma transaccion).
-- Usuarios: pw (products.read/create/update), pr (solo products.read), pn (sin permisos),
-- po (con permisos pero desactivado).

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

-- --------------------------------------------------------------------- usuarios y roles ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'pw@prod.test', '{"first_name":"Escribe","last_name":"Productos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'pr@prod.test', '{"first_name":"Lee","last_name":"Productos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'pn@prod.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e4', 'authenticated', 'authenticated', 'po@prod.test', '{"first_name":"Desactivado","last_name":"Productos"}', now(), now());

insert into public.role(name) values ('p_write'), ('p_read');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['products.read','products.create','products.update']) p where r.name = 'p_write';
insert into public.role_permission(role_id, permission_code)
select r.id, 'products.read' from public.role r where r.name = 'p_read';
update public.profile set role_id = (select id from public.role where name = 'p_write') where email in ('pw@prod.test', 'po@prod.test');
update public.profile set role_id = (select id from public.role where name = 'p_read') where email = 'pr@prod.test';
update public.profile set is_active = false where email = 'po@prod.test';

-- una certificacion inactiva para las pruebas de asignacion
insert into public.certification(code, name, is_active) values ('LEGACY_SEAL', 'Sello heredado', false);

-- ---------------------------------------------------------------- catalogos de referencia ---
select pg_temp.check('semilla: 2 unidades de medida (kg, t)',
  (select count(*) from public.unit_of_measure where code in ('kg', 't')) = 2);
select pg_temp.check('semilla: 3 certificaciones base activas',
  (select count(*) from public.certification where code in ('ORGANIC','FAIR_TRADE','RAINFOREST_ALLIANCE') and is_active) = 3);

-- ----------------------------------------------------------------- sin permisos de producto ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: ve las unidades (catalogo de referencia)', $q$select * from public.unit_of_measure$q$, 2);
select pg_temp.rows('sin permisos: ve las certificaciones', $q$select * from public.certification$q$, 4);
select pg_temp.rows('sin permisos: no ve productos', $q$select * from public.product$q$, 0);
select pg_temp.rows('sin permisos: el catalogo no devuelve nada', $q$select * from public.product_catalog$q$, 0);
select pg_temp.attempt('sin permisos: no crea productos', $q$select public.create_product('{"type":"coffee","variety":"X","quality_grade":"Y","base_unit_code":"kg","humidity_percent":10}')$q$, 'No tienes permiso');

-- ------------------------------------------------------------------------ solo lectura (pr) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
select pg_temp.attempt('lectura: no crea productos', $q$select public.create_product('{"type":"coffee","variety":"X","quality_grade":"Y","base_unit_code":"kg","humidity_percent":10}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no edita productos', $q$select public.update_product(1, '{"variety":"Z"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no inactiva productos', $q$select public.set_product_active(1, false)$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no asocia certificaciones', $q$select public.set_product_certifications(1, '{1}')$q$, 'No tienes permiso');

-- -------------------------------------------------------------------------- registro de cafe ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);

select pg_temp.attempt('cafe valido con certificaciones', $q$select public.create_product(jsonb_build_object(
  'type','coffee','variety','Caturra','quality_grade','Excelso','hs_code','0901.11','base_unit_code','kg',
  'low_stock_threshold',500,'humidity_percent',11.5,
  'certification_ids', (select jsonb_agg(id) from public.certification where code in ('ORGANIC','FAIR_TRADE'))))$q$, 'ok');
select pg_temp.attempt('cafe valido minimo (sin HS, umbral ni certificaciones)', $q$select public.create_product('{"type":"coffee","variety":"Castillo","quality_grade":"Supremo","base_unit_code":"kg","humidity_percent":"12"}')$q$, 'ok');
select pg_temp.attempt('duplicado (mismo tipo, variedad y calidad sin distinguir mayusculas)', $q$select public.create_product('{"type":"coffee","variety":"CATURRA","quality_grade":"excelso","base_unit_code":"kg","humidity_percent":10}')$q$, 'Ya existe un producto');
select pg_temp.attempt('el mismo nombre en otro tipo no es duplicado', $q$select public.create_product('{"type":"cacao","variety":"Caturra","quality_grade":"Excelso","base_unit_code":"kg","bean_type":"Criollo","fermentation_percent":80}')$q$, 'ok');
select pg_temp.attempt('tipo invalido', $q$select public.create_product('{"type":"te","variety":"A","quality_grade":"B","base_unit_code":"kg"}')$q$, 'debe ser café o cacao');
select pg_temp.attempt('falta la variedad', $q$select public.create_product('{"type":"coffee","quality_grade":"B","base_unit_code":"kg","humidity_percent":10}')$q$, 'variedad es obligatoria');
select pg_temp.attempt('falta la calidad', $q$select public.create_product('{"type":"coffee","variety":"A","base_unit_code":"kg","humidity_percent":10}')$q$, 'calidad es obligatoria');
select pg_temp.attempt('falta la humedad del cafe', $q$select public.create_product('{"type":"coffee","variety":"A","quality_grade":"B","base_unit_code":"kg"}')$q$, 'humedad es obligatoria');
select pg_temp.attempt('humedad fuera de rango (101)', $q$select public.create_product('{"type":"coffee","variety":"A1","quality_grade":"B","base_unit_code":"kg","humidity_percent":101}')$q$, 'entre 0 y 100');
select pg_temp.attempt('humedad negativa', $q$select public.create_product('{"type":"coffee","variety":"A2","quality_grade":"B","base_unit_code":"kg","humidity_percent":-1}')$q$, 'entre 0 y 100');
select pg_temp.attempt('humedad que no es numero', $q$select public.create_product('{"type":"coffee","variety":"A3","quality_grade":"B","base_unit_code":"kg","humidity_percent":"abc"}')$q$, 'número válido');
select pg_temp.attempt('unidad base inexistente', $q$select public.create_product('{"type":"coffee","variety":"A4","quality_grade":"B","base_unit_code":"lb","humidity_percent":10}')$q$, 'unidad base no existe');
select pg_temp.attempt('codigo HS con formato invalido', $q$select public.create_product('{"type":"coffee","variety":"A5","quality_grade":"B","hs_code":"09","base_unit_code":"kg","humidity_percent":10}')$q$, 'código HS');
select pg_temp.attempt('umbral negativo', $q$select public.create_product('{"type":"coffee","variety":"A6","quality_grade":"B","base_unit_code":"kg","humidity_percent":10,"low_stock_threshold":-5}')$q$, 'no puede ser negativo');
select pg_temp.attempt('campos de cacao en un cafe se rechazan', $q$select public.create_product('{"type":"coffee","variety":"A7","quality_grade":"B","base_unit_code":"kg","humidity_percent":10,"bean_type":"Criollo"}')$q$, 'Campo no permitido');
select pg_temp.attempt('campo desconocido se rechaza', $q$select public.create_product('{"type":"coffee","variety":"A8","quality_grade":"B","base_unit_code":"kg","humidity_percent":10,"precio":5}')$q$, 'Campo no permitido');
select pg_temp.attempt('certificacion inexistente', $q$select public.create_product('{"type":"coffee","variety":"A9","quality_grade":"B","base_unit_code":"kg","humidity_percent":10,"certification_ids":[9999]}')$q$, 'no existen o están inactivas');
select pg_temp.attempt('certificacion inactiva no se asigna al crear', $q$select public.create_product(jsonb_build_object('type','coffee','variety','B1','quality_grade','B','base_unit_code','kg','humidity_percent',10,'certification_ids', (select jsonb_agg(id) from public.certification where code = 'LEGACY_SEAL')))$q$, 'no existen o están inactivas');
select pg_temp.attempt('certificaciones duplicadas', $q$select public.create_product(jsonb_build_object('type','coffee','variety','B2','quality_grade','B','base_unit_code','kg','humidity_percent',10,'certification_ids', (select jsonb_build_array(min(id), min(id)) from public.certification where code = 'ORGANIC')))$q$, 'duplicadas');
select pg_temp.rows('atomicidad: los intentos fallidos no dejaron productos a medias', $q$select * from public.product where variety in ('A','A1','A2','A3','A4','A5','A6','A7','A8','A9','B1','B2')$q$, 0);

-- -------------------------------------------------------------------------- registro de cacao ---
select pg_temp.attempt('cacao valido', $q$select public.create_product('{"type":"cacao","variety":"Criollo","quality_grade":"Premium","hs_code":"1801.00","base_unit_code":"t","bean_type":"Criollo fino","fermentation_percent":85.5}')$q$, 'ok');
select pg_temp.attempt('falta el tipo de grano del cacao', $q$select public.create_product('{"type":"cacao","variety":"C1","quality_grade":"P","base_unit_code":"kg","fermentation_percent":80}')$q$, 'tipo de grano es obligatorio');
select pg_temp.attempt('falta la fermentacion del cacao', $q$select public.create_product('{"type":"cacao","variety":"C2","quality_grade":"P","base_unit_code":"kg","bean_type":"Forastero"}')$q$, 'fermentación es obligatorio');
select pg_temp.attempt('fermentacion fuera de rango (100.5)', $q$select public.create_product('{"type":"cacao","variety":"C3","quality_grade":"P","base_unit_code":"kg","bean_type":"Forastero","fermentation_percent":100.5}')$q$, 'entre 0 y 100');
select pg_temp.attempt('humedad en un cacao se rechaza', $q$select public.create_product('{"type":"cacao","variety":"C4","quality_grade":"P","base_unit_code":"kg","bean_type":"Forastero","fermentation_percent":80,"humidity_percent":10}')$q$, 'Campo no permitido');

-- -------------------------------------------------------------------------------- consulta (vista) ---
select pg_temp.rows('catalogo: 4 productos creados', $q$select * from public.product_catalog$q$, 4);
select pg_temp.rows('catalogo: filtra por tipo cafe', $q$select * from public.product_catalog where type = 'coffee'$q$, 2);
select pg_temp.rows('catalogo: filtra por tipo cacao', $q$select * from public.product_catalog where type = 'cacao'$q$, 2);
select pg_temp.rows('catalogo: filtra por certificacion (organico)', $q$select * from public.product_catalog where certification_ids @> (select array[id] from public.certification where code = 'ORGANIC')$q$, 1);
select pg_temp.rows('catalogo: busca por calidad (sin distinguir mayusculas)', $q$select * from public.product_catalog where quality_grade ilike '%excel%'$q$, 2);
select pg_temp.check('catalogo: muestra las certificaciones como lista con nombre',
  (select jsonb_array_length(certifications) = 2 and certifications @> '[{"code":"ORGANIC"}]'::jsonb from public.product_catalog where variety = 'Caturra' and type = 'coffee'));
select pg_temp.check('catalogo: trae la unidad base y los atributos del tipo',
  (select base_unit_name = 'Tonelada métrica' and bean_type = 'Criollo fino' and fermentation_percent = 85.5 and humidity_percent is null
     from public.product_catalog where variety = 'Criollo'));
select pg_temp.check('catalogo: el cafe trae humedad y no atributos de cacao',
  (select humidity_percent = 11.5 and bean_type is null from public.product_catalog where variety = 'Caturra' and type = 'coffee'));

-- ----------------------------------------------------------------------------------- edicion ---
select pg_temp.attempt('edita calidad y umbral', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"quality_grade":"Extra","low_stock_threshold":1200}')$q$, 'ok');
select pg_temp.check('la edicion se refleja en el catalogo',
  (select quality_grade = 'Extra' and low_stock_threshold = 1200 from public.product_catalog where variety = 'Castillo'));
select pg_temp.attempt('edita la humedad del cafe', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"humidity_percent":10}')$q$, 'ok');
select pg_temp.attempt('edita el detalle del cacao', $q$select public.update_product((select id from public.product where variety = 'Criollo'), '{"bean_type":"Trinitario","fermentation_percent":70}')$q$, 'ok');
select pg_temp.attempt('borra el codigo HS con null', $q$select public.update_product((select id from public.product where variety = 'Caturra' and type = 'coffee'), '{"hs_code":null}')$q$, 'ok');
select pg_temp.attempt('no cambia el tipo', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"type":"cacao"}')$q$, 'tipo de producto no se puede cambiar');
select pg_temp.attempt('no cambia la unidad base', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"base_unit_code":"t"}')$q$, 'unidad base no se puede cambiar');
select pg_temp.attempt('enviar el mismo tipo y unidad es valido', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"type":"coffee","base_unit_code":"kg","variety":"Castillo"}')$q$, 'ok');
select pg_temp.attempt('un cafe no admite campos de cacao', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"bean_type":"x"}')$q$, 'Campo no permitido');
select pg_temp.attempt('un cacao no admite humedad', $q$select public.update_product((select id from public.product where variety = 'Criollo'), '{"humidity_percent":10}')$q$, 'Campo no permitido');
select pg_temp.attempt('humedad invalida al editar', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"humidity_percent":150}')$q$, 'entre 0 y 100');
select pg_temp.attempt('la edicion no puede duplicar otro producto', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{"variety":"Caturra","quality_grade":"Excelso"}')$q$, 'Ya existe un producto');
select pg_temp.attempt('producto inexistente', $q$select public.update_product(99999, '{"variety":"Z"}')$q$, 'No se encontró');
select pg_temp.attempt('edicion vacia', $q$select public.update_product((select id from public.product where variety = 'Castillo'), '{}')$q$, 'al menos un campo');

-- --------------------------------------------------------------------------------- inactivacion ---
select pg_temp.attempt('inactiva un producto', $q$select public.set_product_active((select id from public.product where variety = 'Castillo'), false)$q$, 'ok');
select pg_temp.check('el producto inactivo sigue consultable en el catalogo',
  (select not is_active from public.product_catalog where variety = 'Castillo'));
select pg_temp.rows('catalogo: filtra solo activos', $q$select * from public.product_catalog where is_active$q$, 3);
select pg_temp.attempt('reactiva el producto', $q$select public.set_product_active((select id from public.product where variety = 'Castillo'), true)$q$, 'ok');
select pg_temp.attempt('inactivar un producto inexistente', $q$select public.set_product_active(99999, false)$q$, 'No se encontró');

-- ------------------------------------------------------------------------------ certificaciones ---
select pg_temp.attempt('reemplaza las certificaciones de un producto', $q$select public.set_product_certifications((select id from public.product where variety = 'Castillo'), (select array_agg(id) from public.certification where code in ('RAINFOREST_ALLIANCE','FAIR_TRADE')))$q$, 'ok');
select pg_temp.rows('queda con 2 certificaciones', $q$select * from public.product_certification where product_id = (select id from public.product where variety = 'Castillo')$q$, 2);
select pg_temp.attempt('quita todas las certificaciones', $q$select public.set_product_certifications((select id from public.product where variety = 'Castillo'), '{}')$q$, 'ok');
select pg_temp.rows('queda sin certificaciones', $q$select * from public.product_certification where product_id = (select id from public.product where variety = 'Castillo')$q$, 0);
select pg_temp.attempt('certificaciones duplicadas al asociar', $q$select public.set_product_certifications((select id from public.product where variety = 'Castillo'), (select array[min(id), min(id)] from public.certification where code = 'ORGANIC'))$q$, 'duplicadas');
select pg_temp.attempt('certificacion inexistente al asociar', $q$select public.set_product_certifications((select id from public.product where variety = 'Castillo'), '{9999}')$q$, 'no existen');
select pg_temp.attempt('una certificacion inactiva no se asigna de nuevo', $q$select public.set_product_certifications((select id from public.product where variety = 'Castillo'), (select array_agg(id) from public.certification where code = 'LEGACY_SEAL'))$q$, 'inactivas');
select pg_temp.attempt('asociar a un producto inexistente', $q$select public.set_product_certifications(99999, '{1}')$q$, 'No se encontró');

-- ------------------------------------------------- escritura directa y borrado: prohibidos ---
select pg_temp.attempt('no se inserta directo en product', $q$insert into public.product(type,variety,quality_grade,base_unit_code) values ('coffee','Z','Z','kg')$q$, 'permission denied');
select pg_temp.attempt('no se actualiza directo product', $q$update public.product set variety = 'Z'$q$, 'permission denied');
select pg_temp.attempt('no se borra directo product (privilegio)', $q$delete from public.product$q$, 'permission denied');
select pg_temp.attempt('no se escribe directo en certification', $q$insert into public.certification(code,name) values ('NUEVA','Nueva')$q$, 'permission denied');
select pg_temp.attempt('no se escribe directo en el detalle', $q$update public.coffee_detail set humidity_percent = 1$q$, 'permission denied');
select pg_temp.attempt('la vista de catalogo no admite escrituras', $q$update public.product_catalog set variety = 'Z'$q$, 'cannot update view');

-- --------------------------------------------------------------- desactivado y anonimo ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
select pg_temp.rows('desactivado (con permisos): no ve el catalogo', $q$select * from public.product_catalog$q$, 0);
select pg_temp.rows('desactivado: no ve ni las unidades', $q$select * from public.unit_of_measure$q$, 0);
select pg_temp.attempt('desactivado: no crea productos', $q$select public.create_product('{"type":"coffee","variety":"D1","quality_grade":"B","base_unit_code":"kg","humidity_percent":10}')$q$, 'No tienes permiso');

reset role;
set local role anon;
select pg_temp.attempt('anonimo no lee productos', $q$select * from public.product$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee el catalogo', $q$select * from public.product_catalog$q$, 'permission denied');
select pg_temp.attempt('anonimo no ejecuta create_product', $q$select public.create_product('{}')$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee las certificaciones', $q$select * from public.certification$q$, 'permission denied');

-- ------------------------------------------------------- integridad que protege incluso al propietario ---
reset role;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('nadie borra productos (ni el propietario)', $q$delete from public.product$q$, 'se inactivan');
select pg_temp.attempt('nadie borra detalles (ni el propietario)', $q$delete from public.coffee_detail$q$, 'se inactivan');
select pg_temp.attempt('el tipo no cambia ni por SQL', $q$update public.product set type = 'cacao' where variety = 'Castillo'$q$, 'tipo de producto no se puede cambiar');
select pg_temp.attempt('la unidad no cambia ni por SQL', $q$update public.product set base_unit_code = 't' where variety = 'Castillo'$q$, 'unidad base no se puede cambiar');
select pg_temp.attempt('el detalle debe corresponder al tipo (cacao con detalle de cafe)', $q$insert into public.coffee_detail(product_id, humidity_percent) select id, 10 from public.product where type = 'cacao' and variety = 'Criollo'$q$, 'no corresponde al tipo');
select pg_temp.attempt('un producto sin detalle falla al cerrar la transaccion', $q$do $do$ begin
    insert into public.product(type, variety, quality_grade, base_unit_code) values ('coffee', 'SinDetalle', 'X', 'kg');
    set constraints all immediate;
  end $do$$q$, 'necesita su detalle');
select pg_temp.attempt('un cacao sin detalle falla al cerrar la transaccion', $q$do $do$ begin
    insert into public.product(type, variety, quality_grade, base_unit_code) values ('cacao', 'SinDetalle2', 'X', 'kg');
    set constraints all immediate;
  end $do$$q$, 'necesita su detalle');
select pg_temp.attempt('CHECK de la base: humedad fuera de rango por SQL', $q$update public.coffee_detail set humidity_percent = 120$q$, 'violates check');

-- ---------------------------------------------------------------------------------- auditoria ---
select pg_temp.check('auditoria: registra creaciones',
  (select count(*) = 4 from public.audit_log where action = 'product.created'));
select pg_temp.check('auditoria: registra ediciones con los campos cambiados',
  (select count(*) >= 2 from public.audit_log where action = 'product.updated' and metadata ? 'fields'));
select pg_temp.check('auditoria: registra inactivacion y reactivacion',
  (select count(*) = 1 from public.audit_log where action = 'product.inactivated')
  and (select count(*) = 1 from public.audit_log where action = 'product.reactivated'));
select pg_temp.check('auditoria: registra el cambio de certificaciones',
  (select count(*) >= 2 from public.audit_log where action = 'product.certifications_changed'));
select pg_temp.check('auditoria: no registra intentos rechazados ni datos personales',
  (select count(*) = 0 from public.audit_log where entity_type = 'product' and metadata::text like '%@%')
  and (select count(distinct entity_id) from public.audit_log where action = 'product.created') = 4);

select n, prueba, resultado from resultados order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select (select count(*) from public.product) as productos_tras_rollback;
