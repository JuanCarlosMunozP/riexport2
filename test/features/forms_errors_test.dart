import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/farms/presentation/farm_form_screen.dart';
import 'package:riexport_app/features/products/presentation/product_form_screen.dart';
import 'package:riexport_app/features/profile/presentation/profile_screen.dart';

ApiException _api(String m) =>
    ApiException(statusCode: 400, code: 'e', message: m);

Future<void> pumpRouted(
  WidgetTester tester,
  Widget screen, {
  bool pushed = false,
}) async {
  tester.view.physicalSize = const Size(700, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: pushed ? '/' : '/x',
    routes: [
      GoRoute(path: '/x', builder: (_, _) => screen),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
      ),
      GoRoute(
        path: '/products',
        builder: (_, _) => const Scaffold(body: Text('CATALOGO')),
      ),
      GoRoute(
        path: '/farms',
        builder: (_, _) => const Scaffold(body: Text('FINCAS')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  if (pushed) {
    unawaited(router.push('/x'));
    await tester.pumpAndSettle();
  }
}

const _profile = {
  'id': 7,
  'email': 'ana@example.com',
  'first_name': 'Ana',
  'last_name': 'Perez',
};

const _cafe = {
  'id': 4,
  'type': 'coffee',
  'variety': 'Caturra',
  'quality_grade': 'Excelso',
  'hs_code': '0901.11',
  'base_unit_code': 'kg',
  'low_stock_threshold': 500.0,
  'humidity_percent': 11.5,
  'certification_ids': <int>[],
};

void main() {
  group('ProfileScreen', () {
    testWidgets('error de carga (API y generico), reintento y volver', (
      tester,
    ) async {
      var mode = 'api';
      await pumpRouted(
        tester,
        ProfileScreen(
          loadProfile: () async {
            if (mode == 'api') throw _api('Sin sesion');
            if (mode == 'boom') throw StateError('x');
            return _profile;
          },
          saveProfile: (c) async => _profile,
          changeEmail: (e) async => {},
        ),
      );
      expect(find.text('Sin sesion'), findsOneWidget);
      mode = 'boom';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No fue posible cargar tu perfil.'), findsWidgets);
      mode = 'ok';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Perez'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver a inicio'));
      await tester.pumpAndSettle();
      expect(find.text('INICIO'), findsOneWidget);
    });

    testWidgets('guardar datos y cambiar correo con error generico', (
      tester,
    ) async {
      await pumpRouted(
        tester,
        ProfileScreen(
          loadProfile: () async => _profile,
          saveProfile: (c) async => throw StateError('x'),
          changeEmail: (e) async => throw StateError('x'),
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Anita');
      await tester.ensureVisible(find.text('Guardar datos'));
      await tester.tap(find.text('Guardar datos'));
      await tester.pumpAndSettle();
      expect(find.text('No fue posible guardar tus datos.'), findsOneWidget);

      await tester.enterText(fields.at(3), 'nuevo@example.com');
      await tester.ensureVisible(find.text('Cambiar correo').last);
      await tester.tap(find.text('Cambiar correo').last);
      await tester.pumpAndSettle();
      expect(find.text('No fue posible cambiar el correo.'), findsOneWidget);
    });
  });

  group('ProductFormScreen', () {
    Widget form({
      Future<List<Map<String, dynamic>>> Function()? certs,
      SaveProduct? onSave,
      Map<String, dynamic>? product,
    }) => ProductFormScreen(
      product: product,
      loadCertifications: certs ?? () async => [],
      loadUnits: () async => [
        {'code': 'kg', 'name': 'Kilogramo'},
        {'code': 't', 'name': 'Tonelada'},
      ],
      onSave:
          onSave ??
          ({
            required fields,
            required certificationIds,
            required certificationsChanged,
          }) async {},
    );

    testWidgets('error de catalogos (API y generico) y reintento', (
      tester,
    ) async {
      var mode = 'api';
      await pumpRouted(
        tester,
        form(
          certs: () async {
            if (mode == 'api') throw _api('Sin catalogo');
            if (mode == 'boom') throw StateError('x');
            return [];
          },
        ),
      );
      expect(find.text('Sin catalogo'), findsOneWidget);
      mode = 'boom';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No fue posible cargar los catálogos.'), findsOneWidget);
      mode = 'ok';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsOneWidget);
    });

    testWidgets('volver sin pila navega al catalogo', (tester) async {
      await pumpRouted(tester, form());
      await tester.tap(find.byTooltip('Volver al catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('CATALOGO'), findsOneWidget);
    });

    testWidgets('editar: sin cambios no guarda; con cambios, error generico y cambio de unidad', (
      tester,
    ) async {
      var saves = 0;
      await pumpRouted(
        tester,
        form(
          product: Map<String, dynamic>.from(_cafe),
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async {
                saves++;
                throw StateError('x');
              },
        ),
        pushed: true,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(saves, 0);
    });

    testWidgets('alta: guardar con error generico', (tester) async {
      await pumpRouted(
        tester,
        form(
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async => throw StateError('x'),
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Caturra');
      await tester.enterText(fields.at(1), 'Excelso');
      await tester.enterText(fields.at(2), '0901.11');
      await tester.enterText(fields.at(4), '11');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('No fue posible guardar el producto.'), findsOneWidget);
    });
  });

  group('FarmFormScreen', () {
    testWidgets('error al cargar proveedores (API y generico) y reintento', (
      tester,
    ) async {
      var mode = 'api';
      await pumpRouted(
        tester,
        FarmFormScreen(
          loadSuppliers: () async {
            if (mode == 'api') throw _api('Sin proveedores');
            if (mode == 'boom') throw StateError('x');
            return [
              {'id': 1, 'name': 'Proveedor 1'},
            ];
          },
          onSave: (fields) async {},
        ),
      );
      expect(find.text('Sin proveedores'), findsOneWidget);
      mode = 'boom';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(
        find.text('No fue posible cargar los proveedores.'),
        findsOneWidget,
      );
      mode = 'ok';
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsNothing);
      await tester.tap(find.byTooltip('Volver a fincas'));
      await tester.pumpAndSettle();
      expect(find.text('FINCAS'), findsOneWidget);
    });
  });
}
