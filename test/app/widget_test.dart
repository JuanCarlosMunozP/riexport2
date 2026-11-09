import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:riexport_app/app/app.dart';
import 'package:riexport_app/backend/local_backend_store.dart';
import 'package:riexport_app/app/state/app_preferences.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';
import 'dart:convert';

class _MemoryTokenStore implements SessionTokenStore {
  _MemoryTokenStore({this.value});

  String? value;
  int deleteCount = 0;

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async => value = token;

  @override
  Future<void> deleteToken() async {
    value = null;
    deleteCount++;
  }
}

void main() {
  testWidgets('provides app preferences and updates the theme mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      RiExportApp(authSession: AuthSession(tokenStore: _MemoryTokenStore())),
    );
    await tester.pumpAndSettle();

    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);

    final context = tester.element(find.byType(MaterialApp));
    expect(
      Provider.of<ApiClient>(context, listen: false).config.baseUri.toString(),
      'http://127.0.0.1:8001/api/v1',
    );
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);

    await tester.ensureVisible(find.text('Regístrate'));
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    expect(find.text('Registro'), findsOneWidget);
    expect(find.text('Datos de la cuenta'), findsOneWidget);
    Provider.of<AppPreferences>(
      context,
      listen: false,
    ).setThemeMode(ThemeMode.dark);
    await tester.pump();

    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opens the home route for a restored session', (tester) async {
    final token = _validLocalToken();
    final store = _MemoryTokenStore(value: token);
    final authSession = AuthSession(tokenStore: store);
    addTearDown(authSession.dispose);
    await authSession.restore();

    await tester.pumpWidget(RiExportApp(authSession: authSession));
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('logout clears persisted token and returns to login', (
    tester,
  ) async {
    final store = _MemoryTokenStore(value: _validLocalToken());
    final authSession = AuthSession(tokenStore: store);
    addTearDown(authSession.dispose);
    await authSession.restore();

    await tester.pumpWidget(RiExportApp(authSession: authSession));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(authSession.isAuthenticated, isFalse);
    expect(store.value, isNull);
    expect(store.deleteCount, 1);
  });

  testWidgets('un 401 del servidor cierra la sesión y avisa en el acceso', (
    tester,
  ) async {
    // Token con forma válida pero que el backend rechaza (usuario inexistente).
    final store = _MemoryTokenStore(
      value: _jwt(DateTime.now().add(const Duration(minutes: 5))),
    );
    final authSession = AuthSession(tokenStore: store);
    addTearDown(authSession.dispose);
    await authSession.restore();
    expect(authSession.isAuthenticated, isTrue);

    await tester.pumpWidget(RiExportApp(authSession: authSession));
    await tester.pumpAndSettle();

    // El inicio consulta /me, recibe 401, cierra la sesión y vuelve al acceso.
    expect(authSession.isAuthenticated, isFalse);
    expect(authSession.sessionExpired, isTrue);
    expect(store.value, isNull);
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(
      find.text('Tu sesión expiró. Inicia sesión de nuevo.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sin sesión no se puede entrar a rutas protegidas', (
    tester,
  ) async {
    final authSession = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(authSession.dispose);
    await tester.pumpWidget(RiExportApp(authSession: authSession));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    for (final ruta in ['/users', '/roles', '/profile', '/']) {
      router.go(ruta);
      await tester.pumpAndSettle();
      expect(find.text('Bienvenido'), findsOneWidget, reason: ruta);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('con sesión activa no se vuelve al acceso ni al registro', (
    tester,
  ) async {
    final authSession = AuthSession(
      tokenStore: _MemoryTokenStore(value: _validLocalToken()),
    );
    addTearDown(authSession.dispose);
    await authSession.restore();
    await tester.pumpWidget(RiExportApp(authSession: authSession));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsNWidgets(2));

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    for (final ruta in ['/login', '/register']) {
      router.go(ruta);
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsNWidgets(2), reason: ruta);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Token que el backend local de la app acepta (el administrador inicial).
String _validLocalToken() =>
    LocalBackendStore().login({
          'email': 'admin@riexport.com',
          'password': 'Admin123!',
        })['access_token']!
        as String;

String _jwt(DateTime expiry) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final payload = base64Url.encode(
    utf8.encode('{"exp":${expiry.millisecondsSinceEpoch ~/ 1000}}'),
  );
  return '$header.$payload.signature';
}
