import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import '../support/local_backend_test_context.dart';

void main() {
  setUp(setUpLocalBackendTest);

  group('productos (backend local)', () {
    Map<String, Object?> cafe({Map<String, Object?> extra = const {}}) => {
      'type': 'coffee',
      'variety': 'Caturra',
      'quality_grade': 'Excelso',
      'hs_code': '0901.11',
      'base_unit_code': 'kg',
      'low_stock_threshold': 500,
      'humidity_percent': 11.5,
      ...extra,
    };

    Future<void> expectError(
      Future<Object?> call,
      int status, [
      Pattern? message,
    ]) => expectLater(
      call,
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', status)
            .having(
              (e) => e.message,
              'message',
              message == null ? anything : contains(message),
            ),
      ),
    );

    test('registra cafe y cacao y los lista con filtros', () async {
      final created =
          await api.post(
                '/products',
                body: cafe(
                  extra: {
                    'certification_ids': [1, 2],
                  },
                ),
              )
              as Map<String, dynamic>;
      expect(created['base_unit_name'], 'Kilogramo');
      expect(created['humidity_percent'], 11.5);
      expect((created['certifications'] as List).map((c) => c['code']), [
        'FAIR_TRADE',
        'ORGANIC',
      ]);

      await api.post(
        '/products',
        body: {
          'type': 'cacao',
          'variety': 'Criollo',
          'quality_grade': 'Premium',
          'base_unit_code': 't',
          'bean_type': 'Criollo fino',
          'fermentation_percent': '85,5'.replaceAll(',', '.'),
        },
      );

      Future<List> list(Map<String, String> q) async =>
          ((await api.get('/products', queryParameters: q)) as Map)['items']
              as List;
      expect(await list({}), hasLength(2));
      expect(await list({'type': 'cacao'}), hasLength(1));
      expect(await list({'certification_id': '1'}), hasLength(1));
      expect(await list({'q': 'excel'}), hasLength(1));
      expect(await list({'is_active': 'false'}), isEmpty);
    });

    test(
      'valida como la base: obligatorios, rangos, formato y duplicados',
      () async {
        await api.post('/products', body: cafe());
        await expectError(
          api.post(
            '/products',
            body: cafe(
              extra: {'variety': 'CATURRA', 'quality_grade': 'excelso'},
            ),
          ),
          409,
          'Ya existe un producto',
        );
        await expectError(
          api.post('/products', body: cafe(extra: {'type': 'te'})),
          422,
          'café o cacao',
        );
        await expectError(
          api.post('/products', body: cafe(extra: {'variety': ' '})),
          422,
          'variedad es obligatoria',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(extra: {'variety': 'X', 'humidity_percent': 101}),
          ),
          422,
          'entre 0 y 100',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(extra: {'variety': 'X', 'humidity_percent': 'abc'}),
          ),
          422,
          'número válido',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(extra: {'variety': 'X', 'hs_code': '09'}),
          ),
          422,
          'código HS',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(extra: {'variety': 'X', 'base_unit_code': 'lb'}),
          ),
          422,
          'unidad base no existe',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(extra: {'variety': 'X', 'low_stock_threshold': -1}),
          ),
          422,
          'negativo',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(extra: {'variety': 'X', 'bean_type': 'Criollo'}),
          ),
          422,
          'Campo no permitido',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(
              extra: {
                'variety': 'X',
                'certification_ids': [99],
              },
            ),
          ),
          422,
          'certificaciones',
        );
        await expectError(
          api.post(
            '/products',
            body: cafe(
              extra: {
                'variety': 'X',
                'certification_ids': [1, 1],
              },
            ),
          ),
          422,
          'duplicadas',
        );
        await expectError(
          api.post(
            '/products',
            body: {
              'type': 'cacao',
              'variety': 'C',
              'quality_grade': 'P',
              'base_unit_code': 'kg',
              'fermentation_percent': 80,
            },
          ),
          422,
          'tipo de grano',
        );
        // Ningún intento fallido dejó un producto a medias.
        expect(((await api.get('/products')) as Map)['items'], hasLength(1));
      },
    );

    test('edita, no cambia tipo ni unidad, inactiva y reactiva', () async {
      final created =
          await api.post('/products', body: cafe()) as Map<String, dynamic>;
      final id = created['id'];
      final updated =
          await api.patch(
                '/products/$id',
                body: {
                  'quality_grade': 'Supremo',
                  'humidity_percent': 10,
                  'hs_code': null,
                },
              )
              as Map<String, dynamic>;
      expect(updated['quality_grade'], 'Supremo');
      expect(updated['hs_code'], isNull);
      await expectError(
        api.patch('/products/$id', body: {'type': 'cacao'}),
        422,
        'tipo de producto',
      );
      await expectError(
        api.patch('/products/$id', body: {'base_unit_code': 't'}),
        422,
        'unidad base',
      );
      await expectError(
        api.patch('/products/$id', body: {'bean_type': 'x'}),
        422,
        'Campo no permitido',
      );
      await expectError(
        api.patch('/products/$id', body: {}),
        422,
        'al menos un campo',
      );
      await expectError(
        api.patch('/products/999', body: {'variety': 'Z'}),
        404,
      );

      final off =
          await api.patch('/products/$id/status', body: {'is_active': false})
              as Map<String, dynamic>;
      expect(off['is_active'], isFalse);
      expect(
        ((await api.get('/products', queryParameters: {'is_active': 'true'}))
            as Map)['items'],
        isEmpty,
      );
      final on =
          await api.patch('/products/$id/status', body: {'is_active': true})
              as Map<String, dynamic>;
      expect(on['is_active'], isTrue);
      await expectError(
        api.patch('/products/$id/status', body: {}),
        422,
        'activo',
      );
    });

    test(
      'asocia certificaciones y rechaza duplicadas o inexistentes',
      () async {
        final id = (await api.post('/products', body: cafe()) as Map)['id'];
        final withCerts =
            await api.put(
                  '/products/$id/certifications',
                  body: {
                    'certification_ids': [3, 1],
                  },
                )
                as Map<String, dynamic>;
        expect(withCerts['certification_ids'], [1, 3]);
        await expectError(
          api.put(
            '/products/$id/certifications',
            body: {
              'certification_ids': [1, 1],
            },
          ),
          422,
          'duplicadas',
        );
        await expectError(
          api.put(
            '/products/$id/certifications',
            body: {
              'certification_ids': [42],
            },
          ),
          422,
          'no existen',
        );
        final cleared =
            await api.put(
                  '/products/$id/certifications',
                  body: {'certification_ids': <int>[]},
                )
                as Map<String, dynamic>;
        expect(cleared['certifications'], isEmpty);
      },
    );

    test('catalogos de referencia y permisos', () async {
      final certs = await api.get('/certifications') as Map<String, dynamic>;
      expect(certs['items'], hasLength(3));
      final units = await api.get('/units') as Map<String, dynamic>;
      expect((units['items'] as List).map((u) => u['code']), ['kg', 't']);

      // Un usuario registrado (rol cliente) no tiene permisos de producto.
      await api.post(
        '/auth/register',
        body: {
          'email': 'sin@permiso.com',
          'password': 'secreto1',
          'first_name': 'Sin',
          'last_name': 'Permiso',
        },
      );
      final admin = token;
      final login =
          await api.post(
                '/auth/login',
                body: {'email': 'sin@permiso.com', 'password': 'secreto1'},
              )
              as Map;
      token = login['access_token'] as String;
      await expectError(api.get('/products'), 403);
      await expectError(api.post('/products', body: cafe()), 403);
      token = admin;
      expect(await api.get('/products'), isA<Map>());
    });
  });
}
