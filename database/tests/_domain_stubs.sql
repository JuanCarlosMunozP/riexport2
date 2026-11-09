-- Tablas de PRUEBA de los modulos de negocio (solo las columnas que usan las politicas de
-- database/drafts/*.sql). Se incluyen con \i desde pruebas que corren dentro de una transaccion
-- que se revierte; no es parte del esquema real.

create table public.customer_order(id bigint generated always as identity primary key, customer_id bigint, nota text);
create table public.order_line(id bigint generated always as identity primary key, order_id bigint);
create table public.export(id bigint generated always as identity primary key, order_id bigint);
create table public.export_line(id bigint generated always as identity primary key, export_id bigint);
create table public.export_document(id bigint generated always as identity primary key, export_id bigint, created_by_id bigint);
create table public.stored_file(id bigint generated always as identity primary key, uploaded_by_id bigint);
create table public.inventory_movement(id bigint generated always as identity primary key, performed_by_id bigint);
create table public.payment_obligation(id bigint generated always as identity primary key, order_id bigint);
create table public.payment_transaction(id bigint generated always as identity primary key, recorded_by_id bigint);
create table public.exchange_rate(id bigint generated always as identity primary key);
create table public.shipment(id bigint generated always as identity primary key, export_id bigint, nota text);
create table public.shipment_event(id bigint generated always as identity primary key, shipment_id bigint, nota text);
create table public.notification(id bigint generated always as identity primary key,
  recipient_user_id bigint, title text, read_at timestamptz);
