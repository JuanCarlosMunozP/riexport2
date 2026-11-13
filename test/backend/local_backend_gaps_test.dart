import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:riexport_app/backend/local_backend_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';

import '../support/local_backend_test_context.dart';

Future<Object?> t(Future<Object?> f) async {
  try {
    return await f;
  } on ApiException catch (e) {
    return e;
  }
}

Future<Map> post(String p, Object? b) async =>
    (await api.post(p, body: b)) as Map;

Future<void> expectStatus(Future<Object?> f, int status) async {
  final r = await t(f);
  expect(r, isA<ApiException>(), reason: 'se esperaba error $status');
  expect((r as ApiException).statusCode, status);
}

void main() {
  setUp(setUpLocalBackendTest);

  test('filtros de listados, inventario y exportaciones', () async {
    final customer = await post('/customers', {
      'name': 'Comprador',
      'country_code': 'CO',
      'preferred_currency_code': 'COP',
    });
    final product = await post('/products', {
      'type': 'coffee',
      'variety': 'Caturra',
      'quality_grade': 'Excelso',
      'base_unit_code': 'kg',
      'humidity_percent': 11.5,
      'low_stock_threshold': 500,
    });
    final cacao = await post('/products', {
      'type': 'cacao',
      'variety': 'CCN51',
      'quality_grade': 'Premium',
      'base_unit_code': 'kg',
      'bean_type': 'forastero',
      'fermentation_percent': 70,
    });
    final supplier = await post('/suppliers', {
      'business_name': 'Proveedor',
      'tax_id': 'CO123456',
    });
    final farm = await post('/farms', {
      'supplier_id': supplier['id'],
      'country_code': 'CO',
      'name': 'Finca Uno',
    });
    await post('/farms', {
      'supplier_id': supplier['id'],
      'country_code': 'CO',
      'name': 'Finca Dos',
    });
    final lot = await post('/lots', {
      'product_id': product['id'],
      'farm_id': farm['id'],
      'lot_code': 'L-1',
    });
    await post('/lots', {
      'product_id': cacao['id'],
      'farm_id': farm['id'],
      'lot_code': 'L-2',
    });
    await post('/inventory/adjustments', {
      'product_lot_id': lot['id'],
      'quantity_delta': 300,
    });

    // Inventario: resumen y solo stock bajo.
    final ov = await api.get('/inventory/overview') as Map;
    expect((ov['items'] as List), isNotEmpty);
    final low = await api.get('/inventory/overview?low_stock=true') as Map;
    expect((low['items'] as List).first['is_low_stock'], true);
    await api.get('/inventory');
    await expectStatus(
      api.post(
        '/inventory/adjustments',
        body: {'product_lot_id': lot['id'], 'quantity_delta': -9999},
      ),
      422,
    );
    await expectStatus(
      api.post('/inventory/adjustments', body: {'otro': 1}),
      422,
    );

    // Filtros de fincas, lotes y productos.
    await api.get('/farms?q=uno&supplier_id=${supplier['id']}&is_active=true');
    await api.get('/farms?is_active=false');
    await api.get(
      '/lots?farm_id=${farm['id']}&product_id=${product['id']}&q=l-',
    );
    await api.get('/products?quality=exce&type=coffee&is_active=true');
    await api.get('/products?certification_id=1');

    // Pedido y exportaciones con filtros.
    final order = await post('/orders', {
      'customer_id': customer['id'],
      'lines': [
        {'product_lot_id': lot['id'], 'quantity': 100, 'unit_price': 5},
      ],
    });
    await api.get('/orders?customer_id=${customer['id']}&status=draft&q=comp');
    final lineId = (order['lines'] as List).first['id'];
    await api.patch('/orders/${order['id']}/status', body: {'status': 'confirmed'});
    await post('/exports', {
      'order_id': order['id'],
      'destination_country_code': 'DE',
      'lines': [
        {'order_line_id': lineId, 'quantity': 10},
      ],
    });
    await api.get('/exports?status=registered&q=de');
    await api.get('/exports?q=comprador');
    await api.get('/exports?status=nada');

    // Pedidos: lineas invalidas, duplicadas y nota larga.
    for (final lines in <Object?>[
      ['x'],
      [
        {'product_lot_id': lot['id'], 'quantity': 0, 'unit_price': 1},
      ],
      [
        {'product_lot_id': lot['id'], 'quantity': 1, 'unit_price': 1},
        {'product_lot_id': lot['id'], 'quantity': 2, 'unit_price': 1},
      ],
    ]) {
      await t(
        api.post(
          '/orders',
          body: {'customer_id': customer['id'], 'lines': lines},
        ),
      );
      await t(api.patch('/orders/${order['id']}', body: {'lines': lines}));
    }
    await t(api.patch('/orders/${order['id']}', body: {'note': 'x' * 600}));
    await t(
      api.post(
        '/orders',
        body: {
          'customer_id': customer['id'],
          'note': 'x' * 600,
          'lines': [
            {'product_lot_id': lot['id'], 'quantity': 1, 'unit_price': 1},
          ],
        },
      ),
    );
    for (final extra in <Map<String, Object?>>[
      {
        'lines': ['x'],
      },
      {
        'export_date': '2026-03-01',
        'lines': [
          {'order_line_id': lineId, 'quantity': 1},
        ],
      },
      {
        'export_date': 'basura',
        'lines': [
          {'order_line_id': lineId, 'quantity': 1},
        ],
      },
    ]) {
      await t(
        api.post(
          '/exports',
          body: {
            'order_id': order['id'],
            'destination_country_code': 'DE',
            ...extra,
          },
        ),
      );
    }

    // Productos: validaciones.
    final pid = product['id'];
    for (final body in <Map<String, Object?>>[
      {'low_stock_threshold': -1},
      {'low_stock_threshold': 'x'},
      {'variety': 'v' * 300},
      {'variety': ''},
      {'variety': 5},
      {'quality_grade': 'q' * 300},
      {'quality_grade': ''},
      {'bean_type': 'x'},
      {'fermentation_percent': 50},
    ]) {
      await t(api.patch('/products/$pid', body: body));
    }
    for (final body in <Map<String, Object?>>[
      {'bean_type': ''},
      {'fermentation_percent': 500},
      {'fermentation_percent': 'x'},
      {'bean_type': 5},
    ]) {
      await t(api.patch('/products/${cacao['id']}', body: body));
    }
    await t(
      api.post(
        '/products',
        body: {
          'type': 'cacao',
          'variety': 'A',
          'quality_grade': 'B',
          'base_unit_code': 'kg',
        },
      ),
    );
    await t(
      api.post(
        '/products',
        body: {
          'type': 'cacao',
          'variety': 'A',
          'quality_grade': 'B',
          'base_unit_code': 'kg',
          'bean_type': 'z' * 300,
          'fermentation_percent': 'x',
        },
      ),
    );

    // Fincas: validaciones y cambios de coordenadas.
    final fid = farm['id'];
    for (final body in <Map<String, Object?>>[
      {'country_code': 'ZZ'},
      {'country_code': ''},
      {'address': 'a' * 400},
      {'address': 5},
      {'latitude': 4.5, 'longitude': -75.1},
      {'latitude': 4.6},
      {'latitude': null, 'longitude': null},
      {'latitude': 200},
      {'name': ''},
      {'name': 7},
    ]) {
      await t(api.patch('/farms/$fid', body: body));
    }
    await t(
      api.post('/farms', body: {'supplier_id': supplier['id'], 'name': 'F'}),
    );
    await t(
      api.post(
        '/farms',
        body: {
          'supplier_id': supplier['id'],
          'name': 'F',
          'country_code': 'CO',
          'address': 5,
        },
      ),
    );
    await t(
      api.post(
        '/lots',
        body: {'product_id': pid, 'farm_id': fid, 'lot_code': 5},
      ),
    );
    await t(
      api.post(
        '/lots',
        body: {'product_id': pid, 'farm_id': fid, 'lot_code': 'x' * 200},
      ),
    );

    // Proveedores y clientes.
    var n = 0;
    for (final body in <Map<String, Object?>>[
      {'phone': 'abc'},
      {'phone': '1' * 40},
      {'email': 'malo'},
      {'email': 'Bueno@Correo.com'},
      {'phone': '+57 300 1234567'},
    ]) {
      n++;
      await t(api.patch('/suppliers/${supplier['id']}', body: body));
      await t(
        api.post(
          '/suppliers',
          body: {'business_name': 'Otro $n', 'tax_id': 'T$n', ...body},
        ),
      );
    }
    for (final body in <Map<String, Object?>>[
      {'email': 'malo'},
      {'email': 'Cli@Correo.com'},
      {'country_code': ''},
      {'country_code': 'ZZ'},
      {'phone': 'abc'},
      {'tax_id': 5},
      {'preferred_currency_code': 'XXX'},
    ]) {
      await t(api.patch('/customers/${customer['id']}', body: body));
      await t(api.post('/customers', body: {'name': 'C', ...body}));
    }
    await t(api.post('/customers', body: {'name': 'C2', 'email': 'a@b.co'}));
    await t(
      api.post(
        '/customers',
        body: {'name': 'C3', 'country_code': 'CO', 'email': 'Z@Z.co'},
      ),
    );
  });

  test('usuarios y roles: protecciones y errores', () async {
    final roles = (await api.get('/roles') as Map)['items'] as List;
    final admin = roles.firstWhere((r) => r['name'] == 'administrador');
    final other = roles.firstWhere((r) => r['name'] != 'administrador');
    final users = (await api.get('/users') as Map)['items'] as List;
    final me = users.first['id'];

    await t(api.patch('/users/$me/deactivate'));
    await t(api.patch('/users/$me', body: {'role_id': other['id']}));
    final u2 = await post('/users', {
      'email': 'dos@correo.com',
      'password': 'Secreto123!',
      'first_name': 'Dos',
      'last_name': 'Usuario',
      'role_id': other['id'],
      'phone': '3001234567',
    });
    for (final body in <Map<String, Object?>>[
      {'role_id': admin['id']},
      {'phone': '9' * 50},
      {'phone': 'abc'},
      {'email': 'nuevo@correo.com'},
      {'email': 5},
      {'role_id': 'x'},
      {'role_id': 9999},
    ]) {
      await t(api.patch('/users/${u2['id']}', body: body));
    }
    for (final extra in <Map<String, Object?>>[
      {},
      {'role_id': 'x'},
    ]) {
      await t(
        api.post(
          '/users',
          body: {
            'email': 'tres@correo.com',
            'password': 'Secreto123!',
            'first_name': 'T',
            'last_name': 'T',
            ...extra,
          },
        ),
      );
    }
    await t(
      api.post(
        '/users',
        body: {
          'password': 'Secreto123!',
          'first_name': 'T',
          'last_name': 'T',
          'role_id': other['id'],
        },
      ),
    );
    await t(api.patch('/users/${u2['id']}/deactivate'));
    await t(api.patch('/users/${u2['id']}/activate'));

    final u3 = await post('/users', {
      'email': 'adm2@correo.com',
      'password': 'Secreto123!',
      'first_name': 'A',
      'last_name': 'D',
      'role_id': admin['id'],
    });
    await t(api.patch('/users/${u3['id']}', body: {'role_id': other['id']}));
    await t(api.patch('/users/${u3['id']}/deactivate'));

    final r = await post('/roles', {'name': 'auditor', 'description': 'x'});
    await t(api.post('/roles', body: {'name': 'auditor'}));
    for (final body in <Map<String, Object?>>[
      {},
      {'name': 'administrador'},
      {'description': 'd' * 600},
      {'name': ''},
      {'name': 5},
    ]) {
      await t(api.patch('/roles/${r['id']}', body: body));
    }
    await t(api.patch('/roles/${admin['id']}', body: {'name': 'otro'}));
    for (final codes in <Object?>[
      'x',
      ['users.read', 'users.read'],
      ['no.existe'],
    ]) {
      await t(
        api.put(
          '/roles/${r['id']}/permissions',
          body: {'permission_codes': codes},
        ),
      );
    }
    await t(
      api.put(
        '/roles/${admin['id']}/permissions',
        body: {
          'permission_codes': ['users.read'],
        },
      ),
    );
    await t(api.patch('/roles/${admin['id']}/deactivate'));
    await t(api.patch('/roles/${other['id']}/deactivate'));
    await t(api.patch('/roles/${r['id']}/deactivate'));
    await t(api.patch('/users/${u2['id']}', body: {'role_id': r['id']}));
    await t(api.patch('/users/${u2['id']}/activate'));
  });

  test('envios, pagos y obligaciones en modo demo', () async {
    await t(api.get('/shipments/99999'));
    await t(api.get('/shipments/99999/events'));
    await t(api.post('/payments/obligations', body: {'export_id': 1}));
    await t(
      api.post(
        '/payments/obligations',
        body: {
          'export_id': 77,
          'amount': 100,
          'currency_code': 'EUR',
          'due_date': '2026-12-31',
          'reference': 'REF',
        },
      ),
    );
    await api.get('/payments/portfolio');
  });

  test('edicion de pedido borrador, obligaciones y JSON invalido', () async {
    final customer = await post('/customers', {
      'name': 'Cliente E',
      'country_code': 'CO',
      'preferred_currency_code': 'COP',
    });
    final product = await post('/products', {
      'type': 'coffee',
      'variety': 'Caturra',
      'quality_grade': 'Excelso',
      'base_unit_code': 'kg',
      'humidity_percent': 11.5,
    });
    final supplier = await post('/suppliers', {
      'business_name': 'Prov E',
      'tax_id': 'CO999',
    });
    final farm = await post('/farms', {
      'supplier_id': supplier['id'],
      'country_code': 'CO',
      'name': 'Finca E',
    });
    final lot = await post('/lots', {
      'product_id': product['id'],
      'farm_id': farm['id'],
      'lot_code': 'LE-1',
    });
    await post('/inventory/adjustments', {
      'product_lot_id': lot['id'],
      'quantity_delta': 500,
    });
    final order = await post('/orders', {
      'customer_id': customer['id'],
      'lines': [
        {'product_lot_id': lot['id'], 'quantity': 10, 'unit_price': 2},
      ],
    });
    final id = order['id'];
    final good = {'product_lot_id': lot['id'], 'quantity': 20, 'unit_price': 3};
    for (final lines in <Object?>[
      ['x'],
      [
        {...good, 'otro': 1},
      ],
      [
        {...good, 'quantity': 0},
      ],
      [
        {...good, 'unit_price': -1},
      ],
      [
        {...good, 'product_lot_id': 'x'},
      ],
      [good, good],
    ]) {
      await t(api.patch('/orders/$id',
          body: {'customer_id': customer['id'], 'lines': lines}));
    }
    await t(api.patch('/orders/$id',
        body: {'customer_id': customer['id'], 'note': 'x' * 600}));
    await t(api.patch('/orders/$id',
        body: {'customer_id': customer['id'], 'note': 5}));
    await t(
      api.patch(
        '/orders/$id',
        body: {
          'customer_id': customer['id'],
          'lines': [good],
        },
      ),
    );
    await t(api.patch('/orders/$id', body: {'note': 'ok'}));

    for (final body in <Map<String, Object?>>[
      {'export_id': 1},
      {'amount_due': 0},
      {'amount_due': 'x'},
      {'amount_due': 100, 'export_id': 1},
      {
        'amount_due': 50,
        'export_id': 77,
        'currency_code': 'EUR',
        'due_date': '2026-12-31',
        'reference': 'REF',
      },
    ]) {
      await t(api.post('/payments/obligations', body: body));
    }

    final raw = LocalBackendClient();
    final login = await raw.post(
      Uri.parse('http://local/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: '{no es json',
    );
    expect(login.statusCode, 400);
    final http.Response unknown = await raw.get(
      Uri.parse('http://local/api/v1/desconocido'),
    );
    expect(unknown.statusCode, 404);
  });
}
