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
import 'package:riexport_app/features/auth/state/auth_session.dart';
import 'package:riexport_app/features/suppliers/presentation/supplier_form_screen.dart';
import 'package:riexport_app/features/suppliers/presentation/supplier_list_screen.dart';

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

const _row = {
  'id': 3,
  'business_name': 'Finca La Esperanza SAS',
  'tax_id': '900.123.456-7',
  'contact_name': 'Ana Ruiz',
  'phone': '+57 300 123 4567',
  'email': 'ana@esperanza.co',
  'location': 'Huila, Colombia',
  'is_active': true,
};

Map<String, Object?> _page(List<Map<String, Object?>> items, {int? total}) => {
  'items': items,
  'pagination': {'total': total ?? items.length, 'limit': 20, 'offset': 0},
};

Map<String, Object?> _supplier({
  int id = 1,
  String name = 'Finca La Esperanza SAS',
  bool active = true,
}) => {
  'id': id,
  'business_name': name,
  'tax_id': '900.123.456-7',
  'contact_name': 'Ana Ruiz',
  'phone': '+57 300 123 4567',
  'email': 'ana@esperanza.co',
  'location': 'Huila',
  'is_active': active,
};

void main() {
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

    Map<String, Object?> proveedor({Map<String, Object?> extra = const {}}) => {
      'business_name': '  Finca La Esperanza SAS ',
      'tax_id': '900.123.456-7',
      ...extra,
    };

    test('registra, consulta y limpia los datos', () async {
      final created =
          await api.post(
                '/suppliers',
                body: proveedor(
                  extra: {
                    'email': 'ANA@Esperanza.CO',
                    'phone': '+57 300 123 4567',
                  },
                ),
              )
              as Map<String, dynamic>;
      expect(created['business_name'], 'Finca La Esperanza SAS');
      expect(created['email'], 'ana@esperanza.co');
      expect(created['is_active'], true);
      expect(created['contact_name'], isNull);

      final one = await api.get('/suppliers/${created['id']}') as Map;
      expect(one['tax_id'], '900.123.456-7');
      final page = await api.get('/suppliers') as Map;
      expect((page['pagination'] as Map)['total'], 1);
    });

    test('valida los campos con los mensajes de la base', () async {
      Future<void> bad(Map<String, Object?> body, String message) =>
          expectLater(
            api.post('/suppliers', body: body),
            throwsA(_status(422, message)),
          );
      await bad({'tax_id': '123456'}, 'La razón social es obligatoria.');
      await bad({
        'business_name': '  ',
        'tax_id': '123456',
      }, 'La razón social es obligatoria.');
      await bad({
        'business_name': 'A',
      }, 'El documento tributario es obligatorio.');
      await bad({
        'business_name': 'A',
        'tax_id': '@@',
      }, 'no tiene un formato válido');
      await bad({
        'business_name': 'A',
        'tax_id': '123456',
        'phone': 'abc',
      }, 'El teléfono no tiene un formato válido');
      await bad({
        'business_name': 'A',
        'tax_id': '123456',
        'email': 'x',
      }, 'El correo no tiene un formato válido');
      await bad({'business_name': 'x' * 161, 'tax_id': '123456'}, 'máximo 160');
      await bad({
        'business_name': 'A',
        'tax_id': '123456',
        'is_active': false,
      }, 'Campo no permitido');
      await bad({'business_name': 5, 'tax_id': '123456'}, 'debe ser texto');
      final page = await api.get('/suppliers') as Map;
      expect(
        (page['pagination'] as Map)['total'],
        0,
        reason: 'nada se guarda a medias',
      );
    });

    test(
      'el documento es unico sin distinguir mayusculas, tambien al editar',
      () async {
        await api.post(
          '/suppliers',
          body: {'business_name': 'A', 'tax_id': 'NIT-2002'},
        );
        await expectLater(
          api.post(
            '/suppliers',
            body: {'business_name': 'B', 'tax_id': 'nit-2002'},
          ),
          throwsA(
            _status(
              409,
              'Ya existe un proveedor con ese documento tributario.',
            ),
          ),
        );
        final other =
            await api.post(
                  '/suppliers',
                  body: {'business_name': 'B', 'tax_id': 'NIT-3003'},
                )
                as Map;
        await expectLater(
          api.patch('/suppliers/${other['id']}', body: {'tax_id': 'Nit-2002'}),
          throwsA(_status(409)),
        );
        // Conservar el propio documento no es un duplicado.
        await api.patch(
          '/suppliers/${other['id']}',
          body: {'tax_id': 'NIT-3003', 'location': 'Tumaco'},
        );
      },
    );

    test('edita solo lo enviado y un opcional vacio queda nulo', () async {
      final created =
          await api.post(
                '/suppliers',
                body: proveedor(extra: {'location': 'Huila'}),
              )
              as Map;
      final id = created['id'];
      final updated =
          await api.patch(
                '/suppliers/$id',
                body: {'contact_name': 'Luis Mora', 'location': ''},
              )
              as Map;
      expect(updated['contact_name'], 'Luis Mora');
      expect(updated['location'], isNull);
      expect(updated['business_name'], 'Finca La Esperanza SAS');
      await expectLater(
        api.patch('/suppliers/$id', body: {}),
        throwsA(_status(422)),
      );
      await expectLater(
        api.patch('/suppliers/$id', body: {'business_name': ''}),
        throwsA(_status(422, 'obligatoria')),
      );
      await expectLater(
        api.patch('/suppliers/$id', body: {'is_active': false}),
        throwsA(_status(422, 'Campo no permitido')),
      );
      await expectLater(
        api.patch('/suppliers/999', body: {'phone': '3001234'}),
        throwsA(_status(404)),
      );
    });

    test(
      'inactivar conserva el proveedor y sus datos; reactivar lo devuelve',
      () async {
        final created =
            await api.post(
                  '/suppliers',
                  body: proveedor(extra: {'contact_name': 'Ana'}),
                )
                as Map;
        final id = created['id'];
        final off =
            await api.patch('/suppliers/$id/status', body: {'is_active': false})
                as Map;
        expect(off['is_active'], false);
        expect(off['contact_name'], 'Ana');
        expect(
          ((await api.get('/suppliers', queryParameters: {'is_active': 'true'}))
              as Map)['items'],
          isEmpty,
        );
        expect(
          (((await api.get(
                        '/suppliers',
                        queryParameters: {'is_active': 'false'},
                      ))
                      as Map)['items']
                  as List)
              .length,
          1,
        );
        expect(
          ((await api.get('/suppliers/$id')) as Map)['business_name'],
          'Finca La Esperanza SAS',
        );
        final on =
            await api.patch('/suppliers/$id/status', body: {'is_active': true})
                as Map;
        expect(on['is_active'], true);
        await expectLater(
          api.patch('/suppliers/$id/status', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/suppliers/999/status', body: {'is_active': false}),
          throwsA(_status(404)),
        );
      },
    );

    test('no existe el borrado de proveedores', () async {
      final created = await api.post('/suppliers', body: proveedor()) as Map;
      await expectLater(
        api.delete('/suppliers/${created['id']}'),
        throwsA(_status(404)),
      );
      expect(((await api.get('/suppliers')) as Map)['items'], hasLength(1));
    });

    test('busqueda por razon social o documento, orden y paginacion', () async {
      for (final (name, tax) in [
        ('Zeta Cacao', 'NIT-0003'),
        ('Alfa Cafe', 'NIT-0001'),
        ('Beta Cafe', 'NIT-0002'),
      ]) {
        await api.post(
          '/suppliers',
          body: {'business_name': name, 'tax_id': tax},
        );
      }
      List names(Object? page) => [
        for (final i in (page as Map)['items'] as List) i['business_name'],
      ];
      expect(names(await api.get('/suppliers')), [
        'Alfa Cafe',
        'Beta Cafe',
        'Zeta Cacao',
      ]);
      expect(
        names(await api.get('/suppliers', queryParameters: {'q': 'cafe'})),
        ['Alfa Cafe', 'Beta Cafe'],
      );
      expect(
        names(await api.get('/suppliers', queryParameters: {'q': 'nit-0003'})),
        ['Zeta Cacao'],
      );
      final second =
          await api.get(
                '/suppliers',
                queryParameters: {'limit': '2', 'offset': '2'},
              )
              as Map;
      expect(names(second), ['Zeta Cacao']);
      expect((second['pagination'] as Map)['total'], 3);
    });

    test('exige sesion y permisos suppliers.*', () async {
      final saved = token;
      token = null;
      await expectLater(api.get('/suppliers'), throwsA(_status(401)));
      // Un usuario registrado (rol cliente) no tiene permisos de proveedores.
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
      await expectLater(api.get('/suppliers'), throwsA(_status(403)));
      await expectLater(
        api.post('/suppliers', body: proveedor()),
        throwsA(_status(403)),
      );
      await expectLater(
        api.patch('/suppliers/1', body: {'phone': '3001234'}),
        throwsA(_status(403)),
      );
      await expectLater(
        api.patch('/suppliers/1/status', body: {'is_active': false}),
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
      'el listado lee la tabla con filtros, busqueda segura y total',
      () async {
        late Uri url;
        final api = client((request) async {
          url = request.url;
          expect(request.headers['Prefer'], 'count=exact');
          return _json([_row], 200, {'content-range': '0-0/7'});
        });
        final page =
            await api.get(
                  '/suppliers',
                  queryParameters: {
                    'limit': '20',
                    'offset': '20',
                    'is_active': 'true',
                    'q': 'fin,(x)*',
                  },
                )
                as Map;
        expect((page['pagination'] as Map)['total'], 7);
        expect(url.path, '/rest/v1/supplier');
        expect(url.queryParameters['is_active'], 'eq.true');
        expect(url.queryParameters['offset'], '20');
        expect(url.queryParameters['or'], isNot(contains(',(')));
        expect(url.queryParameters['or'], isNot(contains('*x')));
        expect(url.queryParameters['select'], contains('business_name'));
      },
    );

    test('registrar usa la funcion atomica y devuelve la fila', () async {
      final calls = <String>[];
      final api = client((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/rpc/create_supplier') {
          expect(jsonDecode(request.body), {
            'p': {'business_name': 'Finca', 'tax_id': '123456'},
          });
          return _json(3);
        }
        expect(request.url.queryParameters['id'], 'eq.3');
        return _json([_row]);
      });
      final created =
          await api.post(
                '/suppliers',
                body: {'business_name': 'Finca', 'tax_id': '123456'},
              )
              as Map;
      expect(created['id'], 3);
      expect(calls, [
        'POST /rest/v1/rpc/create_supplier',
        'GET /rest/v1/supplier',
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
          return _json([_row]);
        });
        await api.patch('/suppliers/3', body: {'phone': '3001234'});
        await api.patch('/suppliers/3/status', body: {'is_active': false});
        expect(bodies['/rest/v1/rpc/update_supplier'], {
          'p_id': 3,
          'p': {'phone': '3001234'},
        });
        expect(bodies['/rest/v1/rpc/set_supplier_active'], {
          'p_id': 3,
          'p_active': false,
        });
        await expectLater(
          api.patch('/suppliers/3', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/suppliers/3/status', body: {}),
          throwsA(_status(422)),
        );
      },
    );

    test(
      'un proveedor oculto o inexistente responde 404 y los errores de la base se traducen',
      () async {
        await expectLater(
          client((_) async => _json([])).get('/suppliers/9'),
          throwsA(_status(404)),
        );
        Future<void> mapped(
          Map<String, Object?> error,
          int status,
          String message,
        ) => expectLater(
          client(
            (_) async => _json(error, 400),
          ).post('/suppliers', body: {'business_name': 'A'}),
          throwsA(_status(status, message)),
        );
        await mapped(
          {'code': '22023', 'message': 'La razón social es obligatoria.'},
          422,
          'obligatoria',
        );
        await mapped(
          {
            'code': 'P0001',
            'message': 'Ya existe un proveedor con ese documento tributario.',
          },
          409,
          'Ya existe',
        );
        await mapped(
          {
            'code': '42501',
            'message': 'No tienes permiso para esta operación.',
          },
          403,
          'permiso',
        );
      },
    );
  });

  group('pantallas', () {
    Widget list({
      required LoadSuppliers loadSuppliers,
      Set<String> permissions = const {
        'suppliers.read',
        'suppliers.create',
        'suppliers.update',
      },
      Future<void> Function(int, bool)? setActive,
      Future<bool> Function(Map<String, dynamic>?)? openForm,
    }) => MaterialApp(
      home: SupplierListScreen(
        loadSuppliers: loadSuppliers,
        loadPermissions: () async => permissions,
        setActive: setActive,
        openForm: openForm,
      ),
    );

    testWidgets(
      'lista los proveedores y oculta las acciones sin permisos de escritura',
      (tester) async {
        await tester.pumpWidget(
          list(
            permissions: const {'suppliers.read'},
            loadSuppliers:
                ({required limit, required offset, query, isActive}) async =>
                    _page([
                      _supplier(),
                      _supplier(id: 2, name: 'Cacao del Sur', active: false),
                    ]),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Finca La Esperanza SAS'), findsOneWidget);
        expect(find.textContaining('NIT 900.123.456-7'), findsWidgets);
        expect(find.text('Inactivo'), findsOneWidget);
        expect(find.byTooltip('Registrar proveedor'), findsNothing);
        expect(find.byTooltip('Acciones del proveedor'), findsNothing);
      },
    );

    testWidgets(
      'estado vacio, filtro por defecto en activos y error con reintento',
      (tester) async {
        bool? seen;
        var fail = true;
        await tester.pumpWidget(
          list(
            loadSuppliers:
                ({required limit, required offset, query, isActive}) async {
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
        expect(find.text('Aún no hay proveedores registrados'), findsOneWidget);
      },
    );

    testWidgets('inactivar pide confirmacion y no inactiva si se cancela', (
      tester,
    ) async {
      final calls = <(int, bool)>[];
      await tester.pumpWidget(
        list(
          loadSuppliers:
              ({required limit, required offset, query, isActive}) async =>
                  _page([_supplier(id: 4)]),
          setActive: (id, active) async => calls.add((id, active)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones del proveedor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(find.byTooltip('Acciones del proveedor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(calls, [(4, false)]);
      expect(find.text('Proveedor inactivado.'), findsOneWidget);
    });

    testWidgets(
      'reactivar no pide confirmacion y un error se muestra sin cerrar',
      (tester) async {
        final calls = <(int, bool)>[];
        var fail = false;
        await tester.pumpWidget(
          list(
            loadSuppliers:
                ({required limit, required offset, query, isActive}) async =>
                    _page([_supplier(id: 4, active: false)]),
            setActive: (id, active) async {
              if (fail) {
                throw const ApiException(
                  statusCode: 404,
                  code: 'NOT_FOUND',
                  message: 'No se encontró el proveedor solicitado.',
                );
              }
              calls.add((id, active));
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Acciones del proveedor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reactivar'));
        await tester.pumpAndSettle();
        expect(calls, [(4, true)]);
        expect(find.text('Proveedor reactivado.'), findsOneWidget);

        fail = true;
        await tester.tap(find.byTooltip('Acciones del proveedor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reactivar'));
        await tester.pumpAndSettle();
        expect(
          find.text('No se encontró el proveedor solicitado.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('registrar abre el formulario y recarga al guardar', (
      tester,
    ) async {
      var loads = 0;
      Map<String, dynamic>? opened = {'sentinel': true};
      await tester.pumpWidget(
        list(
          loadSuppliers:
              ({required limit, required offset, query, isActive}) async {
                loads++;
                return _page([]);
              },
          openForm: (supplier) async {
            opened = supplier;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registrar proveedor'));
      await tester.pumpAndSettle();
      expect(opened, isNull);
      expect(loads, 2);
      expect(find.text('Proveedor registrado.'), findsOneWidget);
    });

    Widget form({
      Map<String, dynamic>? supplier,
      required SaveSupplier onSave,
    }) => MaterialApp(
      home: SupplierFormScreen(supplier: supplier, onSave: onSave),
    );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('el formulario valida y envia solo lo informado', (
      tester,
    ) async {
      tall(tester);
      Map<String, Object?>? sent;
      await tester.pumpWidget(form(onSave: (fields) async => sent = fields));
      final fields = find.byType(TextFormField);

      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.text('La razón social es obligatoria.'), findsOneWidget);
      expect(
        find.text('El documento tributario es obligatorio.'),
        findsOneWidget,
      );
      expect(sent, isNull);

      await tester.enterText(fields.at(0), ' Cacao del Sur ');
      await tester.enterText(fields.at(1), '@@');
      await tester.enterText(fields.at(3), 'abc');
      await tester.enterText(fields.at(4), 'sin-arroba');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(
        find.text('El documento tributario no tiene un formato válido.'),
        findsOneWidget,
      );
      expect(
        find.text('El teléfono no tiene un formato válido.'),
        findsOneWidget,
      );
      expect(
        find.text('El correo no tiene un formato válido.'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(1), 'NIT-2002');
      await tester.enterText(fields.at(3), '');
      await tester.enterText(fields.at(4), 'Ana@Sur.CO');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(sent, {
        'business_name': 'Cacao del Sur',
        'tax_id': 'NIT-2002',
        'email': 'ana@sur.co',
      });
    });

    testWidgets(
      'en edicion solo se envia lo modificado y vaciar un opcional envia null',
      (tester) async {
        tall(tester);
        Map<String, Object?>? sent;
        await tester.pumpWidget(
          form(supplier: _supplier(), onSave: (fields) async => sent = fields),
        );
        expect(find.text('Editar proveedor'), findsOneWidget);
        final fields = find.byType(TextFormField);
        expect(
          tester.widget<TextFormField>(fields.at(0)).controller?.text,
          'Finca La Esperanza SAS',
        );
        await tester.enterText(fields.at(2), 'Luis Mora');
        await tester.enterText(fields.at(5), '');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(sent, {'contact_name': 'Luis Mora', 'location': null});
      },
    );

    testWidgets('en edicion sin cambios no llama al backend', (tester) async {
      tall(tester);
      var calls = 0;
      await tester.pumpWidget(
        form(supplier: _supplier(), onSave: (fields) async => calls++),
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('un error del servidor se muestra sin cerrar la pantalla', (
      tester,
    ) async {
      tall(tester);
      var calls = 0;
      await tester.pumpWidget(
        form(
          supplier: _supplier(),
          onSave: (fields) async {
            calls++;
            throw const ApiException(
              statusCode: 409,
              code: 'CONFLICT',
              message: 'Ya existe un proveedor con ese documento tributario.',
            );
          },
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'NIT-9999');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text('Ya existe un proveedor con ese documento tributario.'),
        findsOneWidget,
      );
      expect(find.text('Guardar'), findsOneWidget);
    });
  });

  testWidgets(
    'recorrido completo: registrar, duplicado, editar, inactivar y reactivar',
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

      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay proveedores registrados'), findsOneWidget);

      await tester.tap(find.byTooltip('Registrar proveedor'));
      await tester.pumpAndSettle();
      var form = find.byType(TextFormField);
      await tester.enterText(form.at(0), 'Finca La Esperanza');
      await tester.enterText(form.at(1), '900.123.456-7');
      await tester.enterText(form.at(2), 'Ana Ruiz');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Proveedor registrado.'), findsOneWidget);
      expect(find.text('Finca La Esperanza'), findsOneWidget);

      // Un documento repetido se rechaza con el mensaje de la regla.
      await tester.tap(find.byTooltip('Registrar proveedor'));
      await tester.pumpAndSettle();
      form = find.byType(TextFormField);
      await tester.enterText(form.at(0), 'Otra finca');
      await tester.enterText(form.at(1), '900.123.456-7');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ya existe un proveedor con ese documento tributario.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Volver a proveedores'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Acciones del proveedor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar proveedor'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Finca La Esperanza SAS',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Proveedor actualizado.'), findsOneWidget);
      expect(find.text('Finca La Esperanza SAS'), findsOneWidget);

      await tester.tap(find.byTooltip('Acciones del proveedor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(find.text('Proveedor inactivado.'), findsOneWidget);
      expect(find.text('Aún no hay proveedores registrados'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivos').last);
      await tester.pumpAndSettle();
      expect(find.text('Finca La Esperanza SAS'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);

      await tester.tap(find.byTooltip('Acciones del proveedor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(find.text('Proveedor reactivado.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
