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
  testWidgets('el inicio muestra la gestion solo a quien tiene permisos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(session.dispose);

    Future<void> login(String email, String password) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), email);
      await tester.enterText(fields.at(1), password);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();

    // Administrador: ve todas las opciones.
    await login('admin@riexport.com', 'Admin123!');
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Consultar usuarios'), findsOneWidget);
    expect(find.text('Administrar roles y permisos'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();

    // Registro público: la cuenta nace como cliente, sin permisos de gestión.
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Luz');
    await tester.enterText(fields.at(1), 'Mora');
    await tester.enterText(fields.at(2), 'luz@correo.com');
    await tester.enterText(fields.at(4), 'Secreto1234!');
    await tester.enterText(fields.at(5), 'Secreto1234!');
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver a iniciar sesión'));
    await tester.pumpAndSettle();

    await login('luz@correo.com', 'Secreto1234!');
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Consultar usuarios'), findsNothing);
    expect(find.text('Administrar roles y permisos'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('recuperar el acceso desde el login de punta a punta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(session.dispose);
    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();

    // Rutas públicas aunque no haya sesión.
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar acceso'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'admin@riexport.com');
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Si existe una cuenta'), findsOneWidget);

    // El backend local devuelve el código en dev_code; la pantalla no lo muestra,
    // así que se canjea con un código inválido para comprobar el error.
    await tester.tap(find.text('Ya tengo un código'));
    await tester.pumpAndSettle();
    expect(find.text('Contraseña nueva'), findsWidgets);
    final fields = find.byType(TextFormField);
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller?.text,
      'admin@riexport.com',
    );
    await tester.enterText(fields.at(1), '000000');
    await tester.enterText(fields.at(2), 'ClaveNueva-2026');
    await tester.enterText(fields.at(3), 'ClaveNueva-2026');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no es válido o ya venció'), findsOneWidget);

    // Volver al acceso.
    await tester.tap(find.byTooltip('Volver a iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
