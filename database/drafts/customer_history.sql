-- SUPERSEDED: implementado por migrations/20261019000000_exports_shipments_documents.sql.
-- Conservado como referencia historica; no ejecutar este archivo.
-- Se valida con database/tests/draft_customer_history.sql sobre tablas de prueba (todo se revierte).
--
-- Dos vistas de solo lectura:
--  * customer_order_history: una fila por pedido del cliente, con su total (suma de cantidad x precio de las
--    lineas), cuantas exportaciones tiene y la fecha de la ultima.
--  * customer_export_history: una fila por exportacion de los pedidos del cliente.
--  * Se ejecutan con los derechos del propietario y filtran por permiso: pedidos exigen customers.read Y
--    orders.read; exportaciones, ademas, exports.read. Sin ellos, no devuelven nada.
--  * Un cliente externo (portal.read) ve su propio historial por las politicas de client_isolation.sql, no por
--    estas vistas (son para el personal).
--  * Supuestos a confirmar: el total del pedido se deriva de las lineas (no se guarda); "historial comercial"
--    son los pedidos y exportaciones; no incluye pagos (otro permiso y otro modulo).

insert into public.permission (code, description) values
  ('orders.read', 'Consultar pedidos.'),
  ('exports.read', 'Consultar exportaciones.')
on conflict (code) do nothing;

create or replace view public.customer_order_history
with (security_invoker = false) as
select
  o.customer_id,
  o.id as order_id,
  o.order_number,
  o.status,
  o.currency_code,
  o.created_at,
  coalesce((select sum(l.quantity * l.unit_price) from public.order_line l where l.order_id = o.id), 0) as order_total,
  (select count(*) from public.export e where e.order_id = o.id) as export_count,
  (select max(e.export_date) from public.export e where e.order_id = o.id) as last_export_date
from public.customer_order o
where public.has_permission('customers.read') and public.has_permission('orders.read');

create or replace view public.customer_export_history
with (security_invoker = false) as
select
  o.customer_id,
  e.id as export_id,
  e.order_id,
  o.order_number,
  e.destination_country_code,
  e.export_date,
  e.status
from public.export e
join public.customer_order o on o.id = e.order_id
where public.has_permission('customers.read')
  and public.has_permission('orders.read')
  and public.has_permission('exports.read');

revoke all on public.customer_order_history, public.customer_export_history from public, anon, authenticated;
grant select on public.customer_order_history, public.customer_export_history to authenticated;
