-- PLAT-439: datos semilla de DESARROLLO (se carga tras las migraciones en `supabase db reset`).
-- Idempotente y sin datos personales reales. NO ejecutar en produccion.
--
-- Los datos de referencia (roles, permisos, unidades de medida, certificaciones, paises de destino e
-- Incoterms) ya los siembran las migraciones. Aqui solo van datos de ejemplo para probar los flujos
-- de origen (proveedor -> finca) y comerciales (cliente). Los productos y lotes se crean desde la app
-- porque exigen su detalle de cafe o cacao. El primer administrador se crea registrando una cuenta y
-- asignando su rol desde SQL (ver database/README.md).

insert into public.supplier (business_name, tax_id, contact_name, phone, email, location)
select 'Cooperativa Cafetera Demo', 'NIT-900000001', 'Contacto Demo', '+57 300 000 0001',
       'proveedor.demo@example.com', 'Huila, Colombia'
where not exists (select 1 from public.supplier where lower(tax_id) = 'nit-900000001');

insert into public.farm (supplier_id, country_code, name, address, latitude, longitude)
select s.id, 'CO', 'Finca Demo La Esperanza', 'Vereda Demo, Pitalito', 1.853000, -76.050000
from public.supplier s
where lower(s.tax_id) = 'nit-900000001'
  and not exists (select 1 from public.farm f where f.supplier_id = s.id and f.name = 'Finca Demo La Esperanza');

insert into public.customer (name, contact_name, email, country_code, eori_number, preferred_currency_code)
select 'Importadora Demo GmbH', 'Contacto Demo', 'cliente.demo@example.com', 'DE', 'DE123456789012', 'EUR'
where not exists (select 1 from public.customer where eori_number = 'DE123456789012');
