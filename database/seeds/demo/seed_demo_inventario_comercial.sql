-- Notificaciones de demostracion para el Gestor de Inventario y el Gestor Comercial
-- (solo desarrollo; NO ejecutar en produccion). Idempotente.
-- Requiere seed_demo_roles.sql, seed_demo_envios.sql y seed_demo_clientes_notificaciones.sql.

do $notif$
declare
  v_inv bigint; v_com bigint; v_l1 bigint; v_l2 bigint; v_l3 bigint;
  v_o1 bigint; v_o2 bigint; v_o3 bigint; v_o4 bigint;
begin
  select id into v_inv from public.profile where email = 'inventario@demo.riexport.test';
  select id into v_com from public.profile where email = 'comercial@demo.riexport.test';
  select id into v_l1 from public.product_lot where lot_code = 'DEMO-ENV-CAF-01';
  select id into v_l2 from public.product_lot where lot_code = 'DEMO-ENV-CAF-02';
  select id into v_l3 from public.product_lot where lot_code = 'DEMO-ENV-CAC-01';
  select o.id into v_o1 from public.customer_order o join public.export e on e.order_id = o.id join public.shipment s on s.export_id = e.id where s.tracking_number = 'MSKU-DEMO-0001';
  select o.id into v_o2 from public.customer_order o join public.export e on e.order_id = o.id join public.shipment s on s.export_id = e.id where s.tracking_number = 'HLCU-DEMO-4521';
  select o.id into v_o3 from public.customer_order o join public.export e on e.order_id = o.id join public.shipment s on s.export_id = e.id where s.tracking_number = 'MSC-DEMO-7788';
  select o.id into v_o4 from public.customer_order o join public.export e on e.order_id = o.id join public.shipment s on s.export_id = e.id where s.tracking_number = 'ONE-DEMO-3310';
  if v_inv is null or v_com is null or v_l1 is null or v_o1 is null then
    raise exception 'Faltan datos: ejecuta antes seed_demo_roles.sql, seed_demo_envios.sql y seed_demo_clientes_notificaciones.sql.';
  end if;

  delete from public.notification
   where recipient_user_id in (v_inv, v_com) and title like 'Demo:%';

  insert into public.notification (recipient_user_id, notification_type, title, body, entity_type, entity_id, created_at, read_at) values
    -- Gestor de Inventario
    (v_inv, 'low_stock',       'Demo: stock bajo en lote DEMO-ENV-CAC-01',
       'El cacao Criollo (Demo Envios) quedo en 1000 kg tras el ultimo pedido; el minimo configurado es 300 kg.', 'product_lot', v_l3, now() - interval '2 hours',  null),
    (v_inv, 'stock_movement',  'Demo: salida de inventario por pedido',
       'Se descontaron 1200 kg del lote DEMO-ENV-CAF-01 por el pedido de Importadora Demo GmbH.',               'product_lot', v_l1, now() - interval '1 day',    null),
    (v_inv, 'stock_movement',  'Demo: salida de inventario por pedido',
       'Se descontaron 600 kg del lote DEMO-ENV-CAF-01 por el pedido de Koffie Import B.V.',                    'product_lot', v_l1, now() - interval '4 days',   now() - interval '3 days'),
    (v_inv, 'stock_movement',  'Demo: ajuste de inventario registrado',
       'Se registro un ajuste de +3000 kg en el lote DEMO-ENV-CAF-02 (ingreso de cosecha).',                    'product_lot', v_l2, now() - interval '9 days',   now() - interval '9 days' + interval '1 hour'),
    -- Gestor Comercial
    (v_com, 'order_status',    'Demo: pedido confirmado',
       'El pedido de Importadora Demo GmbH (cafe Castillo, 1200 kg) esta confirmado y en aduana de destino.',  'customer_order', v_o1, now() - interval '3 hours',  null),
    (v_com, 'order_status',    'Demo: pedido en transito',
       'El pedido de Koffie Import B.V. (800 kg) viaja hacia Rotterdam; llegada estimada en 9 dias.',          'customer_order', v_o2, now() - interval '10 hours', null),
    (v_com, 'order_status',    'Demo: pedido pendiente de embarque',
       'El pedido de cacao Criollo (1500 kg) aun no tiene fecha de embarque confirmada.',                       'customer_order', v_o3, now() - interval '1 day',    null),
    (v_com, 'order_status',    'Demo: nuevo pedido registrado',
       'Se registro un pedido de Koffie Import B.V. por 600 kg de cafe para Amsterdam.',                        'customer_order', v_o4, now() - interval '4 days',   now() - interval '3 days');

  raise notice 'Notificaciones de inventario y comercial cargadas.';
end
$notif$;
