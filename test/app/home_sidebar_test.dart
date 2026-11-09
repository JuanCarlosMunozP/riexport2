import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/app/app.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';

class _MemoryTokenStore implements SessionTokenStore {
  String? value;

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async => value = token;

  @override
  Future<void> deleteToken() async => value = null;
}

void main() {
  Future<void> openHome(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(session.dispose);
    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'admin@riexport.com');
    await tester.enterText(fields.at(1), 'Admin123!');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
  }

  testWidgets('en pantalla ancha el menú lateral está fijo', (tester) async {
    await openHome(tester, const Size(1200, 2400));
    expect(find.byType(Drawer), findsNothing);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.text('Consultar usuarios'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('en móvil el menú se abre con el botón y se cierra al elegir', (
    tester,
  ) async {
    await openHome(tester, const Size(390, 2400));
    expect(find.text('Consultar usuarios'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Consultar usuarios'), findsOneWidget);

    await tester.tap(find.text('Mi perfil'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('las secciones se pliegan y se despliegan con un clic', (
    tester,
  ) async {
    await openHome(tester, const Size(1200, 2400));
    expect(find.text('Consultar usuarios'), findsOneWidget);
    await tester.tap(find.text('Administración'));
    await tester.pumpAndSettle();
    expect(find.text('Consultar usuarios'), findsNothing);
    await tester.tap(find.text('Administración'));
    await tester.pumpAndSettle();
    expect(find.text('Consultar usuarios'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
