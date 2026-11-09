# Registro de decisiones de arquitectura

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.9 (se agregan ADR-030 y ADR-031)  
**Estado general:** Decisiones de diseño para revisión; ninguna implica implementación ni aprobación externa.

Este registro conserva las decisiones y sus razones. **Diseño adoptado** significa que los documentos del proyecto usan actualmente esa decisión; **pendiente de aprobación** señala que debe confirmarse con docente/cliente o al definir infraestructura.

## Índice de decisiones

| ID | Decisión | Estado actual |
|---|---|---|
| ADR-001 | Monolito modular | Reemplazada por ADR-018 |
| ADR-002 | API REST versionada | Reemplazada por ADR-018 |
| ADR-003 | Solicitudes síncronas y trabajos en segundo plano | En revisión (ADR-018) |
| ADR-004 | PostgreSQL y persistencia relacional | Parcial: sigue PostgreSQL, ahora en Supabase (ADR-018) |
| ADR-005 | Cliente Flutter | Vigente |
| ADR-006 | Límites de módulo y propiedad de datos | Vigente (módulo = tablas + reglas + rutas + pantallas) |
| ADR-007 | Control de acceso basado en roles y permisos | Actualizada por ADR-019 y ADR-022 |
| ADR-008 | Inventario como libro de movimientos | Vigente (aún sin implementar) |
| ADR-009 | Integraciones externas tras adaptadores | Vigente (adaptadores como Edge Functions, futuro) |
| ADR-010 | Outbox durable para trabajo asíncrono | En revisión (ADR-018) |
| ADR-011 | Archivos fuera de la base de datos | Vigente; concretada por ADR-025 |
| ADR-012 | Claves, tiempo y precisión | Vigente |
| ADR-013 | Trazabilidad documental y arancelaria | Vigente (aún sin implementar) |
| ADR-014 | Gestión de estado Flutter | Vigente |
| ADR-015 | Cliente HTTP Flutter | Actualizada por ADR-018 y ADR-023 |
| ADR-016 | Navegación Flutter | Vigente |
| ADR-017 | Emisión y validación de JWT | Reemplazada por ADR-021 |
| ADR-018 | Backend dentro de la app Flutter sobre Supabase | Adoptada |
| ADR-019 | Dónde vive la lógica de negocio | Adoptada |
| ADR-020 | Operaciones privilegiadas fuera de la app | Adoptada |
| ADR-021 | Sesión y JWT delegados a Supabase Auth | Adoptada |
| ADR-022 | Modelo de autorización por RLS | Adoptada; actualizada por ADR-026 |
| ADR-023 | Convención de acceso a datos desde la app | Adoptada |
| ADR-024 | Esquema versionado con migraciones de la CLI de Supabase | Adoptada |
| ADR-025 | Almacenamiento de archivos en Supabase Storage con buckets privados | Adoptada |
| ADR-026 | Permiso propio para asignar roles y autoedición del perfil | Adoptada; ampliada por ADR-029 |
| ADR-027 | Bloqueo de usuarios desactivados en la base y en Supabase Auth | Adoptada |
| ADR-028 | Aislamiento del cliente externo por vínculo y vista de usuarios de administración | Vista adoptada; aislamiento propuesto |
| ADR-029 | Política de cambio de rol y auditoría append-only | Adoptada |
| ADR-030 | Productos: lectura por RLS y escritura por funciones atómicas, sin borrado | Adoptada |
| ADR-031 | Recuperación de acceso con código de un solo uso por correo | Adoptada |

**Convención de este registro:** cada decisión tiene Estado, Decisión, Contexto y Consecuencias. Una decisión no se borra: si cambia, se marca como *Reemplazada por ADR-xxx* y se crea una nueva. Las decisiones con estado *Adoptada* o *Vigente* siguen pendientes de aprobación docente/cliente hasta que el acta de `requerimientos.md` (sección 10) esté firmada.

## ADR-001: Monolito modular

- **Estado:** Diseño adoptado; pendiente de aprobación del equipo/docente. **Reemplazada por ADR-018 (2026-10-08): ya no hay backend monolítico propio.**
- **Decisión:** Mantener una sola aplicación backend desplegable, dividida en módulos por dominio con routers, servicios y persistencia bien delimitados.
- **Contexto:** El alcance contiene varios módulos relacionados y el equipo está construyendo una primera versión académica. No hay evidencia de equipos o cargas independientes que justifiquen microservicios.
- **Consecuencias:** Un despliegue y transacciones más sencillas; separación lógica y contratos internos necesarios para evitar dependencias circulares. Escalar un módulo por separado no será posible sin una evolución posterior.

## ADR-002: API REST versionada

- **Estado:** Diseño adoptado. **Reemplazada por ADR-018: el contrato de rutas lo da `lib/backend`; OpenAPI deja de aplicar (RNF-15).**
- **Decisión:** Exponer recursos por HTTP/JSON bajo `/api/v1`, con OpenAPI como contrato del API implementado.
- **Contexto:** El backlog exige API REST CRUD general y documentación Swagger/OpenAPI para una app Flutter multiplataforma.
- **Consecuencias:** Contrato independiente del cliente, operaciones y errores uniformes, y evolución incompatible mediante una nueva versión. El API no replica los nombres de tablas como obligación del cliente.

## ADR-003: Solicitudes síncronas y trabajos en segundo plano

- **Estado:** Diseño adoptado; tecnología de cola pendiente. **En revisión por ADR-018: sin worker propio.**
- **Decisión:** Procesar CRUD, autenticación, validaciones y consultas comunes en solicitudes síncronas. Enviar generación extensa de reportes/PDF, correos, push y lotes a un worker; retornar `202 Accepted` y un identificador consultable.
- **Contexto:** La versión previa usaba endpoints síncronos, SQLAlchemy síncrono y Psycopg síncrono. El backlog define máximo de cinco segundos para reportes/PDF en condiciones normales.
- **Consecuencias:** Mantiene simple el camino principal y evita bloquear la respuesta por procesos largos. Requiere persistir trabajos, estado, errores y estrategia de reintentos. El umbral de volumen para delegar al worker debe medirse; cinco segundos sigue siendo el objetivo para el caso normal.
- **Regla de implementación:** No ejecutar llamadas bloqueantes a base de datos o SDK síncronos dentro de un endpoint `async def`. Un worker puede ser síncrono: el proceso es asíncrono respecto al cliente, aunque el worker ejecute cada tarea secuencialmente.

## ADR-004: PostgreSQL y persistencia relacional

- **Estado:** Propuesta del diseño; confirmar con docente/cliente. **Parcialmente reemplazada por ADR-018: se mantiene PostgreSQL, ahora gestionado por Supabase; SQLAlchemy/Psycopg ya no se usan.**
- **Decisión:** Usar PostgreSQL con SQLAlchemy y driver Psycopg síncrono.
- **Contexto:** El modelo contiene relaciones y restricciones transaccionales entre pedidos, exportaciones, pagos, inventario y trazabilidad; la implementación previa ya usaba SQLAlchemy/Psycopg.
- **Consecuencias:** Claves foráneas, restricciones únicas y transacciones protegen integridad. JSONB queda reservado para metadatos variables de auditoría/trabajos, no para entidades de negocio normalizadas. La plataforma de alojamiento y el servicio administrado no están seleccionados.

## ADR-005: Cliente Flutter

- **Estado:** Requisito del backlog; adoptar como decisión del producto.
- **Decisión:** Mantener un cliente Flutter para Android, iOS y Web que consuma el API REST.
- **Contexto:** El backlog pide pantallas en Flutter y pruebas multiplataforma para Android/iOS/Web.
- **Consecuencias:** Las reglas de negocio y autorización permanecen en backend. La UI adapta navegación a permisos, y las pruebas deben cubrir capacidades reales por plataforma, no solo compilación.

## ADR-006: Límites de módulo y propiedad de datos

- **Estado:** Diseño adoptado.
- **Decisión:** Cada módulo es dueño de sus reglas, servicios y tablas. Otros módulos solicitan cambios mediante servicios internos/operaciones de dominio y no escriben directamente sus tablas.
- **Contexto:** El monolito comparte proceso y base de datos; el aislamiento debe ser lógico para que la complejidad no crezca de forma transversal.
- **Consecuencias:** Se mantienen transacciones locales para flujos que requieren consistencia inmediata; las integraciones largas pasan por trabajos. Las tablas y migraciones se pueden desplegar en una sola base mientras conserve una autoridad de escritura.

## ADR-007: Control de acceso basado en roles y permisos

- **Estado:** Requisito del backlog; detalles de matriz pendientes. **Actualizada por ADR-019: los permisos se aplican en la base (RLS) además de en la interfaz.**
- **Decisión:** Un usuario tiene un rol asignado; los roles agrupan permisos por módulo y acción. Los permisos se verifican en cada endpoint protegido.
- **Contexto:** La historia de usuarios habla de asignar un rol y crear/editar roles con permisos por módulo.
- **Consecuencias:** Se evita confiar en ocultamiento de botones del cliente. La asignación de varios roles a un usuario no se incluye hasta que se solicite.

## ADR-008: Inventario como libro de movimientos

- **Estado:** Diseño adoptado para el modelo inicial; validar reglas de negocio.
- **Decisión:** Registrar entradas, salidas y ajustes como movimientos inmutables; calcular disponibilidad sumando movimientos por lote. Confirmar pedidos/exportaciones genera movimientos en la misma transacción de negocio definida.
- **Contexto:** El backlog exige inventario por producto/lote y actualización automática al confirmar pedido o exportación.
- **Consecuencias:** Historial auditable y ausencia de un saldo duplicado como dato autoritativo. Consultas agregadas pueden necesitar índices o caché medido más adelante. Reservas, reversos, unidades y prevención de stock negativo requieren definición.

## ADR-009: Integraciones externas tras adaptadores

- **Estado:** Diseño adoptado; proveedores pendientes.
- **Decisión:** Aislar almacenamiento de archivos, correo, push, mapas y tasas de cambio mediante interfaces/adaptadores.
- **Contexto:** El backlog requiere todas estas capacidades, pero no escoge proveedor.
- **Consecuencias:** Las entidades guardan identificadores y metadatos del proveedor, no dependen de su SDK. Secretos y URLs de servicios se configuran fuera del código. Selección, costos, privacidad, SLA y comportamiento ante fallos deben aprobarse antes de integrar.

## ADR-010: Outbox durable para trabajo asíncrono

- **Estado:** Propuesta; elegir tecnología de ejecución pendiente. **En revisión por ADR-018: sin worker propio; el trabajo asíncrono se resolverá con Edge Functions o tareas programadas de la base.**
- **Decisión:** Persistir en la misma transacción el trabajo solicitado y un mensaje outbox, y procesar el mensaje por worker con reintentos limitados e idempotencia.
- **Contexto:** Evita confirmar la operación de negocio y perder la tarea de generación/aviso si el proceso cae entre ambos pasos.
- **Consecuencias:** Entrega al menos una vez; cada manejador debe tolerar duplicados. Una tabla outbox permite empezar sin broker; volumen/operación pueden justificar un broker posterior. Los trabajos y mensajes requieren retención y limpieza acordadas.

## ADR-011: Archivos fuera de la base de datos

- **Estado:** Diseño adoptado; proveedor pendiente.
- **Decisión:** Guardar binarios en almacenamiento de objetos/archivos; conservar en PostgreSQL su clave, nombre, MIME, tamaño, hash, autor y fechas.
- **Contexto:** Se adjuntan certificados y se generan PDFs y fotos de perfil.
- **Consecuencias:** La descarga pasa por autorización y URL temporal o streaming. La base de datos no crece con binarios; respaldo y cifrado deben cubrir tanto metadatos como objetos.

## ADR-012: Claves, tiempo y precisión

- **Estado:** Convención propuesta en contrato/modelo; confirmar al implementar.
- **Decisión:** Usar claves sustitutas `BIGINT` internamente/externamente en v1, horas `TIMESTAMPTZ` normalizadas a UTC, país ISO alpha-2, moneda ISO 4217 y `NUMERIC` para importes, tasas y cantidades.
- **Contexto:** El sistema relaciona muchos recursos y registra operaciones comerciales, pagos y eventos internacionales.
- **Consecuencias:** El API y la base deben acordar precisión/redondeo decimal; mostrar fechas/monedas depende de configuración de usuario, pero se almacenan normalizadas. No se serializan importes como punto flotante.

## ADR-013: Trazabilidad documental y arancelaria

- **Estado:** Diseño adoptado; validez normativa pendiente de revisión externa.
- **Decisión:** Guardar en cada línea de exportación el código HS aplicado como instantánea, además de conservar el código vigente del producto. Mantener el PDF generado como archivo inmutable con referencia a la exportación y hash.
- **Contexto:** La clasificación puede cambiar y un documento emitido debe reproducir lo que se usó en ese momento.
- **Consecuencias:** Una exportación histórica no cambia cuando se edita el catálogo. La clasificación propuesta y los documentos requieren revisión humana y fuentes normativas versionadas; el sistema no sustituye asesoría aduanera/legal.

## ADR-014: Gestión de estado Flutter

- **Estado:** Adoptado para la estructura inicial del cliente.
- **Decisión:** Usar `provider` con `ChangeNotifier` para estado compartido de aplicación y estado de cada feature; mantener estado efímero de presentación dentro de widgets con `setState`.
- **Contexto:** El cliente se organiza por features y comparte sesión, permisos y preferencias entre varias pantallas. Se busca una solución pequeña y compatible con las recomendaciones introductorias de Flutter.
- **Consecuencias:** Providers se crean en el límite de la app o feature y liberan sus recursos al salir de alcance. Los widgets observan solo el estado que necesitan. No se centraliza toda la lógica de negocio en un único notifier; se reconsiderará la solución si el crecimiento del cliente lo requiere.

## ADR-015: Cliente HTTP Flutter

- **Estado:** Adoptado para la estructura inicial del cliente. **Actualizada por ADR-018: `ApiClient` se conserva, pero ahora sobre `SupabaseBackendClient`/`LocalBackendClient` en lugar de un servidor externo.**
- **Decisión:** Usar `package:http` detrás de un `ApiClient` inyectable por Provider, con URL base configurable por `API_BASE_URL`, timeout, identificador de solicitud, token opcional y excepciones tipadas que interpretan el contrato de error de la API.
- **Contexto:** El cliente móvil y web necesita compartir transporte, trazabilidad y presentación segura de errores sin acoplar widgets a detalles HTTP.
- **Consecuencias:** Los servicios de cada feature consumen `ApiClient`; no deben usar el transporte directamente. La autenticación puede conectar un proveedor de token cuando se implemente sesión. El cliente no muestra cuerpos crudos de errores ni administra todavía la persistencia de credenciales.

## ADR-016: Navegación Flutter

- **Estado:** Adoptado para el esqueleto inicial del cliente.
- **Decisión:** Usar `go_router` con rutas declarativas centralizadas bajo `lib/app/router/`, ubicaciones URL y manejo explícito de rutas no encontradas.
- **Contexto:** El cliente se desplegará en web y móvil, necesita enlaces directos y debe mantener la URL del navegador sincronizada con la pantalla actual.
- **Consecuencias:** Las features añaden sus rutas al router de aplicación cuando se implementen; autenticación podrá agregar redirecciones cuando exista estado de sesión. Se usa `go_router` 16.3.0 por compatibilidad con Dart 3.10.4.

## ADR-017: Emisión y validación de JWT

- **Estado:** Adoptado para el servicio inicial; duración y ciclo de vida pendientes de aprobación. **Reemplazada por ADR-021: la emisión y validación de JWT las hace Supabase Auth.**
- **Decisión:** Firmar tokens de acceso con HS256 y un secreto configurable por entorno de al menos 32 bytes. Incluir `sub`, `iat`, `exp`, `iss`, `jti` y `token_use=access`; validar algoritmo, firma, emisor, expiración y claims requeridos. No incluir roles ni permisos en el token.
- **Contexto:** El contrato requiere tokens Bearer que identifiquen al usuario y consulta permisos vigentes en backend. El backlog aún no define duración, refresh ni revocación.
- **Consecuencias:** `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` usa provisionalmente 30 minutos, configurable por entorno. Sin secreto o con secreto débil se bloquea la emisión. Refresh tokens y revocación requieren diseño posterior; la rotación de permisos no depende del contenido de un token antiguo.

## ADR-018: Backend dentro de la app Flutter sobre Supabase

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación del docente/cliente.
- **Decisión:** Eliminar el servidor FastAPI. La app Flutter incluye una capa de backend (`lib/backend`) que expone el contrato de rutas `/auth`, `/me`, `/users` y `/roles` y lo traduce a Supabase (Auth + PostgREST + PostgreSQL). Un cliente en memoria (`LocalBackendClient`) con el mismo contrato se usa en pruebas o sin credenciales.
- **Contexto:** El equipo decidió no mantener ni desplegar un servidor propio. El cliente Flutter ya consumía un contrato de rutas desacoplado mediante `ApiClient`, lo que permitió cambiar el backend sin tocar las pantallas.
- **Consecuencias:** Menos infraestructura que operar y un solo repositorio para app y esquema. A cambio, la seguridad depende de RLS y de la base, la app depende de Supabase (RNF-19) y las tareas en segundo plano necesitan otra solución (ADR-003 y ADR-010 en revisión). Reemplaza ADR-001 y ADR-002 y modifica ADR-004, ADR-015 y ADR-017.

## ADR-019: Dónde vive la lógica de negocio

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** Las reglas de **integridad y permisos** viven en PostgreSQL (RLS, triggers, funciones); la **validación de entrada y la traducción de errores** viven en `lib/backend`; la **presentación y el flujo** viven en `lib/features`. Ninguna regla de seguridad se implementa solo en la interfaz.
- **Contexto:** El cliente Flutter no es de confianza: cualquiera con la clave pública puede llamar a la API de Supabase sin pasar por la app. Un servidor intermedio ya no existe para aplicar reglas.
- **Consecuencias:** Toda tabla nueva debe nacer con RLS y sus reglas en `database/migrations/`. Las pantallas pueden ocultar opciones por permiso, pero solo como comodidad. Las reglas en SQL exigen pruebas contra la base real. Actualiza ADR-007.

## ADR-020: Operaciones privilegiadas fuera de la app

- **Estado:** Adoptado el 2026-10-08.
- **Decisión:** La app solo incluye la clave pública (anon/publishable) de Supabase. La clave `service_role` y la cadena de conexión a la base no se incluyen en la app ni en el repositorio. Las operaciones que requieran privilegios totales (por ejemplo, cambiar el correo de otro usuario) se harán con Edge Functions que verifican el permiso del llamador.
- **Contexto:** `service_role` omite RLS; en una app cliente equivale a entregar la base completa. El administrador no cambia hoy el correo de otros usuarios; solo el titular lo hace desde su perfil.
- **Consecuencias:** Algunas funciones administrativas quedan pendientes hasta existir una Edge Function. Los secretos viven en `.env` (no versionado) (RNF-18); no hay plantilla en el repositorio.

## ADR-021: Sesión y JWT delegados a Supabase Auth

- **Estado:** Adoptado el 2026-10-08; duración de sesión y refresh pendientes de aprobación.
- **Decisión:** Supabase Auth gestiona credenciales (bcrypt), confirmación de correo, emisión y expiración del JWT. La app guarda solo el token de acceso en almacenamiento seguro y valida su expiración local. Todo registro público crea la cuenta con el rol de menor privilegio (`cliente`), asignado por un trigger de la base.
- **Contexto:** Reemplaza el JWT HS256 propio de ADR-017 y evita mantener un servicio de autenticación.
- **Consecuencias:** La vigencia del token es la configurada en Supabase. El refresh y la revocación quedan pendientes. El cambio de correo exige confirmar un enlace enviado al correo nuevo y un trigger copia el correo confirmado al perfil.

## ADR-022: Modelo de autorización por RLS

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación. Hallazgos H1 y H2 abiertos (ver `modelo-autorizacion-rls.md`).
- **Decisión:** Denegar por defecto con RLS activa en toda tabla de `public`; los permisos son datos (`permission`, `role_permission`) con códigos `modulo.accion`; las políticas consultan `has_permission(código)`, que exige cuenta activa, rol activo y permiso asignado. Las operaciones atómicas de varios pasos son funciones `SECURITY DEFINER` con `search_path` fijo. Las reglas de integridad que no dependen de quién llama son triggers. El rol `anon` no tiene acceso a ninguna tabla.
- **Contexto:** Sin servidor intermedio, la base es la única barrera real (ADR-019). La clave pública de Supabase está en la app y es conocida.
- **Consecuencias:** Cada tabla nueva debe cumplir la lista de verificación de `modelo-autorizacion-rls.md`. Los permisos se gestionan sin redesplegar la app. Quedan por corregir la separación entre `users.update` y `users.deactivate`, la asignación de rol por quien edita usuarios y los privilegios por defecto de Supabase (`TRUNCATE`, `REFERENCES`, `TRIGGER`). Actualiza ADR-007.

## ADR-023: Convención de acceso a datos desde la app

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** Las pantallas no acceden a la red: reciben funciones inyectadas construidas sobre `ApiClient`, que usa un cliente de backend intercambiable (`SupabaseBackendClient` o `LocalBackendClient`) con el mismo contrato de rutas y de errores. Las columnas se piden explícitas, las relaciones se incrustan, las escrituras de varios pasos son funciones de la base y no hay borrado desde la app (baja lógica). Los errores siguen un formato único (`error.code`, `message`, `details`, `request_id`).
- **Contexto:** Mantiene las pantallas independientes de la plataforma de datos (se cambió de un servidor FastAPI a Supabase sin tocarlas) y permite probarlas sin red.
- **Consecuencias:** Cada módulo nuevo implementa su ruta en ambos clientes y la documenta en `convencion-acceso-datos.md`. Actualiza ADR-015.

## ADR-024: Esquema versionado con migraciones de la CLI de Supabase

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** Todo cambio de la base (tablas, reglas, RLS, buckets) es una migración numerada en `database/migrations/`, gestionada con la CLI de Supabase (`npx supabase@latest`). Una migración aplicada no se edita. `database/migrations/` es una instantánea generada de las migraciones y no se edita a mano. Un entorno local con Docker (`supabase start`) se recrea desde las migraciones.
- **Contexto:** Sin servidor propio ni Alembic, la base necesita un historial reproducible de cambios y un entorno donde probar reglas y RLS sin tocar el proyecto alojado.
- **Consecuencias:** Las migraciones ya aplicadas con `psql` deben marcarse como aplicadas al enlazar la CLI (`migration repair`). Cada cambio exige escribir una migración, aplicarla y regenerar `schema.sql`. El entorno local requiere Docker. Sustituye a la gestión de migraciones con Alembic.

## ADR-025: Almacenamiento de archivos en Supabase Storage con buckets privados

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** Los archivos se guardan en Supabase Storage en buckets **privados** (acceso por URL firmada), con límite de tamaño y de tipos MIME por bucket y políticas RLS sobre `storage.objects`. Convención de rutas: `<auth.uid()>/<archivo>` en `profile-photos`. El bucket `export-documents` se crea sin políticas (nadie accede) hasta que el módulo de documentos defina sus permisos.
- **Contexto:** Concreta ADR-011 (archivos fuera de la base) y ADR-009 (almacenamiento tras un adaptador) en la plataforma elegida.
- **Consecuencias:** Los metadatos (`stored_file`) se crean con el módulo de documentos. Los permisos de documentos (`documents.read`, `documents.upload`, …) y sus políticas son una migración futura. La subida desde la app se hará con el cliente de Storage usando el JWT del usuario; no se usa nunca `service_role`.

## ADR-026: Permiso propio para asignar roles y autoedición del perfil

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** La asignación de roles tiene un permiso propio, `users.assign_role`, separado de `users.update` y `users.deactivate`. La RLS decide qué **filas** puede actualizar cada usuario (la suya, o cualquiera si tiene un permiso de gestión) y el trigger `profile_guard` decide qué **campos**: nombres y teléfono, el titular o `users.update`; el rol, solo `users.assign_role` y nunca sobre sí mismo; el estado, solo `users.deactivate` y nunca sobre sí mismo. El correo no se edita por UPDATE: lo copia un trigger desde Supabase Auth.
- **Contexto:** Los privilegios por columna de PostgreSQL no distinguen entre permisos de negocio, así que la separación por campo debe ir en un trigger. Sin ella, un rol con `users.update` podía asignarse el rol administrador (hallazgo H2) y nadie podía editar su propio perfil (H5).
- **Consecuencias:** Los roles de gestión necesitan también `users.read` para ver las filas que van a editar. Cualquier campo nuevo editable de `profile` debe añadirse a las reglas de `profile_guard`. Actualiza ADR-022.

## ADR-027: Bloqueo de usuarios desactivados en la base y en Supabase Auth

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** El bloqueo de una cuenta desactivada se aplica en tres niveles que no dependen del código de la app: (1) toda política RLS exige un permiso o `is_active_user()`; (2) un trigger veta la cuenta en Supabase Auth (`banned_until`) y revoca sus sesiones al desactivarla, y quita el veto al reactivarla; (3) la app, al recibir que su perfil ya no es visible, cierra la sesión. El cierre de sesión de la app también revoca la sesión en Supabase Auth (al mejor esfuerzo).
- **Contexto:** Antes solo la app comprobaba `is_active` al iniciar sesión; quien llamara a Supabase directamente con la clave pública o conservara un token seguía operando (hallazgo H6).
- **Consecuencias:** Un token ya emitido sigue siendo válido hasta vencer, aunque las políticas no le conceden nada. Cada política nueva debe usar `is_active_user()` o `has_permission()`; `verify_schema.sql` falla si una no lo hace. Actualiza ADR-021 y ADR-022.

## ADR-028: Aislamiento del cliente externo por vínculo y vista de usuarios de administración

- **Estado:** Propuesto el 2026-10-08 (aislamiento: borrador sin aplicar, pendiente de decisión del cliente); la vista de usuarios está **adoptada y aplicada**.
- **Decisión:** (1) El cliente externo accede a sus datos por el permiso `portal.read` **y** un vínculo explícito usuario↔cliente (`customer_user`), solo en lectura y a lo largo de la cadena cliente → pedido → exportación → envío; las políticas son aditivas a las del personal interno. (2) Los listados de administración usan la vista `admin_user_list` con `security_invoker`, de modo que la vista nunca amplía lo que permiten las políticas de `profile`.
- **Contexto:** Las políticas por permiso no distinguen entre registros de distintos clientes; sin un vínculo, "cliente" equivale a "ve todo o no ve nada". La pantalla de usuarios necesitaba el nombre del rol sin una segunda consulta.
- **Consecuencias:** Hay que confirmar el supuesto N:M y qué ve el cliente (no pagos ni inventario). La descarga de documentos exige una política de Storage aparte. Toda vista nueva debe ser `security_invoker` y tener solo `SELECT` para `authenticated` (lo comprueba `verify_schema.sql`). Actualiza ADR-022.

## ADR-029: Política de cambio de rol y auditoría append-only

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación.
- **Decisión:** (1) Asignar o quitar el rol `administrador` solo lo puede hacer un administrador, además de las reglas ya vigentes (permiso `users.assign_role`, nunca el propio rol, rol destino activo, siempre un administrador activo). (2) Los cambios de rol se registran en `audit_log`: tabla append-only, legible solo con `audit.read`, escrita únicamente por triggers `SECURITY DEFINER`, inmutable incluso para el propietario y sin datos personales. No se exige que el rol destino tenga menos permisos que el actor.
- **Contexto:** `users.assign_role` por sí solo permitía promover a cualquiera a administrador (escalada de privilegios). El requisito RNF-12 pide dejar rastro de los cambios sensibles de usuarios y permisos, sin secretos.
- **Consecuencias:** Un rol de gestión sin ser administrador no puede tocar el rol administrador. Todo cambio de rol deja un registro con actor, destino y roles origen y destino. La auditoría de otros eventos (desactivación, permisos de roles) y su pantalla de consulta quedan pendientes. Actualiza ADR-026 y concreta RNF-12.

## ADR-030: Productos: lectura por RLS y escritura por funciones atómicas, sin borrado

- **Estado:** Adoptado el 2026-10-08; pendiente de aprobación (supuestos de la sección 14 de `modelo-autorizacion-rls.md`).
- **Decisión:** Las tablas del catálogo de productos se leen con RLS (`products.read`) y se escriben **solo** con funciones `SECURITY DEFINER` (`create_product`, `update_product`, `set_product_active`, `set_product_certifications`) que comprueban el permiso, validan y guardan producto, detalle y certificaciones de forma atómica. Las reglas de integridad (tipo y unidad inmutables, detalle obligatorio, unicidad, rangos, formato HS) están en la base. Los productos no se borran: se inactivan.
- **Contexto:** PostgREST no permite una transacción de varias tablas desde el cliente, y un producto sin su detalle sería un dato corrupto. El historial (pedidos, inventario) debe poder referirse siempre al producto.
- **Consecuencias:** Cada módulo con datos de varias tablas sigue este patrón (como `set_role_permissions`). Las claves foráneas de las tablas futuras hacia `product` deben ser `ON DELETE RESTRICT`. La app depende de los mensajes de error de las funciones (se mapean a 422, 409, 403 y 404). Concreta ADR-019 y ADR-023.

## ADR-031: Recuperación de acceso con código de un solo uso por correo

- **Estado:** Adoptado el 2026-10-08; la plantilla del correo está en `supabase/templates/recovery.html` y **no se ha empujado** al proyecto alojado.
- **Decisión:** El usuario pide un código de 6 dígitos (`POST /auth/password-reset-requests`, respuesta siempre neutra) y lo canjea junto con su correo y la contraseña nueva (`POST /auth/password-resets`): la app verifica el código en Supabase Auth, cambia la contraseña con esa sesión temporal y la cierra. No se usan enlaces ni *deep links*.
- **Contexto:** Un enlace en el correo exige configurar esquemas de URL nativos en Android e iOS y manejar el fragmento del token en web; un código se escribe en la propia app y funciona igual en las tres plataformas.
- **Consecuencias:** El envío depende del límite de correos de Supabase (hay que configurar un SMTP propio antes de producción). El código vence en 1 hora (`otp_expiry`) y sirve una sola vez. En el backend local el código se devuelve en `dev_code` (solo desarrollo y pruebas). Cumple RF-05. Concreta ADR-021.

## Decisiones pendientes prioritarias

1. Aprobar Supabase como plataforma (plan, región, respaldos) y el manejo de secretos (ADR-018, ADR-020).
2. Decidir cómo se resuelven las tareas en segundo plano sin worker propio (Edge Functions o tareas programadas de la base) y sus reglas de reintento.
3. Elegir proveedor de archivos, mapas, correo, push y tasas FX.
4. Aprobar matriz de roles y permisos.
5. Definir flujos de pedidos, exportaciones, pagos, inventario y envíos; especialmente reserva/reverso de stock.
6. Confirmar moneda base, reglas decimales, EORI, lotes y posibilidad de pedidos multi-producto.
7. Aprobar las metas operativas propuestas en RNF y sus perfiles de prueba.
