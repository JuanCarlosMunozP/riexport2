-- Datos FICTICIOS para la demostracion (solo desarrollo; NO ejecutar en produccion).
-- Se carga tras seed.sql y es idempotente: si ya existe el
-- administrador demo no hace nada.
--
-- Cuentas (contrasena para todas: Demo2026!)
--   admin@demo.riexport.test       administrador
--   comercial@demo.riexport.test   usuario_comercial
--   logistica@demo.riexport.test   encargado_logistico
--   cliente@demo.riexport.test     cliente (portal; vinculado a Importadora Demo GmbH)
--
-- Contenido: proveedores, fincas, productos con lotes e inventario (uno bajo el umbral), 3 pedidos con
-- exportaciones, envios en distintos estados con su linea de tiempo, obligaciones de pago (pendiente,
-- parcial, vencida y pagada), tasas de cambio y notificaciones.

do $demo$
declare
  v_pass constant text := 'Demo2026!';
  v_admin_uid uuid; v_admin bigint; v_com bigint; v_log bigint; v_cli bigint;
  v_sup1 bigint; v_sup2 bigint; v_farm1 bigint; v_farm2 bigint; v_farm3 bigint;
  v_cust_de bigint; v_cust_us bigint; v_cust_nl bigint;
  v_p_cafe bigint; v_p_cafe2 bigint; v_p_cacao bigint; v_p_cacao2 bigint;
  v_l1 bigint; v_l2 bigint; v_l3 bigint; v_l4 bigint;
  v_o1 bigint; v_o2 bigint; v_o3 bigint; v_ol1 bigint; v_ol2 bigint; v_ol3 bigint;
  v_e1 bigint; v_e2 bigint; v_e3 bigint;
  v_s1 bigint; v_s2 bigint; v_s3 bigint;
  v_ob1 bigint; v_ob2 bigint; v_ob3 bigint; v_ob4 bigint;
  v_email text; v_uid uuid; v_first text; v_last text; v_role text;
begin
  if exists (select 1 from auth.users where email = 'admin@demo.riexport.test') then
    raise notice 'Datos demo ya cargados.';
    return;
  end if;

  -- Usuarios (auth.users + auth.identities; el trigger handle_new_user crea el profile) ------------
  for v_email, v_first, v_last, v_role in
    select * from (values
      ('admin@demo.riexport.test',     'Ana',    'Administradora', 'administrador'),
      ('comercial@demo.riexport.test', 'Carlos', 'Comercial',      'usuario_comercial'),
      ('logistica@demo.riexport.test', 'Laura',  'Logistica',      'encargado_logistico'),
      ('cliente@demo.riexport.test',   'Hans',   'Importador',     'cliente')) as t(e, f, l, r)
  loop
    v_uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change, email_change_token_new,
                            email_change_token_current, phone_change, phone_change_token, reauthentication_token)
    values ('00000000-0000-0000-0000-000000000000', v_uid, '', 'authenticated', v_email,
            crypt(v_pass, gen_salt('bf', 10)), now(),
            '{"provider":"email","providers":["email"]}',
            jsonb_build_object('first_name', v_first, 'last_name', v_last),
            now(), now(), '', '', '', '', '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_uid, v_uid::text, 'email',
            jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true), now(), now(), now());
    update public.profile set role_id = (select id from public.role where name = v_role)
     where auth_user_id = v_uid;
  end loop;

  select id, auth_user_id into v_admin, v_admin_uid from public.profile where email = 'admin@demo.riexport.test';
  select id into v_com from public.profile where email = 'comercial@demo.riexport.test';
  select id into v_log from public.profile where email = 'logistica@demo.riexport.test';
  select id into v_cli from public.profile where email = 'cliente@demo.riexport.test';

  -- Las funciones y triggers que estampan al actor usan auth.uid(): se simula la sesion del administrador.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_uid::text, true);

  -- Origen: proveedores y fincas ---------------------------------------------------------------
  select id into v_sup1 from public.supplier where lower(tax_id) = 'nit-900000001';
  insert into public.supplier (business_name, tax_id, contact_name, phone, email, location)
  values ('Cafes de Nariño Demo S.A.S.', 'NIT-900000002', 'Marta Quintero', '+57 300 000 0002',
          'narino.demo@example.com', 'Nariño, Colombia') returning id into v_sup2;
  insert into public.farm (supplier_id, country_code, name, address, latitude, longitude)
  select v_sup1, 'CO', 'Finca Demo El Mirador', 'Vereda Demo, Acevedo', 1.805000, -75.890000 returning id into v_farm2;
  select id into v_farm1 from public.farm where name = 'Finca Demo La Esperanza';
  insert into public.farm (supplier_id, country_code, name, address, latitude, longitude)
  values (v_sup2, 'CO', 'Finca Demo Altos de Sandoná', 'Vereda Demo, Sandoná', 1.283000, -77.470000)
  returning id into v_farm3;

  -- Clientes ----------------------------------------------------------------------------------
  select id into v_cust_de from public.customer where eori_number = 'DE123456789012';
  insert into public.customer (name, contact_name, email, country_code, preferred_currency_code)
  values ('Specialty Roasters Inc. (Demo)', 'Emily Carter', 'compras.us.demo@example.com', 'US', 'USD')
  returning id into v_cust_us;
  insert into public.customer (name, contact_name, email, country_code, eori_number, preferred_currency_code)
  values ('Koffie Import B.V. (Demo)', 'Jan de Vries', 'compras.nl.demo@example.com', 'NL', 'NL123456789012', 'EUR')
  returning id into v_cust_nl;
  insert into public.customer_user (customer_id, profile_id) values (v_cust_de, v_cli);
  -- El rol cliente no trae permisos por defecto: se le da el acceso al portal (lo gestiona la pantalla de roles).
  insert into public.role_permission (role_id, permission_code)
  select id, 'portal.read' from public.role where name = 'cliente' on conflict do nothing;

  -- Productos y lotes -------------------------------------------------------------------------
  insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
  values ('coffee', 'Castillo (Demo)', 'Excelso EP', '0901.11', 'kg', 500) returning id into v_p_cafe;
  insert into public.coffee_detail (product_id, humidity_percent) values (v_p_cafe, 11.5);
  insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
  values ('coffee', 'Geisha (Demo)', 'Especial 87+', '0901.11', 'kg', 100) returning id into v_p_cafe2;
  insert into public.coffee_detail (product_id, humidity_percent) values (v_p_cafe2, 10.8);
  insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
  values ('cacao', 'Criollo (Demo)', 'Premium', '1801.00', 'kg', 300) returning id into v_p_cacao;
  insert into public.cacao_detail (product_id, bean_type, fermentation_percent) values (v_p_cacao, 'Criollo', 82);
  insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
  values ('cacao', 'CCN-51 (Demo)', 'Estandar', '1801.00', 'kg', 1000) returning id into v_p_cacao2;
  insert into public.cacao_detail (product_id, bean_type, fermentation_percent) values (v_p_cacao2, 'CCN-51', 70);
  insert into public.product_certification (product_id, certification_id)
  select p.id, c.id from (values (v_p_cafe, 'ORGANIC'), (v_p_cacao, 'FAIR_TRADE'), (v_p_cacao, 'ORGANIC')) as p(id, code)
  join public.certification c on c.code = p.code;

  insert into public.product_lot (product_id, farm_id, lot_code) values (v_p_cafe,   v_farm1, 'DEMO-CAF-2026-01') returning id into v_l1;
  insert into public.product_lot (product_id, farm_id, lot_code) values (v_p_cafe2,  v_farm2, 'DEMO-GEI-2026-01') returning id into v_l2;
  insert into public.product_lot (product_id, farm_id, lot_code) values (v_p_cacao,  v_farm3, 'DEMO-CAC-2026-01') returning id into v_l3;
  insert into public.product_lot (product_id, farm_id, lot_code) values (v_p_cacao2, v_farm3, 'DEMO-CCN-2026-01') returning id into v_l4;

  insert into public.inventory_movement (product_lot_id, quantity_delta, movement_type, performed_by_id) values
    (v_l1, 6000, 'adjustment', v_admin), (v_l2, 800, 'adjustment', v_admin),
    (v_l3, 2500, 'adjustment', v_admin), (v_l4, 1500, 'adjustment', v_admin);

  -- Pedidos (confirmados) y su salida de inventario -------------------------------------------------
  insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
  values (v_cust_de, null, 'EUR', 'Pedido demo: cafe Castillo para tostion en Hamburgo.', v_com) returning id into v_o1;
  insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
  values (v_o1, v_l1, 1200, 4.80, 'EUR', '0901.11') returning id into v_ol1;
  insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
  values (v_cust_us, null, 'USD', 'Pedido demo: Geisha microlote para Miami.', v_com) returning id into v_o2;
  insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
  values (v_o2, v_l2, 720, 14.50, 'USD', '0901.11') returning id into v_ol2;
  insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
  values (v_cust_nl, null, 'EUR', 'Pedido demo: cacao Criollo para chocolateria.', v_com) returning id into v_o3;
  insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
  values (v_o3, v_l3, 2300, 5.90, 'EUR', '1801.00') returning id into v_ol3;
  update public.customer_order set status = 'confirmed' where id in (v_o1, v_o2, v_o3);
  insert into public.inventory_movement (product_lot_id, quantity_delta, movement_type, order_id, performed_by_id) values
    (v_l1, -1200, 'order', v_o1, v_com), (v_l2, -720, 'order', v_o2, v_com), (v_l3, -2300, 'order', v_o3, v_com);

  -- Exportaciones -----------------------------------------------------------------------------
  insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
  values (v_o1, 'DE', current_date - 20, 'FOB', 'draft') returning id into v_e1;
  insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
  values (v_e1, v_ol1, v_l1, 1200, '0901.11');
  insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
  values (v_o2, 'US', current_date - 8, 'CIF', 'draft') returning id into v_e2;
  insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
  values (v_e2, v_ol2, v_l2, 720, '0901.11');
  insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
  values (v_o3, 'NL', current_date + 5, 'FOB', 'draft') returning id into v_e3;
  insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
  values (v_e3, v_ol3, v_l3, 2300, '1801.00');
  update public.export set status = 'formalized' where id in (v_e1, v_e2, v_e3);

  -- Envios con linea de tiempo ------------------------------------------------------------------
  insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode, container_number)
  values (v_e1, 'Maersk (Demo)', 'MSKU-DEMO-0001', current_date + 6, 'sea', 'MSKU1234567') returning id into v_s1;
  update public.shipment set status = 'in_transit', shipped_at = now() - interval '18 days' where id = v_s1;
  update public.shipment set status = 'in_customs' where id = v_s1;
  insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id) values
    (v_s1, 'planned',    'Envio planificado con la naviera.',            'Cartagena, Colombia', now() - interval '20 days', v_log),
    (v_s1, 'in_transit', 'Contenedor cargado y buque zarpado.',          'Cartagena, Colombia', now() - interval '18 days', v_log),
    (v_s1, 'incident',   'Retraso de 2 dias por congestion en puerto.',  'Algeciras, Espana',   now() - interval '7 days',  v_log),
    (v_s1, 'in_customs', 'En despacho de aduana de destino.',            'Hamburgo, Alemania',  now() - interval '1 day',   v_log);

  insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode)
  values (v_e2, 'DHL Global Forwarding (Demo)', 'DHL-DEMO-4521', current_date + 2, 'air') returning id into v_s2;
  update public.shipment set status = 'in_transit', shipped_at = now() - interval '3 days' where id = v_s2;
  insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id) values
    (v_s2, 'planned',    'Reserva de carga aerea confirmada.',  'Bogota, Colombia', now() - interval '5 days', v_log),
    (v_s2, 'in_transit', 'Carga despachada en vuelo directo.',  'Bogota, Colombia', now() - interval '3 days', v_log);

  insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode, container_number)
  values (v_e3, 'MSC (Demo)', 'MSC-DEMO-7788', current_date + 30, 'sea', 'MSCU7654321') returning id into v_s3;
  insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id)
  values (v_s3, 'planned', 'Envio planificado; pendiente de embarque.', 'Buenaventura, Colombia', now() - interval '1 day', v_log);

  -- Pagos: pendiente, parcial, vencida y pagada ------------------------------------------------------
  insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
  values (v_e1, 5760.00, 'EUR', current_date + 15, 'FAC-DEMO-001 (cafe Castillo)', v_admin) returning id into v_ob1;
  insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
  values (v_e2, 10440.00, 'USD', current_date - 6, 'FAC-DEMO-002 (Geisha)', v_admin) returning id into v_ob2;
  insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
  values (v_e3, 13570.00, 'EUR', current_date + 40, 'FAC-DEMO-003 (cacao Criollo)', v_admin) returning id into v_ob3;
  insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
  values (v_e1, 800.00, 'EUR', current_date - 12, 'Flete y seguro demo', v_admin) returning id into v_ob4;
  insert into public.payment_transaction (obligation_id, amount, currency_code, reference, paid_at, recorded_by_id) values
    (v_ob1, 2880.00, 'EUR', 'Anticipo 50 %',          now() - interval '15 days', v_admin),
    (v_ob2, 3000.00, 'USD', 'Pago parcial transfer.', now() - interval '10 days', v_admin),
    (v_ob4, 800.00,  'EUR', 'Pago total',             now() - interval '11 days', v_admin);

  -- Tasas de cambio (referencia para la demo; la Edge Function refresh-exchange-rates las actualiza) -------
  insert into public.exchange_rate (base_currency_code, quote_currency_code, rate, effective_at, source) values
    ('USD', 'EUR', 0.9200,   now() - interval '1 day', 'demo'),
    ('USD', 'COP', 4100.00,  now() - interval '1 day', 'demo'),
    ('USD', 'GBP', 0.7900,   now() - interval '1 day', 'demo');

  -- Notificaciones (las de stock bajo ya las genera el trigger al registrar el inventario) ------------------
  insert into public.notification (recipient_user_id, notification_type, title, body, entity_type, entity_id, created_at, read_at) values
    (v_admin, 'payment_overdue',  'Pago vencido: FAC-DEMO-002', 'La obligacion de 10440.00 USD vencio hace 6 dias.', 'payment_obligation', v_ob2, now() - interval '2 hours', null),
    (v_admin, 'shipment_status',  'Envio MSKU-DEMO-0001 en aduana', 'El contenedor esta en despacho en Hamburgo.',    'shipment',           v_s1,  now() - interval '1 day',   now() - interval '20 hours'),
    (v_log,   'shipment_status',  'Envio DHL-DEMO-4521 en transito', 'Entrega estimada en 2 dias.',                   'shipment',           v_s2,  now() - interval '3 hours', null),
    (v_cli,   'shipment_status',  'Tu envio esta en aduana',    'Tu pedido llego a Hamburgo y esta en despacho.',     'shipment',           v_s1,  now() - interval '1 day',   null);

  raise notice 'Datos demo cargados (admin@demo.riexport.test / %).', v_pass;
end
$demo$;
