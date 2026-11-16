import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';
import 'package:riexport_app/core/security/security.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';

String _jwt(DateTime exp) {
  String enc(Object o) => base64Url.encode(utf8.encode(jsonEncode(o)));
  return '${enc({'alg': 'none'})}.'
      '${enc({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.firma';
}

class _Store implements SessionTokenStore {
  String? value;
  @override
  Future<String?> readToken() async => value;
  @override
  Future<void> writeToken(String token) async => value = token;
  @override
  Future<void> deleteToken() async => value = null;
}

void main() {
  group('sanitizeText / sanitizeJson (M4)', () {
    test('quita control, ancho cero y bidireccionales; conserva \\n y \\t', () {
      final dirty =
          'a\u0000b\u0007c\u200Bd\u202Ee\u2066f\uFEFFg\u007Fh\nj\tk';
      expect(sanitizeText(dirty), 'abcdefgh\nj\tk');
    });

    test('es recursivo y respeta claves sensibles', () {
      final result = sanitizeJson({
        'name': 'A\u0000B',
        'password': 'x\u0000y',
        'new_password': 'p\u0001q',
        'nested': {
          'list': ['\u202Ez', 1, null, true],
        },
        'code': '1\u200B2',
        'content_base64': 'AA\u0000',
        'count': 3,
      }) as Map;
      expect(result['name'], 'AB');
      expect(result['password'], 'x\u0000y');
      expect(result['new_password'], 'p\u0001q');
      expect(result['code'], '1\u200B2');
      expect(result['content_base64'], 'AA\u0000');
      expect(((result['nested'] as Map)['list'] as List).first, 'z');
      expect(result['count'], 3);
      expect(sanitizeJson(5), 5);
    });
  });

  group('isSafeExternalUri (M5/M8)', () {
    test('solo HTTPS absoluto sin credenciales', () {
      expect(isSafeExternalUri(Uri.parse('https://a.com/x.pdf')), isTrue);
      for (final bad in [
        'http://a.com',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://x#Intent;end',
        'https://user:pw@a.com',
        '/relativo',
        'https://',
      ]) {
        expect(isSafeExternalUri(Uri.tryParse(bad)), isFalse, reason: bad);
      }
      expect(isSafeExternalUri(null), isFalse);
    });
  });

  group('JWT (M3)', () {
    test('lee la expiracion y detecta vencidos', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final future = DateTime.now().add(const Duration(hours: 1));
      expect(isJwtExpired(_jwt(past)), isTrue);
      expect(isJwtExpired(_jwt(future)), isFalse);
      expect(jwtExpiry(_jwt(future)), isNotNull);
      for (final bad in ['abc', 'a.b.c', 'a.!!.c', '${base64Url.encode([1])}.']) {
        expect(jwtExpiry(bad), isNull, reason: bad);
        expect(isJwtExpired(bad), isFalse);
      }
      final noExp =
          '${base64Url.encode(utf8.encode('{}'))}.'
          '${base64Url.encode(utf8.encode('{"a":1}'))}.f';
      expect(jwtExpiry(noExp), isNull);
      final notMap =
          '${base64Url.encode(utf8.encode('{}'))}.'
          '${base64Url.encode(utf8.encode('[1]'))}.f';
      expect(jwtExpiry(notMap), isNull);
    });
  });

  group('redactSensitive (M6)', () {
    test('oculta bearer, jwt y pares clave=valor', () {
      final jwt = _jwt(DateTime.now().add(const Duration(hours: 1)));
      final out = redactSensitive(
        'Authorization: Bearer abc.def-ghi password=Secreto1 '
        '{"token": "xyz123"} jwt=$jwt apikey: K3Y',
      );
      expect(out, isNot(contains('abc.def-ghi')));
      expect(out, isNot(contains('Secreto1')));
      expect(out, isNot(contains('xyz123')));
      expect(out, isNot(contains(jwt)));
      expect(out, isNot(contains('K3Y')));
      expect(out, contains('REDACTADO'));
      expect(redactSensitive('texto normal'), 'texto normal');
    });
  });

  group('LoginThrottle (M3)', () {
    test('bloquea tras N fallos y se libera con el tiempo', () {
      var now = DateTime(2026, 1, 1);
      final t = LoginThrottle(
        maxAttempts: 3,
        lockout: const Duration(seconds: 30),
        clock: () => now,
      );
      expect(t.isLocked, isFalse);
      t.recordFailure();
      t.recordFailure();
      expect(t.isLocked, isFalse);
      t.recordFailure();
      expect(t.isLocked, isTrue);
      expect(t.secondsRemaining, 30);
      t.recordFailure(); // ignorado mientras esta bloqueado
      now = now.add(const Duration(seconds: 10));
      expect(t.secondsRemaining, 20);
      now = now.add(const Duration(seconds: 25));
      expect(t.isLocked, isFalse);
      t.recordFailure();
      t.recordSuccess();
      t.recordFailure();
      t.recordFailure();
      expect(t.isLocked, isFalse);
    });
  });

  group('ApiClient endurecido', () {
    ApiClient client(
      MockClient mock, {
      String? token,
      void Function()? onUnauthorized,
    }) => ApiClient(
      config: ApiConfig(baseUrl: 'https://api.test/v1'),
      client: mock,
      tokenProvider: () => token,
      onUnauthorized: onUnauthorized,
    );

    test('sanea el cuerpo saliente pero no las contrasenas', () async {
      String? sent;
      final api = client(
        MockClient((request) async {
          sent = request.body;
          return http.Response('{}', 200);
        }),
      );
      await api.post(
        '/x',
        body: {'name': 'A\u0000B', 'password': 'p\u0000q'},
      );
      final decoded = jsonDecode(sent!) as Map;
      expect(decoded['name'], 'AB');
      expect(decoded['password'], 'p\u0000q');
    });

    test('no envia un token vencido y cierra la sesion', () async {
      var calls = 0;
      var unauthorized = 0;
      final api = client(
        MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
        token: _jwt(DateTime.now().subtract(const Duration(minutes: 1))),
        onUnauthorized: () => unauthorized++,
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.code, 'code', 'SESSION_EXPIRED'),
        ),
      );
      expect(calls, 0);
      expect(unauthorized, 1);
    });

    test('un token vigente si se envia', () async {
      String? header;
      final api = client(
        MockClient((request) async {
          header = request.headers['Authorization'];
          return http.Response('{}', 200);
        }),
        token: _jwt(DateTime.now().add(const Duration(hours: 1))),
      );
      await api.get('/x');
      expect(header, startsWith('Bearer '));
    });

    test('rechaza respuestas gigantes', () async {
      final api = client(
        MockClient(
          (request) async =>
              http.Response('"${'a' * (ApiClient.maxResponseBytes + 1)}"', 200),
        ),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });
  });

  group('AuthSession: freno de fuerza bruta (M3)', () {
    test('bloquea el login tras demasiados fallos', () async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://api.test/v1'),
        client: MockClient(
          (request) async => http.Response(
            '{"error":{"code":"INVALID_CREDENTIALS","message":"No"}}',
            401,
          ),
        ),
      );
      final session = AuthSession(
        tokenStore: _Store(),
        throttle: LoginThrottle(maxAttempts: 2),
      );
      addTearDown(session.dispose);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          session.authenticate(api, email: 'a@b.co', password: 'x'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
      }
      await expectLater(
        session.authenticate(api, email: 'a@b.co', password: 'x'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 429),
        ),
      );
    });

    test('un error de red no cuenta como intento fallido', () async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://api.test/v1'),
        client: MockClient((request) async => http.Response('x', 500)),
      );
      final session = AuthSession(
        tokenStore: _Store(),
        throttle: LoginThrottle(maxAttempts: 1),
      );
      addTearDown(session.dispose);
      for (var i = 0; i < 3; i++) {
        await expectLater(
          session.authenticate(api, email: 'a@b.co', password: 'x'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 500),
          ),
        );
      }
    });
  });

  group('Configuracion de transporte (M5)', () {
    test('ApiConfig rechaza HTTP remoto, credenciales en URL y esquemas raros', () {
      for (final bad in [
        'http://api.example.com/v1',
        'https://user:pw@api.example.com',
        'ftp://api.example.com',
        'javascript:alert(1)',
      ]) {
        expect(() => ApiConfig(baseUrl: bad), throwsArgumentError, reason: bad);
      }
      expect(() => ApiConfig(baseUrl: 'https://api.example.com/v1'), returnsNormally);
      expect(() => ApiConfig(baseUrl: 'http://localhost:8001/v1'), returnsNormally);
    });
  });
}
