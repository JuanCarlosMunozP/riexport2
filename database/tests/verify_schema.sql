-- Verificación del esquema aplicado (solo lectura). Falla si algo no coincide.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/verify_schema.sql
-- Cubre: tablas y restricciones, datos semilla, RLS y políticas, funciones, triggers,
-- privilegios y buckets de Storage.

create temp table chk(seccion text, comprobacion text, ok boolean, detalle text);

do $$
declare
  t text; n int; v text;
begin
  -- 1. Tablas y restricciones --------------------------------------------------
  foreach t in array array['role','permission','role_permission','profile','audit_log','unit_of_measure','certification','product','coffee_detail','cacao_detail','product_certification','customer','customer_user','customer_order','order_line','inventory_movement','export','export_line','export_destination','incoterm','shipment','shipment_event','stored_file','export_document','notification','payment_obligation','payment_transaction','exchange_rate'] loop
    insert into chk values ('tablas', 'existe public.'||t,
      to_regclass('public.'||t) is not null, null);
  end loop;

  insert into chk select 'restricciones', 'UNIQUE en '||x.rel||'.'||x.col,
    exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
            join pg_attribute a on a.attrelid = c.oid and a.attnum = any(i.indkey)
            where i.indisunique and c.relname = x.rel and a.attname = x.col
              and i.indnatts = 1 and c.relnamespace = 'public'::regnamespace), null
  from (values ('role','name'), ('profile','email'), ('profile','auth_user_id')) x(rel, col);

  select count(*) into n from pg_constraint c
   where c.contype = 'f' and c.connamespace = 'public'::regnamespace;
  insert into chk values ('restricciones', 'claves foráneas en public (mínimo: 15)', n >= 15, n::text);

  select count(*) into n from pg_constraint c
   where c.contype = 'c' and c.connamespace = 'public'::regnamespace;
  insert into chk values ('restricciones', 'CHECK en public (mínimo: 41)', n >= 41, n::text);

  insert into chk values ('restricciones', 'índice profile_role_id_idx',
    to_regclass('public.profile_role_id_idx') is not null, null);

  -- 2. Datos semilla -------------------------------------------------------------
  select count(*) into n from public.permission
   where code in ('roles.read','roles.create','roles.update','roles.permissions.update',
                  'roles.deactivate','users.read','users.create','users.update','users.deactivate',
                  'users.assign_role');
  insert into chk values ('semilla', '10 permisos base', n = 10, n::text);

  select count(*) into n from public.role
   where name in ('administrador','usuario_comercial','encargado_logistico','cliente');
  insert into chk values ('semilla', '4 roles base', n = 4, n::text);

  select count(*) into n from public.role_permission rp join public.role r on r.id = rp.role_id
   where r.name = 'administrador';
  insert into chk values ('semilla', 'administrador tiene todos los permisos',
    n = (select count(*) from public.permission), n::text);

  select count(*) into n from public.role_permission rp join public.role r on r.id = rp.role_id
   where r.name = 'cliente';
  insert into chk values ('semilla', 'cliente solo tiene portal.read', n = 1 and exists (
    select 1 from public.role_permission rp join public.role r on r.id = rp.role_id
    where r.name = 'cliente' and rp.permission_code = 'portal.read'
  ), n::text);

  select count(*) into n from public.role_permission rp join public.role r on r.id = rp.role_id
   where r.name = 'encargado_logistico'
     and rp.permission_code in ('customers.read','orders.read','exports.read','documents.read',
                                'inventory.read','inventory.adjust','logistics.read',
                                'logistics.create','logistics.update');
  insert into chk values ('semilla', 'logística tiene solo los 9 permisos operativos definidos',
    n = 9 and (select count(*) from public.role_permission rp join public.role r on r.id = rp.role_id
                where r.name = 'encargado_logistico') = 9, n::text);

  select count(*) into n from public.role_permission rp join public.role r on r.id = rp.role_id
   where r.name = 'usuario_comercial'
     and rp.permission_code in ('customers.read','customers.create','customers.update',
       'orders.read','orders.create','orders.update','orders.transition',
       'exports.read','exports.create','exports.update',
       'documents.read','documents.upload','documents.generate',
       'inventory.read','payments.read','payments.create','logistics.read');
  insert into chk values ('semilla', 'comercial tiene los 17 permisos comerciales definidos',
    n = 17 and (select count(*) from public.role_permission rp join public.role r on r.id = rp.role_id
                where r.name = 'usuario_comercial') = 17, n::text);

  -- 3. RLS y políticas -----------------------------------------------------------
  foreach t in array array['role','permission','role_permission','profile','audit_log','unit_of_measure','certification','product','coffee_detail','cacao_detail','product_certification','customer','customer_user','customer_order','order_line','inventory_movement','export','export_line','export_destination','incoterm','shipment','shipment_event','stored_file','export_document','notification','payment_obligation','payment_transaction','exchange_rate'] loop
    insert into chk select 'rls', 'RLS activa en public.'||t, c.relrowsecurity, null
      from pg_class c where c.oid = ('public.'||t)::regclass;
  end loop;
  insert into chk select 'rls', 'RLS activa en storage.objects', c.relrowsecurity, null
    from pg_class c where c.oid = 'storage.objects'::regclass;

  select count(*) into n from pg_policies where schemaname = 'public';
  insert into chk values ('rls', 'políticas en public (mínimo: 20)', n >= 20, n::text);
  select count(*) into n from pg_policies where schemaname = 'storage' and tablename = 'objects';
  insert into chk values ('rls', 'políticas en storage.objects (mínimo: 6)', n >= 6, n::text);
  select count(*) into n from pg_policies
   where schemaname = 'public' and roles <> '{authenticated}';
  insert into chk values ('rls', 'ninguna política abierta a anon/public', n = 0, n::text);

  -- Toda politica de public/storage debe exigir un permiso o una cuenta activa
  -- (detecta politicas que dejarian pasar a un usuario desactivado).
  select count(*) into n from pg_policies
   where schemaname in ('public','storage')
     and coalesce(qual, '') || coalesce(with_check, '') not like '%has_permission%'
     and coalesce(qual, '') || coalesce(with_check, '') not like '%is_active_user%'
     and coalesce(qual, '') || coalesce(with_check, '') not like '%current_profile_id%'
     and coalesce(qual, '') || coalesce(with_check, '') not like '%auth.uid()%';
  insert into chk values ('rls', 'toda politica exige permiso o cuenta activa', n = 0, n::text);

  -- 4. Funciones y triggers --------------------------------------------------------
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('has_permission','handle_new_user','handle_user_email_change',
                       'guard_profile_update','guard_role_update','set_role_permissions',
                       'grant_new_permission_to_administrator',
                       'is_active_user','sync_auth_access','current_user_role','audit_profile_role_change',
                       'create_product','update_product','set_product_active','set_product_certifications','_product_audit',
                       'create_supplier','update_supplier','set_supplier_active','_supplier_audit',
                       'create_farm','update_farm','set_farm_active','create_lot','_origin_audit',
                       'create_customer','update_customer','set_customer_active','_customer_audit',
                       'link_customer_user','unlink_customer_user','create_customer_order',
                       'transition_customer_order','update_customer_order','create_customer_export',
                       'stamp_export_shipment_actor','stamp_payment_obligation_actor','adjust_lot_inventory')
     and p.prosecdef
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%');
  insert into chk values ('funciones', '38 funciones SECURITY DEFINER con search_path fijo', n = 38, n::text);

  select count(*) into n from pg_trigger where not tgisinternal and tgname in
    ('on_auth_user_created','on_auth_user_email_changed','profile_guard','role_guard','profile_sync_auth_access',
     'profile_audit_role_change','audit_log_immutable','audit_log_no_truncate',
     'permission_grant_administrator',
     'product_guard','coffee_detail_type_guard','cacao_detail_type_guard','product_detail_required',
     'product_no_delete','coffee_detail_no_delete','cacao_detail_no_delete',
     'supplier_guard','supplier_no_delete',
     'farm_guard','farm_no_delete','product_lot_no_delete','product_lot_no_update',
     'customer_guard','customer_no_delete','export_guard','export_line_guard','export_actor_stamp',
     'shipment_actor_stamp','shipment_event_actor_stamp','customer_order_export_guard','payment_transaction_guard','payment_obligation_actor_stamp');
  insert into chk values ('triggers', '32 triggers de reglas y dominio', n = 32, n::text);

  -- 5. Privilegios ---------------------------------------------------------------
  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon';
  insert into chk values ('privilegios', 'anon sin privilegios en public', n = 0, n::text);

  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'profile' and grantee = 'authenticated'
     and privilege_type in ('INSERT','DELETE');
  insert into chk values ('privilegios', 'authenticated sin INSERT/DELETE en profile', n = 0, n::text);

  select string_agg(column_name, ',' order by column_name) into v
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'profile'
     and grantee = 'authenticated' and privilege_type = 'UPDATE';
  insert into chk values ('privilegios', 'UPDATE en profile solo en columnas editables',
    v = 'first_name,is_active,last_name,phone,role_id', v);

  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('authenticated','anon')
     and privilege_type in ('TRUNCATE','REFERENCES','TRIGGER');
  insert into chk values ('privilegios', 'sin TRUNCATE/REFERENCES/TRIGGER para authenticated ni anon (H1)', n = 0, n::text);

  select count(*) into n from information_schema.role_table_grants
   where table_schema='public' and table_name in ('export','export_line')
     and grantee='authenticated' and privilege_type='INSERT';
  insert into chk values ('privilegios', 'exportaciones solo se crean por RPC transaccional', n = 0, n::text);

  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name in ('permission','role_permission')
     and grantee = 'authenticated' and privilege_type in ('INSERT','UPDATE','DELETE');
  insert into chk values ('privilegios', 'authenticated sin escritura en permission/role_permission', n = 0, n::text);

  -- Vista de administracion y sus indices
  insert into chk select 'vista', 'admin_user_list existe con security_invoker',
    coalesce((select 'security_invoker=true' = any(c.reloptions) from pg_class c
              where c.oid = to_regclass('public.admin_user_list')), false), null;
  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'admin_user_list'
     and ((grantee = 'authenticated' and privilege_type <> 'SELECT') or grantee in ('anon','PUBLIC'));
  insert into chk values ('vista', 'admin_user_list: solo SELECT para authenticated, nada para anon', n = 0, n::text);
  select count(*) into n from pg_indexes
   where schemaname = 'public' and indexname in
     ('profile_first_name_trgm_idx','profile_last_name_trgm_idx','profile_email_trgm_idx');
  insert into chk values ('vista', '3 indices de busqueda (pg_trgm)', n = 3, n::text);

  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'audit_log'
     and ((grantee = 'authenticated' and privilege_type <> 'SELECT') or grantee in ('anon','PUBLIC'));
  insert into chk values ('privilegios', 'audit_log: solo SELECT para authenticated, nada para anon', n = 0, n::text);

  -- Modulo de productos
  select count(*) into n from public.unit_of_measure where code in ('kg', 't');
  select count(*) + n into n from public.certification where code in ('ORGANIC','FAIR_TRADE','RAINFOREST_ALLIANCE');
  insert into chk values ('productos', 'semilla: 2 unidades y 3 certificaciones base', n = 5, n::text);

  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('unit_of_measure','certification','product','coffee_detail','cacao_detail',
                        'product_certification','product_catalog')
     and ((grantee = 'authenticated' and privilege_type <> 'SELECT') or grantee in ('anon','PUBLIC'));
  insert into chk values ('productos', 'tablas y vista de productos: solo SELECT para authenticated, nada para anon', n = 0, n::text);

  insert into chk select 'productos', 'product_catalog es security_invoker',
    coalesce((select 'security_invoker=true' = any(c.reloptions) from pg_class c
              where c.oid = to_regclass('public.product_catalog')), false), null;

  select count(*) into n from unnest(array['public.create_product(jsonb)','public.update_product(bigint,jsonb)',
      'public.set_product_active(bigint,boolean)','public.set_product_certifications(bigint,bigint[])']) f
   where has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE');
  insert into chk values ('productos', 'las 4 funciones de escritura: authenticated si, anon no', n = 0, n::text);

  insert into chk values ('productos', 'indice unico de identidad del producto',
    to_regclass('public.product_identity_uq') is not null, null);

  -- Pedidos comerciales
  select count(*) into n from public.permission where code in ('orders.read','orders.create','orders.update','orders.transition');
  insert into chk values ('pedidos', 'permisos de lectura, registro, edición y transicion', n = 4, n::text);
  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name in ('customer_order','order_line')
     and ((grantee = 'authenticated' and privilege_type <> 'SELECT') or grantee in ('anon','PUBLIC'));
  insert into chk values ('pedidos', 'tablas de pedidos sin escritura directa ni acceso anonimo', n = 0, n::text);
  select count(*) into n from pg_class c
   where c.oid in (to_regclass('public.customer_order'), to_regclass('public.order_line'))
     and c.relrowsecurity;
  insert into chk values ('pedidos', 'RLS habilitado en cabecera y lineas', n = 2, n::text);
  select count(*) into n from unnest(array['public.create_customer_order(jsonb)']) f
   where has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE');
  insert into chk values ('pedidos', 'RPC de registro solo para authenticated', n = 0, n::text);
  select count(*) into n from unnest(array['public.transition_customer_order(jsonb)']) f
   where has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE');
  insert into chk values ('pedidos', 'RPC de transicion solo para authenticated', n = 0, n::text);
  select count(*) into n from unnest(array['public.update_customer_order(jsonb)']) f
   where has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE');
  insert into chk values ('pedidos', 'RPC de edición solo para authenticated', n = 0, n::text);
  insert into chk values ('pedidos', 'historial de estado con RLS',
    to_regclass('public.order_status_history') is not null
    and (select relrowsecurity from pg_class where oid = to_regclass('public.order_status_history')), null);
  insert into chk values ('pedidos', 'indices por cliente y por pedido/lote',
    to_regclass('public.customer_order_customer_idx') is not null
    and to_regclass('public.order_line_order_idx') is not null
    and to_regclass('public.order_line_lot_idx') is not null, null);
  insert into chk values ('pedidos', 'vista de pedidos con datos relacionados y permiso de lectura',
    to_regclass('public.customer_order_details') is not null
    and has_table_privilege('authenticated', 'public.customer_order_details', 'SELECT')
    and not has_table_privilege('anon', 'public.customer_order_details', 'SELECT'), null);

  -- 6. Storage --------------------------------------------------------------------
  select count(*) into n from storage.buckets where id in ('profile-photos','export-documents') and not public;
  insert into chk values ('storage', '2 buckets privados', n = 2, n::text);
end $$;

select seccion, comprobacion, case when ok then 'OK' else 'FALLA' end as resultado, coalesce(detalle, '') as detalle
from chk order by case when ok then 1 else 0 end, seccion, comprobacion;

do $$
declare f int;
begin
  select count(*) into f from chk where not ok;
  if f > 0 then raise exception 'La verificación falló en % comprobación(es)', f; end if;
end $$;
