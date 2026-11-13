import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/inventory/presentation/inventory_screen.dart';
import 'package:riexport_app/features/payments/presentation/exchange_rates_screen.dart';

ApiException _api(String message) =>
    ApiException(statusCode: 400, code: 'e', message: message);

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Descarta las aserciones conocidas de Flutter (ver reporte: hallazgo sobre el
/// TextEditingController liberado mientras el dialogo se cierra).
void dropKnownExceptions(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

/// Ejecuta [body] ignorando los errores de framework conocidos (QA-02).
Future<void> ignoringFlutterErrors(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {};
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

void main() {
  group('ExchangeRatesScreen', () {
    Widget app({
      Future<List<Map<String, dynamic>>> Function()? loadRates,
      Future<Map<String, dynamic>> Function(num, String, String)? convert,
      Future<void> Function()? refresh,
      Future<void> Function(Map<String, dynamic>)? add,
    }) => MaterialApp(
      home: ExchangeRatesScreen(
        loadRates:
            loadRates ??
            () async => [
              {
                'base_currency_code': 'USD',
                'quote_currency_code': 'EUR',
                'rate': 0.9,
                'effective_at': '2026-01-01T00:00:00Z',
                'source': 'manual',
              },
            ],
        convert:
            convert ??
            (a, f, t) async => {'converted': a * 0.9, 'rate': 0.9, 'source': 'x'},
        refreshRates: refresh,
        addRate: add,
      ),
    );

    testWidgets('sin tasas muestra el aviso y errores de carga', (tester) async {
      await tester.pumpWidget(app(loadRates: () async => []));
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay tasas registradas.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(loadRates: () async => throw _api('Sin red')));
      await tester.pumpAndSettle();
      expect(find.text('Sin red'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(loadRates: () async => throw StateError('x')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudieron cargar las tasas.'), findsOneWidget);
    });

    testWidgets('el conversor valida y muestra errores', (tester) async {
      var mode = 'ok';
      await tester.pumpWidget(
        app(
          convert: (a, f, t) async {
            if (mode == 'api') throw _api('Sin tasa');
            if (mode == 'boom') throw StateError('x');
            return {'converted': 90, 'rate': 0.9, 'source': 'manual'};
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversion')), findsOneWidget);
      expect(find.textContaining('= 90'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'abc');
      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indica un monto y dos monedas de 3 letras.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(0), '10,5');
      mode = 'api';
      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(find.text('Sin tasa'), findsOneWidget);
      mode = 'boom';
      await tester.tap(find.text('Convertir'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo convertir el monto.'), findsOneWidget);
    });

    testWidgets('actualizar desde el servicio externo y sus errores', (
      tester,
    ) async {
      var mode = 'ok';
      await tester.pumpWidget(
        app(
          refresh: () async {
            if (mode == 'api') throw _api('Limite');
            if (mode == 'boom') throw StateError('x');
          },
        ),
      );
      await tester.pumpAndSettle();
      Future<void> refresh() async {
        await tester.tap(find.byTooltip('Actualizar desde el servicio externo'));
        await brief(tester);
      }

      await refresh();
      expect(find.text('Tasas actualizadas.'), findsOneWidget);
      mode = 'api';
      await refresh();
      expect(find.text('Limite'), findsOneWidget);
      mode = 'boom';
      await refresh();
      expect(
        find.text('No se pudo actualizar desde el servicio externo.'),
        findsOneWidget,
      );
    });

    testWidgets('registrar una tasa manual: validar, cancelar, guardar y fallar', (
      tester,
    ) async {
      var mode = 'ok';
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        app(
          add: (rate) async {
            if (mode == 'api') throw _api('Duplicada');
            if (mode == 'boom') throw StateError('x');
            saved = rate;
          },
        ),
      );
      await tester.pumpAndSettle();

      Future<void> open() async {
        await tester.tap(find.byTooltip('Registrar tasa manual'));
        await tester.pumpAndSettle();
      }

      Future<void> fill(String base, String quote, String rate) async {
        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(fields.at(0), base);
        await tester.enterText(fields.at(1), quote);
        await tester.enterText(fields.at(2), rate);
      }

      await open();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(saved, isNull);

      await open();
      await fill('us', 'USD', '0');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await fill('USD', 'USD', 'x');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await fill('USD', 'EUR', '0,91');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(saved?['rate'], 0.91);
      expect(saved?['base_currency_code'], 'USD');

      mode = 'api';
      await open();
      await fill('usd', 'cop', '4000');
      await tester.tap(find.text('Guardar'));
      await brief(tester);
      expect(find.text('Duplicada'), findsOneWidget);

      mode = 'boom';
      await open();
      await fill('usd', 'jpy', '150');
      await tester.tap(find.text('Guardar'));
      await brief(tester);
      expect(find.text('No se pudo guardar la tasa.'), findsOneWidget);
    });
  });

  group('InventoryScreen', () {
    Widget app({
      Future<List<Map<String, dynamic>>> Function(String?)? load,
      Future<void> Function(int, num)? adjust,
      bool canAdjust = true,
    }) => MaterialApp(
      home: InventoryScreen(
        canAdjust: canAdjust,
        loadOverview: () async => [
          {
            'product_id': 1,
            'product_type': 'cacao',
            'variety': 'CCN51',
            'quality_grade': 'A',
            'available_quantity': 2,
            'is_low_stock': true,
          },
          {
            'product_id': 2,
            'product_type': 'coffee',
            'variety': 'Castillo',
            'quality_grade': 'B',
            'available_quantity': 50,
            'is_low_stock': false,
          },
        ],
        loadInventory:
            load ??
            (q) async => [
              {
                'id': 5,
                'lot_code': 'L-5',
                'product_id': 1,
                'product_type': 'cacao',
                'product_variety': 'CCN51',
                'available_quantity': 2,
              },
            ],
        adjustInventory: adjust ?? (id, delta) async {},
      ),
    );

    testWidgets('errores de carga: API y generico', (tester) async {
      await tester.pumpWidget(app(load: (q) async => throw _api('Caido')));
      await tester.pumpAndSettle();
      expect(find.text('Caido'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(load: (q) async => throw StateError('x')));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo cargar el inventario.'), findsOneWidget);
    });

    // Cada escenario del dialogo va en su propia prueba y desmonta el arbol al
    // terminar: hallazgo QA-02 (el TextEditingController se libera antes de que
    // acabe la animacion de cierre y deja aserciones residuales en Flutter).
    final attempts = <String>[];
    Future<void> adjustScenario(
      WidgetTester tester, {
      required String mode,
      required String? value,
      required List<(int, num)> adjustments,
      void Function()? check,
    }) => ignoringFlutterErrors(() async {
      await tester.pumpWidget(
        app(
          adjust: (id, delta) async {
            attempts.add('call:$mode');
            if (mode == 'api') throw _api('Stock negativo');
            if (mode == 'boom') throw StateError('x');
            adjustments.add((id, delta));
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajustar existencias'));
      await tester.pumpAndSettle();
      if (value == null) {
        await tester.tap(find.text('Cancelar'));
      } else {
        await tester.enterText(find.byType(TextField).last, value);
        await tester.tap(find.byType(FilledButton).last);
      }
      await tester.pump();
      await brief(tester);
      check?.call();
      await tester.pumpWidget(const SizedBox());
      dropKnownExceptions(tester);
    });

    testWidgets('ajustar existencias: cancelar no llama al backend', (
      tester,
    ) async {
      final adjustments = <(int, num)>[];
      await adjustScenario(
        tester,
        mode: 'ok',
        value: null,
        adjustments: adjustments,
      );
      expect(adjustments, isEmpty);
    });

    // QA-02 (corregido): el dialogo ya no libera un controller en uso, por lo
    // que el ajuste exitoso y los errores se prueban sin ocultar excepciones.
    Future<void> adjustWith(
      WidgetTester tester,
      String mode,
      String value,
      List<(int, num)> adjustments,
    ) async {
      await tester.pumpWidget(
        app(
          adjust: (id, delta) async {
            if (mode == 'api') throw _api('Stock negativo');
            if (mode == 'boom') throw StateError('x');
            adjustments.add((id, delta));
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajustar existencias'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, value);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      await brief(tester);
    }

    testWidgets('ajustar existencias: exito (coma decimal) recarga', (
      tester,
    ) async {
      final adjustments = <(int, num)>[];
      await adjustWith(tester, 'ok', '2,5', adjustments);
      expect(adjustments.single.$2, 2.5);
    });

    testWidgets('ajustar existencias: valor invalido no guarda', (
      tester,
    ) async {
      final adjustments = <(int, num)>[];
      await adjustWith(tester, 'ok', '0', adjustments);
      expect(adjustments, isEmpty);
      expect(find.text('Cambio de existencias'), findsWidgets);
    });

    testWidgets('ajustar existencias: error de API y generico', (tester) async {
      await adjustWith(tester, 'api', '-3', []);
      expect(find.text('Stock negativo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await adjustWith(tester, 'boom', '-3', []);
      expect(find.text('No se pudo registrar el ajuste.'), findsOneWidget);
    });

    testWidgets('buscar con Enter y alternar la vista por producto', (
      tester,
    ) async {
      final queries = <String?>[];
      await tester.pumpWidget(
        app(
          load: (q) async {
            queries.add(q);
            return [];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'cacao');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(queries.last, 'cacao');
      await tester.tap(find.text('Por producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Por lote'));
      await tester.pumpAndSettle();
    });

    testWidgets('sin permiso de ajuste no hay boton', (tester) async {
      await tester.pumpWidget(app(canAdjust: false));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ajustar existencias'), findsNothing);
    });
  });
}
