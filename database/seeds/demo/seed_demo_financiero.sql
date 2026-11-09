-- Datos de demostracion para el Gestor Financiero (solo desarrollo; NO ejecutar en produccion).
-- Idempotente. Requiere seed_demo_roles.sql, seed_demo_envios.sql y seed_demo_clientes_notificaciones.sql.
--
-- Carga la cartera de pagos de las 4 exportaciones demo (pendiente, parcial, vencida y pagada),
-- tasas de cambio de referencia y notificaciones financieras.

do $financiero$
declare
  v_fin bigint; v_fin_uid uuid; v_admin bigint;
  v_e1 bigint; v_e2 bigint; v_e3 bigint; v_e4 bigint;
  v_ob1 bigint; v_ob2 bigint; v_ob3 bigint; v_ob4 bigint; v_ob5 bigint;
begin
  select id, auth_user_id into v_fin, v_fin_uid from public.profile where email = 'financiero@demo.riexport.test';
  select id into v_admin from public.profile where email = 'admin@demo.riexport.test';
  select e.id into v_e1 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'MSKU-DEMO-0001';
  select e.id into v_e2 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'HLCU-DEMO-4521';
  select e.id into v_e3 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'MSC-DEMO-7788';
  select e.id into v_e4 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'ONE-DEMO-3310';
  if v_fin is null or v_e1 is null or v_e4 is null then
    raise exception 'Faltan datos: ejecuta antes seed_demo_roles.sql, seed_demo_envios.sql y seed_demo_clientes_notificaciones.sql.';
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_fin_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_fin_uid::text, true);

  -- Cartera: pendiente, parcial, vencida, pagada y pendiente a largo plazo ------------------------------
  if not exists (select 1 from public.payment_obligation where reference = 'FAC-DEMO-001 (cafe Castillo)') then
    insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
    values (v_e1, 5760.00, 'EUR', current_date + 15, 'FAC-DEMO-001 (cafe Castillo)', v_fin) returning id into v_ob1;
    insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
    values (v_e2, 4080.00, 'EUR', current_date - 6, 'FAC-DEMO-002 (cafe Rotterdam)', v_fin) returning id into v_ob2;
    insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
    values (v_e3, 8850.00, 'EUR', current_date + 40, 'FAC-DEMO-003 (cacao Criollo)', v_fin) returning id into v_ob3;
    insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
    values (v_e1, 800.00, 'EUR', current_date - 12, 'Flete y seguro demo', v_fin) returning id into v_ob4;
    insert into public.payment_obligation (export_id, amount_due, currency_code, due_date, reference, created_by_id)
    values (v_e4, 2970.00, 'EUR', current_date + 25, 'FAC-DEMO-004 (cafe Amsterdam)', v_fin) returning id into v_ob5;

    insert into public.payment_transaction (obligation_id, amount, currency_code, reference, paid_at, recorded_by_id) values
      (v_ob1, 2880.00, 'EUR', 'Anticipo 50 %',          now() - interval '15 days', v_fin),
      (v_ob2, 1500.00, 'EUR', 'Pago parcial transfer.', now() - interval '10 days', v_fin),
      (v_ob4,  800.00, 'EUR', 'Pago total',             now() - interval '11 days', v_fin);
  else
    select id into v_ob2 from public.payment_obligation where reference = 'FAC-DEMO-002 (cafe Rotterdam)';
    select id into v_ob1 from public.payment_obligation where reference = 'FAC-DEMO-001 (cafe Castillo)';
    select id into v_ob5 from public.payment_obligation where reference = 'FAC-DEMO-004 (cafe Amsterdam)';
  end if;

  -- Tasas de cambio de referencia (solo si no hay ninguna) ----------------------------------------------
  if not exists (select 1 from public.exchange_rate) then
    insert into public.exchange_rate (base_currency_code, quote_currency_code, rate, effective_at, source) values
      ('USD', 'EUR', 0.9200,  now() - interval '1 day', 'demo'),
      ('USD', 'COP', 4100.00, now() - interval '1 day', 'demo'),
      ('USD', 'GBP', 0.7900,  now() - interval '1 day', 'demo');
  end if;

  -- Notificaciones financieras --------------------------------------------------------------------------
  delete from public.notification
   where recipient_user_id in (v_fin, v_admin)
     and notification_type in ('payment_overdue', 'payment_due_soon', 'payment_received')
     and title like 'Demo: %';
  insert into public.notification (recipient_user_id, notification_type, title, body, entity_type, entity_id, created_at, read_at) values
    (v_fin, 'payment_overdue',  'Demo: pago vencido FAC-DEMO-002',
       'La obligacion de 4080.00 EUR (Koffie Import B.V.) vencio hace 6 dias; saldo pendiente 2580.00 EUR.', 'payment_obligation', v_ob2, now() - interval '2 hours',  null),
    (v_fin, 'payment_due_soon', 'Demo: cobro proximo FAC-DEMO-001',
       'Faltan 15 dias para el vencimiento de 5760.00 EUR; saldo pendiente 2880.00 EUR.',                    'payment_obligation', v_ob1, now() - interval '8 hours',  null),
    (v_fin, 'payment_received', 'Demo: pago registrado',
       'Se registro el pago total de 800.00 EUR por flete y seguro.',                                       'payment_obligation', v_ob1, now() - interval '11 days', now() - interval '11 days' + interval '2 hours'),
    (v_fin, 'payment_due_soon', 'Demo: cobro por vencer FAC-DEMO-004',
       'La factura de 2970.00 EUR de Koffie Import B.V. vence en 25 dias.',                                  'payment_obligation', v_ob5, now() - interval '1 day',    null),
    (v_admin, 'payment_overdue','Demo: pago vencido FAC-DEMO-002',
       'La obligacion de 4080.00 EUR vencio hace 6 dias.',                                                   'payment_obligation', v_ob2, now() - interval '2 hours',  null);

  raise notice 'Datos financieros cargados.';
end
$financiero$;
