-- BORRADOR (no aplicado): permisos y politicas RLS de los modulos de negocio.
-- PLAT-462 (comercial), 463 (exportaciones y documentos), 464 (inventario y finanzas),
-- 465 (logistica y notificaciones).
--
-- Cada bloque se aplica EN LA MISMA MIGRACION que crea sus tablas (docs/modelo-datos.md,
-- seccion 4), nunca antes: las tablas no existen todavia. Se valida sobre tablas de prueba con
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/draft_policies.sql
-- (transaccion que se revierte).
--
-- Reglas comunes (docs/modelo-autorizacion-rls.md):
--  * RLS activa, denegar por defecto; anon sin acceso; sin TRUNCATE/REFERENCES/TRIGGER.
--  * Los permisos son datos (modulo.accion, segun docs/contrato-api.md). Ninguno se concede a un
--    rol al crearlo: el administrador los asigna desde la pantalla de roles.
--  * Sin DELETE desde la API (baja logica). Excepciones: lineas de pedido/exportacion.
--  * Libros inmutables (movimientos, pagos, eventos, documentos): solo INSERT.
--  * Lo que escribe el sistema (tasas de cambio, notificaciones, movimientos por pedido/exportacion)
--    se hace con funciones SECURITY DEFINER o Edge Functions, no con politicas de usuario.
--
-- Pendiente al crear las tablas: triggers de reglas por campo, como profile_guard
--   customer_order.status solo con orders.transition y edicion solo en estado pending;
--   export: bloqueo tras formalizar; order_line / export_line: solo si el padre esta en pending.
-- Sin resolver (decision del cliente): acceso del rol externo "cliente" a sus propios envios.

-- 0. Funcion auxiliar y catalogo de permisos ---------------------------------------------------

-- id numerico del perfil del usuario actual (null si no hay sesion o la cuenta esta desactivada).
create or replace function public.current_profile_id()
returns bigint
language sql stable security definer set search_path = public
as $$
  select pr.id
  from public.profile pr
  join public.role r on r.id = pr.role_id
  where pr.auth_user_id = auth.uid() and pr.is_active and r.is_active;
$$;
revoke all on function public.current_profile_id() from public, anon;
grant execute on function public.current_profile_id() to authenticated;

insert into public.permission (code, description) values
  ('orders.read', 'Consultar pedidos.'),
  ('orders.create', 'Registrar pedidos.'),
  ('orders.update', 'Editar pedidos pendientes.'),
  ('orders.transition', 'Cambiar el estado de un pedido.'),
  ('exports.read', 'Consultar exportaciones.'),
  ('exports.create', 'Registrar exportaciones.'),
  ('exports.update', 'Editar exportaciones.'),
  ('documents.read', 'Consultar documentos de exportacion.'),
  ('documents.generate', 'Generar documentos de exportacion.'),
  ('documents.upload', 'Adjuntar documentos de exportacion.'),
  ('inventory.read', 'Consultar inventario y sus movimientos.'),
  ('inventory.adjust', 'Registrar ajustes manuales de inventario.'),
  ('payments.read', 'Consultar pagos, obligaciones y tasas de cambio.'),
  ('payments.create', 'Registrar obligaciones y pagos.'),
  ('logistics.read', 'Consultar envios y su linea de tiempo.'),
  ('logistics.create', 'Registrar envios.'),
  ('logistics.update', 'Actualizar envios y registrar eventos logisticos.')
on conflict (code) do nothing;

-- NOTA: la tabla `customer` ya es un modulo real (migracion 20261013000000_customers_module.sql); aqui solo
-- quedan pedidos y lineas.
-- 1. PLAT-462: modulo comercial -----------------------------------------------------------------

alter table public.customer_order enable row level security;
alter table public.order_line     enable row level security;

drop policy if exists customer_order_select on public.customer_order;
create policy customer_order_select on public.customer_order
  for select to authenticated using (public.has_permission('orders.read'));
drop policy if exists customer_order_insert on public.customer_order;
create policy customer_order_insert on public.customer_order
  for insert to authenticated with check (public.has_permission('orders.create'));
drop policy if exists customer_order_update on public.customer_order;
create policy customer_order_update on public.customer_order
  for update to authenticated
  using (public.has_permission('orders.update') or public.has_permission('orders.transition'))
  with check (public.has_permission('orders.update') or public.has_permission('orders.transition'));

drop policy if exists order_line_select on public.order_line;
create policy order_line_select on public.order_line
  for select to authenticated using (public.has_permission('orders.read'));
drop policy if exists order_line_insert on public.order_line;
create policy order_line_insert on public.order_line
  for insert to authenticated
  with check (public.has_permission('orders.create') or public.has_permission('orders.update'));
drop policy if exists order_line_update on public.order_line;
create policy order_line_update on public.order_line
  for update to authenticated
  using (public.has_permission('orders.update'))
  with check (public.has_permission('orders.update'));
drop policy if exists order_line_delete on public.order_line;
create policy order_line_delete on public.order_line
  for delete to authenticated using (public.has_permission('orders.update'));

revoke all on public.customer_order, public.order_line from anon;
revoke truncate, references, trigger on public.customer_order, public.order_line from authenticated;
revoke delete on public.customer_order from authenticated;

-- 2. PLAT-463: exportaciones y documentos -------------------------------------------------------

alter table public.export          enable row level security;
alter table public.export_line     enable row level security;
alter table public.export_document enable row level security;
alter table public.stored_file     enable row level security;

drop policy if exists export_select on public.export;
create policy export_select on public.export
  for select to authenticated using (public.has_permission('exports.read'));
drop policy if exists export_insert on public.export;
create policy export_insert on public.export
  for insert to authenticated with check (public.has_permission('exports.create'));
drop policy if exists export_update on public.export;
create policy export_update on public.export
  for update to authenticated
  using (public.has_permission('exports.update'))
  with check (public.has_permission('exports.update'));

drop policy if exists export_line_select on public.export_line;
create policy export_line_select on public.export_line
  for select to authenticated using (public.has_permission('exports.read'));
drop policy if exists export_line_insert on public.export_line;
create policy export_line_insert on public.export_line
  for insert to authenticated
  with check (public.has_permission('exports.create') or public.has_permission('exports.update'));
drop policy if exists export_line_update on public.export_line;
create policy export_line_update on public.export_line
  for update to authenticated
  using (public.has_permission('exports.update'))
  with check (public.has_permission('exports.update'));
drop policy if exists export_line_delete on public.export_line;
create policy export_line_delete on public.export_line
  for delete to authenticated using (public.has_permission('exports.update'));

-- Documentos del expediente: inmutables (una version nueva es una fila nueva).
drop policy if exists export_document_select on public.export_document;
create policy export_document_select on public.export_document
  for select to authenticated using (public.has_permission('documents.read'));
drop policy if exists export_document_insert on public.export_document;
create policy export_document_insert on public.export_document
  for insert to authenticated
  with check ((public.has_permission('documents.upload') or public.has_permission('documents.generate'))
              and created_by_id = public.current_profile_id());

-- Metadatos de archivos: quien sube un archivo ve sus metadatos; el expediente lo ve documents.read.
drop policy if exists stored_file_select on public.stored_file;
create policy stored_file_select on public.stored_file
  for select to authenticated
  using (uploaded_by_id = public.current_profile_id() or public.has_permission('documents.read'));
drop policy if exists stored_file_insert on public.stored_file;
create policy stored_file_insert on public.stored_file
  for insert to authenticated with check (uploaded_by_id = public.current_profile_id());

revoke all on public.export, public.export_line, public.export_document, public.stored_file from anon;
revoke truncate, references, trigger
  on public.export, public.export_line, public.export_document, public.stored_file from authenticated;
revoke delete on public.export, public.export_document, public.stored_file from authenticated;
revoke update on public.export_document, public.stored_file from authenticated;

-- 3. PLAT-464: inventario y finanzas -----------------------------------------------------------------

alter table public.inventory_movement  enable row level security;
alter table public.payment_obligation  enable row level security;
alter table public.payment_transaction enable row level security;
alter table public.exchange_rate       enable row level security;

-- Libro de inventario: solo INSERT. Los movimientos por pedido/exportacion los crea una funcion
-- SECURITY DEFINER; aqui solo los ajustes manuales, firmados por quien los registra.
drop policy if exists inventory_movement_select on public.inventory_movement;
create policy inventory_movement_select on public.inventory_movement
  for select to authenticated using (public.has_permission('inventory.read'));
drop policy if exists inventory_movement_insert on public.inventory_movement;
create policy inventory_movement_insert on public.inventory_movement
  for insert to authenticated
  with check (public.has_permission('inventory.adjust')
              and performed_by_id = public.current_profile_id());

drop policy if exists payment_obligation_select on public.payment_obligation;
create policy payment_obligation_select on public.payment_obligation
  for select to authenticated using (public.has_permission('payments.read'));
drop policy if exists payment_obligation_insert on public.payment_obligation;
create policy payment_obligation_insert on public.payment_obligation
  for insert to authenticated with check (public.has_permission('payments.create'));

drop policy if exists payment_transaction_select on public.payment_transaction;
create policy payment_transaction_select on public.payment_transaction
  for select to authenticated using (public.has_permission('payments.read'));
drop policy if exists payment_transaction_insert on public.payment_transaction;
create policy payment_transaction_insert on public.payment_transaction
  for insert to authenticated
  with check (public.has_permission('payments.create')
              and recorded_by_id = public.current_profile_id());

-- Tasas de cambio: solo lectura para usuarios; las escribe el sistema (Edge Function / service_role).
drop policy if exists exchange_rate_select on public.exchange_rate;
create policy exchange_rate_select on public.exchange_rate
  for select to authenticated using (public.has_permission('payments.read'));

revoke all on public.inventory_movement, public.payment_obligation,
              public.payment_transaction, public.exchange_rate from anon;
revoke truncate, references, trigger on public.inventory_movement, public.payment_obligation,
              public.payment_transaction, public.exchange_rate from authenticated;
revoke update, delete on public.inventory_movement, public.payment_obligation,
              public.payment_transaction, public.exchange_rate from authenticated;
revoke insert on public.exchange_rate from authenticated;

-- 4. PLAT-465: logistica y notificaciones --------------------------------------------------------------

alter table public.shipment       enable row level security;
alter table public.shipment_event enable row level security;
alter table public.notification   enable row level security;

drop policy if exists shipment_select on public.shipment;
create policy shipment_select on public.shipment
  for select to authenticated using (public.has_permission('logistics.read'));
drop policy if exists shipment_insert on public.shipment;
create policy shipment_insert on public.shipment
  for insert to authenticated with check (public.has_permission('logistics.create'));
drop policy if exists shipment_update on public.shipment;
create policy shipment_update on public.shipment
  for update to authenticated
  using (public.has_permission('logistics.update'))
  with check (public.has_permission('logistics.update'));

-- Eventos logisticos: cronologia inmutable (solo INSERT).
drop policy if exists shipment_event_select on public.shipment_event;
create policy shipment_event_select on public.shipment_event
  for select to authenticated using (public.has_permission('logistics.read'));
drop policy if exists shipment_event_insert on public.shipment_event;
create policy shipment_event_insert on public.shipment_event
  for insert to authenticated with check (public.has_permission('logistics.update'));

-- Notificaciones: cada usuario ve las suyas y solo puede marcarlas como leidas. Las crea el sistema.
drop policy if exists notification_select on public.notification;
create policy notification_select on public.notification
  for select to authenticated using (recipient_user_id = public.current_profile_id());
drop policy if exists notification_update on public.notification;
create policy notification_update on public.notification
  for update to authenticated
  using (recipient_user_id = public.current_profile_id())
  with check (recipient_user_id = public.current_profile_id());

revoke all on public.shipment, public.shipment_event, public.notification from anon;
revoke truncate, references, trigger on public.shipment, public.shipment_event, public.notification from authenticated;
revoke delete on public.shipment, public.shipment_event, public.notification from authenticated;
revoke update on public.shipment_event from authenticated;
revoke insert, update on public.notification from authenticated;
grant update (read_at) on public.notification to authenticated;
