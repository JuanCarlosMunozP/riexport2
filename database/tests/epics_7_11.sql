-- Pruebas de EP-7 a EP-11 (documentos, inventario, pagos, logística y notificaciones).
-- Todo se revierte al final.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/epics_7_11.sql
-- Requiere la migración 20261023000000. Usuarios: sa (todo), sn (sin permisos),
-- cl (cliente externo con portal.read vinculado al cliente del pedido), cx (cliente externo ajeno).

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
  values (p_name, case when coalesce(p_ok, false) then 'OK' else 'FALLA: ' || p_detail end);
$$;

-- ------------------------------------------------------------ usuarios y roles ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'sa@ep7.test', '{"first_name":"Staff","last_name":"Total"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'sn@ep7.test', '{"first_name":"Sin","last_name":"Permisos"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'cl@ep7.test', '{"first_name":"Cliente","last_name":"Propio"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e4', 'authenticated', 'authenticated', 'cx@ep7.test', '{"first_name":"Cliente","last_name":"Ajeno"}', now(), now());

insert into public.role(name) values ('e7_staff'), ('e7_none'), ('e7_portal');
insert into public.role_permission(role_id, permission_code)
select r.id, p.code from public.role r, public.permission p
where r.name = 'e7_staff' and p.code in (
  'products.read','products.create','suppliers.create','suppliers.read','farms.read','farms.create','lots.read','lots.create',
  'customers.read','customers.create','customers.update','orders.read','orders.create','orders.transition','exports.read','exports.create',
  'documents.read','documents.generate','documents.upload','inventory.read','inventory.adjust',
  'logistics.read','logistics.create','logistics.update','payments.read','payments.create');
insert into public.role_permission(role_id, permission_code)
select r.id, 'portal.read' from public.role r where r.name = 'e7_portal';
update public.profile set role_id = (select id from public.role where name = 'e7_staff') where email = 'sa@ep7.test';
update public.profile set role_id = (select id from public.role where name = 'e7_none') where email = 'sn@ep7.test';
update public.profile set role_id = (select id from public.role where name = 'e7_portal') where email in ('cl@ep7.test', 'cx@ep7.test');

-- ------------------------------------------------------------------ datos base (sa) ---
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select public.create_supplier('{"business_name":"Proveedor EP7","tax_id":"NIT-EP7"}');
select public.create_farm(jsonb_build_object('supplier_id', (select id from public.supplier where tax_id = 'NIT-EP7'), 'country_code', 'CO', 'name', 'Finca EP7', 'latitude', 1.85, 'longitude', -76.05));
select public.create_product('{"type":"coffee","variety":"Caturra EP7","quality_grade":"Excelso","base_unit_code":"kg","humidity_percent":11,"low_stock_threshold":100,"hs_code":"0901.11"}');
select public.create_lot(jsonb_build_object('product_id', (select id from public.product where variety = 'Caturra EP7'), 'farm_id', (select id from public.farm where name = 'Finca EP7'), 'lot_code', 'EP7-L1'));
select public.adjust_lot_inventory(jsonb_build_object('product_lot_id', (select id from public.product_lot where lot_code = 'EP7-L1'), 'quantity_delta', 500));
select public.create_customer('{"name":"Cliente EP7","country_code":"US","preferred_currency_code":"USD"}');
select public.create_customer('{"name":"Cliente Ajeno EP7","country_code":"CA","preferred_currency_code":"EUR"}');
select public.link_customer_user((select id from public.customer where name = 'Cliente EP7'), 'cl@ep7.test');
select public.link_customer_user((select id from public.customer where name = 'Cliente Ajeno EP7'), 'cx@ep7.test');

select public.create_customer_order(jsonb_build_object('customer_id', (select id from public.customer where name = 'Cliente EP7'),
  'lines', jsonb_build_array(jsonb_build_object('product_lot_id', (select id from public.product_lot where lot_code = 'EP7-L1'), 'quantity', 300, 'unit_price', 4.5))));
select public.transition_customer_order(jsonb_build_object('order_id', (select max(id) from public.customer_order), 'status', 'confirmed'));
select public.create_customer_export(jsonb_build_object('order_id', (select max(id) from public.customer_order), 'destination_country_code', 'US',
  'lines', jsonb_build_array(jsonb_build_object('order_line_id', (select max(id) from public.order_line), 'quantity', 300))));

select pg_temp.check('el inventario descontó el pedido', (select available_quantity = 200 from public.lot_inventory_availability where product_lot_id = (select id from public.product_lot where lot_code = 'EP7-L1')));

-- ------------------------------------------------- EP-8: inventario consolidado y stock bajo ---
select pg_temp.check('vista consolidada: total del producto', (select available_quantity = 200 and lot_count = 1 from public.inventory_overview where variety = 'Caturra EP7'));
select pg_temp.check('vista consolidada: 200 > umbral 100, no es stock bajo', (select not is_low_stock from public.inventory_overview where variety = 'Caturra EP7'));
select pg_temp.attempt('no se permite dejar existencias negativas (ajuste)', $q$select public.adjust_lot_inventory(jsonb_build_object('product_lot_id', (select id from public.product_lot where lot_code = 'EP7-L1'), 'quantity_delta', -201))$q$, 'negativas');
select pg_temp.attempt('ni siquiera un INSERT directo burla el saldo', $q$insert into public.inventory_movement(product_lot_id, quantity_delta, movement_type) values ((select id from public.product_lot where lot_code = 'EP7-L1'), -999, 'adjustment')$q$, 'permission denied');
select pg_temp.rows('sin alerta mientras el stock supera el umbral', $q$select * from public.notification where notification_type = 'low_stock'$q$, 0);
select public.adjust_lot_inventory(jsonb_build_object('product_lot_id', (select id from public.product_lot where lot_code = 'EP7-L1'), 'quantity_delta', -150));
select pg_temp.check('vista consolidada: 50 <= umbral 100 es stock bajo', (select is_low_stock from public.inventory_overview where variety = 'Caturra EP7'));
select pg_temp.check('el movimiento disparó la alerta a quien consulta inventario', (select count(*) = 1 from public.notification where notification_type = 'low_stock' and recipient_user_id = public.current_profile_id()));
select public.adjust_lot_inventory(jsonb_build_object('product_lot_id', (select id from public.product_lot where lot_code = 'EP7-L1'), 'quantity_delta', -10));
select pg_temp.check('la alerta no se duplica el mismo día', (select count(*) = 1 from public.notification where notification_type = 'low_stock' and recipient_user_id = public.current_profile_id()));

-- ------------------------------------------------------------ EP-7: numeración y datos ---
select pg_temp.check('reserva el primer número de factura', public.reserve_document_number((select max(id) from public.export), 'commercial_invoice') = 'FAC-' || extract(year from now())::int || '-000001');
select pg_temp.check('la misma exportación conserva su número', public.reserve_document_number((select max(id) from public.export), 'commercial_invoice') = 'FAC-' || extract(year from now())::int || '-000001');
select pg_temp.check('cada serie es independiente', public.reserve_document_number((select max(id) from public.export), 'packing_list') = 'PL-' || extract(year from now())::int || '-000001');
select pg_temp.attempt('el resumen no usa numeración', $q$select public.reserve_document_number((select max(id) from public.export), 'export_summary')$q$, 'no usa numeración');
select pg_temp.attempt('exportación inexistente', $q$select public.reserve_document_number(999999, 'commercial_invoice')$q$, 'no existe');
select pg_temp.check('los datos del documento incluyen cliente, línea y origen',
  (select d->'customer'->>'name' = 'Cliente EP7' and jsonb_array_length(d->'lines') = 1
      and (d->'lines'->0->>'line_total')::numeric = 1350 and d->'lines'->0->>'farm_name' = 'Finca EP7'
      and d->'export'->>'destination_name' = 'Estados Unidos'
   from (select public.export_document_data((select max(id) from public.export)) d) x));

-- Sin objeto en Storage no se registra el documento.
select pg_temp.attempt('registrar sin archivo en Storage falla', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'commercial_invoice', 'object_path', 'exports/' || (select max(id) from public.export) || '/commercial_invoice/v1.pdf', 'original_name', 'f.pdf', 'mime_type', 'application/pdf', 'byte_size', 100))$q$, 'no se encuentra en el almacenamiento');

reset role;
insert into storage.objects(bucket_id, name, owner_id) values
  ('export-documents', 'exports/' || (select max(id) from public.export) || '/commercial_invoice/v1.pdf', '00000000-0000-0000-0000-0000000000e1'),
  ('export-documents', 'uploads/' || (select max(id) from public.export) || '/abc_fito.pdf', '00000000-0000-0000-0000-0000000000e1'),
  ('export-documents', 'uploads/' || (select max(id) from public.export) || '/abc_fito.exe', '00000000-0000-0000-0000-0000000000e1'),
  ('export-documents', 'uploads/' || (select max(id) from public.export) || '/abc_grande.pdf', '00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);

select pg_temp.check('registra la factura con su número',
  (select r->>'document_number' = 'FAC-' || extract(year from now())::int || '-000001' and (r->>'version')::int = 1
   from (select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'commercial_invoice',
     'document_number', 'FAC-' || extract(year from now())::int || '-000001',
     'object_path', 'exports/' || (select max(id) from public.export) || '/commercial_invoice/v1.pdf', 'original_name', 'f.pdf',
     'mime_type', 'application/pdf', 'byte_size', 2048)) r) x));
select pg_temp.check('el número queda emitido', (select status = 'issued' from public.document_number where document_type = 'commercial_invoice'));
select pg_temp.attempt('un número ajeno no se acepta', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'packing_list', 'document_number', 'FAC-2000-000009', 'object_path', 'exports/' || (select max(id) from public.export) || '/packing_list/v1.pdf', 'original_name', 'p.pdf', 'mime_type', 'application/pdf', 'byte_size', 10))$q$, 'no corresponde');
select pg_temp.attempt('fitosanitario PDF válido', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'phytosanitary_certificate', 'object_path', 'uploads/' || (select max(id) from public.export) || '/abc_fito.pdf', 'original_name', 'fito.pdf', 'mime_type', 'application/pdf', 'byte_size', 5000))$q$, 'ok');
select pg_temp.attempt('fitosanitario con tipo no permitido', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'phytosanitary_certificate', 'object_path', 'uploads/' || (select max(id) from public.export) || '/abc_fito.exe', 'original_name', 'fito.exe', 'mime_type', 'application/x-msdownload', 'byte_size', 5000))$q$, 'PDF, PNG o JPEG');
select pg_temp.attempt('fitosanitario con extensión que no coincide', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'phytosanitary_certificate', 'object_path', 'uploads/' || (select max(id) from public.export) || '/abc_fito.exe', 'original_name', 'fito.exe', 'mime_type', 'application/pdf', 'byte_size', 5000))$q$, 'extensión');
select pg_temp.attempt('fitosanitario de más de 10 MB', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'phytosanitary_certificate', 'object_path', 'uploads/' || (select max(id) from public.export) || '/abc_grande.pdf', 'original_name', 'grande.pdf', 'mime_type', 'application/pdf', 'byte_size', 10485761))$q$, '10 MB');
select pg_temp.attempt('ruta de otra exportación', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'phytosanitary_certificate', 'object_path', 'uploads/999/abc_fito.pdf', 'original_name', 'fito.pdf', 'mime_type', 'application/pdf', 'byte_size', 10))$q$, 'ruta del archivo');
select pg_temp.attempt('campo no permitido', $q$select public.register_export_document('{"export_id":1,"hack":true}')$q$, 'Campo no permitido');
select pg_temp.attempt('tipo de documento no válido', $q$select public.register_export_document(jsonb_build_object('export_id', (select max(id) from public.export), 'document_type', 'otro', 'byte_size', 1))$q$, 'tipo de documento');
select pg_temp.attempt('no se inserta stored_file directo', $q$insert into public.stored_file(bucket_id, object_path, original_name, mime_type, byte_size, uploaded_by_id) values ('export-documents', 'x', 'x.pdf', 'application/pdf', 1, 1)$q$, 'permission denied');
select pg_temp.rows('expediente: factura y fitosanitario', $q$select * from public.export_dossier$q$, 2);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: expediente vacío', $q$select * from public.export_dossier$q$, 0);
select pg_temp.attempt('sin permisos: no reserva números', $q$select public.reserve_document_number(1, 'commercial_invoice')$q$, 'No tienes permiso');
select pg_temp.attempt('sin permisos: no lee datos del documento', $q$select public.export_document_data(1)$q$, 'No tienes permiso');
select pg_temp.attempt('sin permisos: no adjunta', $q$select public.register_export_document(jsonb_build_object('export_id', 1, 'document_type', 'phytosanitary_certificate', 'byte_size', 1))$q$, 'No tienes permiso');

-- ------------------------------------------------------------------------- EP-9: pagos ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
insert into public.payment_obligation(export_id, amount_due, currency_code, due_date, reference, created_by_id)
values ((select max(id) from public.export), 1350, 'USD', current_date - 2, 'FAC-1', 0);
select pg_temp.check('cartera: obligación vencida sin pagos',
  (select status = 'overdue' and balance = 1350 and days_overdue = 2 and amount_paid = 0 from public.payment_portfolio));
select pg_temp.attempt('un pago no supera el saldo', $q$insert into public.payment_transaction(obligation_id, amount, currency_code, recorded_by_id) values ((select max(id) from public.payment_obligation), 1350.01, 'USD', 0)$q$, 'supera el saldo');
select pg_temp.attempt('el pago debe ir en la moneda de la obligación', $q$insert into public.payment_transaction(obligation_id, amount, currency_code, recorded_by_id) values ((select max(id) from public.payment_obligation), 10, 'EUR', 0)$q$, 'moneda');
insert into public.payment_transaction(obligation_id, amount, currency_code, reference, recorded_by_id)
values ((select max(id) from public.payment_obligation), 350, 'USD', 'Transferencia 1', 0);
select pg_temp.check('cartera: pago parcial reduce el saldo', (select amount_paid = 350 and balance = 1000 and status = 'overdue' from public.payment_portfolio));
insert into public.payment_transaction(obligation_id, amount, currency_code, recorded_by_id)
values ((select max(id) from public.payment_obligation), 1000, 'USD', 0);
select pg_temp.check('cartera: pagada por completo', (select status = 'paid' and balance = 0 and days_overdue = 0 from public.payment_portfolio));
select pg_temp.attempt('no se edita un pago', $q$update public.payment_transaction set amount = 1$q$, 'permission denied');

insert into public.payment_obligation(export_id, amount_due, currency_code, due_date, reference, created_by_id)
values ((select max(id) from public.export), 500, 'EUR', current_date + 2, 'FAC-2', 0);
create temp table ids as select max(id) as obligation_id from public.payment_obligation;
grant select on ids to authenticated;
select pg_temp.check('cartera: por vencer queda pendiente', (select status = 'pending' from public.payment_portfolio where reference = 'FAC-2'));
select pg_temp.attempt('registra una tasa manual', $q$select public.register_exchange_rate('{"base_currency_code":"EUR","quote_currency_code":"USD","rate":1.1,"source":"prueba"}')$q$, 'ok');
select pg_temp.attempt('una tasa debe ser positiva', $q$select public.register_exchange_rate('{"base_currency_code":"EUR","quote_currency_code":"USD","rate":-1,"source":"prueba"}')$q$, 'check');
select pg_temp.attempt('registra USD a COP', $q$select public.register_exchange_rate('{"base_currency_code":"USD","quote_currency_code":"COP","rate":4000,"source":"prueba"}')$q$, 'ok');
select pg_temp.check('conversión directa', (public.convert_amount(100, 'EUR', 'USD')->>'converted')::numeric = 110.00);
select pg_temp.check('conversión inversa', (public.convert_amount(110, 'USD', 'EUR')->>'converted')::numeric = 100.00);
select pg_temp.check('conversión cruzada por USD', (public.convert_amount(100, 'EUR', 'COP')->>'converted')::numeric = 440000.00);
select pg_temp.check('misma moneda', (public.convert_amount(10, 'USD', 'USD')->>'rate')::numeric = 1);
select pg_temp.attempt('sin tasa disponible', $q$select public.convert_amount(10, 'USD', 'JPY')$q$, 'No hay tasa');
select pg_temp.check('cartera convertida a USD', (select balance_converted = 550.00 from public.payment_portfolio_in('USD') c join public.payment_portfolio pp using (obligation_id) where pp.reference = 'FAC-2'));
select pg_temp.check('la ejecución forzada genera alertas de pago', (select (r->>'payments')::int = 1 from (select public.run_scheduled_alerts(true) r) x));
select pg_temp.check('se creó una notificación de pago por vencer', (select count(*) = 1 from public.notification where notification_type = 'payment_due'));
select pg_temp.check('no hay alerta para la obligación pagada', (select count(*) = 0 from public.notification where notification_type = 'payment_overdue'));

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
select pg_temp.rows('sin permisos: cartera vacía', $q$select * from public.payment_portfolio$q$, 0);
select pg_temp.attempt('sin permisos: no registra pagos', $q$insert into public.payment_transaction(obligation_id, amount, currency_code, recorded_by_id) values ((select obligation_id from ids), 1, 'EUR', 0)$q$, 'row-level security');
select pg_temp.attempt('sin permisos: no convierte', $q$select public.convert_amount(1, 'USD', 'EUR')$q$, 'No tienes permiso');
select pg_temp.attempt('sin permisos: no registra tasas', $q$select public.register_exchange_rate('{"base_currency_code":"EUR","quote_currency_code":"USD","rate":1}')$q$, 'No tienes permiso');

-- ------------------------------------------------------------------ EP-10: logística ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
insert into public.shipment(export_id, carrier, tracking_number, status, shipped_at, created_by_id, transport_mode)
values ((select max(id) from public.export), 'Maersk', 'MAEU123', 'delivered', now(), 0, 'sea');
select pg_temp.check('un envío nuevo siempre nace planificado', (select status = 'planned' and shipped_at is null and delivered_at is null from public.shipment));
select pg_temp.attempt('el estado no se edita directo', $q$update public.shipment set status = 'delivered'$q$, 'permission denied');
select pg_temp.attempt('los datos de transporte sí se editan', $q$update public.shipment set carrier = 'MSC', container_number = 'MSCU1234567'$q$, 'ok');
select pg_temp.attempt('un evento no se inserta directo', $q$insert into public.shipment_event(shipment_id, event_type) values (1, 'x')$q$, 'permission denied');
select pg_temp.attempt('transición no permitida (planned → delivered)', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'delivered'))$q$, 'No se puede pasar');
select pg_temp.attempt('estado inexistente', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'volando'))$q$, 'no es válido');
select pg_temp.attempt('coordenadas incompletas', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'in_transit', 'latitude', 4.6))$q$, 'juntas');
select pg_temp.attempt('planned → in_transit', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'in_transit', 'location', 'Puerto de Cartagena', 'latitude', 10.4, 'longitude', -75.5))$q$, 'ok');
select pg_temp.check('in_transit fija shipped_at', (select status = 'in_transit' and shipped_at is not null from public.shipment));
select pg_temp.attempt('in_transit → in_customs', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'in_customs', 'description', 'Inspección'))$q$, 'ok');
select pg_temp.attempt('in_customs → delivered', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'delivered', 'location', 'Hamburgo'))$q$, 'ok');
select pg_temp.check('delivered fija delivered_at', (select status = 'delivered' and delivered_at is not null from public.shipment));
select pg_temp.attempt('un envío entregado es terminal', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'in_transit'))$q$, 'No se puede pasar');
select pg_temp.attempt('evento libre', $q$select public.add_shipment_event(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'event_type', 'documentos_revisados', 'description', 'OK'))$q$, 'ok');
select pg_temp.rows('historial: 3 cambios de estado y un evento', $q$select * from public.shipment_event where shipment_id = (select max(id) from public.shipment)$q$, 4);
select pg_temp.check('el catálogo expone transporte y contenedor', (select transport_mode = 'sea' and container_number = 'MSCU1234567' from public.shipment_catalog));

-- Aislamiento entre clientes (PLAT-640).
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
select pg_temp.rows('el cliente propio ve su seguimiento', $q$select * from public.customer_shipment_tracking$q$, 1);
select pg_temp.check('el seguimiento muestra el último evento', (select last_event_type = 'documentos_revisados' and status_label = 'Entregado' from public.customer_shipment_tracking));
select pg_temp.rows('el cliente propio ve la línea de tiempo', $q$select * from public.shipment_event$q$, 4);
select pg_temp.rows('el cliente propio ve su expediente', $q$select * from public.export_dossier$q$, 2);
select pg_temp.rows('el cliente propio recibe sus avisos de envío', $q$select * from public.notification where notification_type = 'shipment_status'$q$, 3);
select pg_temp.rows('el cliente no ve la cartera', $q$select * from public.payment_portfolio$q$, 0);
select pg_temp.rows('el cliente no ve inventario', $q$select * from public.inventory_overview$q$, 0);
select pg_temp.attempt('el cliente no cambia estados', $q$select public.update_shipment_status(jsonb_build_object('shipment_id', (select max(id) from public.shipment), 'status', 'cancelled'))$q$, 'No tienes permiso');
select pg_temp.attempt('el cliente no reserva números', $q$select public.reserve_document_number(1, 'commercial_invoice')$q$, 'No tienes permiso');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
select pg_temp.rows('otro cliente no ve ese seguimiento', $q$select * from public.customer_shipment_tracking$q$, 0);
select pg_temp.rows('otro cliente no ve eventos ajenos', $q$select * from public.shipment_event$q$, 0);
select pg_temp.rows('otro cliente no ve expedientes ajenos', $q$select * from public.export_dossier$q$, 0);
select pg_temp.rows('otro cliente no ve avisos ajenos', $q$select * from public.notification$q$, 0);

-- ---------------------------------------------------------------- EP-11: notificaciones ---
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select pg_temp.check('el personal ve solo sus avisos (stock y pago)', (select count(*) = 2 from public.notification));
select pg_temp.rows('marcar leída una notificación', $q$update public.notification set read_at = now() where notification_type = 'low_stock'$q$, 1);
select pg_temp.check('quedan sin leer', (select count(*) = 1 from public.notification where read_at is null));
select pg_temp.attempt('no se edita el contenido', $q$update public.notification set title = 'x'$q$, 'permission denied');
select pg_temp.attempt('no se borran avisos', $q$delete from public.notification$q$, 'permission denied');
select pg_temp.attempt('no se crean avisos desde el cliente', $q$insert into public.notification(recipient_user_id, notification_type, title) values (1, 'x', 'x')$q$, 'permission denied');
select pg_temp.check('marcar todas como leídas', public.mark_all_notifications_read() = 1);
select pg_temp.check('la tarea programada respeta la ventana de 5 minutos (ya corrió arriba)',
  (select (r->>'skipped')::boolean from (select public.run_scheduled_alerts(false) r) x));
select pg_temp.check('la ejecución forzada no duplica avisos', (select (r->>'skipped')::boolean = false from (select public.run_scheduled_alerts(true) r) x) and (select count(*) = 2 from public.notification));
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
select pg_temp.attempt('el cliente no ejecuta funciones internas', $q$select public.check_low_stock()$q$, 'permission denied');

reset role;
set local role anon;
select pg_temp.attempt('anónimo: sin cartera', $q$select * from public.payment_portfolio$q$, 'permission denied');
select pg_temp.attempt('anónimo: sin expediente', $q$select * from public.export_dossier$q$, 'permission denied');
select pg_temp.attempt('anónimo: sin conversión', $q$select public.convert_amount(1, 'USD', 'EUR')$q$, 'permission denied');
select pg_temp.attempt('anónimo: sin avisos', $q$select * from public.notification$q$, 'permission denied');
reset role;

select n, prueba, resultado from resultados where resultado <> 'OK' order by n;
select count(*) filter (where resultado <> 'OK') as fallas, count(*) as pruebas from resultados;

rollback;
