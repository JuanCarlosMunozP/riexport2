import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/backend/local_backend_client.dart';
import 'package:riexport_app/backend/supabase_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';
import 'package:riexport_app/features/customers/presentation/customer_accounts_screen.dart';
import 'package:riexport_app/features/customers/presentation/customer_history_screen.dart';
import 'package:riexport_app/features/customers/presentation/customer_list_screen.dart';

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

const _customer = {'id': 7, 'name': 'Importadora Iberica SL'};

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(700, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('backend local: cuentas vinculadas (PLAT-529)', () {
    late ApiClient api;
    late String? token;
    late int customerId;

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
      customerId =
          (await api.post(
                    '/customers',
                    body: {
                      'name': 'Coffee Corp',
                      'country_code': 'US',
                      'preferred_currency_code': 'USD',
                    },
                  )
                  as Map)['id']
              as int;
    });

    Future<void> register(String email) => api.post(
      '/auth/register',
      body: {
        'first_name': 'Luz',
        'last_name': 'Mora',
        'email': email,
        'password': 'secreto1',
      },
    );

    test(
      'vincula una cuenta por correo y la lista con su acceso al portal',
      () async {
        await register('luz@correo.com');
        final linked =
            await api.post(
                  '/customers/$customerId/accounts',
                  body: {'email': '  LUZ@correo.com '},
                )
                as Map;
        final items = linked['items'] as List;
        expect(items, hasLength(1));
        expect(items.single['email'], 'luz@correo.com');
        expect(items.single['first_name'], 'Luz');
        expect(items.single['account_is_active'], true);
        expect(
          items.single['has_portal_access'],
          true,
          reason: 'el rol cliente tiene el permiso base portal.read',
        );
        expect(
          ((await api.get('/customers/$customerId/accounts')) as Map)['items'],
          hasLength(1),
        );
      },
    );

    test(
      'un cliente puede tener varias cuentas y una cuenta varios clientes',
      () async {
        await register('luz@correo.com');
        await register('ana@correo.com');
        final other =
            (await api.post(
                  '/customers',
                  body: {
                    'name': 'Otro',
                    'country_code': 'US',
                    'preferred_currency_code': 'USD',
                  },
                )
                as Map)['id'];
        await api.post(
          '/customers/$customerId/accounts',
          body: {'email': 'luz@correo.com'},
        );
        await api.post(
          '/customers/$customerId/accounts',
          body: {'email': 'ana@correo.com'},
        );
        await api.post(
          '/customers/$other/accounts',
          body: {'email': 'luz@correo.com'},
        );
        expect(
          ((await api.get('/customers/$customerId/accounts')) as Map)['items'],
          hasLength(2),
        );
        expect(
          ((await api.get('/customers/$other/accounts')) as Map)['items'],
          hasLength(1),
        );
      },
    );

    test('valida correo, cuenta, cliente y duplicados', () async {
      await register('luz@correo.com');
      Future<void> bad(int id, Object? email, int status, String message) =>
          expectLater(
            api.post('/customers/$id/accounts', body: {'email': email}),
            throwsA(_status(status, message)),
          );
      await bad(customerId, '  ', 422, 'correo de la cuenta es obligatorio');
      await bad(customerId, 'sin-arroba', 422, 'formato válido');
      await bad(customerId, 'nadie@correo.com', 422, 'No existe una cuenta');
      await bad(999, 'luz@correo.com', 404, 'No se encontró el cliente');
      await api.post(
        '/customers/$customerId/accounts',
        body: {'email': 'luz@correo.com'},
      );
      await bad(customerId, 'luz@correo.com', 409, 'ya está vinculada');
      await api.patch(
        '/customers/$customerId/status',
        body: {'is_active': false},
      );
      await register('ana@correo.com');
      await bad(customerId, 'ana@correo.com', 422, 'cliente está inactivo');
      expect(
        ((await api.get('/customers/$customerId/accounts')) as Map)['items'],
        hasLength(1),
      );
    });

    test('desvincular quita el acceso y no se puede repetir', () async {
      await register('luz@correo.com');
      final linked =
          await api.post(
                '/customers/$customerId/accounts',
                body: {'email': 'luz@correo.com'},
              )
              as Map;
      final profileId = (linked['items'] as List).single['profile_id'];
      final after =
          await api.delete('/customers/$customerId/accounts/$profileId') as Map;
      expect(after['items'], isEmpty);
      await expectLater(
        api.delete('/customers/$customerId/accounts/$profileId'),
        throwsA(_status(404, 'No se encontró el vínculo')),
      );
    });

    test(
      'exige customers.update para vincular y customers.read para ver',
      () async {
        final saved = token;
        token = null;
        await register('luz@correo.com');
        final login =
            await api.post(
                  '/auth/login',
                  body: {'email': 'luz@correo.com', 'password': 'secreto1'},
                )
                as Map;
        token = login['access_token'] as String;
        await expectLater(
          api.get('/customers/$customerId/accounts'),
          throwsA(_status(403)),
        );
        await expectLater(
          api.post(
            '/customers/$customerId/accounts',
            body: {'email': 'luz@correo.com'},
          ),
          throwsA(_status(403)),
        );
        await expectLater(
          api.delete('/customers/$customerId/accounts/1'),
          throwsA(_status(403)),
        );
        await expectLater(
          api.get('/customers/$customerId/history'),
          throwsA(_status(403)),
        );
        token = saved;
      },
    );

    test(
      'el historial está disponible (vacío sin pedidos) y valida el cliente',
      () async {
        final history = await api.get('/customers/$customerId/history') as Map;
        expect(history['available'], true);
        expect(history['exports_available'], true);
        expect(history['orders'], isEmpty);
        expect(history['exports'], isEmpty);
        await expectLater(
          api.get('/customers/999/history'),
          throwsA(_status(404)),
        );
      },
    );

    test('el filtro por país combina con la búsqueda', () async {
      await api.post(
        '/customers',
        body: {
          'name': 'Otro US',
          'country_code': 'US',
          'preferred_currency_code': 'USD',
        },
      );
      await api.post(
        '/customers',
        body: {
          'name': 'Iberica',
          'country_code': 'ES',
          'eori_number': 'ES12345678Z',
          'preferred_currency_code': 'EUR',
        },
      );
      List names(Object? page) => [
        for (final i in (page as Map)['items'] as List) i['name'],
      ];
      expect(
        names(
          await api.get('/customers', queryParameters: {'country_code': 'es'}),
        ),
        ['Iberica'],
      );
      expect(
        names(
          await api.get(
            '/customers',
            queryParameters: {'country_code': 'US', 'q': 'otro'},
          ),
        ),
        ['Otro US'],
      );
      expect(
        names(
          await api.get(
            '/customers',
            queryParameters: {'country_code': 'ES', 'q': 'otro'},
          ),
        ),
        isEmpty,
      );
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
      'lee la vista de cuentas, vincula y desvincula con las funciones',
      () async {
        final calls = <String>[];
        final bodies = <String, Object?>{};
        final api = client((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            bodies[request.url.path] = jsonDecode(request.body);
            return http.Response('', 204);
          }
          expect(request.url.path, '/rest/v1/customer_account_link');
          expect(request.url.queryParameters['customer_id'], 'eq.7');
          return _json([
            {
              'customer_id': 7,
              'profile_id': 3,
              'email': 'luz@correo.com',
              'account_is_active': true,
              'has_portal_access': true,
            },
          ]);
        });
        expect(
          ((await api.get('/customers/7/accounts')) as Map)['items'],
          hasLength(1),
        );
        final linked =
            await api.post(
                  '/customers/7/accounts',
                  body: {'email': 'luz@correo.com'},
                )
                as Map;
        expect(linked['items'], hasLength(1));
        await api.delete('/customers/7/accounts/3');
        expect(bodies['/rest/v1/rpc/link_customer_user'], {
          'p_customer_id': 7,
          'p_email': 'luz@correo.com',
        });
        expect(bodies['/rest/v1/rpc/unlink_customer_user'], {
          'p_customer_id': 7,
          'p_profile_id': 3,
        });
        expect(calls.where((c) => c.startsWith('POST')), hasLength(2));
      },
    );

    test('traduce los errores del vínculo', () async {
      Future<void> mapped(
        Map<String, Object?> error,
        int status,
        String message,
      ) => expectLater(
        client(
          (_) async => _json(error, 400),
        ).post('/customers/7/accounts', body: {'email': 'x@y.co'}),
        throwsA(_status(status, message)),
      );
      await mapped(
        {'code': '22023', 'message': 'No existe una cuenta con ese correo.'},
        422,
        'No existe una cuenta',
      );
      await mapped(
        {
          'code': 'P0001',
          'message': 'Esa cuenta ya está vinculada a este cliente.',
        },
        409,
        'ya está vinculada',
      );
      await mapped(
        {'code': '42501', 'message': 'No tienes permiso para esta operación.'},
        403,
        'permiso',
      );
    });

    test(
      'el historial usa las vistas y, si no existen, informa available: false',
      () async {
        final paths = <String>[];
        final api = client((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('customer_order_history')) {
            return _json([
              {'order_id': 1, 'order_number': 'PO-1', 'order_total': 450},
            ]);
          }
          return _json([
            {
              'export_id': 2,
              'order_number': 'PO-1',
              'destination_country_code': 'DE',
            },
          ]);
        });
        final history = await api.get('/customers/7/history') as Map;
        expect(history['available'], true);
        expect(history['orders'], hasLength(1));
        expect(history['exports'], hasLength(1));
        expect(paths, [
          '/rest/v1/customer_order_history',
          '/rest/v1/customer_export_history',
        ]);

        final missing =
            await client(
                  (_) async =>
                      _json({'code': 'PGRST205', 'message': 'no existe'}, 404),
                ).get('/customers/7/history')
                as Map;
        expect(missing['available'], false);
        expect(missing['orders'], isEmpty);

        // Si solo falta la vista de exportaciones, los pedidos se muestran igual.
        final partial =
            await client((request) async {
                  return request.url.path.endsWith('customer_order_history')
                      ? _json([
                          {'order_id': 1},
                        ])
                      : _json({'code': 'PGRST205'}, 404);
                }).get('/customers/7/history')
                as Map;
        expect(partial['available'], true);
        expect(partial['exports'], isEmpty);

        await expectLater(
          client(
            (_) async => _json({'code': '42501', 'message': 'x'}, 403),
          ).get('/customers/7/history'),
          throwsA(_status(403)),
        );
      },
    );
  });

  group('pantalla de cuentas', () {
    Widget screen({
      required Future<List<Map<String, dynamic>>> Function() load,
      Future<void> Function(String)? link,
      Future<void> Function(int)? unlink,
      bool canEdit = true,
    }) => MaterialApp(
      home: CustomerAccountsScreen(
        customer: Map<String, dynamic>.from(_customer),
        loadAccounts: load,
        link: link ?? (_) async {},
        unlink: unlink ?? (_) async {},
        canEdit: canEdit,
      ),
    );

    Map<String, dynamic> account(
      int id, {
      bool active = true,
      bool portal = true,
    }) => {
      'profile_id': id,
      'email': 'cuenta$id@correo.com',
      'first_name': 'Luz',
      'last_name': 'Mora',
      'account_is_active': active,
      'has_portal_access': portal,
    };

    testWidgets(
      'lista las cuentas y avisa de las desactivadas o sin permiso de portal',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(
          screen(
            load: () async => [
              account(1),
              account(2, portal: false),
              account(3, active: false),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('cuenta1@correo.com'), findsOneWidget);
        expect(find.text('Sin permiso de portal'), findsOneWidget);
        expect(find.text('Cuenta desactivada'), findsOneWidget);
      },
    );

    testWidgets('estado vacío y error con reintento', (tester) async {
      _view(tester);
      var fail = true;
      await tester.pumpWidget(
        screen(
          load: () async {
            if (fail) {
              throw const ApiException(
                statusCode: 403,
                code: 'FORBIDDEN',
                message: 'No tienes permiso.',
              );
            }
            return [];
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No tienes permiso.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Este cliente aún no tiene cuentas vinculadas.'),
        findsOneWidget,
      );
    });

    testWidgets('valida el correo, vincula y recarga', (tester) async {
      _view(tester);
      final sent = <String>[];
      var linked = false;
      await tester.pumpWidget(
        screen(
          load: () async => linked ? [account(1)] : [],
          link: (email) async {
            sent.add(email);
            linked = true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular'));
      await tester.pump();
      expect(
        find.text('El correo de la cuenta es obligatorio.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), 'sin-arroba');
      await tester.tap(find.text('Vincular'));
      await tester.pump();
      expect(
        find.text('El correo no tiene un formato válido.'),
        findsOneWidget,
      );
      expect(sent, isEmpty);
      await tester.enterText(
        find.byType(TextFormField),
        ' Cuenta1@Correo.com ',
      );
      await tester.tap(find.text('Vincular'));
      await tester.pumpAndSettle();
      expect(sent, ['cuenta1@correo.com']);
      expect(find.text('Cuenta vinculada.'), findsOneWidget);
      expect(find.text('cuenta1@correo.com'), findsOneWidget);
    });

    testWidgets(
      'un error del servidor al vincular se muestra sin perder lo escrito',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(
          screen(
            load: () async => [],
            link: (_) async => throw const ApiException(
              statusCode: 422,
              code: 'VALIDATION_ERROR',
              message: 'No existe una cuenta con ese correo.',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'nadie@correo.com');
        await tester.tap(find.text('Vincular'));
        await tester.pumpAndSettle();
        expect(
          find.text('No existe una cuenta con ese correo.'),
          findsOneWidget,
        );
        expect(find.text('nadie@correo.com'), findsOneWidget);
      },
    );

    testWidgets('desvincular pide confirmación', (tester) async {
      _view(tester);
      final removed = <int>[];
      await tester.pumpWidget(
        screen(
          load: () async => [account(5)],
          unlink: (id) async => removed.add(id),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Desvincular cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);
      await tester.tap(find.byTooltip('Desvincular cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desvincular'));
      await tester.pumpAndSettle();
      expect(removed, [5]);
      expect(find.text('Cuenta desvinculada.'), findsOneWidget);
    });

    testWidgets(
      'sin permiso de edición no hay formulario ni se puede desvincular',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(
          screen(load: () async => [account(1)], canEdit: false),
        );
        await tester.pumpAndSettle();
        expect(find.text('Vincular'), findsNothing);
        final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.link_off_rounded),
        );
        expect(button.onPressed, isNull);
      },
    );
  });

  group('pantalla de historial', () {
    Widget screen(Future<Map<String, dynamic>> Function() load) => MaterialApp(
      home: CustomerHistoryScreen(
        customer: Map<String, dynamic>.from(_customer),
        loadHistory: load,
      ),
    );

    testWidgets('sin módulo de pedidos lo explica', (tester) async {
      _view(tester);
      await tester.pumpWidget(
        screen(() async => {'available': false, 'orders': [], 'exports': []}),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('estará disponible cuando se activen'),
        findsOneWidget,
      );
    });

    testWidgets('muestra pedidos con total y exportaciones', (tester) async {
      _view(tester);
      await tester.pumpWidget(
        screen(
          () async => {
            'available': true,
            'orders': [
              {
                'order_number': 'PO-0001',
                'created_at': '2026-01-10T00:00:00+00:00',
                'status': 'exported',
                'currency_code': 'USD',
                'order_total': 450,
                'export_count': 2,
              },
              {
                'order_number': 'PO-0002',
                'created_at': '2026-02-10',
                'status': 'pending',
                'currency_code': 'USD',
                'order_total': '30.0000',
                'export_count': 0,
              },
            ],
            'exports': [
              {
                'order_number': 'PO-0001',
                'destination_country_code': 'DE',
                'export_date': '2026-01-20',
                'status': 'shipped',
              },
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PO-0001'), findsOneWidget);
      expect(
        find.textContaining(
          '2026-01-10  ·  exported  ·  450.00 USD  ·  2 exportación(es)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('30.00 USD'), findsOneWidget);
      expect(find.text('PO-0001 → DE'), findsOneWidget);
      expect(find.textContaining('2026-01-20  ·  shipped'), findsOneWidget);
    });

    testWidgets('disponible pero sin datos muestra los vacíos', (tester) async {
      _view(tester);
      await tester.pumpWidget(
        screen(() async => {'available': true, 'orders': [], 'exports': []}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Este cliente aún no tiene pedidos.'), findsOneWidget);
      expect(
        find.text('Este cliente aún no tiene exportaciones.'),
        findsOneWidget,
      );
    });

    testWidgets('error con reintento', (tester) async {
      _view(tester);
      var fail = true;
      await tester.pumpWidget(
        screen(() async {
          if (fail) {
            throw const ApiException(
              statusCode: 403,
              code: 'FORBIDDEN',
              message: 'No tienes permiso.',
            );
          }
          return {'available': true, 'orders': [], 'exports': []};
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('No tienes permiso.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Este cliente aún no tiene pedidos.'), findsOneWidget);
    });
  });

  group('lista de clientes', () {
    Map<String, Object?> page(List<Map<String, Object?>> items) => {
      'items': items,
      'pagination': {'total': items.length, 'limit': 20, 'offset': 0},
    };

    testWidgets(
      'el filtro por país solo se envía con 2 letras y vuelve a cargar',
      (tester) async {
        final seen = <String?>[];
        await tester.pumpWidget(
          MaterialApp(
            home: CustomerListScreen(
              loadPermissions: () async => {'customers.read'},
              loadCustomers:
                  ({
                    required limit,
                    required offset,
                    query,
                    countryCode,
                    isActive,
                  }) async {
                    seen.add(countryCode);
                    return page([]);
                  },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(seen, [null]);
        await tester.enterText(find.widgetWithText(TextField, 'País'), 'e');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(seen.last, isNull, reason: 'con una sola letra no se filtra');
        await tester.enterText(find.widgetWithText(TextField, 'País'), 'es');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(seen.last, 'ES');
        expect(
          find.text('No se encontraron clientes con esos filtros'),
          findsOneWidget,
        );
      },
    );

    testWidgets('el menú abre cuentas e historial del cliente', (tester) async {
      Map<String, dynamic>? accounts;
      Map<String, dynamic>? history;
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerListScreen(
            loadPermissions: () async => {'customers.read', 'customers.update'},
            openAccounts: (c) => accounts = c,
            openHistory: (c) => history = c,
            loadCustomers:
                ({
                  required limit,
                  required offset,
                  query,
                  countryCode,
                  isActive,
                }) async => page([
                  {
                    'id': 3,
                    'name': 'Coffee Corp',
                    'country_code': 'US',
                    'preferred_currency_code': 'USD',
                    'is_active': true,
                  },
                ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuentas de acceso'));
      await tester.pumpAndSettle();
      expect(accounts?['id'], 3);
      await tester.tap(find.byTooltip('Acciones del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historial comercial'));
      await tester.pumpAndSettle();
      expect(history?['id'], 3);
    });
  });
}
