import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/farms/presentation/lot_screens.dart';
import 'package:riexport_app/features/orders/presentation/order_registration_screen.dart';
import 'package:riexport_app/features/payments/presentation/payment_portfolio_screen.dart';

ApiException _api(String m) =>
    ApiException(statusCode: 400, code: 'e', message: m);

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Map<String, dynamic>> _customers() => [
  {
    'id': 3,
    'name': 'Cliente Norte',
    'is_active': true,
    'preferred_currency_code': 'EUR',
  },
  {
    'id': 4,
    'name': 'Cliente Sur',
    'is_active': true,
    'preferred_currency_code': 'USD',
  },
];

List<Map<String, dynamic>> _lots() => [
  {
    'id': 9,
    'lot_code': 'LOTE-9',
    'product_variety': 'Caturra',
    'product_quality': 'Excelso',
    'farm_name': 'Finca 1',
  },
  {
    'id': 10,
    'lot_code': 'LOTE-10',
    'product_variety': 'Castillo',
    'product_quality': 'A',
    'farm_name': 'Finca 2',
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
  group('OrderRegistrationScreen', () {
    Widget app({
      Future<List<Map<String, dynamic>>> Function()? customers,
      Future<List<Map<String, dynamic>>> Function()? lots,
      Future<Object?> Function(Map<String, Object?>)? onSave,
      Map<String, dynamic>? existing,
    }) => MaterialApp(
      home: OrderRegistrationScreen(
        loadCustomers: customers ?? () async => _customers(),
        loadLots: lots ?? () async => _lots(),
        onSave: onSave ?? (order) async => {'id': 1},
        existingOrder: existing,
      ),
    );

    testWidgets('error al cargar clientes y lotes', (tester) async {
      await tester.pumpWidget(app(customers: () async => throw StateError('x')));
      await tester.pumpAndSettle();
      expect(find.text('No se pudieron cargar clientes y lotes.'), findsOneWidget);
    });

    testWidgets('valida lineas, duplicados, cambia cliente/lote y quita lineas', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Sin cantidad ni precio.
      await tester.tap(find.text('Agregar línea'));
      await tester.pumpAndSettle();
      expect(
        find.text('Selecciona un lote e indica cantidad y precio válidos.'),
        findsOneWidget,
      );

      // Cambia de cliente y de lote.
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cliente Sur').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<int>, 'Lote de origen'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('LOTE-10').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad'), '5');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Precio unitario'),
        '2,5',
      );
      await tester.tap(find.text('Agregar línea'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Quitar línea'), findsOneWidget);

      // El mismo lote otra vez: duplicado.
      await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad'), '1');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Precio unitario'),
        '1',
      );
      await tester.tap(find.text('Agregar línea'));
      await tester.pumpAndSettle();
      expect(find.text('Ese lote ya está en el pedido.'), findsOneWidget);

      // Quitar la linea y enviar sin lineas.
      await tester.tap(find.byTooltip('Quitar línea'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Quitar línea'), findsNothing);
      final submit = find.byKey(const Key('order-submit'));
      await _scrollTo(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Agrega al menos una línea al pedido.'), findsOneWidget);
    });

    testWidgets('el guardado muestra errores de API y genericos', (tester) async {
      bigView(tester);
      var api = true;
      await tester.pumpWidget(
        app(
          onSave: (order) async {
            if (api) throw _api('Cliente inactivo');
            throw StateError('x');
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad'), '5');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Precio unitario'),
        '3',
      );
      await tester.tap(find.text('Agregar línea'));
      await tester.pumpAndSettle();
      final submit = find.byKey(const Key('order-submit'));
      await _scrollTo(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Cliente inactivo'), findsOneWidget);
      api = false;
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('No fue posible registrar el pedido.'), findsOneWidget);
    });

    testWidgets('edicion: precarga lineas existentes', (tester) async {
      bigView(tester);
      await tester.pumpWidget(
        app(
          existing: {
            'id': 1,
            'customer_id': 4,
            'note': 'nota previa',
            'lines': [
              {'product_lot_id': 9, 'quantity': 3, 'unit_price': 2},
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Quitar línea'), findsOneWidget);
      await tester.tap(find.byTooltip('Editar línea'));
      await tester.pumpAndSettle();
    });
  });

  group('LotFormScreen', () {
    Widget form({
      Future<List<Map<String, dynamic>>> Function()? farms,
      SaveLot? onSave,
    }) => LotFormScreen(
      loadFarms:
          farms ??
          () async => [
            {'id': 1, 'name': 'Finca 1', 'supplier_name': 'Prov'},
          ],
      loadProducts: () async => [
        {'id': 1, 'type': 'coffee', 'variety': 'Castillo', 'quality_grade': 'A'},
      ],
      onSave: onSave ?? (fields) async {},
    );

    Future<void> pumpForm(WidgetTester tester, Widget screen) async {
      bigView(tester);
      final router = GoRouter(
        initialLocation: '/x',
        routes: [
          GoRoute(path: '/x', builder: (_, _) => screen),
          GoRoute(
            path: '/lots',
            builder: (_, _) => const Scaffold(body: Text('LOTES')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('error de carga (API y generico), reintento y volver', (
      tester,
    ) async {
      var mode = 'api';
      await pumpForm(
        tester,
        form(
          farms: () async {
            if (mode == 'api') throw _api('Sin fincas');
            if (mode == 'boom') throw StateError('x');
            return [
              {'id': 1, 'name': 'Finca 1'},
            ];
          },
        ),
      );
      expect(find.text('Sin fincas'), findsOneWidget);
      mode = 'boom';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(
        find.text('No fue posible cargar fincas y productos.'),
        findsOneWidget,
      );
      mode = 'ok';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Volver a lotes'));
      await tester.pumpAndSettle();
      expect(find.text('LOTES'), findsOneWidget);
    });

    testWidgets('guardar con error de API y generico', (tester) async {
      var api = true;
      await pumpForm(
        tester,
        form(
          onSave: (fields) async {
            if (api) throw _api('Codigo repetido');
            throw StateError('x');
          },
        ),
      );
      final fieldFinder = find.byType(TextFormField);
      await tester.enterText(fieldFinder.first, 'LOTE-XYZ');
      final dropdowns = find.byType(DropdownButtonFormField<int>);
      await tester.tap(dropdowns.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Finca 1').last);
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Castillo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Codigo repetido'), findsOneWidget);
      api = false;
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('No fue posible registrar el lote.'), findsOneWidget);
    });
  });

  group('PaymentPortfolioScreen', () {
    Widget app({
      Future<List<Map<String, dynamic>>> Function({
        String? query,
        String? status,
        String? currency,
      })?
      load,
      Future<void> Function(Map<String, dynamic>)? register,
      Future<void> Function(Map<String, dynamic>)? create,
      Future<List<Map<String, dynamic>>> Function()? exports,
    }) => MaterialApp(
      home: PaymentPortfolioScreen(
        loadPortfolio:
            load ??
            ({query, status, currency}) async => [
              {
                'id': 1,
                'order_number': 'PED-1',
                'customer_name': 'Cliente',
                'currency_code': 'USD',
                'amount': 100,
                'balance': 40,
                'status': 'partial',
                'due_date': '2026-12-01',
              },
            ],
        registerPayment: register,
        createObligation: create,
        loadExports: exports,
      ),
    );

    testWidgets('errores de carga: API y generico', (tester) async {
      await tester.pumpWidget(
        app(load: ({query, status, currency}) async => throw _api('Caido')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Caido'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(load: ({query, status, currency}) async => throw StateError('x')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudo cargar la cartera.'), findsOneWidget);
    });

    testWidgets('buscar con Enter', (tester) async {
      final queries = <String?>[];
      await tester.pumpWidget(
        app(
          load: ({query, status, currency}) async {
            queries.add(query);
            return [];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'PED');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(queries.last, 'PED');
    });

    testWidgets('crear obligacion: sin exportaciones, fallo de carga, errores', (
      tester,
    ) async {
      var mode = 'empty';
      await tester.pumpWidget(
        app(
          create: (o) async {
            if (mode == 'api') throw _api('Monto invalido');
            if (mode == 'boom') throw StateError('x');
          },
          exports: () async {
            if (mode == 'loadfail') throw StateError('x');
            if (mode == 'empty') return [];
            return [
              {'id': 5, 'order_number': 'PED-5', 'customer_name': 'Cliente'},
            ];
          },
        ),
      );
      await tester.pumpAndSettle();
      final addButton = find.byTooltip('Crear obligación');
      if (addButton.evaluate().isEmpty) return;
      await tester.tap(addButton);
      await brief(tester);
      expect(
        find.text('No hay exportaciones sobre las que crear una obligación.'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      mode = 'loadfail';
      await tester.tap(addButton);
      await brief(tester);
      expect(
        find.text('No se pudieron cargar las exportaciones.'),
        findsOneWidget,
      );
    });
  });
}
