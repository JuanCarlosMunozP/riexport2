import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import '../support/local_backend_test_context.dart';

void main() {
  setUp(setUpLocalBackendTest);

  test('registra pedido con cliente, lote, cantidad y precio', () async {
    final customer =
        await api.post(
              '/customers',
              body: {
                'name': 'Comprador de prueba',
                'country_code': 'CO',
                'preferred_currency_code': 'COP',
              },
            )
            as Map;
    final product =
        await api.post(
              '/products',
              body: {
                'type': 'coffee',
                'variety': 'Caturra',
                'quality_grade': 'Excelso',
                'base_unit_code': 'kg',
                'humidity_percent': 11.5,
              },
            )
            as Map;
    final supplier =
        await api.post(
              '/suppliers',
              body: {
                'business_name': 'Proveedor de prueba',
                'tax_id': 'CO123456',
              },
            )
            as Map;
    final farm =
        await api.post(
              '/farms',
              body: {
                'supplier_id': supplier['id'],
                'country_code': 'CO',
                'name': 'Finca de prueba',
              },
            )
            as Map;
    final lot =
        await api.post(
              '/lots',
              body: {
                'product_id': product['id'],
                'farm_id': farm['id'],
                'lot_code': 'LOTE-001',
              },
            )
            as Map;
    await api.post(
      '/inventory/adjustments',
      body: {'product_lot_id': lot['id'], 'quantity_delta': 200},
    );

    final order =
        await api.post(
              '/orders',
              body: {
                'customer_id': customer['id'],
                // Payload de prueba: se conserva como texto y nunca se interpreta como SQL.
                'note': "'; DROP TABLE customer_order; --",
                'lines': [
                  {
                    'product_lot_id': lot['id'],
                    'quantity': 125.5,
                    'unit_price': 8400,
                  },
                ],
              },
            )
            as Map;

    expect(order['order_number'], startsWith('PED-'));
    expect(order['customer_id'], customer['id']);
    expect(order['currency_code'], 'COP');
    expect(order['status'], 'draft');
    expect(order['note'], "'; DROP TABLE customer_order; --");
    expect((order['lines'] as List).single['lot_code'], 'LOTE-001');

    final confirmed =
        await api.patch(
              '/orders/${order['id']}/status',
              body: {'status': 'confirmed'},
            )
            as Map;
    expect(confirmed['status'], 'confirmed');
    await expectLater(
      api.patch('/orders/${order['id']}/status', body: {'status': 'draft'}),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 422),
      ),
    );
    final cancelled =
        await api.patch(
              '/orders/${order['id']}/status',
              body: {'status': 'cancelled'},
            )
            as Map;
    expect(cancelled['status'], 'cancelled');
    await expectLater(
      api.patch('/orders/${order['id']}/status', body: {'status': 'confirmed'}),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 422),
      ),
    );
    final orders =
        await api.get(
              '/orders',
              queryParameters: {'q': 'Comprador', 'status': 'cancelled'},
            )
            as Map;
    expect((orders['items'] as List).single['status'], 'cancelled');
    expect((orders['pagination'] as Map)['total'], 1);
    expect(
      ((orders['items'] as List).single['status_history'] as List).length,
      3,
    );
  });

  test('edita pedidos borrador y registra exportaciones parciales', () async {
    final customer =
        await api.post(
              '/customers',
              body: {
                'name': 'Importadora del Norte',
                'country_code': 'DE',
                'eori_number': 'DE12345678901',
                'preferred_currency_code': 'EUR',
              },
            )
            as Map;
    final product =
        await api.post(
              '/products',
              body: {
                'type': 'coffee',
                'variety': 'Caturra',
                'quality_grade': 'Excelso',
                'base_unit_code': 'kg',
                'humidity_percent': 11.5,
              },
            )
            as Map;
    final supplier =
        await api.post(
              '/suppliers',
              body: {
                'business_name': 'Cooperativa Andina',
                'tax_id': 'CO987654',
              },
            )
            as Map;
    final farm =
        await api.post(
              '/farms',
              body: {
                'supplier_id': supplier['id'],
                'country_code': 'CO',
                'name': 'Finca Andina',
                'latitude': 4.5,
                'longitude': -75.6,
              },
            )
            as Map;
    final lot =
        await api.post(
              '/lots',
              body: {
                'product_id': product['id'],
                'farm_id': farm['id'],
                'lot_code': 'LOTE-EDIT',
              },
            )
            as Map;
    await api.post(
      '/inventory/adjustments',
      body: {'product_lot_id': lot['id'], 'quantity_delta': 100},
    );

    final order =
        await api.post(
              '/orders',
              body: {
                'customer_id': customer['id'],
                'note': 'Original',
                'lines': [
                  {
                    'product_lot_id': lot['id'],
                    'quantity': 20,
                    'unit_price': 4,
                  },
                ],
              },
            )
            as Map;
    final updated =
        await api.patch(
              '/orders/${order['id']}',
              body: {
                'customer_id': customer['id'],
                'note': 'Actualizado',
                'lines': [
                  {
                    'product_lot_id': lot['id'],
                    'quantity': 30,
                    'unit_price': 5,
                  },
                ],
              },
            )
            as Map;
    expect(updated['note'], 'Actualizado');
    expect(updated['order_total'], 150);
    final available =
        await api.get('/inventory', queryParameters: {'q': 'LOTE-EDIT'}) as Map;
    expect((available['items'] as List).single['available_quantity'], 70);

    final lineId = ((updated['lines'] as List).single as Map)['order_line_id'];
    await api.patch(
      '/orders/${order['id']}/status',
      body: {'status': 'confirmed'},
    );
    await expectLater(
      api.patch(
        '/orders/${order['id']}',
        body: {
          'customer_id': customer['id'],
          'lines': [
            {'product_lot_id': lot['id'], 'quantity': 1, 'unit_price': 1},
          ],
        },
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
    );

    final destinations = await api.get('/export-catalogs/destinations') as Map;
    final terms = await api.get('/export-catalogs/incoterms') as Map;
    expect(
      (destinations['items'] as List).any((item) => item['code'] == 'DE'),
      isTrue,
    );
    expect(
      (terms['items'] as List).any((item) => item['code'] == 'FOB'),
      isTrue,
    );

    final first =
        await api.post(
              '/exports',
              body: {
                'order_id': order['id'],
                'destination_country_code': 'DE',
                'incoterm_code': 'FOB',
                'lines': [
                  {'order_line_id': lineId, 'quantity': 12},
                ],
              },
            )
            as Map;
    final second =
        await api.post(
              '/exports',
              body: {
                'order_id': order['id'],
                'destination_country_code': 'DE',
                'lines': [
                  {'order_line_id': lineId, 'quantity': 18},
                ],
              },
            )
            as Map;
    expect(first['incoterm_code'], 'FOB');
    expect(second['incoterm_code'], isNull);
    expect((first['lines'] as List).single['hs_code_snapshot'], '0901.11');
    final traceability =
        await api.get('/exports/${first['id']}/traceability') as Map;
    expect((traceability['items'] as List), isNotEmpty);
    expect(
      (traceability['items'] as List).single['hs_code_snapshot'],
      '0901.11',
    );
    final eudr = await api.get('/exports/${first['id']}/eudr') as Map;
    expect(eudr['traceability_valid'], isTrue, reason: '${eudr['issues']}');
    expect(eudr['hs_codes'], contains('0901.11'));
    await expectLater(
      api.post(
        '/exports',
        body: {
          'order_id': order['id'],
          'destination_country_code': 'DE',
          'lines': [
            {'order_line_id': lineId, 'quantity': 1},
          ],
        },
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
    );
    final exports = await api.get('/exports') as Map;
    expect(exports['items'], hasLength(2));
  });
}
