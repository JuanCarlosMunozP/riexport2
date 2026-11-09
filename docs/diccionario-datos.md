# Diccionario de datos RiExport

Generado a partir de `database/migrations/*.sql` (esquema `public`). Regenerar con `python docs/_gen_diccionario.py` si cambian las tablas. Cada fila: columna, tipo y restricciones declaradas en línea.

## `role`
Migración: `20261008000000_auth_roles_baseline.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `name` | text not null unique check (name ~ '^[a-z][a-z0-9_]{1,59}$') |
| `description` | text check (char_length(description) <= 250) |
| `is_active` | boolean not null default true |
| `created_at` | timestamptz not null default now() |

## `permission`
Migración: `20261008000000_auth_roles_baseline.sql`

| Columna | Tipo y restricciones |
|---|---|
| `code` | text primary key |
| `description` | text not null |

## `role_permission`
Migración: `20261008000000_auth_roles_baseline.sql`

| Columna | Tipo y restricciones |
|---|---|
| `role_id` | bigint not null references public.role (id) on delete cascade |
| `permission_code` | text   not null references public.permission (code) on delete cascade |

## `profile`
Migración: `20261008000000_auth_roles_baseline.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `auth_user_id` | uuid not null unique references auth.users (id) on delete cascade |
| `email` | text not null unique |
| `first_name` | text not null check (char_length(first_name) between 1 and 100) |
| `last_name` | text not null check (char_length(last_name) between 1 and 100) |
| `phone` | text check (char_length(phone) <= 32) |
| `role_id` | bigint not null references public.role (id) |
| `is_active` | boolean not null default true |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |

## `audit_log`
Migración: `20261008000600_role_change_policy_and_audit.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `actor_user_id` | bigint references public.profile (id) on delete set null |
| `action` | text not null check (char_length(action) between 1 and 100) |
| `entity_type` | text not null check (char_length(entity_type) between 1 and 60) |
| `entity_id` | bigint not null |
| `request_id` | text |
| `metadata` | jsonb not null default '{}'::jsonb |
| `created_at` | timestamptz not null default now() |

## `unit_of_measure`
Migración: `20261008000700_products_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `code` | text primary key check (code ~ '^[a-z][a-z0-9_]{0,11}$') |
| `name` | text not null unique check (char_length(name) between 1 and 60) |

## `certification`
Migración: `20261008000700_products_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `code` | text not null unique check (code ~ '^[A-Z][A-Z0-9_]{1,49}$') |
| `name` | text not null check (char_length(name) between 1 and 120) |
| `is_active` | boolean not null default true |

## `product`
Migración: `20261008000700_products_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `type` | text not null check (type in ('coffee', 'cacao')) |
| `variety` | text not null check (char_length(variety) between 1 and 120) |
| `quality_grade` | text not null check (char_length(quality_grade) between 1 and 80) |
| `hs_code` | text check (hs_code ~ '^[0-9]{4}(\.[0-9]{2}){0,3}$') |
| `base_unit_code` | text not null references public.unit_of_measure (code) |
| `low_stock_threshold` | numeric(18, 3) check (low_stock_threshold >= 0) |
| `is_active` | boolean not null default true |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |

## `coffee_detail`
Migración: `20261008000700_products_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `product_id` | bigint primary key references public.product (id) |
| `humidity_percent` | numeric(5, 2) not null check (humidity_percent between 0 and 100) |

## `cacao_detail`
Migración: `20261008000700_products_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `product_id` | bigint primary key references public.product (id) |
| `bean_type` | text not null check (char_length(bean_type) between 1 and 100) |
| `fermentation_percent` | numeric(5, 2) not null check (fermentation_percent between 0 and 100) |

## `product_certification`
Migración: `20261008000700_products_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `product_id` | bigint not null references public.product (id) |
| `certification_id` | bigint not null references public.certification (id) |

## `supplier`
Migración: `20261009000000_suppliers_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `business_name` | text not null check (char_length(business_name) between 1 and 160) |
| `tax_id` | text not null check (tax_id ~ '^[A-Za-z0-9][A-Za-z0-9.\-]{2,29}$') |
| `contact_name` | text check (char_length(contact_name) between 1 and 120) |
| `phone` | text check (phone ~ '^\+?[0-9][0-9 ()\-]{5,24}$') |
| `email` | text check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254) |
| `location` | text check (char_length(location) between 1 and 200) |
| `is_active` | boolean not null default true |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |

## `farm`
Migración: `20261010000000_farms_and_lots.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `supplier_id` | bigint not null references public.supplier (id) |
| `country_code` | text not null check (country_code ~ '^[A-Z]{2}$') |
| `name` | text not null check (char_length(name) between 1 and 160) |
| `address` | text check (char_length(address) between 1 and 300) |
| `latitude` | numeric(9, 6) check (latitude between -90 and 90) |
| `longitude` | numeric(9, 6) check (longitude between -180 and 180) |
| `is_active` | boolean not null default true |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |

## `product_lot`
Migración: `20261010000000_farms_and_lots.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `product_id` | bigint not null references public.product (id) |
| `farm_id` | bigint not null references public.farm (id) |
| `lot_code` | text not null check (char_length(lot_code) between 1 and 80) |
| `created_at` | timestamptz not null default now() |

## `customer`
Migración: `20261013000000_customers_module.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `name` | text not null check (char_length(name) between 1 and 180) |
| `contact_name` | text check (char_length(contact_name) between 1 and 160) |
| `email` | text check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254) |
| `country_code` | text not null check (country_code ~ '^[A-Z]{2}$') |
| `eori_number` | text |
| `preferred_currency_code` | text not null check (preferred_currency_code ~ '^[A-Z]{3}$') |
| `is_active` | boolean not null default true |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |
| `eori_number` | is null |
| `or` | left(eori_number, 2) = case country_code when 'GR' then 'EL' else country_code end |
| `or` | (country_code = 'GB' and left(eori_number, 2) = 'XI') |
| `eori_number` | is not null |
| `or` | country_code not in ('AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU','IE','IT' |

## `customer_user`
Migración: `20261014000000_customer_user_link.sql`

| Columna | Tipo y restricciones |
|---|---|
| `customer_id` | bigint not null references public.customer (id) |
| `profile_id` | bigint not null references public.profile (id) on delete cascade |
| `created_at` | timestamptz not null default now() |

## `customer_order`
Migración: `20261016000000_customer_orders.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `customer_id` | bigint not null references public.customer(id) |
| `order_number` | text not null unique |
| `status` | text not null default 'draft' |
| `currency_code` | text not null check (currency_code ~ '^[A-Z]{3}$') |
| `note` | text check (char_length(note) <= 1000) |
| `created_by_id` | bigint references public.profile(id) on delete set null |
| `created_at` | timestamptz not null default now() |

## `order_line`
Migración: `20261016000000_customer_orders.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `order_id` | bigint not null references public.customer_order(id) |
| `product_lot_id` | bigint not null references public.product_lot(id) |
| `quantity` | numeric(18,3) not null check (quantity > 0) |
| `unit_price` | numeric(18,2) not null check (unit_price >= 0) |
| `currency_code` | text not null check (currency_code ~ '^[A-Z]{3}$') |
| `hs_code_snapshot` | text check (hs_code_snapshot is null or hs_code_snapshot ~ '^[0-9]{4}(\.[0-9]{2}){0,3}$') |
| `created_at` | timestamptz not null default now() |

## `inventory_movement`
Migración: `20261016000000_customer_orders.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `product_lot_id` | bigint not null references public.product_lot(id) |
| `quantity_delta` | numeric(18,3) not null check (quantity_delta <> 0) |
| `movement_type` | text not null check (movement_type in ('adjustment', 'order')) |
| `order_id` | bigint references public.customer_order(id) |
| `performed_by_id` | bigint references public.profile(id) on delete set null |
| `created_at` | timestamptz not null default now() |
| `or` | (movement_type = 'adjustment' and order_id is null)) |

## `order_status_history`
Migración: `20261017000000_order_status_transitions.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `order_id` | bigint not null references public.customer_order(id) |
| `from_status` | text check (from_status in ('draft', 'confirmed', 'cancelled')) |
| `to_status` | text not null check (to_status in ('draft', 'confirmed', 'cancelled')) |
| `changed_by_id` | bigint references public.profile(id) on delete set null |
| `note` | text check (note is null or char_length(note) <= 500) |
| `changed_at` | timestamptz not null default now() |

## `export`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `order_id` | bigint not null references public.customer_order(id) |
| `destination_country_code` | text not null check (destination_country_code ~ '^[A-Z]{2}$') |
| `export_date` | date not null default current_date |
| `status` | text not null default 'draft' check (status in ('draft','formalized','cancelled')) |
| `created_by_id` | bigint references public.profile(id) on delete set null |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |

## `export_line`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `export_id` | bigint not null references public.export(id) |
| `order_line_id` | bigint not null references public.order_line(id) |
| `product_lot_id` | bigint not null references public.product_lot(id) |
| `quantity` | numeric(18,3) not null check (quantity > 0) |
| `hs_code_snapshot` | text check (hs_code_snapshot is null or hs_code_snapshot ~ '^[0-9]{4}(\.[0-9]{2}){0,3}$') |
| `created_at` | timestamptz not null default now() |

## `shipment`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `export_id` | bigint not null references public.export(id) |
| `carrier` | text check (carrier is null or char_length(carrier) <= 120) |
| `tracking_number` | text check (tracking_number is null or char_length(tracking_number) <= 160) |
| `status` | text not null default 'planned' check (status in ('planned','in_transit','delivered','cancelled')) |
| `shipped_at` | timestamptz |
| `estimated_delivery_at` | date |
| `delivered_at` | timestamptz |
| `created_by_id` | bigint references public.profile(id) on delete set null |
| `created_at` | timestamptz not null default now() |
| `updated_at` | timestamptz not null default now() |

## `shipment_event`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `shipment_id` | bigint not null references public.shipment(id) |
| `event_type` | text not null check (char_length(event_type) between 1 and 80) |
| `description` | text check (description is null or char_length(description) <= 1000) |
| `location` | text check (location is null or char_length(location) <= 240) |
| `latitude` | numeric(9,6) check (latitude is null or latitude between -90 and 90) |
| `longitude` | numeric(9,6) check (longitude is null or longitude between -180 and 180) |
| `event_at` | timestamptz not null default now() |
| `recorded_by_id` | bigint references public.profile(id) on delete set null |

## `stored_file`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `bucket_id` | text not null check (bucket_id = 'export-documents') |
| `object_path` | text not null unique |
| `original_name` | text not null check (char_length(original_name) between 1 and 255) |
| `mime_type` | text not null check (mime_type in ('application/pdf','image/png','image/jpeg')) |
| `byte_size` | bigint not null check (byte_size between 1 and 20971520) |
| `sha256` | text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$') |
| `uploaded_by_id` | bigint not null references public.profile(id) |
| `uploaded_at` | timestamptz not null default now() |

## `export_document`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `export_id` | bigint not null references public.export(id) |
| `stored_file_id` | bigint not null references public.stored_file(id) |
| `document_type` | text not null check (char_length(document_type) between 1 and 80) |
| `version` | integer not null default 1 check (version > 0) |
| `notes` | text check (notes is null or char_length(notes) <= 1000) |
| `created_by_id` | bigint not null references public.profile(id) |
| `created_at` | timestamptz not null default now() |

## `notification`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `recipient_user_id` | bigint not null references public.profile(id) on delete cascade |
| `notification_type` | text not null check (char_length(notification_type) between 1 and 80) |
| `title` | text not null check (char_length(title) between 1 and 180) |
| `body` | text check (body is null or char_length(body) <= 1000) |
| `entity_type` | text |
| `entity_id` | bigint |
| `created_at` | timestamptz not null default now() |
| `read_at` | timestamptz |

## `payment_obligation`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `export_id` | bigint not null references public.export(id) |
| `amount_due` | numeric(18,2) not null check (amount_due > 0) |
| `currency_code` | text not null check (currency_code ~ '^[A-Z]{3}$') |
| `due_date` | date |
| `reference` | text check (reference is null or char_length(reference) <= 160) |
| `created_by_id` | bigint not null references public.profile(id) |
| `created_at` | timestamptz not null default now() |

## `payment_transaction`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `obligation_id` | bigint not null references public.payment_obligation(id) |
| `amount` | numeric(18,2) not null check (amount > 0) |
| `currency_code` | text not null check (currency_code ~ '^[A-Z]{3}$') |
| `reference` | text check (reference is null or char_length(reference) <= 160) |
| `paid_at` | timestamptz not null default now() |
| `recorded_by_id` | bigint not null references public.profile(id) |
| `created_at` | timestamptz not null default now() |

## `exchange_rate`
Migración: `20261019000000_exports_shipments_documents.sql`

| Columna | Tipo y restricciones |
|---|---|
| `id` | bigint generated always as identity primary key |
| `base_currency_code` | text not null check (base_currency_code ~ '^[A-Z]{3}$') |
| `quote_currency_code` | text not null check (quote_currency_code ~ '^[A-Z]{3}$') |
| `rate` | numeric(20,10) not null check (rate > 0) |
| `effective_at` | timestamptz not null |
| `source` | text not null check (char_length(source) between 1 and 160) |
| `created_at` | timestamptz not null default now() |

## `export_destination`
Migración: `20261020000000_order_edit_export_catalogs.sql`

| Columna | Tipo y restricciones |
|---|---|
| `code` | text primary key check (code ~ '^[A-Z]{2}$') |
| `name` | text not null unique |
| `is_active` | boolean not null default true |

## `incoterm`
Migración: `20261020000000_order_edit_export_catalogs.sql`

| Columna | Tipo y restricciones |
|---|---|
| `code` | text primary key check (code in |
| `name` | text not null |
| `is_active` | boolean not null default true |
