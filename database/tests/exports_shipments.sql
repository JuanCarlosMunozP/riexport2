-- Verificaciones estructurales de exportaciones, documentos, finanzas y logística.
-- Solo lectura, requiere 20261022000000_export_eudr_declaration.sql.
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/exports_shipments.sql

begin;
do $$
declare
  t text;
  v text;
begin
  foreach t in array array['export','export_line','export_destination','incoterm','shipment','shipment_event','stored_file','export_document','notification','payment_obligation','payment_transaction','exchange_rate'] loop
    if to_regclass('public.'||t) is null then raise exception 'Falta tabla public.%', t; end if;
    if not (select relrowsecurity from pg_class where oid=('public.'||t)::regclass) then raise exception 'RLS no está activa en public.%', t; end if;
  end loop;
  foreach v in array array['export_catalog','shipment_catalog','export_traceability','export_origin_farms','shipment_origin_farms','customer_order_history','customer_export_history','customer_order_details','export_history'] loop
    if to_regclass('public.'||v) is null then raise exception 'Falta vista public.%', v; end if;
    if not has_table_privilege('authenticated','public.'||v,'SELECT') then raise exception 'authenticated no puede consultar public.%', v; end if;
    if has_table_privilege('anon','public.'||v,'SELECT') then raise exception 'anon tiene acceso a public.%', v; end if;
  end loop;
  if has_function_privilege('anon','public.create_customer_export(jsonb)','EXECUTE') then raise exception 'anon puede ejecutar create_customer_export'; end if;
  if not has_function_privilege('authenticated','public.create_customer_export(jsonb)','EXECUTE') then raise exception 'authenticated no puede ejecutar create_customer_export'; end if;
  if has_function_privilege('anon','public.update_customer_order(jsonb)','EXECUTE') then raise exception 'anon puede ejecutar update_customer_order'; end if;
  if not has_function_privilege('authenticated','public.update_customer_order(jsonb)','EXECUTE') then raise exception 'authenticated no puede ejecutar update_customer_order'; end if;
  if has_table_privilege('authenticated','public.export','INSERT') or has_table_privilege('authenticated','public.export_line','INSERT') then raise exception 'authenticated puede omitir el RPC de creación de exportaciones'; end if;
  if position('order_edit' in pg_get_functiondef('public.transition_customer_order(jsonb)'::regprocedure)) = 0 then raise exception 'La cancelación no repone los cambios de inventario por edición'; end if;
  if has_function_privilege('anon','public.export_eudr_declaration(bigint)','EXECUTE') then raise exception 'anon puede ejecutar export_eudr_declaration'; end if;
  if not has_function_privilege('authenticated','public.export_eudr_declaration(bigint)','EXECUTE') then raise exception 'authenticated no puede ejecutar export_eudr_declaration'; end if;
  if not exists(select 1 from public.permission where code='orders.update') then raise exception 'Falta permiso orders.update'; end if;
  if (select count(*) from public.incoterm where is_active) <> 11 then raise exception 'El catálogo debe contener los 11 Incoterms ICC 2020'; end if;
  if (select count(*) from public.export_destination where is_active) < 60 then raise exception 'El catálogo de destinos está incompleto'; end if;
  if not exists(select 1 from public.role_permission rp join public.role r on r.id=rp.role_id where r.name='usuario_comercial' and rp.permission_code='exports.create') then raise exception 'El rol comercial no tiene exports.create'; end if;
  if not exists(select 1 from pg_constraint where conrelid='public.inventory_movement'::regclass and conname='inventory_movement_order_shape' and pg_get_constraintdef(oid) like '%order_edit%') then raise exception 'Falta registrar ajustes de inventario por edición'; end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='export' and policyname='export_select_own') then raise exception 'Falta aislamiento del portal para export'; end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='shipment' and policyname='shipment_select_own') then raise exception 'Falta aislamiento del portal para shipment'; end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='export_documents_select') then raise exception 'Falta política de lectura privada de documentos'; end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='export_documents_insert') then raise exception 'Falta política de carga privada de documentos'; end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='payment_transaction' and policyname='payment_transaction_insert') then raise exception 'Falta permiso de escritura de pagos'; end if;
  if not exists(select 1 from pg_trigger where tgname='payment_transaction_guard' and not tgisinternal) then raise exception 'Falta validación transaccional del saldo'; end if;
end $$;
rollback;
