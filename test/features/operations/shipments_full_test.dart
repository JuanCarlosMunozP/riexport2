import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_list_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_timeline_screen.dart';

ApiException _api(String m) =>
    ApiException(statusCode: 400, code: 'e', message: m);

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void clearSnacks(WidgetTester tester) => ScaffoldMessenger.of(
  tester.element(find.byType(Scaffold).first),
).clearSnackBars();

Map<String, dynamic> _ship({String status = 'planned'}) => {
  'id': 4,
  'tracking_number': 'TRK-4',
  'order_number': 'PED-4',
  'customer_name': 'Cliente',
  'carrier': 'Maersk',
  'transport_mode': 'sea',
  'estimated_delivery_at': '2026-12-01',
  'status': status,
};

void main() {
  group('ShipmentListScreen', () {
    Widget app({
      Future<List<Map<String, dynamic>>> Function({String? query, String? status})?
      load,
      Future<void> Function(int, Map<String, dynamic>)? update,
      VoidCallback? onCreate,
      void Function(Map<String, dynamic>)? onEdit,
      void Function(int)? onTimeline,
      void Function(int)? onMap,
    }) => MaterialApp(
      home: ShipmentListScreen(
        loadShipments: load ?? ({query, status}) async => [_ship()],
        updateStatus: update,
        onCreate: onCreate,
        onEdit: onEdit,
        onOpenTimeline: onTimeline,
        onOpenMap: onMap,
      ),
    );

    testWidgets('errores de carga y lista vacia', (tester) async {
      await tester.pumpWidget(
        app(load: ({query, status}) async => throw _api('Caido')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Caido'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(load: ({query, status}) async => throw StateError('x')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudieron cargar los envíos.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(load: ({query, status}) async => []));
      await tester.pumpAndSettle();
      expect(find.text('No hay envíos registrados.'), findsOneWidget);
    });

    testWidgets('acciones de fila: crear, editar, mapa, linea de tiempo y busqueda', (
      tester,
    ) async {
      final log = <String>[];
      final queries = <String?>[];
      await tester.pumpWidget(
        app(
          load: ({query, status}) async {
            queries.add(query);
            return [_ship()];
          },
          onCreate: () => log.add('create'),
          onEdit: (s) => log.add('edit${s['id']}'),
          onTimeline: (id) => log.add('tl$id'),
          onMap: (id) => log.add('map$id'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo envío'));
      await tester.tap(find.byTooltip('Editar transporte'));
      await tester.tap(find.byTooltip('Ver trazabilidad en el mapa'));
      await tester.tap(find.textContaining('TRK-4'));
      expect(log, ['create', 'edit4', 'map4', 'tl4']);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Buscar'));
      await tester.pumpAndSettle();
      expect(queries.where((q) => q == 'abc').length, greaterThanOrEqualTo(2));
    });

    testWidgets('cambiar el estado: cancelar, exito y errores', (tester) async {
      var mode = 'ok';
      final changes = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        app(
          update: (id, change) async {
            if (mode == 'api') throw _api('Transicion invalida');
            if (mode == 'boom') throw StateError('x');
            changes.add(change);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('TRK-4'), findsWidgets);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);

      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'Puerto');
      await tester.enterText(fields.at(1), 'Zarpó');
      await tester.tap(find.byKey(const ValueKey('new-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelado').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar').last);
      await tester.pumpAndSettle();
      expect(changes.single['status'], 'cancelled');
      expect(changes.single['location'], 'Puerto');
      expect(changes.single['description'], 'Zarpó');

      mode = 'api';
      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar').last);
      await brief(tester);
      expect(find.text('Transicion invalida'), findsOneWidget);
      clearSnacks(tester);
      mode = 'boom';
      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar').last);
      await brief(tester);
      expect(find.text('No se pudo actualizar el estado.'), findsOneWidget);
    });

    testWidgets('un envio entregado no ofrece cambiar de estado', (tester) async {
      await tester.pumpWidget(
        app(
          load: ({query, status}) async => [_ship(status: 'delivered')],
          update: (id, change) async {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Actualizar estado'), findsNothing);
    });
  });

  group('ShipmentTimelineScreen', () {
    Widget app({
      Future<Map<String, dynamic>> Function(int)? loadShipment,
      Future<List<Map<String, dynamic>>> Function(int)? loadEvents,
      Future<void> Function(int, Map<String, dynamic>)? update,
      Future<void> Function(int, Map<String, dynamic>)? addEvent,
    }) => MaterialApp(
      home: ShipmentTimelineScreen(
        shipmentId: 4,
        loadShipment: loadShipment ?? (id) async => _ship(),
        loadEvents:
            loadEvents ??
            (id) async => [
              {
                'id': 1,
                'event_type': 'in_transit',
                'event_at': '2026-10-01T10:00:00.123Z',
                'location': 'Mar',
                'description': 'Zarpó',
              },
              {'id': 2, 'event_type': 'inspeccion', 'event_at': '2026-10-02'},
            ],
        updateStatus: update,
        addEvent: addEvent,
      ),
    );

    testWidgets('muestra el envio y su historial', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Pedido PED-4'), findsOneWidget);
      expect(find.text('Marítimo'), findsOneWidget);
      expect(find.text('inspeccion'), findsOneWidget);
    });

    testWidgets('errores de carga: API y generico', (tester) async {
      await tester.pumpWidget(app(loadShipment: (id) async => throw _api('No existe')));
      await tester.pumpAndSettle();
      expect(find.text('No existe'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(loadShipment: (id) async => throw StateError('x')));
      await tester.pumpAndSettle();
      expect(find.textContaining('seguimiento'), findsWidgets);
    });

    testWidgets('sin eventos muestra el aviso', (tester) async {
      await tester.pumpWidget(app(loadEvents: (id) async => []));
      await tester.pumpAndSettle();
      expect(
        find.text('Todavía no hay eventos para este envío.'),
        findsOneWidget,
      );
    });

    testWidgets('actualizar estado y registrar evento: exito y errores', (
      tester,
    ) async {
      var mode = 'ok';
      final log = <String>[];
      await tester.pumpWidget(
        app(
          update: (id, change) async {
            if (mode == 'api') throw _api('Transicion invalida');
            if (mode == 'boom') throw StateError('x');
            log.add('status:${change['status']}');
          },
          addEvent: (id, event) async {
            if (mode == 'api') throw _api('Evento invalido');
            if (mode == 'boom') throw StateError('x');
            log.add('event:${event['event_type']}');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar').last);
      await tester.pumpAndSettle();
      expect(log, ['status:in_transit']);

      // Evento: cancelar, validar vacio, registrar con ubicacion y detalle.
      await tester.tap(find.byTooltip('Registrar evento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registrar evento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar').last);
      await tester.pumpAndSettle();
      expect(find.text('Describe el tipo de evento.'), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'inspección');
      await tester.enterText(fields.at(1), 'Aduana');
      await tester.enterText(fields.at(2), 'Revisión física');
      await tester.tap(find.text('Registrar').last);
      await tester.pumpAndSettle();
      expect(log.last, 'event:inspección');

      mode = 'api';
      await tester.tap(find.byTooltip('Registrar evento'));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(0), 'retraso');
      await tester.tap(find.text('Registrar').last);
      await brief(tester);
      expect(find.text('Evento invalido'), findsOneWidget);
      clearSnacks(tester);

      mode = 'boom';
      await tester.tap(find.byTooltip('Registrar evento'));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(0), 'retraso');
      await tester.tap(find.text('Registrar').last);
      await brief(tester);
      expect(find.text('No se pudo registrar el evento.'), findsOneWidget);
      clearSnacks(tester);

      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar').last);
      await brief(tester);
      expect(find.text('No se pudo actualizar el estado.'), findsOneWidget);
      clearSnacks(tester);
      mode = 'api';
      await tester.tap(find.byTooltip('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar').last);
      await brief(tester);
      expect(find.text('Transicion invalida'), findsOneWidget);
    });
  });
}
