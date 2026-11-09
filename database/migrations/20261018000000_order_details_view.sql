-- PLAT-553: consulta de pedidos con cliente, lineas y total agregado.
-- La vista comprueba orders.read antes de devolver filas. Se ejecuta con el
-- propietario para poder incluir datos relacionados sujetos a otros permisos.
create or replace view public.customer_order_details
with (security_barrier = true) as
select
  o.id,
  o.order_number,
  o.customer_id,
  c.name as customer_name,
  o.status,
  o.currency_code,
  o.note,
  o.created_at,
  count(ol.id)::integer as line_count,
  coalesce(sum(ol.quantity * ol.unit_price), 0)::numeric(18,2) as order_total,
  coalesce(
    jsonb_agg(jsonb_build_object(
      'id', ol.id,
      'product_lot_id', ol.product_lot_id,
      'lot_code', l.lot_code,
      'product_name', concat_ws(' ', p.type, p.variety, p.quality_grade),
      'quantity', ol.quantity,
      'unit_price', ol.unit_price,
      'line_total', (ol.quantity * ol.unit_price)::numeric(18,2),
      'currency_code', ol.currency_code
    ) order by ol.id) filter (where ol.id is not null),
    '[]'::jsonb
  ) as lines
from public.customer_order o
join public.customer c on c.id = o.customer_id
left join public.order_line ol on ol.order_id = o.id
left join public.product_lot l on l.id = ol.product_lot_id
left join public.product p on p.id = l.product_id
where public.has_permission('orders.read')
group by o.id, c.name;

revoke all on public.customer_order_details from public, anon, authenticated;
grant select on public.customer_order_details to authenticated;
