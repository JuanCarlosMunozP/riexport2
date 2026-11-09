-- Datos de demostracion para el Gestor de Cumplimiento UE (solo desarrollo; NO ejecutar en produccion).
-- Idempotente. Requiere seed_demo_roles.sql, seed_demo_envios.sql y seed_demo_clientes_notificaciones.sql.
--
-- Que ve esta cuenta con sus permisos (exports.read/update, documents.*, orders/lots/farms/suppliers.read):
--   * las 4 exportaciones demo con su trazabilidad (lote -> finca con coordenadas -> proveedor, codigo HS),
--     de las que se genera la declaracion EUDR bajo demanda (es valida: toda linea llega a una finca geolocalizada);
--   * documentos de exportacion de ejemplo: certificado fitosanitario y declaracion de diligencia debida.
--     Son SOLO registros (metadatos): no tienen archivo en Storage, asi que no se pueden descargar;
--   * notificaciones de cumplimiento.

do $cumplimiento$
declare
  v_cum bigint; v_cum_uid uuid; v_e1 bigint; v_e2 bigint; v_e3 bigint; v_e4 bigint;
  v_f1 bigint; v_f2 bigint; v_f3 bigint; v_f4 bigint;
begin
  select id, auth_user_id into v_cum, v_cum_uid from public.profile where email = 'cumplimiento@demo.riexport.test';
  select e.id into v_e1 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'MSKU-DEMO-0001';
  select e.id into v_e2 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'HLCU-DEMO-4521';
  select e.id into v_e3 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'MSC-DEMO-7788';
  select e.id into v_e4 from public.export e join public.shipment s on s.export_id = e.id where s.tracking_number = 'ONE-DEMO-3310';
  if v_cum is null or v_e1 is null or v_e4 is null then
    raise exception 'Faltan datos: ejecuta antes seed_demo_roles.sql, seed_demo_envios.sql y seed_demo_clientes_notificaciones.sql.';
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_cum_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_cum_uid::text, true);

  -- Documentos de exportacion (metadatos de demostracion) ------------------------------------------
  with docs(export_id, document_type, file_name, note) as (values
    (v_e1, 'phytosanitary_certificate', 'certificado-fitosanitario-DEMO-0001.pdf', 'Demo: certificado fitosanitario ICA para Alemania.'),
    (v_e1, 'eudr_due_diligence',        'declaracion-eudr-DEMO-0001.pdf',          'Demo: declaracion de diligencia debida EUDR firmada.'),
    (v_e2, 'phytosanitary_certificate', 'certificado-fitosanitario-DEMO-0002.pdf', 'Demo: certificado fitosanitario ICA para Paises Bajos.'),
    (v_e4, 'eudr_due_diligence',        'declaracion-eudr-DEMO-0004.pdf',          'Demo: declaracion de diligencia debida EUDR (pendiente de envio al sistema TRACES).')
  ), files as (
    insert into public.stored_file (bucket_id, object_path, original_name, mime_type, byte_size, uploaded_by_id)
    select 'export-documents', 'demo/' || d.export_id || '/' || d.file_name, d.file_name, 'application/pdf', 48213, v_cum
    from docs d
    where not exists (select 1 from public.stored_file f where f.object_path = 'demo/' || d.export_id || '/' || d.file_name)
    returning id, object_path
  )
  insert into public.export_document (export_id, stored_file_id, document_type, version, notes, created_by_id)
  select d.export_id, f.id, d.document_type, 1, d.note, v_cum
  from docs d join files f on f.object_path = 'demo/' || d.export_id || '/' || d.file_name
  on conflict do nothing;

  -- Notificaciones de cumplimiento ------------------------------------------------------------------
  delete from public.notification where recipient_user_id = v_cum and title like 'Demo:%';
  insert into public.notification (recipient_user_id, notification_type, title, body, entity_type, entity_id, created_at, read_at) values
    (v_cum, 'eudr_review',   'Demo: declaracion EUDR pendiente de revision',
       'La exportacion hacia Paises Bajos (HLCU-DEMO-4521) aun no tiene declaracion de diligencia debida.', 'export', v_e2, now() - interval '3 hours',  null),
    (v_cum, 'eudr_review',   'Demo: declaracion EUDR pendiente de revision',
       'La exportacion hacia Alemania (MSC-DEMO-7788) sale en 30 dias: prepara la declaracion de cafe/cacao.', 'export', v_e3, now() - interval '9 hours',  null),
    (v_cum, 'document_ready','Demo: documentos de exportacion cargados',
       'Se cargaron el certificado fitosanitario y la declaracion EUDR de MSKU-DEMO-0001.',               'export', v_e1, now() - interval '1 day',    now() - interval '20 hours'),
    (v_cum, 'shipment_status','Demo: envio en aduana de destino',
       'MSKU-DEMO-0001 esta en despacho en Hamburgo: verifica que la declaracion EUDR este registrada.',   'export', v_e1, now() - interval '30 hours', null),
    (v_cum, 'eudr_review',   'Demo: trazabilidad verificada',
       'Todas las lineas de la exportacion ONE-DEMO-3310 llegan a una finca con coordenadas.',             'export', v_e4, now() - interval '2 days',   now() - interval '2 days' + interval '1 hour');

  raise notice 'Datos de cumplimiento cargados.';
end
$cumplimiento$;
