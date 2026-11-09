-- BORRADOR (no aplicado): aislamiento del cliente externo (PLAT-466).
-- Se aplica DESPUES de domain_policies.sql y en la misma migracion que crea las tablas de negocio.
-- Valida: database/tests/client_isolation.sql (tablas de prueba, transaccion revertida).
--
-- Regla: un usuario con el permiso `portal.read` ve SOLO los registros de los clientes (customer)
-- a los que esta vinculado en `customer_user`, y solo en lectura:
--   su cliente -> sus pedidos y lineas -> sus exportaciones, lineas y documentos -> sus envios y eventos.
-- Las politicas son ADITIVAS a las de personal interno (domain_policies.sql): el personal con
-- orders.read sigue viendo todo; el cliente externo no recibe ningun permiso interno.
--
-- DECISIONES DEL CLIENTE que este borrador asume y hay que confirmar:
--   1. Un usuario externo puede estar vinculado a varios clientes y un cliente puede tener varios
--      usuarios (tabla N:M). Si es 1:1, basta una columna profile_id en customer.
--   2. El cliente externo NO ve pagos, inventario, lotes ni notas internas (solo lo listado arriba).
--   3. La descarga de los archivos de los documentos exige ademas una politica de Storage sobre el
--      bucket export-documents, que sigue sin politicas (nadie accede) hasta decidir esto.
--   4. Quien vincula usuarios a clientes es el personal con customers.update (no el propio cliente).

-- 1. Vinculo usuario externo <-> cliente y permiso portal.read ---------------------------------------
-- YA ES UNA MIGRACION REAL: 20261014000000_customer_user_link.sql (tabla customer_user, funciones
-- link_customer_user / unlink_customer_user, vista customer_account_link y el permiso portal.read).
-- Este borrador solo anade, sobre esa tabla, las politicas de lectura propia de las tablas de negocio.

-- 2. Funciones auxiliares: cadena cliente -> pedido -> exportacion -> envio ------------------------
-- SECURITY DEFINER para recorrer la cadena sin que las politicas de cada tabla se evaluen entre si.
create or replace function public.my_customer_ids()
returns setof bigint
language sql stable security definer set search_path = public
as $$
  select cu.customer_id from public.customer_user cu
  where cu.profile_id = public.current_profile_id();
$$;

create or replace function public.my_order_ids()
returns setof bigint
language sql stable security definer set search_path = public
as $$
  select o.id from public.customer_order o
  where o.customer_id in (select public.my_customer_ids());
$$;

create or replace function public.my_export_ids()
returns setof bigint
language sql stable security definer set search_path = public
as $$
  select e.id from public.export e
  where e.order_id in (select public.my_order_ids());
$$;

create or replace function public.my_shipment_ids()
returns setof bigint
language sql stable security definer set search_path = public
as $$
  select s.id from public.shipment s
  where s.export_id in (select public.my_export_ids());
$$;

revoke all on function public.my_customer_ids(), public.my_order_ids(),
                       public.my_export_ids(), public.my_shipment_ids() from public, anon;
grant execute on function public.my_customer_ids(), public.my_order_ids(),
                          public.my_export_ids(), public.my_shipment_ids() to authenticated;

-- 3. Politicas de lectura propia (solo SELECT) -----------------------------------------------------
drop policy if exists customer_select_own on public.customer;
create policy customer_select_own on public.customer
  for select to authenticated
  using (public.has_permission('portal.read') and id in (select public.my_customer_ids()));

drop policy if exists customer_order_select_own on public.customer_order;
create policy customer_order_select_own on public.customer_order
  for select to authenticated
  using (public.has_permission('portal.read') and customer_id in (select public.my_customer_ids()));

drop policy if exists order_line_select_own on public.order_line;
create policy order_line_select_own on public.order_line
  for select to authenticated
  using (public.has_permission('portal.read') and order_id in (select public.my_order_ids()));

drop policy if exists export_select_own on public.export;
create policy export_select_own on public.export
  for select to authenticated
  using (public.has_permission('portal.read') and id in (select public.my_export_ids()));

drop policy if exists export_line_select_own on public.export_line;
create policy export_line_select_own on public.export_line
  for select to authenticated
  using (public.has_permission('portal.read') and export_id in (select public.my_export_ids()));

drop policy if exists export_document_select_own on public.export_document;
create policy export_document_select_own on public.export_document
  for select to authenticated
  using (public.has_permission('portal.read') and export_id in (select public.my_export_ids()));

drop policy if exists shipment_select_own on public.shipment;
create policy shipment_select_own on public.shipment
  for select to authenticated
  using (public.has_permission('portal.read') and id in (select public.my_shipment_ids()));

drop policy if exists shipment_event_select_own on public.shipment_event;
create policy shipment_event_select_own on public.shipment_event
  for select to authenticated
  using (public.has_permission('portal.read') and shipment_id in (select public.my_shipment_ids()));
