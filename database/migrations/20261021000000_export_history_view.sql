-- PLAT-575/576: historial de exportaciones. Amplía el catálogo con el número de
-- documentos, el último documento generado y el estado del último envío.
-- Hereda las reglas de acceso: exports.read, y los datos de documentos/envíos
-- solo se cuentan si el usuario además puede leerlos.

create or replace view public.export_history with (security_barrier=true) as
select e.id,e.order_id,o.order_number,o.customer_id,c.name as customer_name,
       e.destination_country_code,e.export_date,e.status,e.created_at,
       coalesce(lines.line_count,0)::integer as line_count,
       coalesce(lines.total_quantity,0)::numeric(18,3) as total_quantity,
       coalesce(shipments.shipment_count,0)::integer as shipment_count,
       shipments.last_shipment_status,
       case when public.has_permission('documents.read') then coalesce(docs.document_count,0) else 0 end::integer as document_count,
       case when public.has_permission('documents.read') then docs.last_document_at end as last_document_at
from public.export e join public.customer_order o on o.id=e.order_id
join public.customer c on c.id=o.customer_id
left join lateral (select count(*) as line_count,sum(el.quantity) as total_quantity from public.export_line el where el.export_id=e.id) lines on true
left join lateral (
  select count(*) as shipment_count,
         (array_agg(sh.status order by sh.created_at desc,sh.id desc))[1] as last_shipment_status
  from public.shipment sh where sh.export_id=e.id
) shipments on true
left join lateral (select count(*) as document_count,max(d.created_at) as last_document_at from public.export_document d where d.export_id=e.id) docs on true
where public.has_permission('exports.read');

revoke all on public.export_history from public,anon,authenticated;
grant select on public.export_history to authenticated;
