import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/products/presentation/product_catalog_screen.dart';

const _certs = [
  {'id': 1, 'code': 'ORGANIC', 'name': 'Orgánico', 'is_active': true},
  {'id': 2, 'code': 'FAIR_TRADE', 'name': 'Fair Trade', 'is_active': true},
  {'id': 9, 'code': 'LEGACY', 'name': 'Sello heredado', 'is_active': false},
];

Map<String, Object?> _product({
  int id = 1,
  String type = 'coffee',
  String variety = 'Caturra',
  bool active = true,
}) => {
  'id': id,
  'type': type,
  'variety': variety,
  'quality_grade': 'Excelso',
  'hs_code': '0901.11',
  'base_unit_code': 'kg',
  'base_unit_name': 'Kilogramo',
  'low_stock_threshold': 500,
  'is_active': active,
  if (type == 'coffee') 'humidity_percent': 11.5,
  if (type == 'cacao') ...{
    'bean_type': 'Criollo fino',
    'fermentation_percent': 85,
  },
  'certifications': [
    {'id': 1, 'code': 'ORGANIC', 'name': 'Orgánico'},
  ],
  'certification_ids': [1],
};

Map<String, Object?> _page(List<Map<String, Object?>> items, {int? total}) => {
  'items': items,
  'pagination': {'total': total ?? items.length, 'limit': 20, 'offset': 0},
};

Widget _catalog({
  required LoadProducts loadProducts,
  Set<String> permissions = const {
    'products.read',
    'products.create',
    'products.update',
  },
  Future<void> Function(int, bool)? setActive,
  Future<bool> Function(Map<String, dynamic>?)? openForm,
}) => MaterialApp(
  home: ProductCatalogScreen(
    loadProducts: loadProducts,
    loadCertifications: () async => [
      for (final c in _certs) Map<String, dynamic>.from(c),
    ],
    loadPermissions: () async => permissions,
    setActive: setActive,
    openForm: openForm,
  ),
);

void main() {
  group('catalogo', () {
    testWidgets('lista los productos con sus datos y certificaciones', (
      tester,
    ) async {
      await tester.pumpWidget(
        _catalog(
          loadProducts:
              ({
                required limit,
                required offset,
                query,
                type,
                certificationId,
                isActive,
              }) async => _page([
                _product(),
                _product(id: 2, type: 'cacao', variety: 'Criollo'),
              ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Caturra'), findsOneWidget);
      expect(find.text('Criollo'), findsOneWidget);
      expect(find.textContaining('Humedad 11.5 %'), findsOneWidget);
      expect(find.textContaining('Grano Criollo fino'), findsOneWidget);
      expect(find.textContaining('Fermentación 85 %'), findsOneWidget);
      expect(find.text('Orgánico'), findsWidgets);
      expect(find.byTooltip('Registrar producto'), findsOneWidget);
    });

    testWidgets('por defecto muestra solo activos y los filtros se envian', (
      tester,
    ) async {
      final calls = <Map<String, Object?>>[];
      await tester.pumpWidget(
        _catalog(
          loadProducts:
              ({
                required limit,
                required offset,
                query,
                type,
                certificationId,
                isActive,
              }) async {
                calls.add({
                  'q': query,
                  'type': type,
                  'cert': certificationId,
                  'active': isActive,
                });
                return _page([_product()]);
              },
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.last, {
        'q': null,
        'type': null,
        'cert': null,
        'active': true,
      });

      await tester.enterText(find.byType(TextField), 'cat');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(calls.last['q'], 'cat');

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cacao').last);
      await tester.pumpAndSettle();
      expect(calls.last['type'], 'cacao');

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fair Trade').last);
      await tester.pumpAndSettle();
      expect(calls.last['cert'], 2);
    });

    testWidgets('sin permiso de creacion o edicion no hay acciones', (
      tester,
    ) async {
      await tester.pumpWidget(
        _catalog(
          permissions: const {'products.read'},
          loadProducts:
              ({
                required limit,
                required offset,
                query,
                type,
                certificationId,
                isActive,
              }) async => _page([_product()]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Registrar producto'), findsNothing);
      expect(find.byTooltip('Acciones del producto'), findsNothing);
      expect(find.text('Caturra'), findsOneWidget);
    });

    testWidgets('inactiva con confirmacion y reactiva sin ella', (
      tester,
    ) async {
      var active = true;
      final changes = <String>[];
      await tester.pumpWidget(
        _catalog(
          loadProducts:
              ({
                required limit,
                required offset,
                query,
                type,
                certificationId,
                isActive,
              }) async => _page([_product(active: active)]),
          setActive: (id, value) async {
            changes.add('$id:$value');
            active = value;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Acciones del producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('su historial se conserva'), findsOneWidget);
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(changes, ['1:false']);
      expect(find.text('Producto inactivado.'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);

      await tester.tap(find.byTooltip('Acciones del producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(changes, ['1:false', '1:true']);
      expect(find.text('Producto reactivado.'), findsOneWidget);
    });

    testWidgets(
      'muestra el error, permite reintentar y avisa cuando no hay resultados',
      (tester) async {
        var fail = true;
        await tester.pumpWidget(
          _catalog(
            loadProducts:
                ({
                  required limit,
                  required offset,
                  query,
                  type,
                  certificationId,
                  isActive,
                }) async {
                  if (fail) {
                    throw const ApiException(
                      statusCode: 403,
                      code: 'FORBIDDEN',
                      message: 'No tienes permiso para esta operación.',
                    );
                  }
                  return _page([]);
                },
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('No tienes permiso para esta operación.'),
          findsOneWidget,
        );
        fail = false;
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Aún no hay productos registrados'), findsOneWidget);
      },
    );

    testWidgets(
      'editar abre el formulario con el producto y recarga al guardar',
      (tester) async {
        var loads = 0;
        Map<String, dynamic>? opened;
        await tester.pumpWidget(
          _catalog(
            loadProducts:
                ({
                  required limit,
                  required offset,
                  query,
                  type,
                  certificationId,
                  isActive,
                }) async {
                  loads++;
                  return _page([_product()]);
                },
            openForm: (product) async {
              opened = product;
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Acciones del producto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();
        expect(opened?['id'], 1);
        expect(loads, 2);
        expect(find.text('Producto actualizado.'), findsOneWidget);
      },
    );
  });
}
