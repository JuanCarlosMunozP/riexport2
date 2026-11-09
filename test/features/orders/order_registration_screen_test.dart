import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/features/orders/presentation/order_registration_screen.dart';

void main() {
  testWidgets('crea un pedido con cliente, lote y línea de precio', (
    tester,
  ) async {
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: OrderRegistrationScreen(
          loadCustomers: () async => [
            {
              'id': 3,
              'name': 'Cliente Norte',
              'is_active': true,
              'preferred_currency_code': 'EUR',
            },
          ],
          loadLots: () async => [
            {
              'id': 9,
              'lot_code': 'LOTE-9',
              'product_variety': 'Caturra',
              'product_quality': 'Excelso',
              'farm_name': 'Finca 1',
            },
          ],
          onSave: (order) async {
            saved = order;
            return {'id': 1, 'order_number': 'PED-2026-000001'};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cantidad'),
      '12.5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Precio unitario'),
      '8.75',
    );
    await tester.tap(find.text('Agregar línea'));
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('order-submit'));
    for (var attempt = 0; attempt < 4 && submit.evaluate().isEmpty; attempt++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      saved,
      isNotNull,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .join(' | '),
    );
    expect(saved?['customer_id'], 3);
    expect((saved?['lines'] as List).single, {
      'product_lot_id': 9,
      'quantity': 12.5,
      'unit_price': 8.75,
    });
  });

  testWidgets('edita línea y recalcula el total del pedido pendiente', (
    tester,
  ) async {
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: OrderRegistrationScreen(
          existingOrder: {
            'id': 17,
            'status': 'draft',
            'customer_id': 3,
            'note': 'Nota anterior',
            'lines': [
              {
                'id': 41,
                'order_line_id': 41,
                'product_lot_id': 9,
                'lot_code': 'LOTE-9',
                'quantity': 2,
                'unit_price': 10,
              },
            ],
          },
          loadCustomers: () async => [
            {
              'id': 3,
              'name': 'Cliente Norte',
              'is_active': true,
              'preferred_currency_code': 'EUR',
            },
          ],
          loadLots: () async => [
            {
              'id': 9,
              'lot_code': 'LOTE-9',
              'product_variety': 'Caturra',
              'product_quality': 'Excelso',
              'farm_name': 'Finca 1',
            },
          ],
          onSave: (order) async {
            saved = order;
            return {'id': 17};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar línea'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad'), '4');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Precio unitario'),
      '12.5',
    );
    await tester.tap(find.text('Actualizar línea'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Total estimado: 50.00 EUR'), findsOneWidget);

    final submit = find.byKey(const Key('order-submit'));
    for (var attempt = 0; attempt < 5 && submit.evaluate().isEmpty; attempt++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(saved?['customer_id'], 3);
    expect((saved?['lines'] as List).single, {
      'product_lot_id': 9,
      'quantity': 4,
      'unit_price': 12.5,
    });
  });
}
