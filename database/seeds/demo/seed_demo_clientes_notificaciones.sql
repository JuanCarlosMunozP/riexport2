-- Segundo cliente demo (aislamiento entre clientes) y notificaciones de demostracion.
-- Solo desarrollo; NO ejecutar en produccion. Idempotente.
-- Requiere seed_demo_roles.sql y seed_demo_envios.sql.
--
--   cliente@demo.riexport.test   -> Importadora Demo GmbH   (3 envios)
--   cliente2@demo.riexport.test  -> Koffie Import B.V.      (1 envio)
-- Cada cuenta de cliente solo ve los envios y notificaciones de su propio cliente.

do $clientes$
declare
  v_admin bigint; v_admin_uid uuid; v_com bigint; v_log bigint; v_cli bigint; v_cli2 bigint;
  v_cust2 bigint; v_l bigint; v_o bigint; v_ol bigint; v_e bigint; v_s bigint;
  v_s1 bigint; v_s2 bigint; v_s3 bigint;
begin
  select id, auth_user_id into v_admin, v_admin_uid from public.profile where email = 'admin@demo.riexport.test';
  select id into v_com  from public.profile where email = 'comercial@demo.riexport.test';
  select id into v_log  from public.profile where email = 'logistica@demo.riexport.test';
  select id into v_cli  from public.profile where email = 'cliente@demo.riexport.test';
  select id into v_cli2 from public.profile where email = 'cliente2@demo.riexport.test';
  select id into v_s1 from public.shipment where tracking_number = 'MSKU-DEMO-0001';
  select id into v_s2 from public.shipment where tracking_number = 'HLCU-DEMO-4521';
  select id into v_s3 from public.shipment where tracking_number = 'MSC-DEMO-7788';
  if v_admin is null or v_cli is null or v_cli2 is null or v_s1 is null then
    raise exception 'Faltan datos: ejecuta antes seed_demo_roles.sql y seed_demo_envios.sql.';
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_uid::text, true);

  -- Segundo cliente, su cuenta y un envio propio -----------------------------------------------
  select id into v_cust2 from public.customer where name = 'Koffie Import B.V. (Demo)';
  if v_cust2 is null then
    insert into public.customer (name, contact_name, email, country_code, eori_number, preferred_currency_code)
    values ('Koffie Import B.V. (Demo)', 'Jan de Vries', 'cliente2@demo.riexport.test', 'NL', 'NL123456789012', 'EUR')
    returning id into v_cust2;
  end if;
  insert into public.customer_user (customer_id, profile_id) values (v_cust2, v_cli2) on conflict do nothing;

  if not exists (select 1 from public.shipment where tracking_number = 'ONE-DEMO-3310') then
    select id into v_l from public.product_lot where lot_code = 'DEMO-ENV-CAF-01';
    insert into public.customer_order (customer_id, order_number, currency_code, note, created_by_id)
    values (v_cust2, null, 'EUR', 'Pedido demo: cafe para Amsterdam (otro cliente).', v_com) returning id into v_o;
    insert into public.order_line (order_id, product_lot_id, quantity, unit_price, currency_code, hs_code_snapshot)
    values (v_o, v_l, 600, 4.95, 'EUR', '0901.11') returning id into v_ol;
    update public.customer_order set status = 'confirmed' where id = v_o;
    insert into public.inventory_movement (product_lot_id, quantity_delta, movement_type, order_id, performed_by_id)
    values (v_l, -600, 'order', v_o, v_com);
    insert into public.export (order_id, destination_country_code, export_date, incoterm_code, status)
    values (v_o, 'NL', current_date - 4, 'FOB', 'draft') returning id into v_e;
    insert into public.export_line (export_id, order_line_id, product_lot_id, quantity, hs_code_snapshot)
    values (v_e, v_ol, v_l, 600, '0901.11');
    update public.export set status = 'formalized' where id = v_e;
    insert into public.shipment (export_id, carrier, tracking_number, estimated_delivery_at, transport_mode, container_number)
    values (v_e, 'ONE (Demo)', 'ONE-DEMO-3310', current_date + 12, 'sea', 'ONEU9988776') returning id into v_s;
    update public.shipment set status = 'in_transit', shipped_at = now() - interval '2 days' where id = v_s;
    insert into public.shipment_event (shipment_id, event_type, description, location, event_at, recorded_by_id) values
      (v_s, 'planned',    'Reserva de contenedor confirmada.', 'Cartagena, Colombia', now() - interval '4 days', v_log),
      (v_s, 'in_transit', 'Buque zarpado hacia Amsterdam.',    'Cartagena, Colombia', now() - interval '2 days', v_log);
  end if;
  select id into v_s from public.shipment where tracking_number = 'ONE-DEMO-3310';

  -- Notificaciones: se reemplazan las demo anteriores para poder repetir el seed ------------------
  delete from public.notification where title like '%(demo)%' or title like 'Demo:%';
  insert into public.notification (recipient_user_id, notification_type, title, body, entity_type, entity_id, created_at, read_at) values
    -- Cliente 1 (Importadora Demo GmbH): solo sus envios
    (v_cli,  'shipment_status', 'Demo: tu envio esta en aduana',       'El contenedor MSKU-DEMO-0001 llego a Hamburgo y esta en despacho.', 'shipment', v_s1, now() - interval '1 day',    null),
    (v_cli,  'shipment_status', 'Demo: tu envio salio de Cartagena',   'El buque con HLCU-DEMO-4521 zarpo hacia Rotterdam.',                'shipment', v_s2, now() - interval '6 days',   now() - interval '5 days'),
    (v_cli,  'shipment_status', 'Demo: nuevo envio planificado',       'Se planifico MSC-DEMO-7788 con salida desde Buenaventura.',         'shipment', v_s3, now() - interval '12 hours', null),
    -- Cliente 2 (Koffie Import B.V.): solo su envio
    (v_cli2, 'shipment_status', 'Demo: tu envio esta en transito',     'El buque con ONE-DEMO-3310 zarpo hacia Amsterdam.',                 'shipment', v_s,  now() - interval '2 days',   null),
    -- Personal interno
    (v_admin,'shipment_status', 'Demo: envio MSKU-DEMO-0001 en aduana','El contenedor esta en despacho en Hamburgo.',                       'shipment', v_s1, now() - interval '1 day',    null),
    (v_log,  'shipment_status', 'Demo: envio HLCU-DEMO-4521 en transito','Entrega estimada en 9 dias.',                                    'shipment', v_s2, now() - interval '3 hours',  null),
    (v_com,  'shipment_status', 'Demo: pedido en camino',              'El pedido de Importadora Demo GmbH ya esta en aduana de destino.',  'shipment', v_s1, now() - interval '20 hours', null);

  raise notice 'Cliente 2 y notificaciones demo cargados.';
end
$clientes$;
