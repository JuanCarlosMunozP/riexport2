-- SUPERSEDED: implementado por migrations/20261019000000_exports_shipments_documents.sql.
-- Conservado como referencia historica; no ejecutar este archivo.
-- Se valida con database/tests/draft_export_traceability.sql sobre tablas de prueba (todo se revierte).
--
-- Cadena de trazabilidad: exportacion -> linea de exportacion -> lote -> finca -> proveedor.
--  * export_traceability: una fila por linea de exportacion, con producto, lote, finca (con su punto
--    geografico) y proveedor, y la cantidad y el codigo HS aplicados (instantanea historica).
--  * export_origin_farms: una fila por (exportacion, finca) con la cantidad total y los lotes: es lo que
--    dibuja el mapa de fincas de una exportacion/envio.
--  * Las vistas se ejecutan con los derechos del propietario (para unir tablas que el lector no puede
--    leer directamente) y filtran por permiso: exports.read Y farms.read. Sin ambos, no devuelven nada.
--  * Solo lectura: nadie escribe por las vistas (privilegios).
--  * Supuesto a confirmar: un envio (shipment) pertenece a una exportacion, asi que las fincas de un envio
--    son las de su exportacion; si un envio llevara solo parte de las lineas, habra que enlazar shipment
--    con export_line.

insert into public.permission (code, description) values
  ('exports.read', 'Consultar exportaciones.')
on conflict (code) do nothing;

create or replace view public.export_traceability
with (security_invoker = false) as
select
  el.export_id,
  el.id as export_line_id,
  el.order_line_id,
  el.quantity,
  el.hs_code_snapshot,
  l.id as lot_id,
  l.lot_code,
  p.id as product_id,
  p.type as product_type,
  p.variety as product_variety,
  p.quality_grade as product_quality,
  f.id as farm_id,
  f.name as farm_name,
  f.country_code,
  f.latitude,
  f.longitude,
  s.id as supplier_id,
  s.business_name as supplier_name
from public.export_line el
join public.product_lot l on l.id = el.product_lot_id
join public.product p on p.id = l.product_id
join public.farm f on f.id = l.farm_id
join public.supplier s on s.id = f.supplier_id
where public.has_permission('exports.read') and public.has_permission('farms.read');

create or replace view public.export_origin_farms
with (security_invoker = false) as
select
  t.export_id,
  t.farm_id,
  t.farm_name,
  t.country_code,
  t.latitude,
  t.longitude,
  t.supplier_id,
  t.supplier_name,
  sum(t.quantity) as total_quantity,
  count(distinct t.lot_id) as lot_count
from public.export_traceability t
group by t.export_id, t.farm_id, t.farm_name, t.country_code, t.latitude, t.longitude,
         t.supplier_id, t.supplier_name;

revoke all on public.export_traceability, public.export_origin_farms from public, anon, authenticated;
grant select on public.export_traceability, public.export_origin_farms to authenticated;
