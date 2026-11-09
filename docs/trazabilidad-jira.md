# Revisión de trazabilidad de las capturas Jira

Este documento revisa las tareas visibles PLAT-404–PLAT-566. Los estados Jira no se editan desde el repositorio; “implementado” significa que se encontró código o migración local.

| Grupo de tickets | Estado en el repo | Evidencia / pendiente |
|---|---|---|
| EP-0 PLAT-405–438: requisitos, arquitectura, modelo y base inicial | Parcial | Código, migraciones y pruebas cubren configuración técnica. Se añadieron arquitectura/modelo/RLS/API en `docs/`; el taller (PLAT-406), validación y firma del cliente (PLAT-409/422) no se pueden certificar con una captura de backlog y requieren evidencia del cliente. |
| EP-1 PLAT-439–480: Auth, usuarios, roles y políticas | Parcial/implementado por módulo | Auth, cuentas, roles, auditoría, catálogo y pedidos cuentan con migraciones/pantallas. La migración nueva completa políticas para exportaciones, documentos, logística, notificaciones y aislamiento de portal. Pagos/tasas siguen sin reglas de negocio acordadas. |
| EP-2 PLAT-490–508: productos | Implementado localmente | Productos café/cacao, certificaciones, edición, inactivación y pruebas. |
| EP-3 PLAT-509–524: proveedor, finca, lote y EUDR | Parcial | Proveedores/fincas/lotes y mapa de origen de lote existen. La migración nueva añade exportación, envíos y vistas de trazabilidad; la pantalla de envíos abre el mapa. La carga parcial de una exportación en varios envíos queda como supuesto a validar. |
| EP-4 PLAT-525–538: clientes | Parcial/implementado por módulo | CRUD, EORI y vínculo de cuenta existen; la migración añade vistas de historial. El modo local aún no persiste exportaciones, así que informa que esa sección no está disponible. |
| EP-5 PLAT-539–558: pedidos | Implementado localmente | Registro, vista de datos relacionados, búsqueda/filtros, transiciones controladas y edición únicamente en borrador; el total se recalcula desde las líneas y el inventario conserva los ajustes en el libro de movimientos. Falta aplicar las migraciones pendientes al Supabase alojado. |
| EP-6 PLAT-560–566: exportaciones | Implementado localmente | Tablas de exportación y detalle, catálogos de países de destino e Incoterms ICC 2020, registro transaccional desde pedido confirmado y asistente Flutter. Se permiten varias exportaciones parciales por pedido; Incoterm opcional. Falta aplicar la migración en Supabase alojado y probar allí con usuarios/permisos reales. |

## Cierres externos

1. Aplicar las migraciones pendientes al Supabase de destino y comprobar `supabase migration list`.
2. Adjuntar evidencia real del taller y aprobación de requisitos; el repo no puede producir la firma del cliente.
3. Confirmar si cada envío transporta toda la exportación o si se asignan líneas/cantidades a envíos parciales.
4. Definir reglas de pagos, obligaciones y tasas antes de implementar tablas o permisos financieros.

## PLAT-575–583: historial y documentos de exportación

| Ticket | Estado en el repo |
|---|---|
| PLAT-575/576/577 historial | Vista `export_history` (migración `20261021000000`), `GET /exports` la usa, pantalla `ExportHistoryScreen` en `/exports` con búsqueda y filtro de estado. Falta aplicar la migración en Supabase alojado. |
| PLAT-580 decisión | `docs/decision-generacion-documentos.md`: Edge Function con `pdf-lib`. |
| PLAT-581 entorno | `supabase/config.toml` y `supabase/functions/deno.json`. |
| PLAT-582 librería PDF | `pdf-lib` 1.17.1 fijada; helper `_shared/pdf.ts`. |
| PLAT-583 servicio base | `functions/generate-document`; plantilla `export_summary`. **No ejecutado**: no hay Deno ni Supabase CLI en esta máquina. |
| PLAT-579 historia | Backend listo; falta botón en la app para invocar la función y descargar el PDF. |

## Cierre de brechas EP-0 a EP-6 (2026-10-30)

El tablero marca como «Listo» estas tareas; el código se alineó con él:

| Ticket | Qué se añadió | Evidencia |
|---|---|---|
| PLAT-529 (prueba) | El historial local ya devuelve pedidos y exportaciones; se actualizó la expectativa desactualizada | `test/customer_links_test.dart` |
| PLAT-439 semilla | `database/seeds/seed.sql` (datos de ejemplo idempotentes) | `database/seeds/seed.sql` |
| PLAT-406/409/422 | Formatos de acta de taller y de validación/firma, **sin firmar** (la evidencia real la aporta el equipo) | `docs/acta-*.md` |
| PLAT-407/408 | Requisitos funcionales y no funcionales | `docs/requisitos.md` |
| PLAT-415 | Registro de decisiones (ADR) | `docs/adr/` |
| PLAT-419 | Diccionario de datos generado desde las migraciones | `docs/diccionario-datos.md` |
| PLAT-449 | Confirmación de correo por código: plantilla, `POST /auth/email-confirmations`, `ConfirmEmailScreen` | `confirm_email_screen.dart`, `test/confirm_email_screen_test.dart` |
| PLAT-567–569 | El código HS se copia del producto a la línea del pedido y de la exportación y se muestra en el asistente | migraciones `20261019`/`20261020` |
| PLAT-571/572 | Función `export_eudr_declaration` (validez de trazabilidad: líneas → lote → finca con coordenadas → proveedor + HS) y ruta `GET /exports/:id/eudr` | migración `20261022000000` |
| PLAT-573/574 | `EudrDeclarationScreen` y pruebas (widget, cliente Supabase, backend local) | `test/eudr_declaration_screen_test.dart` |
| PLAT-579/582/583 | Botón «Generar PDF» en el historial; `POST /exports/:id/documents` invoca la Edge Function y firma la descarga | `export_history_screen.dart`, `test/supabase_backend_test.dart` |
| PLAT-584–604 (EP-7) | Numeración correlativa (`reserve_document_number`), `export_document_data`, plantillas factura/packing/EUR.1 (borrador), `register_export_document`, expediente y subida de archivos | migración `20261023000000`, `supabase/functions/generate-document`, `export_dossier_screen.dart`, `test/epics_7_11_screens_test.dart` |
| PLAT-606–617 (EP-8) | Vista `inventory_overview`, bloqueo de saldos negativos, alerta de stock bajo, vista por producto | migración `20261023000000`, `inventory_screen.dart` |
| PLAT-619–630 (EP-9) | Cartera (`payment_portfolio`), pagos parciales, tasas de cambio (`convert_amount`, `register_exchange_rate`), Edge Function `refresh-exchange-rates` | migración `20261023000000`, `payment_portfolio_screen.dart`, `exchange_rates_screen.dart` |
| PLAT-632–643 (EP-10) | Catálogo de estados y transiciones, `update_shipment_status`, `add_shipment_event`, línea de tiempo y seguimiento del cliente | migración `20261023000000`, `shipment_*_screen.dart` |
| PLAT-645–654 (EP-11) | Notificaciones con `dedupe_key`, `run_scheduled_alerts` (pg_cron opcional), centro de notificaciones con insignia | migración `20261023000000`, `notification_center_screen.dart` |
| Pruebas EP-7–11 | 98 pruebas SQL, 22 de cliente Supabase y widgets | `database/tests/epics_7_11.sql`, `test/supabase_epics_7_11_test.dart` |

## Validación ticket por ticket, EP-7 a EP-11 (2026-11-01)

Estado: **Hecho** = implementado y con evidencia ejecutada; **Hecho (alojado pendiente)** = implementado y verificado en Docker local, falta aplicarlo/desplegarlo en el alojado. Evidencia: `M23` = migración `20261023000000`, `M24` = `20261024000000`, `SQL` = `database/tests/epics_7_11.sql`, `UI` = `test/epics_7_11_screens_test.dart`, `CLI` = `test/supabase_epics_7_11_test.dart`, `QA-PDF` = `database/tests/qa/validate_documents.py`, `QA-CONC` = `database/tests/qa/concurrency_inventory.sh`.

| Ticket | Qué pide | Estado | Evidencia |
|---|---|---|---|
| 584 | Políticas de acceso al almacenamiento | Hecho | M23 (`export_documents_insert`, `_delete_unregistered`), SQL |
| 585 | HU.31 Factura comercial | Hecho | 586–591 |
| 586 | Tabla de documentos | Hecho | `export_document` (+ `document_number`), `register_export_document` (M23), SQL |
| 587 | Numeración consecutiva | Hecho | `reserve_document_number`, SQL (FAC-AAAA-000001, reutilización) |
| 588 | Plantilla de factura | Hecho | `functions/_shared/templates.ts`, QA-PDF |
| 589 | Emisión de la factura | Hecho | `functions/generate-document`; probada en local y en el alojado |
| 590 | Emisión y descarga en la app | Hecho | `export_dossier_screen.dart`, UI, CLI |
| 591 | QA contenido de la factura | Hecho | QA-PDF (número, comprador, producto, importe, moneda) |
| 592–595 | Packing list: plantilla, emisión, app | Hecho | `templates.ts`, `generate-document`, UI, QA-PDF |
| 596–599 | EUR.1: plantilla, emisión, app (borrador) | Hecho | idem; se marca «borrador» hasta el visado de aduanas |
| 600–602 | Certificado fitosanitario: tipo y tamaño, carga en la app | Hecho (alojado pendiente M24) | `register_export_document` (PDF/PNG/JPEG ≤ 10 MB), M24 alinea el bucket a 10 MB, `POST /exports/:id/documents/upload`, UI, CLI |
| 603–604 | Expediente documental | Hecho | vista `export_dossier`, `ExportDossierScreen`, SQL, UI |
| 606–609 | Inventario disponible (tabla, vista, pantalla) | Hecho | `lot_inventory_availability`, `inventory_overview` (M23), `inventory_screen.dart`, SQL, UI |
| 610–613 | Inventario automático: movimientos, descuento, concurrencia | Hecho | `inventory_movement`, `guard_inventory_movement` (bloqueo + sin negativos), SQL, QA-CONC |
| 614 | QA consistencia del inventario | Hecho | SQL + QA-CONC (6 descuentos simultáneos: pasan 2 de 80 kg, saldo 20) |
| 615–617 | Umbral de stock bajo (columna, indicador) | Hecho | `product.low_stock_threshold`, formulario de producto, chips en inventario, SQL, UI |
| 619–623 | Pago de un pedido: tabla, validación de saldo, formulario, QA | Hecho | `payment_transaction`, `guard_payment_transaction`, `PaymentPortfolioScreen`, SQL, UI |
| 624–626 | Cartera pendiente/vencida | Hecho | `payment_portfolio`, pantalla de cartera, SQL, UI |
| 627–630 | Monedas: tasas, servicio externo, conversión | Hecho (alojado: función desplegada y probada) | `exchange_rate`, `convert_amount`, `payment_portfolio_in`, `refresh-exchange-rates`, SQL, UI |
| 632–636 | Estado logístico: catálogo, historial, función, app | Hecho | `shipment_status(_transition)`, `shipment_event`, `update_shipment_status`, `shipment_list_screen.dart`, SQL, UI |
| 637–640 | Seguimiento del cliente y aislamiento | Hecho | `customer_shipment_tracking`, `shipment_timeline_screen.dart`, SQL (cliente propio vs ajeno) |
| 641–643 | Transportista y guía | Hecho | `shipment.carrier/tracking_number/transport_mode/container_number`, `shipment_form_screen.dart`, SQL, UI |
| 645–648 | Servicio de notificaciones: tabla, tareas programadas, función base | Hecho (alojado pendiente M24) | `notification`, `notify_permission_holders`, `run_scheduled_alerts`, pg_cron (M23 guardado; M24 lo activa) |
| 649–651 | Alerta de stock bajo | Hecho | `check_low_stock` + trigger, SQL |
| 652–653 | Alerta de pago por vencer o vencido | Hecho | `check_payment_alerts`, SQL |
| 654 | Centro de notificaciones | Hecho | `notification_center_screen.dart`, insignia en inicio, UI |

Lo que ningún código cierra: aplicar `M24` al alojado (activa pg_cron y limita el bucket a 10 MB; el resto de EP-7–11 ya está allí) y programar la actualización periódica de tasas (la función `refresh-exchange-rates` acepta `x-cron-secret`; el cron externo o pg_net debe llamarla). Cambiar el estado en Jira es manual.

## Pendiente que ningún código puede cerrar

- **Desplegar las Edge Functions** (`supabase functions deploy generate-document refresh-exchange-rates --project-ref xrtharjpxyitaisolayl`, requiere `SUPABASE_ACCESS_TOKEN`). Las migraciones `20261016`–`20261023` ya están aplicadas en el proyecto alojado (2026-10-30, registro en `migration_state.applied`; `verify_schema.sql` sin fallas). Faltan por ejecutar en el alojado las demás pruebas SQL.
- Firmas y evidencias reales de PLAT-406, 409 y 422.
- Confirmar con el cliente los supuestos de `docs/adr/0005`.
