import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/app/app.dart';
import 'package:riexport_app/backend/local_backend_client.dart';
import 'package:riexport_app/backend/supabase_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';
import 'package:riexport_app/core/validation/eori.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';
import 'package:riexport_app/features/customers/presentation/customer_form_screen.dart';
import 'package:riexport_app/features/customers/presentation/customer_list_screen.dart';

class _MemoryTokenStore implements SessionTokenStore {
  String? value;

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async => value = token;

  @override
  Future<void> deleteToken() async => value = null;
}

TypeMatcher<ApiException> _status(int code, [String? message]) {
  final matcher = isA<ApiException>().having(
    (e) => e.statusCode,
    'status',
    code,
  );
  return message == null
      ? matcher
      : matcher.having((e) => e.message, 'message', contains(message));
}

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?h},
    );

Map<String, Object?> _page(List<Map<String, Object?>> items) => {
  'items': items,
  'pagination': {'total': items.length, 'limit': 20, 'offset': 0},
};

Map<String, Object?> _customer({
  int id = 1,
  String name = 'Importadora Iberica SL',
  bool active = true,
}) => {
  'id': id,
  'name': name,
  'contact_name': 'Marta Gil',
  'email': 'marta@iberica.es',
  'country_code': 'ES',
  'eori_number': 'ES12345678Z',
  'preferred_currency_code': 'EUR',
  'is_active': active,
};

void main() {
  group('EORI (helper del cliente)', () {
    test('normaliza como la base de datos', () {
      expect(normalizeEori(' es-1234 5678.z '), 'ES12345678Z');
      expect(normalizeEori('   '), isNull);
      expect(normalizeEori(null), isNull);
    });

    test('obligatorio en los 27 paises de la UE y opcional fuera', () {
      expect(euCountryCodes, hasLength(27));
      for (final code in euCountryCodes) {
        expect(
          validateEori('', code),
          'El EORI es obligatorio para clientes de la Unión Europea.',
          reason: code,
        );
      }
      expect(validateEori('', 'US'), isNull);
      expect(validateEori(null, 'CO'), isNull);
      expect(
        validateEori('', 'GB'),
        isNull,
        reason: 'el Reino Unido ya no es de la UE',
      );
    });

    test('formato: 2 letras de pais y de 1 a 15 alfanumericos', () {
      expect(
        validateEori('DE123456789012345', 'DE'),
        isNull,
        reason: '15 tras el pais',
      );
      expect(
        validateEori('DE1234567890123456', 'DE'),
        contains('formato válido'),
        reason: '16 tras el pais',
      );
      expect(validateEori('DE', 'DE'), contains('formato válido'));
      expect(validateEori('DE12345_678', 'DE'), contains('formato válido'));
      expect(validateEori('1E12345678', 'DE'), contains('formato válido'));
      expect(
        validateEori('de-123 456', 'DE'),
        isNull,
        reason: 'se normaliza antes de validar',
      );
    });

    test(
      'el prefijo debe ser el pais del cliente (Grecia EL, Irlanda del Norte XI)',
      () {
        expect(
          validateEori('FR12345678', 'DE'),
          'El EORI debe empezar por DE (el país del cliente).',
        );
        expect(
          validateEori('GR123456789', 'GR'),
          'El EORI debe empezar por EL (el país del cliente).',
        );
        expect(validateEori('EL123456789', 'GR'), isNull);
        expect(eoriPrefixFor('GR'), 'EL');
        expect(validateEori('GB123456789000', 'GB'), isNull);
        expect(validateEori('XI123456789000', 'GB'), isNull);
        expect(
          validateEori('XI123456789000', 'US'),
          'El EORI debe empezar por US (el país del cliente).',
        );
        expect(
          validateEori('ES12345678Z', 'US'),
          'El EORI debe empezar por US (el país del cliente).',
        );
      },
    );
  });

  group('backend local', () {
    late ApiClient api;
    late String? token;

    setUp(() async {
      token = null;
      api = ApiClient(
        config: ApiConfig(),
        client: LocalBackendClient(),
        tokenProvider: () => token,
      );
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'admin@riexport.com', 'password': 'Admin123!'},
              )
              as Map<String, dynamic>;
      token = login['access_token'] as String;
    });

    Map<String, Object?> cliente([Map<String, Object?> extra = const {}]) => {
      'name': '  Importadora Iberica SL ',
      'contact_name': 'Marta Gil',
      'email': 'MARTA@Iberica.ES',
      'country_code': 'es',
      'eori_number': 'es-1234 5678z',
      'preferred_currency_code': 'eur',
      ...extra,
    };

    Future<void> bad(
      Map<String, Object?> body,
      String message, {
      int status = 422,
    }) => expectLater(
      api.post('/customers', body: body),
      throwsA(_status(status, message)),
    );

    test('registra un cliente y lo guarda limpio', () async {
      final created = await api.post('/customers', body: cliente()) as Map;
      expect(created['name'], 'Importadora Iberica SL');
      expect(created['email'], 'marta@iberica.es');
      expect(created['country_code'], 'ES');
      expect(created['eori_number'], 'ES12345678Z');
      expect(created['preferred_currency_code'], 'EUR');
      expect(created['is_active'], true);
      expect(
        ((await api.get('/customers/${created['id']}')) as Map)['name'],
        'Importadora Iberica SL',
      );
    });

    test('fuera de la UE el EORI es opcional', () async {
      final created =
          await api.post(
                '/customers',
                body: {
                  'name': 'Coffee Corp',
                  'country_code': 'US',
                  'preferred_currency_code': 'USD',
                },
              )
              as Map;
      expect(created['eori_number'], isNull);
    });

    test(
      'valida obligatorios y formatos con los mensajes de la base',
      () async {
        await bad({
          'country_code': 'US',
          'preferred_currency_code': 'USD',
        }, 'nombre del cliente es obligatorio');
        await bad({
          'name': 'A',
          'preferred_currency_code': 'USD',
        }, 'país es obligatorio');
        await bad({
          'name': 'A',
          'country_code': 'USA',
          'preferred_currency_code': 'USD',
        }, 'país');
        await bad({
          'name': 'A',
          'country_code': 'US',
        }, 'moneda preferida es obligatoria');
        await bad({
          'name': 'A',
          'country_code': 'US',
          'preferred_currency_code': 'US',
        }, 'código de 3 letras');
        await bad({
          'name': 'A',
          'country_code': 'US',
          'preferred_currency_code': 'USD',
          'email': 'x',
        }, 'correo no tiene un formato válido');
        await bad({
          'name': 'A',
          'country_code': 'US',
          'preferred_currency_code': 'USD',
          'is_active': false,
        }, 'Campo no permitido');
        await bad({
          'name': 5,
          'country_code': 'US',
          'preferred_currency_code': 'USD',
        }, 'debe ser texto');
        await bad({
          'name': 'x' * 181,
          'country_code': 'US',
          'preferred_currency_code': 'USD',
        }, 'máximo 180');
        expect(
          ((await api.get('/customers')) as Map)['items'],
          isEmpty,
          reason: 'nada se guarda a medias',
        );
      },
    );

    test('valida el EORI: obligatorio en la UE, prefijo y formato', () async {
      Map<String, Object?> eu(String eori, [String country = 'DE']) => {
        'name': 'A',
        'country_code': country,
        'eori_number': eori,
        'preferred_currency_code': 'EUR',
      };
      await bad({
        'name': 'A',
        'country_code': 'DE',
        'preferred_currency_code': 'EUR',
      }, 'obligatorio para clientes de la Unión Europea');
      await bad(eu('  '), 'obligatorio para clientes de la Unión Europea');
      await bad(eu('FR12345678'), 'debe empezar por DE');
      await bad(eu('GR123456789', 'GR'), 'debe empezar por EL');
      await bad(eu('DE'), 'formato válido');
      await bad(eu('DE1234567890123456'), 'formato válido');
      await bad(eu('DE12345_678'), 'formato válido');
      await api.post('/customers', body: eu('DE123456789012345'));
      await api.post('/customers', body: eu('EL123456789', 'GR'));
      await api.post(
        '/customers',
        body: {
          'name': 'NI',
          'country_code': 'GB',
          'eori_number': 'XI123456789000',
          'preferred_currency_code': 'GBP',
        },
      );
    });

    test('el EORI es unico tras normalizar, tambien al editar', () async {
      await api.post('/customers', body: cliente());
      await bad(
        cliente({'name': 'Otro', 'eori_number': ' ES 12345678-z'}),
        'Ya existe un cliente con ese EORI',
        status: 409,
      );
      final other =
          await api.post(
                '/customers',
                body: cliente({'name': 'Otro', 'eori_number': 'ES99999999Z'}),
              )
              as Map;
      await expectLater(
        api.patch(
          '/customers/${other['id']}',
          body: {'eori_number': 'ES12345678Z'},
        ),
        throwsA(_status(409)),
      );
      await api.patch(
        '/customers/${other['id']}',
        body: {'eori_number': 'ES99999999Z', 'contact_name': 'Luis'},
      );
    });

    test(
      'editar: solo lo enviado; pais y EORI deben seguir siendo coherentes',
      () async {
        final us =
            await api.post(
                  '/customers',
                  body: {
                    'name': 'Coffee Corp',
                    'country_code': 'US',
                    'preferred_currency_code': 'USD',
                  },
                )
                as Map;
        final id = us['id'];
        final updated =
            await api.patch(
                  '/customers/$id',
                  body: {
                    'contact_name': 'John',
                    'preferred_currency_code': 'cad',
                  },
                )
                as Map;
        expect(updated['contact_name'], 'John');
        expect(updated['preferred_currency_code'], 'CAD');
        expect(updated['name'], 'Coffee Corp');
        await api.patch('/customers/$id', body: {'eori_number': 'US123456'});
        expect(
          ((await api.patch('/customers/$id', body: {'eori_number': null}))
              as Map)['eori_number'],
          isNull,
        );
        await expectLater(
          api.patch('/customers/$id', body: {'country_code': 'FR'}),
          throwsA(
            _status(422, 'obligatorio para clientes de la Unión Europea'),
          ),
        );
        await expectLater(
          api.patch(
            '/customers/$id',
            body: {'country_code': 'FR', 'eori_number': 'DE12345'},
          ),
          throwsA(_status(422, 'debe empezar por FR')),
        );
        final moved =
            await api.patch(
                  '/customers/$id',
                  body: {'country_code': 'FR', 'eori_number': 'FR12345678901'},
                )
                as Map;
        expect(moved['country_code'], 'FR');
        await expectLater(
          api.patch('/customers/$id', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/customers/$id', body: {'name': ''}),
          throwsA(_status(422, 'obligatorio')),
        );
        await expectLater(
          api.patch('/customers/$id', body: {'is_active': false}),
          throwsA(_status(422, 'Campo no permitido')),
        );
        await expectLater(
          api.patch('/customers/999', body: {'name': 'X'}),
          throwsA(_status(404)),
        );
      },
    );

    test(
      'inactivar conserva los datos, se puede reactivar y no hay borrado',
      () async {
        final created = await api.post('/customers', body: cliente()) as Map;
        final id = created['id'];
        expect(
          ((await api.patch(
                '/customers/$id/status',
                body: {'is_active': false},
              ))
              as Map)['is_active'],
          false,
        );
        expect(
          ((await api.get('/customers', queryParameters: {'is_active': 'true'}))
              as Map)['items'],
          isEmpty,
        );
        expect(
          ((await api.get('/customers/$id')) as Map)['contact_name'],
          'Marta Gil',
        );
        expect(
          ((await api.patch('/customers/$id/status', body: {'is_active': true}))
              as Map)['is_active'],
          true,
        );
        await expectLater(
          api.patch('/customers/$id/status', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/customers/999/status', body: {'is_active': false}),
          throwsA(_status(404)),
        );
        await expectLater(api.delete('/customers/$id'), throwsA(_status(404)));
      },
    );

    test(
      'busca por nombre, EORI (aunque se escriba con espacios) y pais',
      () async {
        await api.post('/customers', body: cliente());
        await api.post(
          '/customers',
          body: {
            'name': 'Coffee Corp',
            'country_code': 'US',
            'preferred_currency_code': 'USD',
          },
        );
        List names(Object? page) => [
          for (final i in (page as Map)['items'] as List) i['name'],
        ];
        expect(
          names(await api.get('/customers', queryParameters: {'q': 'coffee'})),
          ['Coffee Corp'],
        );
        expect(
          names(
            await api.get('/customers', queryParameters: {'q': 'es 1234-5678'}),
          ),
          ['Importadora Iberica SL'],
        );
        expect(
          names(
            await api.get(
              '/customers',
              queryParameters: {'country_code': 'us'},
            ),
          ),
          ['Coffee Corp'],
        );
        expect(names(await api.get('/customers')), [
          'Coffee Corp',
          'Importadora Iberica SL',
        ]);
      },
    );

    test('exige sesion y permisos customers.*', () async {
      final saved = token;
      token = null;
      await expectLater(api.get('/customers'), throwsA(_status(401)));
      await api.post(
        '/auth/register',
        body: {
          'first_name': 'Luz',
          'last_name': 'Mora',
          'email': 'luz@correo.com',
          'password': 'secreto1',
        },
      );
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'luz@correo.com', 'password': 'secreto1'},
              )
              as Map;
      token = login['access_token'] as String;
      await expectLater(api.get('/customers'), throwsA(_status(403)));
      await expectLater(
        api.post('/customers', body: cliente()),
        throwsA(_status(403)),
      );
      await expectLater(
        api.patch('/customers/1', body: {'name': 'X'}),
        throwsA(_status(403)),
      );
      await expectLater(
        api.patch('/customers/1/status', body: {'is_active': false}),
        throwsA(_status(403)),
      );
      token = saved;
    });
  });

  group('cliente de Supabase', () {
    ApiClient client(Future<http.Response> Function(http.Request) handler) =>
        ApiClient(
          config: ApiConfig(),
          client: SupabaseBackendClient(
            url: 'https://demo.supabase.co',
            anonKey: 'anon-key',
            inner: MockClient(handler),
          ),
          tokenProvider: () => 'jwt',
        );

    test(
      'el listado lee la tabla con filtros y busqueda por nombre o EORI normalizado',
      () async {
        late Uri url;
        final api = client((request) async {
          url = request.url;
          expect(request.headers['Prefer'], 'count=exact');
          return _json([_customer()], 200, {'content-range': '0-0/9'});
        });
        final page =
            await api.get(
                  '/customers',
                  queryParameters: {
                    'limit': '20',
                    'offset': '40',
                    'is_active': 'true',
                    'country_code': 'es',
                    'q': 'es 12-34,(x)*',
                  },
                )
                as Map;
        expect((page['pagination'] as Map)['total'], 9);
        expect(url.path, '/rest/v1/customer');
        expect(url.queryParameters['is_active'], 'eq.true');
        expect(url.queryParameters['country_code'], 'eq.ES');
        expect(url.queryParameters['offset'], '40');
        final or = url.queryParameters['or']!;
        expect(or, contains('name.ilike.'));
        expect(or, contains('eori_number.ilike.*ES1234X*'));
        expect(or, isNot(contains('(x)')));
        expect(url.queryParameters['select'], contains('eori_number'));
      },
    );

    test('registrar usa la funcion atomica y devuelve la fila', () async {
      final calls = <String>[];
      final api = client((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/rpc/create_customer') {
          expect(jsonDecode(request.body), {
            'p': {
              'name': 'A',
              'country_code': 'ES',
              'eori_number': 'ES12345678Z',
              'preferred_currency_code': 'EUR',
            },
          });
          return _json(5);
        }
        expect(request.url.queryParameters['id'], 'eq.5');
        return _json([_customer(id: 5)]);
      });
      final created =
          await api.post(
                '/customers',
                body: {
                  'name': 'A',
                  'country_code': 'ES',
                  'eori_number': 'ES12345678Z',
                  'preferred_currency_code': 'EUR',
                },
              )
              as Map;
      expect(created['id'], 5);
      expect(calls, [
        'POST /rest/v1/rpc/create_customer',
        'GET /rest/v1/customer',
      ]);
    });

    test(
      'editar e inactivar llaman a sus funciones y validan la solicitud',
      () async {
        final bodies = <String, Object?>{};
        final api = client((request) async {
          if (request.method == 'POST') {
            bodies[request.url.path] = jsonDecode(request.body);
            return http.Response('', 204);
          }
          return _json([_customer()]);
        });
        await api.patch('/customers/1', body: {'eori_number': null});
        await api.patch('/customers/1/status', body: {'is_active': false});
        expect(bodies['/rest/v1/rpc/update_customer'], {
          'p_id': 1,
          'p': {'eori_number': null},
        });
        expect(bodies['/rest/v1/rpc/set_customer_active'], {
          'p_id': 1,
          'p_active': false,
        });
        await expectLater(
          api.patch('/customers/1', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/customers/1/status', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          client((_) async => _json([])).get('/customers/9'),
          throwsA(_status(404)),
        );
      },
    );

    test('traduce los errores de la base, incluidos los del EORI', () async {
      Future<void> mapped(
        Map<String, Object?> error,
        int status,
        String message,
      ) => expectLater(
        client(
          (_) async => _json(error, 400),
        ).post('/customers', body: {'name': 'A'}),
        throwsA(_status(status, message)),
      );
      await mapped(
        {
          'code': '22023',
          'message':
              'El EORI es obligatorio para clientes de la Unión Europea.',
        },
        422,
        'obligatorio para clientes',
      );
      await mapped(
        {
          'code': '22023',
          'message': 'El EORI debe empezar por DE (el país del cliente).',
        },
        422,
        'debe empezar por DE',
      );
      await mapped(
        {'code': 'P0001', 'message': 'Ya existe un cliente con ese EORI.'},
        409,
        'Ya existe',
      );
      await mapped(
        {
          'code': '23514',
          'message': 'violates check constraint "customer_eori_format"',
        },
        422,
        '',
      );
      await mapped(
        {'code': '42501', 'message': 'No tienes permiso para esta operación.'},
        403,
        'permiso',
      );
    });
  });

  group('pantallas', () {
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget list({
      required LoadCustomers loadCustomers,
      Set<String> permissions = const {
        'customers.read',
        'customers.create',
        'customers.update',
      },
      Future<void> Function(int, bool)? setActive,
    }) => MaterialApp(
      home: CustomerListScreen(
        loadCustomers: loadCustomers,
        loadPermissions: () async => permissions,
        setActive: setActive,
      ),
    );

    testWidgets('lista clientes con pais y EORI; sin acciones si solo lee', (
      tester,
    ) async {
      await tester.pumpWidget(
        list(
          permissions: const {'customers.read'},
          loadCustomers:
              ({
                required limit,
                required offset,
                query,
                countryCode,
                isActive,
              }) async => _page([
                _customer(),
                _customer(id: 2, name: 'Coffee Corp', active: false),
              ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Importadora Iberica SL'), findsOneWidget);
      expect(find.textContaining('EORI ES12345678Z'), findsNWidgets(2));
      expect(find.text('Inactivo'), findsOneWidget);
      expect(find.byTooltip('Registrar cliente'), findsNothing);
      // Quien solo lee ve el menú, pero sin editar ni inactivar.
      await tester.tap(find.byTooltip('Acciones del cliente').first);
      await tester.pumpAndSettle();
      expect(find.text('Cuentas de acceso'), findsOneWidget);
      expect(find.text('Historial comercial'), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Inactivar'), findsNothing);
    });

    testWidgets('vacio, filtro por defecto en activos y error con reintento', (
      tester,
    ) async {
      bool? seen;
      var fail = true;
      await tester.pumpWidget(
        list(
          loadCustomers:
              ({
                required limit,
                required offset,
                query,
                countryCode,
                isActive,
              }) async {
                seen = isActive;
                if (fail) {
                  throw const ApiException(
                    statusCode: 403,
                    code: 'FORBIDDEN',
                    message: 'No tienes permiso.',
                  );
                }
                return _page([]);
              },
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, isTrue);
      expect(find.text('No tienes permiso.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay clientes registrados'), findsOneWidget);
    });

    testWidgets('inactivar pide confirmacion; reactivar no', (tester) async {
      final calls = <(int, bool)>[];
      var active = true;
      await tester.pumpWidget(
        list(
          loadCustomers:
              ({
                required limit,
                required offset,
                query,
                countryCode,
                isActive,
              }) async => _page([_customer(id: 4, active: active)]),
          setActive: (id, value) async {
            calls.add((id, value));
            active = value;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(calls, [(4, false)]);
      expect(find.text('Cliente inactivado.'), findsOneWidget);
      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(calls, [(4, false), (4, true)]);
      expect(find.text('Cliente reactivado.'), findsOneWidget);
    });

    Widget form({
      Map<String, dynamic>? customer,
      required SaveCustomer onSave,
    }) => MaterialApp(
      home: CustomerFormScreen(customer: customer, onSave: onSave),
    );

    // 0 nombre, 1 contacto, 2 correo, 3 pais, 4 EORI, 5 moneda
    testWidgets('el formulario valida obligatorios y el EORI segun el pais', (
      tester,
    ) async {
      tall(tester);
      Map<String, Object?>? sent;
      await tester.pumpWidget(form(onSave: (fields) async => sent = fields));
      final fields = find.byType(TextFormField);

      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(
        find.text('El nombre del cliente es obligatorio.'),
        findsOneWidget,
      );
      expect(find.text('El país es obligatorio.'), findsOneWidget);
      expect(sent, isNull);
      expect(
        tester.widget<TextFormField>(fields.at(5)).controller?.text,
        'USD',
        reason: 'moneda por defecto',
      );

      await tester.enterText(fields.at(0), ' Importadora Iberica ');
      await tester.enterText(fields.at(3), 'de');
      await tester.pump();
      expect(
        find.textContaining('Obligatorio para clientes de la Unión Europea'),
        findsOneWidget,
      );
      expect(find.text('EORI'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(
        find.text('El EORI es obligatorio para clientes de la Unión Europea.'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(4), 'FR12345678');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(
        find.text('El EORI debe empezar por DE (el país del cliente).'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(4), 'de-1234 5678z');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(sent, {
        'name': 'Importadora Iberica',
        'country_code': 'DE',
        'eori_number': 'DE12345678Z',
        'preferred_currency_code': 'USD',
      });
    });

    testWidgets('fuera de la UE el EORI es opcional', (tester) async {
      tall(tester);
      Map<String, Object?>? sent;
      await tester.pumpWidget(form(onSave: (fields) async => sent = fields));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Coffee Corp');
      await tester.enterText(fields.at(3), 'us');
      await tester.pump();
      expect(find.text('EORI (opcional)'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(sent, {
        'name': 'Coffee Corp',
        'country_code': 'US',
        'preferred_currency_code': 'USD',
      });
    });

    testWidgets(
      'en edicion solo se envia lo modificado y vaciar el EORI envia null',
      (tester) async {
        tall(tester);
        Map<String, Object?>? sent;
        await tester.pumpWidget(
          form(
            customer: {
              ..._customer(),
              'country_code': 'US',
              'eori_number': 'US123456',
            },
            onSave: (fields) async => sent = fields,
          ),
        );
        final fields = find.byType(TextFormField);
        expect(
          tester.widget<TextFormField>(fields.at(4)).controller?.text,
          'US123456',
        );
        await tester.enterText(fields.at(1), 'Luis');
        await tester.enterText(fields.at(4), '');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(sent, {'contact_name': 'Luis', 'eori_number': null});
      },
    );

    testWidgets('un error del servidor se muestra sin cerrar la pantalla', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(
        form(
          customer: _customer(),
          onSave: (fields) async => throw const ApiException(
            statusCode: 409,
            code: 'CONFLICT',
            message: 'Ya existe un cliente con ese EORI.',
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(4), 'ES99999999Z');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Ya existe un cliente con ese EORI.'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
    });
  });

  testWidgets(
    'recorrido completo: registrar, EORI repetido, editar, inactivar y reactivar',
    (tester) async {
      tester.view.physicalSize = const Size(700, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = AuthSession(tokenStore: _MemoryTokenStore());
      addTearDown(session.dispose);

      await tester.pumpWidget(RiExportApp(authSession: session));
      await tester.pumpAndSettle();
      final login = find.byType(TextFormField);
      await tester.enterText(login.at(0), 'admin@riexport.com');
      await tester.enterText(login.at(1), 'Admin123!');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clientes'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay clientes registrados'), findsOneWidget);

      Future<void> register(String name, String country, String eori) async {
        await tester.tap(find.byTooltip('Registrar cliente'));
        await tester.pumpAndSettle();
        final form = find.byType(TextFormField);
        await tester.enterText(form.at(0), name);
        await tester.enterText(form.at(3), country);
        await tester.enterText(form.at(4), eori);
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
      }

      await register('Importadora Iberica', 'ES', 'ES12345678Z');
      expect(find.text('Cliente registrado.'), findsOneWidget);
      expect(find.text('Importadora Iberica'), findsOneWidget);

      await register('Otra importadora', 'ES', 'es 12345678-z');
      expect(find.text('Ya existe un cliente con ese EORI.'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver a clientes'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar cliente'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Importadora Iberica SL',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Cliente actualizado.'), findsOneWidget);
      expect(find.text('Importadora Iberica SL'), findsOneWidget);

      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(find.text('Cliente inactivado.'), findsOneWidget);
      expect(find.text('Aún no hay clientes registrados'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivos').last);
      await tester.pumpAndSettle();
      expect(find.text('Importadora Iberica SL'), findsOneWidget);
      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(find.text('Cliente reactivado.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
