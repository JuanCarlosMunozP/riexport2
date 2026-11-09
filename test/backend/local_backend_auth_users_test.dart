import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import '../support/local_backend_test_context.dart';

void main() {
  setUp(setUpLocalBackendTest);

  test('rechaza credenciales incorrectas y peticiones sin token', () async {
    token = null;
    await expectLater(
      api.get('/users'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    await expectLater(
      api.post('/auth/login', body: {'email': 'x@y.co', 'password': 'no'}),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
  });

  test(
    'aplica perfiles de minimo privilegio y protege todos los permisos admin',
    () async {
      final roles =
          ((await api.get('/roles') as Map<String, dynamic>)['items'] as List)
              .cast<Map<String, dynamic>>();
      final permissions =
          ((await api.get('/roles/permissions')
                      as Map<String, dynamic>)['items']
                  as List)
              .cast<Map<String, dynamic>>()
              .map((permission) => permission['code'] as String)
              .toSet();
      final byName = {for (final role in roles) role['name'] as String: role};
      Set<String> codes(String name) =>
          (byName[name]!['permission_codes'] as List).cast<String>().toSet();

      expect(codes('administrador'), permissions);
      expect(codes('usuario_comercial'), {
        'customers.read',
        'customers.create',
        'customers.update',
        'orders.read',
        'orders.create',
        'orders.update',
        'orders.transition',
        'exports.read',
        'exports.create',
        'exports.update',
        'documents.read',
        'documents.upload',
        'documents.generate',
        'inventory.read',
        'payments.read',
        'payments.create',
        'logistics.read',
      });
      expect(codes('encargado_logistico'), {
        'customers.read',
        'orders.read',
        'exports.read',
        'documents.read',
        'inventory.read',
        'inventory.adjust',
        'logistics.read',
        'logistics.create',
        'logistics.update',
      });
      expect(codes('cliente'), {'portal.read'});
      await expectLater(
        api.put('/roles/1/permissions', body: {'permission_codes': <String>[]}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
    },
  );

  test('registra, lista, edita y desactiva usuarios', () async {
    await api.post(
      '/users',
      body: {
        'email': 'Ana@Correo.com',
        'password': 'secreto',
        'first_name': 'Ana',
        'last_name': 'Ruiz',
        'role_id': 2,
      },
    );
    await expectLater(
      api.post(
        '/users',
        body: {
          'email': 'ana@correo.com',
          'password': 'x',
          'first_name': 'A',
          'last_name': 'B',
          'role_id': 2,
        },
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );

    final page =
        await api.get('/users', queryParameters: {'q': 'ana', 'limit': '20'})
            as Map<String, dynamic>;
    expect((page['pagination'] as Map)['total'], 1);
    final user = (page['items'] as List).single as Map<String, dynamic>;
    expect(user['email'], 'ana@correo.com');
    expect(jsonEncode(user), isNot(contains('secreto')));

    await api.patch('/users/${user['id']}', body: {'first_name': 'Anita'});
    await api.patch('/users/${user['id']}/deactivate');
    final inactive =
        await api.get('/users', queryParameters: {'is_active': 'false'})
            as Map<String, dynamic>;
    expect((inactive['items'] as List).single['first_name'], 'Anita');
  });

  test('protege al administrador y gestiona roles', () async {
    await expectLater(
      api.patch('/users/1/deactivate'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
    final role =
        await api.post('/roles', body: {'name': 'Supervisor Logistico'})
            as Map<String, dynamic>;
    expect(role['name'], 'supervisor_logistico');
    final updated =
        await api.put(
              '/roles/${role['id']}/permissions',
              body: {
                'permission_codes': ['users.read'],
              },
            )
            as Map<String, dynamic>;
    expect(updated['permission_codes'], ['users.read']);
    await expectLater(
      api.put('/roles/1/permissions', body: {'permission_codes': <String>[]}),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test(
    'el registro público no requiere sesión y asigna el rol cliente',
    () async {
      token = null;
      final created =
          await api.post(
                '/auth/register',
                body: {
                  'email': 'luz@correo.com',
                  'password': 'secreto',
                  'first_name': 'Luz',
                  'last_name': 'Mora',
                  'role_id': 1,
                },
              )
              as Map<String, dynamic>;
      expect(created['role_id'], 4);

      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'luz@correo.com', 'password': 'secreto'},
              )
              as Map<String, dynamic>;
      expect(login['access_token'], isNotEmpty);
    },
  );

  test(
    'el titular cambia su correo y el administrador no puede cambiar el de otros',
    () async {
      final me = await api.get('/me') as Map<String, dynamic>;
      expect(me['email'], 'admin@riexport.com');

      await api.patch('/me', body: {'email': 'nuevo@riexport.com'});
      expect(
        ((await api.get('/me')) as Map<String, dynamic>)['email'],
        'nuevo@riexport.com',
      );
      await expectLater(
        api.patch('/me', body: {'email': 'nuevo@riexport.com'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );
      await expectLater(
        api.patch('/users/1', body: {'email': 'otro@riexport.com'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );
    },
  );

  test(
    'el titular edita sus datos personales pero no su rol ni su estado',
    () async {
      final row =
          await api.patch(
                '/me',
                body: {
                  'first_name': 'Admin',
                  'last_name': 'Nuevo',
                  'phone': ' 300 ',
                },
              )
              as Map<String, dynamic>;
      expect(row['last_name'], 'Nuevo');
      expect(row['phone'], '300');

      for (final body in <Map<String, Object?>>[
        {'role_id': 2},
        {'is_active': false},
        {'first_name': ''},
      ]) {
        await expectLater(
          api.patch('/me', body: body),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 422),
          ),
        );
      }
      final me = await api.get('/me') as Map<String, dynamic>;
      expect(me['permission_codes'], contains('users.assign_role'));
    },
  );

  test(
    'un usuario desactivado no inicia sesion y su token deja de valer',
    () async {
      final created =
          await api.post(
                '/auth/register',
                body: {
                  'email': 'baja@correo.com',
                  'password': 'secreto1',
                  'first_name': 'Baja',
                  'last_name': 'Prueba',
                },
              )
              as Map<String, dynamic>;
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'baja@correo.com', 'password': 'secreto1'},
              )
              as Map<String, dynamic>;
      final tokenBaja = login['access_token'] as String;

      await api.patch('/users/${created['id']}/deactivate');

      await expectLater(
        api.post(
          '/auth/login',
          body: {'email': 'baja@correo.com', 'password': 'secreto1'},
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      token = tokenBaja; // la sesion que ya tenia
      await expectLater(
        api.get('/me'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    },
  );

  test('cerrar sesion es valido con o sin token', () async {
    expect(await api.post('/auth/logout'), isNull);
    token = null;
    expect(await api.post('/auth/logout'), isNull);
  });

  test(
    'el listado de usuarios incluye el nombre del rol y filtra por texto',
    () async {
      await api.post(
        '/auth/register',
        body: {
          'email': 'buscar@correo.com',
          'password': 'secreto1',
          'first_name': 'Beatriz',
          'last_name': 'Quintero',
        },
      );
      final page =
          await api.get('/users', queryParameters: {'q': 'quinte'})
              as Map<String, dynamic>;
      final item = (page['items'] as List).single as Map<String, dynamic>;
      expect(item['role_name'], 'cliente');
      expect((page['pagination'] as Map)['total'], 1);

      final admin =
          await api.get('/users', queryParameters: {'q': 'admin@riexport'})
              as Map<String, dynamic>;
      expect((admin['items'] as List).single['role_name'], 'administrador');
    },
  );

  test(
    'cambio de rol: nunca el propio, y el rol administrador solo lo gestiona un administrador',
    () async {
      // El administrador (id 1) no cambia su propio rol.
      await expectLater(
        api.patch('/users/1', body: {'role_id': 2}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', contains('propio rol')),
        ),
      );

      // Un usuario nuevo (rol cliente, sin users.assign_role) no cambia roles.
      final created =
          await api.post(
                '/auth/register',
                body: {
                  'email': 'otro@correo.com',
                  'password': 'secreto1',
                  'first_name': 'Otro',
                  'last_name': 'Usuario',
                },
              )
              as Map<String, dynamic>;
      final adminToken = token;
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'otro@correo.com', 'password': 'secreto1'},
              )
              as Map<String, dynamic>;
      token = login['access_token'] as String;
      await expectLater(
        api.patch('/users/1', body: {'role_id': 2}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );

      // El administrador sí cambia el rol de otro, y puede promover a administrador.
      token = adminToken;
      final updated =
          await api.patch('/users/${created['id']}', body: {'role_id': 2})
              as Map<String, dynamic>;
      expect(updated['role_id'], 2);
      final promoted =
          await api.patch('/users/${created['id']}', body: {'role_id': 1})
              as Map<String, dynamic>;
      expect(promoted['role_id'], 1);
    },
  );

  test(
    'recuperacion de acceso: codigo de un solo uso y contrasena nueva',
    () async {
      token = null;
      final request =
          await api.post(
                '/auth/password-reset-requests',
                body: {'email': 'admin@riexport.com'},
              )
              as Map<String, dynamic>;
      final code = request['dev_code'] as String;
      expect(code, matches(RegExp(r'^[0-9]{6}$')));

      // Un correo que no existe recibe la misma respuesta, sin código.
      final unknown =
          await api.post(
                '/auth/password-reset-requests',
                body: {'email': 'nadie@correo.com'},
              )
              as Map<String, dynamic>;
      expect(unknown['message'], request['message']);
      expect(unknown.containsKey('dev_code'), isFalse);

      // Código equivocado, contraseña repetida y contraseña vacía.
      await expectLater(
        api.post(
          '/auth/password-resets',
          body: {
            'email': 'admin@riexport.com',
            'code': '000000',
            'new_password': 'Nueva-2026',
          },
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_CODE'),
        ),
      );
      await expectLater(
        api.post(
          '/auth/password-resets',
          body: {
            'email': 'admin@riexport.com',
            'code': code,
            'new_password': 'Admin123!',
          },
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );

      await api.post(
        '/auth/password-resets',
        body: {
          'email': 'admin@riexport.com',
          'code': code,
          'new_password': 'Nueva-2026',
        },
      );

      // La contraseña anterior ya no sirve, la nueva sí, y el código no se reutiliza.
      await expectLater(
        api.post(
          '/auth/login',
          body: {'email': 'admin@riexport.com', 'password': 'Admin123!'},
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'admin@riexport.com', 'password': 'Nueva-2026'},
              )
              as Map<String, dynamic>;
      expect(login['access_token'], isNotEmpty);
      await expectLater(
        api.post(
          '/auth/password-resets',
          body: {
            'email': 'admin@riexport.com',
            'code': code,
            'new_password': 'Otra-2026',
          },
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_CODE'),
        ),
      );
    },
  );

  test('un usuario desactivado no recibe codigo de recuperacion', () async {
    await api.post(
      '/auth/register',
      body: {
        'email': 'baja2@correo.com',
        'password': 'secreto1',
        'first_name': 'Baja',
        'last_name': 'Dos',
      },
    );
    final users =
        await api.get('/users', queryParameters: {'q': 'baja2'})
            as Map<String, dynamic>;
    await api.patch(
      '/users/${(users['items'] as List).single['id']}/deactivate',
    );
    token = null;
    final result =
        await api.post(
              '/auth/password-reset-requests',
              body: {'email': 'baja2@correo.com'},
            )
            as Map<String, dynamic>;
    expect(result.containsKey('dev_code'), isFalse);
  });

  test(
    'un usuario desactivado se reactiva y vuelve a iniciar sesion',
    () async {
      final created =
          await api.post(
                '/auth/register',
                body: {
                  'email': 'vuelve@correo.com',
                  'password': 'secreto1',
                  'first_name': 'Vuelve',
                  'last_name': 'Pronto',
                },
              )
              as Map<String, dynamic>;
      await api.patch('/users/${created['id']}/deactivate');
      await expectLater(
        api.post(
          '/auth/login',
          body: {'email': 'vuelve@correo.com', 'password': 'secreto1'},
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      final back =
          await api.patch('/users/${created['id']}/activate')
              as Map<String, dynamic>;
      expect(back['is_active'], isTrue);
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'vuelve@correo.com', 'password': 'secreto1'},
              )
              as Map<String, dynamic>;
      expect(login['access_token'], isNotEmpty);
    },
  );
}
