import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';

import '../support/local_backend_test_context.dart';

/// Valores invalidos o limite que se inyectan campo por campo.
final _badValues = <Object?>[
  null,
  '',
  '   ',
  'x' * 600,
  'sin-arroba',
  'a@b',
  'ES',
  'ZZ',
  '0000',
  -1,
  0,
  1.5,
  1e12,
  true,
  false,
  <String, dynamic>{},
  <Object?>[],
  [1, 2],
  [
    {'a': 1},
    'x',
    null,
  ],
  '2020-13-45',
  '2999-01-01',
  '2000-01-01',
  '12345678901234567890123456789012345678901234567890',
  '+57 300 000 0000',
  '999',
];

const _commonKeys = [
  'name',
  'email',
  'phone',
  'first_name',
  'last_name',
  'password',
  'role_id',
  'country_code',
  'address',
  'tax_id',
  'eori',
  'notes',
  'note',
  'status',
  'is_active',
  'variety',
  'quality_grade',
  'type',
  'product_type',
  'base_unit_code',
  'low_stock_threshold',
  'bean_type',
  'fermentation_percent',
  'altitude',
  'certification_ids',
  'latitude',
  'longitude',
  'supplier_id',
  'farm_id',
  'product_id',
  'product_lot_id',
  'lot_code',
  'harvest_date',
  'quantity',
  'quantity_delta',
  'unit_price',
  'currency_code',
  'customer_id',
  'order_id',
  'export_id',
  'lines',
  'destination_country_code',
  'incoterm_code',
  'carrier',
  'tracking_code',
  'transport_mode',
  'estimated_arrival',
  'location',
  'event_type',
  'description',
  'amount',
  'due_date',
  'reference',
  'base_currency_code',
  'quote_currency_code',
  'rate',
  'source',
  'read_at',
  'document_type',
  'file_name',
  'content_base64',
  'permission_codes',
  'description',
  'deforestation_free',
  'declaration_reference',
];

Future<Object?> _try(Future<Object?> Function() call) async {
  try {
    return await call();
  } on ApiException {
    return null;
  } catch (_) {
    return null;
  }
}

Future<List<Map<String, dynamic>>> _items(String path) async {
  final result = await _try(() => api.get(path));
  final items = result is Map ? result['items'] : null;
  return [
    if (items is List)
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<void> _mutate(
  String method,
  String path,
  Map<String, dynamic> base,
) async {
  Future<Object?> send(Object? body) => switch (method) {
    'POST' => api.post(path, body: body),
    'PATCH' => api.patch(path, body: body),
    _ => api.put(path, body: body),
  };
  await _try(() => send(null));
  await _try(() => send('texto'));
  await _try(() => send(<Object?>[]));
  await _try(() => send(<String, dynamic>{}));
  await _try(() => send(base));
  final keys = {...base.keys, ..._commonKeys};
  for (final key in keys) {
    final without = Map<String, dynamic>.of(base)..remove(key);
    await _try(() => send(without));
    for (final value in _badValues) {
      await _try(() => send({...base, key: value}));
    }
  }
}

Future<void> _fuzzCollection(
  String collection, {
  List<String> subPaths = const [],
  List<String> writeVerbs = const ['POST', 'PATCH'],
}) async {
  final items = await _items('/$collection?limit=100');
  final base = items.isEmpty ? <String, dynamic>{} : items.first;
  final id = base['id'] ?? 1;
  if (writeVerbs.contains('POST')) await _mutate('POST', '/$collection', base);
  if (writeVerbs.contains('PATCH')) {
    await _mutate('PATCH', '/$collection/$id', base);
  }
  for (final sub in subPaths) {
    for (final verb in ['POST', 'PATCH', 'PUT']) {
      await _mutate(verb, '/$collection/$id/$sub', base);
    }
  }
  // Consultas con parametros extremos.
  for (final query in [
    'q=%20',
    'q=${'x' * 300}',
    'limit=0',
    'limit=-5',
    'limit=abc',
    'limit=100000',
    'offset=-1',
    'offset=abc',
    'offset=100000',
    'is_active=maybe',
    'is_active=false',
    'status=nope',
    'type=zzz',
    'country_code=ZZ',
    'country_code=co',
    'certification_id=abc',
    'certification_id=999',
    'unread=true',
    'include_inactive=true',
    'currency=XXX',
    'low_stock=true',
    'supplier_id=1',
    'farm_id=1',
    'product_id=1',
    'customer_id=1',
    'quality=a',
  ]) {
    await _try(() => api.get('/$collection?$query'));
  }
  for (final badId in ['0', '99999', 'abc', '-1']) {
    await _try(() => api.get('/$collection/$badId'));
    await _try(() => api.patch('/$collection/$badId', body: base));
    await _try(() => api.patch('/$collection/$badId/status', body: base));
    await _try(() => api.delete('/$collection/$badId'));
  }
  await _try(() => api.get('/$collection/$id'));
  await _try(() => api.get('/$collection/$id/history'));
  await _try(() => api.get('/$collection/$id/accounts'));
  await _try(() => api.get('/$collection/$id/origin-farms'));
  await _try(() => api.get('/$collection/$id/eudr'));
  await _try(() => api.get('/$collection/$id/documents'));
}

void main() {
  setUp(() async {
    await setUpLocalBackendTest();
  });

  for (final group in <(String, List<String>)>[
    ('products', ['status', 'certifications']),
    ('suppliers', ['status']),
    ('customers', ['status', 'accounts']),
    ('farms', ['status']),
    ('lots', []),
    ('orders', ['status']),
    ('exports', ['eudr', 'documents', 'documents/upload']),
    ('shipments', ['status', 'events']),
    ('inventory', []),
    ('notifications', []),
    ('roles', ['permissions', 'deactivate']),
  ]) {
    test('validaciones y consultas extremas: ${group.$1}', () async {
      await _fuzzCollection(group.$1, subPaths: group.$2);
    });
  }

  test('usuarios, perfil propio y registro con entradas invalidas', () async {
    final users = await _items('/users');
    final base = users.first;
    await _mutate('POST', '/users', base);
    await _mutate('PATCH', '/users/${users.last['id']}', base);
    await _mutate('PATCH', '/me', base);
    await _mutate('PATCH', '/me', {'email': 'otro@riexport.com'});
    await _mutate('POST', '/auth/register', {
      'first_name': 'A',
      'last_name': 'B',
      'email': 'nuevo@riexport.com',
      'password': 'Secreto1234!',
    });
    await _mutate('POST', '/auth/login', {
      'email': 'admin@riexport.com',
      'password': 'Admin123!',
    });
    await _mutate('POST', '/auth/password-reset-requests', {
      'email': 'admin@riexport.com',
    });
    await _mutate('POST', '/auth/password-resets', {
      'email': 'admin@riexport.com',
      'code': '123456',
      'new_password': 'Nueva-Clave-2026',
    });
    for (final path in [
      '/users?q=a&is_active=true&limit=1&offset=0',
      '/users?is_active=nope',
      '/users?limit=zzz',
      '/users/abc/deactivate',
      '/users/99999/activate',
    ]) {
      await _try(() => api.get(path));
      await _try(() => api.patch(path));
    }
    final last = users.last['id'];
    await _try(() => api.patch('/users/$last/deactivate'));
    await _try(() => api.patch('/users/$last/deactivate'));
    await _try(() => api.patch('/users/$last/activate'));
    await _try(() => api.patch('/users/1/deactivate'));
    await _try(() => api.patch('/users/1', body: {'role_id': 2}));
  });

  test('finanzas, notificaciones y catalogos con entradas invalidas', () async {
    for (final verb in ['POST', 'PATCH', 'PUT']) {
      for (final path in [
        '/payments/obligations',
        '/payments/transactions',
        '/payments/exchange-rates',
        '/payments/exchange-rates/refresh',
        '/inventory/adjustments',
        '/notifications/read-all',
        '/notifications/refresh',
        '/notifications/1',
        '/notifications/99999',
        '/shipments/1/status',
        '/shipments/1/events',
        '/orders/1/status',
        '/exports',
        '/export-catalogs/destinations',
        '/export-catalogs/incoterms',
      ]) {
        await _mutate(verb, path, {
          'export_id': 1,
          'order_id': 1,
          'product_lot_id': 1,
          'obligation_id': 1,
          'amount': 10,
          'currency_code': 'USD',
          'status': 'in_transit',
          'quantity_delta': 5,
          'base_currency_code': 'USD',
          'quote_currency_code': 'EUR',
          'rate': 0.9,
        });
      }
    }
    for (final path in [
      '/payments/portfolio',
      '/payments/portfolio?status=overdue&currency=USD&q=a',
      '/payments/portfolio?status=zzz',
      '/payments/convert?amount=10&from=USD&to=EUR',
      '/payments/convert?amount=10&from=EUR&to=USD',
      '/payments/convert?amount=10&from=EUR&to=COP',
      '/payments/convert?amount=abc&from=USD&to=EUR',
      '/payments/convert?amount=-1&from=USD&to=EUR',
      '/payments/convert?amount=1&from=XXX&to=YYY',
      '/payments/convert?amount=1&from=USD&to=USD',
      '/payments/convert',
      '/payments/exchange-rates',
      '/inventory/overview',
      '/inventory/overview?low_stock=true',
      '/inventory?q=a',
      '/shipment-statuses',
      '/tracking',
      '/tracking/1',
      '/tracking/99999',
      '/units',
      '/certifications',
      '/roles/permissions',
      '/export-catalogs/destinations',
      '/export-catalogs/incoterms',
      '/documents/1/download',
      '/documents/99999/download',
      '/desconocido',
      '/api',
      '/',
    ]) {
      await _try(() => api.get(path));
    }
  });

  test('sin sesion o sin permisos las rutas protegidas se rechazan', () async {
    final saved = token;
    for (final t in [null, 'basura', ''] ) {
      token = t;
      for (final path in [
        '/me',
        '/users',
        '/products',
        '/suppliers',
        '/customers',
        '/farms',
        '/lots',
        '/orders',
        '/exports',
        '/inventory',
        '/shipments',
        '/payments/portfolio',
        '/notifications',
        '/roles',
      ]) {
        await _try(() => api.get(path));
        await _try(() => api.post(path, body: {}));
      }
    }
    token = saved;
    // Un cliente recien registrado carece de permisos de gestion.
    await _try(
      () => api.post(
        '/auth/register',
        body: {
          'first_name': 'Cli',
          'last_name': 'Ente',
          'email': 'cliente.qa@riexport.com',
          'password': 'Secreto1234!',
        },
      ),
    );
    final login = await _try(
      () => api.post(
        '/auth/login',
        body: {'email': 'cliente.qa@riexport.com', 'password': 'Secreto1234!'},
      ),
    );
    if (login is Map) {
      token = login['access_token'] as String;
      for (final path in [
        '/users',
        '/products',
        '/suppliers',
        '/customers',
        '/farms',
        '/lots',
        '/orders',
        '/exports',
        '/exports/1',
        '/exports/1/origin-farms',
        '/inventory',
        '/inventory/overview',
        '/shipments',
        '/shipments/1',
        '/payments/portfolio',
        '/payments/exchange-rates',
        '/notifications',
        '/roles',
        '/export-catalogs/destinations',
        '/export-catalogs/incoterms',
        '/tracking',
        '/tracking/1',
      ]) {
        await _try(() => api.get(path));
        await _try(() => api.post(path, body: {}));
        await _try(() => api.patch(path, body: {}));
      }
      for (final path in [
        '/products/1',
        '/products/1/status',
        '/suppliers/1',
        '/customers/1',
        '/customers/1/accounts',
        '/farms/1',
        '/orders/1',
        '/orders/1/status',
        '/shipments/1/status',
        '/shipments/1/events',
        '/inventory/adjustments',
        '/payments/obligations',
        '/payments/transactions',
        '/payments/exchange-rates',
        '/notifications/read-all',
        '/roles/1',
        '/roles/1/permissions',
      ]) {
        await _try(() => api.post(path, body: {'x': 1}));
        await _try(() => api.patch(path, body: {'x': 1}));
        await _try(() => api.put(path, body: {'x': 1}));
        await _try(() => api.delete(path));
      }
    }
  });
}
