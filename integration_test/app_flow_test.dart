// Pruebas de integracion y funcionales en dispositivo real.
// Usan el backend local en memoria (no tocan Supabase ni datos reales).
//
//   flutter test integration_test -d <id-del-celular>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<AuthSession> start(WidgetTester tester, {_MemoryTokenStore? store}) async {
    final session = AuthSession(tokenStore: store ?? _MemoryTokenStore());
    addTearDown(session.dispose);
    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> login(WidgetTester tester, String email, String password) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
  }

  // En un celular el menu vive en un Drawer y la lista se dibuja perezosamente.
  ScaffoldState homeScaffold(WidgetTester tester) =>
      Scaffold.of(tester.element(find.text('Inicio').first));

  Future<void> closeMenu(WidgetTester tester) async {
    if (find.byType(Drawer).evaluate().isNotEmpty) {
      homeScaffold(tester).closeDrawer();
      await tester.pumpAndSettle();
    }
  }

  Future<bool> reachable(WidgetTester tester, String label) async {
    if (find.byType(Drawer).evaluate().isEmpty &&
        homeScaffold(tester).hasDrawer) {
      homeScaffold(tester).openDrawer();
      await tester.pumpAndSettle();
    }
    final item = find.text(label);
    if (item.evaluate().isNotEmpty) return true;
    final scroll = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );
    try {
      await tester.scrollUntilVisible(
        item,
        200,
        scrollable: scroll.evaluate().isNotEmpty
            ? scroll.first
            : find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> backHome(WidgetTester tester) async {
    await closeMenu(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/');
    await tester.pumpAndSettle();
  }

  testWidgets('IT-01 login con credenciales invalidas muestra error', (tester) async {
    await start(tester);
    await login(tester, 'admin@riexport.com', 'ClaveIncorrecta1!');
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Mi perfil'), findsNothing);
  });

  testWidgets('IT-02 login admin, menu completo y cierre de sesion', (tester) async {
    final store = _MemoryTokenStore();
    await start(tester, store: store);
    await login(tester, 'admin@riexport.com', 'Admin123!');
    expect(await reachable(tester, 'Mi perfil'), isTrue);
    expect(await reachable(tester, 'Consultar usuarios'), isTrue);
    expect(await reachable(tester, 'Administrar roles y permisos'), isTrue);
    await closeMenu(tester);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('IT-03 registro de cliente y permisos restringidos', (tester) async {
    await start(tester);
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Luz');
    await tester.enterText(fields.at(1), 'Mora');
    await tester.enterText(fields.at(2), 'luz.it@correo.com');
    await tester.enterText(fields.at(4), 'Secreto1234!');
    await tester.enterText(fields.at(5), 'Secreto1234!');
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver a iniciar sesión'));
    await tester.pumpAndSettle();
    await login(tester, 'luz.it@correo.com', 'Secreto1234!');
    expect(await reachable(tester, 'Mi perfil'), isTrue);
    expect(await reachable(tester, 'Consultar usuarios'), isFalse);
    expect(await reachable(tester, 'Administrar roles y permisos'), isFalse);
    await closeMenu(tester);
  });

  testWidgets('IT-04 cada opcion del menu abre su pantalla sin errores', (tester) async {
    await start(tester);
    await login(tester, 'admin@riexport.com', 'Admin123!');
    const entries = [
      'Mi perfil',
      'Catálogo de productos',
      'Proveedores',
      'Fincas',
      'Lotes',
      'Clientes',
      'Registrar pedido',
      'Consultar pedidos',
      'Registrar exportación',
      'Historial de exportaciones',
      'Consultar inventario',
      'Consultar envíos',
      'Cartera de pagos',
      'Consultar usuarios',
      'Administrar roles y permisos',
    ];
    for (final label in entries) {
      await backHome(tester);
      expect(await reachable(tester, label), isTrue, reason: label);
      final item = find.text(label);
      await Scrollable.ensureVisible(
        tester.element(item.first),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(item.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
      expect(find.byType(Scaffold), findsWidgets, reason: label);
    }
  });

  testWidgets('IT-05 recuperar acceso: codigo invalido es rechazado', (tester) async {
    await start(tester);
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'admin@riexport.com');
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Si existe una cuenta'), findsOneWidget);
    await tester.tap(find.text('Ya tengo un código'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '000000');
    await tester.enterText(fields.at(2), 'ClaveNueva-2026');
    await tester.enterText(fields.at(3), 'ClaveNueva-2026');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no es válido o ya venció'), findsOneWidget);
  });

  testWidgets('IT-06 seguridad: 5 intentos fallidos bloquean el login', (tester) async {
    await start(tester);
    for (var i = 0; i < 5; i++) {
      await login(tester, 'admin@riexport.com', 'Mala-$i-Clave!');
    }
    await login(tester, 'admin@riexport.com', 'Admin123!');
    expect(find.text('Mi perfil'), findsNothing);
    expect(find.textContaining('Demasiados intentos'), findsOneWidget);
  });
}
