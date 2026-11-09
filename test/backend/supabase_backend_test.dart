import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/backend/supabase_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?h},
    );

ApiClient _api(
  Future<http.Response> Function(http.Request request) handler, {
  String? token,
}) => ApiClient(
  config: ApiConfig(),
  client: SupabaseBackendClient(
    url: 'https://demo.supabase.co',
    anonKey: 'anon-key',
    inner: MockClient(handler),
  ),
  tokenProvider: () => token,
);

TypeMatcher<ApiException> _status(int code) =>
    isA<ApiException>().having((e) => e.statusCode, 'status', code);

/// JWT de prueba con `sub` indicado (la firma no se valida en el cliente).
String _token(String sub) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': sub})))
      .replaceAll('=', '');
  return 'h.$payload.s';
}

void main() {
  test('rejects cleartext Supabase endpoints outside loopback', () {
    expect(
      () => SupabaseBackendClient(
        url: 'http://supabase.example.test',
        anonKey: 'public',
      ),
      throwsArgumentError,
    );
    final local = SupabaseBackendClient(
      url: 'http://127.0.0.1:54321',
      anonKey: 'public',
    );
    local.close();
  });

  test('login valida la cuenta activa y devuelve el token', () async {
    final seen = <String>[];
    final api = _api((request) async {
      seen.add('${request.method} ${request.url.path}');
      expect(request.headers['apikey'], 'anon-key');
      if (request.url.path == '/auth/v1/token') {
        expect(jsonDecode(request.body), {
          'email': 'ana@correo.com',
          'password': 'secreto',
        });
        return _json({'access_token': 'jwt', 'expires_in': 3600});
      }
      expect(request.headers['Authorization'], 'Bearer jwt');
      return _json([
        {
          'is_active': true,
          'role': {'is_active': true},
        },
      ]);
    });
    final result =
        await api.post(
              '/auth/login',
              body: {'email': ' ANA@correo.com ', 'password': 'secreto'},
            )
            as Map<String, dynamic>;
    expect(result['access_token'], 'jwt');
    expect(result['token_type'], 'bearer');
    expect(seen, ['POST /auth/v1/token', 'GET /rest/v1/profile']);
  });

  test(
    'login rechaza credenciales, correo sin confirmar y cuentas inactivas',
    () async {
      Future<void> expectLoginError(
        Future<http.Response> Function(http.Request) handler,
        String message,
      ) => expectLater(
        _api(
          handler,
        ).post('/auth/login', body: {'email': 'a@b.co', 'password': 'x'}),
        throwsA(
          _status(401).having((e) => e.message, 'message', contains(message)),
        ),
      );

      await expectLoginError(
        (_) async => _json({'error_code': 'invalid_credentials'}, 400),
        'incorrectos',
      );
      await expectLoginError(
        (_) async => _json({'error_code': 'email_not_confirmed'}, 400),
        'Confirma tu correo',
      );
      await expectLoginError(
        (request) async => request.url.path == '/auth/v1/token'
            ? _json({'access_token': 'jwt'})
            : _json([
                {
                  'is_active': false,
                  'role': {'is_active': true},
                },
              ]),
        'incorrectos',
      );
    },
  );

  test('el registro no envia rol y traduce correo duplicado', () async {
    Map<String, dynamic>? sent;
    final ok = _api((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'id': 'uuid'});
    });
    await ok.post(
      '/auth/register',
      body: {
        'email': 'Luz@Correo.com',
        'password': 'secreto',
        'first_name': 'Luz',
        'last_name': 'Mora',
        'role_id': 1,
      },
    );
    expect(sent!['email'], 'luz@correo.com');
    expect(sent!.containsKey('role_id'), isFalse);
    expect((sent!['data'] as Map).containsKey('role_id'), isFalse);

    final duplicated = _api(
      (_) async => _json({'error_code': 'user_already_exists'}, 422),
    );
    await expectLater(
      duplicated.post(
        '/auth/register',
        body: {
          'email': 'luz@correo.com',
          'password': 'x',
          'first_name': 'L',
          'last_name': 'M',
        },
      ),
      throwsA(_status(409)),
    );
  });

  test('lista usuarios con filtros y total desde content-range', () async {
    late Uri url;
    final api = _api(token: 'jwt', (request) async {
      url = request.url;
      expect(request.headers['Authorization'], 'Bearer jwt');
      return _json(
        [
          {'id': 1, 'email': 'a@b.co', 'first_name': 'Ana', 'is_active': true},
        ],
        200,
        {'content-range': '0-0/41'},
      );
    });
    final page =
        await api.get(
              '/users',
              queryParameters: {
                'limit': '20',
                'offset': '20',
                'q': 'ana,(x)',
                'is_active': 'true',
              },
            )
            as Map<String, dynamic>;
    expect((page['pagination'] as Map)['total'], 41);
    expect(url.path, '/rest/v1/admin_user_list');
    expect(url.queryParameters['select'], contains('role_name'));
    expect(url.queryParameters['is_active'], 'eq.true');
    expect(url.queryParameters['offset'], '20');
    expect(url.queryParameters['or'], isNot(contains(',(')));
  });

  test(
    'busqueda con texto de forma SQL conserva la consulta REST fija',
    () async {
      late http.Request seen;
      final api = _api(token: 'jwt', (request) async {
        seen = request;
        return _json(<Object>[]);
      });

      await api.get('/users', queryParameters: {'q': "x') OR 1=1 --"});

      expect(seen.method, 'GET');
      expect(seen.url.path, '/rest/v1/admin_user_list');
      expect(seen.body, isEmpty);
      expect(seen.url.queryParameters['or'], startsWith('(first_name.ilike.*'));
      expect(seen.url.queryParameters['or'], endsWith('*)'));
    },
  );

  test(
    'registra pedido mediante RPC con la cabecera y sus lineas atomicas',
    () async {
      final api = _api(token: 'jwt', (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/create_customer_order');
        expect(jsonDecode(request.body), {
          'p': {
            'customer_id': 12,
            'note': 'Pedido inicial',
            'lines': [
              {'product_lot_id': 8, 'quantity': 25, 'unit_price': 2.5},
            ],
          },
        });
        return _json({
          'id': 31,
          'order_number': 'PED-2026-000031',
          'customer_id': 12,
          'currency_code': 'EUR',
          'status': 'draft',
        });
      });

      final result =
          await api.post(
                '/orders',
                body: {
                  'customer_id': 12,
                  'note': 'Pedido inicial',
                  'lines': [
                    {'product_lot_id': 8, 'quantity': 25, 'unit_price': 2.5},
                  ],
                },
              )
              as Map;
      expect(result['order_number'], 'PED-2026-000031');
      expect(result['currency_code'], 'EUR');
    },
  );

  test(
    'envia el cambio de estado al RPC transaccional con el id fijado por ruta',
    () async {
      final api = _api(token: 'jwt', (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/transition_customer_order');
        expect(jsonDecode(request.body), {
          'p': {'order_id': 31, 'status': 'cancelled'},
        });
        return _json({
          'id': 31,
          'order_number': 'PED-31',
          'status': 'cancelled',
        });
      });

      final response =
          await api.patch('/orders/31/status', body: {'status': 'cancelled'})
              as Map;
      expect(response['status'], 'cancelled');
    },
  );

  test(
    'consulta pedidos relacionados aplicando busqueda, estado y paginacion',
    () async {
      final api = _api(token: 'jwt', (request) async {
        expect(request.url.path, '/rest/v1/customer_order_details');
        expect(request.url.queryParameters['status'], 'eq.confirmed');
        expect(
          request.url.queryParameters['or'],
          contains('customer_name.ilike.*Finca*'),
        );
        expect(request.url.queryParameters['limit'], '10');
        expect(request.url.queryParameters['offset'], '20');
        expect(request.headers['Prefer'], 'count=exact');
        return _json(
          [
            {
              'id': 31,
              'customer_name': 'Finca Andina',
              'line_count': 2,
              'order_total': 50,
              'lines': [],
            },
          ],
          200,
          {'content-range': '20-20/21'},
        );
      });
      final response =
          await api.get(
                '/orders',
                queryParameters: {
                  'q': 'Finca',
                  'status': 'confirmed',
                  'limit': '10',
                  'offset': '20',
                },
              )
              as Map;
      expect(
        (response['items'] as List).single['customer_name'],
        'Finca Andina',
      );
      expect((response['pagination'] as Map)['total'], 21);
    },
  );

  test('consulta catálogos de destino e Incoterm', () async {
    final api = _api(token: 'jwt', (request) async {
      expect(request.method, 'GET');
      if (request.url.path.endsWith('/export_destination')) {
        expect(request.url.queryParameters['is_active'], 'eq.true');
        return _json([
          {'code': 'DE', 'name': 'Alemania'},
        ]);
      }
      expect(request.url.path, '/rest/v1/incoterm');
      return _json([
        {'code': 'FOB', 'name': 'Franco a bordo'},
      ]);
    });
    final destinations = await api.get('/export-catalogs/destinations') as Map;
    final incoterms = await api.get('/export-catalogs/incoterms') as Map;
    expect((destinations['items'] as List).single['code'], 'DE');
    expect((incoterms['items'] as List).single['code'], 'FOB');
  });

  test('edita un pedido con RPC y consulta pedido individual', () async {
    final api = _api(token: 'jwt', (request) async {
      if (request.url.path == '/rest/v1/rpc/update_customer_order') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'p': {
            'order_id': 31,
            'customer_id': 4,
            'note': 'Revisado',
            'lines': [
              {'product_lot_id': 8, 'quantity': 10, 'unit_price': 4.5},
            ],
          },
        });
        return _json({'id': 31, 'status': 'draft'});
      }
      expect(request.url.path, '/rest/v1/customer_order_details');
      expect(request.url.queryParameters['id'], 'eq.31');
      return _json([
        {'id': 31, 'status': 'draft', 'lines': []},
      ]);
    });

    final updated =
        await api.patch(
              '/orders/31',
              body: {
                'customer_id': 4,
                'note': 'Revisado',
                'lines': [
                  {'product_lot_id': 8, 'quantity': 10, 'unit_price': 4.5},
                ],
              },
            )
            as Map;
    expect(updated['status'], 'draft');
    final order = await api.get('/orders/31') as Map;
    expect(order['id'], 31);
  });

  test('registra exportación usando el RPC transaccional', () async {
    final api = _api(token: 'jwt', (request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/create_customer_export');
      expect(jsonDecode(request.body), {
        'p': {
          'order_id': 31,
          'destination_country_code': 'DE',
          'incoterm_code': 'FOB',
          'export_date': '2026-10-22',
          'lines': [
            {'order_line_id': 42, 'quantity': 12.5},
          ],
        },
      });
      return _json({
        'id': 9,
        'order_id': 31,
        'status': 'draft',
        'destination_country_code': 'DE',
        'incoterm_code': 'FOB',
      });
    });
    final result =
        await api.post(
              '/exports',
              body: {
                'order_id': 31,
                'destination_country_code': 'DE',
                'incoterm_code': 'FOB',
                'export_date': '2026-10-22',
                'lines': [
                  {'order_line_id': 42, 'quantity': 12.5},
                ],
              },
            )
            as Map;
    expect(result['id'], 9);
    expect(result['incoterm_code'], 'FOB');
  });

  test('confirma el correo del registro con el código OTP de signup', () async {
    final paths = <String>[];
    final api = _api((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/auth/v1/verify') {
        expect(jsonDecode(request.body), {
          'type': 'signup',
          'email': 'ana@correo.com',
          'token': '123456',
        });
        return _json({'access_token': 'temp'});
      }
      return http.Response('', 204);
    });
    final result =
        await api.post(
              '/auth/email-confirmations',
              body: {'email': 'Ana@correo.com', 'code': '123456'},
            )
            as Map;
    expect(result['message'], contains('confirmado'));
    expect(paths, ['/auth/v1/verify', '/auth/v1/logout']);

    final invalid = _api((_) async => _json({'code': 'otp_expired'}, 403));
    await expectLater(
      invalid.post(
        '/auth/email-confirmations',
        body: {'email': 'ana@correo.com', 'code': '123456'},
      ),
      throwsA(_status(400)),
    );
  });

  test('declaración EUDR usa el RPC export_eudr_declaration', () async {
    final api = _api(token: 'jwt', (request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/export_eudr_declaration');
      expect(jsonDecode(request.body), {'p_export_id': 9});
      return _json({
        'export_id': 9,
        'traceability_valid': false,
        'issues': ['1 línea(s) sin código arancelario HS.'],
      });
    });
    final result = await api.get('/exports/9/eudr') as Map;
    expect(result['traceability_valid'], isFalse);
    expect(result['issues'], hasLength(1));
  });

  test('genera el PDF con la Edge Function y firma la descarga', () async {
    final paths = <String>[];
    final api = _api(token: 'jwt', (request) async {
      paths.add(request.url.path);
      if (request.url.path == '/functions/v1/generate-document') {
        expect(jsonDecode(request.body), {
          'export_id': 9,
          'document_type': 'export_summary',
        });
        return _json({
          'id': 1,
          'version': 1,
          'object_path': 'exports/9/export_summary/v1.pdf',
        }, 201);
      }
      expect(
        request.url.path,
        '/storage/v1/object/sign/export-documents/exports/9/export_summary/v1.pdf',
      );
      return _json({'signedURL': '/object/sign/export-documents/x.pdf?token=t'});
    });
    final result =
        await api.post(
              '/exports/9/documents',
              body: {'document_type': 'export_summary'},
            )
            as Map;
    expect(paths, hasLength(2));
    expect(
      result['download_url'],
      'https://demo.supabase.co/storage/v1/object/sign/export-documents/x.pdf?token=t',
    );
  });

  test('traduce errores de la base y bloquea el cambio de correo', () async {
    final denied = _api(
      token: 'jwt',
      (_) async => _json({'code': '42501', 'message': 'denied'}, 403),
    );
    await expectLater(denied.get('/users'), throwsA(_status(403)));

    final guard = _api(
      token: 'jwt',
      (_) async => _json({
        'code': 'P0001',
        'message': 'No se puede dejar el sistema sin un administrador activo.',
      }, 400),
    );
    await expectLater(
      guard.patch('/users/1/deactivate'),
      throwsA(
        _status(
          409,
        ).having((e) => e.message, 'message', contains('administrador')),
      ),
    );

    await expectLater(
      _api(
        token: 'jwt',
        (_) async => _json([]),
      ).patch('/users/1', body: {'email': 'otro@correo.com'}),
      throwsA(_status(422)),
    );
  });

  test(
    'roles: lista con permisos, crea y reemplaza permisos via RPC',
    () async {
      final calls = <String>[];
      final role = {
        'id': 2,
        'name': 'supervisor',
        'description': null,
        'is_active': true,
        'role_permission': [
          {'permission_code': 'users.read'},
        ],
      };
      final api = _api(token: 'jwt', (request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/rpc/set_role_permissions') {
          expect(jsonDecode(request.body), {
            'p_role_id': 2,
            'p_codes': ['users.read'],
          });
          return http.Response('', 204);
        }
        return _json([role]);
      });

      final roles =
          await api.get('/roles', queryParameters: {'include_inactive': 'true'})
              as Map<String, dynamic>;
      expect((roles['items'] as List).single['permission_codes'], [
        'users.read',
      ]);

      final created =
          await api.post('/roles', body: {'name': 'Supervisor'})
              as Map<String, dynamic>;
      expect(created['name'], 'supervisor');

      final updated =
          await api.put(
                '/roles/2/permissions',
                body: {
                  'permission_codes': ['users.read'],
                },
              )
              as Map<String, dynamic>;
      expect(updated['permission_codes'], ['users.read']);
      expect(calls, contains('POST /rest/v1/rpc/set_role_permissions'));
    },
  );

  test(
    'perfil propio: lee su fila y pide el cambio de correo a Supabase Auth',
    () async {
      final token = _token('user-uuid');
      final calls = <String>[];
      final api = _api(token: token, (request) async {
        calls.add('${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], 'Bearer $token');
        if (request.url.path == '/rest/v1/profile') {
          expect(request.url.queryParameters['auth_user_id'], 'eq.user-uuid');
          return _json([
            {'id': 7, 'email': 'ana@correo.com', 'first_name': 'Ana'},
          ]);
        }
        expect(jsonDecode(request.body), {'email': 'nuevo@correo.com'});
        return _json({'id': 'user-uuid', 'new_email': 'nuevo@correo.com'});
      });

      final me = await api.get('/me') as Map<String, dynamic>;
      expect(me['email'], 'ana@correo.com');

      final result =
          await api.patch('/me', body: {'email': ' Nuevo@Correo.com '})
              as Map<String, dynamic>;
      expect(result['pending_email'], 'nuevo@correo.com');
      expect(result['message'], contains('confirmación'));
      expect(calls, ['GET /rest/v1/profile', 'PUT /auth/v1/user']);
    },
  );

  test(
    'perfil propio: exige sesion y traduce errores de Supabase Auth',
    () async {
      await expectLater(
        _api((_) async => _json([])).get('/me'),
        throwsA(_status(401)),
      );

      final token = _token('u');
      Future<void> expectError(String code, int status) => expectLater(
        _api(
          token: token,
          (_) async => _json({'error_code': code}, 422),
        ).patch('/me', body: {'email': 'otro@correo.com'}),
        throwsA(_status(status)),
      );
      await expectError('email_exists', 409);
      await expectError('same_email', 422);
      await expectLater(
        _api(
          token: token,
          (_) async => _json([]),
        ).patch('/me', body: {'email': 'mal'}),
        throwsA(_status(422)),
      );
    },
  );

  test(
    '/me devuelve los permisos del rol activo y ninguno si esta inactivo',
    () async {
      final token = _token('u');
      Map<String, dynamic> row(bool active) => {
        'id': 1,
        'email': 'a@b.co',
        'role': {
          'is_active': active,
          'role_permission': [
            {'permission_code': 'users.read'},
            {'permission_code': 'roles.read'},
          ],
        },
      };

      final active = _api(token: token, (_) async => _json([row(true)]));
      final me = await active.get('/me') as Map<String, dynamic>;
      expect(me['permission_codes'], ['roles.read', 'users.read']);
      expect(me.containsKey('role'), isFalse);

      final inactive = _api(token: token, (_) async => _json([row(false)]));
      expect(
        ((await inactive.get('/me'))
            as Map<String, dynamic>)['permission_codes'],
        isEmpty,
      );
    },
  );

  test(
    'autoedicion: PATCH /me con nombres y telefono usa la fila propia',
    () async {
      final token = _token('user-uuid');
      late Uri url;
      Map<String, dynamic>? sent;
      final api = _api(token: token, (request) async {
        url = request.url;
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.method, 'PATCH');
        expect(request.headers['Prefer'], 'return=representation');
        return _json([
          {'id': 7, 'first_name': 'Ana María', 'phone': null},
        ]);
      });

      final row =
          await api.patch(
                '/me',
                body: {'first_name': ' Ana María ', 'phone': '  '},
              )
              as Map<String, dynamic>;
      expect(url.path, '/rest/v1/profile');
      expect(url.queryParameters['auth_user_id'], 'eq.user-uuid');
      expect(sent, {'first_name': 'Ana María', 'phone': null});
      expect(row['first_name'], 'Ana María');
    },
  );

  test(
    'autoedicion: rechaza campos ajenos, mezclar correo y sin sesion',
    () async {
      final token = _token('u');
      final api = _api(token: token, (_) async => _json([]));
      for (final body in <Map<String, Object?>>[
        {'role_id': 1},
        {'is_active': false},
        {'first_name': ''},
        {'first_name': 'Ana', 'email': 'otro@correo.com'},
        <String, Object?>{},
      ]) {
        await expectLater(api.patch('/me', body: body), throwsA(_status(422)));
      }
      await expectLater(
        _api((_) async => _json([])).patch('/me', body: {'first_name': 'Ana'}),
        throwsA(_status(401)),
      );
      // La base rechaza el cambio de rol propio: se traduce a conflicto, sin cerrar la app.
      final guard = _api(
        token: token,
        (_) async => _json({
          'code': 'P0001',
          'message': 'No puedes cambiar tu propio rol.',
        }, 400),
      );
      await expectLater(
        guard.patch('/me', body: {'first_name': 'Ana'}),
        throwsA(
          _status(
            409,
          ).having((e) => e.message, 'message', contains('propio rol')),
        ),
      );
    },
  );

  test(
    'registro: contraseña débil y correo inválido llegan en español y con detalle',
    () async {
      Future<ApiException> fail(
        Map<String, Object?> authError,
        int status,
      ) async {
        final api = _api((_) async => _json(authError, status));
        try {
          await api.post(
            '/auth/register',
            body: {
              'email': 'qa@example.com',
              'password': '123',
              'first_name': 'QA',
              'last_name': 'Registro',
            },
          );
        } on ApiException catch (error) {
          return error;
        }
        throw StateError('Se esperaba ApiException');
      }

      // Respuestas reales de Supabase (comprobadas con curl el 2026-10-08).
      final weak = await fail({
        'code': 422,
        'error_code': 'weak_password',
        'msg': 'Password should be at least 6 characters.',
      }, 422);
      expect(weak.statusCode, 422);
      expect(weak.message, contains('12 caracteres'));
      expect(weak.details.single.field, 'password');

      final badEmail = await fail({
        'code': 400,
        'error_code': 'validation_failed',
        'msg': 'Unable to validate email address: invalid format',
      }, 400);
      expect(badEmail.statusCode, 422);
      expect(badEmail.message, 'Ingresa un correo válido.');
      expect(badEmail.message, isNot(contains('Unable')));
    },
  );

  test(
    'cerrar sesion revoca la sesion en Supabase y no falla sin token',
    () async {
      final token = _token('u');
      final calls = <String>[];
      final api = _api(token: token, (request) async {
        calls.add('${request.method} ${request.url.path}?${request.url.query}');
        expect(request.headers['Authorization'], 'Bearer $token');
        return http.Response('', 204);
      });
      expect(await api.post('/auth/logout'), isNull);
      expect(calls, ['POST /auth/v1/logout?scope=local']);

      final sinToken = _api(
        (_) async => fail('no debe llamar a Supabase sin token'),
      );
      expect(await sinToken.post('/auth/logout'), isNull);
    },
  );

  test(
    'un usuario vetado (desactivado) no inicia sesion y no se revela el motivo',
    () async {
      final api = _api(
        (_) async => _json({
          'code': 403,
          'error_code': 'user_banned',
          'msg': 'User is banned',
        }, 403),
      );
      await expectLater(
        api.post('/auth/login', body: {'email': 'a@b.co', 'password': 'x'}),
        throwsA(
          _status(
            401,
          ).having((e) => e.message, 'message', contains('incorrectos')),
        ),
      );
    },
  );

  test(
    '/me con el perfil oculto por la base (cuenta desactivada) es un 401',
    () async {
      final api = _api(token: _token('u'), (_) async => _json([]));
      await expectLater(
        api.get('/me'),
        throwsA(
          _status(
            401,
          ).having((e) => e.message, 'message', contains('no está activa')),
        ),
      );
    },
  );

  test(
    'recuperacion: pide el codigo con respuesta neutra y respeta el limite de correos',
    () async {
      final calls = <String>[];
      Map<String, dynamic>? sent;
      final api = _api((request) async {
        calls.add('${request.method} ${request.url.path}');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({});
      });
      final result =
          await api.post(
                '/auth/password-reset-requests',
                body: {'email': ' Ana@Correo.com '},
              )
              as Map<String, dynamic>;
      expect(calls, ['POST /auth/v1/recover']);
      expect(sent, {'email': 'ana@correo.com'});
      expect(result['message'], contains('Si existe una cuenta'));
      expect(result.containsKey('dev_code'), isFalse);

      // Correo con formato inválido: ni siquiera se llama a Supabase.
      await expectLater(
        _api((_) async => fail('no debe llamar')).post(
          '/auth/password-reset-requests',
          body: {'email': 'no-es-correo'},
        ),
        throwsA(_status(422)),
      );
      // Límite de correos de Supabase.
      await expectLater(
        _api(
          (_) async => _json({'error_code': 'over_email_send_rate_limit'}, 429),
        ).post(
          '/auth/password-reset-requests',
          body: {'email': 'ana@correo.com'},
        ),
        throwsA(_status(429)),
      );
    },
  );

  test(
    'recuperacion: canjea el codigo, cambia la contrasena y cierra la sesion temporal',
    () async {
      final calls = <String>[];
      final api = _api((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/auth/v1/verify') {
          expect(jsonDecode(request.body), {
            'type': 'recovery',
            'email': 'ana@correo.com',
            'token': '123456',
          });
          return _json({'access_token': 'temporal'});
        }
        expect(request.headers['Authorization'], 'Bearer temporal');
        if (request.url.path == '/auth/v1/user') {
          expect(jsonDecode(request.body), {'password': 'ClaveNueva-2026'});
        }
        return _json({});
      });
      final result = await api.post(
        '/auth/password-resets',
        body: {
          'email': 'ana@correo.com',
          'code': '123456',
          'new_password': 'ClaveNueva-2026',
        },
      );
      expect(result, isNull);
      expect(calls, [
        'POST /auth/v1/verify',
        'PUT /auth/v1/user',
        'POST /auth/v1/logout',
      ]);
    },
  );

  test(
    'recuperacion: codigo invalido, contrasena debil o repetida se traducen',
    () async {
      Future<ApiException> fail(
        Future<http.Response> Function(http.Request) handler, {
        String code = '123456',
      }) async {
        try {
          await _api(handler).post(
            '/auth/password-resets',
            body: {
              'email': 'ana@correo.com',
              'code': code,
              'new_password': 'x',
            },
          );
        } on ApiException catch (error) {
          return error;
        }
        throw StateError('Se esperaba ApiException');
      }

      // Respuesta real de Supabase con un código falso (curl, 2026-10-08): 403 otp_expired.
      final invalid = await fail(
        (_) async => _json({
          'code': 403,
          'error_code': 'otp_expired',
          'msg': 'Token has expired or is invalid',
        }, 403),
      );
      expect(invalid.statusCode, 400);
      expect(invalid.code, 'INVALID_CODE');
      expect(invalid.message, contains('no es válido o ya venció'));

      http.Response session(http.Request r) => r.url.path == '/auth/v1/verify'
          ? _json({'access_token': 't'})
          : _json({});
      final weak = await fail(
        (r) async => r.url.path == '/auth/v1/verify'
            ? session(r)
            : _json({'error_code': 'weak_password'}, 422),
      );
      expect(weak.statusCode, 422);
      expect(weak.message, contains('12 caracteres'));

      final same = await fail(
        (r) async => r.url.path == '/auth/v1/verify'
            ? session(r)
            : _json({'error_code': 'same_password'}, 422),
      );
      expect(same.message, contains('distinta de la anterior'));

      // Código con formato inválido: no se llama a Supabase.
      final bad = await fail(
        (_) async => throw StateError('no debe llamar'),
        code: '12',
      );
      expect(bad.statusCode, 422);
    },
  );

  test('reactivar un usuario actualiza is_active a true', () async {
    Map<String, dynamic>? sent;
    final api = _api(token: 'jwt', (request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.queryParameters['id'], 'eq.5');
      return _json([
        {'id': 5, 'is_active': true},
      ]);
    });
    final row = await api.patch('/users/5/activate') as Map<String, dynamic>;
    expect(sent, {'is_active': true});
    expect(row['is_active'], isTrue);
  });

  group('productos (cliente de Supabase)', () {
    final row = {
      'id': 7,
      'type': 'coffee',
      'variety': 'Caturra',
      'is_active': true,
      'certifications': [],
      'certification_ids': [],
    };

    test('el listado usa la vista, filtros, busqueda segura y total', () async {
      late Uri url;
      final api = _api(token: 'jwt', (request) async {
        url = request.url;
        expect(request.headers['Prefer'], 'count=exact');
        return _json([row], 200, {'content-range': '0-0/12'});
      });
      final page =
          await api.get(
                '/products',
                queryParameters: {
                  'limit': '20',
                  'offset': '40',
                  'type': 'coffee',
                  'is_active': 'true',
                  'certification_id': '3',
                  'q': 'cat,(x)',
                  'quality': 'exc*',
                },
              )
              as Map<String, dynamic>;
      expect((page['pagination'] as Map)['total'], 12);
      expect(url.path, '/rest/v1/product_catalog');
      expect(url.queryParameters['type'], 'eq.coffee');
      expect(url.queryParameters['is_active'], 'eq.true');
      expect(url.queryParameters['certification_ids'], 'cs.{3}');
      expect(url.queryParameters['offset'], '40');
      expect(url.queryParameters['quality_grade'], isNot(contains('*x')));
      expect(url.queryParameters['or'], isNot(contains(',(')));
      expect(url.queryParameters['select'], contains('certification_ids'));
    });

    test(
      'crear usa la funcion atomica y devuelve la fila del catalogo',
      () async {
        final calls = <String>[];
        final api = _api(token: 'jwt', (request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.url.path == '/rest/v1/rpc/create_product') {
            expect(jsonDecode(request.body), {
              'p': {
                'type': 'coffee',
                'variety': 'Caturra',
                'certification_ids': [1],
              },
            });
            return _json(7);
          }
          expect(request.url.queryParameters['id'], 'eq.7');
          return _json([row]);
        });
        final created =
            await api.post(
                  '/products',
                  body: {
                    'type': 'coffee',
                    'variety': 'Caturra',
                    'certification_ids': [1],
                  },
                )
                as Map<String, dynamic>;
        expect(created['id'], 7);
        expect(calls, [
          'POST /rest/v1/rpc/create_product',
          'GET /rest/v1/product_catalog',
        ]);
      },
    );

    test(
      'editar, inactivar y certificaciones llaman a sus funciones',
      () async {
        final bodies = <String, Object?>{};
        final api = _api(token: 'jwt', (request) async {
          if (request.method == 'POST') {
            bodies[request.url.path] = jsonDecode(request.body);
            return http.Response('', 204);
          }
          return _json([row]);
        });
        await api.patch('/products/7', body: {'variety': 'Castillo'});
        await api.patch('/products/7/status', body: {'is_active': false});
        await api.put(
          '/products/7/certifications',
          body: {
            'certification_ids': [1, 2],
          },
        );
        expect(bodies['/rest/v1/rpc/update_product'], {
          'p_id': 7,
          'p': {'variety': 'Castillo'},
        });
        expect(bodies['/rest/v1/rpc/set_product_active'], {
          'p_id': 7,
          'p_active': false,
        });
        expect(bodies['/rest/v1/rpc/set_product_certifications'], {
          'p_id': 7,
          'p_ids': [1, 2],
        });

        await expectLater(
          api.patch('/products/7/status', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.put(
            '/products/7/certifications',
            body: {
              'certification_ids': ['a'],
            },
          ),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/products/7', body: {}),
          throwsA(_status(422)),
        );
      },
    );

    test('traduce los errores de las funciones de la base', () async {
      Future<void> expectMapped(
        Map<String, Object?> error,
        int status,
        String message,
      ) => expectLater(
        _api(
          token: 'jwt',
          (_) async => _json(error, 400),
        ).post('/products', body: {'type': 'coffee'}),
        throwsA(
          _status(
            status,
          ).having((e) => e.message, 'message', contains(message)),
        ),
      );
      await expectMapped(
        {'code': '22023', 'message': 'La humedad debe estar entre 0 y 100.'},
        422,
        'entre 0 y 100',
      );
      await expectMapped(
        {
          'code': 'P0001',
          'message': 'Ya existe un producto con ese tipo, variedad y calidad.',
        },
        409,
        'Ya existe',
      );
      await expectMapped(
        {'code': '42501', 'message': 'No tienes permiso para esta operación.'},
        403,
        'permiso',
      );
      await expectMapped(
        {'code': 'P0002', 'message': 'No se encontró el producto solicitado.'},
        404,
        'No se encontró',
      );
    });

    test('catalogos de certificaciones y unidades', () async {
      final paths = <String>[];
      final api = _api(token: 'jwt', (request) async {
        paths.add(request.url.path);
        return _json([
          {'id': 1, 'code': 'ORGANIC', 'name': 'Orgánico', 'is_active': true},
        ]);
      });
      expect(
        ((await api.get('/certifications')) as Map)['items'],
        hasLength(1),
      );
      expect(((await api.get('/units')) as Map)['items'], hasLength(1));
      expect(paths, ['/rest/v1/certification', '/rest/v1/unit_of_measure']);
    });
  });
}
