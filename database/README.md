# Base de datos (Supabase): esquema, semillas y pruebas

Todo el SQL del proyecto vive en esta carpeta, separado por responsabilidad. `supabase/` conserva solo la configuración de la CLI (`config.toml`), las plantillas de correo de Auth y las Edge Functions.

```
database/
  migrations/      # cambios del esquema, en orden (única fuente de verdad); una migración por tema
  seeds/
    seed.sql       # datos base mínimos (se carga con `supabase db reset`)
    demo/          # datos ficticios de demostración, uno por área (solo desarrollo)
  tests/           # verificación del esquema, reglas, RLS y borradores
  drafts/          # borradores NO aplicados
  scripts/
    sync-supabase.ps1   # copia migrations/ y seeds a supabase/ para usar la CLI
supabase/
  config.toml      # configuración de la CLI: entorno local, Auth y buckets
  templates/       # plantillas de correo de Auth (recuperación de acceso)
  functions/       # Edge Functions
```

No existe un `schema.sql` monolítico: el esquema completo es la suma ordenada de `database/migrations/*.sql`. Para aplicarlo a una base vacía (por ejemplo, con `psql`), ejecuta las migraciones en orden:

```powershell
Get-ChildItem database\migrations\*.sql | Sort-Object Name | ForEach-Object { psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -q -f $_.FullName }
```

La CLI de Supabase solo lee `supabase/migrations/`, así que antes de `db push` o `db reset` se sincroniza desde esta carpeta (esa copia está en `.gitignore`):

```powershell
.\database\scripts\sync-supabase.ps1
```

Datos de demostración (solo desarrollo; en este orden): `seeds/demo/seed_demo_roles.sql`, `seed_demo_envios.sql`, `seed_demo_clientes_notificaciones.sql`, y luego `seed_demo_cumplimiento.sql`, `seed_demo_financiero.sql` y `seed_demo_inventario_comercial.sql`.

## CLI

No hace falta instalarla: `npx supabase@latest <comando>` (probada la v2.120.0, Node 24). Alternativa: instalarla con Scoop o Chocolatey.

```powershell
npx supabase@latest login                                  # una vez; abre el navegador
npx supabase@latest link --project-ref <project-ref>       # pide la contraseña de la base
```

`<project-ref>` es el identificador en `SUPABASE_URL` (`https://<project-ref>.supabase.co`). La contraseña y el token de acceso se escriben en la terminal, nunca en archivos del repositorio.

## Versionado del esquema

Regla: **nunca se edita una migración ya aplicada**; todo cambio es una migración nueva.

```powershell
# crea database/migrations/<AAAAMMDDHHMMSS>_nombre_del_cambio.sql y escribe el SQL
# (con RLS y permisos, ver docs/modelo-autorizacion-rls.md, sección 9); la versión debe ser única
.\database\scripts\sync-supabase.ps1                      # copia las migraciones para la CLI
npx supabase@latest db push                                # aplica las migraciones pendientes al proyecto enlazado
```

El registro de pedidos vive en `20261016000000_customer_orders.sql`. Añade las tablas `customer_order` y `order_line`, y el RPC atómico `create_customer_order(jsonb)`. El usuario debe tener `orders.create`; la consulta directa requiere `orders.read`. La moneda y el EORI se toman del cliente, y cada línea conserva lote, cantidad, precio y código HS.

La migración `20261020000000_order_edit_export_catalogs.sql` completa la edición transaccional de pedidos en borrador (`orders.update`), conserva los ajustes de existencias en el libro de movimientos y agrega los catálogos de destino e Incoterms ICC 2020. `create_customer_export(jsonb)` exige un pedido confirmado, valida las cantidades restantes y registra cada exportación con una o más líneas en una sola transacción; se permiten exportaciones parciales. El Incoterm es opcional.

**Línea base.** Las migraciones `20261008000000_auth_roles_baseline.sql`, `20261008000100_storage_buckets.sql` y `20261008000200_profile_self_edit_and_role_assignment.sql` `20261008000300_block_deactivated_users.sql` y `20261008000400_current_user_role_helper.sql`, `20261008000500_admin_user_list_view.sql` y `20261008000501_admin_user_list_privileges.sql` `20261008000600_role_change_policy_and_audit.sql` `20261008000700_products_module.sql` y `20261009000000_suppliers_module.sql` y `20261010000000_farms_and_lots.sql` `20261013000000_customers_module.sql` y `20261014000000_customer_user_link.sql` ya se aplicaron al proyecto alojado con `psql` antes de enlazar la CLI. Tras el primer `link`, hay que marcarlas como aplicadas para que `db push` no intente repetirlas:

```powershell
npx supabase@latest migration repair --status applied 20261008000000
npx supabase@latest migration repair --status applied 20261008000100
npx supabase@latest migration repair --status applied 20261008000200
npx supabase@latest migration repair --status applied 20261008000300
npx supabase@latest migration repair --status applied 20261008000400
npx supabase@latest migration repair --status applied 20261008000500
npx supabase@latest migration repair --status applied 20261008000501
npx supabase@latest migration repair --status applied 20261008000600
npx supabase@latest migration repair --status applied 20261008000700
npx supabase@latest migration repair --status applied 20261009000000
npx supabase@latest migration repair --status applied 20261010000000
npx supabase@latest migration repair --status applied 20261013000000
npx supabase@latest migration repair --status applied 20261014000000
npx supabase@latest migration list                         # local y remoto deben coincidir
```

Sin la CLI también se puede aplicar un archivo con `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f database/migrations/<archivo>.sql` (la cadena `DATABASE_URL` está en `.env`).

## Pruebas de la base

Scripts SQL contra el proyecto alojado (o el local); fallan con `ON_ERROR_STOP` si algo no coincide:

```powershell
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/verify_schema.sql   # solo lectura: tablas, semilla, RLS, privilegios, buckets
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/rules.sql           # reglas y RLS con sesiones simuladas; se revierte
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/referential_integrity.sql # solo lectura: claves foráneas validadas y números sin huérfanos
```

Además, sobre tablas de prueba y con transacción revertida (no crean nada): `tests/draft_policies.sql` valida `drafts/domain_policies.sql` (54/54), `tests/client_isolation.sql` valida `drafts/client_isolation.sql` (33/33), `tests/draft_customer_history.sql` valida `drafts/customer_history.sql` (22/22; igual que el anterior), `tests/draft_export_traceability.sql` valida `drafts/export_traceability.sql` (22/22; crea tablas de prueba y se niega si ya existen), `tests/policies_by_role.sql` prueba cada rol sembrado contra cada tabla y operación y `tests/exports_shipments.sql` verifica exportaciones, permisos, catálogos y restricciones.

Estado al 2026-10-16: `verify_schema.sql` 54/54, `rules.sql` 84/84, `products.sql` 97/97, `suppliers.sql` 50/50, `farms_lots.sql` 98/98 `customers.sql` 74/74 y `customer_links.sql` 45/45 correctas (los de módulo se revierten: no dejan datos). La migración de pedidos/exportaciones añadida después requiere aplicar la migración pendiente y ejecutar las pruebas Flutter del flujo local y del cliente Supabase.

## Pruebas QA de EP-7 a EP-11 (`database/tests/qa/`)

- Las pruebas SQL (`tests/*.sql`) asumen una base vacía: con datos demo `migrate.sh` las omite (`FORCE_SQL_TESTS=1` las fuerza).

## Datos de demostración (`database/seeds/demo/seed_demo.sql`)

Idempotente y solo para desarrollo (no ejecutar en producción). Cuentas con contraseña `Demo2026!`: `admin@demo.riexport.test`, `comercial@demo.riexport.test`, `logistica@demo.riexport.test` y `cliente@demo.riexport.test` (portal, vinculado a «Importadora Demo GmbH»; el seed le concede `portal.read`). Carga 2 proveedores, 3 fincas, 4 productos con lote e inventario (2 por debajo del umbral), 3 clientes, 3 pedidos con exportación formalizada, 3 envíos (en aduana, en tránsito y planificado) con su línea de tiempo, 4 obligaciones de pago (parcial, vencida, pendiente y pagada), tasas de ejemplo y notificaciones.

## Datos semilla (`database/seeds/seed.sql`)

`supabase db reset` aplica las migraciones y luego `seed.sql` (idempotente, solo desarrollo): un proveedor, una finca geolocalizada y un cliente de ejemplo. Roles, permisos, unidades, certificaciones, destinos e Incoterms los siembran las migraciones.

Primer administrador: registra una cuenta (confirma el correo con el código) y asigna el rol desde SQL: `update public.profile set role_id = (select id from public.role where name = 'administrador') where email = '<correo>';`. 

## Entorno local de desarrollo


```powershell
npx supabase@latest start      # levanta Postgres, Auth, Storage, Studio (http://127.0.0.1:54323) y un buzón de correos de prueba (54324)
npx supabase@latest status     # imprime API URL y claves locales
npx supabase@latest db reset   # recrea la base local aplicando migrations/ desde cero
npx supabase@latest stop
```

Para usar el entorno local desde la app, crea un `.env.local` (ignorado por git) con los valores de `status` y arranca con él:

```
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<anon key que imprime `supabase status`>
```

```powershell
flutter run --dart-define-from-file=.env.local
```

En el emulador de Android el equipo anfitrión no es `127.0.0.1` sino `10.0.2.2`: usa `SUPABASE_URL=http://10.0.2.2:54321`. En local, los correos de confirmación llegan al buzón de pruebas (puerto 54324), no a una bandeja real.


## Autenticación (Supabase Auth)

Valores deseados en `config.toml` (sección `[auth]`):

| Ajuste | Valor | Motivo |
|---|---|---|
| Proveedor de correo y contraseña | Habilitado; sin otros proveedores | Único método de acceso previsto (RF-01) |
| Registro público (`enable_signup`) | Sí | Autorregistro con rol `cliente` (RF-02) |
| Confirmación de correo (`enable_confirmations`) | Sí | Igual que el proyecto alojado hoy |
| Doble confirmación al cambiar correo (`double_confirm_changes`) | Sí | El cambio se confirma en el correo actual y en el nuevo |
| Contraseña | 12 caracteres, mayúscula, minúscula, número y símbolo | Política aplicada en Auth y en los formularios |
| Cambio de contraseña | Reautenticación reciente requerida | Reduce cambios de contraseña desde sesiones robadas |
| Límites de acceso | 10 inicios/registros y verificaciones por IP cada 5 minutos | Reduce intentos automatizados; los límites de correo siguen sujetos a SMTP |
| Vigencia del JWT (`jwt_expiry`) | 3600 s | Valor por defecto; ver ADR-021 |
| `site_url` y redirecciones | `https://localhost:5000` (la web de `run_web.ps1`) | Enlaces de los correos en desarrollo web |

Este archivo **no cambia el proyecto alojado por sí solo**. Para aplicarlo: `npx supabase@latest config push` (con el proyecto enlazado) o el panel *Authentication*. Antes de producción hay que poner la URL pública real en `site_url` y configurar un servidor SMTP propio (el de Supabase limita el envío de correos).

## Almacenamiento de archivos (Supabase Storage)

| Bucket | Acceso | Límite | Tipos | Políticas |
|---|---|---|---|---|
| `profile-photos` | Privado (URLs firmadas) | 2 MiB | PNG, JPEG, WebP | Cada usuario gestiona solo `<su auth.uid()>/…`; con `users.read` se pueden ver las de otros |
| `export-documents` | Privado (URLs firmadas) | 20 MiB | PDF, PNG, JPEG | Ninguna: nadie con sesión accede hasta que el módulo de documentos defina sus permisos |

Convención de rutas: `profile-photos/<auth.uid()>/<archivo>`. Los metadatos relacionales (`stored_file`) se crean con el módulo de documentos; hoy solo existen los buckets.

## Declaración EUDR

La migración `20261022000000_export_eudr_declaration.sql` añade `export_eudr_declaration(export_id)` (SECURITY INVOKER, usa los permisos `exports.read` y `farms.read`). La app la consume con `GET /exports/:id/eudr`. La confirmación de correo usa la plantilla `templates/confirmation.html` (código OTP, `POST /auth/email-confirmations`).
