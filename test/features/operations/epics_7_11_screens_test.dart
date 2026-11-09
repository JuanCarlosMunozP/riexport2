import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/inventory/presentation/inventory_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_form_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_list_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_timeline_screen.dart';
import 'package:riexport_app/features/notifications/presentation/notification_center_screen.dart';
import 'package:riexport_app/features/orders/presentation/export_dossier_screen.dart';
import 'package:riexport_app/features/payments/presentation/exchange_rates_screen.dart';
import 'package:riexport_app/features/payments/presentation/payment_portfolio_screen.dart';

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  group('expediente documental', () {
    final docs = <Map<String, dynamic>>[
      {
        'id': 2,
        'document_type': 'commercial_invoice',
        'version': 2,
        'document_number': 'FAC-2026-000001',
        'created_at': '2026-10-30T10:00:00Z',
      },
      {
        'id': 1,
        'document_type': 'commercial_invoice',
        'version': 1,
        'document_number': 'FAC-2026-000001',
        'created_at': '2026-10-29T10:00:00Z',
      },
    ];

    testWidgets('muestra lo emitido y lo pendiente', (tester) async {
      await tester.pumpWidget(
        _app(
          ExportDossierScreen(
            exportId: 9,
            loadDocuments: (_) async => docs,
            downloadDocument: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Documentos requeridos: 1 de 4'), findsOneWidget);
      expect(find.textContaining('FAC-2026-000001 · v2'), findsOneWidget);
      expect(find.text('Pendiente'), findsNWidgets(3));
      // Sin permisos no hay acciones de emitir ni adjuntar.
      expect(find.byTooltip('Emitir Packing list'), findsNothing);
      expect(
        find.byTooltip('Adjuntar Certificado fitosanitario'),
        findsNothing,
      );
      expect(find.byTooltip('Descargar Factura comercial'), findsOneWidget);
    });

    testWidgets('emite un documento y recarga el expediente', (tester) async {
      final generated = <String>[];
      var loads = 0;
      await tester.pumpWidget(
        _app(
          ExportDossierScreen(
            exportId: 9,
            loadDocuments: (_) async {
              loads++;
              return loads == 1 ? const [] : docs;
            },
            downloadDocument: (_) async => null,
            generateDocument: (id, type) async => generated.add('$id:$type'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('todavía no tiene documentos'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Emitir Factura comercial'));
      await tester.pumpAndSettle();
      expect(generated, ['9:commercial_invoice']);
      expect(loads, 2);
      expect(find.textContaining('FAC-2026-000001 · v2'), findsOneWidget);
    });

    testWidgets(
      'adjunta el fitosanitario y rechaza tipos o tamaños no válidos',
      (tester) async {
        final uploaded = <String>[];
        PickedDocument? next;
        await tester.pumpWidget(
          _app(
            ExportDossierScreen(
              exportId: 9,
              loadDocuments: (_) async => const [],
              downloadDocument: (_) async => null,
              uploadDocument: (id, type, file) async =>
                  uploaded.add('$id:$type:${file.name}'),
              pickFile: () async => next,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byTooltip('Adjuntar Certificado fitosanitario');

        next = PickedDocument('virus.exe', Uint8List.fromList([1, 2, 3]));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.text('Solo se aceptan archivos PDF, PNG o JPEG.'),
          findsOneWidget,
        );

        next = PickedDocument(
          'grande.pdf',
          Uint8List(maxDossierUploadBytes + 1),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.text('El archivo debe pesar entre 1 byte y 10 MB.'),
          findsOneWidget,
        );

        next = null; // la persona cancela el selector
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(uploaded, isEmpty);

        next = PickedDocument('fito.PDF', Uint8List.fromList([1, 2, 3]));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(uploaded, ['9:phytosanitary_certificate:fito.PDF']);
      },
    );

    testWidgets(
      'descarga abre la URL firmada y, si falla, la ofrece para copiar',
      (tester) async {
        final opened = <String>[];
        var failOpen = false;
        await tester.pumpWidget(
          _app(
            ExportDossierScreen(
              exportId: 9,
              loadDocuments: (_) async => docs,
              downloadDocument: (id) async => 'https://x.test/$id.pdf',
              openUrl: (url) async {
                if (failOpen) throw StateError('sin navegador');
                opened.add(url);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Descargar Factura comercial'));
        await tester.pumpAndSettle();
        expect(opened, ['https://x.test/2.pdf']);

        failOpen = true;
        await tester.tap(find.byTooltip('Descargar Factura comercial'));
        await tester.pumpAndSettle();
        expect(find.textContaining('https://x.test/2.pdf'), findsOneWidget);
        expect(find.text('Copiar enlace'), findsOneWidget);
      },
    );

    testWidgets('muestra el error de la API al emitir', (tester) async {
      await tester.pumpWidget(
        _app(
          ExportDossierScreen(
            exportId: 9,
            loadDocuments: (_) async => const [],
            downloadDocument: (_) async => null,
            generateDocument: (_, _) async => throw const ApiException(
              statusCode: 403,
              code: 'FORBIDDEN',
              message: 'No tienes permiso para esta operación.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Emitir Packing list'));
      await tester.pumpAndSettle();
      expect(
        find.text('No tienes permiso para esta operación.'),
        findsOneWidget,
      );
    });
  });

  group('inventario', () {
    testWidgets('avisa del stock bajo y alterna la vista por producto', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          InventoryScreen(
            canAdjust: false,
            loadInventory: (_) async => [
              {
                'id': 1,
                'product_id': 7,
                'lot_code': 'L-1',
                'product_type': 'coffee',
                'available_quantity': 50,
              },
              {
                'id': 2,
                'product_id': 8,
                'lot_code': 'L-2',
                'product_type': 'cacao',
                'available_quantity': 900,
              },
            ],
            adjustInventory: (_, _) async {},
            loadOverview: () async => [
              {
                'product_id': 7,
                'product_type': 'coffee',
                'variety': 'Caturra',
                'quality_grade': 'Excelso',
                'base_unit_code': 'kg',
                'low_stock_threshold': 100,
                'lot_count': 1,
                'available_quantity': 50,
                'is_low_stock': true,
              },
              {
                'product_id': 8,
                'product_type': 'cacao',
                'variety': 'Criollo',
                'quality_grade': 'Premium',
                'base_unit_code': 'kg',
                'low_stock_threshold': null,
                'lot_count': 1,
                'available_quantity': 900,
                'is_low_stock': false,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Stock bajo en 1 producto'), findsOneWidget);
      // Solo el lote del producto en alerta lleva el indicador.
      expect(find.text('Stock bajo'), findsOneWidget);

      await tester.tap(find.text('Por producto'));
      await tester.pumpAndSettle();
      expect(find.text('Café Caturra (Excelso)'), findsWidgets);
      expect(find.textContaining('umbral mínimo 100 kg'), findsOneWidget);
      expect(find.textContaining('sin umbral mínimo'), findsOneWidget);
      expect(find.text('50 kg'), findsOneWidget);
    });

    testWidgets('sin resumen se comporta como antes', (tester) async {
      await tester.pumpWidget(
        _app(
          InventoryScreen(
            canAdjust: false,
            loadInventory: (_) async => const [],
            adjustInventory: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Por producto'), findsNothing);
      expect(find.text('No hay lotes para mostrar.'), findsOneWidget);
    });
  });

  group('cartera de pagos', () {
    final rows = <Map<String, dynamic>>[
      {
        'obligation_id': 1,
        'order_number': 'PED-1',
        'customer_name': 'Importadora',
        'amount_due': 1000,
        'amount_paid': 400,
        'balance': 600,
        'currency_code': 'USD',
        'due_date': '2026-10-01',
        'status': 'overdue',
        'days_overdue': 29,
      },
      {
        'obligation_id': 2,
        'order_number': 'PED-2',
        'customer_name': 'Otra',
        'amount_due': 500,
        'amount_paid': 500,
        'balance': 0,
        'currency_code': 'EUR',
        'status': 'paid',
        'days_overdue': 0,
      },
    ];

    testWidgets('lista obligaciones con saldo, atraso y estado', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          PaymentPortfolioScreen(
            loadPortfolio: ({query, status, currency}) async => rows,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saldo por cobrar: 600.00 USD'), findsOneWidget);
      expect(find.textContaining('29 días de atraso'), findsOneWidget);
      expect(find.text('Vencido'), findsOneWidget);
      expect(find.text('Pagado'), findsWidgets);
      // Sin permiso no hay botón de pago.
      expect(find.byTooltip('Registrar pago'), findsNothing);
    });

    testWidgets('filtra por estado y por moneda', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _app(
          PaymentPortfolioScreen(
            loadPortfolio: ({query, status, currency}) async {
              calls.add('$status/$currency');
              return currency == null
                  ? rows
                  : [
                      {
                        ...rows.first,
                        'balance_converted': 550.5,
                        'converted_currency': 'EUR',
                      },
                    ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portfolio-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vencido').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portfolio-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      expect(calls, ['null/null', 'overdue/null', 'overdue/EUR']);
      expect(find.textContaining('≈ 550.50 EUR'), findsWidgets);
    });

    testWidgets(
      'el pago no puede superar el saldo y se envía en la moneda de la obligación',
      (tester) async {
        final payments = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          _app(
            PaymentPortfolioScreen(
              loadPortfolio: ({query, status, currency}) async => rows,
              registerPayment: (payment) async => payments.add(payment),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Registrar pago'),
          findsOneWidget,
        ); // solo la que tiene saldo
        await tester.tap(find.byTooltip('Registrar pago'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Monto (USD)'),
          '600.01',
        );
        await tester.tap(find.text('Registrar'));
        await tester.pumpAndSettle();
        expect(
          find.text('El pago supera el saldo de la obligación.'),
          findsOneWidget,
        );
        expect(payments, isEmpty);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Monto (USD)'),
          '250,5',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Referencia (opcional)'),
          'Transf. 77',
        );
        await tester.tap(find.text('Registrar'));
        await tester.pumpAndSettle();
        expect(payments, [
          {
            'obligation_id': 1,
            'amount': 250.5,
            'currency_code': 'USD',
            'reference': 'Transf. 77',
          },
        ]);
        expect(find.text('Pago registrado.'), findsOneWidget);
      },
    );

    testWidgets('muestra el error del servidor al registrar', (tester) async {
      await tester.pumpWidget(
        _app(
          PaymentPortfolioScreen(
            loadPortfolio: ({query, status, currency}) async => rows,
            registerPayment: (_) async => throw const ApiException(
              statusCode: 422,
              code: 'VALIDATION_ERROR',
              message: 'El pago supera el saldo de la obligación.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registrar pago'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('crea una obligación sobre una exportación', (tester) async {
      final created = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _app(
          PaymentPortfolioScreen(
            loadPortfolio: ({query, status, currency}) async => const [],
            createObligation: (body) async => created.add(body),
            loadExports: () async => [
              {'id': 4, 'order_number': 'PED-9', 'customer_name': 'Cliente'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva obligación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.text('Indica un monto mayor que cero.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Monto'),
        '1250',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Vencimiento (AAAA-MM-DD, opcional)',
        ),
        '31/12/2026',
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.text('Usa el formato AAAA-MM-DD.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Vencimiento (AAAA-MM-DD, opcional)',
        ),
        '2026-12-31',
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(created, [
        {
          'export_id': 4,
          'amount_due': 1250,
          'currency_code': 'USD',
          'due_date': '2026-12-31',
        },
      ]);
    });
  });

  group('tasas de cambio', () {
    testWidgets('convierte, actualiza desde el servicio y valida la entrada', (
      tester,
    ) async {
      var refreshed = 0;
      await tester.pumpWidget(
        _app(
          ExchangeRatesScreen(
            loadRates: () async => [
              {
                'base_currency_code': 'USD',
                'quote_currency_code': 'EUR',
                'rate': 0.92,
                'effective_at': '2026-10-30T00:00:00Z',
                'source': 'open.er-api.com',
              },
            ],
            convert: (amount, from, to) async {
              if (to == 'JPY') {
                throw const ApiException(
                  statusCode: 404,
                  code: 'NOT_FOUND',
                  message: 'No hay tasa de cambio disponible de USD a JPY.',
                );
              }
              return {
                'converted': 92.0,
                'rate': 0.92,
                'source': 'open.er-api.com',
              };
            },
            refreshRates: () async => refreshed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 USD = 0.92 EUR'), findsOneWidget);

      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversion')), findsOneWidget);
      expect(find.textContaining('= 92.0 EUR'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'A'), 'JPY');
      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(
        find.text('No hay tasa de cambio disponible de USD a JPY.'),
        findsOneWidget,
      );

      await tester.enterText(find.widgetWithText(TextField, 'A'), 'EURO');
      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indica un monto y dos monedas de 3 letras.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Actualizar desde el servicio externo'));
      await tester.pumpAndSettle();
      expect(refreshed, 1);
    });
  });

  group('envíos', () {
    final shipments = <Map<String, dynamic>>[
      {
        'id': 5,
        'order_number': 'PED-1',
        'customer_name': 'Cliente',
        'carrier': 'Maersk',
        'tracking_number': 'MAEU1',
        'status': 'planned',
        'transport_mode': 'sea',
        'estimated_delivery_at': '2026-12-01',
      },
      {
        'id': 6,
        'order_number': 'PED-2',
        'customer_name': 'Cliente',
        'status': 'delivered',
      },
    ];

    testWidgets(
      'muestra estados y solo ofrece cambiar los que no son terminales',
      (tester) async {
        await tester.pumpWidget(
          _app(
            ShipmentListScreen(
              loadShipments: ({query, status}) async => shipments,
              updateStatus: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Planificado'), findsOneWidget);
        expect(find.text('Entregado'), findsOneWidget);
        expect(find.textContaining('Marítimo'), findsOneWidget);
        expect(find.byTooltip('Actualizar estado'), findsOneWidget);
      },
    );

    testWidgets('cambia el estado eligiendo una transición válida', (
      tester,
    ) async {
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          ShipmentListScreen(
            loadShipments: ({query, status}) async => shipments,
            updateStatus: (id, change) async => changes.add('$id:$change'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      // Desde «Planificado» solo se puede pasar a tránsito o cancelar.
      await tester.tap(find.byKey(const ValueKey('new-status')));
      await tester.pumpAndSettle();
      expect(find.text('En tránsito'), findsWidgets);
      expect(find.text('Cancelado'), findsWidgets);
      expect(
        find.text('Entregado'),
        findsOneWidget,
      ); // solo el chip de la fila 6
      await tester.tap(find.text('En tránsito').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Ubicación (opcional)'),
        'Cartagena',
      );
      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();
      expect(changes, ["5:{status: in_transit, location: Cartagena}"]);
    });

    testWidgets('filtra por estado', (tester) async {
      final statuses = <String?>[];
      await tester.pumpWidget(
        _app(
          ShipmentListScreen(
            loadShipments: ({query, status}) async {
              statuses.add(status);
              return shipments;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En aduana').last);
      await tester.pumpAndSettle();
      expect(statuses, [null, 'in_customs']);
    });

    testWidgets('el formulario valida y envía los datos de transporte', (
      tester,
    ) async {
      final bodies = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _app(
          ShipmentFormScreen(
            loadExports: () async => [
              {'id': 3, 'order_number': 'PED-3', 'customer_name': 'Cliente'},
            ],
            onSubmit: (body) async => bodies.add(body),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Entrega estimada (AAAA-MM-DD)'),
        'mañana',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Usa el formato AAAA-MM-DD.'), findsOneWidget);
      expect(bodies, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Entrega estimada (AAAA-MM-DD)'),
        '2026-12-01',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Transportista'),
        'MSC',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Guía / tracking'),
        'G-1',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(bodies.single, {
        'export_id': 3,
        'carrier': 'MSC',
        'tracking_number': 'G-1',
        'transport_mode': null,
        'container_number': null,
        'estimated_delivery_at': '2026-12-01',
      });
    });

    testWidgets('editar no pide exportación y precarga los datos', (
      tester,
    ) async {
      final bodies = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _app(
          ShipmentFormScreen(
            initial: shipments.first,
            onSubmit: (body) async => bodies.add(body),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shipment-export')), findsNothing);
      expect(find.text('Editar transporte'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(bodies.single.containsKey('export_id'), isFalse);
      expect(bodies.single['carrier'], 'Maersk');
      expect(bodies.single['transport_mode'], 'sea');
    });

    testWidgets(
      'la línea de tiempo muestra el historial y, con permiso, registra eventos',
      (tester) async {
        final events = <String>[];
        await tester.pumpWidget(
          _app(
            ShipmentTimelineScreen(
              shipmentId: 5,
              loadShipment: (_) async => {
                'id': 5,
                'order_number': 'PED-1',
                'status': 'in_transit',
                'carrier': 'Maersk',
                'tracking_number': 'MAEU1',
              },
              loadEvents: (_) async => [
                {
                  'id': 2,
                  'event_type': 'in_transit',
                  'event_at': '2026-10-29T10:00:00Z',
                  'location': 'Cartagena',
                },
                {
                  'id': 1,
                  'event_type': 'planned',
                  'event_at': '2026-10-28T10:00:00Z',
                },
              ],
              updateStatus: (_, _) async {},
              addEvent: (id, event) async =>
                  events.add('$id:${event['event_type']}'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Envío MAEU1'), findsOneWidget);
        expect(find.text('En tránsito'), findsWidgets);
        expect(find.text('Planificado'), findsOneWidget);
        expect(find.text('Cartagena'), findsOneWidget);

        await tester.tap(find.byTooltip('Registrar evento'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Registrar'));
        await tester.pumpAndSettle();
        expect(find.text('Describe el tipo de evento.'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            'Evento (p. ej. inspección, retraso)',
          ),
          'inspeccion',
        );
        await tester.tap(find.text('Registrar'));
        await tester.pumpAndSettle();
        expect(events, ['5:inspeccion']);
      },
    );

    testWidgets('el cliente solo lee: sin acciones de edición', (tester) async {
      await tester.pumpWidget(
        _app(
          ShipmentTimelineScreen(
            shipmentId: 5,
            loadShipment: (_) async => {
              'shipment_id': 5,
              'order_number': 'PED-1',
              'status': 'delivered',
              'status_label': 'Entregado',
            },
            loadEvents: (_) async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Actualizar estado'), findsNothing);
      expect(find.byTooltip('Registrar evento'), findsNothing);
      expect(find.text('Entregado'), findsOneWidget);
      expect(
        find.text('Todavía no hay eventos para este envío.'),
        findsOneWidget,
      );
    });
  });

  group('centro de notificaciones', () {
    List<Map<String, dynamic>> data() => [
      {
        'id': 1,
        'notification_type': 'low_stock',
        'title': 'Stock bajo: Caturra',
        'body': 'Quedan 50 kg',
        'created_at': '2026-10-30T10:00:00Z',
        'read_at': null,
        'entity_type': 'product',
        'entity_id': 7,
      },
      {
        'id': 2,
        'notification_type': 'payment_overdue',
        'title': 'Pago vencido: PED-1',
        'created_at': '2026-10-29T10:00:00Z',
        'read_at': '2026-10-29T11:00:00Z',
      },
    ];

    testWidgets('ejecuta las alertas, lista y marca como leída al abrir', (
      tester,
    ) async {
      final read = <int>[];
      final opened = <String>[];
      var refreshed = 0;
      await tester.pumpWidget(
        _app(
          NotificationCenterScreen(
            refreshAlerts: () async => refreshed++,
            loadNotifications: ({unreadOnly = false}) async => data(),
            markRead: (id) async => read.add(id),
            markAllRead: () async {},
            onOpenEntity: (type, id) => opened.add('$type:$id'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(refreshed, 1);
      expect(find.text('Notificaciones (1)'), findsOneWidget);
      expect(find.text('Stock bajo: Caturra'), findsOneWidget);

      await tester.tap(find.text('Stock bajo: Caturra'));
      await tester.pumpAndSettle();
      expect(read, [1]);
      expect(opened, ['product:7']);
      expect(find.text('Notificaciones'), findsOneWidget); // ya no hay sin leer
    });

    testWidgets('marca todas como leídas y filtra las no leídas', (
      tester,
    ) async {
      var all = false;
      final filters = <bool>[];
      await tester.pumpWidget(
        _app(
          NotificationCenterScreen(
            loadNotifications: ({unreadOnly = false}) async {
              filters.add(unreadOnly);
              return all
                  ? [
                      for (final n in data())
                        {...n, 'read_at': '2026-10-30T12:00:00Z'},
                    ]
                  : data();
            },
            markRead: (_) async {},
            markAllRead: () async => all = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver solo no leídas'));
      await tester.pumpAndSettle();
      expect(filters, [false, true]);
      await tester.tap(find.byTooltip('Marcar todas como leídas'));
      await tester.pumpAndSettle();
      expect(find.text('Notificaciones'), findsOneWidget);
    });

    testWidgets(
      'sin avisos o con error lo informa; las alertas fallidas no bloquean',
      (tester) async {
        await tester.pumpWidget(
          _app(
            NotificationCenterScreen(
              refreshAlerts: () async => throw StateError('sin cron'),
              loadNotifications: ({unreadOnly = false}) async => const [],
              markRead: (_) async {},
              markAllRead: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('No tienes notificaciones.'), findsOneWidget);

        await tester.pumpWidget(
          _app(
            NotificationCenterScreen(
              key: const ValueKey('failing'),
              loadNotifications: ({unreadOnly = false}) async =>
                  throw const ApiException(
                    statusCode: 500,
                    code: 'X',
                    message: 'Servidor caído.',
                  ),
              markRead: (_) async {},
              markAllRead: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Servidor caído.'), findsOneWidget);
      },
    );
  });
}
