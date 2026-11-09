# Contrato de la API REST

**Versión:** 0.1 - contrato inicial  
**Estado:** Propuesta alineada con requisitos y arquitectura; pendiente de aprobación  
**Formato:** JSON sobre HTTPS; archivos por carga/descarga autenticada

## 1. Convenciones

- Base URL: `/api/v1`; respuestas JSON usan `application/json; charset=utf-8`.
- CORS se aplica a clientes de navegador, incluido Flutter Web; no es una restricción de Flutter nativo Android/iOS. En desarrollo se permiten orígenes locales; en producción se configura una lista explícita de orígenes web permitidos, nunca `*`.
- Las respuestas exitosas no agregan un envoltorio global `data`: operaciones de recurso devuelven el recurso definido por su contrato; los listados usan `{ "items": [], "pagination": { "limit": 20, "offset": 0, "total": 0 } }`. Las respuestas sin contenido usan `204`.
- Los identificadores públicos son enteros positivos `int64` en esta versión inicial, igual que las claves de persistencia propuestas.
- Fechas/horas se intercambian en ISO 8601 con zona (`2026-10-02T15:30:00Z`) y se almacenan en UTC. Fechas de negocio sin hora usan `YYYY-MM-DD`.
- Importes usan decimal JSON como cadena para evitar pérdida de precisión, p. ej. `"1250.50"`; nunca `float` binario. Cantidades y tasas también se serializan como cadenas decimales.
- País usa código ISO 3166-1 alpha-2; moneda usa código ISO 4217; estados y códigos se envían como valores estables en minúscula con guion bajo.
- Campos desconocidos en una petición se rechazan con `422`; campos de salida nuevos y opcionales no deben romper clientes existentes.
- Listados aceptan `limit` (por defecto 20, máximo 100), `offset` (por defecto 0) y filtros documentados por recurso. Respuesta: `{ "items": [], "pagination": { "limit": 20, "offset": 0, "total": 0 } }`.
- Ordenamiento se limita a campos permitidos por endpoint mediante `sort` y `order=asc|desc`; no se aceptan nombres de columnas arbitrarios.
- Mutaciones protegidas requieren `Authorization: Bearer <access_token>`. El token identifica al usuario; la API evalúa permisos vigentes desde el backend.
- `X-Request-ID` se acepta si contiene entre 1 y 128 caracteres alfanuméricos o `._:-`; si falta o no cumple el formato, el servidor genera uno con prefijo `req_`. Se devuelve siempre en la cabecera de respuesta y también en el cuerpo de error para correlación. `Idempotency-Key` es obligatorio al crear pagos, movimientos de inventario, exportaciones y trabajos asíncronos; reusar la clave con cuerpo distinto devuelve `409`.
- Las operaciones son síncronas salvo las marcadas **async**. Una tarea async devuelve `202 Accepted`, `Location: /api/v1/jobs/{job_id}` y `Retry-After` cuando aplique.

## 2. Errores

Todos los errores usan una forma común:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "La solicitud contiene datos no válidos.",
    "details": [{ "field": "email", "code": "invalid_format", "message": "Formato no válido." }],
    "request_id": "req_..."
  }
}
```

`details` puede ser una lista vacía; el mensaje no incluye secretos ni datos personales innecesarios.
Cada elemento de `details` tiene `field` (opcional), `code` y `message`. Los errores de validación usan códigos estables como `required`, `unknown_field`, `invalid_format` e `invalid_value`; nunca se devuelven valores de entrada ni trazas. Los errores inesperados se registran en el servidor y responden con un mensaje genérico.

| HTTP | Cuándo se usa |
|---|---|
| 400 | Parámetros/formato general inválidos que no corresponden a validación de campos. |
| 401 | Token ausente, inválido o expirado; credenciales incorrectas. |
| 403 | Usuario autenticado sin permiso para la operación. |
| 404 | Recurso inexistente o fuera del alcance visible para el usuario. |
| 409 | Duplicado, estado incompatible, transición no permitida o conflicto de idempotencia. |
| 422 | Campos o relaciones de la solicitud no pasan validación. |
| 429 | Límite de solicitudes excedido; incluye `Retry-After`. |
| 500 | Error inesperado; respuesta genérica con `request_id`. |
| 503 | Dependencia necesaria temporalmente no disponible. |

## 3. Endpoints

`Auth` indica token requerido; `Público` no requiere token; `Permiso` requiere autenticación y permiso de módulo/acción.

| Método y ruta | Acceso | Contrato / resultado |
|---|---|---|
| `GET /health/live` | Público/interno | `200`; el proceso está vivo. No revela configuración. |
| `GET /health/ready` | Público/interno | `200` si dependencias esenciales están listas; `503` si no. |
| `POST /auth/login` | Público | `{email,password}` -> `200 {access_token,token_type,expires_in,user}`; credenciales inválidas `401`. |
| `POST /auth/password-reset-requests` | Público | `{email}` -> `202`; respuesta no revela si el correo existe. Envío se procesa async. |
| `POST /auth/password-resets` | Público | `{token,new_password}` -> `204`; token vencido/consumido `400`. |
| `GET /users/me` | Auth | `200 User`; solo perfil propio. |
| `PATCH /users/me` | Auth | Campos editables del perfil -> `200 User`. |
| `GET /users` | Permiso `users.read` | Filtros `q`, `role_id`, `is_active`; `200` paginado. |
| `POST /users` | Permiso `users.create` | `{email,password,first_name,last_name,phone?,role_id}` -> `201 User`; correo duplicado `409`. |
| `GET /users/{user_id}` | Permiso `users.read` | `200 User`. |
| `PATCH /users/{user_id}` | Permiso `users.update` | Actualiza campos administrables -> `200 User`. |
| `PATCH /users/{user_id}/status` | Permiso `users.manage` | `{is_active}` -> `200 User`. |
| `GET /roles` | Permiso `roles.read` | `200` paginado con permisos asociados. |
| `POST /roles` | Permiso `roles.manage` | `{name,description?,permission_codes[]}` -> `201 Role`. |
| `PATCH /roles/{role_id}` | Permiso `roles.manage` | Actualiza nombre, descripción y conjunto de permisos -> `200 Role`. |
| `GET /products` | Permiso `products.read` | Filtros `type`, `quality`, `certification_id`, `is_active`; `200` paginado. |
| `POST /products` | Permiso `products.create` | Producto tipado café/cacao con sus atributos; `201 Product`. |
| `GET /products/{product_id}` | Permiso `products.read` | `200 Product` con certificaciones. |
| `PATCH /products/{product_id}` | Permiso `products.update` | Actualización parcial -> `200 Product`. |
| `PUT /products/{product_id}/certifications` | Permiso `products.update` | `{certification_ids[]}` reemplaza asociaciones -> `200 Product`. |
| `GET /suppliers` / `POST /suppliers` | `suppliers.read/create` | Listado paginado o creación de proveedor -> `200` / `201 Supplier`. |
| `GET /suppliers/{id}` / `PATCH /suppliers/{id}` | `suppliers.read/update` | Consulta o actualización de proveedor. |
| `GET /farms` / `POST /farms` | `farms.read/create` | Filtros `supplier_id`; crear finca geolocalizada -> `201 Farm`. |
| `GET /farms/{id}` / `PATCH /farms/{id}` | `farms.read/update` | Consulta o actualización de finca/coordenadas. |
| `GET /product-lots` / `POST /product-lots` | `lots.read/create` | Filtros `product_id`, `farm_id`; creación de lote de producto -> `201 ProductLot`. |
| `GET /customers` / `POST /customers` | `customers.read/create` | Filtros `q`, `country_code`, `eori`; crear cliente con país, EORI y moneda preferida -> `201 Customer`. |
| `GET /customers/{id}` / `PATCH /customers/{id}` | `customers.read/update` | Consulta o actualización de cliente. |
| `GET /customers/{id}/history` | `customers.read` | `200 {orders[],exports[]}` paginados o con paginación independiente. |
| `GET /orders` | `orders.read` | Filtros `customer_id`, `product_id`, `status`; `200` paginado. |
| `POST /orders` | `orders.create` | `{customer_id,currency_code,lines:[{product_id,quantity,unit_price}]}` -> `201 Order`. Se exige al menos una línea; la cantidad usa la unidad base del producto. |
| `GET /orders/{id}` | `orders.read` | Pedido, líneas y totales calculados -> `200 Order`. |
| `PATCH /orders/{id}` | `orders.update` | Solo pedidos `pending`; modifica datos permitidos y líneas -> `200`; otros estados `409`. |
| `PATCH /orders/{id}/status` | `orders.transition` | `{status}` en `pending`, `confirmed`, `in_process`, `exported` -> `200 Order`; transición inválida `409`. |
| `GET /exports` | `exports.read` | Filtros `customer_id`, `country_code`, `from`, `to`, `order_id`; `200` paginado. |
| `POST /orders/{order_id}/exports` | `exports.create` | `{destination_country_code,incoterm_code,incoterm_edition_year,export_date,lines:[{order_line_id,product_lot_id,quantity,hs_code?}]}` -> `201 Export`; exige al menos una línea, cantidades en unidad base; requiere `Idempotency-Key`. |
| `GET /exports/{id}` | `exports.read` | Exportación, líneas y referencia a pedido -> `200 Export`. |
| `PATCH /exports/{id}` | `exports.update` | Actualiza campos modificables antes de formalización -> `200`; regla de bloqueo por estado pendiente de aprobación. |
| `POST /exports/{id}/due-diligence-declarations` | `exports.documents.generate` | Solicita declaración EUDR -> `202 Job`; valida/enumera información faltante cuando el trabajo se procesa. |
| `GET /exports/{id}/documents` | `documents.read` | Listado de metadatos del expediente -> `200` paginado. |
| `POST /exports/{id}/documents/generate` | `documents.generate` | `{type}` (`commercial_invoice`, `packing_list`, `eur1`) -> `202 Job`. La generación de EUDR usa la ruta dedicada. Tipos oficiales habilitados dependen de aprobación normativa. |
| `POST /exports/{id}/documents` | `documents.upload` | Metadatos y archivo adjunto fitosanitario u otro permitido -> `201 ExportDocument`; límites/tipos de archivo se publican en OpenAPI. |
| `GET /documents/{id}` | `documents.read` | Metadatos -> `200 ExportDocument`. |
| `GET /documents/{id}/content` | `documents.read` | Descarga autenticada o `302` a URL temporal firmada. |
| `GET /inventory` | `inventory.read` | Filtros `product_id`, `product_lot_id`; cantidades disponibles calculadas de movimientos. |
| `GET /inventory/movements` | `inventory.read` | Filtros por lote, tipo y fecha -> movimientos paginados. |
| `POST /inventory/adjustments` | `inventory.adjust` | `{product_lot_id,quantity_delta,unit_code,reason}` -> `201 InventoryMovement`; `unit_code` se valida contra la unidad base del producto; requiere `Idempotency-Key`. |
| `GET /orders/{order_id}/payment-obligations` / `POST /orders/{order_id}/payment-obligations` | `payments.read/create` | Consulta o crea obligación `{amount_due,currency_code,due_date}` -> `200` / `201`. Entidad propuesta para soportar pendientes/vencidos. |
| `POST /payment-obligations/{id}/transactions` | `payments.create` | `{amount,currency_code,paid_at,exchange_rate_id?}` -> `201 PaymentTransaction`; requiere `Idempotency-Key`. |
| `GET /payment-obligations` | `payments.read` | Filtros `status=unpaid|partial|paid|overdue`, `order_id`; `paid` si los abonos cubren el total, `unpaid` si no hay abonos y no venció, `partial` si hay abonos y aún no venció, `overdue` si queda saldo y pasó la fecha límite. |
| `GET /exchange-rates` | `payments.read` | Filtros `from_currency`, `to_currency`, `as_of`; `200` con tasa y fuente/fecha. |
| `GET /exports/{export_id}/shipments` / `POST /exports/{export_id}/shipments` | `logistics.read/create` | Consulta o registra transportista/guía -> `200` / `201 Shipment`. |
| `POST /shipments/{id}/events` | `logistics.update` | `{status,occurred_at,description?}` en preparación, tránsito, aduana o entregado -> `201 ShipmentEvent`. |
| `GET /shipments/{id}/timeline` | Auth con acceso al envío | `200` cronología ordenada por fecha. |
| `GET /notifications` | Auth | Filtros `is_read`, `type`; solo notificaciones del usuario actual. |
| `PATCH /notifications/{id}` | Auth | `{is_read:true}` -> `200`; solo el destinatario puede actualizarla. |
| `GET /reports/exports` | Permiso `reports.read` | Filtros `product_id`, `customer_id`, `country_code`, `from`, `to`; respuesta síncrona. Si el alcance excede el límite interactivo, devuelve `409 ASYNC_REQUIRED` e indica usar el endpoint de trabajos. |
| `POST /reports/exports/jobs` | Permiso `reports.read` | Mismos filtros más formato -> `202 Job` para generación extensa. |
| `GET /dashboard` | Permiso `dashboard.read` | KPIs definidos para el rol/periodo -> `200`; catálogo y fórmula de KPI pendientes. |
| `GET /jobs/{job_id}` | Propietario del trabajo o permiso administrativo | `200 Job`; acceso a trabajos ajenos devuelve `404`. |

Los endpoints `GET /...` y `POST /...` combinados en una fila tienen los permisos indicados como `recurso.read/create` en el mismo orden; en OpenAPI se publicarán como operaciones separadas.

## 4. Contratos de recursos principales

### Producto

```json
{
  "id": 42,
  "type": "coffee",
  "variety": "string",
  "quality_grade": "string",
  "hs_code": "string|null",
  "base_unit_code": "kg",
  "coffee_details": { "humidity_percent": "decimal" },
  "cacao_details": null,
  "certifications": [{ "id": 3, "code": "organic", "name": "Orgánico" }],
  "is_active": true,
  "created_at": "2026-10-02T15:30:00Z",
  "updated_at": "2026-10-02T15:30:00Z"
}
```

Para `type=cacao`, `cacao_details` contiene `bean_type` y `fermentation_percent`, y `coffee_details` es `null`. Solo el subtipo correspondiente puede enviarse.

### Pedido

```json
{
  "id": 81,
  "customer_id": 17,
  "status": "pending",
  "currency_code": "EUR",
  "lines": [{ "id": 1, "product_id": 42, "quantity": "500.000", "unit_code": "kg", "unit_price": "4.2500", "line_total": "2125.00" }],
  "total": "2125.00",
  "created_at": "2026-10-02T15:30:00Z",
  "updated_at": "2026-10-02T15:30:00Z"
}
```

`line_total` y `total` son calculados por el servidor y de solo lectura. `unit_code` en la respuesta se deriva de `product.base_unit_code`; no se persiste en la línea. La precisión y redondeo de precios/totales se fijarán junto con monedas y unidades.

### Exportación

```json
{
  "id": 93,
  "order_id": 81,
  "destination_country_code": "DE",
  "incoterm_code": "FOB",
  "incoterm_edition_year": 2020,
  "export_date": "2026-10-02",
  "status": "draft",
  "lines": [{ "id": 1, "order_line_id": 1, "product_lot_id": 55, "quantity": "500.000", "unit_code": "kg", "hs_code": "0901.11" }],
  "created_at": "2026-10-02T15:30:00Z"
}
```

`status=draft` es un valor propuesto; estados y transición de exportación deben aprobarse. `unit_code` se deriva del producto de la línea del pedido. El HS devuelto por línea es el código aplicado a esa exportación, no necesariamente el valor vigente del catálogo.

### Trabajo asíncrono

```json
{
  "id": 205,
  "type": "export_report",
  "status": "queued",
  "progress_percent": 0,
  "created_at": "2026-10-02T15:30:00Z",
  "completed_at": null,
  "result_document_id": null,
  "error_code": null
}
```

Estados públicos: `queued`, `running`, `succeeded`, `failed`. El worker puede usar estados internos adicionales, pero debe mapearlos a estos valores.

## 5. Reglas de contrato

- La API nunca confía en identificadores o permisos de la interfaz; valida autorización y propiedad/acceso en backend.
- Las operaciones con efectos financieros o de inventario son transaccionales e idempotentes.
- Crear un pedido no reduce stock. Confirmar pedido/exportación genera movimientos de inventario según la regla aprobada; cualquier reverso genera un movimiento compensatorio, no borra el historial.
- Estados de pedido válidos según backlog: `pending`, `confirmed`, `in_process`, `exported`. Estados logísticos: `preparation`, `in_transit`, `customs`, `delivered`. Transiciones requieren autorización de negocio.
- Los datos derivados (`line_total`, stock disponible, estado de obligación vencida) se calculan en servidor; no se aceptan como autoridad desde el cliente.
- Las cargas de archivos limitan extensión, MIME, tamaño y permisos; el archivo binario no se devuelve en listados.
- La generación de documentos responde `202`; el trabajo debe completarse dentro del objetivo de 5 segundos para las condiciones normales acordadas, aunque la API retorne antes con el identificador.
- Cambios incompatibles se publican en una nueva versión de API. Swagger/OpenAPI es la fuente del contrato implementado.

## 6. Pendientes para cerrar el contrato

1. Acordar permisos por operación y qué perfiles pueden acceder a información comercial.
2. Confirmar si el registro de usuarios es exclusivamente administrativo o si habrá autorregistro; la tarea de interfaz menciona registro, mientras la historia asigna esa acción al administrador.
3. Aprobar códigos de estado de pedido/exportación/pago y transiciones.
4. Definir EORI opcional/obligatorio según país, campos de cliente y reglas de pedido de varios productos.
5. Definir moneda base, precisión, redondeo, proveedor/tolerancia de tasas de cambio y obligaciones de pago.
6. Confirmar umbral de reportes/PDF síncronos, formatos de salida y límites de archivo.
7. Acordar si el cliente accede a su propia línea de tiempo o si toda consulta logística requiere cuenta autenticada.
8. Validar campos, formatos oficiales y estados documentales para EUDR, EUR.1 y certificados.
