-- Cuentas de demostracion por rol (solo desarrollo; NO ejecutar en produccion). Idempotente.
-- Contrasena para todas: Demo2026!
do $roles$
declare v_email text; v_first text; v_last text; v_role text; v_uid uuid;
begin
  for v_email, v_first, v_last, v_role in
    select * from (values
      ('admin@demo.riexport.test',        'Ana',    'Administradora', 'administrador'),
      ('comercial@demo.riexport.test',    'Carlos', 'Comercial',      'usuario_comercial'),
      ('logistica@demo.riexport.test',    'Laura',  'Logistica',      'encargado_logistico'),
      ('inventario@demo.riexport.test',   'Ivan',   'Inventario',     'gestor_inventario'),
      ('financiero@demo.riexport.test',   'Felipe', 'Financiero',     'gestor_financiero'),
      ('cumplimiento@demo.riexport.test', 'Camila', 'Cumplimiento',   'gestor_cumplimiento'),
      ('cliente@demo.riexport.test',      'Hans',   'Importador',     'cliente'),
      ('cliente2@demo.riexport.test',     'Jan',    'de Vries',       'cliente')) as t(e, f, l, r)
  loop
    select id into v_uid from auth.users where email = v_email;
    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                              raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                              confirmation_token, recovery_token, email_change, email_change_token_new,
                              email_change_token_current, phone_change, phone_change_token, reauthentication_token)
      values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
              crypt('Demo2026!', gen_salt('bf', 10)), now(),
              '{"provider":"email","providers":["email"]}',
              jsonb_build_object('first_name', v_first, 'last_name', v_last),
              now(), now(), '', '', '', '', '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_uid, v_uid::text, 'email',
              jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true), now(), now(), now());
    end if;
    update public.profile set role_id = (select id from public.role where name = v_role)
     where auth_user_id = v_uid;
  end loop;
end
$roles$;
