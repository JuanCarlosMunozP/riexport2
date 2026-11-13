import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/customers/presentation/customer_list_screen.dart';
import 'package:riexport_app/features/farms/presentation/farm_list_screen.dart';
import 'package:riexport_app/features/farms/presentation/lot_screens.dart';
import 'package:riexport_app/features/products/presentation/product_catalog_screen.dart';
import 'package:riexport_app/features/suppliers/presentation/supplier_list_screen.dart';
import 'package:riexport_app/features/users/presentation/users_screen.dart';

typedef Loader = Future<Object?> Function(int offset, String? query);

Map<String, dynamic> _item(int i) => {
  'id': i,
  'name': 'Elemento $i',
  'legal_name': 'Razon $i',
  'trade_name': 'Comercial $i',
  'contact_name': 'Contacto $i',
  'email': 'e$i@x.co',
  'first_name': 'Nombre$i',
  'last_name': 'Apellido$i',
  'phone': '300$i',
  'role': 'administrador',
  'role_name': 'administrador',
  'role_id': 1,
  'country_code': 'CO',
  'tax_id': '900$i',
  'eori_number': 'DE12345678901$i',
  'preferred_currency_code': 'USD',
  'supplier_id': 1,
  'supplier_name': 'Proveedor',
  'address': 'Calle $i',
  'latitude': 4.5,
  'longitude': -74.0,
  'lot_count': 2,
  'lot_code': 'L-$i',
  'product_id': 1,
  'product_type': 'coffee',
  'type': 'coffee',
  'variety': 'Castillo',
  'quality_grade': 'A',
  'base_unit_code': 'kg',
  'farm_name': 'Finca',
  'is_active': i.isOdd,
  'certifications': [
    {'id': 1, 'name': 'Organico', 'code': 'ORG'},
  ],
  'created_at': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> page(int offset, {int total = 45}) => {
  'items': [_item(offset + 1), _item(offset + 2)],
  'pagination': {'total': total, 'limit': 20, 'offset': offset},
};

class Spec {
  Spec(this.name, this.build, this.errorText, this.refreshTooltip);
  final String name;
  final Widget Function(Loader load) build;
  final String errorText;
  final String? refreshTooltip;
}

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
      ),
      GoRoute(path: '/x', builder: (_, _) => screen),
      GoRoute(
        path: '/lots/new',
        builder: (_, _) => const Scaffold(body: Text('NUEVO LOTE')),
      ),
      GoRoute(
        path: '/lots/origin',
        builder: (_, _) => const Scaffold(body: Text('ORIGEN')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<Set<String>> _perms() async => {
  'customers.create',
  'customers.update',
  'suppliers.create',
  'suppliers.update',
  'farms.create',
  'farms.update',
  'products.create',
  'products.update',
  'lots.create',
};

final specs = <Spec>[
  Spec(
    'clientes',
    (load) => CustomerListScreen(
      loadCustomers:
          ({required limit, required offset, query, countryCode, isActive}) =>
              load(offset, query),
      loadPermissions: _perms,
      setActive: (id, active) async {},
    ),
    'No fue posible cargar los clientes.',
    'Actualizar clientes',
  ),
  Spec(
    'proveedores',
    (load) => SupplierListScreen(
      loadSuppliers: ({required limit, required offset, query, isActive}) =>
          load(offset, query),
      loadPermissions: _perms,
      setActive: (id, active) async {},
    ),
    'No fue posible cargar los proveedores.',
    'Actualizar proveedores',
  ),
  Spec(
    'fincas',
    (load) => FarmListScreen(
      loadFarms: ({required limit, required offset, query, isActive}) =>
          load(offset, query),
      loadPermissions: _perms,
      setActive: (id, active) async {},
    ),
    'No fue posible cargar las fincas.',
    'Actualizar fincas',
  ),
  Spec(
    'productos',
    (load) => ProductCatalogScreen(
      loadProducts:
          ({
            required limit,
            required offset,
            query,
            type,
            certificationId,
            isActive,
          }) => load(offset, query),
      loadCertifications: () async => [],
      loadPermissions: _perms,
      setActive: (id, active) async {},
    ),
    'No fue posible cargar los productos.',
    'Actualizar catálogo',
  ),
  Spec(
    'usuarios',
    (load) => UsersScreen(
      loadUsers: ({required limit, required offset, query, isActive}) =>
          load(offset, query),
      deactivateUser: (id) async {},
      reactivateUser: (id) async {},
    ),
    'No fue posible cargar los usuarios. Inténtalo de nuevo.',
    'Actualizar lista',
  ),
  Spec(
    'lotes',
    (load) => LotListScreen(
      loadLots: ({required limit, required offset, query}) =>
          load(offset, query),
      loadPermissions: _perms,
    ),
    'No fue posible cargar los lotes.',
    'Actualizar lotes',
  ),
];

void main() {
  for (final spec in specs) {
    group('listado de ${spec.name}', () {
      testWidgets('error de API, reintento y error generico', (tester) async {
        var calls = 0;
        Object? failure = const ApiException(
          statusCode: 500,
          code: 'e',
          message: 'Servidor caido',
        );
        await pumpScreen(
          tester,
          spec.build((offset, query) async {
            calls++;
            if (failure != null) throw failure;
            return page(offset);
          }),
        );
        expect(find.text('Servidor caido'), findsOneWidget);
        failure = StateError('x');
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text(spec.errorText), findsOneWidget);
        failure = null;
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Reintentar'), findsNothing);
        expect(calls, greaterThanOrEqualTo(3));
      });

      testWidgets('una respuesta con formato invalido muestra error', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          spec.build((offset, query) async => 'no-es-un-mapa'),
        );
        expect(find.text('Reintentar'), findsOneWidget);
      });

      testWidgets('paginacion, busqueda con retardo y refresco', (tester) async {
        final offsets = <int>[];
        final queries = <String?>[];
        await pumpScreen(
          tester,
          spec.build((offset, query) async {
            offsets.add(offset);
            queries.add(query);
            return page(offset);
          }),
        );
        expect(offsets, isNotEmpty);
        await tester.tap(find.byTooltip('Página siguiente'));
        await tester.pumpAndSettle();
        expect(offsets.last, 20);
        await tester.tap(find.byTooltip('Página anterior'));
        await tester.pumpAndSettle();
        expect(offsets.last, 0);

        await tester.enterText(find.byType(TextField).first, 'cafe');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField).first, 'cafe verde');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(queries.last, 'cafe verde');

        if (spec.refreshTooltip != null) {
          final before = offsets.length;
          await tester.tap(find.byTooltip(spec.refreshTooltip!));
          await tester.pumpAndSettle();
          expect(offsets.length, greaterThan(before));
        }
      });

      testWidgets('lista vacia y volver al inicio', (tester) async {
        await pumpScreen(
          tester,
          spec.build(
            (offset, query) async => {
              'items': <Object?>[],
              'pagination': {'total': 0, 'limit': 20, 'offset': 0},
            },
          ),
        );
        expect(find.byType(Card), findsNothing);
        await tester.tap(find.byTooltip('Volver a inicio'));
        await tester.pumpAndSettle();
        expect(find.text('INICIO'), findsOneWidget);
      });
    });
  }

  testWidgets('usuarios: respuesta invalida y limpiar la busqueda', (
    tester,
  ) async {
    var invalid = true;
    await pumpScreen(
      tester,
      UsersScreen(
        loadUsers: ({required limit, required offset, query, isActive}) async {
          if (invalid) throw const FormatException('x');
          return page(offset, total: 2);
        },
        deactivateUser: (id) async {},
        reactivateUser: (id) async {},
      ),
    );
    expect(
      find.text('El servidor devolvió una respuesta no válida.'),
      findsOneWidget,
    );
    invalid = false;
    await tester.tap(find.byTooltip('Actualizar lista'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ana');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('lotes: abrir el formulario y el origen desde la lista', (
    tester,
  ) async {
    var opened = 0;
    Map<String, dynamic>? origin;
    await pumpScreen(
      tester,
      LotListScreen(
        loadLots: ({required limit, required offset, query}) async =>
            page(offset, total: 2),
        loadPermissions: _perms,
        openForm: () async {
          opened++;
          return true;
        },
        openOrigin: (lot) => origin = lot,
      ),
    );
    await tester.tap(find.byTooltip('Registrar lote'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Lote registrado.'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver origen en el mapa').first);
    await tester.pumpAndSettle();
    expect(origin?['id'], 1);
  });

  testWidgets('lotes: navegacion por defecto al formulario y al origen', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      LotListScreen(
        loadLots: ({required limit, required offset, query}) async =>
            page(offset, total: 2),
        loadPermissions: _perms,
      ),
    );
    await tester.tap(find.byTooltip('Ver origen en el mapa').first);
    await tester.pumpAndSettle();
    expect(find.text('ORIGEN'), findsOneWidget);
  });

  testWidgets('lotes: los permisos fallidos dejan la lista en solo lectura', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      LotListScreen(
        loadLots: ({required limit, required offset, query}) async =>
            page(offset, total: 2),
        loadPermissions: () async => throw StateError('x'),
      ),
    );
    expect(find.byTooltip('Registrar lote'), findsNothing);
  });
}
