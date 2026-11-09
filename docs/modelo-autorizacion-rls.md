# Modelo de autorización por RLS

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.8 (módulo de productos)  
**Estado:** Descripción de lo aplicado en Supabase el 2026-10-08, contrastada con las políticas reales de la base (`pg_policies`). Pendiente de aprobación docente/cliente.  
**Relacionado:** ADR-007, ADR-019, ADR-020 y ADR-022 (`decisiones-arquitectura.md`); RF-04, RNF-03 y RNF-18 (`requerimientos.md`); `database/migrations/`.

## 1. Principios

1. **Denegar por defecto.** Toda tabla de `public` tiene RLS activa; lo que no concede una política queda prohibido. El rol `anon` (cualquiera con la clave pública) no tiene acceso a ninguna tabla.
2. **Los permisos son datos.** Se definen como códigos `modulo.accion` en la tabla `permission` y se asignan a roles mediante `role_permission`; no están escritos en el código de la app.
3. **La base decide, la interfaz solo informa.** La app oculta opciones según permisos por comodidad, pero la autorización real ocurre en PostgreSQL aunque alguien llame a la API sin pasar por la app.
4. **Mínimo privilegio.** Todo registro público nace con el rol `cliente`, que no tiene permisos de gestión. Las operaciones con privilegios totales no existen en la app (ADR-020).

## 2. Cadena de identidad

```
JWT de Supabase Auth  ->  auth.uid()  ->  profile.auth_user_id  ->  profile.role_id
                                                                        |
                              permission.code  <-  role_permission  <-  role
```

Tres funciones `SECURITY DEFINER` resuelven la cadena (todas con `search_path` fijo, sin acceso para `anon`): `public.current_user_role()` devuelve el **nombre del rol** del usuario actual, o `null` si no hay sesión, la cuenta está desactivada o su rol está inactivo; y las dos siguientes: `public.is_active_user()` (la cuenta está activa y su rol también; la usan las políticas de lectura y de autoedición) y `public.has_permission(p_code)` (lo anterior **y** que el rol tenga el permiso). Esta última resuelve esa cadena y devuelve verdadero solo si **la cuenta está activa, su rol está activo y el rol tiene el permiso**. Se ejecuta como `SECURITY DEFINER` con `search_path = public` para poder leer `profile` y `role_permission` sin que las propias políticas se bloqueen entre sí.

## 3. Catálogo de permisos y roles

| Permiso | Significado |
|---|---|
| `roles.read` / `roles.create` / `roles.update` / `roles.deactivate` | Consultar, crear, editar y desactivar roles |
| `roles.permissions.update` | Asignar permisos a un rol |
| `users.read` / `users.create` / `users.update` / `users.deactivate` | Consultar, registrar, editar y desactivar usuarios |
| `users.assign_role` | Asignar o cambiar el rol de un usuario (ver sección 13.1) |
| `audit.read` | Consultar el registro de auditoría (ver sección 13.2) |
| `products.read` / `products.create` / `products.update` | Consultar, registrar y editar productos del catálogo (ver sección 14; no se asignan a ningún rol por defecto) |

| Rol inicial | Permisos al crearse |
|---|---|
| `administrador` | Los 11. No se puede renombrar, desactivar ni quitarle `roles.read`, `roles.create`, `roles.update` y `roles.permissions.update`. |
| `usuario_comercial`, `encargado_logistico`, `cliente` | Ninguno. Se asignan desde la pantalla de roles. |

Las convenciones para permisos nuevos: `modulo.accion` en minúsculas, un permiso por operación de negocio, nunca un permiso "todo".

## 4. Matriz de políticas (verificada en la base)

Rol de base de datos que aplica: `authenticated` (usuario con sesión). `anon` no tiene políticas ni privilegios. **Toda política exige un permiso o una cuenta activa** (`is_active_user()`): una cuenta desactivada no lee, edita ni sube nada aunque conserve un token. Lo comprueba `verify_schema.sql`.

| Tabla | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profile` | Su propia fila (con la cuenta activa), o cualquiera con `users.read` | Nadie desde la API (lo hace el trigger de registro) | **Su propia fila** (autoedición), o cualquier fila con `users.update`, `users.deactivate` o `users.assign_role`; columnas `first_name`, `last_name`, `phone`, `role_id`, `is_active` (el correo no se edita por UPDATE: lo copia el trigger desde Supabase Auth). Qué campo puede cambiar cada uno lo decide el trigger `profile_guard` (tabla siguiente). | Nadie |
| `audit_log` | Con `audit.read` | Nadie desde la API (solo triggers) | Nadie (ni el propietario) | Nadie (ni el propietario) |
| `role` | Cualquier usuario con cuenta activa | Con `roles.create` | Con `roles.update` o `roles.deactivate` | Nadie |
| `permission` | Cualquier usuario con cuenta activa | Nadie | Nadie | Nadie |
| `role_permission` | Cualquier usuario con cuenta activa | Solo vía función `set_role_permissions` | Solo vía función | Solo vía función |

**Reglas por campo de `profile` (trigger `profile_guard`, con sesión de usuario):**

| Campo | Quién puede cambiarlo |
|---|---|
| `first_name`, `last_name`, `phone` | El titular (su propia fila) o quien tenga `users.update` |
| `role_id` | Solo quien tenga `users.assign_role`, **nunca sobre sí mismo** y, si el rol origen o destino es `administrador`, solo un administrador (sección 13.1) |
| `is_active` | Solo quien tenga `users.deactivate`, y nunca sobre sí mismo |
| `email`, `auth_user_id`, `id` | Nadie por UPDATE (sin privilegio de columna) |

Como la política SELECT también filtra las filas que un UPDATE puede ver, un rol de gestión necesita `users.read` además del permiso de edición.

La función `set_role_permissions(role_id, codes[])` exige `roles.permissions.update`, valida que los códigos existan y no se repitan, protege los permisos mínimos del administrador y reemplaza el conjunto de forma atómica.

## 5. Reglas de negocio aplicadas en la base (triggers)

| Regla | Dónde | Efecto |
|---|---|---|
| Toda cuenta nueva recibe el rol `cliente` | Trigger `on_auth_user_created` | Ignora cualquier rol pedido en el registro |
| Desactivar veta la cuenta en Auth y revoca sus sesiones; reactivar quita el veto | Trigger `profile_sync_auth_access` | `auth.users.banned_until` impide iniciar sesión y renovar tokens aunque se llame a Supabase Auth directamente |
| El correo confirmado se copia al perfil | Trigger `on_auth_user_email_changed` | Mantiene `profile.email` al día |
| No desactivarse a sí mismo | `profile_guard` | Error de la base, mostrado al usuario como conflicto |
| Siempre queda un administrador activo | `profile_guard` | Impide desactivar o cambiar de rol al último |
| El rol destino debe estar activo | `profile_guard` | Evita asignar roles inactivos |
| El rol `administrador` es intocable; un rol con usuarios activos no se desactiva | `role_guard` | Evita dejar el sistema sin gestión |

## 6. Qué puede hacer cada actor (verificado por inspección)

| Actor | Puede | No puede |
|---|---|---|
| Anónimo con la clave pública | Registrarse y llamar a los endpoints de autenticación de Supabase | Leer o escribir cualquier tabla (verificado: responde `42501`) |
| `cliente` (sin permisos) | Leer su propio perfil, editar sus nombres y teléfono, y leer la lista de roles y permisos | Ver otros perfiles; cambiar su rol, su estado o su correo por UPDATE |
| Rol con `users.read` | Ver todos los perfiles | Editarlos (necesita además `users.update`, `users.deactivate` o `users.assign_role`) |
| `administrador` | Gestionar usuarios, roles y permisos | Desactivarse a sí mismo o quedar sin administrador |

## 7. Nivel de verificación

Dos scripts del repositorio de la app, ejecutados el 2026-10-08 contra el proyecto alojado:

- `database/tests/verify_schema.sql` (solo lectura): **54 de 54 comprobaciones correctas**: tablas, restricciones, datos semilla, RLS y políticas, funciones y triggers, privilegios y buckets.
- `database/tests/rules.sql` (transacción que se revierte): **84 de 84 pruebas correctas** (`rules.sql`; el módulo de productos tiene las suyas en la sección 14) con sesiones simuladas de cliente, administrador, roles parciales (`users.update`, `users.deactivate`, `users.assign_role`) y anónimo. Cubre el aislamiento entre usuarios, las reglas de `profile_guard` y `role_guard` (no autodesactivarse, siempre un administrador activo, rol inactivo, rol administrador intocable), `set_role_permissions` (atomicidad, duplicados, inexistentes, permisos mínimos del administrador), los rechazos de RLS, el acceso anónimo y **el bloqueo de usuarios desactivados** (cuenta y administrador desactivados, veto y sesiones en Auth, reactivación). No quedó ningún dato tras la prueba.

**Sigue sin probarse:** el flujo con sesiones reales emitidas por Supabase Auth (las pruebas simulan el JWT), las políticas de Storage con la API de Storage y el comportamiento bajo carga o concurrencia.

Para repetirlas: `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/<archivo>.sql`. Procedimiento manual para probar una política como un usuario concreto:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"<auth_user_id>","role":"authenticated"}', true);
-- operación a probar, por ejemplo: select * from profile;
rollback;
```

## 8. Hallazgos

| # | Hallazgo | Estado |
|---|---|---|
| H1 | Supabase otorga por defecto a `authenticated` `TRUNCATE`, `REFERENCES` y `TRIGGER` (y escritura en `permission` y `role_permission`). | **Resuelto** (migración `20261008000200`): privilegios revocados y valores por defecto de `public` ajustados. Lo comprueba `verify_schema.sql`. |
| H2 | Un rol con solo `users.deactivate` podía editar nombre y rol, y quien editaba usuarios podía asignarse el rol `administrador`. | **Resuelto**: permiso nuevo `users.assign_role`, y reglas por campo en `profile_guard`; nadie cambia su propio rol. 9 pruebas de `rules.sql` lo cubren. |
| H3 | `role` y `permission` son legibles por cualquier usuario con sesión. | Aceptado (la app los necesita para mostrar el perfil); revisar si se vuelven sensibles. |
| H4 | El registro público está abierto a cualquiera con la clave pública. | **Abierto.** Depender de los límites de Supabase Auth, mantener la confirmación de correo y valorar CAPTCHA (RNF-18, tarea de límites de intento). |
| H5 | Ningún usuario podía editar su propio perfil (RF-06). | **Resuelto**: política `profile_update_self` limitada por `profile_guard` a nombres y teléfono. |

| H6 | Una cuenta desactivada con un token válido seguía leyendo catálogos, editando su perfil y usando Storage, y podía iniciar sesión llamando a Supabase Auth directamente: el bloqueo estaba solo en el código de la app, y desactivar no revocaba las sesiones. Detectado el 2026-10-08. | **Resuelto** (migración `20261008000300`): `is_active_user()` en todas las políticas, veto en Auth (`banned_until`) y sesiones revocadas al desactivar. |

**Límite que sigue vigente:** el token de acceso ya emitido sigue siendo válido hasta vencer (por defecto, 1 hora); las políticas dejan de concederle datos de inmediato, pero un servicio que solo validara la firma del token lo seguiría aceptando.

**Efectos colaterales a tener en cuenta:** el correo ya no se puede cambiar por UPDATE directo (solo por Supabase Auth con confirmación); y el permiso `users.assign_role` se concede al rol `administrador` pero no a otros roles, que lo recibirán desde la pantalla de roles.

## 9. Cómo añadir una tabla nueva (lista de verificación)

1. Crearla en `database/migrations/` y activar `enable row level security` en la misma sentencia de cambios.
2. Definir una política por operación permitida, usando `has_permission('modulo.accion')`; si una operación no se debe permitir, no crear su política.
3. Revocar a `anon` todo y a `authenticated` lo que sobre (`TRUNCATE`, `REFERENCES`, `TRIGGER`, y los privilegios de escritura que no se usen); conceder por columna cuando solo algunas sean editables.
4. Las operaciones de varios pasos que deban ser atómicas se implementan como función `SECURITY DEFINER` con `search_path` fijo y comprobación explícita del permiso.
5. Reglas de integridad que no dependan de quién llama, como triggers.
6. Probar con el procedimiento de la sección 7 al menos: usuario sin permiso (rechazo), usuario con permiso (éxito) y anónimo (rechazo).
7. Añadir el permiso nuevo a la sección 3 y al catálogo de `permission`.

## 10. Almacenamiento de archivos (storage.objects)

RLS activa en `storage.objects`; el rol `anon` no accede. Políticas aplicadas el 2026-10-08 (migración `20261008000100_storage_buckets`):

| Bucket | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profile-photos` | Su carpeta `<auth.uid()>/…`, o cualquiera con `users.read` | Solo su carpeta | Solo su carpeta | Solo su carpeta |
| `export-documents` | Nadie | Nadie | Nadie | Nadie (sin políticas, a propósito) |

Verificado con usuarios simulados en una transacción revertida: aislamiento entre usuarios, rechazo al subir a la carpeta de otro o a `export-documents`, y rechazo al anónimo. Detalle y salvedades en `infraestructura-supabase.md`, sección 4.

## 11. Políticas de los módulos de negocio (borrador, sin aplicar)

**Estado:** escritas y validadas, **no aplicadas**: las 14 tablas de estos módulos aún no existen en Supabase y el modelo de datos exige resolver varias decisiones de negocio antes de crearlas (`modelo-datos.md`, hallazgos). Las políticas viven en `database/drafts/domain_policies.sql` y se aplican **en la misma migración que crea cada tabla**. Se validaron con `database/tests/draft_policies.sql` sobre tablas de prueba con las columnas que usan (**54 de 54 pruebas correctas**, transacción revertida; la base no cambió).

Los permisos salen de `contrato-api.md`; **ninguno se concede a un rol al crearlo** (ni siquiera al administrador, que gestiona usuarios y roles, no operaciones de negocio): se asignan desde la pantalla de roles. Función nueva: `current_profile_id()` (id numérico del perfil activo del usuario actual).

| Módulo (tarea) | Tabla | Leer | Crear | Editar | Borrar |
|---|---|---|---|---|---|
| Comercial (462) | `customer` | `customers.read` | `customers.create` | `customers.update` | no |
| | `customer_order` | `orders.read` | `orders.create` | `orders.update` o `orders.transition` (el campo lo decide un trigger al crear la tabla) | no |
| | `order_line` | `orders.read` | `orders.create` o `orders.update` | `orders.update` | `orders.update` (las líneas se reemplazan al editar) |
| Exportaciones y documentos (463) | `export` | `exports.read` | `exports.create` | `exports.update` | no |
| | `export_line` | `exports.read` | `exports.create` o `exports.update` | `exports.update` | `exports.update` |
| | `export_document` | `documents.read` | `documents.upload` o `documents.generate`, firmado por quien lo crea | inmutable | no |
| | `stored_file` | el autor, o `documents.read` | solo a nombre propio | inmutable | no |
| Inventario y finanzas (464) | `inventory_movement` | `inventory.read` | `inventory.adjust`, firmado por quien lo registra | inmutable | no |
| | `payment_obligation` | `payments.read` | `payments.create` | inmutable | no |
| | `payment_transaction` | `payments.read` | `payments.create`, firmado por quien lo registra | inmutable | no |
| | `exchange_rate` | `payments.read` | solo el sistema | solo el sistema | no |
| Logística y notificaciones (465) | `shipment` | `logistics.read` | `logistics.create` | `logistics.update` | no |
| | `shipment_event` | `logistics.read` | `logistics.update` | inmutable | no |
| | `notification` | solo el destinatario | solo el sistema | el destinatario, **solo `read_at`** | no |

**Qué comprueban las 54 pruebas:** un rol de solo lectura ve todo y no escribe nada; un rol con todos los permisos escribe donde corresponde y no puede borrar, ni editar los libros inmutables, ni firmar a nombre de otro; un rol sin permisos no ve nada salvo sus notificaciones; una cuenta **desactivada con rol completo** no ve ni escribe; y el anónimo no accede.

**Decisiones abiertas que afectan a estas políticas:**
1. **Acceso del rol externo `cliente` a sus propios pedidos y envíos.** El modelo no relaciona un perfil con un cliente (`customer`), así que hoy no se puede limitar por propietario; las políticas son por permiso, no por propiedad. Requiere decisión del cliente y una columna nueva.
2. **Regla de inventario** (reserva al confirmar, descuento al exportar): define qué funciones del sistema escriben movimientos.
3. **Estados y transiciones** de pedidos y exportaciones: definen los triggers por campo que acompañan a estas políticas (ver el encabezado del borrador).
4. **Quién escribe tasas de cambio y notificaciones:** el borrador asume funciones del sistema (Edge Functions o `SECURITY DEFINER`); depende de ADR-003 y ADR-010 (trabajo en segundo plano).
5. **Reportes, panel y trabajos** (`reports.read`, `dashboard.read`, jobs) y `audit_log` no están cubiertos: no pertenecen a estas tareas.

## 12. Aislamiento del cliente externo y matriz por rol (propuesta validada, sin aplicar)

### 12.1 Aislamiento del cliente externo (PLAT-466)

**Estado:** borrador en `database/drafts/client_isolation.sql`, validado con `database/tests/client_isolation.sql` (**33 de 33 pruebas correctas**, tablas de prueba, transacción revertida). Se aplica después de `domain_policies.sql` y en la misma migración que crea las tablas de negocio.

**Regla:** un usuario con el permiso `portal.read` ve **solo** los registros de los clientes (`customer`) a los que está vinculado en la nueva tabla `customer_user` (N:M), y solo en lectura: su cliente → sus pedidos y líneas → sus exportaciones, líneas y documentos → sus envíos y eventos. La cadena la recorren funciones `SECURITY DEFINER` (`my_customer_ids()`, `my_order_ids()`, `my_export_ids()`, `my_shipment_ids()`) para que las políticas de cada tabla no dependan entre sí. Las políticas son aditivas: el personal interno con `orders.read` sigue viendo todo; el cliente no recibe ningún permiso interno.

**Qué comprueban las 33 pruebas:** el cliente A ve solo lo suyo y el B solo lo suyo; no ve pagos ni inventario; no escribe nada, no se vincula a otro cliente ni se desvincula; con `portal.read` pero sin vínculo no ve nada; vinculado pero sin `portal.read` no ve nada; una cuenta desactivada no ve nada; el personal interno conserva su visibilidad; y el anónimo no accede.

**Supuestos que el cliente debe confirmar:**
1. Un usuario externo puede estar vinculado a varios clientes y un cliente puede tener varios usuarios (si es 1:1, basta una columna en `customer`).
2. El cliente externo no ve pagos, inventario, lotes ni notas internas.
3. La descarga de los archivos de documentos exige además una política de Storage sobre `export-documents`, que hoy no tiene ninguna (nadie accede).
4. Quien vincula usuarios a clientes es el personal con `customers.update`, no el propio cliente.

### 12.2 Perfiles de permisos por rol

La migración `20261107000000_role_permission_baselines.sql` establece los siguientes perfiles mínimos. El administrador recibe **todos los permisos del catálogo**, incluidos los que se agreguen en el futuro; el trigger de la migración concede automáticamente cada permiso nuevo. El cambio no elimina los límites de las políticas RLS: el administrador solo accede a las filas y columnas permitidas por esas políticas. Al aplicarla, se reemplazan las asignaciones actuales de comercial, logística y cliente; hay que revisar cualquier personalización antes de aplicarla a una base con datos reales.

| Rol | Permisos asignados |
|---|---|
| `administrador` | Todos los permisos existentes y futuros, incluidos administración y operaciones |
| `usuario_comercial` | `customers.read/create/update`, `orders.read/create/update/transition`, `exports.read/create/update`, `documents.read/upload/generate`, `inventory.read`, `payments.read/create`, `logistics.read` |
| `encargado_logistico` | `customers.read`, `orders.read`, `exports.read`, `documents.read`, `inventory.read/adjust`, `logistics.read/create/update` |
| `cliente` (externo) | `portal.read` (aislado por vínculo con su cliente) |

### 12.3 Matriz de pruebas por rol (PLAT-467)

`database/tests/policies_by_role.sql` ejecuta, con un usuario por rol sembrado, **cada operación sobre cada tabla** (4 roles × 15 tablas × 4 operaciones = **240 celdas**) y la compara con lo esperado. Letras: **A** administrador, **C** comercial, **L** logístico, **K** cliente externo.

| Tabla | Leer | Crear | Editar | Borrar |
|---|---|---|---|---|
| `customer` | A C L K | — (RPC) | — (RPC) | — |
| `customer_order` | A C L K | A C | A C | — |
| `order_line` | A C L K | A C | A C | A C |
| `export` | A C L K | A C | A C | — |
| `export_line` | A C L K | A C | A C | A C |
| `export_document` | A C L K | A C | — (inmutable) | — |
| `stored_file` | A C L | A C L K (solo a nombre propio) | — | — |
| `inventory_movement` | A C L | A L | — (inmutable) | — |
| `payment_obligation` | A C | A C | — | — |
| `payment_transaction` | A C | A C | — (inmutable) | — |
| `exchange_rate` | A C | solo el sistema | solo el sistema | — |
| `shipment` | A C L K | A L | A L | — |
| `shipment_event` | A C L K | A L | — (inmutable) | — |
| `notification` | A C L K (solo las propias) | solo el sistema | A C L K (solo `read_at` propio) | — |
| `customer_user` | A C L K (K solo el suyo) | — (RPC) | — | — |

Lectura por el cliente (K): solo a través de su vínculo; no ve pagos, inventario, tasas ni metadatos de archivos ajenos. Los datos asociados a un cliente y las notificaciones conservan las restricciones de fila incluso para el administrador.

### 12.4 Vista de usuarios para administración (PLAT-469)

`public.admin_user_list` (migración `20261008000500`, aplicada; privilegios corregidos en `20261008000501`) une `profile` con el nombre del rol (`role_name`) y no expone `auth_user_id`. Es `security_invoker`: **no abre nada que las políticas no abran** (con `users.read` se ven todos; sin él, solo el propio perfil; una cuenta desactivada no ve nada; el anónimo no accede). Tres índices `pg_trgm` (nombre, apellido, correo) aceleran la búsqueda por texto. La app la usa para listar y buscar usuarios (PLAT-468). Verificado con `verify_schema.sql` y `rules.sql` (4 pruebas propias).

## 13. Política de cambio de rol y auditoría (PLAT-472, PLAT-473)

**Aplicado el 2026-10-08** (migración `20261008000600`). Verificado con `rules.sql` (**84 de 84**) y `verify_schema.sql` (**37 de 37**); la prueba revertida previa a aplicarlo también dio 84 de 84.

### 13.1 Política de cambio de rol

Cambiar el `role_id` de un usuario exige, **todas** estas condiciones (las aplica `profile_guard`, no la app):

| Regla | Mensaje al usuario |
|---|---|
| Tener el permiso `users.assign_role` | "No tienes permiso para asignar roles." |
| Nunca sobre uno mismo | "No puedes cambiar tu propio rol." |
| El rol destino debe estar activo | "El rol indicado no existe o está inactivo." |
| No dejar el sistema sin un administrador activo | "No se puede dejar el sistema sin un administrador activo." |
| **Nuevo:** asignar o quitar el rol `administrador` solo lo puede hacer un administrador | "Solo un administrador puede asignar o quitar el rol administrador." |

La regla nueva cierra una escalada que seguía abierta tras H2: un rol de gestión con `users.assign_role` (por ejemplo, un supervisor) podía promover a cualquiera a administrador. El administrador puede asignar roles porque recibe todos los permisos actuales del sistema; los perfiles de los roles asignados permanecen acotados por sus permisos y las políticas RLS.

### 13.2 Registro de auditoría

Tabla `public.audit_log` (modelo de datos: `audit_log`), **append-only** y con tres capas de protección:

1. **Privilegios:** `authenticated` solo tiene `SELECT`; sin políticas de escritura. Solo la escriben triggers `SECURITY DEFINER`.
2. **Lectura:** exige el permiso nuevo `audit.read`, que recibe el rol `administrador`.
3. **Inmutabilidad:** triggers que impiden `UPDATE`, `DELETE` y `TRUNCATE` **incluso al propietario**. Única excepción: el `ON DELETE SET NULL` del actor, para que borrar una cuenta no se rompa y el registro se conserve con actor nulo.

Cada cambio de rol (`user.role_changed`) guarda: quién lo hizo (`actor_user_id`, nulo si vino de un script SQL), a quién (`entity_id` = id del perfil), el rol origen y destino (ids y nombres) y la fecha. **No guarda datos personales** (correos ni nombres: lo comprueba una prueba) y los intentos rechazados no dejan registro.

**Pendiente (RNF-12):** auditar también desactivación y reactivación de usuarios, cambios de permisos de un rol y creación de roles, y una pantalla de consulta de la auditoría (hoy solo se lee con la API de Supabase o SQL).

## 14. Módulo de productos (PLAT-491 a PLAT-506)

**Aplicado el 2026-10-08** (migración `20261008000700`). Verificado con `database/tests/products.sql` (**97 de 97 pruebas correctas**, transacción revertida) y `verify_schema.sql` (**54 de 54**).

**Patrón:** los usuarios **leen** las tablas (RLS) y **escriben solo mediante funciones `SECURITY DEFINER`**, que comprueban el permiso, validan y son atómicas (producto + detalle + certificaciones se guardan juntos o no se guarda nada). Nadie tiene `INSERT`, `UPDATE` ni `DELETE` directos.

| Tabla / vista | Leer | Escribir |
|---|---|---|
| `unit_of_measure`, `certification` | Cualquier cuenta activa | Nadie desde la API (catálogos de referencia) |
| `product`, `coffee_detail`, `cacao_detail`, `product_certification` | `products.read` | Solo por las funciones de abajo |
| `product_catalog` (vista, `security_invoker`) | `products.read` | Solo lectura |

| Función | Permiso | Qué hace |
|---|---|---|
| `create_product(p jsonb)` | `products.create` | Registra café o cacao con su detalle y certificaciones |
| `update_product(id, p jsonb)` | `products.update` | Edita variedad, calidad, HS, umbral y los datos del tipo |
| `set_product_active(id, activo)` | `products.update` | Inactiva o reactiva |
| `set_product_certifications(id, ids[])` | `products.update` | Reemplaza las certificaciones |

**Reglas en la base** (las pantallas solo las repiten para dar buenos mensajes):

| Regla | Dónde |
|---|---|
| Tipo `coffee` o `cacao`; el tipo y la unidad base **no cambian** | `CHECK` y trigger `product_guard` (también para el propietario) |
| Cada tipo exige su detalle (café: humedad 0 a 100; cacao: tipo de grano y fermentación 0 a 100) | Restricción diferida `product_detail_required` y trigger de tipo de detalle |
| Un producto es único por (tipo, variedad, calidad) sin distinguir mayúsculas | Índice único `product_identity_uq` |
| Código HS con formato `0901`, `0901.11` o `0901.11.00` (fuente y versión normativa pendientes) | `CHECK` |
| Umbral de stock bajo no negativo; unidad base existente | `CHECK` y clave foránea |
| Certificaciones existentes, sin duplicados y activas para asignar (una inactiva ya asignada puede conservarse) | Funciones |
| Campos desconocidos o de otro tipo se rechazan (un café no admite `bean_type`) | Funciones |
| **Los productos no se borran** (se inactivan), tengan historial o no | Sin privilegio `DELETE` y trigger `product_no_delete` (también para el propietario) |

**Auditoría:** cada creación, edición (con los nombres de los campos cambiados), inactivación, reactivación y cambio de certificaciones queda en `audit_log` (`product.created`, `product.updated`, `product.inactivated`, `product.reactivated`, `product.certifications_changed`), sin datos personales y sin registrar los intentos rechazados.

**Permisos nuevos:** `products.read`, `products.create`, `products.update`. **No se concedieron a ningún rol** (ni al administrador, que gestiona usuarios y roles): se asignan desde la pantalla de roles. Una propuesta por rol está en la sección 12.2 (comercial: los tres; logístico: lectura).

**Pendiente:** el catálogo de unidades solo tiene `kg` y `t`; no se modela la conversión entre unidades (decisión abierta del cliente). Cuando existan las tablas de pedidos, inventario y lotes, sus claves foráneas hacia `product` deben ser `ON DELETE RESTRICT`.
