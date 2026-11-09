-- Roles por area segun las diapositivas "Roles y permisos" del cliente:
--   Administrador (control total) · Gestor de Inventario · Gestor Comercial · Gestor de Logistica
--   · Gestor Financiero · Cliente (portal). Se anade el Gestor de Cumplimiento UE (EUDR y
--   documentacion de exportacion de cafe y cacao a la Union Europea).
-- Idempotente. El administrador conserva todos los permisos existentes.

-- Roles (los nombres existentes se conservan: otras migraciones los referencian).
insert into public.role (name, description) values
  ('usuario_comercial',   'Gestor Comercial: clientes, pedidos y exportaciones.'),
  ('encargado_logistico', 'Gestor de Logistica: despachos, envios y seguimiento.'),
  ('gestor_inventario',   'Gestor de Inventario: productos, lotes, fincas, proveedores y movimientos.'),
  ('gestor_financiero',   'Gestor Financiero: cartera de pagos y control financiero.'),
  ('gestor_cumplimiento', 'Gestor de Cumplimiento UE: declaracion EUDR, trazabilidad y documentos de exportacion.'),
  ('cliente',             'Cliente externo: portal de seguimiento de sus envios.')
on conflict (name) do update set description = excluded.description;

-- Permisos por rol: se reemplazan por el conjunto indicado.
delete from public.role_permission
where role_id in (select id from public.role where name in
  ('usuario_comercial','encargado_logistico','gestor_inventario','gestor_financiero','gestor_cumplimiento','cliente'));

insert into public.role_permission (role_id, permission_code)
select r.id, g.code
from (values
  -- Gestor Comercial
  ('usuario_comercial','customers.read'),('usuario_comercial','customers.create'),('usuario_comercial','customers.update'),
  ('usuario_comercial','orders.read'),('usuario_comercial','orders.create'),('usuario_comercial','orders.update'),
  ('usuario_comercial','orders.transition'),
  ('usuario_comercial','exports.read'),('usuario_comercial','exports.create'),
  ('usuario_comercial','products.read'),('usuario_comercial','inventory.read'),
  ('usuario_comercial','logistics.read'),('usuario_comercial','payments.read'),
  ('usuario_comercial','documents.read'),('usuario_comercial','documents.generate'),
  -- Gestor de Logistica
  ('encargado_logistico','logistics.read'),('encargado_logistico','logistics.create'),('encargado_logistico','logistics.update'),
  ('encargado_logistico','exports.read'),('encargado_logistico','orders.read'),
  ('encargado_logistico','customers.read'),('encargado_logistico','products.read'),
  ('encargado_logistico','lots.read'),('encargado_logistico','inventory.read'),
  ('encargado_logistico','documents.read'),('encargado_logistico','documents.upload'),
  -- Gestor de Inventario
  ('gestor_inventario','products.read'),('gestor_inventario','products.create'),('gestor_inventario','products.update'),
  ('gestor_inventario','inventory.read'),('gestor_inventario','inventory.adjust'),
  ('gestor_inventario','lots.read'),('gestor_inventario','lots.create'),
  ('gestor_inventario','farms.read'),('gestor_inventario','farms.create'),('gestor_inventario','farms.update'),
  ('gestor_inventario','suppliers.read'),('gestor_inventario','suppliers.create'),('gestor_inventario','suppliers.update'),
  -- Gestor Financiero
  ('gestor_financiero','payments.read'),('gestor_financiero','payments.create'),
  ('gestor_financiero','orders.read'),('gestor_financiero','customers.read'),
  ('gestor_financiero','exports.read'),('gestor_financiero','documents.read'),
  -- Gestor de Cumplimiento UE
  ('gestor_cumplimiento','exports.read'),('gestor_cumplimiento','exports.update'),
  ('gestor_cumplimiento','documents.read'),('gestor_cumplimiento','documents.generate'),('gestor_cumplimiento','documents.upload'),
  ('gestor_cumplimiento','orders.read'),('gestor_cumplimiento','customers.read'),
  ('gestor_cumplimiento','products.read'),('gestor_cumplimiento','lots.read'),
  ('gestor_cumplimiento','farms.read'),('gestor_cumplimiento','suppliers.read'),
  -- Cliente (portal)
  ('cliente','portal.read')
) as g(role_name, code)
join public.role r on r.name = g.role_name
on conflict do nothing;

-- El administrador conserva todos los permisos existentes.
insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r cross join public.permission p where r.name = 'administrador'
on conflict do nothing;
