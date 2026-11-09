# QA de registro, autenticación y sesión

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.1  
**Fecha de ejecución:** 2026-10-08 (secciones 2.4 y 3 ampliadas con PLAT-454 a PLAT-457)  
**Alcance:** RF-01 (iniciar sesión), RF-02 (registro público) y la gestión de sesión de la app. Backlog: PLAT-450 a PLAT-457 y PLAT-466 a PLAT-506.  
**Estado:** Pruebas automatizadas y contra el servicio real completadas con las salvedades de la sección 4. **El recorrido completo con una cuenta real sigue pendiente.**

## 1. Resumen

| Capa | Resultado |
|---|---|
| Pruebas automatizadas de la app | **105 de 105 correctas** (`flutter test`; `flutter analyze` sin problemas) |
| Pruebas de la base (`database/tests`) | `verify_schema.sql` **54 de 54**; `rules.sql` **84 de 84**; `products.sql` **97 de 97** (sesiones simuladas, transacción revertida) |
| Comprobaciones contra Supabase real | 4 respuestas de error verificadas; no se creó ninguna cuenta (0 filas en `auth.users` antes y después) |
| Prueba en emulador Android | Inconclusa para el envío del registro: el emulador no tuvo salida a Internet. Sí se verificó el manejo del fallo de red |

## 2. Casos de prueba

### 2.1 Registro público (PLAT-450 / RF-02)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| R1 | Campos obligatorios vacíos no se envían | Correcto | Prueba de pantalla |
| R2 | Contraseña y confirmación distintas | Correcto | Prueba de pantalla (añadida hoy) |
| R3 | Contraseña de más de 72 bytes | Correcto | Prueba de pantalla (añadida hoy) |
| R4 | El formulario no ofrece ni envía rol | Correcto | Pruebas del cliente de Supabase y del local |
| R5 | La cuenta nace siempre con rol `cliente`, aunque se pida otro | Correcto | `rules.sql` caso 1 (base real, transacción revertida); prueba del backend local |
| R6 | Contraseña débil (`123`): Supabase la rechaza y la app muestra un mensaje en español | Correcto | Respuesta real `422 weak_password` (curl) y prueba del mapeo; **defecto corregido hoy** (ver 3) |
| R7 | Correo con formato inválido | Correcto | Respuesta real `400 validation_failed` (curl); mensaje traducido (prueba) |
| R8 | Correo ya registrado (backend local) | Correcto | `409` en pruebas del backend local |
| R9 | Correo ya registrado con Supabase real | **No verificado** | Con confirmación de correo activa, Supabase no devuelve error para no revelar qué correos existen; el mensaje de la app es neutro a propósito. Requiere dos registros reales |
| R10 | Registro exitoso de extremo a extremo (cuenta, correo de confirmación, perfil) | **No verificado** | Crea una cuenta y envía un correo real; falta |
| R11 | Falla de red o tiempo agotado | Correcto | En emulador la app mostró "La solicitud tardó demasiado. Inténtalo de nuevo." sin cerrarse y permitió reintentar (RNF-19) |

### 2.2 Autenticarse (PLAT-451, PLAT-452 / RF-01)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| A1 | Campos vacíos: validación y no se envía | Correcto | Prueba de pantalla y emulador |
| A2 | Credenciales incorrectas: mensaje único, sin revelar si la cuenta existe | Correcto | Emulador contra Supabase real ("Correo electrónico o contraseña incorrectos.") y pruebas |
| A3 | Correo sin confirmar: mensaje específico tras validar la contraseña | Correcto en prueba; **no verificado con Supabase real** | Prueba del mapeo |
| A4 | Cuenta desactivada o con rol inactivo no inicia sesión | Correcto en prueba; la regla de la base no se ejercitó con `login` real | Pruebas del cliente; `rules.sql` cubre la desactivación |
| A5 | Mostrar/ocultar contraseña | Correcto | Prueba de pantalla |
| A6 | Navegación entre acceso y registro (ida y vuelta) | Correcto | Emulador y pruebas |
| A7 | Inicio de sesión exitoso con una cuenta real | **No verificado** | Falta crear la cuenta |

### 2.3 Gestión de sesión (PLAT-453)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| S1 | El token se guarda en almacenamiento seguro y se restaura al abrir la app | Correcto | Pruebas de `AuthSession` y de la app |
| S2 | Un token vencido o malformado se descarta al restaurar | Correcto | Pruebas de `AuthSession` |
| S3 | Cerrar sesión borra el token y vuelve al acceso | Correcto | Prueba de la app |
| S4 | **Un `401` del servidor cierra la sesión y avisa "Tu sesión expiró"** | Correcto (nuevo) | Pruebas de `ApiClient`, `AuthSession` y de la app |
| S5 | **Sin sesión no se entra a rutas protegidas; con sesión no se vuelve al acceso ni al registro** | Correcto (nuevo) | Pruebas de la app (`/users`, `/roles`, `/profile`, `/`, `/login`, `/register`) |
| S6 | El `401` de un inicio de sesión fallido no cierra nada | Correcto | Prueba de `ApiClient` |
| S7 | Refresco automático del token | **No implementado** | Pendiente (ADR-021) |

### 2.4 Usuarios desactivados y cierre de sesión (PLAT-454 a PLAT-457)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| B1 | Una cuenta desactivada no ve su propio perfil, ni roles, permisos ni `role_permission` | Correcto | `rules.sql` (base real, transacción revertida) |
| B2 | Una cuenta desactivada no edita su perfil ni sube archivos a Storage | Correcto | `rules.sql` |
| B3 | Un administrador desactivado pierde también el acceso de gestión | Correcto | `rules.sql` |
| B4 | Desactivar veta la cuenta en Supabase Auth (`banned_until`) y revoca sus sesiones | Correcto | `rules.sql` (con una sesión de Auth simulada) |
| B5 | Reactivar quita el veto y devuelve el acceso | Correcto | `rules.sql` |
| B6 | Un usuario vetado no inicia sesión y el mensaje no revela el motivo | Correcto en prueba; **no verificado con Supabase real** | Prueba del mapeo (`user_banned` → "incorrectos") |
| B7 | Un usuario desactivado con la app abierta es expulsado al siguiente `/me` | Correcto en prueba | Pruebas de `/me` (401) y de `ApiClient` (cierra la sesión) |
| B8 | Cerrar sesión borra el token local, vuelve al acceso y **revoca la sesión en Supabase** (`POST /auth/v1/logout?scope=local`) | Correcto en prueba; **no verificado con Supabase real** | Pruebas del cliente de Supabase |
| B9 | Cerrar sesión funciona aunque la revocación en el servidor falle o el token ya venció, sin marcar la sesión como "expirada" | Correcto | Pruebas de `ApiClient` (`signalUnauthorized: false`) y de la app |
| B10 | Desactivar cierra la sesión que ya tenía el usuario en el backend local | Correcto | Pruebas del backend local |
| B11 | Un token ya emitido sigue siendo válido hasta vencer, aunque las políticas no le concedan nada | **Limitación conocida** | Documentada en `modelo-autorizacion-rls.md` |

### 2.5 Políticas por rol, aislamiento y vista de usuarios (PLAT-466 a PLAT-469)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| P1 | Cada rol sembrado (administrador, comercial, logístico, cliente) × cada tabla de negocio × cada operación | Matriz actualizada para los perfiles basales; pendiente de reejecución contra el esquema con la nueva migración | `database/tests/policies_by_role.sql` (datos de prueba y transacción revertida) |
| P2 | Aislamiento del cliente externo: cada cliente ve solo lo suyo, sin vínculo o sin `portal.read` no ve nada, no escribe ni se auto-vincula | **33 de 33** | `database/tests/client_isolation.sql` |
| P3 | Políticas de los módulos de negocio con roles de solo lectura, completo, sin permisos, desactivado y anónimo | **54 de 54** | `database/tests/draft_policies.sql` |
| P4 | La vista de usuarios respeta la RLS: el administrador ve todos con el nombre del rol, el cliente solo su fila, el desactivado nada, el anónimo no accede | Correcto | `rules.sql` (4 pruebas) |
| P5 | Lista y búsqueda de usuarios en la app: usa la vista, muestra el nombre del rol, filtra por texto, estado y página | Correcto | Pruebas del cliente de Supabase y del backend local |
| P6 | Aplicar las políticas de negocio y el aislamiento en la base real | **No hecho a propósito** | Las tablas aún no existen; ver `modelo-autorizacion-rls.md`, secciones 11 y 12 |

### 2.6 Cambio de rol y auditoría (PLAT-470 a PLAT-473)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| C1 | Un rol con solo `users.assign_role` no promueve a nadie a administrador ni degrada a un administrador | Correcto | `rules.sql` (2 pruebas) |
| C2 | Un administrador sí promueve y degrada a otro usuario | Correcto | `rules.sql` (2 pruebas) |
| C3 | Cada cambio de rol queda registrado con actor, usuario, rol origen y destino; los cambios por SQL quedan con actor nulo | Correcto | `rules.sql` |
| C4 | Un intento rechazado no deja registro; el registro no guarda correos ni nombres | Correcto | `rules.sql` |
| C5 | Quien tiene `audit.read` consulta la auditoría; quien no, ve 0 filas; el anónimo no accede | Correcto | `rules.sql` |
| C6 | Nadie escribe, edita ni borra la auditoría desde la API, y ni el propietario puede editarla, borrarla o vaciarla | Correcto | `rules.sql` |
| C7 | Borrar la cuenta de un actor conserva sus registros con actor nulo | Correcto | `rules.sql` |
| C8 | Pantalla de edición: selector de rol por nombre; bloqueado sin `users.assign_role` o al editarse a uno mismo; muestra el error de la base | Correcto | 4 pruebas de pantalla |
| C9 | El backend local aplica la misma política (nunca el propio rol, con permiso, rol administrador solo por un administrador) | Correcto | Prueba del backend local |
| C10 | Cambio de rol de punta a punta en el emulador con Supabase real | **No verificado** | Falta una cuenta real; el emulador no tuvo Internet en la última sesión |
| C11 | Listado de usuarios (PLAT-470) | Correcto | Ver 2.5 (P5) y pruebas de la pantalla |

### 2.7 Recuperación de acceso (PLAT-485 a PLAT-487)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| V1 | Pedir el código: respuesta siempre neutra (exista o no la cuenta); correo inválido no llama a Supabase; límite de correos se informa | Correcto | Pruebas del cliente de Supabase y del backend local |
| V2 | Canjear: verifica el código, cambia la contraseña y cierra la sesión temporal | Correcto | Prueba del cliente de Supabase (3 llamadas, en orden) |
| V3 | Código inválido o vencido → mensaje claro; contraseña débil o repetida → 422 | Correcto | Pruebas; la respuesta real de Supabase a un código falso es `403 otp_expired` (curl) |
| V4 | Un solo uso, la contraseña anterior deja de servir y un usuario desactivado no recibe código | Correcto | Pruebas del backend local |
| V5 | Pantallas: validación, solo dígitos, errores del servidor, rutas públicas sin sesión, enlace desde el login | Correcto | 5 pruebas de pantalla |
| V6 | Correo real con el código, plantilla aplicada al proyecto | **No verificado** | Consume el límite de correos de Supabase; la plantilla (`supabase/templates/recovery.html`) no se ha empujado |

### 2.8 Módulo de productos (PLAT-491 a PLAT-506)

| # | Caso | Resultado | Evidencia |
|---|---|---|---|
| M1 | Registrar café y cacao con sus datos propios y certificaciones | Correcto | `products.sql`, pruebas de cliente y de pantalla |
| M2 | Validaciones en la base: obligatorios, rangos 0 a 100, formato HS, umbral, unidad, certificaciones, campos ajenos | Correcto (15 casos) | `products.sql` |
| M3 | Duplicado (mismo tipo, variedad y calidad) | Correcto | `products.sql` y recorrido de la app |
| M4 | Atomicidad: un intento fallido no deja productos a medias | Correcto | `products.sql` |
| M5 | Editar; el tipo y la unidad no cambian; HS se puede borrar | Correcto | `products.sql` y pantalla |
| M6 | Inactivar y reactivar, con historial consultable; sin borrado (ni para el propietario) | Correcto | `products.sql`, catálogo |
| M7 | Asociar certificaciones: reemplazo atómico, duplicadas, inexistentes, inactivas | Correcto | `products.sql` |
| M8 | Catálogo: filtros por tipo, certificación, calidad, estado y texto; datos de unidad y certificaciones | Correcto | `products.sql` (vista) y pruebas del catálogo |
| M9 | Permisos: lectura sin escritura, sin permisos no ve nada, cuenta desactivada no ve nada, anónimo no accede | Correcto | `products.sql` |
| M10 | Auditoría de creación, edición, inactivación y certificaciones, sin datos personales | Correcto | `products.sql` |
| M11 | Interfaz: recorrido completo (registrar, rechazar duplicado, editar, inactivar, filtrar inactivos, reactivar); botón solo con `products.read` | Correcto | `products_flow_test.dart` (ancho 700 px) |
| M12 | Registrar un producto con una cuenta real contra Supabase, y la interfaz en el emulador | **No verificado** | Falta una cuenta con permisos de producto; el emulador no tuvo Internet |

## 3. Defectos encontrados y corregidos

| # | Defecto | Corrección |
|---|---|---|
| D1 | **Sesión vencida sin manejo:** con el token vencido o revocado la app seguía "dentro" y cada pantalla mostraba errores. No había guarda de rutas: sin sesión se podía abrir `/users` por URL. | `ApiClient` avisa de un `401` con token; `AuthSession.expire()` cierra la sesión una sola vez; `go_router` redirige según la sesión; el acceso muestra "Tu sesión expiró". |
| D2 | **Mensajes de validación genéricos:** ante una contraseña débil, la pantalla habría mostrado "La solicitud contiene datos no válidos." porque las pantallas leen solo `message` y el detalle por campo se perdía. | `ApiClient` usa el detalle concreto como mensaje en los `422`; afecta a todas las pantallas. |
| D3 | **Mensaje en inglés** de Supabase para un correo inválido. | Traducido a "Ingresa un correo válido." / "Ingresa una contraseña válida.". |
| D4 | **Usuarios desactivados sin bloqueo real (H6):** el control estaba solo en el código de la app; una cuenta desactivada con un token válido seguía leyendo catálogos, editando su perfil y usando Storage, y podía iniciar sesión en Supabase Auth directamente. | Migración `20261008000300`: `is_active_user()` en todas las políticas, veto en Auth y sesiones revocadas al desactivar. |
| D6 | **La vista de usuarios conservaba privilegios de escritura** que Supabase concede por defecto a `authenticated` (el `revoke` inicial solo quitó los de `anon`). Lo detectó `verify_schema.sql` tras aplicar la migración. | Migración `20261008000501`: la vista queda solo con `SELECT`. |
| D7 | **Escalada a administrador:** un rol con `users.assign_role` podía promover a cualquiera a administrador. | Regla en `profile_guard`: el rol administrador solo lo asigna o quita un administrador (migración `20261008000600`). |
| D8 | **Cambios de rol sin rastro:** no existía registro de auditoría. | Tabla `audit_log` append-only y trigger de auditoría de cambios de rol. |
| D9 | **Error en `update_product` (productos):** concatenaba a un arreglo sin tipo y fallaba con `malformed array literal`. Lo detectó `products.sql` antes de aplicar la migración. | Corregido con `array_append` antes de aplicar la migración 0700. |
| D10 | **Avisos en cola en el catálogo:** un aviso anterior ocultaba el del resultado nuevo (por ejemplo, "Producto reactivado"). | El catálogo oculta el aviso actual antes de mostrar el nuevo. |
| D5 | **Cierre de sesión solo local:** la sesión seguía viva en Supabase tras "Cerrar sesión". | Se revoca en el servidor, al mejor esfuerzo, antes de borrar el token local. |

## 4. Límites de esta ejecución y lo que falta

- **Emulador sin red:** el emulador no alcanzó Internet en esta sesión (ni siquiera con el Wi‑Fi reiniciado), por lo que el envío del registro desde el móvil no se completó. Es un problema del emulador, no de la app.
- **No se creó ninguna cuenta** en Supabase: un registro real crea un usuario y envía un correo; el envío integrado de Supabase está limitado a pocos correos por hora.
- **Cierre de sesión en un solo lugar:** el botón vive en el inicio; las pantallas de usuarios, roles y perfil vuelven al inicio con la flecha. No hay un acceso a cerrar sesión en cada pantalla.
- **Para cerrar R9, R10, A3, A7, B6 y B8:** crear una cuenta real (o el administrador desde el panel), confirmar el correo, iniciar sesión y comprobar que el perfil existe con rol `cliente`. Repetir el registro con el mismo correo para confirmar R9.
- La contraseña mínima vigente en el proyecto es **6** (la de `config.toml`, 8, está como valor deseado sin aplicar).

## 5. Cómo repetir las pruebas

```powershell
flutter analyze; flutter test                                        # app
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/verify_schema.sql
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/rules.sql
```
