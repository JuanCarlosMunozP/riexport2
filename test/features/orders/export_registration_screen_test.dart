import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/features/orders/presentation/export_registration_screen.dart';

void main() {
  testWidgets('registra una exportación parcial con Incoterm opcional', (
    tester,
  ) async {
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ExportRegistrationScreen(
          loadOrders: () async => [
            {
              'id': 7,
              'order_number': 'PED-7',
              'customer_name': 'Cliente Norte',
              'status': 'confirmed',
              'lines': [
                {
                  'id': 41,
                  'order_line_id': 41,
                  'product_lot_id': 9,
                  'lot_code': 'LOTE-9',
                  'quantity': 20,
                  'remaining_quantity': 15,
                },
              ],
            },
          ],
          loadDestinations: () async => [
            {'code': 'DE', 'name': 'Alemania'},
          ],
          loadIncoterms: () async => [
            {'code': 'FOB', 'name': 'Franco a bordo'},
          ],
          onSave: (export) async {
            saved = export;
            return {'id': 12};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('export-quantity-41')), '5.5');
    final submit = find.byKey(const Key('export-submit'));
    for (var attempt = 0; attempt < 5 && submit.evaluate().isEmpty; attempt++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved?['order_id'], 7);
    expect(saved?['destination_country_code'], 'DE');
    expect(saved?['incoterm_code'], isNull);
    expect((saved?['lines'] as List).single, {
      'order_line_id': 41,
      'quantity': 5.5,
    });
  });

  testWidgets('muestra el HS asignado en la línea exportada', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExportRegistrationScreen(
          loadOrders: () async => [
            {
              'id': 9,
              'order_number': 'PED-9',
              'customer_name': 'Cliente Norte',
              'status': 'confirmed',
              'lines': [
                {
                  'id': 61,
                  'order_line_id': 61,
                  'lot_code': 'LOTE-61',
                  'quantity': 10,
                  'remaining_quantity': 10,
                  'hs_code_snapshot': '0901.11',
                },
              ],
            },
          ],
          loadDestinations: () async => [
            {'code': 'DE', 'name': 'Alemania'},
          ],
          loadIncoterms: () async => const [],
          onSave: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('HS 0901.11'), findsOneWidget);
  });

  testWidgets('no permite exceder la cantidad restante', (tester) async {
    var saveCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ExportRegistrationScreen(
          loadOrders: () async => [
            {
              'id': 8,
              'status': 'confirmed',
              'lines': [
                {
                  'id': 51,
                  'order_line_id': 51,
                  'quantity': 10,
                  'remaining_quantity': 2,
                },
              ],
            },
          ],
          loadDestinations: () async => [
            {'code': 'DE', 'name': 'Alemania'},
          ],
          loadIncoterms: () async => const [],
          onSave: (_) async {
            saveCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('export-quantity-51')), '3');
    final submit = find.byKey(const Key('export-submit'));
    for (var attempt = 0; attempt < 5 && submit.evaluate().isEmpty; attempt++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(saveCalls, 0);
    expect(
      find.text(
        'Cada cantidad debe ser positiva y no superar el saldo disponible.',
      ),
      findsOneWidget,
    );
  });
}
