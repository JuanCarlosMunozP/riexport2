# Infraestructura en Supabase

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.1  
**Estado:** Configuración hecha y verificada el 2026-10-08 contra el proyecto alojado, con las salvedades de la sección 6. Pendiente de aprobación docente/cliente.  
**Relacionado:** ADR-018, ADR-021, ADR-024 y ADR-025 (`decisiones-arquitectura.md`); `modelo-autorizacion-rls.md`; `database/README.md` en el repositorio de la app.

## 1. Resumen por tarea

| Tarea | Resultado | Dónde |
|---|---|---|
| **[INFRA] Configurar la CLI y el versionado del esquema** | CLI de Supabase usada vía `npx` (v2.120.0), proyecto inicializado (`config.toml`), migraciones numeradas como fuente de verdad y `schema.sql` generado a partir de ellas | `supabase/` |
| **[INFRA] Configurar el entorno local de desarrollo** | Configuración y guía listas (Postgres 17, Auth, Storage, Studio y buzón de correos, con Docker). **Sin probar**: Docker estaba apagado. | `supabase/config.toml`, `database/README.md` |
| **[INFRA] Habilitar y configurar el servicio de autenticación** | Supabase Auth con correo y contraseña habilitado y en uso; valores deseados documentados en `config.toml` (algunos aún sin aplicar al proyecto alojado) | Sección 3 |
| **[INFRA] Habilitar el almacenamiento de archivos** | Dos buckets privados creados en el proyecto alojado, con políticas de acceso verificadas | Sección 4 |

## 2. CLI y versionado del esquema

- **Herramienta:** `npx supabase@latest …` (no hay instalación global). Comandos de enlace, creación y aplicación de migraciones en `database/README.md`.
- **Fuente de verdad:** `database/migrations/<fecha>_<nombre>.sql`. Regla: una migración aplicada no se edita; el cambio siguiente es otra migración.
- **Sin instantánea:** no hay `schema.sql` monolítico; el estado completo es la suma ordenada de `database/migrations/`. `database/scripts/sync-supabase.ps1` las copia a `supabase/migrations` para la CLI.
- **Estado actual:**

| Migración | Contenido | Aplicada al proyecto alojado |
|---|---|---|
| `20261008000000_auth_roles_baseline` | Tablas, reglas, RLS y datos base de usuarios y roles | Sí (con `psql`) |
| `20261008000100_storage_buckets` | Buckets de archivos y sus políticas | Sí (con `psql`) |
| `20261008000200_profile_self_edit_and_role_assignment` | Autoedición del perfil, permiso `users.assign_role`, reglas por campo y endurecimiento de privilegios | Sí (con `psql`) |
| `20261008000300_block_deactivated_users` | Bloqueo de usuarios desactivados: `is_active_user()`, políticas, veto y revocación de sesiones en Auth | Sí (con `psql`) |
| `20261008000400_current_user_role_helper` | Función auxiliar `current_user_role()` | Sí (con `psql`) |
| `20261008000500_admin_user_list_view` | Vista `admin_user_list` (`security_invoker`) e índices de búsqueda | Sí (con `psql`) |
| `20261008000501_admin_user_list_privileges` | Corrige los privilegios de la vista (solo `SELECT`) | Sí (con `psql`) |
| `20261008000600_role_change_policy_and_audit` | Regla del rol administrador, `audit_log` append-only y auditoría de cambios de rol | Sí (con `psql`) |
| `20261008000700_products_module` | Módulo de productos: tablas, validaciones, RLS, funciones atómicas, vista de catálogo | Sí (con `psql`) |
| `20261107000000_role_permission_baselines` | Admin con todos los permisos; perfiles limitados para comercial, logística y cliente | No (pendiente; reemplaza asignaciones personalizadas de esos roles: revisar antes de aplicar; no aplicar al proyecto alojado sin autorización) |

- **Pendiente de enlazar:** como ambas se aplicaron con `psql` antes de enlazar la CLI, al hacer el primer `supabase link` hay que marcarlas con `supabase migration repair --status applied <versión>` para que `db push` no las repita.
- La versión de PostgreSQL del proyecto (17.11) coincide con la configurada para el entorno local (`major_version = 17`).

## 3. Autenticación

**Estado del proyecto alojado (leído de los ajustes públicos de Auth):** proveedor de correo y contraseña habilitado, ningún otro proveedor externo activo, registro público permitido y **confirmación de correo exigida**.

**Valores deseados** (en `config.toml`; se aplican con `supabase config push` o desde el panel, y hoy no se han empujado):

| Ajuste | Valor | Nota |
|---|---|---|
| Correo y contraseña | Habilitado | Único método (RF-01) |
| Registro público | Sí | Autorregistro con rol `cliente` (RF-02) |
| Confirmación de correo | Sí | Coincide con el estado actual |
| Doble confirmación al cambiar correo | Sí | El cambio se confirma en el correo actual y en el nuevo; la app lo avisa así |
| Contraseña mínima | 8 | **Propuesta**; Supabase usa 6 por defecto. Hay que validarla con el cliente (RNF) |
| Vigencia del JWT | 3600 s | Valor por defecto (ADR-021) |
| URL del sitio y redirecciones | `https://localhost:5000` (web local) | Cambiar por la URL pública antes de producción |

**Pendientes antes de producción:** servidor SMTP propio (el envío integrado de Supabase está limitado), URL pública y, si se desea, CAPTCHA contra registros masivos (hallazgo H4 de `modelo-autorizacion-rls.md`). La plantilla de los correos de confirmación sigue la de Supabase por defecto, sin personalizar.

## 4. Almacenamiento de archivos

**Aplicado el 2026-10-08.** Dos buckets, ambos privados (se acceden con URLs firmadas, nunca públicas):

| Bucket | Límite | Tipos permitidos | Quién accede |
|---|---|---|---|
| `profile-photos` | 2 MiB | PNG, JPEG, WebP | Cada usuario, solo a su carpeta `<auth.uid()>/…`; quien tenga el permiso `users.read` puede ver las de otros |
| `export-documents` | 20 MiB | PDF, PNG, JPEG | Nadie con sesión, a propósito: se abrirá cuando el módulo de documentos defina permisos y políticas |

**Verificación** (usuarios simulados dentro de una transacción revertida; no quedó ningún archivo):

| Prueba | Resultado |
|---|---|
| Usuario A sube a su carpeta | Permitido |
| Usuario A sube a la carpeta de B | Rechazado |
| Usuario A sube a `export-documents` | Rechazado |
| Usuario B lista los archivos de A | 0 visibles |
| Anónimo sube o lista | Rechazado / 0 visibles |

No probado: la subida real con el cliente de Storage y una cuenta con sesión (requiere la cuenta de administrador), el límite de tamaño y de tipo, y las URLs firmadas. La política de borrado no se pudo ejercitar por SQL porque Supabase bloquea borrados directos en las tablas de Storage; solo se ejercita desde la API.

La tabla de metadatos del modelo de datos (`stored_file`: clave, nombre, tipo, tamaño, hash, autor) se crea con el módulo de documentos; hoy solo existen los buckets (ADR-011).

## 5. Entorno local

`supabase start` levanta con Docker una copia completa (base, Auth, Storage, Studio y un buzón de correos de prueba) que se recrea desde las migraciones con `supabase db reset`. La app se apunta a ella con un `.env.local` (ignorado por git) y `flutter run --dart-define-from-file=.env.local`; en el emulador de Android el anfitrión es `10.0.2.2`. Pasos completos en `database/README.md`.

## 6. Qué falta o no se verificó

| Tema | Estado |
|---|---|
| Entorno local con Docker | Configurado, **no ejecutado** |
| `supabase link` y `db push` | **No ejecutados** (requieren iniciar sesión en la CLI y la contraseña de la base, que no se comparten con el asistente) |
| `config push` de Auth | **No ejecutado**; los valores deseados no están aplicados |
| Subida real de archivos y URLs firmadas | **No probado** (falta cuenta con sesión) |
| SMTP propio y dominio | Pendiente |
| Respaldos y plan del proyecto | Por revisar según el plan contratado (RNF-09) |
