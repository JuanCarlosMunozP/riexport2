-- Envios FICTICIOS para ver el "Seguimiento de mis envios" del portal del cliente
-- (solo desarrollo; NO ejecutar en produccion). Idempotente.
-- Requiere las cuentas de database/seeds/demo/seed_demo_roles.sql y el cliente "Importadora Demo GmbH"
-- vinculado a cliente@demo.riexport.test. Crea el origen minimo (proveedor, finca, producto, lote),
-- 3 pedidos confirmados con su exportacion y 3 envios del cliente: en aduana, en transito y planificado.

do $envios$
declare
  v_admin bigint; v_admin_uid uuid; v_com bigint; v_log bigint; v_cli bigint;
  v_cust bigint;
  v_sup bigint; v_farm bigint; v_prod bigint; v_prod2 bigint; v_l1 bigint; v_l2 bigint; v_l3 bigint;
  v_o1 bigint; v_o2 bigint; v_o3 bigint; v_ol1 bigint; v_ol2 bigint; v_ol3 bigint;
  v_e1 bigint; v_e2 bigint; v_e3 bigint; v_s1 bigint; v_s2 bigint; v_s3 bigint;
begin
  if exists (select 1 from public.shipment where tracking_number = 'MSKU-DEMO-0001') then
    raise notice 'Envios demo ya cargados.';
    return;
  end if;

  select id, auth_user_id into v_admin, v_admin_uid from public.profile where email = 'admin@demo.riexport.test';
  select id into v_com from public.profile where email = 'comercial@demo.riexport.test';
  select id into v_log from public.profile where email = 'logistica@demo.riexport.test';
  select id into v_cli from public.profile where email = 'cliente@demo.riexport.test';
  select id into v_cust from public.customer where name = 'Importadora Demo GmbH';
  if v_admin is null or v_com is null or v_log is null or v_cust is null then
    raise exception 'Faltan las cuentas demo o el cliente Importadora Demo GmbH (ver seed_demo_roles.sql).';
  end if;
  insert into public.customer_user (customer_id, profile_id) values (v_cust, v_cli) on conflict do nothing;

  -- Las funciones y triggers que estampan al actor usan auth.uid(): se simula la sesion del administrador.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_uid::text, true);

  -- Origen minimo ------------------------------------------------------------------------------
  insert into public.supplier (business_name, tax_id, contact_name, phone, email, location)
  values ('Cooperativa Cafetera Demo del Huila', 'NIT-900000101', 'Marta Quintero', '+57 300 000 0101',
          'huila.demo@example.com', 'Huila, Colombia') returning id into v_sup;
  insert into public.farm (supplier_id, country_code, name, address, latitude, longitude)
  values (v_sup, 'CO', 'Finca Demo Envios El Paraiso', 'Vereda Demo, Pitalito', 1.853000, -76.050000)
  returning id into v_farm;

  insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
  values ('coffee', 'Castillo (Demo Envios)', 'Excelso EP', '0901.11', 'kg', 500) returning id into v_prod;
  insert into public.coffee_detail (product_id, humidity_percent) values (v_prod, 11.5);
  insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
  values ('cacao', 'Criollo (Demo Envios)', 'Premium', '1801.00', 'kg', 300) returning id into v_prod2;
  insert into public.cacao_detail (product_id, bean_type, fermentation_percent) values (v_prod2, 'Criollo', 82);

  insert into public.product_lot (product_id, farm_id, lot_code) values (v_prod,  v_farm, 'DEMO-ENV-CAF-01') returning id into v_l1;
  insert into public.product_lot (product_id, farm_id, lot_code) values (v_prod,  v_farm, 'DEMO-ENV-CAF-02') returning id into v_l2;
  insert into public.product_lot (product_id, farm_id, lot_code) values (v_prod2, v_farm, 'DEMO-ENV-CAC-01') returning id into v_l3;
  insert into public.inventory_movement (product_lot_id, quantity_delta, movement_type, performed_by_id) values
    (v_l1, 5000, 'adjustment', v_admin), (v_l2, 3000, 'adjustment', v_admin), (v_l3, 2500, 'adjustment', v_admin);

  -- Pedidos confirmados del cliente ----------------------------------------------------------------
  insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
  values (v_cust, null, 'EUR', 'Pedido demo: cafe Castillo para tostion en Hamburgo.', v_com) returning id into v_o1;
  insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
  values (v_o1, v_l1, 1200, 4.80, 'EUR', '0901.11') returning id into v_ol1;
  insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
  values (v_cust, null, 'EUR', 'Pedido demo: segundo lote de cafe para Rotterdam.', v_com) returning id into v_o2;
  insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
  values (v_o2, v_l2, 800, 5.10, 'EUR', '0901.11') returning id into v_ol2;
  insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
  values (v_cust, null, 'EUR', 'Pedido demo: cacao Criollo para chocolateria.', v_com) returning id into v_o3;
  insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
  values (v_o3, v_l3, 1500, 5.90, 'EUR', '1801.00') returning id into v_ol3;
  update public.customer_order set status = 'confirmed' where id in (v_o1, v_o2, v_o3);
  insert into public.inventory_movement (product_lot_id, quantity_delta, movement_type, order_id, performed_by_id) values
    (v_l1, -1200, 'order', v_o1, v_com), (v_l2, -800, 'order', v_o2, v_com), (v_l3, -1500, 'order', v_o3, v_com);

  -- Exportaciones formalizadas --------------------------------------------------------------------
  insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
  values (v_o1, 'DE', current_date - 20, 'FOB', 'draft') returning id into v_e1;
  insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
  values (v_e1, v_ol1, v_l1, 1200, '0901.11');
  insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
  values (v_o2, 'NL', current_date - 8, 'CIF', 'draft') returning id into v_e2;
  insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
  values (v_e2, v_ol2, v_l2, 800, '0901.11');
  insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
  values (v_o3, 'DE', current_date + 5, 'FOB', 'draft') returning id into v_e3;
  insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
  values (v_e3, v_ol3, v_l3, 1500, '1801.00');
  update public.export set status = 'formalized' where id in (v_e1, v_e2, v_e3);

  -- Envios con linea de tiempo ------------------------------------------------------------------------
  insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode, container_number)
  values (v_e1, 'Maersk (Demo)', 'MSKU-DEMO-0001', current_date + 6, 'sea', 'MSKU1234567') returning id into v_s1;
  update public.shipment set status = 'in_transit', shipped_at = now() - interval '18 days' where id = v_s1;
  update public.shipment set status = 'in_customs' where id = v_s1;
  insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id) values
    (v_s1, 'planned',    'Envio planificado con la naviera.',           'Cartagena, Colombia', now() - interval '20 days', v_log),
    (v_s1, 'in_transit', 'Contenedor cargado y buque zarpado.',         'Cartagena, Colombia', now() - interval '18 days', v_log),
    (v_s1, 'incident',   'Retraso de 2 dias por congestion en puerto.', 'Algeciras, Espana',   now() - interval '7 days',  v_log),
    (v_s1, 'in_customs', 'En despacho de aduana de destino.',           'Hamburgo, Alemania',  now() - interval '1 day',   v_log);

  insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode, container_number)
  values (v_e2, 'Hapag-Lloyd (Demo)', 'HLCU-DEMO-4521', current_date + 9, 'sea', 'HLCU4455667') returning id into v_s2;
  update public.shipment set status = 'in_transit', shipped_at = now() - interval '6 days' where id = v_s2;
  insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id) values
    (v_s2, 'planned',    'Reserva de contenedor confirmada.',        'Cartagena, Colombia', now() - interval '9 days', v_log),
    (v_s2, 'in_transit', 'Buque zarpado hacia Rotterdam.',           'Cartagena, Colombia', now() - interval '6 days', v_log);

  insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode, container_number)
  values (v_e3, 'MSC (Demo)', 'MSC-DEMO-7788', current_date + 30, 'sea', 'MSCU7654321') returning id into v_s3;
  insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id)
  values (v_s3, 'planned', 'Envio planificado; pendiente de embarque.', 'Buenaventura, Colombia', now() - interval '1 day', v_log);

  raise notice 'Envios demo cargados para Importadora Demo GmbH.';
end
$envios$;
