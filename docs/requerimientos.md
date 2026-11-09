# Requerimientos del sistema

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.3 - actualización por backend en Flutter + Supabase  
**Estado:** Base revisada contra backlog y contra lo implementado; pendiente de aprobación docente/cliente  
**Última actualización:** 2026-10-08 (ver sección 9, registro de cambios)  
**Fuente principal:** `product_backlog_corregido.csv`, Épica 0 y épicas funcionales relacionadas.

## 1. Propósito

Establecer una base verificable para el alcance de la plataforma que administra productos de café y cacao y acompaña su comercialización y exportación. Este documento cubre los requerimientos funcionales y no funcionales derivados del backlog. No define todavía historias de usuario detalladas, modelo de datos, arquitectura ni implementación.

## 2. Alcance del producto

La plataforma permitirá administrar usuarios y permisos, catálogo de productos, proveedores y fincas, clientes, pedidos, exportaciones, documentos, inventario, pagos, logística, notificaciones e informes. La aplicación se plantea para Android, iOS y Web con Flutter. Desde la versión 0.3 el backend vive dentro de la aplicación (capa `lib/backend`, que expone servicios con el mismo contrato de rutas) y se apoya en **Supabase**: Supabase Auth para credenciales y sesión, PostgreSQL para los datos y políticas RLS y triggers para aplicar permisos y reglas de negocio en la base. No hay un servidor de aplicación propio.

Las funciones de diligencia debida EUDR, códigos arancelarios, documentos de exportación y tratamiento de datos personales requieren validación del docente/cliente y de las fuentes normativas aplicables antes de considerarse aptas para uso comercial o cumplimiento legal.

## 3. Actores

- **Visitante (sin sesión):** crea su propia cuenta desde la pantalla de inicio de sesión.
- **Cliente:** rol con el que nace toda cuenta autoregistrada; accede a su perfil y solo a los módulos que su rol autorice.
- **Administrador:** gestiona usuarios, roles y permisos.
- **Usuario comercial:** administra productos, clientes, pedidos y exportaciones según sus permisos.
- **Usuario operativo:** consulta o actualiza inventario, documentos y logística según sus permisos.
- **Usuario autenticado:** accede a su perfil y a los módulos autorizados.

Los nombres definitivos de roles y la matriz de permisos quedan por acordar. Los actores comercial y operativo son perfiles iniciales derivados de los módulos del backlog, no roles rígidos del sistema.

## 4. Requerimientos funcionales

Cada requerimiento tiene un identificador estable y criterios de aceptación iniciales. Los criterios refinan las historias y tareas del backlog; deben confirmarse con el cliente antes de cerrar su alcance.

### Usuarios y acceso

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-01 | El sistema permitirá iniciar sesión con correo electrónico y contraseña. | Credenciales válidas abren una sesión; credenciales inválidas no conceden acceso y muestran un mensaje que no revela si existe una cuenta; una cuenta desactivada o con rol inactivo no inicia sesión y no conserva acceso a datos aunque tenga un token (el bloqueo lo aplica la base, no solo la app); si el correo exige confirmación, tras validar la contraseña el sistema lo indica sin conceder acceso; el usuario puede cerrar sesión y la sesión se revoca en el servidor. |
| RF-02 | Cualquier persona podrá crear su propia cuenta desde la pantalla de inicio de sesión (“¿No tienes una cuenta? Regístrate”), sin sesión previa y sin elegir rol. | Se validan nombres, apellidos, correo y contraseña (con confirmación); el correo no se duplica; la cuenta se crea siempre con el rol de menor privilegio (`cliente`), aunque la solicitud intente indicar otro; el formulario no ofrece selección de rol; el usuario es informado si debe confirmar su correo. |
| RF-03 | El administrador podrá consultar, buscar, editar y desactivar usuarios, incluido el cambio de rol. El listado muestra el nombre del rol y la búsqueda es por nombre, apellido o correo, con filtro por estado y paginación. | Los cambios quedan persistidos; el administrador no edita el correo de otros usuarios (solo su titular, RF-06); no puede desactivarse a sí mismo ni dejar al sistema sin un administrador activo; el rol destino debe estar activo; cambiar el rol de un usuario exige un permiso propio (`users.assign_role`), nadie cambia su propio rol y asignar o quitar el rol administrador solo lo hace un administrador; cada cambio de rol queda registrado en la auditoría (actor, usuario, rol origen y destino); una cuenta desactivada no inicia sesión y sus acciones previas se conservan. |
| RF-04 | El administrador podrá crear y editar roles y sus permisos por módulo. | Los permisos configurados determinan qué módulos y operaciones puede usar cada usuario; un usuario sin permiso recibe acceso denegado; la interfaz solo muestra los módulos para los que el rol tiene permiso y la base de datos rechaza las operaciones no permitidas aunque se invoquen directamente; el rol `administrador` no se renombra ni desactiva y conserva sus permisos de gestión; un rol con usuarios activos no se desactiva. |
| RF-05 | El usuario podrá solicitar la recuperación de contraseña por correo. | El sistema permite iniciar el flujo sin revelar la existencia de la cuenta; el enlace o código tiene vigencia limitada y solo puede utilizarse según las reglas acordadas. |
| RF-06 | El usuario podrá consultar y editar su perfil, incluidos nombre, foto y datos de contacto, y cambiar su propio correo electrónico. | Se muestran los datos propios; los cambios se validan y guardan; el usuario no puede modificar perfiles ajenos mediante esta función; el cambio de correo exige confirmar un enlace enviado al correo nuevo y, hasta entonces, se conserva el anterior; se rechazan correos ya registrados o iguales al actual. |

### Catálogo de productos

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-07 | El usuario autorizado podrá registrar productos de café con variedad, calidad, humedad y código HS. | El formulario diferencia café de cacao, valida campos obligatorios y conserva los valores registrados. |
| RF-08 | El usuario autorizado podrá registrar productos de cacao con variedad, tipo de grano y porcentaje de fermentación. | El porcentaje acepta únicamente valores dentro del rango definido con el cliente; los demás atributos se validan antes de guardar. |
| RF-09 | El usuario autorizado podrá asociar una o varias certificaciones a un producto. | Se pueden seleccionar certificaciones disponibles, incluidas orgánico, Fair Trade y Rainforest Alliance; el producto muestra sus certificaciones asociadas. |
| RF-10 | El usuario autorizado podrá editar, inactivar, listar y filtrar productos. | La búsqueda permite filtrar como mínimo por tipo, calidad y certificación; un producto inactivo no se ofrece para nuevas operaciones, pero su historial permanece consultable. |

### Proveedores, fincas y trazabilidad

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-11 | El usuario autorizado podrá registrar proveedores con información de contacto y ubicación. | Los datos obligatorios se validan; el proveedor queda disponible para asociarlo a fincas/lotes. |
| RF-12 | El usuario autorizado podrá registrar fincas o lotes de un proveedor con coordenadas geográficas. | Cada finca/lote queda asociado a un proveedor; latitud y longitud se validan dentro de rangos geográficos válidos. |
| RF-13 | El usuario autorizado podrá asociar lotes de producto a fincas. | Se puede consultar la relación entre producto/lote y finca de origen para seguir la trazabilidad. |
| RF-14 | El usuario autorizado podrá visualizar fincas en un mapa. | El mapa representa las coordenadas registradas y permite identificar las fincas relacionadas con el envío seleccionado; proveedor de mapas y funcionamiento sin conexión quedan por definir. |

### Clientes y pedidos

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-15 | El usuario autorizado podrá registrar, editar, desactivar, buscar y consultar clientes. | Se registran país, EORI y moneda preferida; la búsqueda admite nombre, país o EORI; el historial muestra pedidos y exportaciones asociados. Las reglas de obligatoriedad del EORI dependen del país y deben validarse. |
| RF-16 | El usuario autorizado podrá registrar pedidos con cliente, producto, cantidad y precio, y consultar, filtrar y editar pedidos pendientes. | Se validan los datos requeridos; el listado permite filtrar por cliente, producto o estado; solo se editan pedidos pendientes. El soporte de varios productos por pedido se propone en el modelo y debe confirmarse. |
| RF-17 | El usuario autorizado podrá cambiar el estado de un pedido. | El sistema reconoce los estados pendiente, confirmado, en proceso y exportado; solo permite transiciones autorizadas y refleja el estado actualizado en listados e historial. La matriz exacta de transiciones y roles debe aprobarse. |

### Exportaciones y documentos

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-18 | El usuario autorizado podrá registrar una exportación asociada a un pedido, indicando cantidad, país de destino, Incoterm y fecha. | No se registra una exportación sin pedido asociado ni con datos obligatorios inválidos; el detalle permite consultar los datos guardados. |
| RF-19 | El sistema propondrá o calculará el código arancelario HS del producto exportado. | El código se obtiene conforme a reglas y fuente oficial aprobadas; el usuario puede revisar el resultado antes de formalizar la exportación; los casos ambiguos se señalan para revisión. |
| RF-20 | El usuario autorizado podrá generar la declaración de diligencia debida EUDR de una exportación. | El documento utiliza la información de origen y trazabilidad disponible; señala datos faltantes y permite identificar la exportación a la que corresponde. Su validez normativa debe ser revisada por el cliente. |
| RF-21 | El usuario autorizado podrá consultar y filtrar el historial de exportaciones por cliente, país o fecha. | Los filtros se pueden combinar y el resultado solo incluye exportaciones permitidas por el rol del usuario. |
| RF-22 | El usuario autorizado podrá generar factura comercial, packing list y certificado de origen EUR.1, y adjuntar certificados fitosanitarios. | Cada archivo queda asociado a su exportación/expediente; los archivos generados se pueden descargar y los adjuntos se pueden consultar por usuarios autorizados. |
| RF-23 | El usuario autorizado podrá consultar el expediente documental de una exportación. | El expediente presenta los documentos asociados, su tipo y disponibilidad; se informa cuando un documento requerido aún no existe. |

### Inventario, pagos y logística

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-24 | El usuario autorizado podrá consultar existencias disponibles de café y cacao. | El inventario se consulta por producto y lote, mostrando cantidad y unidad acordadas. |
| RF-25 | El sistema actualizará automáticamente el inventario al confirmar pedidos o exportaciones y notificará niveles bajos. | Los movimientos de inventario corresponden a la operación confirmada; el umbral de stock bajo se define según el producto. Deben acordarse reservas, reversos y prevención de stock negativo. |
| RF-26 | El usuario autorizado podrá registrar pagos asociados a pedidos, indicando monto, moneda y fecha, y consultar pagos pendientes o vencidos. | Los pagos se asocian a un pedido; para determinar vencimiento se requiere definir fecha límite y si se permiten abonos. |
| RF-27 | El sistema convertirá automáticamente el monto a una moneda base usando una tasa de cambio actualizada. | Se conserva importe y moneda originales junto con tasa, moneda base, proveedor y fecha/hora de consulta para hacer reproducible la conversión. La moneda base y frecuencia de actualización están por acordar. |
| RF-28 | El usuario autorizado podrá registrar transportista y guía/BL, actualizar el estado logístico y consultar su línea de tiempo. | Se soportan los estados preparación, tránsito, aduana y entregado; cada evento registra fecha/hora y queda asociado a un envío de una exportación. |

### Notificaciones, informes e interfaz

| ID | Requerimiento | Criterios de aceptación |
|---|---|---|
| RF-29 | El sistema notificará stock bajo y pagos próximos a vencer. | La notificación identifica el elemento relacionado, el motivo y la fecha; no se genera repetidamente fuera de las reglas acordadas. |
| RF-30 | El usuario podrá consultar un centro de notificaciones in-app y recibir notificaciones push cuando estén habilitadas. | El centro lista notificaciones y permite distinguir leídas de no leídas; la entrega push depende de permisos del dispositivo y configuración del servicio. |
| RF-31 | El usuario autorizado podrá generar reportes de exportaciones filtrados por producto, cliente o país y visualizar gráficas de ventas/exportaciones por periodo. | Los totales corresponden a los datos de origen y respetan permisos; cada reporte indica filtros y periodo aplicados. |
| RF-32 | El sistema mostrará un dashboard con indicadores clave y contenido acorde al rol. | Cada indicador tiene definición y periodo visibles; el usuario solo ve información autorizada para su rol. |
| RF-33 | La interfaz ofrecerá flujos responsivos y componentes visuales consistentes en Android, iOS y Web. | Las funciones incluidas en cada entrega se pueden completar en los tres entornos objetivo; wireframes y guía de estilos se validarán antes de implementar las pantallas. |

## 5. Requerimientos no funcionales

Los objetivos marcados **Propuesta por validar** no están fijados por el backlog y requieren aprobación del docente/cliente. Se distinguen de los compromisos explícitos del backlog para evitar presentarlos como acuerdos ya aprobados.

| ID | Atributo | Requerimiento / criterio de verificación | Estado |
|---|---|---|---|
| RNF-01 | Seguridad de transporte | Toda comunicación entre la aplicación y Supabase debe usar HTTPS con TLS vigente; no se deben transmitir credenciales ni documentos en texto plano. | Explícito en backlog; TLS lo provee Supabase. |
| RNF-02 | Seguridad de credenciales | Las contraseñas deben almacenarse mediante hash adaptativo con salt (bcrypt, gestionado por Supabase Auth). La aplicación nunca almacena ni registra contraseñas en claro. | Explícito en backlog; cumplido delegando el hash a Supabase Auth. |
| RNF-03 | Control de acceso | Las vistas deben aplicar autenticación y permisos por rol, y la base de datos debe aplicarlos de forma independiente (RLS y triggers) validando el JWT de Supabase antes de cada operación protegida. Ocultar opciones en la interfaz es solo una comodidad, no un control de seguridad. | Explícito en backlog. Vigencia, renovación y revocación de tokens por definir (hoy: expiración del JWT de Supabase). |
| RNF-04 | Privacidad | El tratamiento de datos personales debe aplicar minimización, finalidad, acceso restringido, retención definida y mecanismos para atender solicitudes de titulares, conforme al análisis GDPR aplicable al producto. | Buenas prácticas GDPR explícitas; bases legales, plazos y responsable deben validarse con cliente/asesoría. |
| RNF-05 | Cifrado de datos | Los datos sensibles y documentos almacenados deben protegerse en reposo, además de protegerse durante el transporte. | Propuesta por validar; el backlog solo menciona expresamente HTTPS y cifrado de contraseñas. |
| RNF-06 | Rendimiento | La generación de reportes y PDF no debe superar 5 segundos bajo condiciones normales. La prueba debe documentar volumen de datos, concurrencia y entorno. | Umbral explícito en backlog; condiciones de prueba deben acordarse. |
| RNF-07 | Rendimiento de operaciones | **Propuesta:** al menos el 95 % de las operaciones de consulta/guardado comunes debe responder en 2 segundos o menos bajo carga acordada. | Propuesta por validar; fijar concurrencia y conjunto de datos de prueba. |
| RNF-08 | Disponibilidad | **Propuesta:** disponibilidad mensual de 99,5 % para el backend en producción, excluyendo ventanas de mantenimiento anunciadas. | Propuesta por validar; aplica cuando exista entorno productivo. |
| RNF-09 | Copias de seguridad | La base de datos debe tener respaldos automáticos periódicos, protegidos contra acceso no autorizado, con restauraciones de prueba documentadas. | Respaldos explícitos; dependen del plan de Supabase contratado; frecuencia, retención, RPO y RTO por acordar. |
| RNF-10 | Compatibilidad | La aplicación debe probarse en Android, iOS y navegadores Web objetivo definidos con el cliente; las pruebas deben cubrir flujos principales y resoluciones representativas. | Plataformas explícitas; versiones/dispositivos/navegadores por acordar. |
| RNF-11 | Integridad y trazabilidad | Las relaciones entre pedido, exportación, producto/lote, finca, documentos, pagos y envío deben conservar integridad; las operaciones confirmadas no deben producir actualizaciones parciales incoherentes. | Derivado del alcance del backlog; reglas transaccionales por concretar en diseño. |
| RNF-12 | Auditoría | Los cambios sensibles (usuarios/permisos, pedidos, exportaciones, inventario, pagos y documentos) deben dejar registro de actor, acción y fecha/hora, sin incluir secretos. | El backlog pide logs de auditoría; eventos, retención y acceso al log por acordar. **Avance (2026-10-08):** los cambios de rol ya se auditan en `audit_log` (append-only, solo ids y nombres de rol); faltan desactivaciones, permisos de roles y una pantalla de consulta. |
| RNF-13 | Usabilidad | Formularios deben validar campos y mostrar errores accionables; los flujos principales deben poder completarse con teclado táctil o físico según plataforma. | Criterio inicial derivado; validar con wireframes y pruebas de usuario. |
| RNF-14 | Accesibilidad | **Propuesta:** apuntar a WCAG 2.2 nivel AA para la interfaz Web y aplicar criterios equivalentes de contraste, foco, etiquetas y lector de pantalla en móvil. | Propuesta por validar; no aparece como compromiso explícito en el backlog. |
| RNF-15 | Mantenibilidad e interoperabilidad | El contrato de servicios del backend debe estar documentado (rutas, entradas, salidas) junto con el esquema de base versionado (`database/migrations/`); los errores usan un formato uniforme (`code`, `message`, `details`, `request_id`) en todos los módulos. | El backlog pedía OpenAPI/Swagger, que deja de aplicar al no existir servidor FastAPI; criterio sustituto por validar. |
| RNF-16 | Normativa comercial | La generación de documentos, clasificación HS y declaración EUDR debe usar reglas y fuentes vigentes identificables, y permitir revisión humana antes de emitir resultados críticos. | Necesidad derivada del backlog; fuentes, responsable de actualización y aprobación legal por validar. |
| RNF-17 | Idioma y formatos | **Propuesta:** interfaz inicial en español; fechas, separadores numéricos, zonas horarias y monedas deben mostrarse de forma inequívoca y guardar moneda/fecha con formato normalizado. | Propuesta por validar; operación en Colombia/UE sugiere múltiples formatos y monedas. |
| RNF-18 | Gestión de secretos | La aplicación solo incluye la clave pública (anon/publishable) de Supabase; la clave `service_role` y la cadena de conexión a la base no se incluyen en la aplicación ni en el repositorio. Los valores viven en `.env` (no versionado); no hay plantilla en el repositorio. | Nuevo en 0.3; deriva de la decisión de backend en Flutter + Supabase. |
| RNF-19 | Tolerancia a indisponibilidad | Si Supabase no responde, la aplicación debe fallar sin cerrarse: aplica un tiempo máximo de espera, informa el error con un mensaje accionable y permite reintentar. | Nuevo en 0.3; tiempo máximo actual de 15 s, por validar. |

## 6. Supuestos y decisiones pendientes

1. Confirmar usuarios objetivo, nombres de roles y matriz de permisos por módulo/operación.
2. Definir campos obligatorios, unidades de medida y rangos válidos para productos, clientes, pedidos, lotes, pagos e inventario.
3. Acordar flujo y estados válidos de pedidos, exportaciones, pagos y envíos, así como quién puede cambiar cada estado.
4. Validar el alcance legal y las fuentes para EUDR, códigos HS y documentos EUR.1/fitosanitarios; precisar si la plataforma genera documentos oficiales o borradores para revisión.
5. Elegir proveedores externos para mapas, correo de recuperación, push, tasas de cambio y almacenamiento de archivos; acordar costos y manejo de fallos.
6. Definir volúmenes esperados, concurrencia, retención de datos, disponibilidad, política de respaldo, RPO y RTO.
7. Confirmar navegadores, versiones de Android/iOS, dispositivos y resoluciones que se soportarán.
8. Definir si pagos son solo registro/seguimiento o si se integrará una pasarela de pago.
9. Acordar idioma, monedas, zona horaria, accesibilidad y requisitos de exportación de reportes.

## 7. Validación de requerimientos

### Resultado de revisión

Se verificó que cada capacidad incluida tenga correspondencia con historias o tareas del backlog y que los requisitos estén expresados como comportamiento observable. La revisión confirma cobertura documental, pero no sustituye la validación con usuarios, docente o cliente. Los RNF con estado **Propuesta por validar** son metas candidatas, no compromisos aprobados.

| Grupo | Resultado | Evidencia del backlog |
|---|---|---|
| RF-01 a RF-06 | Correspondencia confirmada; criterios de seguridad y unicidad amplían la historia y deben aprobarse. | Iniciar sesión, registrar/editar/desactivar usuarios, roles, recuperación de contraseña y perfil en Autenticación y Gestión de Usuarios. |
| RF-07 a RF-10 | Correspondencia confirmada. Atributos específicos de café/cacao y filtros aparecen en sus historias. | Registrar café/cacao, certificaciones, edición/inactivación y filtros en Gestión de Productos. |
| RF-11 a RF-14 | Correspondencia confirmada; queda por decidir si una finca contiene varios lotes y cómo se relaciona el mapa con cada envío. | Proveedores, fincas/lotes, geolocalización, asociación de lotes y mapa en Trazabilidad EUDR. |
| RF-15 a RF-17 | Correspondencia confirmada; país/EORI/moneda y estados están en el backlog. Quedan por acordar obligatoriedad del EORI, estructura de varios productos y transiciones permitidas. | Clientes por nombre/país/EORI; pedidos con cliente/producto/cantidad/precio y estados pendiente, confirmado, en proceso y exportado. |
| RF-18 a RF-23 | Correspondencia confirmada; HS, EUDR y documentos dependen de reglas y fuentes oficiales que aún no están identificadas. | Registro e historial de exportaciones, HS automático, declaración EUDR, factura, packing list, EUR.1, certificado fitosanitario y expediente. |
| RF-24 a RF-28 | Correspondencia confirmada; el backlog precisa actualización al confirmar pedido/exportación y estados logísticos. Umbral de stock, vencimiento, moneda base y proveedor FX siguen pendientes. | Inventario por producto/lote; pagos; conversión a moneda base; transportista/guía y estados preparación, tránsito, aduana y entregado. |
| RF-29 a RF-33 | Correspondencia confirmada; reglas anti-repetición y catálogo de KPI requieren acuerdo. | Notificaciones de stock/pagos, centro leído/no leído, reportes filtrados por producto/cliente/país, gráficas por periodo, dashboard por rol e interfaz responsiva. |
| RNF-01 a RNF-04, RNF-06, RNF-09, RNF-10, RNF-12, RNF-15 | Base explícita en tareas del backlog; varios criterios de aceptación necesitan parámetros operativos. | HTTPS/hash, buenas prácticas GDPR, límite de 5 s, backups, pruebas Android/iOS/Web, logs de auditoría y OpenAPI. |
| RNF-05, RNF-07, RNF-08, RNF-11, RNF-13, RNF-14, RNF-16, RNF-17 | Derivados o propuestos; requieren decisión explícita del docente/cliente antes de convertirse en criterios contractuales. | Necesidades transversales inferidas del alcance; no tienen umbral o compromiso explícito en el backlog. |

### Hallazgos que requieren decisión

1. **Clasificación HS:** RF-07 almacena un código HS del producto y RF-19 pide calcularlo automáticamente para la exportación. Definir si el sistema propone el código desde el producto, si cada exportación puede sobrescribirlo y qué fuente/versión arancelaria prevalece.
2. **Estados y reglas de negocio:** el backlog enumera estados para pedidos y logística, pero no las transiciones permitidas ni los estados de exportación/pago. Definir roles autorizados y condiciones de cierre/cancelación.
3. **Inventario:** el backlog fija actualización al confirmar pedido o exportación. Especificar cantidades descontadas en cada evento, unidades, reservas, reversos y reglas para impedir stock negativo.
4. **Criterio de rendimiento:** el límite de 5 segundos para reportes/PDF es verificable solo después de acordar volumen de datos, concurrencia, hardware y qué intervalo se mide. El objetivo RNF-07 de 2 segundos sigue siendo propuesta.
5. **Datos personales y normativa:** identificar responsable del tratamiento, usuarios afectados, base legal, retención y proceso de atención de solicitudes; validar alcance GDPR y EUDR con el cliente/asesoría.
6. **Respaldos:** fijar frecuencia, retención, cifrado, ubicación, RPO, RTO y periodicidad de las pruebas de restauración.
7. **Integraciones externas:** elegir correo, mapas, tasas de cambio, almacenamiento de archivos y push, con política ante indisponibilidad, costos y credenciales.
8. **Actores y alcance de pago:** aprobar matriz de permisos; confirmar si pagos solo se registran o si se integrará una pasarela.
9. **Registro de usuarios:** *resuelto en 0.3* — se adopta el autorregistro público con rol `cliente` (RF-02); el administrador solo consulta, edita y desactiva (RF-03). Pendiente confirmar con el docente/cliente.

**Dictamen (v0.2):** los requisitos son aptos como línea base para continuar el análisis y el diseño modular. No se consideran aprobados para desarrollo hasta resolver los hallazgos de negocio y aceptar expresamente las propuestas no funcionales.

## 8. Trazabilidad con el backlog

Los requerimientos RF-01 a RF-06 corresponden a **Autenticación y Gestión de Usuarios**; RF-07 a RF-10 a **Gestión de Productos**; RF-11 a RF-14 a **Proveedores y Fincas**; RF-15 a RF-17 a **Clientes y Pedidos**; RF-18 a RF-23 a **Exportaciones y Gestión Documental**; RF-24 a RF-28 a **Inventario, Pagos y Logística**; RF-29 a RF-33 a **Notificaciones, Reportes, Diseño de Interfaces y Backend**. Los RNF reflejan la épica **Requisitos No Funcionales** y las necesidades transversales del producto.

Este documento atiende las actividades excepcionales de **levantamiento y validación de requerimientos**. No desarrolla la actividad separada **“Definir historias de usuario”** ni las tareas de modelo entidad-relación o creación de base de datos.

## 9. Registro de cambios y validación contra lo implementado

### 9.1 Cambios de la versión 0.3 (2026-10-08)

| Cambio | Motivo | Requerimientos afectados |
|---|---|---|
| El backend deja de ser una API FastAPI y pasa a una capa dentro de la app Flutter sobre Supabase (Auth + PostgreSQL con RLS y triggers). | Decisión del equipo; elimina el servidor propio y su despliegue. | Alcance; RNF-01, 02, 03, 09, 15, 18, 19 |
| Registro de usuarios público (autorregistro), sin elegir rol; toda cuenta nace como `cliente`. | Quien se registra no tiene sesión; no existe alta administrativa. | RF-02, RF-03; actor Visitante y Cliente |
| El administrador ya no cambia el correo de otros usuarios; lo cambia el titular con confirmación por enlace. | El correo es la credencial de Supabase Auth; cambiar el de otro exige la clave `service_role`, que no puede ir en la app. | RF-03, RF-06 |
| La interfaz muestra solo los módulos permitidos por el rol, y la base aplica los permisos por su cuenta. | Evitar opciones inútiles sin confiar la seguridad al cliente. | RF-04, RNF-03 |
| Se añaden RNF de secretos e indisponibilidad; se sustituye el criterio OpenAPI. | Riesgos propios del nuevo modelo. | RNF-15, 18, 19 |

### 9.2 Estado de verificación por requerimiento

Cobertura de lo ya construido (módulo de Autenticación y Gestión de Usuarios). Los demás RF no tienen implementación todavía.

| ID | Estado | Evidencia |
|---|---|---|
| RF-01 | Implementado; verificado parcialmente | 63 pruebas automatizadas, incluidas las de sesión (restauración, vencimiento, cierre por `401`, guarda de rutas, cierre de sesión con revocación) y 57 de la base (bloqueo de desactivados). En emulador Android se verificó el rechazo de credenciales falsas contra Supabase. Falta el inicio de sesión exitoso con una cuenta real. Detalle en `qa-autenticacion-registro.md`. |
| RF-02 | Implementado; verificado parcialmente | Pruebas automatizadas (validaciones, sin rol, contraseña débil y correo inválido con las respuestas reales de Supabase). En la base se verificó que el trigger asigna siempre el rol `cliente`. Falta un registro real de extremo a extremo (confirmación de correo) y el caso de correo duplicado con Supabase. Detalle en `qa-autenticacion-registro.md`. |
| RF-03 | Implementado; reglas de base probadas con sesiones simuladas | Pruebas automatizadas de listado, edición y desactivación. Las reglas de la base (no autodesactivarse, último administrador, rol activo) se ejercitaron el 2026-10-08 con sesiones simuladas (`database/tests/rules.sql`, 31 pruebas); falta repetirlas con sesiones reales. |
| RF-04 | Implementado; verificado parcialmente | Pruebas automatizadas y visibilidad de módulos por permiso. Se verificó que la clave pública no puede leer tablas (RLS). |
| RF-05 | Implementado; sin probar con correo real | Solicitud y canje del código de 6 dígitos (pantallas, rutas y backends), respuesta neutra y un solo uso; 8 pruebas automatizadas y los errores reales de Supabase para un código falso (`403 otp_expired`). La plantilla del correo está en `supabase/templates/recovery.html` pero **no se ha empujado** al proyecto alojado, y el envío real no se probó (consume el límite de correos de Supabase). ADR-031. |
| RF-06 | Parcial | Implementado: ver el perfil, **editar nombres y teléfono propios** y cambiar el correo con confirmación (pruebas automatizadas; la base lo permite y lo limita al titular, verificado con `database/tests/rules.sql`). Pendiente: la foto de perfil (bucket creado, sin pantalla). |
| RF-07 a RF-10 | Implementado (backend y app); verificado en base y con pruebas, sin una cuenta real | Registro de café y cacao, certificaciones, catálogo con filtros (tipo, calidad, certificación, estado y texto), edición e inactivación sin borrado. Base: 97 pruebas; app: pruebas de cliente, pantallas y un recorrido completo. Supuestos por confirmar: producto único por (tipo, variedad, calidad), tipo y unidad inmutables, formato del HS (`modelo-autorizacion-rls.md`, sección 14). |
| RF-11 a RF-33 | Pendiente | Sin implementación; sus criterios siguen vigentes. |

### 9.3 Decisiones aún abiertas tras la 0.3

1. Aprobar con el docente/cliente el autorregistro con rol `cliente` y los permisos por defecto de ese rol (hoy ninguno).
2. Decidir si se exige confirmación de correo (hoy activa en Supabase) y qué mensaje ve el usuario.
3. Definir el sustituto de OpenAPI para el contrato de servicios (RNF-15).
4. Alinear los documentos con la v0.3: `arquitectura-inicial.md` y `decisiones-arquitectura.md` ya se actualizaron (ADR-018 a ADR-021); queda pendiente `contrato-api.md`, que aún describe el servidor FastAPI y OpenAPI.

## 10. Validación y firma del documento de requisitos

**Estado:** *Pendiente de firma.* Este apartado es el formato del acta; **no contiene firmas ni aprobaciones**. Debe completarse en la sesión de validación con el docente/cliente (ver `levantamiento-requerimientos.md`).

### 10.1 Lista de verificación previa a la firma

| # | Verificación | Resultado |
|---|---|---|
| 1 | Cada RF y RNF tiene identificador, criterio de aceptación y, en el RNF, su estado (explícito, derivado o propuesta). | Cumple (secciones 4 y 5). |
| 2 | Los cambios de la versión 0.3 están registrados con su motivo (sección 9.1). | Cumple. |
| 3 | Las decisiones abiertas están listadas con responsable (secciones 6 y 9.3, y `levantamiento-requerimientos.md`). | Cumple; responsables por asignar en la sesión. |
| 4 | Las propuestas no funcionales (RNF-05, 07, 08, 14, 17, 18, 19) están marcadas como por validar. | Cumple. |
| 5 | Existe trazabilidad con el backlog y con la arquitectura (`arquitectura-inicial.md`, ADR-018 a ADR-021). | Cumple. |
| 6 | El docente/cliente aprobó el alcance y las decisiones de prioridad Alta. | **Pendiente** |

### 10.2 Acta de aprobación

**Documento:** Requerimientos del sistema, versión ____  **Fecha de sesión:** ____________

| Nombre | Rol | Decisión (☐ Aprueba ☐ Aprueba con cambios ☐ Rechaza) | Firma | Fecha |
|---|---|---|---|---|
|  | Docente / cliente |  |  |  |
|  | Líder del equipo |  |  |  |
|  | Integrante responsable |  |  |  |

**Cambios solicitados antes de aprobar:**

-

Una vez firmada, la versión queda como **línea base**: todo cambio posterior se registra en la sección 9 con nueva versión y fecha.
