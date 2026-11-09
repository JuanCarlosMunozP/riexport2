# Trazabilidad del backlog: PLAT-474 a PLAT-506

**Proyecto:** Plataforma de exportación de café y cacao  
**Fecha:** 2026-10-08  
**Alcance:** las 32 tareas visibles en el backlog entre PLAT-474 y PLAT-506 (la 490 no aparecía en las capturas). Épicas EP-1 (Autenticación y gestión de usuarios) y EP-2 (Gestión de productos).  
**Cómo leerlo:** *Hecho antes* = ya existía y se verificó; *Hecho ahora* = se construyó en esta sesión; *Parcial* o *Sin verificar* = falta algo que se indica. Detalle de las pruebas en `qa-autenticacion-registro.md`; diseño en `modelo-autorizacion-rls.md`.

## EP-1: Autenticación y gestión de usuarios

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **474** [APP] Acción de cambio de rol | Hecho ahora | Selector de rol por nombre en la edición de usuario; bloqueado sin `users.assign_role` o al editarse a uno mismo | — |
| **475** [QA] Probar la protección del cambio de rol | Hecho ahora | `rules.sql` (9 casos de rol) y pruebas del backend local | Sin sesiones reales de Supabase |
| **476** Desactivar un usuario | Hecho | Menú de la fila con confirmación; ahora también **reactivar** | — |
| **477** [BD] Política de desactivación | Hecho ahora | `is_active_user()` en todas las políticas, veto en Auth y sesiones revocadas (ADR-027) | El token ya emitido vale hasta vencer, sin acceso a datos |
| **478** [APP] Acción de desactivar usuario | Hecho | `users_screen` | — |
| **479** [QA] Probar la desactivación | Hecho ahora | `rules.sql` (11 casos) | Rechazo del vetado con Supabase real sin verificar |
| **480** Administrar el catálogo de roles y permisos | Hecho antes | Pantalla de roles; catálogo de 14 permisos | — |
| **481** [BD] Tablas de permisos y su relación con rol | Hecho antes | `permission`, `role_permission` | — |
| **482** [BD] Enlazar los permisos con las políticas | Hecho ahora | Toda política usa `has_permission()` o `is_active_user()`; `verify_schema.sql` falla si alguna no | — |
| **483** [APP] Pantalla de administración de roles | Hecho antes | `roles_screen` | — |
| **484** [QA] Probar el control de acceso por rol | Hecho ahora | `policies_by_role.sql` (240 celdas) y `rules.sql` | Los permisos de negocio por rol son una propuesta |
| **485** Recuperar el acceso a mi cuenta | Hecho ahora | Código de 6 dígitos por correo (ADR-031) | **Sin probar con un correo real** |
| **486** [INFRA] Plantilla de recuperación | Hecho ahora (en el repositorio) | `supabase/templates/recovery.html` y `config.toml` | **No empujada** al proyecto alojado (`supabase config push`) |
| **487** [APP] Pantallas de recuperación | Hecho ahora | `forgot_password_screen`, `reset_password_screen`, enlace en el login | — |
| **488** Consultar y editar mi perfil | Parcial | Nombres, teléfono y correo | La **foto de perfil** sigue pendiente (el bucket existe, sin pantalla) |
| **489** [APP] Pantalla de perfil | Hecho antes | `profile_screen` | — |

## EP-2: Gestión de productos

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **491** Registrar un producto de café | Hecho ahora | Formulario y función `create_product` | — |
| **492** [BD] Tabla de productos | Hecho ahora | `product`, `coffee_detail`, `unit_of_measure` (migración 0700, aplicada) | — |
| **493** [BD] Validaciones de producto | Hecho ahora | `CHECK`, índice único, triggers y funciones; 97 pruebas | Supuestos por confirmar: unicidad por (tipo, variedad, calidad), formato HS |
| **494** [APP] Formulario de registro de producto | Hecho ahora | `product_form_screen` | — |
| **495** [QA] Probar el registro de productos | Hecho ahora | `products.sql`, pruebas de cliente, de pantalla y un recorrido completo | Sin una cuenta real ni emulador |
| **496** Registrar un producto de cacao | Hecho ahora | Mismo formulario y función, con sus campos | — |
| **497** [BD] Extender la tabla con atributos de cacao | Hecho ahora | `cacao_detail` y el detalle obligatorio por tipo | — |
| **498** [APP] Habilitar el formulario para cacao | Hecho ahora | Selector de tipo con campos propios | — |
| **499** Asociar certificaciones a un producto | Hecho ahora | `set_product_certifications`; al crear o editar | — |
| **500** [BD] Tabla de certificaciones y su relación | Hecho ahora | `certification`, `product_certification`; 3 certificaciones base | — |
| **501** [APP] Sección de certificaciones del producto | Hecho ahora | Chips seleccionables en el formulario | — |
| **502** Consultar y filtrar productos | Hecho ahora | Catálogo con búsqueda, tipo, certificación, estado y paginación | — |
| **503** [BD] Vista de catálogo de productos | Hecho ahora | `product_catalog` (`security_invoker`) | — |
| **504** [APP] Pantalla de catálogo | Hecho ahora | `product_catalog_screen` | — |
| **505** Editar o inactivar un producto | Hecho ahora | Edición con tipo y unidad fijos; inactivar con confirmación y reactivar | — |
| **506** [BD] Impedir el borrado de productos con historial | Hecho ahora | Sin privilegio `DELETE` y trigger (también para el propietario): los productos nunca se borran | Las claves foráneas futuras deben ser `RESTRICT` |

## Proveedores (PLAT-507, 508, 510 y 511)

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **507** [APP] Pantalla de edición de producto | Hecho (junto con 494 y 505) | `product_form_screen` en modo edición: tipo y unidad bloqueados, envía solo lo modificado | — |
| **508** [QA] La inactivación conserva el historial | Hecho (junto con 506) | `products.sql`: el producto inactivo sigue consultable, la reactivación lo restituye y la auditoría registra ambos hechos; nadie borra productos | Sin historial de pedidos o inventario todavía: esos módulos no existen |
| **510** Registrar un proveedor | Hecho ahora | Pantallas `supplier_list_screen` y `supplier_form_screen`; función `create_supplier`; también editar, inactivar y reactivar | Campos propuestos, por confirmar con el cliente |
| **511** [BD] Tabla de proveedores | Hecho ahora | Migración `20261009000000_suppliers_module.sql` (aplicada): tabla `supplier`, documento único sin distinguir mayúsculas, RLS, escritura por funciones, baja lógica, auditoría; `suppliers.sql` 50/50 | País como texto hasta que exista el catálogo `country`; sin fincas todavía |

Los permisos `suppliers.read`, `suppliers.create` y `suppliers.update` no se asignaron a ningún rol.

## Fincas y lotes con geolocalización (PLAT-512 a 515)

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **512** [APP] Pantallas de proveedores | Hecho (junto con 510) | `supplier_list_screen` y `supplier_form_screen`; 22 pruebas en `suppliers_test.dart` | — |
| **513** Registrar una finca o lote con geolocalización | Hecho ahora | `farm_list_screen`, `farm_form_screen` y `lot_screens`; la finca guarda su punto (latitud y longitud) y el lote hereda el de su finca | **Las coordenadas se escriben a mano**: no hay botón de GPS ni mapa; sin polígonos EUDR |
| **514** [BD] Tabla de fincas y lotes | Hecho ahora | Migración `20261010000000_farms_and_lots.sql` (aplicada): `farm` y `product_lot`, vistas `farm_catalog` y `lot_catalog`, RLS, escritura por funciones, auditoría; lotes inmutables y sin borrado | País como código de 2 letras sin catálogo `country`; un lote exige producto y finca activos |
| **515** [BD] Validar las coordenadas | Hecho ahora | `CHECK` en la tabla (rango, par completo, no (0, 0)) y validación en las funciones con mensajes claros (rango, máximo 6 decimales, número); `farms_lots.sql` 98/98 | Rechazar el punto (0, 0) y limitar a 6 decimales son decisiones propias por confirmar |

Los permisos `farms.read`, `farms.create`, `farms.update`, `lots.read` y `lots.create` no se asignaron a ningún rol. Para registrar un lote hacen falta también `products.read` y `farms.read` (alimentan los selectores); para registrar una finca, `suppliers.read`.

## Mapas y captura de coordenadas (PLAT-516 a 519)

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **516** [APP] Integrar el servicio de mapas en Flutter | Hecho ahora | Paquetes `flutter_map` y `latlong2` con mosaicos de OpenStreetMap (sin clave de API); capa de mosaicos sustituible (`tileLayerBuilder`). Se añadió el permiso `INTERNET` al manifiesto principal de Android: sin él la app de release no podía conectar ni con Supabase | **OpenStreetMap es un servidor comunitario con política de uso razonable**: vale para desarrollo y uso moderado; en producción con mucho tráfico hay que cambiar de proveedor. No probado en emulador ni dispositivo |
| **517** [APP] Selector de ubicación en mapa | Hecho ahora | `location_picker_screen`: se toca el mapa, aparece el marcador y las coordenadas, y "Usar esta ubicación" las lleva al formulario de finca ("Elegir en el mapa"), tanto al registrar como al editar. Las coordenadas se normalizan (6 decimales, longitud en -180..180, latitud en -90..90) y siguen validándose en el formulario y en la base | Sin GPS del dispositivo ni búsqueda de direcciones; no se puede escribir un punto exacto en el mapa (para eso están los campos de texto) |
| **518** [QA] Probar la captura de coordenadas | Hecho ahora | `location_picker_test.dart` (14 pruebas: normalización, tocar y mover el punto, confirmar y cancelar, punto inicial, integración con el formulario) y `farms_lots_test.dart` (validación) | El recorrido por el router con el mapa real (con mosaicos) no se probó: las pruebas usan un mapa sin mosaicos |
| **519** Asociar un lote de producto a una finca | Hecho (junto con 513 y 514) | `create_lot` y `lot_form`: un lote exige finca y producto activos, el código es único por finca; la finca cuenta sus lotes y el lote muestra la geolocalización de su finca | — |

## Lotes, mapa de envíos y trazabilidad por exportación (PLAT-520 a 523)

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **520** [BD] Tabla de lotes de producto | Hecho (junto con 514) | `product_lot` en `20261010000000_farms_and_lots.sql` (aplicada): producto y finca obligatorios, código único por finca, inmutable y sin borrado, auditado | Sin fecha de cosecha (el modelo no la define) |
| **521** [APP] Pantalla de lotes | Hecho (junto con 513 y 519) | `LotListScreen` (búsqueda por código, origen y geolocalización de cada lote, paginación) y `LotFormScreen` | — |
| **522** Visualizar las fincas de un envío en el mapa | **Parcial** | `FarmsMapScreen`: un marcador por finca, datos al tocarlo, encuadre automático y aviso de las fincas sin punto; hoy se abre desde "Fincas > Ver fincas en el mapa" con todas las fincas activas | **No existe aún el módulo de envíos ni de exportaciones**, así que no se puede abrir "las fincas de un envío". La pantalla recibe cualquier lista de fincas: cuando existan, se alimenta con `export_origin_farms` |
| **523** [BD] Vista de trazabilidad por exportación | **Parcial (borrador validado, no aplicado)** | `database/drafts/export_traceability.sql`: vistas `export_traceability` (línea de exportación → lote → producto → finca con punto → proveedor, con cantidad y HS) y `export_origin_farms` (fincas por exportación con cantidad y lotes). `draft_export_traceability.sql` 22/22 sobre tablas de prueba | **Las tablas `export` y `export_line` no existen** (dependen de clientes, pedidos, monedas, países e Incoterms). Se aplica como migración cuando existan; la prueba se niega a ejecutarse si ya existen, para no pisarlas. Supuesto: un envío pertenece a una exportación |

## Clientes, EORI y mapa de trazabilidad (PLAT-524, 526 a 528)

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **524** [APP] Vista de mapa de trazabilidad | **Parcial** | `TraceabilityMapScreen`: dibuja las fincas de origen de las líneas que recibe y, al tocar una, sus lotes y cantidades. Hoy se abre desde "Lotes > Ver origen en el mapa" (el origen de un lote). 9 pruebas nuevas | **La trazabilidad por exportación no se puede abrir todavía**: no existen exportaciones. La pantalla ya acepta las filas de `export_traceability` (borrador de la 523) |
| **526** Registrar un cliente | Hecho ahora | `customer_list_screen` y `customer_form_screen` (alta, edición, inactivar, reactivar, búsqueda por nombre o EORI); funciones `create_customer`, `update_customer`, `set_customer_active`; auditoría | Sin historial de pedidos y exportaciones del cliente (RF-15): esos módulos no existen |
| **527** [BD] Tabla de clientes | Hecho ahora | Migración `20261013000000_customers_module.sql` (aplicada): `customer`, RLS, escritura por funciones, sin borrado, auditoría; `customers.sql` 74/74 | País y moneda como códigos ISO sin catálogos `country`/`currency` (aún no existen); moneda preferida obligatoria, como exige el modelo |
| **528** [BD] Validar el formato de EORI | Hecho ahora | `CHECK` en la tabla y validación en las funciones con mensajes claros: formato (2 letras de país + 1 a 15 alfanuméricos), normalización (mayúsculas, sin espacios, guiones ni puntos), unicidad tras normalizar, prefijo igual al país (Grecia `EL`; Reino Unido `GB` o `XI`) y **obligatorio en los 27 países de la UE**. El mismo validador está en la app (`validateEori`) para avisar antes de enviar | **Reglas por país son supuestos a confirmar**: el backlog deja abierta la obligatoriedad del EORI. No se comprueban dígitos de control ni se consulta el servicio oficial de validación de la UE |

La tabla `customer` ya existe de verdad, así que se retiró del borrador de políticas (`drafts/domain_policies.sql`) y sus pruebas la usan real (`draft_policies` 55/55, `client_isolation` 33/33, `policies_by_role` 240/240). Los permisos `customers.read`, `customers.create` y `customers.update` no se asignaron a ningún rol.

## Cuentas de cliente, búsqueda e historial comercial (PLAT-529 a 536)

Los títulos de 529, 530, 534, 535 y 536 aparecían truncados en la captura; esta es la interpretación aplicada (corregir si el alcance era otro): 529 "enlazar el cliente con su cuenta (de usuario)", 530 "construir el formulario (de cliente)", 534 "consultar el historial comercial del cliente", 535 "crear la vista del historial del cliente" y 536 "construir la vista de historial".

| Tarea | Estado | Dónde / evidencia | Salvedad |
|---|---|---|---|
| **529** [BD] Enlazar el cliente con su cuenta | Hecho ahora | Migración `20261014000000_customer_user_link.sql` (aplicada): tabla `customer_user` (N:M), permiso `portal.read`, funciones `link_customer_user` y `unlink_customer_user` (por correo, solo con `customers.update`), vista `customer_account_link`, auditoría; `customer_links.sql` 45/45 | Por confirmar: varios clientes por cuenta y varias cuentas por cliente; solo el personal vincula. Las políticas que limitan lo que ve cada cliente externo siguen en `drafts/client_isolation.sql` (sin tablas de pedidos aún) |
| **530** [APP] Formulario | Hecho (con 526) | `customer_form_screen` (alta y edición, EORI con ayuda y validación según el país). Además, `customer_accounts_screen` para vincular y desvincular cuentas por correo | Si 530 era otro formulario, indicarlo |
| **531** [QA] Probar la validación de EORI | Hecho (con 528) | `customers.sql` (EORI: formato, prefijo, obligatoriedad UE, unicidad, `CHECK` directos) y `customers_test.dart` (helper, backend local, cliente Supabase, formulario) | — |
| **532** Consultar y buscar clientes | Hecho | Búsqueda por nombre o EORI (aunque se escriba con espacios), filtro por país y por estado, paginación | — |
| **533** [APP] Pantalla de lista de clientes | Hecho (con 526) | `customer_list_screen`; quien solo lee no ve editar ni inactivar | — |
| **534** Consultar el historial comercial | **Parcial** | Opción "Historial comercial" en cada cliente; `GET /customers/{id}/history` | **No existen pedidos ni exportaciones**: hoy muestra un aviso. Se llena cuando existan esos módulos |
| **535** [BD] Vista del historial del cliente | **Parcial (borrador validado, no aplicado)** | `drafts/customer_history.sql`: `customer_order_history` (pedidos con total derivado de las líneas y exportaciones) y `customer_export_history`; `draft_customer_history.sql` 22/22 sobre tablas de prueba | Las tablas `customer_order`, `order_line` y `export` no existen; la prueba se niega a ejecutarse si ya existen |
| **536** [APP] Vista de historial | **Parcial** | `customer_history_screen` (pedidos con total y exportaciones, estados vacío, de error y "aún no disponible"); 4 pruebas de pantalla | Solo se verá información cuando se aplique la 535 |

Los permisos `customers.*` y `portal.read` no se asignaron a ningún rol. Para que un cliente externo vea algo, su cuenta necesita un rol con `portal.read` (la lista de cuentas lo avisa).

## Lo que sigue pendiente en este tramo

1. **Probar con una cuenta real en Supabase** (crear la cuenta, darle un rol con `products.*`, registrar un producto y recuperar el acceso por correo): ninguna verificación contra el servicio real pudo completarse sin una cuenta.
2. **Empujar la plantilla de recuperación** y la configuración de Auth al proyecto alojado, y configurar un SMTP propio.
3. **Asignar permisos de producto a un rol**: no se concedieron a ninguno (ni al administrador); se hace desde la pantalla de roles.
4. **Foto de perfil** (tarea 488).
5. **Decisiones del cliente** que afectan a productos: unicidad, inmutabilidad del tipo y la unidad, formato y fuente del código HS, conversión entre unidades.
6. **Probar la interfaz en el emulador:** la última sesión no tuvo Internet; las pantallas se verificaron con pruebas de widget.
