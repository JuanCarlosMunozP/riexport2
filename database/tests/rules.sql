-- Prueba de reglas y RLS con sesiones simuladas. Todo ocurre en una transaccion que se
-- revierte al final: no queda ningun dato.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/rules.sql
--
-- Usuarios de prueba: a1 y a2 (administrador), c1 (cliente, registro con role_id=1 en los metadatos),
-- c2 (users.read + users.update), c3 (users.read + users.deactivate), c4 (users.read + users.assign_role).
-- users.read es necesario en los roles parciales: para actualizar una fila hay que poder verla (politica SELECT).

begin;

create temp table resultados(n serial, prueba text, resultado text);
grant all on resultados to authenticated, anon;
grant usage on sequence resultados_n_seq to authenticated, anon;

-- Ejecuta una sentencia y comprueba que funcione ('ok') o que falle con un mensaje que contenga el texto.
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

-- Ejecuta una sentencia y comprueba cuantas filas afecta o devuelve.
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

-- ---------------------------------------------------------------- preparacion ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'a1@rls.test', '{"first_name":"Admin","last_name":"Uno"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'a2@rls.test', '{"first_name":"Admin","last_name":"Dos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'c1@rls.test', '{"first_name":"Cliente","last_name":"Uno","role_id":1}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated', 'c2@rls.test', '{"first_name":"Solo","last_name":"Update"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'c3@rls.test', '{"first_name":"Solo","last_name":"Deactivate"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c4', 'authenticated', 'authenticated', 'c4@rls.test', '{"first_name":"Solo","last_name":"AssignRole"}', now(), now());

insert into auth.sessions(id, user_id, created_at, updated_at)
values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1', now(), now());

-- Roles parciales (se crean como superusuario: auth.uid() nulo, sin comprobacion de permisos).
insert into public.role(name) values ('r_upd'), ('r_ded'), ('r_assign');
insert into public.role_permission(role_id, permission_code)
select r.id, x.p from public.role r
join (values ('r_upd','users.read'), ('r_upd','users.update'),
             ('r_ded','users.read'), ('r_ded','users.deactivate'),
             ('r_assign','users.read'), ('r_assign','users.assign_role')) x(n,p) on x.n = r.name;
update public.profile set role_id = (select id from public.role where name = 'r_upd')    where email = 'c2@rls.test';
update public.profile set role_id = (select id from public.role where name = 'r_ded')    where email = 'c3@rls.test';
update public.profile set role_id = (select id from public.role where name = 'r_assign') where email = 'c4@rls.test';

update public.profile set role_id = (select id from public.role where name = 'administrador')
 where email in ('a1@rls.test', 'a2@rls.test');

insert into public.permission (code, description)
values ('test.future_admin', 'Prueba temporal de permisos futuros');

insert into resultados(prueba, resultado)
select 'registro: el rol pedido en los metadatos se ignora (cliente)',
       case when r.name = 'cliente' then 'OK' else 'FALLA: ' || r.name end
from public.profile p join public.role r on r.id = p.role_id where p.email = 'c1@rls.test';

-- ------------------------------------------------------------------ cliente ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);

insert into resultados(prueba, resultado)
select 'current_user_role(): cliente', case when public.current_user_role() = 'cliente' then 'OK' else 'FALLA: ' || coalesce(public.current_user_role(), 'nulo') end;
select pg_temp.rows('vista de administracion: el cliente ve solo su fila', $q$select * from public.admin_user_list where email like '%@rls.test'$q$, 1);
select pg_temp.rows('cliente ve solo su propio perfil', $q$select * from public.profile where email like '%@rls.test'$q$, 1);
select pg_temp.rows('cliente no edita perfiles ajenos', $q$update public.profile set first_name = 'X' where email = 'a1@rls.test'$q$, 0);
select pg_temp.rows('cliente edita su propio nombre y telefono (autoedicion)', $q$update public.profile set first_name = 'Nuevo', phone = '311' where email = 'c1@rls.test'$q$, 1);
select pg_temp.attempt('cliente no cambia su propio rol', $q$update public.profile set role_id = (select id from public.role where name='administrador') where email = 'c1@rls.test'$q$, 'No puedes cambiar tu propio rol');
select pg_temp.attempt('cliente no se reactiva ni desactiva a si mismo', $q$update public.profile set is_active = false where email = 'c1@rls.test'$q$, 'No tienes permiso para activar o desactivar');
select pg_temp.attempt('nadie edita el correo por UPDATE directo', $q$update public.profile set email = 'otro@rls.test' where email = 'c1@rls.test'$q$, 'permission denied');
select pg_temp.attempt('no se cambia auth_user_id desde la autoedicion', $q$update public.profile set auth_user_id = gen_random_uuid() where email = 'c1@rls.test'$q$, 'permission denied');
select pg_temp.attempt('cliente no crea roles', $q$insert into public.role(name) values ('hack')$q$, 'row-level security');
select pg_temp.attempt('cliente no asigna permisos a roles', $q$select public.set_role_permissions((select id from public.role where name='cliente'), array['users.read'])$q$, 'No tienes permiso');
select pg_temp.rows('cliente puede leer el catalogo de roles', $q$select * from public.role where name in ('administrador','usuario_comercial','encargado_logistico','cliente')$q$, 4);
select pg_temp.attempt('cliente no puede insertar en permission', $q$insert into public.permission values ('x.y','z')$q$, 'permission denied');
select pg_temp.attempt('cliente no puede insertar en profile', $q$insert into public.profile(auth_user_id,email,first_name,last_name,role_id) values (gen_random_uuid(),'z@rls.test','a','b',1)$q$, 'permission denied');

-- -------------------------------------------------------------- administrador ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

insert into resultados(prueba, resultado)
select 'current_user_role(): administrador', case when public.current_user_role() = 'administrador' then 'OK' else 'FALLA: ' || coalesce(public.current_user_role(), 'nulo') end;
insert into resultados(prueba, resultado)
select 'administrador recibe los permisos agregados al catalogo',
       case when public.has_permission('test.future_admin') then 'OK' else 'FALLA: permiso no asignado' end;
select pg_temp.rows('vista de administracion: el admin ve todos, con el nombre del rol', $q$select * from public.admin_user_list where email like '%@rls.test' and role_name is not null$q$, 6);
select pg_temp.rows('admin ve todos los perfiles de prueba', $q$select * from public.profile where email like '%@rls.test'$q$, 6);
select pg_temp.rows('admin edita el telefono de otro usuario', $q$update public.profile set phone = '300' where email = 'c1@rls.test'$q$, 1);
select pg_temp.attempt('admin no puede cambiar auth_user_id (columna sin privilegio)', $q$update public.profile set auth_user_id = gen_random_uuid() where email = 'c1@rls.test'$q$, 'permission denied');
select pg_temp.attempt('admin no se desactiva a si mismo', $q$update public.profile set is_active = false where email = 'a1@rls.test'$q$, 'No puedes desactivar tu propio usuario');
select pg_temp.rows('admin desactiva a otro administrador (queda uno)', $q$update public.profile set is_active = false where email = 'a2@rls.test'$q$, 1);
select pg_temp.attempt('admin no cambia su propio rol (aunque tenga el permiso)', $q$update public.profile set role_id = (select id from public.role where name='cliente') where email = 'a1@rls.test'$q$, 'No puedes cambiar tu propio rol');

select pg_temp.attempt('admin crea un rol', $q$insert into public.role(name, description) values ('tmp_rol', 'prueba')$q$, 'ok');
select pg_temp.attempt('el nombre de rol invalido se rechaza', $q$insert into public.role(name) values ('Mal Nombre')$q$, 'check');
select pg_temp.attempt('el nombre de rol duplicado se rechaza', $q$insert into public.role(name) values ('tmp_rol')$q$, 'duplicate key');
select pg_temp.attempt('admin asigna permisos a un rol (atomico)', $q$select public.set_role_permissions((select id from public.role where name='tmp_rol'), array['users.read','roles.read'])$q$, 'ok');
select pg_temp.rows('los permisos quedaron asignados', $q$select * from public.role_permission rp join public.role r on r.id=rp.role_id where r.name='tmp_rol'$q$, 2);
select pg_temp.attempt('permisos duplicados se rechazan', $q$select public.set_role_permissions((select id from public.role where name='tmp_rol'), array['users.read','users.read'])$q$, 'duplicados');
select pg_temp.attempt('permisos inexistentes se rechazan', $q$select public.set_role_permissions((select id from public.role where name='tmp_rol'), array['no.existe'])$q$, 'no existen');
select pg_temp.attempt('el administrador conserva sus permisos de gestion', $q$select public.set_role_permissions((select id from public.role where name='administrador'), array['users.read'])$q$, 'conservar sus permisos');
select pg_temp.attempt('se puede desactivar un rol sin usuarios activos', $q$update public.role set is_active = false where name = 'tmp_rol'$q$, 'ok');
select pg_temp.attempt('no se asigna un rol inactivo', $q$update public.profile set role_id = (select id from public.role where name='tmp_rol') where email = 'c1@rls.test'$q$, 'inactivo');
select pg_temp.attempt('no se renombra el rol administrador', $q$update public.role set name = 'jefe' where name = 'administrador'$q$, 'administrador del sistema');
select pg_temp.attempt('no se desactiva el rol administrador', $q$update public.role set is_active = false where name = 'administrador'$q$, 'administrador del sistema');
select pg_temp.attempt('no se desactiva un rol con usuarios activos', $q$update public.role set is_active = false where name = 'cliente'$q$, 'usuarios activos');

-- ---------------------------------------------------- permisos parciales (H2) ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
select pg_temp.rows('users.read+update: edita el telefono de otro', $q$update public.profile set phone = '322' where email = 'c1@rls.test'$q$, 1);
select pg_temp.attempt('users.read+update: no asigna roles (H2)', $q$update public.profile set role_id = (select id from public.role where name='administrador') where email = 'c1@rls.test'$q$, 'No tienes permiso para asignar roles');
select pg_temp.attempt('users.read+update: no se asigna rol a si mismo (H2)', $q$update public.profile set role_id = (select id from public.role where name='administrador') where email = 'c2@rls.test'$q$, 'No puedes cambiar tu propio rol');
select pg_temp.attempt('users.read+update: no desactiva usuarios', $q$update public.profile set is_active = false where email = 'c1@rls.test'$q$, 'No tienes permiso para activar o desactivar');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
select pg_temp.attempt('users.read+deactivate: no edita nombres ajenos', $q$update public.profile set first_name = 'Z' where email = 'c1@rls.test'$q$, 'No tienes permiso para editar a otros');
select pg_temp.attempt('users.read+deactivate: desactiva a otro', $q$update public.profile set is_active = false where email = 'c1@rls.test'$q$, 'ok');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c4","role":"authenticated"}', true);
select pg_temp.attempt('users.read+assign_role: cambia el rol de otro', $q$update public.profile set role_id = (select id from public.role where name='encargado_logistico') where email = 'c2@rls.test'$q$, 'ok');
select pg_temp.attempt('users.read+assign_role: no deja al sistema sin administrador activo', $q$update public.profile set role_id = (select id from public.role where name='cliente') where email = 'a1@rls.test'$q$, 'sin un administrador activo');
select pg_temp.attempt('users.read+assign_role: no edita nombres ajenos', $q$update public.profile set first_name = 'Z' where email = 'c1@rls.test'$q$, 'No tienes permiso para editar a otros');


-- ----------------------------------- politica de cambio de rol y auditoria (472, 473) ---
reset role;
select set_config('request.jwt.claims', '{}', true);   -- sin sesion de usuario: DML como superusuario
-- Un tercer administrador activo, para que la regla del ultimo administrador no tape la nueva.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'a3@rls.test', '{"first_name":"Admin","last_name":"Tres"}', now(), now());
update public.profile set role_id = (select id from public.role where name = 'administrador') where email = 'a3@rls.test';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c4","role":"authenticated"}', true);
select pg_temp.attempt('assign_role sin ser administrador: no promueve a administrador', $q$update public.profile set role_id = (select id from public.role where name='administrador') where email = 'c2@rls.test'$q$, 'Solo un administrador');
select pg_temp.attempt('assign_role sin ser administrador: no degrada a un administrador', $q$update public.profile set role_id = (select id from public.role where name='cliente') where email = 'a3@rls.test'$q$, 'Solo un administrador');
select pg_temp.rows('sin permiso audit.read: no ve la auditoria', $q$select * from public.audit_log$q$, 0);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select pg_temp.attempt('un administrador si promueve a otro usuario a administrador', $q$update public.profile set role_id = (select id from public.role where name='administrador') where email = 'c2@rls.test'$q$, 'ok');
select pg_temp.attempt('un administrador si degrada a otro administrador', $q$update public.profile set role_id = (select id from public.role where name='cliente') where email = 'c2@rls.test'$q$, 'ok');
insert into resultados(prueba, resultado)
select 'auditoria: el administrador (audit.read) la consulta', case when count(*) > 0 then 'OK' else 'FALLA: sin filas' end from public.audit_log;
select pg_temp.attempt('auditoria: nadie escribe desde la API (INSERT)', $q$insert into public.audit_log(action, entity_type, entity_id) values ('x', 'profile', 1)$q$, 'permission denied');
select pg_temp.attempt('auditoria: nadie edita desde la API (UPDATE)', $q$update public.audit_log set action = 'x'$q$, 'permission denied');
select pg_temp.attempt('auditoria: nadie borra desde la API (DELETE)', $q$delete from public.audit_log$q$, 'permission denied');

reset role;
insert into resultados(prueba, resultado)
select 'auditoria: el cambio hecho por c4 queda con actor, rol origen y destino',
       case when count(*) = 1 then 'OK' else 'FALLA: ' || count(*) end
from public.audit_log l
join public.profile actor on actor.id = l.actor_user_id and actor.email = 'c4@rls.test'
join public.profile target on target.id = l.entity_id and target.email = 'c2@rls.test'
where l.action = 'user.role_changed' and l.entity_type = 'profile'
  and l.metadata ->> 'to_role' = 'encargado_logistico' and l.metadata ->> 'from_role' = 'r_upd';
insert into resultados(prueba, resultado)
select 'auditoria: el intento rechazado de promocion no deja registro (solo la promocion valida)',
       case when count(*) = 1 then 'OK' else 'FALLA: ' || count(*) end
from public.audit_log l join public.profile t on t.id = l.entity_id and t.email = 'c2@rls.test'
where l.action = 'user.role_changed' and l.metadata ->> 'to_role' = 'administrador';
insert into resultados(prueba, resultado)
select 'auditoria: los cambios hechos por SQL (sin sesion) quedan con actor nulo',
       case when count(*) >= 3 then 'OK' else 'FALLA: ' || count(*) end
from public.audit_log where action = 'user.role_changed' and actor_user_id is null;
insert into resultados(prueba, resultado)
select 'auditoria: no guarda datos personales (solo ids y nombres de rol)',
       case when count(*) = 0 then 'OK' else 'FALLA: ' || count(*) end
from public.audit_log where metadata::text like '%@%';

select pg_temp.attempt('auditoria inmutable: ni el propietario la edita', $q$update public.audit_log set action = 'x'$q$, 'no se puede modificar');
select pg_temp.attempt('auditoria inmutable: ni el propietario la borra', $q$delete from public.audit_log$q$, 'no se puede modificar');
select pg_temp.attempt('auditoria inmutable: ni el propietario la vacia', $q$truncate public.audit_log$q$, 'no se puede modificar');
select pg_temp.attempt('borrar una cuenta con auditoria conserva el registro (actor nulo)', $q$delete from auth.users where email = 'c4@rls.test'$q$, 'ok');
insert into resultados(prueba, resultado)
select 'auditoria: tras borrar la cuenta del actor sus registros siguen, con actor nulo',
       case when count(*) >= 1 then 'OK' else 'FALLA: 0' end
from public.audit_log l where l.action = 'user.role_changed' and l.actor_user_id is null
  and l.metadata ->> 'to_role' = 'encargado_logistico';

-- -------------------------------------------------- usuario desactivado (c1) ---
-- c3 desactivo a c1 en el bloque anterior.
reset role;
insert into resultados(prueba, resultado)
select 'desactivar veta la cuenta en Auth (banned_until)',
       case when banned_until > now() + interval '1 year' then 'OK' else 'FALLA: ' || coalesce(banned_until::text, 'nulo') end
from auth.users where email = 'c1@rls.test';
insert into resultados(prueba, resultado)
select 'desactivar revoca las sesiones de Auth',
       case when count(*) = 0 then 'OK' else 'FALLA: quedan ' || count(*) end
from auth.sessions where user_id = '00000000-0000-0000-0000-0000000000c1';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
insert into resultados(prueba, resultado)
select 'current_user_role(): desactivado devuelve nulo', case when public.current_user_role() is null then 'OK' else 'FALLA: ' || public.current_user_role() end;
select pg_temp.rows('desactivado: la vista de administracion no devuelve nada', $q$select * from public.admin_user_list where email like '%@rls.test'$q$, 0);
select pg_temp.rows('desactivado: no ve su propio perfil', $q$select * from public.profile where email like '%@rls.test'$q$, 0);
select pg_temp.rows('desactivado: no lee roles', $q$select * from public.role$q$, 0);
select pg_temp.rows('desactivado: no lee permisos', $q$select * from public.permission$q$, 0);
select pg_temp.rows('desactivado: no lee role_permission', $q$select * from public.role_permission$q$, 0);
select pg_temp.rows('desactivado: no edita su propio perfil', $q$update public.profile set first_name = 'X' where email = 'c1@rls.test'$q$, 0);
select pg_temp.attempt('desactivado: no sube archivos a su carpeta', $q$insert into storage.objects (bucket_id, name) values ('profile-photos', '00000000-0000-0000-0000-0000000000c1/foto.png')$q$, 'row-level security');

-- un administrador desactivado (a2, desactivado antes por a1) tampoco conserva nada
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
select pg_temp.rows('administrador desactivado: no lee roles ni usuarios', $q$select * from public.role$q$, 0);
select pg_temp.rows('administrador desactivado: no ve perfiles ajenos', $q$select * from public.profile where email like '%@rls.test'$q$, 0);
select pg_temp.attempt('administrador desactivado: no crea roles', $q$insert into public.role(name) values ('colado')$q$, 'row-level security');

-- reactivar devuelve el acceso y quita el veto
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
select pg_temp.rows('reactivar a un usuario', $q$update public.profile set is_active = true where email = 'c1@rls.test'$q$, 1);
reset role;
insert into resultados(prueba, resultado)
select 'reactivar quita el veto de Auth',
       case when banned_until is null then 'OK' else 'FALLA: ' || banned_until::text end
from auth.users where email = 'c1@rls.test';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select pg_temp.rows('reactivado: vuelve a ver su perfil', $q$select * from public.profile where email like '%@rls.test'$q$, 1);

-- ---------------------------------------------------------------- anonimo ---
reset role;
set local role anon;
select pg_temp.attempt('anonimo no puede ejecutar current_user_role()', $q$select public.current_user_role()$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee la vista de administracion', $q$select * from public.admin_user_list$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee la auditoria', $q$select * from public.audit_log$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee perfiles', $q$select * from public.profile$q$, 'permission denied');
select pg_temp.attempt('anonimo no lee roles', $q$select * from public.role$q$, 'permission denied');

reset role;
select n, prueba, resultado from resultados order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;

select count(*) as usuarios_de_prueba_tras_rollback from auth.users where email like '%@rls.test';
