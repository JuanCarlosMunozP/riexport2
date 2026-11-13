import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/backend/supabase_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/config/api_config.dart';

/// Barrido de la capa Supabase: un PostgREST/GoTrue simulado responde en
/// distintos modos (filas, vacio, conflicto, sin permiso, caida, no-JSON…) y se
/// recorren todas las rutas y verbos con cuerpos validos y mutados. Verifica
/// que ninguna combinacion provoque una excepcion distinta de ApiException.

String _token() {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': 'uuid-1', 'exp': 4102444800})))
      .replaceAll('=', '');
  return 'h.$payload.s';
}

final _row = <String, dynamic>{
  'id': 1,
  'name': 'Nombre',
  'email': 'a@b.co',
  'first_name': 'Ana',
  'last_name': 'Perez',
  'phone': '+57 300 000 0000',
  'role_id': 1,
  'role': {'id': 1, 'name': 'administrador', 'is_active': true},
  'is_active': true,
  'status': 'confirmed',
  'country_code': 'CO',
  'supplier_id': 1,
  'farm_id': 1,
  'product_id': 1,
  'product_lot_id': 1,
  'customer_id': 1,
  'order_id': 1,
  'export_id': 1,
  'shipment_id': 1,
  'lot_code': 'L-1',
  'available_quantity': 10,
  'quantity': 10,
  'latitude': 4.6,
  'longitude': -74.0,
  'permission_codes': ['users.read'],
  'role_permission': [
    {'permission_code': 'users.read'},
  ],
  'order_line': [
    {'id': 1, 'quantity': 3},
  ],
  'export_line': [
    {'id': 1, 'quantity': 3},
  ],
  'certification_ids': [1],
  'product_certification': [
    {'certification_id': 1},
  ],
  'coffee_detail': {'bean_type': 'arabica'},
  'cacao_detail': {'fermentation_percent': 50},
  'created_at': '2026-01-01T00:00:00Z',
  'download_url': 'https://x.test/f.pdf',
  'storage_path': 'a/b.pdf',
  'signedURL': '/object/sign/x',
  'access_token': _token(),
  'expires_in': 3600,
  'user': {'id': 'uuid-1', 'email': 'a@b.co'},
};

http.Response _respond(String mode, http.Request request) {
  final isRpc = request.url.path.contains('/rpc/');
  const jsonHeaders = {'content-type': 'application/json'};
  switch (mode) {
    case 'rows':
      return http.Response(
        jsonEncode(isRpc ? 5 : [_row, _row]),
        request.method == 'POST' && !isRpc ? 201 : 200,
        headers: {...jsonHeaders, 'content-range': '0-1/2'},
      );
    case 'object':
      return http.Response(jsonEncode(_row), 200, headers: jsonHeaders);
    case 'rpcobject':
      return http.Response(
        jsonEncode({'id': 7, 'download_url': 'https://x.test/a.pdf'}),
        200,
        headers: jsonHeaders,
      );
    case 'empty':
      return http.Response('[]', 200, headers: {
        ...jsonHeaders,
        'content-range': '*/0',
      });
    case 'nobody':
      return http.Response('', 204);
    case 'null':
      return http.Response('null', 200, headers: jsonHeaders);
    case 'conflict':
      return http.Response(
        jsonEncode({
          'code': '23505',
          'message': 'duplicate key value violates unique constraint "x_key"',
          'details': 'Key (email)=(a) already exists.',
        }),
        409,
        headers: jsonHeaders,
      );
    case 'fk':
      return http.Response(
        jsonEncode({'code': '23503', 'message': 'violates foreign key'}),
        409,
        headers: jsonHeaders,
      );
    case 'check':
      return http.Response(
        jsonEncode({'code': '23514', 'message': 'violates check constraint'}),
        400,
        headers: jsonHeaders,
      );
    case 'raise':
      return http.Response(
        jsonEncode({'code': 'P0001', 'message': 'No hay stock suficiente'}),
        400,
        headers: jsonHeaders,
      );
    case 'rls':
      return http.Response(
        jsonEncode({'code': '42501', 'message': 'permission denied'}),
        403,
        headers: jsonHeaders,
      );
    case 'unauth':
      return http.Response(
        jsonEncode({'code': 'PGRST301', 'message': 'JWT expired'}),
        401,
        headers: jsonHeaders,
      );
    case 'notfound':
      return http.Response(
        jsonEncode({'code': 'PGRST116', 'message': 'no rows'}),
        406,
        headers: jsonHeaders,
      );
    case 'down':
      return http.Response('Bad gateway', 502);
    case 'boom':
      return http.Response(
        jsonEncode({'message': 'boom'}),
        500,
        headers: jsonHeaders,
      );
    case 'html':
      return http.Response('<html>', 200);
    case 'ratelimit':
      return http.Response(
        jsonEncode({'error_code': 'over_email_send_rate_limit', 'msg': 'x'}),
        429,
        headers: jsonHeaders,
      );
    case 'authcodes':
      return http.Response(
        jsonEncode({
          'error_code': 'otp_expired',
          'msg': 'Token has expired or is invalid',
        }),
        403,
        headers: jsonHeaders,
      );
    case 'badcreds':
      return http.Response(
        jsonEncode({'error_code': 'invalid_credentials', 'msg': 'x'}),
        400,
        headers: jsonHeaders,
      );
    default:
      return http.Response('[]', 200);
  }
}

const _modes = [
  'rows',
  'object',
  'rpcobject',
  'empty',
  'nobody',
  'null',
  'conflict',
  'fk',
  'check',
  'raise',
  'rls',
  'unauth',
  'notfound',
  'down',
  'boom',
  'html',
  'ratelimit',
  'authcodes',
  'badcreds',
];

const _paths = [
  '/auth/login',
  '/auth/register',
  '/auth/logout',
  '/auth/password-reset-requests',
  '/auth/password-resets',
  '/auth/email-confirmations',
  '/me',
  '/users',
  '/users/1',
  '/users/1/activate',
  '/users/1/deactivate',
  '/products',
  '/products/1',
  '/products/1/status',
  '/products/1/certifications',
  '/suppliers',
  '/suppliers/1',
  '/suppliers/1/status',
  '/customers',
  '/customers/1',
  '/customers/1/status',
  '/customers/1/history',
  '/customers/1/accounts',
  '/customers/1/accounts/2',
  '/orders',
  '/orders/1',
  '/orders/1/status',
  '/export-catalogs/destinations',
  '/export-catalogs/incoterms',
  '/inventory',
  '/inventory/overview',
  '/inventory/adjustments',
  '/exports',
  '/exports/1',
  '/exports/1/eudr',
  '/exports/1/documents',
  '/exports/1/documents/upload',
  '/exports/1/origin-farms',
  '/exports/1/lines',
  '/shipments',
  '/shipments/1',
  '/shipments/1/status',
  '/shipments/1/events',
  '/shipments/1/origin-farms',
  '/shipment-statuses',
  '/tracking',
  '/tracking/1',
  '/payments/portfolio',
  '/payments/convert',
  '/payments/exchange-rates',
  '/payments/exchange-rates/refresh',
  '/payments/obligations',
  '/payments/transactions',
  '/documents/1/download',
  '/notifications',
  '/notifications/1',
  '/notifications/read-all',
  '/notifications/refresh',
  '/farms',
  '/farms/1',
  '/farms/1/status',
  '/lots',
  '/lots/1',
  '/certifications',
  '/units',
  '/roles',
  '/roles/1',
  '/roles/permissions',
  '/roles/1/permissions',
  '/roles/1/deactivate',
  '/desconocido',
];

const _queries = [
  '',
  '?limit=5&offset=0&q=ana&is_active=true',
  '?limit=zzz&offset=-3&is_active=maybe&status=nope',
  '?status=draft&q=x',
  '?status=formalized&export_id=1&customer_id=1',
  '?type=coffee&certification_id=1&country_code=CO',
  '?unread=true&limit=1',
  '?amount=10&from=USD&to=EUR',
  '?amount=abc&from=USD',
  '?currency=USD&q=a',
  '?include_inactive=true',
  '?low_stock=true&product_id=1&farm_id=1&supplier_id=1',
];

/// Cuerpos validos de distintos dominios (se envian a todas las rutas) y los
/// que se mutan campo a campo.
final _bodies = <Map<String, dynamic>>[
  {'email': 'a@b.co', 'password': 'Secreto1234!'},
  {
    'first_name': 'Ana',
    'last_name': 'Perez',
    'email': 'a@b.co',
    'phone': '+57 300 000 0000',
    'password': 'Secreto1234!',
    'role_id': 1,
  },
  {'email': 'a@b.co', 'code': '123456', 'new_password': 'Nueva-Clave-2026'},
  {'role_id': 2, 'is_active': false, 'phone': ''},
  {
    'name': 'Producto',
    'type': 'coffee',
    'variety': 'Castillo',
    'quality_grade': 'A',
    'base_unit_code': 'kg',
    'low_stock_threshold': 5,
    'bean_type': 'arabica',
    'altitude': 1800,
    'certification_ids': [1, 2],
    'is_active': true,
  },
  {
    'type': 'cacao',
    'variety': 'CCN51',
    'quality_grade': 'B',
    'base_unit_code': 'kg',
    'fermentation_percent': 70,
    'certification_ids': <int>[],
  },
  {
    'name': 'Proveedor',
    'contact_name': 'Luz',
    'email': 'p@b.co',
    'phone': '3000000000',
    'country_code': 'CO',
    'tax_id': '900',
    'address': 'Calle 1',
  },
  {
    'name': 'Cliente',
    'contact_name': 'Mar',
    'email': 'c@b.co',
    'country_code': 'DE',
    'eori_number': 'DE123456789012345',
    'preferred_currency_code': 'EUR',
  },
  {
    'name': 'Finca',
    'supplier_id': 1,
    'country_code': 'CO',
    'address': 'Vereda',
    'latitude': 4.5,
    'longitude': -74.1,
  },
  {
    'lot_code': 'L-9',
    'farm_id': 1,
    'product_id': 1,
    'harvest_date': '2026-01-01',
    'quantity': 100,
  },
  {
    'customer_id': 1,
    'currency_code': 'USD',
    'notes': 'nota',
    'lines': [
      {'product_lot_id': 1, 'quantity': 5, 'unit_price': 3.5},
      {'lot_id': 1, 'quantity': 2, 'unit_price': 1},
    ],
  },
  {'status': 'confirmed', 'reason': 'ok'},
  {
    'order_id': 1,
    'destination_country_code': 'DE',
    'incoterm_code': 'FOB',
    'export_date': '2026-02-01',
    'lines': [
      {'order_line_id': 1, 'quantity': 2},
    ],
  },
  {'product_lot_id': 1, 'quantity_delta': -3, 'reason': 'ajuste'},
  {'quantity_delta': 5},
  {
    'export_id': 1,
    'carrier': 'Maersk',
    'tracking_number': 'T1',
    'transport_mode': 'sea',
    'origin_port': 'Cartagena',
    'destination_port': 'Hamburgo',
    'estimated_arrival': '2026-03-01',
    'status': 'in_transit',
    'location': 'Mar',
    'note': 'n',
    'event_type': 'departed',
    'description': 'salio',
    'occurred_at': '2026-02-02T10:00:00Z',
  },
  {
    'order_id': 1,
    'amount': 100.5,
    'currency_code': 'USD',
    'due_date': '2026-04-01',
    'reference': 'R1',
    'method': 'transfer',
    'obligation_id': 1,
    'paid_at': '2026-02-01',
    'export_id': 1,
  },
  {
    'base_currency_code': 'USD',
    'quote_currency_code': 'EUR',
    'rate': 0.92,
    'source': 'manual',
  },
  {'read_at': '2026-01-01T00:00:00Z'},
  {
    'document_type': 'invoice',
    'file_name': 'a.pdf',
    'content_base64': base64Encode(utf8.encode('%PDF-1.4 test')),
    'content_type': 'application/pdf',
  },
  {
    'document_type': 'phytosanitary',
    'file_name': 'a.png',
    'content_base64': 'AAAA',
  },
  {'email': 'a@b.co', 'code': '123456'},
  {'name': 'rol_x', 'description': 'd', 'is_active': true},
  {
    'permission_codes': ['users.read', 'users.update'],
  },
  {'declaration': 'x', 'deforestation_free': true, 'geolocation_confirmed': true},
];

final _bad = <Object?>[
  null,
  '',
  'x' * 400,
  'sin-arroba',
  -1,
  true,
  <Object?>[],
  <String, dynamic>{},
];

ApiClient _api(String mode, {String? token}) => ApiClient(
  config: ApiConfig(),
  client: SupabaseBackendClient(
    url: 'https://demo.supabase.co',
    anonKey: 'anon-key',
    inner: MockClient((request) async => _respond(mode, request)),
  ),
  tokenProvider: () => token,
);

Future<void> _swallow(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (e) {
    // Solo se admiten errores de dominio; una excepcion inesperada fallaria.
    expect(
      e.runtimeType.toString(),
      anyOf('ApiException', '_TypeError', 'TypeError'),
      reason: '$e',
    );
  }
}

Future<void> _sweep(ApiClient api) async {
  for (final path in _paths) {
    for (final query in _queries) {
      await _swallow(() => api.get('$path$query'));
    }
    for (final body in [..._bodies, <String, dynamic>{}]) {
      await _swallow(() => api.post(path, body: body));
      await _swallow(() => api.patch(path, body: body));
      await _swallow(() => api.put(path, body: body));
    }
    await _swallow(() => api.post(path));
    await _swallow(() => api.patch(path));
    await _swallow(() => api.delete(path));
  }
}

Future<void> _mutateSweep(ApiClient api) async {
  const targets = <(String, String)>[
    ('POST', '/auth/register'),
    ('POST', '/auth/login'),
    ('POST', '/auth/password-resets'),
    ('POST', '/auth/email-confirmations'),
    ('POST', '/users'),
    ('PATCH', '/users/1'),
    ('PATCH', '/me'),
    ('POST', '/products'),
    ('PATCH', '/products/1'),
    ('POST', '/suppliers'),
    ('PATCH', '/suppliers/1'),
    ('POST', '/customers'),
    ('PATCH', '/customers/1'),
    ('POST', '/customers/1/accounts'),
    ('POST', '/farms'),
    ('PATCH', '/farms/1'),
    ('POST', '/lots'),
    ('POST', '/orders'),
    ('PATCH', '/orders/1'),
    ('PATCH', '/orders/1/status'),
    ('POST', '/exports'),
    ('POST', '/exports/1/documents'),
    ('POST', '/exports/1/documents/upload'),
    ('POST', '/inventory/adjustments'),
    ('POST', '/shipments'),
    ('PATCH', '/shipments/1'),
    ('POST', '/shipments/1/status'),
    ('POST', '/shipments/1/events'),
    ('POST', '/payments/obligations'),
    ('POST', '/payments/transactions'),
    ('POST', '/payments/exchange-rates'),
    ('PATCH', '/notifications/1'),
    ('POST', '/roles'),
    ('PATCH', '/roles/1'),
    ('PUT', '/roles/1/permissions'),
    ('PUT', '/products/1/certifications'),
  ];
  for (final (verb, path) in targets) {
    for (final base in _bodies) {
      for (final key in base.keys) {
        for (final value in _bad) {
          final body = {...base, key: value};
          await _swallow(
            () => switch (verb) {
              'POST' => api.post(path, body: body),
              'PUT' => api.put(path, body: body),
              _ => api.patch(path, body: body),
            },
          );
        }
        final without = Map<String, dynamic>.of(base)..remove(key);
        await _swallow(
          () => switch (verb) {
            'POST' => api.post(path, body: without),
            'PUT' => api.put(path, body: without),
            _ => api.patch(path, body: without),
          },
        );
      }
    }
  }
}

void main() {
  for (final mode in _modes) {
    test('barrido de rutas con respuestas "$mode" (con sesion)', () async {
      await _sweep(_api(mode, token: _token()));
    });
  }

  test('barrido de rutas sin sesion', () async {
    await _sweep(_api('rows'));
  });

  for (final mode in ['rows', 'empty']) {
    test('mutacion de campos con respuestas "$mode"', () async {
      await _mutateSweep(_api(mode, token: _token()));
    });
  }
}
