import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/app/router/app_router.dart';

void main() {
  testWidgets('resolves the initial location and unknown routes', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: '/not-defined');
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Página no encontrada'), findsOneWidget);
    expect(find.text('No existe la ruta /not-defined.'), findsOneWidget);
  });

  testWidgets('opens a user edit screen with the selected user', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: '/not-defined');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go(
      '/users/12/edit',
      extra: <String, dynamic>{
        'id': 12,
        'first_name': 'Ana',
        'last_name': 'Pérez',
        'email': 'ana@example.com',
        'phone': null,
        'role_id': 3,
        'is_active': true,
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Editar usuario'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
  });
}
