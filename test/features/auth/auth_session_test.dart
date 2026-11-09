import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/config/api_config.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';

void main() {
  test(
    'stores a successful login token and restores it from the store',
    () async {
      final store = _MemoryTokenStore();
      final session = AuthSession(tokenStore: store);
      final token = _jwt(DateTime.now().add(const Duration(minutes: 10)));
      final apiClient = ApiClient(
        config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': token,
              'token_type': 'bearer',
              'expires_in': 600,
              'user': {'id': 7},
            }),
            200,
          ),
        ),
      );
      addTearDown(apiClient.close);
      addTearDown(session.dispose);

      await session.authenticate(
        apiClient,
        email: 'user@example.com',
        password: 'secret',
      );

      expect(session.accessToken, token);
      expect(store.value, token);

      final restored = AuthSession(tokenStore: store);
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.isAuthenticated, isTrue);
      expect(restored.accessToken, token);
    },
  );

  test('deletes expired or malformed tokens during restore', () async {
    final expiredStore = _MemoryTokenStore(
      value: _jwt(DateTime.now().subtract(const Duration(seconds: 5))),
    );
    final expiredSession = AuthSession(tokenStore: expiredStore);
    addTearDown(expiredSession.dispose);

    await expiredSession.restore();

    expect(expiredSession.isAuthenticated, isFalse);
    expect(expiredStore.value, isNull);
    expect(expiredStore.deleteCount, 1);

    final malformedStore = _MemoryTokenStore(value: 'not-a-jwt');
    final malformedSession = AuthSession(tokenStore: malformedStore);
    addTearDown(malformedSession.dispose);

    await malformedSession.restore();

    expect(malformedSession.isAuthenticated, isFalse);
    expect(malformedStore.value, isNull);
  });

  test('clear removes the in-memory and persisted token', () async {
    final store = _MemoryTokenStore(
      value: _jwt(DateTime.now().add(const Duration(minutes: 2))),
    );
    final session = AuthSession(tokenStore: store);
    addTearDown(session.dispose);
    await session.restore();

    await session.clear();

    expect(session.isAuthenticated, isFalse);
    expect(store.value, isNull);
    expect(store.deleteCount, 1);
  });

  test('expire cierra la sesion una sola vez y marca el motivo', () async {
    final store = _MemoryTokenStore();
    final session = AuthSession(tokenStore: store);
    store.value = _jwt(DateTime.now().add(const Duration(minutes: 5)));
    await session.restore();
    expect(session.isAuthenticated, isTrue);
    expect(session.sessionExpired, isFalse);

    var notifications = 0;
    session.addListener(() => notifications++);
    await Future.wait([session.expire(), session.expire()]);

    expect(session.isAuthenticated, isFalse);
    expect(session.sessionExpired, isTrue);
    expect(store.value, isNull);
    expect(notifications, 1);
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
