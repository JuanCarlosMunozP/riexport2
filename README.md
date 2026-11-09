# RiExport Flutter

Cliente Flutter de RiExport para Android, iOS y Web. La estructura de `lib/` sigue la arquitectura modular descrita en la documentación del proyecto. Incluye autenticación y el formulario de registro de usuarios.

El estado compartido se gestiona con `provider` y `ChangeNotifier`; cada feature mantendrá sus propios notifiers/estados. Usa `setState` para estado efímero limitado a un widget. La sesión se restaura al iniciar y conserva solo el token de acceso en almacenamiento seguro del dispositivo.

## Ejecutar

Desde la raíz del repositorio:

```powershell
flutter pub get
.\setup_local_https.ps1
.\run_web.ps1
```

La primera vez, instala `mkcert` (por ejemplo, con `winget install --id FiloSottile.mkcert --exact`). `setup_local_https.ps1` crea un certificado para `localhost` y pide a Windows confiar en la autoridad local para este usuario. Acepta el aviso de seguridad; si lo cancelas, los archivos se generan pero el navegador advertirá que el certificado no es de confianza. Los archivos se guardan en `.certs-local/`, excluido de Git. El servidor escucha en `https://localhost:5000`; si el puerto está ocupado, informa del conflicto en vez de cambiarlo.

Este certificado es únicamente para desarrollo web local: no lo uses en producción. La app móvil no sirve HTTPS; como cliente, valida el certificado TLS del backend al conectarse. Supabase ya usa HTTPS con `SUPABASE_URL` del `.env`. Si configuras un backend propio mediante `API_BASE_URL`, usa una URL HTTPS pública con un certificado válido y confiable para Android/iOS; `localhost` en un teléfono apunta al propio teléfono, no a tu PC.

## Verificar

```powershell
flutter analyze
flutter test
```

`pubspec.lock` fija las dependencias Dart resueltas para esta aplicación.

## Backend en Flutter + Supabase

El backend vive dentro de la app (`lib/backend/`) y habla directo con Supabase (Auth + PostgREST), sin servidor propio:

- `SupabaseBackendClient` atiende autenticacion, usuarios/roles, catalogos, clientes, pedidos, inventario, exportaciones, trazabilidad y envios. Las reglas de negocio y los permisos los aplica la base mediante RLS y triggers.
- `LocalBackendClient` conserva en memoria los flujos locales implementados, incluidos pedidos en borrador editables y el registro parcial de exportaciones. Para la demostración sin Supabase, el modo local trae **datos ficticios en memoria** (`lib/backend/local_demo_store.dart`): 3 envíos con su línea de tiempo y cambios de estado válidos, cartera de pagos (pendiente, parcial, vencida y pagada) con registro de pagos y conversor de moneda, tasas de cambio y notificaciones. Se pierden al cerrar la app. En modo local no hay generación ni subida de documentos (requiere Edge Functions y Storage) ni actualización de tasas desde el servicio externo.

Configuración (una sola vez):

1. Crea un archivo `.env` en la raíz (está en `.gitignore`: nunca se sube a GitHub) con `SUPABASE_URL` y `SUPABASE_ANON_KEY` (clave pública/publishable; nunca uses la secret key en la app). `DATABASE_URL` y `SUPABASE_DB_PASSWORD` solo sirven para aplicar el esquema con `psql`; la app no los lee. Pide los valores al responsable del proyecto o cópialos de Project Settings > API en Supabase.
2. Aplica las migraciones de `database/migrations/` en orden (una a una en Supabase > SQL Editor, o con el bucle de `psql` de `database/README.md`). No existe un `schema.sql` monolítico.
3. Crea tu cuenta (Authentication > Users > Add user, con "Auto Confirm User", o regístrate desde la app) y promuévela a administrador con el `update` comentado al final de `database/migrations/20261008000000_auth_roles_baseline.sql`.
4. En Supabase > Authentication > Providers > Email puedes desactivar "Confirm email" para pruebas; si está activo, hay que confirmar el correo antes de iniciar sesión.

Cambio de correo: solo el titular puede hacerlo, desde **Mi perfil** (`PATCH /me`). Supabase Auth envía un enlace de confirmación al correo nuevo y, al confirmarlo, un trigger copia el correo a `public.profile`. El administrador no puede cambiar el correo de otros usuarios desde la app (requeriría la clave `service_role`, que nunca debe ir en la app).

El registro es público ("¿No tienes una cuenta? Regístrate"): toda cuenta nace con el rol `cliente`. El inicio muestra Usuarios y Roles solo a quien tenga los permisos `users.read` / `roles.read`.

Funciones disponibles: registro público, inicio y cierre de sesión (con revocación en el servidor), **recuperación de acceso por código de 6 dígitos** (plantilla en `supabase/templates/recovery.html`, pendiente de empujar al proyecto), perfil propio, usuarios y roles con permisos, y el **catálogo de productos** de café y cacao con certificaciones (permisos `products.read/create/update`, que se asignan a un rol desde la pantalla de roles).

Pedidos: el rol comercial puede consultar, registrar, filtrar y cambiar estados; solo los pedidos en borrador se pueden editar. El total se recalcula desde sus líneas. Exportaciones: se crean desde pedidos confirmados, admiten asignación parcial de cantidades en varias exportaciones y ofrecen catálogos de destino e Incoterms ICC 2020 (opcional).

Ejecutar con Supabase:

```powershell
flutter run --dart-define-from-file=.env
```

En Android/iOS, ese comando conecta a Supabase usando HTTPS. No instales ni desactives la validación del certificado en la app móvil.

Para usar un servidor HTTP externo con el mismo contrato, compila con `--dart-define=USE_REMOTE_API=true` (y `API_BASE_URL` si hace falta).

## Navegación

La navegación declarativa con `go_router` está centralizada en
`lib/app/router/app_router.dart`. Una sesión restaurada abre `/` y una sesión
ausente o vencida abre `/login`; rutas desconocidas muestran una página 404.
Desde Inicio se accede a `/users` para consultar, buscar y paginar usuarios
(permiso `users.read`) y a `/users/new` para registrarlos (permiso
`users.create`). La edición se abre en `/users/:userId/edit` desde las acciones
del listado y requiere `users.update`; la desactivación requiere
`users.deactivate`. `/roles` permite crear y editar roles, consultar el
catálogo y asignar permisos (`roles.read`, `roles.create`, `roles.update`,
`roles.permissions.update`); la desactivación requiere `roles.deactivate`.
Hasta que esté disponible un selector de roles, el formulario de alta de usuario
recibe el ID de un rol activo. El enrutador sincroniza la ubicación web con la
URL y permite abrir rutas directamente.

## Interfaz

- **Menú lateral.** El inicio usa un menú lateral con secciones que se pliegan y se despliegan con un clic: Cuenta, Catálogo, Ventas y exportación, Operación y Administración. Cada opción aparece solo si el rol del usuario tiene el permiso correspondiente (los permisos se leen una vez al abrir el inicio; tras cambiar un rol hay que cerrar sesión y volver a entrar). En pantallas de 600 px o más el menú queda fijo a la izquierda; por debajo se abre como cajón desde el botón de menú. Al final del menú está el botón **Cerrar sesión**.
- **Inicio.** El área principal muestra un resumen con **datos de ejemplo** (pedidos activos, envíos en tránsito, stock y cobros pendientes). No se lee de ningún backend: es solo demostrativo (`lib/features/home/presentation/demo_dashboard.dart`).
- **Formularios en modal.** Crear y editar productos, proveedores, clientes, fincas, lotes y envíos se abre como ventana modal sobre la lista (`lib/app/router/modal_form_page.dart`), no como página completa. El registro de pedidos y de exportaciones, el editor de usuarios, el login y el registro siguen a pantalla completa.

## Roles y permisos

Los permisos son códigos (`modulo.accion`) que se asignan a roles; la base los aplica con RLS. El administrador los gestiona desde **Administrar roles y permisos**. La migración `database/migrations/20261107000100_roles_por_modulo.sql` deja definidos estos roles, que siguen las diapositivas «Roles y permisos» del cliente:

| Rol (nombre en la app) | Nombre técnico | Qué hace |
|---|---|---|
| **Administrador** | `administrador` | Control total: usuarios, roles, permisos y seguridad. Tiene todos los permisos existentes; no se puede desactivar ni renombrar, ni dejar el sistema sin un administrador activo. |
| **Gestor de Inventario** | `gestor_inventario` | Existencias: catálogo de productos, lotes, fincas, proveedores y ajustes de inventario (`products.*`, `lots.read/create`, `farms.*`, `suppliers.*`, `inventory.read/adjust`). |
| **Gestor Comercial** | `usuario_comercial` | Relaciones comerciales: clientes y pedidos (crear, editar, cambiar estado) y exportaciones. Lectura de productos, inventario, envíos y pagos; genera documentos. |
| **Gestor de Logística** | `encargado_logistico` | Operación: despachos y seguimiento de envíos (`logistics.read/create/update`). Lectura de pedidos, clientes, productos, lotes e inventario; consulta y sube documentos de envío. |
| **Gestor Financiero** | `gestor_financiero` | Control financiero: cartera de pagos y registro de pagos (`payments.read/create`). Lectura de pedidos, clientes, exportaciones y documentos. |
| **Gestor de Cumplimiento UE** | `gestor_cumplimiento` | Exportación a la Unión Europea: declaración EUDR, trazabilidad y documentos de exportación de café y cacao. Edita exportaciones y genera/sube documentos; lectura de pedidos, clientes, productos, lotes, fincas y proveedores. Es el único rol añadido por el equipo; no figura en las diapositivas del cliente. |
| **Cliente** | `cliente` | Portal externo (`portal.read`): seguimiento de sus propios envíos. Toda cuenta registrada desde la app nace con este rol. Para ver envíos, la cuenta debe estar vinculada a un cliente (tabla `customer_user`). |

Permisos existentes: `audit.read`, `customers.*`, `documents.read/generate/upload`, `exports.read/create/update`, `farms.*`, `inventory.read/adjust`, `logistics.read/create/update`, `lots.read/create`, `orders.read/create/update/transition`, `payments.read/create`, `portal.read`, `products.*`, `roles.read/create/update/deactivate/permissions.update`, `suppliers.*` y `users.read/create/update/deactivate/assign_role` (donde `*` = `read`, `create` y `update`).

No existe todavía un permiso ni una pantalla de reportes; el Gestor Financiero trabaja con la cartera de pagos.

### Cuentas de demostración

`database/seeds/demo/seed_demo_roles.sql` (solo desarrollo, idempotente) crea una cuenta por rol: `admin@`, `comercial@`, `logistica@`, `inventario@`, `financiero@`, `cumplimiento@`, `cliente@` y `cliente2@` con dominio `demo.riexport.test`. Las contraseñas no se documentan aquí: están en `credenciales.txt` (archivo local, ignorado por Git). No uses estas cuentas fuera de desarrollo.

## Pruebas

```powershell
flutter test                          # toda la suite
flutter test test/features/products   # un solo módulo
```

Los tests están organizados por módulo:

```
test/
├── app/        router, inicio, menú lateral y permisos
├── core/       cliente de API
├── backend/    backend local y cliente Supabase
├── support/    utilidades compartidas
└── features/   auth, users, products, suppliers, customers, farms, orders, operations
```

Las pruebas SQL de la base están en `database/tests/`.

## Ejecutar la web con HTTPS

Con el certificado ya generado (`.\setup_local_https.ps1`):

```powershell
flutter run -d web-server --web-hostname localhost --web-port 5000 --web-launch-url https://localhost:5000 --web-tls-cert-path .certs-local/localhost.pem --web-tls-cert-key-path .certs-local/localhost-key.pem --dart-define-from-file=.env
```

La primera carga en modo debug puede tardar hasta un minuto. Si el puerto 5000 está ocupado (`errno = 10048`), cierra el otro `flutter run` que lo usa. Tras un cambio de código, pulsa `r` o `R` en esa terminal. Si abres una pestaña mientras se reinicia el servidor, ciérrala y abre una nueva para evitar errores `ERR_CONNECTION_REFUSED`.

## Notas de la base de datos

- El rol `authenticated` necesita `SELECT` sobre `profile`, `role`, `permission` y `role_permission`; si falta, el login falla con un 403 al leer `profile`. Las migraciones asumen que Supabase lo concede por defecto: en un proyecto nuevo, comprueba `grant select on public.profile, public.role, public.permission, public.role_permission to authenticated;`.
- Las migraciones crean los permisos de cada módulo; el trigger de `20261107000000_role_permission_baselines.sql` se los asigna automáticamente al administrador cuando se insertan, y `20261107000100_roles_por_modulo.sql` define los permisos de los demás roles.

### Datos de demostración del portal del cliente

`database/seeds/demo/seed_demo_envios.sql` carga 3 envíos de «Importadora Demo GmbH» (en aduana, en tránsito y planificado) y `database/seeds/demo/seed_demo_clientes_notificaciones.sql` añade un segundo cliente («Koffie Import B.V.», con 1 envío) y notificaciones para cada cuenta. Cada cuenta de cliente solo ve los envíos y las notificaciones de su propio cliente (la vista `customer_shipment_tracking` filtra por `customer_user` y las notificaciones por destinatario); el personal con permisos de logística ve todos. Orden de carga: `seed_demo_roles.sql`, `seed_demo_envios.sql`, `seed_demo_clientes_notificaciones.sql`.

`database/seeds/demo/seed_demo_cumplimiento.sql` añade datos para el Gestor de Cumplimiento UE: documentos de exportación de ejemplo (certificado fitosanitario y declaración EUDR; solo registros, **sin archivo en Storage**, por lo que no se pueden descargar) y notificaciones de cumplimiento. La declaración EUDR de cada exportación se genera bajo demanda desde la trazabilidad (lote, finca con coordenadas, proveedor y código HS). Se carga después de los otros tres seeds.

`database/seeds/demo/seed_demo_financiero.sql` añade la cartera de pagos de las exportaciones demo (pendiente, parcial, vencida y pagada), tasas de cambio de referencia y notificaciones para el Gestor Financiero. Se carga después de los seeds de roles, envíos y clientes.
