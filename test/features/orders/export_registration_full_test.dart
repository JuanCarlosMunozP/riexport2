import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/orders/presentation/export_registration_screen.dart';

List<Map<String, dynamic>> _orders() => [
  {
    'id': 7,
    'order_number': 'PED-7',
    'customer_name': 'Cliente Norte',
    'lines': [
      {
        'id': 41,
        'lot_code': 'LOTE-9',
        'hs_code': '0901.11',
        'quantity': 20,
        'remaining_quantity': 15,
      },
      {'id': 42, 'quantity': 4},
      {'id': 43, 'remaining_quantity': 0, 'quantity': 3},
      {'id': 'texto', 'quantity': 2},
    ],
  },
  {
    'id': 8,
    'order_number': 'PED-8',
    'customer_name': 'Otro',
    'lines': [
      {'order_line_id': 50, 'quantity': 0},
    ],
  },
];

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 6 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  Widget app({
    Future<List<Map<String, dynamic>>> Function()? orders,
    Future<List<Map<String, dynamic>>> Function()? destinations,
    Future<List<Map<String, dynamic>>> Function()? incoterms,
    Future<Object?> Function(Map<String, Object?>)? onSave,
  }) => MaterialApp(
    home: ExportRegistrationScreen(
      loadOrders: orders ?? () async => _orders(),
      loadDestinations:
          destinations ??
          () async => [
            {'code': 'DE', 'name': 'Alemania'},
            {'code': 'NL', 'name': 'Paises Bajos'},
          ],
      loadIncoterms:
          incoterms ??
          () async => [
            {'code': 'FOB', 'name': 'Franco a bordo'},
          ],
      onSave: onSave ?? (export) async => {'id': 1},
    ),
  );

  testWidgets('errores al cargar opciones: API y generico', (tester) async {
    await tester.pumpWidget(
      app(
        orders: () async => throw const ApiException(
          statusCode: 500,
          code: 'e',
          message: 'Caido',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caido'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(destinations: () async => throw StateError('x')));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudieron cargar pedidos y catálogos de exportación.'),
      findsOneWidget,
    );
  });

  testWidgets('sin pedidos ni destinos no hay lineas ni se puede enviar', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(orders: () async => [], destinations: () async => []),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('El pedido no tiene cantidades disponibles.'),
      findsOneWidget,
    );
    await _scrollTo(tester, find.byKey(const Key('export-submit')));
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(ExportRegistrationScreen), findsOneWidget);
  });

  testWidgets('cambia pedido, destino, incoterm y fecha; valida cantidades', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?>? saved;
    await tester.pumpWidget(app(onSave: (export) async => saved = export));
    await tester.pumpAndSettle();

    // Fecha: abrir el selector y elegir.
    await tester.tap(find.textContaining('Fecha de exportación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('export-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paises Bajos').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-incoterm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FOB · Franco a bordo').last);
    await tester.pumpAndSettle();

    // Cantidad superior al saldo.
    await tester.enterText(find.byKey(const Key('export-quantity-41')), '99');
    await _scrollTo(tester, find.byKey(const Key('export-submit')));
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cada cantidad debe ser positiva y no superar el saldo disponible.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('export-quantity-41')), 'abc');
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('export-quantity-41')), '-1');
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();

    // Cantidades validas (coma decimal) y envio.
    await tester.enterText(find.byKey(const Key('export-quantity-41')), '2,5');
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    expect(saved?['destination_country_code'], 'NL');
    expect(saved?['incoterm_code'], 'FOB');
  });

  testWidgets('un pedido sin saldo disponible no genera lineas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('PED-8').last);
    await tester.pumpAndSettle();
    expect(
      find.text('El pedido no tiene cantidades disponibles.'),
      findsOneWidget,
    );
    await _scrollTo(tester, find.byKey(const Key('export-submit')));
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('El pedido no tiene cantidades disponibles.'),
      findsWidgets,
    );
  });

  testWidgets('el guardado muestra errores de API y genericos', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var api = true;
    await tester.pumpWidget(
      app(
        onSave: (export) async {
          if (api) {
            throw const ApiException(
              statusCode: 409,
              code: 'e',
              message: 'Saldo agotado',
            );
          }
          throw StateError('x');
        },
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('export-submit')));
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Saldo agotado'), findsOneWidget);
    api = false;
    await tester.tap(find.byKey(const Key('export-submit')));
    await tester.pumpAndSettle();
    expect(find.text('No fue posible registrar la exportación.'), findsOneWidget);
  });
}
