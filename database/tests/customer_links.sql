-- Pruebas del vinculo cliente <-> cuenta de usuario (PLAT-529). Todo se revierte al final.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/customer_links.sql
-- Requiere las migraciones 20261013000000 y 20261014000000 aplicadas.
-- Usuarios: sw (customers.read/create/update), sr (solo customers.read), sn (sin permisos),
-- ca y cb (clientes externos con portal.read), co (externo desactivado), cs (staff sin portal.read).

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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'sw@link.test', '{"first_name":"Escribe","last_name":"Clientes"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d2', 'authenticated', 'authenticated', 'sr@link.test', '{"first_name":"Lee","last_name":"Clientes"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d3', 'authenticated', 'authenticated', 'sn@link.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d4', 'authenticated', 'authenticated', 'ca@link.test', '{"first_name":"Cliente","last_name":"A"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d5', 'authenticated', 'authenticated', 'cb@link.test', '{"first_name":"Cliente","last_name":"B"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d6', 'authenticated', 'authenticated', 'co@link.test', '{"first_name":"Cliente","last_name":"Off"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d7', 'authenticated', 'authenticated', 'cs@link.test', '{"first_name":"Staff","last_name":"Interno"}', now(), now());

insert into public.role(name) values ('l_write'), ('l_read'), ('l_portal');
insert into public.role_permission(role_id, permission_code)
select r.id, p from public.role r, unnest(array['customers.read','customers.create','customers.update']) p where r.name = 'l_write';
insert into public.role_permission(role_id, permission_code)
select r.id, 'customers.read' from public.role r where r.name = 'l_read';
insert into public.role_permission(role_id, permission_code)
select r.id, 'portal.read' from public.role r where r.name = 'l_portal';
update public.profile set role_id = (select id from public.role where name = 'l_write') where email = 'sw@link.test';
update public.profile set role_id = (select id from public.role where name = 'l_read') where email = 'sr@link.test';
update public.profile set role_id = (select id from public.role where name = 'l_portal') where email in ('ca@link.test', 'cb@link.test', 'co@link.test');
update public.profile set is_active = false where email = 'co@link.test';

select pg_temp.check('semilla: el permiso portal.read existe',
  exists (select 1 from public.permission where code = 'portal.read'));

-- --------------------------------------------------------------------------- datos (como sw) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select public.create_customer('{"name":"Cliente Uno","country_code":"US","preferred_currency_code":"USD"}');
select public.create_customer('{"name":"Cliente Dos","country_code":"US","preferred_currency_code":"USD"}');
select public.create_customer('{"name":"Cliente Inactivo","country_code":"US","preferred_currency_code":"USD"}');
select public.set_customer_active((select id from public.customer where name = 'Cliente Inactivo'), false);

-- ------------------------------------------------------------------------- sin permisos (sn) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d3","role":"authenticated"}', true);
select pg_temp.attempt('sin permisos: no vincula', $q$select public.link_customer_user(1, 'ca@link.test')$q$, 'No tienes permiso');
select pg_temp.attempt('sin permisos: no desvincula', $q$select public.unlink_customer_user(1, 1)$q$, 'No tienes permiso');
select pg_temp.rows('sin permisos: no ve vinculos', $q$select * from public.customer_user$q$, 0);
select pg_temp.rows('sin permisos: no ve la vista de cuentas', $q$select * from public.customer_account_link$q$, 0);

-- ----------------------------------------------------------------------------- con permisos (sw) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select pg_temp.attempt('vincula una cuenta a un cliente', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Uno'), '  CA@Link.Test ')$q$, 'ok');
select pg_temp.attempt('un cliente puede tener varias cuentas', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Uno'), 'cs@link.test')$q$, 'ok');
select pg_temp.attempt('una cuenta puede estar en varios clientes', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Dos'), 'ca@link.test')$q$, 'ok');
select pg_temp.attempt('vincula la cuenta del otro cliente', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Dos'), 'cb@link.test')$q$, 'ok');
select pg_temp.rows('lee los vinculos', $q$select * from public.customer_user$q$, 4);
select pg_temp.check('la vista une correo, nombre y acceso al portal',
  (select email = 'ca@link.test' and first_name = 'Cliente' and account_is_active and has_portal_access
     from public.customer_account_link
    where customer_id = (select id from public.customer where name = 'Cliente Uno') and email = 'ca@link.test'));
select pg_temp.check('la vista avisa si la cuenta no tiene portal.read',
  (select not has_portal_access from public.customer_account_link where email = 'cs@link.test'));

select pg_temp.attempt('vinculo duplicado', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Uno'), 'ca@link.test')$q$, 'ya está vinculada');
select pg_temp.attempt('correo obligatorio', $q$select public.link_customer_user(1, '  ')$q$, 'correo de la cuenta es obligatorio');
select pg_temp.attempt('correo con formato invalido', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Uno'), 'sin-arroba')$q$, 'formato válido');
select pg_temp.attempt('cuenta inexistente', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Uno'), 'nadie@link.test')$q$, 'No existe una cuenta');
select pg_temp.attempt('cuenta desactivada', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Uno'), 'co@link.test')$q$, 'cuenta está desactivada');
select pg_temp.attempt('cliente inexistente', $q$select public.link_customer_user(99999, 'ca@link.test')$q$, 'No se encontró el cliente');
select pg_temp.attempt('cliente inactivo', $q$select public.link_customer_user((select id from public.customer where name = 'Cliente Inactivo'), 'ca@link.test')$q$, 'cliente está inactivo');
select pg_temp.rows('los rechazos no dejan vinculos', $q$select * from public.customer_user$q$, 4);

-- ---------------------------------------------------------------------- solo lectura (sr) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d2","role":"authenticated"}', true);
select pg_temp.rows('lectura: ve todos los vinculos', $q$select * from public.customer_user$q$, 4);
select pg_temp.rows('lectura: ve la vista de cuentas', $q$select * from public.customer_account_link$q$, 4);
select pg_temp.attempt('lectura: no vincula', $q$select public.link_customer_user(1, 'ca@link.test')$q$, 'No tienes permiso');
select pg_temp.attempt('lectura: no desvincula', $q$select public.unlink_customer_user(1, 1)$q$, 'No tienes permiso');

-- ----------------------------------------------------------------------- el propio cliente (ca) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select pg_temp.rows('el cliente ve solo sus vinculos (2 clientes)', $q$select * from public.customer_user$q$, 2);
select pg_temp.rows('el cliente no ve la vista con datos de cuentas', $q$select * from public.customer_account_link$q$, 0);
select pg_temp.attempt('el cliente no se vincula a otro', $q$select public.link_customer_user(1, 'ca@link.test')$q$, 'No tienes permiso');
select pg_temp.attempt('el cliente no se desvincula', $q$select public.unlink_customer_user(1, 1)$q$, 'No tienes permiso');
select pg_temp.attempt('el cliente no escribe directo (insert)', $q$insert into public.customer_user(customer_id, profile_id) values (1, 1)$q$, 'permission denied');
select pg_temp.attempt('el cliente no escribe directo (delete)', $q$delete from public.customer_user$q$, 'permission denied');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d5","role":"authenticated"}', true);
select pg_temp.rows('el otro cliente ve solo su vinculo', $q$select * from public.customer_user$q$, 1);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d6","role":"authenticated"}', true);
select pg_temp.rows('una cuenta desactivada no ve nada', $q$select * from public.customer_user$q$, 0);

-- ------------------------------------------------------------------------------- desvincular ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select pg_temp.attempt('desvincula una cuenta', $q$select public.unlink_customer_user((select id from public.customer where name = 'Cliente Dos'), (select profile_id from public.customer_account_link where email = 'ca@link.test' limit 1))$q$, 'ok');
select pg_temp.rows('quedan 3 vinculos', $q$select * from public.customer_user$q$, 3);
select pg_temp.attempt('desvincular dos veces falla', $q$select public.unlink_customer_user((select id from public.customer where name = 'Cliente Dos'), (select profile_id from public.customer_account_link where email = 'ca@link.test' limit 1))$q$, 'No se encontró el vínculo');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select pg_temp.rows('tras desvincular, el cliente ya solo ve un vinculo', $q$select * from public.customer_user$q$, 1);

reset role;
set local role anon;
select pg_temp.attempt('anonimo: no lee vinculos', $q$select * from public.customer_user$q$, 'permission denied');
select pg_temp.attempt('anonimo: no lee la vista', $q$select * from public.customer_account_link$q$, 'permission denied');
select pg_temp.attempt('anonimo: no vincula', $q$select public.link_customer_user(1, 'ca@link.test')$q$, 'permission denied');
reset role;

-- un cliente con vinculos no se puede borrar (ni inactivar borra el vinculo)
select set_config('request.jwt.claims', '{}', true);
select pg_temp.attempt('un cliente vinculado no se borra', $q$delete from public.customer where name = 'Cliente Uno'$q$, 'se inactivan');
select pg_temp.attempt('eliminar la cuenta elimina su vinculo (cascada)', $q$delete from auth.users where email = 'cb@link.test'$q$, 'ok');
select pg_temp.rows('el vinculo de la cuenta eliminada desaparece', $q$select * from public.customer_user where profile_id not in (select id from public.profile)$q$, 0);

-- ------------------------------------------------------------------------------- auditoria ---
select pg_temp.check('auditoria: 4 vinculaciones', (select count(*) = 4 from public.audit_log where action = 'customer.user_linked'));
select pg_temp.check('auditoria: 1 desvinculacion', (select count(*) = 1 from public.audit_log where action = 'customer.user_unlinked'));
select pg_temp.check('auditoria: guarda el id de la cuenta, no el correo',
  (select count(*) = 0 from public.audit_log where action like 'customer.user_%' and metadata::text like '%@%')
  and (select count(*) = 5 from public.audit_log where action like 'customer.user_%' and metadata ? 'profile_id'));

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select (select count(*) from public.customer_user) as vinculos_tras_rollback;
