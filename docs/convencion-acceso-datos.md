# Convención de acceso a datos desde la app Flutter

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.1  
**Estado:** Describe lo implementado en `lib/backend` y `lib/core/api`; pendiente de aprobación docente/cliente.  
**Supuesto:** el título de la tarea PLAT-414 estaba truncado en el backlog ("…acceso a datos d…"); se interpretó como "acceso a datos desde la app". Corregir si el alcance era otro.  
**Relacionado:** ADR-018, ADR-019, ADR-023 (`decisiones-arquitectura.md`); `modelo-autorizacion-rls.md`; RNF-15, RNF-18 y RNF-19.

## 1. Regla de capas

```
Pantalla (lib/features)  ->  callback inyectado  ->  ApiClient (lib/core/api)  ->  cliente de backend (lib/backend)  ->  Supabase
```

1. **Las pantallas nunca llaman a Supabase ni a `http` directamente.** Reciben funciones (`loadUsers`, `createRole`, …) construidas en el router a partir de `ApiClient`. Así se prueban sin red.
2. **`ApiClient`** construye la petición (método, ruta, cuerpo JSON, `X-Request-ID`, token Bearer, tiempo máximo de 15 s) y convierte toda respuesta de error en `ApiException`.
3. **El cliente de backend** implementa el contrato de rutas y decide cómo cumplirlo:
   - `SupabaseBackendClient`: traduce cada ruta a Supabase Auth o PostgREST.
   - `LocalBackendClient`: el mismo contrato en memoria, para pruebas y desarrollo sin credenciales.
4. **Se elige el cliente por configuración**, no por código: con `SUPABASE_URL` y `SUPABASE_ANON_KEY` (`--dart-define-from-file=.env`) se usa Supabase; si faltan, el local; con `USE_REMOTE_API=true`, un servidor HTTP externo.

## 2. Contrato de rutas implementado

Rutas relativas a la base; `Auth` indica si requiere sesión. El permiso lo aplica la base (ver `modelo-autorizacion-rls.md`).

| Método y ruta | Auth | Permiso en la base | Equivalente en Supabase |
|---|---|---|---|
| `POST /auth/login` | No | — | `POST auth/v1/token?grant_type=password` y comprobación de cuenta/rol activos en `profile` |
| `POST /auth/register` | No | — | `POST auth/v1/signup` (el trigger asigna el rol `cliente`) |
| `POST /auth/logout` | Sí | Titular | `POST auth/v1/logout?scope=local` (al mejor esfuerzo) |
| `POST /auth/password-reset-requests` | No | — | `POST auth/v1/recover` (respuesta siempre neutra) |
| `POST /auth/password-resets` | No | — | `POST auth/v1/verify` (código) + `PUT auth/v1/user` (contraseña) + cierre de la sesión temporal |
| `GET /products` | Sí | `products.read` | `GET rest/v1/product_catalog` (filtros `type`, `is_active`, `certification_id`, `quality`, `q`) |
| `GET /products/{id}` | Sí | `products.read` | `GET rest/v1/product_catalog?id=eq.{id}` |
| `POST /products` | Sí | `products.create` | `POST rest/v1/rpc/create_product` |
| `PATCH /products/{id}` | Sí | `products.update` | `POST rest/v1/rpc/update_product` |
| `PATCH /products/{id}/status` | Sí | `products.update` | `POST rest/v1/rpc/set_product_active` |
| `PUT /products/{id}/certifications` | Sí | `products.update` | `POST rest/v1/rpc/set_product_certifications` |
| `GET /suppliers` | Sí | `suppliers.read` | `GET rest/v1/supplier` (filtros `is_active`, `q` sobre razón social y documento) |
| `GET /suppliers/{id}` | Sí | `suppliers.read` | `GET rest/v1/supplier?id=eq.{id}` |
| `POST /suppliers` | Sí | `suppliers.create` | `POST rest/v1/rpc/create_supplier` |
| `PATCH /suppliers/{id}` | Sí | `suppliers.update` | `POST rest/v1/rpc/update_supplier` |
| `PATCH /suppliers/{id}/status` | Sí | `suppliers.update` | `POST rest/v1/rpc/set_supplier_active` |
| `GET /customers` | Sí | `customers.read` | `GET rest/v1/customer` (filtros `is_active`, `country_code`, `q` sobre nombre y EORI normalizado) |
| `GET /customers/{id}` | Sí | `customers.read` | `GET rest/v1/customer?id=eq.{id}` |
| `POST /customers` | Sí | `customers.create` | `POST rest/v1/rpc/create_customer` |
| `PATCH /customers/{id}` | Sí | `customers.update` | `POST rest/v1/rpc/update_customer` |
| `PATCH /customers/{id}/status` | Sí | `customers.update` | `POST rest/v1/rpc/set_customer_active` |
| `GET /customers/{id}/accounts` | Sí | `customers.read` | `GET rest/v1/customer_account_link?customer_id=eq.{id}` (vista con correo, nombre y acceso al portal) |
| `POST /customers/{id}/accounts` | Sí | `customers.update` | `POST rest/v1/rpc/link_customer_user` (por el correo de la cuenta) |
| `DELETE /customers/{id}/accounts/{profile_id}` | Sí | `customers.update` | `POST rest/v1/rpc/unlink_customer_user` |
| `GET /customers/{id}/history` | Sí | `customers.read` | `GET rest/v1/customer_order_history` y `customer_export_history` (borrador, ver `drafts/customer_history.sql`); responde `available: false` mientras las vistas no existan |
| `GET /farms` | Sí | `farms.read` | `GET rest/v1/farm_catalog` (vista con proveedor y total de lotes; filtros `is_active`, `supplier_id`, `q`) |
| `GET /farms/{id}` | Sí | `farms.read` | `GET rest/v1/farm_catalog?id=eq.{id}` |
| `POST /farms` | Sí | `farms.create` | `POST rest/v1/rpc/create_farm` |
| `PATCH /farms/{id}` | Sí | `farms.update` | `POST rest/v1/rpc/update_farm` |
| `PATCH /farms/{id}/status` | Sí | `farms.update` | `POST rest/v1/rpc/set_farm_active` |
| `GET /lots`, `GET /lots/{id}` | Sí | `lots.read` | `GET rest/v1/lot_catalog` (filtros `farm_id`, `product_id`, `q` sobre el código) |
| `POST /lots` | Sí | `lots.create` | `POST rest/v1/rpc/create_lot` |
| `GET /certifications`, `GET /units` | Sí | Cuenta activa | `GET rest/v1/certification`, `GET rest/v1/unit_of_measure` |
| `PATCH /users/{id}/activate` | Sí | `users.deactivate` | `PATCH rest/v1/profile` con `is_active=true` |
| `GET /me` | Sí | Fila propia | `GET rest/v1/profile?auth_user_id=eq.<sub>` con los permisos del rol embebidos |
| `PATCH /me` | Sí | Titular | `PUT auth/v1/user` (cambio de correo con confirmación) |
| `GET /users` | Sí | `users.read` | `GET rest/v1/profile` |
| `PATCH /users/{id}` | Sí | `users.update` | `PATCH rest/v1/profile?id=eq.{id}` |
| `PATCH /users/{id}/deactivate` | Sí | `users.deactivate` | `PATCH rest/v1/profile` con `is_active=false` |
| `GET /roles`, `GET /roles/permissions` | Sí | Cualquier sesión | `GET rest/v1/role`, `GET rest/v1/permission` |
| `POST /roles` | Sí | `roles.create` | `POST rest/v1/role` |
| `PATCH /roles/{id}` | Sí | `roles.update` | `PATCH rest/v1/role?id=eq.{id}` |
| `PATCH /roles/{id}/deactivate` | Sí | `roles.deactivate` | `PATCH rest/v1/role` con `is_active=false` |
| `PUT /roles/{id}/permissions` | Sí | `roles.permissions.update` | `POST rest/v1/rpc/set_role_permissions` |

## 3. Convenciones de datos

- **Nombres:** JSON en `snake_case`. Identificadores numéricos (`BIGINT`) en `id` y `*_id`; los usuarios de Supabase Auth (UUID) no salen del cliente de backend.
- **Listados:** respuesta `{ "items": [...], "pagination": { "total", "limit", "offset" } }`. Parámetros `limit` (1 a 100, por defecto 20), `offset`, `q` (texto) y filtros por campo (`is_active`). El total sale de `Prefer: count=exact`.
- **Búsqueda:** el texto se limpia de los caracteres que PostgREST interpreta (`, ( ) * % \`) antes de armar el filtro `ilike`.
- **Texto:** se recorta (`trim`); el correo se normaliza a minúsculas; el nombre de rol, a `minusculas_con_guion_bajo`.
- **Columnas:** siempre se piden de forma explícita (`select=id,email,...`), nunca `*`; las relaciones se incrustan en la misma consulta (`role(is_active,role_permission(permission_code))`) para evitar peticiones extra.
- **Fechas y horas:** `TIMESTAMPTZ` en UTC.

## 4. Convenciones de escritura

- Las modificaciones piden la fila resultante (`Prefer: return=representation`). Si la respuesta viene vacía, se trata como "no encontrado" (o sin permiso, que desde RLS es indistinguible).
- **Una operación de negocio = una llamada atómica.** Si implica varios pasos que deben cumplirse juntos (por ejemplo, reemplazar los permisos de un rol), se implementa como función de base de datos (`rpc/...`) y no como varias peticiones desde la app.
- Los campos que la app no puede editar se rechazan en el cliente (`422`) y, además, la base los protege con privilegios por columna.
- No existe borrado desde la app: se usa baja lógica (`is_active`).

## 5. Formato de errores

Toda respuesta de error tiene la forma:

```json
{ "error": { "code": "CONFLICT", "message": "...", "details": [ { "field": "email", "code": "already_exists", "message": "..." } ], "request_id": "..." } }
```

| Origen | Situación | HTTP / `code` |
|---|---|---|
| Auth | Credenciales incorrectas, cuenta o rol inactivos | `401` `UNAUTHORIZED` (mensaje único, sin revelar si la cuenta existe) |
| Auth | Correo sin confirmar (tras validar la contraseña) | `401` `UNAUTHORIZED` con mensaje específico |
| Auth | Correo ya registrado | `409` `CONFLICT` |
| Auth | Contraseña débil / correo inválido | `422` `VALIDATION_ERROR` |
| Auth | Límite de correos | `429` `RATE_LIMIT_EXCEEDED` |
| PostgREST | JWT vencido (`PGRST303`) | `401` `UNAUTHORIZED` |
| PostgREST | Sin permiso (`42501`, `403`) | `403` `FORBIDDEN` |
| PostgREST | Unicidad (`23505`) | `409` `CONFLICT` |
| Regla de negocio de la base (`P0001`) | Por ejemplo, "no se puede dejar el sistema sin administrador activo" | `409` `CONFLICT`, con el mensaje de la regla |
| Función de la base | No encontrado (`P0002`) | `404` `NOT_FOUND` |
| Base | Datos no válidos (`22023`, `23503`, `23514`) | `422` `VALIDATION_ERROR` |
| Supabase | Caída o respuesta ilegible | `502` `INTERNAL_SERVER_ERROR` |
| Red | Sin conexión o tiempo agotado | `ApiException` `API_CONNECTION_ERROR` / `REQUEST_TIMEOUT` |

Las pantallas muestran `message`; nunca el cuerpo crudo del error ni trazas.

## 6. Cabeceras y sesión

- Todas las llamadas llevan `apikey` (clave pública). La cabecera `Authorization: Bearer` lleva el JWT del usuario; en las rutas de autenticación sin sesión se usa la clave pública.
- El token se guarda con `flutter_secure_storage`, se descarta si ya venció y se elimina al cerrar sesión. No se guardan contraseñas.
- Un `401` por vencimiento obliga a iniciar sesión de nuevo (no hay refresco automático todavía; ADR-021).
- La clave `service_role` y la cadena de conexión **nunca** se incluyen en la app (ADR-020). `.env` no se versiona (está en `.gitignore`) y es el único lugar con las claves.

## 7. Cómo añadir un módulo nuevo

1. **Base:** tablas, RLS, permisos y triggers en `database/migrations/` (lista de verificación en `modelo-autorizacion-rls.md`, sección 9).
2. **Contrato:** añadir las rutas a este documento (sección 2).
3. **Clientes:** implementar la ruta en `SupabaseBackendClient` y en `LocalBackendClient`, con las mismas respuestas y errores.
4. **Pantalla:** en `lib/features/<modulo>/`, con funciones inyectadas desde el router; sin acceso directo a red.
5. **Pruebas:** del cliente de Supabase con `MockClient` (rutas, parámetros, errores), del cliente local, y de la pantalla con funciones falsas.

## 8. Pendientes

- Refresco de sesión y revocación (ADR-021).
- Operaciones privilegiadas mediante Edge Functions (ADR-020), por ejemplo cambiar el correo de otro usuario.
- Contrato para los módulos de negocio restantes (productos, pedidos, exportaciones, inventario, pagos, logística, notificaciones, reportes).
- Sustituto de OpenAPI para publicar el contrato (RNF-15); hoy es este documento.
