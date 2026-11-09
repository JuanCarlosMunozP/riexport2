-- Pruebas del modulo de proveedores (EP-2, PLAT-510/511). Todo se revierte al final: no queda ningun dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/suppliers.sql
-- Requiere la migracion 20261009000000 aplicada. Usuarios: sw (suppliers.read/create/update),
-- sr (solo suppliers.read), sn (sin permisos), so (con permisos pero desactivado).

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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated', 'sw@sup.test', '{"first_name":"Escribe","last_name":"Proveedores"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f2', 'authenticated', 'authenticated', 'sr@sup.test', '{"first_name":"Lee","last_name":"Proveedores"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f3', 'authenticated', 'authenticated', 'sn@sup.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f4', 'authenticated', 'authenticated', 'so@sup.test', '{"first_name":"Desactivado","last_name":"Proveedores"}', now(), now());

insert into public.role(name) values ('s_write'), ('s_read');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['suppliers.read','suppliers.create','suppliers.update']) p where r.name = 's_write';
insert into public.role_permission(role_id, permission_code)
select r.id, 'suppliers.read' from public.role r where r.name = 's_read';
update public.profile set role_id = (select id from public.role where name = 's_write') where email in ('sw@sup.test', 'so@sup.test');
update public.profile set role_id = (select id from public.role where name = 's_read') where email = 'sr@sup.test';
update public.profile set is_active = false where email = 'so@sup.test';

select pg_temp.check('semilla: 3 permisos de proveedores y ninguno asignado a los roles de fabrica',
  (select count(*) from public.permission where code like 'suppliers.%') = 3
  and (select count(*) from public.role_permission rp join public.role r on r.id = rp.role_id
        where rp.permission_code like 'suppliers.%' and r.name not in ('s_write', 's_read')) = 0);

-- ------------------------------------------------------------------------- sin permisos (sn) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f3","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: no ve proveedores', $q$select * from public.supplier$q$, 0);
select pg_temp.attempt('sin permisos: no registra proveedores', $q$select public.create_supplier('{"business_name":"X","tax_id":"900123"}')$q$, 'No tienes permiso');

-- -------------------------------------------------------------------------- desactivado (so) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f4","role":"authenticated"}', true);
select pg_temp.attempt('desactivado: no registra proveedores', $q$select public.create_supplier('{"business_name":"X","tax_id":"900123"}')$q$, 'No tienes permiso');

-- ---------------------------------------------------------------------- con permisos (sw) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
select pg_temp.attempt('registra un proveedor completo', $q$select public.create_supplier('{"business_name":"  Finca La Esperanza SAS ","tax_id":"900.123.456-7","contact_name":"Ana Ruiz","phone":"+57 300 123 4567","email":"ANA@Esperanza.CO","location":"Huila, Colombia"}')$q$, 'ok');
select pg_temp.attempt('registra un proveedor solo con los obligatorios', $q$select public.create_supplier('{"business_name":"Cacao del Sur","tax_id":"NIT-2002"}')$q$, 'ok');
select pg_temp.check('se guardan limpios: recorte y correo en minusculas',
  (select business_name = 'Finca La Esperanza SAS' and email = 'ana@esperanza.co' and is_active
     from public.supplier where tax_id = '900.123.456-7'));
select pg_temp.rows('lee los proveedores', $q$select * from public.supplier$q$, 2);

select pg_temp.attempt('razon social obligatoria', $q$select public.create_supplier('{"tax_id":"111222"}')$q$, 'razón social es obligatoria');
select pg_temp.attempt('razon social vacia', $q$select public.create_supplier('{"business_name":"   ","tax_id":"111222"}')$q$, 'razón social es obligatoria');
select pg_temp.attempt('documento obligatorio', $q$select public.create_supplier('{"business_name":"Sin documento"}')$q$, 'documento tributario es obligatorio');
select pg_temp.attempt('documento con formato invalido', $q$select public.create_supplier('{"business_name":"A","tax_id":"@@"}')$q$, 'formato válido');
select pg_temp.attempt('documento duplicado (sin distinguir mayusculas)', $q$select public.create_supplier('{"business_name":"Otro","tax_id":"nit-2002"}')$q$, 'ya existe un proveedor con ese documento');
select pg_temp.attempt('telefono invalido', $q$select public.create_supplier('{"business_name":"A","tax_id":"333444","phone":"abc"}')$q$, 'teléfono no tiene un formato válido');
select pg_temp.attempt('correo invalido', $q$select public.create_supplier('{"business_name":"A","tax_id":"333444","email":"sin-arroba"}')$q$, 'correo no tiene un formato válido');
select pg_temp.attempt('razon social demasiado larga', format($q$select public.create_supplier('{"business_name":"%s","tax_id":"333444"}')$q$, repeat('x', 161)), 'máximo 160');
select pg_temp.attempt('campo ajeno rechazado', $q$select public.create_supplier('{"business_name":"A","tax_id":"333444","is_active":false}')$q$, 'Campo no permitido');
select pg_temp.attempt('campo con tipo incorrecto', $q$select public.create_supplier('{"business_name":5,"tax_id":"333444"}')$q$, 'debe ser texto');
select pg_temp.attempt('cuerpo no objeto', $q$select public.create_supplier('[1]')$q$, 'solicitud no es válida');
select pg_temp.rows('los intentos rechazados no dejan filas', $q$select * from public.supplier$q$, 2);

-- edicion
select pg_temp.attempt('edita un proveedor', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{"contact_name":"Luis Mora","location":"Tumaco"}')$q$, 'ok');
select pg_temp.check('la edicion se guarda',
  (select contact_name = 'Luis Mora' and location = 'Tumaco' and updated_at >= created_at from public.supplier where tax_id = 'NIT-2002'));
select pg_temp.attempt('vaciar un opcional lo deja nulo', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{"location":""}')$q$, 'ok');
select pg_temp.check('el opcional vacio queda nulo', (select location is null from public.supplier where tax_id = 'NIT-2002'));
select pg_temp.attempt('no vacia la razon social', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{"business_name":""}')$q$, 'razón social es obligatoria');
select pg_temp.attempt('documento duplicado al editar', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{"tax_id":"900.123.456-7"}')$q$, 'ya existe un proveedor con ese documento');
select pg_temp.attempt('sin campos', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{}')$q$, 'al menos un campo');
select pg_temp.attempt('campo ajeno al editar', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{"is_active":false}')$q$, 'Campo no permitido');
select pg_temp.attempt('proveedor inexistente', $q$select public.update_supplier(99999, '{"phone":"3001234"}')$q$, 'No se encontró');
select pg_temp.attempt('editar sin cambios no falla', $q$select public.update_supplier((select id from public.supplier where tax_id = 'NIT-2002'), '{"contact_name":"Luis Mora"}')$q$, 'ok');

-- inactivacion: conserva la fila y el historial
select pg_temp.attempt('inactiva un proveedor', $q$select public.set_supplier_active((select id from public.supplier where tax_id = 'NIT-2002'), false)$q$, 'ok');
select pg_temp.check('el proveedor inactivo sigue consultable con sus datos',
  (select not is_active and contact_name = 'Luis Mora' from public.supplier where tax_id = 'NIT-2002'));
select pg_temp.attempt('inactivar dos veces no falla', $q$select public.set_supplier_active((select id from public.supplier where tax_id = 'NIT-2002'), false)$q$, 'ok');
select pg_temp.attempt('reactiva el proveedor', $q$select public.set_supplier_active((select id from public.supplier where tax_id = 'NIT-2002'), true)$q$, 'ok');
select pg_temp.attempt('estado nulo rechazado', $q$select public.set_supplier_active((select id from public.supplier where tax_id = 'NIT-2002'), null)$q$, 'debe quedar activo');
select pg_temp.attempt('inactivar un inexistente', $q$select public.set_supplier_active(99999, false)$q$, 'No se encontró');

-- ------------------------------------------------------------------------ solo lectura (sr) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
select pg_temp.rows('lectura: ve los proveedores', $q$select * from public.supplier$q$, 2);
select pg_temp.attempt('lectura: no registra', $q$select public.create_supplier('{"business_name":"A","tax_id":"555666"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no edita', $q$select public.update_supplier(1, '{"phone":"3001234"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no inactiva', $q$select public.set_supplier_active(1, false)$q$, 'No tienes permiso');
select pg_temp.attempt('escritura directa denegada (insert)', $q$insert into public.supplier(business_name, tax_id) values ('A', '555666')$q$, 'permission denied');
select pg_temp.attempt('escritura directa denegada (update)', $q$update public.supplier set is_active = false$q$, 'permission denied');
select pg_temp.attempt('borrado directo denegado', $q$delete from public.supplier$q$, 'permission denied');

-- anonimo
reset role;
set local role anon;
select pg_temp.attempt('anonimo: no lee proveedores', $q$select * from public.supplier$q$, 'permission denied');
select pg_temp.attempt('anonimo: no ejecuta create_supplier', $q$select public.create_supplier('{"business_name":"A","tax_id":"555666"}')$q$, 'permission denied');
reset role;

-- propietario: el borrado esta bloqueado tambien por trigger
select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('nadie borra proveedores (ni el propietario)', $q$delete from public.supplier$q$, 'se inactivan');

-- ------------------------------------------------------------------------------- auditoria ---
select pg_temp.check('auditoria: 2 altas', (select count(*) = 2 from public.audit_log where action = 'supplier.created'));
select pg_temp.check('auditoria: ediciones con los campos cambiados (sin los no cambiados)',
  (select count(*) = 2 from public.audit_log where action = 'supplier.updated' and metadata ? 'fields')
  and not exists (select 1 from public.audit_log where action = 'supplier.updated' and metadata -> 'fields' ? 'tax_id'));
select pg_temp.check('auditoria: inactivacion y reactivacion una sola vez',
  (select count(*) = 1 from public.audit_log where action = 'supplier.inactivated')
  and (select count(*) = 1 from public.audit_log where action = 'supplier.reactivated'));
select pg_temp.check('auditoria: sin datos personales',
  (select count(*) = 0 from public.audit_log where entity_type = 'supplier' and metadata::text like '%@%'));

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select (select count(*) from public.supplier) as proveedores_tras_rollback;
