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
import 'package:riexport_app/features/farms/presentation/farm_form_screen.dart';
import 'package:riexport_app/features/farms/presentation/farm_list_screen.dart';
import 'package:riexport_app/features/farms/presentation/lot_screens.dart';

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

Map<String, Object?> _farm({
  int id = 1,
  String name = 'La Esperanza',
  bool active = true,
  Object? lat = 2.535,
  Object? lon = -75.527,
}) => {
  'id': id,
  'supplier_id': 1,
  'supplier_name': 'Proveedor Uno',
  'country_code': 'CO',
  'name': name,
  'address': 'Vereda Alta',
  'latitude': lat,
  'longitude': lon,
  'is_active': active,
  'lot_count': 2,
};

void main() {
  group('backend local', () {
    late ApiClient api;
    late String? token;
    late int supplier;
    late int product;

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
      supplier =
          (await api.post(
                    '/suppliers',
                    body: {
                      'business_name': 'Proveedor Uno',
                      'tax_id': 'NIT-0001',
                    },
                  )
                  as Map)['id']
              as int;
      product =
          (await api.post(
                    '/products',
                    body: {
                      'type': 'coffee',
                      'base_unit_code': 'kg',
                      'variety': 'Caturra',
                      'quality_grade': 'Excelso',
                      'humidity_percent': 11,
                    },
                  )
                  as Map)['id']
              as int;
    });

    Map<String, Object?> finca([Map<String, Object?> extra = const {}]) => {
      'supplier_id': supplier,
      'country_code': 'co',
      'name': '  La Esperanza ',
      ...extra,
    };

    Future<void> bad(Map<String, Object?> body, String message) => expectLater(
      api.post('/farms', body: body),
      throwsA(_status(422, message)),
    );

    test('registra una finca con coordenadas y la devuelve limpia', () async {
      final created =
          await api.post(
                '/farms',
                body: finca({'latitude': 2.535, 'longitude': '-75,527'}),
              )
              as Map;
      expect(created['name'], 'La Esperanza');
      expect(created['country_code'], 'CO');
      expect(created['latitude'], 2.535);
      expect(created['longitude'], -75.527);
      expect(created['supplier_name'], 'Proveedor Uno');
      expect(created['lot_count'], 0);
      expect(
        ((await api.get('/farms/${created['id']}')) as Map)['name'],
        'La Esperanza',
      );
    });

    test('una finca puede registrarse sin geolocalizacion', () async {
      final created = await api.post('/farms', body: finca()) as Map;
      expect(created['latitude'], isNull);
      expect(created['longitude'], isNull);
    });

    test(
      'valida las coordenadas: rango, par completo, (0, 0) y decimales',
      () async {
        await bad(
          finca({'latitude': 90.5, 'longitude': 10}),
          'La latitud debe estar entre -90 y 90.',
        );
        await bad(
          finca({'latitude': -91, 'longitude': 10}),
          'La latitud debe estar entre',
        );
        await bad(
          finca({'latitude': 10, 'longitude': 180.1}),
          'La longitud debe estar entre -180 y 180.',
        );
        await bad(
          finca({'latitude': 10, 'longitude': -181}),
          'La longitud debe estar entre',
        );
        await bad(finca({'latitude': 10}), 'juntas, o ninguna');
        await bad(finca({'longitude': 10}), 'juntas, o ninguna');
        await bad(finca({'latitude': 0, 'longitude': 0}), '(0, 0)');
        await bad(
          finca({'latitude': 2.1234567, 'longitude': 10}),
          'máximo 6 decimales',
        );
        await bad(finca({'latitude': 'abc', 'longitude': 10}), 'número válido');
        await bad(
          finca({'latitude': true, 'longitude': 10}),
          'debe ser un número',
        );
        expect(
          ((await api.get('/farms')) as Map)['items'],
          isEmpty,
          reason: 'nada se guarda a medias',
        );
        // Los limites exactos y los 6 decimales son validos.
        await api.post(
          '/farms',
          body: finca({'name': 'Limite', 'latitude': 90, 'longitude': -180}),
        );
        await api.post(
          '/farms',
          body: finca({
            'name': 'Precisa',
            'latitude': 2.123456,
            'longitude': -75.654321,
          }),
        );
        await api.post(
          '/farms',
          body: finca({'name': 'Ecuador', 'latitude': 0, 'longitude': -78.5}),
        );
      },
    );

    test('valida proveedor, pais, nombre y campos ajenos', () async {
      await bad({
        'country_code': 'CO',
        'name': 'A',
      }, 'proveedor es obligatorio');
      await bad(finca({'supplier_id': 999}), 'proveedor no existe');
      await bad(finca({'country_code': 'Col'}), 'país');
      await bad(finca({'country_code': ''}), 'país es obligatorio');
      await bad(finca({'name': '  '}), 'nombre de la finca es obligatorio');
      await bad(finca({'is_active': false}), 'Campo no permitido');
      await bad(finca({'address': 'x' * 301}), 'máximo 300');
      await api.patch(
        '/suppliers/$supplier/status',
        body: {'is_active': false},
      );
      await bad(finca(), 'proveedor está inactivo');
    });

    test('el nombre es unico por proveedor, no entre proveedores', () async {
      await api.post('/farms', body: finca());
      await expectLater(
        api.post('/farms', body: finca({'name': 'LA ESPERANZA'})),
        throwsA(_status(409, 'ya tiene una finca con ese nombre')),
      );
      final other =
          (await api.post(
                    '/suppliers',
                    body: {'business_name': 'Dos', 'tax_id': 'NIT-0002'},
                  )
                  as Map)['id']
              as int;
      await api.post('/farms', body: finca({'supplier_id': other}));
    });

    test('edita, quita el punto y valida igual que al crear', () async {
      final created =
          await api.post(
                '/farms',
                body: finca({'latitude': 2.5, 'longitude': -75.5}),
              )
              as Map;
      final id = created['id'];
      final updated =
          await api.patch(
                '/farms/$id',
                body: {'name': 'Nueva', 'latitude': 4.5, 'longitude': -74.1},
              )
              as Map;
      expect(updated['name'], 'Nueva');
      expect(updated['latitude'], 4.5);
      final cleared =
          await api.patch(
                '/farms/$id',
                body: {'latitude': null, 'longitude': null},
              )
              as Map;
      expect(cleared['latitude'], isNull);
      expect(cleared['longitude'], isNull);

      await expectLater(
        api.patch('/farms/$id', body: {'latitude': 4.5}),
        throwsA(_status(422, 'juntas, o ninguna')),
      );
      await expectLater(
        api.patch('/farms/$id', body: {'latitude': 100, 'longitude': 10}),
        throwsA(_status(422, 'La latitud debe estar entre')),
      );
      await expectLater(
        api.patch('/farms/$id', body: {'latitude': 0, 'longitude': 0}),
        throwsA(_status(422, '(0, 0)')),
      );
      await expectLater(
        api.patch('/farms/$id', body: {'supplier_id': supplier + 1}),
        throwsA(_status(422, 'otro proveedor')),
      );
      await expectLater(
        api.patch('/farms/$id', body: {}),
        throwsA(_status(422)),
      );
      await expectLater(
        api.patch('/farms/999', body: {'name': 'X'}),
        throwsA(_status(404)),
      );
      expect(
        ((await api.get('/farms/$id')) as Map)['latitude'],
        isNull,
        reason: 'los rechazos no cambian nada',
      );
    });

    test('inactivar una finca conserva sus lotes; no hay borrado', () async {
      final farm =
          await api.post(
                '/farms',
                body: finca({'latitude': 2.5, 'longitude': -75.5}),
              )
              as Map;
      final id = farm['id'] as int;
      await api.post(
        '/lots',
        body: {'product_id': product, 'farm_id': id, 'lot_code': 'L-1'},
      );
      final off =
          await api.patch('/farms/$id/status', body: {'is_active': false})
              as Map;
      expect(off['is_active'], false);
      expect(off['lot_count'], 1);
      expect(
        ((await api.get('/farms', queryParameters: {'is_active': 'true'}))
            as Map)['items'],
        isEmpty,
      );
      expect(((await api.get('/lots')) as Map)['items'], hasLength(1));
      await expectLater(
        api.post(
          '/lots',
          body: {'product_id': product, 'farm_id': id, 'lot_code': 'L-2'},
        ),
        throwsA(_status(422, 'finca está inactiva')),
      );
      await expectLater(api.delete('/farms/$id'), throwsA(_status(404)));
      await api.patch('/farms/$id/status', body: {'is_active': true});
      await api.post(
        '/lots',
        body: {'product_id': product, 'farm_id': id, 'lot_code': 'L-2'},
      );
      await expectLater(
        api.patch('/farms/$id/status', body: {}),
        throwsA(_status(422)),
      );
    });

    test('registra lotes con la geolocalizacion de su finca', () async {
      final farm =
          await api.post(
                '/farms',
                body: finca({'latitude': 2.535, 'longitude': -75.527}),
              )
              as Map;
      final lot =
          await api.post(
                '/lots',
                body: {
                  'product_id': product,
                  'farm_id': farm['id'],
                  'lot_code': '  L-2026-01 ',
                },
              )
              as Map;
      expect(lot['lot_code'], 'L-2026-01');
      expect(lot['latitude'], 2.535);
      expect(lot['longitude'], -75.527);
      expect(lot['product_variety'], 'Caturra');
      expect(lot['farm_name'], 'La Esperanza');
      expect(lot['supplier_name'], 'Proveedor Uno');
      expect(((await api.get('/farms/${farm['id']}')) as Map)['lot_count'], 1);
      expect(
        ((await api.get('/lots/${lot['id']}')) as Map)['lot_code'],
        'L-2026-01',
      );
      expect(
        (((await api.get('/lots', queryParameters: {'q': '2026'}))
                as Map)['items']
            as List),
        hasLength(1),
      );
      expect(
        (((await api.get('/lots', queryParameters: {'q': 'zzz'}))
                as Map)['items']
            as List),
        isEmpty,
      );
    });

    test(
      'valida el lote: obligatorios, existentes, activos y codigo unico por finca',
      () async {
        final farm =
            (await api.post('/farms', body: finca()) as Map)['id'] as int;
        Future<void> badLot(
          Map<String, Object?> body,
          int status,
          String message,
        ) => expectLater(
          api.post('/lots', body: body),
          throwsA(_status(status, message)),
        );
        Map<String, Object?> lote([Map<String, Object?> extra = const {}]) => {
          'product_id': product,
          'farm_id': farm,
          'lot_code': 'L-1',
          ...extra,
        };
        await badLot(
          {'farm_id': farm, 'lot_code': 'A'},
          422,
          'producto es obligatorio',
        );
        await badLot(
          {'product_id': product, 'lot_code': 'A'},
          422,
          'finca es obligatoria',
        );
        await badLot(
          lote({'lot_code': ' '}),
          422,
          'código del lote es obligatorio',
        );
        await badLot(lote({'product_id': 999}), 422, 'producto no existe');
        await badLot(lote({'farm_id': 999}), 422, 'finca no existe');
        await badLot(lote({'latitude': 1}), 422, 'Campo no permitido');
        await api.post('/lots', body: lote());
        await badLot(
          lote({'lot_code': 'l-1'}),
          409,
          'ya tiene un lote con ese código',
        );
        await api.patch(
          '/products/$product/status',
          body: {'is_active': false},
        );
        await badLot(lote({'lot_code': 'L-9'}), 422, 'producto está inactivo');
        expect(((await api.get('/lots')) as Map)['items'], hasLength(1));
      },
    );

    test('exige sesion y permisos farms.* y lots.*', () async {
      final saved = token;
      token = null;
      await expectLater(api.get('/farms'), throwsA(_status(401)));
      await expectLater(api.get('/lots'), throwsA(_status(401)));
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
      await expectLater(api.get('/farms'), throwsA(_status(403)));
      await expectLater(
        api.post('/farms', body: finca()),
        throwsA(_status(403)),
      );
      await expectLater(
        api.patch('/farms/1', body: {'name': 'X'}),
        throwsA(_status(403)),
      );
      await expectLater(
        api.patch('/farms/1/status', body: {'is_active': false}),
        throwsA(_status(403)),
      );
      await expectLater(api.get('/lots'), throwsA(_status(403)));
      await expectLater(
        api.post(
          '/lots',
          body: {'product_id': 1, 'farm_id': 1, 'lot_code': 'A'},
        ),
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
      'el listado de fincas lee la vista con filtros, busqueda segura y total',
      () async {
        late Uri url;
        final api = client((request) async {
          url = request.url;
          expect(request.headers['Prefer'], 'count=exact');
          return _json([_farm()], 200, {'content-range': '0-0/5'});
        });
        final page =
            await api.get(
                  '/farms',
                  queryParameters: {
                    'limit': '20',
                    'offset': '20',
                    'is_active': 'true',
                    'q': 'es,(x)*',
                    'supplier_id': '3',
                  },
                )
                as Map;
        expect((page['pagination'] as Map)['total'], 5);
        expect(url.path, '/rest/v1/farm_catalog');
        expect(url.queryParameters['is_active'], 'eq.true');
        expect(url.queryParameters['supplier_id'], 'eq.3');
        expect(url.queryParameters['offset'], '20');
        expect(url.queryParameters['or'], isNot(contains(',(')));
        expect(url.queryParameters['select'], contains('latitude'));
      },
    );

    test('registrar finca usa la funcion atomica y devuelve la fila', () async {
      final calls = <String>[];
      final api = client((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/rpc/create_farm') {
          expect(jsonDecode(request.body), {
            'p': {
              'supplier_id': 1,
              'country_code': 'CO',
              'name': 'La Esperanza',
              'latitude': 2.535,
              'longitude': -75.527,
            },
          });
          return _json(4);
        }
        expect(request.url.queryParameters['id'], 'eq.4');
        return _json([_farm(id: 4)]);
      });
      final created =
          await api.post(
                '/farms',
                body: {
                  'supplier_id': 1,
                  'country_code': 'CO',
                  'name': 'La Esperanza',
                  'latitude': 2.535,
                  'longitude': -75.527,
                },
              )
              as Map;
      expect(created['id'], 4);
      expect(calls, [
        'POST /rest/v1/rpc/create_farm',
        'GET /rest/v1/farm_catalog',
      ]);
    });

    test(
      'editar e inactivar fincas llaman a sus funciones y validan la solicitud',
      () async {
        final bodies = <String, Object?>{};
        final api = client((request) async {
          if (request.method == 'POST') {
            bodies[request.url.path] = jsonDecode(request.body);
            return http.Response('', 204);
          }
          return _json([_farm()]);
        });
        await api.patch(
          '/farms/1',
          body: {'latitude': null, 'longitude': null},
        );
        await api.patch('/farms/1/status', body: {'is_active': false});
        expect(bodies['/rest/v1/rpc/update_farm'], {
          'p_id': 1,
          'p': {'latitude': null, 'longitude': null},
        });
        expect(bodies['/rest/v1/rpc/set_farm_active'], {
          'p_id': 1,
          'p_active': false,
        });
        await expectLater(
          api.patch('/farms/1', body: {}),
          throwsA(_status(422)),
        );
        await expectLater(
          api.patch('/farms/1/status', body: {}),
          throwsA(_status(422)),
        );
      },
    );

    test(
      'lotes: listado por la vista, alta por funcion y 404 si no se ve',
      () async {
        late Uri url;
        final api = client((request) async {
          if (request.url.path == '/rest/v1/rpc/create_lot') {
            expect(jsonDecode(request.body), {
              'p': {'product_id': 1, 'farm_id': 2, 'lot_code': 'L-1'},
            });
            return _json(9);
          }
          url = request.url;
          return _json(
            [
              {
                'id': 9,
                'lot_code': 'L-1',
                'farm_name': 'La Esperanza',
                'latitude': 2.5,
                'longitude': -75.5,
              },
            ],
            200,
            {'content-range': '0-0/1'},
          );
        });
        final page =
            await api.get(
                  '/lots',
                  queryParameters: {
                    'farm_id': '2',
                    'product_id': '1',
                    'q': 'L-1',
                  },
                )
                as Map;
        expect((page['pagination'] as Map)['total'], 1);
        expect(url.path, '/rest/v1/lot_catalog');
        expect(url.queryParameters['farm_id'], 'eq.2');
        expect(url.queryParameters['product_id'], 'eq.1');
        expect(url.queryParameters['lot_code'], 'ilike.*L-1*');
        final created =
            await api.post(
                  '/lots',
                  body: {'product_id': 1, 'farm_id': 2, 'lot_code': 'L-1'},
                )
                as Map;
        expect(created['id'], 9);
        await expectLater(
          client((_) async => _json([])).get('/lots/9'),
          throwsA(_status(404)),
        );
        await expectLater(
          client((_) async => _json([])).get('/farms/9'),
          throwsA(_status(404)),
        );
      },
    );

    test('traduce los errores de las funciones de la base', () async {
      Future<void> mapped(
        Map<String, Object?> error,
        int status,
        String message,
      ) => expectLater(
        client(
          (_) async => _json(error, 400),
        ).post('/farms', body: {'name': 'A'}),
        throwsA(_status(status, message)),
      );
      await mapped(
        {'code': '22023', 'message': 'La latitud debe estar entre -90 y 90.'},
        422,
        'entre -90 y 90',
      );
      await mapped(
        {
          'code': '23514',
          'message': 'violates check constraint "farm_point_complete"',
        },
        422,
        '',
      );
      await mapped(
        {
          'code': 'P0001',
          'message': 'El proveedor ya tiene una finca con ese nombre.',
        },
        409,
        'ya tiene una finca',
      );
      await mapped(
        {'code': '42501', 'message': 'No tienes permiso para esta operación.'},
        403,
        'permiso',
      );
    });
  });

  group('validacion de coordenadas en el formulario', () {
    test(
      'acepta coma decimal y rechaza rango, formato y exceso de decimales',
      () {
        expect(parseCoordinate(' 2,535 '), 2.535);
        expect(parseCoordinate(''), isNull);
        expect(validateCoordinate('', 'La latitud', 90), isNull);
        expect(validateCoordinate('2.535', 'La latitud', 90), isNull);
        expect(validateCoordinate('90', 'La latitud', 90), isNull);
        expect(validateCoordinate('-180', 'La longitud', 180), isNull);
        expect(validateCoordinate('2.123456', 'La latitud', 90), isNull);
        expect(
          validateCoordinate('90.1', 'La latitud', 90),
          'La latitud debe estar entre -90 y 90.',
        );
        expect(
          validateCoordinate('-180.5', 'La longitud', 180),
          'La longitud debe estar entre -180 y 180.',
        );
        expect(
          validateCoordinate('2.1234567', 'La latitud', 90),
          'Máximo 6 decimales.',
        );
        expect(
          validateCoordinate('abc', 'La latitud', 90),
          'Ingresa un número válido.',
        );
        expect(
          validateCoordinate('NaN', 'La latitud', 90),
          'Ingresa un número válido.',
        );
      },
    );
  });

  group('pantallas', () {
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget list({
      required LoadFarms loadFarms,
      Set<String> permissions = const {
        'farms.read',
        'farms.create',
        'farms.update',
      },
      Future<void> Function(int, bool)? setActive,
      Future<bool> Function(Map<String, dynamic>?)? openForm,
    }) => MaterialApp(
      home: FarmListScreen(
        loadFarms: loadFarms,
        loadPermissions: () async => permissions,
        setActive: setActive,
        openForm: openForm,
      ),
    );

    testWidgets(
      'lista fincas con su geolocalizacion y sin acciones si solo lee',
      (tester) async {
        await tester.pumpWidget(
          list(
            permissions: const {'farms.read'},
            loadFarms:
                ({required limit, required offset, query, isActive}) async =>
                    _page([
                      _farm(),
                      _farm(id: 2, name: 'Sin punto', lat: null, lon: null),
                    ]),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('La Esperanza'), findsOneWidget);
        expect(find.text('2.535000, -75.527000'), findsOneWidget);
        expect(find.text('Sin geolocalización'), findsOneWidget);
        expect(find.textContaining('2 lotes'), findsWidgets);
        expect(find.byTooltip('Registrar finca'), findsNothing);
        expect(find.byTooltip('Acciones de la finca'), findsNothing);
      },
    );

    testWidgets('vacio, filtro por defecto en activas y error con reintento', (
      tester,
    ) async {
      bool? seen;
      var fail = true;
      await tester.pumpWidget(
        list(
          loadFarms:
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
      expect(find.text('Aún no hay fincas registradas'), findsOneWidget);
    });

    testWidgets('inactivar pide confirmacion; reactivar no', (tester) async {
      final calls = <(int, bool)>[];
      var active = true;
      await tester.pumpWidget(
        list(
          loadFarms:
              ({required limit, required offset, query, isActive}) async =>
                  _page([_farm(id: 4, active: active)]),
          setActive: (id, value) async {
            calls.add((id, value));
            active = value;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones de la finca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(find.byTooltip('Acciones de la finca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(calls, [(4, false)]);
      expect(find.text('Finca inactivada.'), findsOneWidget);

      await tester.tap(find.byTooltip('Acciones de la finca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(calls, [(4, false), (4, true)]);
      expect(find.text('Finca reactivada.'), findsOneWidget);
    });

    Widget form({Map<String, dynamic>? farm, required SaveFarm onSave}) =>
        MaterialApp(
          home: FarmFormScreen(
            farm: farm,
            loadSuppliers: () async => [
              {'id': 1, 'business_name': 'Proveedor Uno'},
              {'id': 2, 'business_name': 'Proveedor Dos'},
            ],
            onSave: onSave,
          ),
        );

    testWidgets(
      'el formulario valida proveedor, rangos, par y (0, 0) y envia numeros',
      (tester) async {
        tall(tester);
        Map<String, Object?>? sent;
        await tester.pumpWidget(form(onSave: (fields) async => sent = fields));
        await tester.pumpAndSettle();
        // 0 nombre, 1 pais, 2 direccion, 3 latitud, 4 longitud
        final fields = find.byType(TextFormField);

        await tester.tap(find.text('Guardar'));
        await tester.pump();
        expect(find.text('El proveedor es obligatorio.'), findsOneWidget);
        expect(
          find.text('El nombre de la finca es obligatorio.'),
          findsOneWidget,
        );
        expect(sent, isNull);

        await tester.enterText(fields.at(0), ' La Esperanza ');
        await tester.enterText(fields.at(3), '95');
        await tester.enterText(fields.at(4), '-181');
        await tester.tap(find.text('Guardar'));
        await tester.pump();
        expect(
          find.text('La latitud debe estar entre -90 y 90.'),
          findsOneWidget,
        );
        expect(
          find.text('La longitud debe estar entre -180 y 180.'),
          findsOneWidget,
        );

        await tester.enterText(fields.at(3), '2.535');
        await tester.enterText(fields.at(4), '');
        await tester.tap(find.text('Guardar'));
        await tester.pump();
        expect(
          find.text('Informa latitud y longitud juntas, o ninguna.'),
          findsOneWidget,
        );

        await tester.enterText(fields.at(3), '0');
        await tester.enterText(fields.at(4), '0');
        await tester.tap(find.text('Guardar'));
        await tester.pump();
        expect(
          find.text('Las coordenadas (0, 0) no son una ubicación válida.'),
          findsOneWidget,
        );

        await tester.enterText(fields.at(3), '2,535');
        await tester.enterText(fields.at(4), '-75.527');
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proveedor Dos').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(sent, {
          'supplier_id': 2,
          'country_code': 'CO',
          'name': 'La Esperanza',
          'latitude': 2.535,
          'longitude': -75.527,
        });
      },
    );

    testWidgets(
      'en edicion el proveedor no cambia y vaciar el punto envia null',
      (tester) async {
        tall(tester);
        Map<String, Object?>? sent;
        await tester.pumpWidget(
          form(farm: _farm(), onSave: (fields) async => sent = fields),
        );
        await tester.pumpAndSettle();
        expect(find.text('Editar finca'), findsOneWidget);
        expect(find.text('Proveedor Uno'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        final fields = find.byType(TextFormField);
        expect(
          tester.widget<TextFormField>(fields.at(3)).controller?.text,
          '2.535',
        );
        await tester.enterText(fields.at(3), '');
        await tester.enterText(fields.at(4), '');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(sent, {'latitude': null, 'longitude': null});
      },
    );

    testWidgets('un error del servidor se muestra sin cerrar la pantalla', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(
        form(
          farm: _farm(),
          onSave: (fields) async => throw const ApiException(
            statusCode: 409,
            code: 'CONFLICT',
            message: 'El proveedor ya tiene una finca con ese nombre.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Otra');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('El proveedor ya tiene una finca con ese nombre.'),
        findsOneWidget,
      );
      expect(find.text('Guardar'), findsOneWidget);
    });

    testWidgets(
      'el formulario de lote muestra la geolocalizacion de la finca elegida y envia los ids',
      (tester) async {
        tall(tester);
        Map<String, Object?>? sent;
        await tester.pumpWidget(
          MaterialApp(
            home: LotFormScreen(
              loadFarms: () async => [
                _farm(),
                _farm(id: 2, name: 'Sin punto', lat: null, lon: null),
              ],
              loadProducts: () async => [
                {'id': 7, 'variety': 'Caturra', 'quality_grade': 'Excelso'},
              ],
              onSave: (fields) async => sent = fields,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar'));
        await tester.pump();
        expect(find.text('La finca es obligatoria.'), findsOneWidget);
        expect(find.text('El producto es obligatorio.'), findsOneWidget);
        expect(find.text('El código del lote es obligatorio.'), findsOneWidget);

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Sin punto').last);
        await tester.pumpAndSettle();
        expect(
          find.text('La finca no tiene geolocalización registrada.'),
          findsOneWidget,
        );

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('La Esperanza').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('2.535000, -75.527000'), findsOneWidget);

        await tester.tap(find.byType(DropdownButtonFormField<int>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Caturra').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), ' L-1 ');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(sent, {'product_id': 7, 'farm_id': 1, 'lot_code': 'L-1'});
      },
    );

    testWidgets('la lista de lotes muestra el origen y pagina', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LotListScreen(
            loadPermissions: () async => {'lots.read'},
            loadLots: ({required limit, required offset, query}) async =>
                _page([
                  {
                    'id': 1,
                    'lot_code': 'L-1',
                    'product_type': 'coffee',
                    'product_variety': 'Caturra',
                    'product_quality': 'Excelso',
                    'farm_name': 'La Esperanza',
                    'supplier_name': 'Proveedor Uno',
                    'latitude': 2.535,
                    'longitude': -75.527,
                  },
                  {
                    'id': 2,
                    'lot_code': 'L-2',
                    'product_type': 'cacao',
                    'product_variety': 'Criollo',
                    'product_quality': 'Premium',
                    'farm_name': 'Sin punto',
                    'supplier_name': 'Proveedor Uno',
                    'latitude': null,
                    'longitude': null,
                  },
                ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('L-1'), findsOneWidget);
      expect(find.text('2.535000, -75.527000'), findsOneWidget);
      expect(find.text('Finca sin geolocalización'), findsOneWidget);
      expect(find.byTooltip('Registrar lote'), findsNothing);
      expect(find.text('Mostrando 1–2 de 2'), findsOneWidget);
    });
  });

  testWidgets(
    'recorrido completo: proveedor, finca con coordenadas invalidas y validas, y lote',
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

      // Proveedor y producto necesarios.
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registrar proveedor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Proveedor Uno');
      await tester.enterText(find.byType(TextFormField).at(1), 'NIT-0001');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Volver a inicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo de productos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registrar producto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Caturra');
      await tester.enterText(find.byType(TextFormField).at(1), 'Excelso');
      await tester.enterText(find.byType(TextFormField).at(4), '11');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Volver a inicio'));
      await tester.pumpAndSettle();

      // Finca: primero coordenadas fuera de rango, luego validas.
      await tester.tap(find.text('Fincas'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay fincas registradas'), findsOneWidget);
      await tester.tap(find.byTooltip('Registrar finca'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedor Uno').last);
      await tester.pumpAndSettle();
      final farm = find.byType(TextFormField);
      await tester.enterText(farm.at(0), 'La Esperanza');
      await tester.enterText(farm.at(3), '95');
      await tester.enterText(farm.at(4), '-75.527');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(
        find.text('La latitud debe estar entre -90 y 90.'),
        findsOneWidget,
      );
      await tester.enterText(farm.at(3), '2.535');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Finca registrada.'), findsOneWidget);
      expect(find.text('2.535000, -75.527000'), findsOneWidget);

      // Lote de esa finca.
      await tester.tap(find.byTooltip('Volver a inicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lotes'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay lotes registrados'), findsOneWidget);
      await tester.tap(find.byTooltip('Registrar lote'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('La Esperanza').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Caturra').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'L-2026-01');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Lote registrado.'), findsOneWidget);
      expect(find.text('L-2026-01'), findsOneWidget);
      expect(find.text('2.535000, -75.527000'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
