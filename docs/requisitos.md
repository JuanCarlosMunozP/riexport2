# Documento de requisitos — RiExport (PLAT-407, PLAT-408)

Requisitos derivados del backlog (HU.01–HU.30) y verificados contra el código. Estado: **borrador pendiente de validación y firma** (ver `acta-validacion-requisitos.md`).

## Requisitos funcionales

| ID | Requisito | HU | Implementación |
|---|---|---|---|
| RF-01 | Registro público de usuarios con confirmación de correo | HU.01 | `handle_new_user`, `UserRegistrationScreen`, `ConfirmEmailScreen` |
| RF-02 | Inicio y cierre de sesión; bloqueo de usuarios desactivados | HU.02/03 | `LoginScreen`, `is_active_user`, `sync_auth_access` |
| RF-03 | Listar, buscar, cambiar rol y desactivar usuarios (con auditoría) | HU.05–07 | `admin_user_list`, `audit_log`, `UsersScreen` |
| RF-04 | Administrar roles y permisos | HU.08 | `set_role_permissions`, `RolesScreen` |
| RF-05 | Recuperar acceso y editar el perfil propio | HU.09/10 | `recovery`, `ProfileScreen` |
| RF-06 | Gestionar productos de café y cacao, certificaciones, filtros e inactivación sin perder historial | HU.11–15 | `create_product`, `product_catalog`, `block_product_delete` |
| RF-07 | Gestionar proveedores | HU.16 | `supplier`, `SupplierListScreen` |
| RF-08 | Registrar fincas y lotes con geolocalización y mapa | HU.17/18 | `farm`, `product_lot`, `LocationPickerScreen` |
| RF-09 | Visualizar el origen de un envío en el mapa | — | `export_traceability`, `TraceabilityMapScreen` |
| RF-10 | Gestionar clientes (EORI), historial comercial y cuentas vinculadas | HU.20–22 | `customer`, `customer_user`, `CustomerHistoryScreen` |
| RF-11 | Registrar, editar (solo borrador), filtrar y cambiar el estado de pedidos validando inventario | HU.22–25 | `create_customer_order`, `transition_customer_order` |
| RF-12 | Registrar exportaciones desde pedidos confirmados con país e Incoterm | HU.26 | `create_customer_export`, `ExportRegistrationScreen` |
| RF-13 | Asignar el código HS a cada línea de exportación | HU.27 | `hs_code_snapshot` |
| RF-14 | Generar la declaración EUDR validando la trazabilidad completa | HU.28 | `export_eudr_declaration`, `EudrDeclarationScreen` |
| RF-15 | Consultar el historial de exportaciones | HU.29 | `export_history`, `ExportHistoryScreen` |
| RF-16 | Generar documentos PDF de la exportación | HU.30 | `generate-document`, `POST /exports/:id/documents` |

## Requisitos no funcionales

| ID | Requisito | Cómo se cumple |
|---|---|---|
| RNF-01 | Seguridad: acceso mínimo por rol y aislamiento del cliente externo | RLS + `has_permission` + `my_*_ids` |
| RNF-02 | Integridad: nada con historial se borra | Triggers `*_no_delete`, baja lógica |
| RNF-03 | Auditoría de cambios sensibles | `audit_log` inmutable |
| RNF-04 | Credenciales fuera del repositorio | `.env` ignorado por `.gitignore`, clave anónima pública |
| RNF-05 | Plataformas: Android, iOS y web | Proyecto Flutter |
| RNF-06 | Transporte seguro | HTTPS obligatorio salvo loopback |
| RNF-07 | Trazabilidad EUDR hasta finca geolocalizada | Vistas de trazabilidad |
| RNF-08 | Mantenibilidad: esquema versionado y pruebas | Migraciones, `database/tests`, `flutter test` |
| RNF-09 | Idioma de interfaz: español | Textos de UI |
