import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';
import 'package:riexport_app/features/logistics/shipment_status.dart';

class _Store implements SessionTokenStore {
  _Store({this.token, this.failRead = false, this.failDelete = false});
  String? token;
  bool failRead;
  bool failDelete;
  int deletes = 0;
  @override
  Future<String?> readToken() async {
    if (failRead) throw StateError('x');
    return token;
  }

  @override
  Future<void> writeToken(String t) async => token = t;
  @override
  Future<void> deleteToken() async {
    if (failDelete) throw StateError('x');
    deletes++;
    token = null;
  }
}

String _jwt(Map<String, Object?> payload) {
  final body = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'h.$body.s';
}

ApiClient _client(MockClientHandler handler, {Duration? timeout}) => ApiClient(
  config: ApiConfig(timeout: timeout ?? const Duration(seconds: 5)),
  client: MockClient(handler),
);

void main() {
  group('ApiClient', () {
    test('usa un cliente HTTP propio cuando no se inyecta', () {
      final api = ApiClient(config: ApiConfig());
      expect(api.config.baseUri.host, '127.0.0.1');
    });

    test('envia Idempotency-Key, token y cuerpo JSON', () async {
      late http.Request seen;
      final api = ApiClient(
        config: ApiConfig(),
        client: MockClient((request) async {
          seen = request;
          return http.Response('{"ok":true}', 200);
        }),
        tokenProvider: () => 'tok',
        requestIdProvider: () => 'rid-1',
      );
      final result = await api.post(
        '/x',
        body: {'a': 1},
        idempotencyKey: 'key-1',
      );
      expect(result, {'ok': true});
      expect(seen.headers['Idempotency-Key'], 'key-1');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['X-Request-ID'], 'rid-1');
      expect(seen.headers['Content-Type'], 'application/json');
    });

    test('put, patch y delete usan su metodo', () async {
      final methods = <String>[];
      final api = _client((request) async {
        methods.add(request.method);
        return http.Response('', 204);
      });
      expect(await api.put('/x', body: {}), isNull);
      expect(await api.patch('/x', body: {}), isNull);
      expect(await api.delete('/x'), isNull);
      expect(methods, ['PUT', 'PATCH', 'DELETE']);
    });

    test('un tiempo de espera agotado se informa como REQUEST_TIMEOUT', () async {
      final api = _client(
        (request) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        api.get('/lento'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'REQUEST_TIMEOUT'),
        ),
      );
    });

    test('un error de red se informa como API_CONNECTION_ERROR', () async {
      final api = _client((request) async => throw http.ClientException('x'));
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'API_CONNECTION_ERROR',
          ),
        ),
      );
    });

    test('un 2xx que no es JSON es INVALID_RESPONSE', () async {
      final api = _client((request) async => http.Response('<html>', 200));
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('un error no JSON usa el codigo y mensaje de respaldo', () async {
      for (final status in [400, 401, 403, 404, 409, 422, 429, 500, 503]) {
        final api = _client((request) async => http.Response('boom', status));
        await expectLater(
          api.get('/x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.message, 'message', isNotEmpty)
                .having((e) => e.code, 'code', isNotEmpty),
          ),
        );
      }
    });

    test('un error con cuerpo sin code ni message usa los de respaldo', () async {
      final api = _client(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'details': [
                {'field': 3, 'code': 4, 'message': 5},
                'no-es-mapa',
              ],
            },
          }),
          500,
        ),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', isNotEmpty)
              .having((e) => e.message, 'message', isNotEmpty)
              .having((e) => e.details.first.code, 'detail', 'invalid_value')
              .having(
                (e) => e.details.first.message,
                'detail msg',
                'El valor no es válido.',
              ),
        ),
      );
    });

    test('un 422 con detalle usa el mensaje del primer campo', () async {
      final api = _client(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'validation',
              'message': 'general',
              'request_id': 'r-9',
              'details': [
                {'field': 'email', 'code': 'bad', 'message': 'Correo malo'},
              ],
            },
          }),
          422,
        ),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Correo malo')
              .having((e) => e.requestId, 'rid', 'r-9'),
        ),
      );
    });

    test('un 401 con token avisa; sin token o con signalUnauthorized=false no', () async {
      var signals = 0;
      http.Response unauthorized() => http.Response(
        jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'no'},
        }),
        401,
      );
      ApiClient make(String? token) => ApiClient(
        config: ApiConfig(),
        client: MockClient((request) async => unauthorized()),
        tokenProvider: () => token,
        onUnauthorized: () => signals++,
      );
      await expectLater(make('t').get('/x'), throwsA(isA<ApiException>()));
      expect(signals, 1);
      await expectLater(make(null).get('/x'), throwsA(isA<ApiException>()));
      await expectLater(make('').get('/x'), throwsA(isA<ApiException>()));
      await expectLater(
        make('t').post('/x', signalUnauthorized: false),
        throwsA(isA<ApiException>()),
      );
      expect(signals, 1);
    });
  });

  group('ApiConfig', () {
    test('resuelve rutas con y sin barra final y con consulta', () {
      expect(
        ApiConfig(baseUrl: 'https://x.test/api/v1').resolve('/a/b').toString(),
        'https://x.test/api/v1/a/b',
      );
      expect(
        ApiConfig(
          baseUrl: 'https://x.test/api/v1/',
        ).resolve('a', queryParameters: {'q': '1'}).toString(),
        'https://x.test/api/v1/a?q=1',
      );
    });

    test('rechaza URLs inseguras o invalidas', () {
      expect(() => ApiConfig(baseUrl: 'http://x.test'), throwsArgumentError);
      expect(() => ApiConfig(baseUrl: 'ftp://localhost'), throwsArgumentError);
      expect(
        () => ApiConfig(baseUrl: 'https://u:p@x.test'),
        throwsArgumentError,
      );
      expect(() => ApiConfig(baseUrl: '/relativa'), throwsArgumentError);
      ApiConfig(baseUrl: 'http://localhost:8000');
    });
  });

  group('AuthSession', () {
    test('restaura un token vigente y descarta uno vencido o mal formado', () async {
      final valid = _jwt({
        'exp': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });
      var store = _Store(token: valid);
      var session = AuthSession(tokenStore: store);
      await session.restore();
      expect(session.isAuthenticated, isTrue);

      for (final bad in [
        _jwt({'exp': 1}),
        _jwt({'sin': 'exp'}),
        'solo-un-segmento',
        'a.@@@.c',
        'a.${base64Url.encode(utf8.encode('[1,2]'))}.c',
        'a.${base64Url.encode(utf8.encode('no json'))}.c',
      ]) {
        store = _Store(token: bad);
        session = AuthSession(tokenStore: store);
        await session.restore();
        expect(session.isAuthenticated, isFalse, reason: bad);
        expect(store.deletes, 1, reason: bad);
      }

      store = _Store();
      session = AuthSession(tokenStore: store);
      await session.restore();
      expect(session.isAuthenticated, isFalse);
    });

    test('si el almacen falla al leer, queda sin sesion', () async {
      final session = AuthSession(tokenStore: _Store(failRead: true));
      await session.restore();
      expect(session.isAuthenticated, isFalse);
    });

    test('clear informa si no pudo borrar el token; expire es idempotente', () async {
      final store = _Store(failDelete: true);
      final session = AuthSession(tokenStore: store);
      await session.expire(); // sin sesion: no hace nada
      expect(session.sessionExpired, isFalse);
      expect(await session.clear(), isFalse);
      store.failDelete = false;
      expect(await session.clear(), isTrue);
    });

    test('authenticate rechaza respuestas incompletas', () async {
      final bodies = <Object?>[
        'texto',
        {'access_token': '', 'token_type': 'bearer'},
        {'access_token': 'a.b.c', 'token_type': 'mac'},
        {'access_token': 'a.b.c', 'token_type': 'bearer'},
      ];
      for (final body in bodies) {
        final api = _client((request) async => http.Response(jsonEncode(body), 200));
        final session = AuthSession(tokenStore: _Store());
        await expectLater(
          session.authenticate(api, email: 'a@b.co', password: 'x'),
          throwsA(isA<ApiException>()),
        );
        expect(session.isAuthenticated, isFalse);
      }
    });

    test('authenticate guarda el token y limpia la marca de vencida', () async {
      final token = _jwt({
        'exp': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });
      final api = _client(
        (request) async => http.Response(
          jsonEncode({'access_token': token, 'token_type': 'Bearer'}),
          200,
        ),
      );
      final store = _Store();
      final session = AuthSession(tokenStore: store);
      await session.authenticate(api, email: ' a@b.co ', password: 'x');
      expect(session.accessToken, token);
      expect(store.token, token);
      await session.expire();
      expect(session.sessionExpired, isTrue);
      expect(session.isAuthenticated, isFalse);
    });

    test('SecureSessionTokenStore lee, escribe y borra', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionTokenStore();
      expect(await store.readToken(), isNull);
      await store.writeToken('abc');
      expect(await store.readToken(), 'abc');
      await store.deleteToken();
      expect(await store.readToken(), isNull);
      final custom = SecureSessionTokenStore(storage: const FlutterSecureStorage());
      await custom.writeToken('z');
      expect(await custom.readToken(), 'z');
      // El constructor por omisión de AuthSession usa el almacén seguro.
      final session = AuthSession();
      await session.restore();
    });
  });

  test('shipmentIdOf toma id o shipment_id', () {
    expect(shipmentIdOf({'id': 4}), 4);
    expect(shipmentIdOf({'shipment_id': 7}), 7);
    expect(shipmentIdOf({}), isNull);
    expect(shipmentStatusLabel('desconocido'), 'desconocido');
    expect(shipmentStatusLabel(null), '');
  });
}
