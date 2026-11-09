import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';

void main() {
  test('rejects cleartext API endpoints outside loopback', () {
    expect(
      () => ApiConfig(baseUrl: 'http://api.example.test/api/v1'),
      throwsArgumentError,
    );
    expect(
      ApiConfig(baseUrl: 'http://127.0.0.1:8001/api/v1').baseUri.host,
      '127.0.0.1',
    );
  });

  test(
    'sends JSON headers, bearer token, request ID and query parameters',
    () async {
      final client = ApiClient(
        config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/orders');
          expect(request.url.queryParameters, {'status': 'pending'});
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(request.headers['x-request-id'], 'req-test-1');
          expect(request.headers['accept'], 'application/json');
          return http.Response('{"items":[]}', 200);
        }),
        tokenProvider: () => 'test-token',
        requestIdProvider: () => 'req-test-1',
      );
      addTearDown(client.close);

      expect(
        await client.get('/orders', queryParameters: {'status': 'pending'}),
        {'items': []},
      );
    },
  );

  test(
    'parses the API error envelope without exposing submitted values',
    () async {
      final client = ApiClient(
        config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'VALIDATION_ERROR',
                'message': 'La solicitud contiene datos no válidos.',
                'request_id': 'req-server-1',
                'details': [
                  {
                    'field': 'email',
                    'code': 'invalid_format',
                    'message': 'El correo no es válido.',
                  },
                ],
              },
            }),
            422,
          ),
        ),
        requestIdProvider: () => 'req-client-1',
      );
      addTearDown(client.close);

      try {
        await client.post('/users', body: {'email': 'private@example.test'});
        fail('Se esperaba ApiException');
      } on ApiException catch (error) {
        expect(error.statusCode, 422);
        expect(error.code, 'VALIDATION_ERROR');
        expect(error.requestId, 'req-server-1');
        expect(error.details.single.field, 'email');
        expect(error.details.single.code, 'invalid_format');
        // El mensaje es el detalle concreto, no el genérico del servidor.
        expect(error.message, error.details.single.message);
        expect(error.toString(), isNot(contains('private@example.test')));
      }
    },
  );

  test('does not expose a non-JSON server error body', () async {
    final client = ApiClient(
      config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
      client: MockClient((_) async => http.Response('internal traceback', 500)),
    );
    addTearDown(client.close);

    await expectLater(
      client.get('/health'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'INTERNAL_SERVER_ERROR')
            .having((error) => error.message, 'message', contains('inesperado'))
            .having(
              (error) => error.toString(),
              'text',
              isNot(contains('traceback')),
            ),
      ),
    );
  });

  test('maps transport failures to a safe connection error', () async {
    final client = ApiClient(
      config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
      client: MockClient((_) => throw http.ClientException('internal details')),
    );
    addTearDown(client.close);

    await expectLater(
      client.get('/health'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'API_CONNECTION_ERROR')
            .having(
              (error) => error.toString(),
              'text',
              isNot(contains('internal details')),
            ),
      ),
    );
  });

  test(
    'onUnauthorized se invoca con un 401 si la petición llevaba token',
    () async {
      var calls = 0;
      ApiClient client({String? token}) => ApiClient(
        config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"code":"UNAUTHORIZED","message":"x"}}',
            401,
          ),
        ),
        tokenProvider: () => token,
        onUnauthorized: () => calls++,
      );

      await expectLater(
        client(token: 'jwt').get('/users'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);

      // Sin token (inicio de sesión con credenciales incorrectas) no cierra nada.
      await expectLater(
        client().post('/auth/login', body: {}),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    },
  );

  test('signalUnauthorized: false no cierra la sesion ante un 401', () async {
    var calls = 0;
    final client = ApiClient(
      config: ApiConfig(baseUrl: 'https://api.example.test/api/v1'),
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"code":"UNAUTHORIZED","message":"x"}}',
          401,
        ),
      ),
      tokenProvider: () => 'jwt',
      onUnauthorized: () => calls++,
    );
    await expectLater(
      client.post('/auth/logout', signalUnauthorized: false),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 0);
  });
}
