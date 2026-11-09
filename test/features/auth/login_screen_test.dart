import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:riexport_app/app/router/app_router.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';
import 'package:riexport_app/features/auth/presentation/login_screen.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';

void main() {
  testWidgets('validates required login fields without submitting', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(onLogin: (_, _) async => submitted = true)),
    );

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();

    expect(find.text('Ingresa tu correo electrónico.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('toggles password visibility and displays API errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onLogin: (_, _) async {
            throw const ApiException(
              statusCode: 401,
              code: 'UNAUTHORIZED',
              message: 'Credenciales incorrectas.',
            );
          },
        ),
      ),
    );

    final passwordField = find.byType(TextFormField).last;
    final editablePassword = find.descendant(
      of: passwordField,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editablePassword).obscureText, isTrue);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(tester.widget<EditableText>(editablePassword).obscureText, isFalse);

    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(passwordField, 'wrong-password');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Credenciales incorrectas.'), findsOneWidget);
  });

  testWidgets('submits credentials, persists token and opens home', (
    tester,
  ) async {
    final store = _MemoryTokenStore();
    final session = AuthSession(tokenStore: store);
    final token = _jwt(DateTime.now().add(const Duration(minutes: 10)));
    final apiClient = ApiClient(
      config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'ANA@EXAMPLE.COM',
          'password': 'secret123',
        });
        return http.Response(
          jsonEncode({
            'access_token': token,
            'token_type': 'bearer',
            'expires_in': 600,
          }),
          200,
        );
      }),
    );
    final router = createAppRouter();
    addTearDown(router.dispose);
    addTearDown(apiClient.close);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: session),
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      ' ANA@EXAMPLE.COM ',
    );
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsNWidgets(2));
    expect(session.isAuthenticated, isTrue);
    expect(store.value, token);
  });
}

String _jwt(DateTime expiry) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final payload = base64Url.encode(
    utf8.encode('{"exp":${expiry.millisecondsSinceEpoch ~/ 1000}}'),
  );
  return '$header.$payload.signature';
}

class _MemoryTokenStore implements SessionTokenStore {
  String? value;

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async => value = token;

  @override
  Future<void> deleteToken() async => value = null;
}
