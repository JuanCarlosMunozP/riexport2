-- Pruebas del modulo de clientes y de la validacion del EORI (PLAT-526/527/528). Todo se revierte al final.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/customers.sql
-- Requiere la migracion 20261013000000 aplicada.
-- Usuarios: cw (customers.read/create/update), cr (solo customers.read), cn (sin permisos), co (desactivado).

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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'cw@cust.test', '{"first_name":"Escribe","last_name":"Clientes"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated', 'cr@cust.test', '{"first_name":"Lee","last_name":"Clientes"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'cn@cust.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c4', 'authenticated', 'authenticated', 'co@cust.test', '{"first_name":"Desactivado","last_name":"Clientes"}', now(), now());

insert into public.role(name) values ('c_write'), ('c_read');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['customers.read','customers.create','customers.update']) p where r.name = 'c_write';
insert into public.role_permission(role_id, permission_code)
select r.id, 'customers.read' from public.role r where r.name = 'c_read';
update public.profile set role_id = (select id from public.role where name = 'c_write') where email in ('cw@cust.test', 'co@cust.test');
update public.profile set role_id = (select id from public.role where name = 'c_read') where email = 'cr@cust.test';
update public.profile set is_active = false where email = 'co@cust.test';

select pg_temp.check('semilla: 3 permisos de clientes',
  (select count(*) from public.permission where code like 'customers.%') = 3);

-- ------------------------------------------------------------- normalizacion del EORI (funcion pura) ---
select pg_temp.check('normaliza: mayusculas y sin espacios, guiones ni puntos',
  public.normalize_eori(' es-1234 5678.z ') = 'ES12345678Z');
select pg_temp.check('normaliza: vacio es nulo', public.normalize_eori('  ') is null and public.normalize_eori(null) is null);

-- ------------------------------------------------------------------------- sin permisos (cn) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: no ve clientes', $q$select * from public.customer$q$, 0);
select pg_temp.attempt('sin permisos: no registra clientes', $q$select public.create_customer('{"name":"X","country_code":"CO","preferred_currency_code":"USD"}')$q$, 'No tienes permiso');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c4","role":"authenticated"}', true);
select pg_temp.attempt('desactivado: no registra clientes', $q$select public.create_customer('{"name":"X","country_code":"CO","preferred_currency_code":"USD"}')$q$, 'No tienes permiso');

-- ---------------------------------------------------------------------- con permisos (cw) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select pg_temp.attempt('registra un cliente de la UE con EORI', $q$select public.create_customer('{"name":"  Importadora Iberica SL ","contact_name":"Marta Gil","email":"MARTA@Iberica.ES","country_code":"es","eori_number":"es-1234 5678z","preferred_currency_code":"eur"}')$q$, 'ok');
select pg_temp.attempt('registra un cliente fuera de la UE sin EORI', $q$select public.create_customer('{"name":"Coffee Corp","country_code":"US","preferred_currency_code":"USD"}')$q$, 'ok');
select pg_temp.attempt('registra un cliente fuera de la UE con EORI de su pais', $q$select public.create_customer('{"name":"UK Roasters","country_code":"GB","eori_number":"GB123456789000","preferred_currency_code":"GBP"}')$q$, 'ok');
select pg_temp.attempt('Irlanda del Norte: el Reino Unido admite XI', $q$select public.create_customer('{"name":"NI Roasters","country_code":"GB","eori_number":"XI123456789000","preferred_currency_code":"GBP"}')$q$, 'ok');
select pg_temp.attempt('Grecia usa el prefijo EL', $q$select public.create_customer('{"name":"Hellas Coffee","country_code":"GR","eori_number":"EL123456789","preferred_currency_code":"EUR"}')$q$, 'ok');
select pg_temp.check('se guardan limpios: nombre recortado, correo en minusculas, EORI normalizado y pais y moneda en mayusculas',
  (select name = 'Importadora Iberica SL' and email = 'marta@iberica.es' and eori_number = 'ES12345678Z'
          and country_code = 'ES' and preferred_currency_code = 'EUR' and is_active
     from public.customer where eori_number = 'ES12345678Z'));
select pg_temp.rows('lee los clientes', $q$select * from public.customer$q$, 5);

-- obligatorios
select pg_temp.attempt('nombre obligatorio', $q$select public.create_customer('{"country_code":"US","preferred_currency_code":"USD"}')$q$, 'nombre del cliente es obligatorio');
select pg_temp.attempt('pais obligatorio', $q$select public.create_customer('{"name":"A","preferred_currency_code":"USD"}')$q$, 'país es obligatorio');
select pg_temp.attempt('pais invalido', $q$select public.create_customer('{"name":"A","country_code":"USA","preferred_currency_code":"USD"}')$q$, 'país');
select pg_temp.attempt('moneda obligatoria', $q$select public.create_customer('{"name":"A","country_code":"US"}')$q$, 'moneda preferida es obligatoria');
select pg_temp.attempt('moneda invalida', $q$select public.create_customer('{"name":"A","country_code":"US","preferred_currency_code":"US"}')$q$, 'moneda debe ser un código de 3 letras');
select pg_temp.attempt('correo invalido', $q$select public.create_customer('{"name":"A","country_code":"US","preferred_currency_code":"USD","email":"sin-arroba"}')$q$, 'correo no tiene un formato válido');
select pg_temp.attempt('campo ajeno rechazado', $q$select public.create_customer('{"name":"A","country_code":"US","preferred_currency_code":"USD","is_active":false}')$q$, 'Campo no permitido');
select pg_temp.attempt('campo con tipo incorrecto', $q$select public.create_customer('{"name":5,"country_code":"US","preferred_currency_code":"USD"}')$q$, 'debe ser texto');
select pg_temp.attempt('nombre demasiado largo', format($q$select public.create_customer('{"name":"%s","country_code":"US","preferred_currency_code":"USD"}')$q$, repeat('x', 181)), 'máximo 180');

-- EORI (PLAT-528)
select pg_temp.attempt('UE sin EORI: obligatorio', $q$select public.create_customer('{"name":"A","country_code":"DE","preferred_currency_code":"EUR"}')$q$, 'obligatorio para clientes de la Unión Europea');
select pg_temp.attempt('UE con EORI vacio: obligatorio', $q$select public.create_customer('{"name":"A","country_code":"FR","eori_number":"  ","preferred_currency_code":"EUR"}')$q$, 'obligatorio para clientes de la Unión Europea');
select pg_temp.attempt('EORI con prefijo de otro pais', $q$select public.create_customer('{"name":"A","country_code":"DE","eori_number":"FR12345678","preferred_currency_code":"EUR"}')$q$, 'debe empezar por DE');
select pg_temp.attempt('Grecia con prefijo GR (debe ser EL)', $q$select public.create_customer('{"name":"A","country_code":"GR","eori_number":"GR123456789","preferred_currency_code":"EUR"}')$q$, 'debe empezar por EL');
select pg_temp.attempt('EORI sin parte numerica (solo el prefijo)', $q$select public.create_customer('{"name":"A","country_code":"DE","eori_number":"DE","preferred_currency_code":"EUR"}')$q$, 'formato válido');
select pg_temp.attempt('EORI demasiado largo (16 caracteres tras el pais)', $q$select public.create_customer('{"name":"A","country_code":"DE","eori_number":"DE1234567890123456","preferred_currency_code":"EUR"}')$q$, 'formato válido');
select pg_temp.attempt('EORI con caracteres no validos', $q$select public.create_customer('{"name":"A","country_code":"DE","eori_number":"DE12345_678","preferred_currency_code":"EUR"}')$q$, 'formato válido');
select pg_temp.attempt('EORI con 15 caracteres tras el pais es valido', $q$select public.create_customer('{"name":"B","country_code":"DE","eori_number":"DE123456789012345","preferred_currency_code":"EUR"}')$q$, 'ok');
select pg_temp.attempt('EORI de otro pais para un cliente de fuera de la UE', $q$select public.create_customer('{"name":"A","country_code":"US","eori_number":"DE12345678","preferred_currency_code":"USD"}')$q$, 'debe empezar por US');
select pg_temp.attempt('EORI duplicado tras normalizar', $q$select public.create_customer('{"name":"Otro","country_code":"ES","eori_number":" ES 12345678-z","preferred_currency_code":"EUR"}')$q$, 'Ya existe un cliente con ese EORI');
select pg_temp.rows('los intentos rechazados no dejan filas', $q$select * from public.customer$q$, 6);

-- los CHECK de la tabla protegen aunque se escriba sin pasar por las funciones
reset role;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('CHECK: formato de EORI por SQL', $q$insert into public.customer(name, country_code, eori_number, preferred_currency_code) values ('D1', 'DE', 'de123', 'EUR')$q$, 'customer_eori_format');
select pg_temp.attempt('CHECK: prefijo del EORI por SQL', $q$insert into public.customer(name, country_code, eori_number, preferred_currency_code) values ('D2', 'DE', 'FR12345', 'EUR')$q$, 'customer_eori_prefix');
select pg_temp.attempt('CHECK: EORI obligatorio en la UE por SQL', $q$insert into public.customer(name, country_code, preferred_currency_code) values ('D3', 'IT', 'EUR')$q$, 'customer_eori_required_eu');
select pg_temp.attempt('CHECK: EORI unico por SQL', $q$insert into public.customer(name, country_code, eori_number, preferred_currency_code) values ('D4', 'ES', 'ES12345678Z', 'EUR')$q$, 'customer_eori_uq');
select pg_temp.attempt('CHECK: pais en minusculas por SQL', $q$insert into public.customer(name, country_code, preferred_currency_code) values ('D5', 'us', 'USD')$q$, 'violates check');
select pg_temp.attempt('CHECK: correo invalido por SQL', $q$insert into public.customer(name, country_code, preferred_currency_code, email) values ('D6', 'US', 'USD', 'x')$q$, 'violates check');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);

-- edicion
select pg_temp.attempt('edita contacto y moneda', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"contact_name":"John Doe","preferred_currency_code":"cad"}')$q$, 'ok');
select pg_temp.check('la edicion se guarda', (select contact_name = 'John Doe' and preferred_currency_code = 'CAD' from public.customer where name = 'Coffee Corp'));
select pg_temp.attempt('agrega un EORI a un cliente que no lo tenia', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"eori_number":"US123456"}')$q$, 'ok');
select pg_temp.attempt('quita el EORI a un cliente fuera de la UE', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"eori_number":null}')$q$, 'ok');
select pg_temp.check('el EORI queda ausente', (select eori_number is null from public.customer where name = 'Coffee Corp'));
select pg_temp.attempt('no quita el EORI a un cliente de la UE', $q$select public.update_customer((select id from public.customer where name = 'Importadora Iberica SL'), '{"eori_number":""}')$q$, 'obligatorio para clientes de la Unión Europea');
select pg_temp.attempt('cambiar el pais a la UE exige EORI', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"country_code":"FR"}')$q$, 'obligatorio para clientes de la Unión Europea');
select pg_temp.attempt('cambiar el pais con EORI de otro pais falla', $q$select public.update_customer((select id from public.customer where name = 'Importadora Iberica SL'), '{"country_code":"FR"}')$q$, 'debe empezar por FR');
select pg_temp.attempt('cambiar pais y EORI a la vez es valido', $q$select public.update_customer((select id from public.customer where name = 'Importadora Iberica SL'), '{"country_code":"FR","eori_number":"FR12345678901"}')$q$, 'ok');
select pg_temp.attempt('EORI duplicado al editar', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"country_code":"FR","eori_number":"FR12345678901"}')$q$, 'Ya existe un cliente con ese EORI');
select pg_temp.attempt('no vacia el nombre', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"name":""}')$q$, 'nombre del cliente es obligatorio');
select pg_temp.attempt('sin campos', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{}')$q$, 'al menos un campo');
select pg_temp.attempt('campo ajeno al editar', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"is_active":false}')$q$, 'Campo no permitido');
select pg_temp.attempt('cliente inexistente', $q$select public.update_customer(99999, '{"name":"X"}')$q$, 'No se encontró');
select pg_temp.attempt('editar sin cambios no falla', $q$select public.update_customer((select id from public.customer where name = 'Coffee Corp'), '{"name":"Coffee Corp"}')$q$, 'ok');

-- inactivacion
select pg_temp.attempt('inactiva un cliente', $q$select public.set_customer_active((select id from public.customer where name = 'Coffee Corp'), false)$q$, 'ok');
select pg_temp.check('el cliente inactivo sigue consultable con sus datos', (select not is_active and contact_name = 'John Doe' from public.customer where name = 'Coffee Corp'));
select pg_temp.attempt('inactivar dos veces no falla', $q$select public.set_customer_active((select id from public.customer where name = 'Coffee Corp'), false)$q$, 'ok');
select pg_temp.attempt('reactiva el cliente', $q$select public.set_customer_active((select id from public.customer where name = 'Coffee Corp'), true)$q$, 'ok');
select pg_temp.attempt('estado nulo rechazado', $q$select public.set_customer_active((select id from public.customer where name = 'Coffee Corp'), null)$q$, 'debe quedar activo');
select pg_temp.attempt('inactivar un inexistente', $q$select public.set_customer_active(99999, false)$q$, 'No se encontró');

-- ------------------------------------------------------------------------ solo lectura (cr) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
select pg_temp.rows('lectura: ve los clientes', $q$select * from public.customer$q$, 6);
select pg_temp.attempt('lectura: no registra', $q$select public.create_customer('{"name":"A","country_code":"US","preferred_currency_code":"USD"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no edita', $q$select public.update_customer(1, '{"name":"X"}')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no inactiva', $q$select public.set_customer_active(1, false)$q$, 'No tienes permiso');
select pg_temp.attempt('escritura directa denegada (insert)', $q$insert into public.customer(name, country_code, preferred_currency_code) values ('A', 'US', 'USD')$q$, 'permission denied');
select pg_temp.attempt('escritura directa denegada (update)', $q$update public.customer set name = 'X'$q$, 'permission denied');
select pg_temp.attempt('borrado directo denegado', $q$delete from public.customer$q$, 'permission denied');

reset role;
set local role anon;
select pg_temp.attempt('anonimo: no lee clientes', $q$select * from public.customer$q$, 'permission denied');
select pg_temp.attempt('anonimo: no ejecuta create_customer', $q$select public.create_customer('{"name":"A","country_code":"US","preferred_currency_code":"USD"}')$q$, 'permission denied');
reset role;

select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('nadie borra clientes (ni el propietario)', $q$delete from public.customer$q$, 'se inactivan');

-- ------------------------------------------------------------------------------- auditoria ---
select pg_temp.check('auditoria: 6 altas', (select count(*) = 6 from public.audit_log where action = 'customer.created'));
select pg_temp.check('auditoria: ediciones con los campos cambiados (sin los no cambiados)',
  (select count(*) = 4 from public.audit_log where action = 'customer.updated' and metadata ? 'fields')
  and not exists (select 1 from public.audit_log where action = 'customer.updated' and metadata -> 'fields' ? 'name'));
select pg_temp.check('auditoria: inactivacion y reactivacion una sola vez',
  (select count(*) = 1 from public.audit_log where action = 'customer.inactivated')
  and (select count(*) = 1 from public.audit_log where action = 'customer.reactivated'));
select pg_temp.check('auditoria: sin datos personales ni EORI',
  (select count(*) = 0 from public.audit_log where entity_type = 'customer' and (metadata::text like '%@%' or metadata::text ~ '[A-Z]{2}[0-9]{6}')));

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select (select count(*) from public.customer) as clientes_tras_rollback;
