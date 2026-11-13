import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/backend/supabase_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';

String _jwt(String sub) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': sub})))
      .replaceAll('=', '');
  return 'h.$payload.s';
}

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

ApiClient _api(Future<http.Response> Function(http.Request) handler,
    {String? token}) => ApiClient(
  config: ApiConfig(),
  client: SupabaseBackendClient(
    url: 'https://demo.supabase.co',
    anonKey: 'anon',
    inner: MockClient(handler),
  ),
  tokenProvider: () => token,
);

Matcher _error(int status, [String? text]) => throwsA(
  isA<ApiException>()
      .having((e) => e.statusCode, 'status', status)
      .having((e) => e.message, 'message', text == null ? isNotEmpty : _has(text)),
);

Matcher _has(String s) => predicate<String>((m) => m.contains(s), 'contiene $s');

void main() {
  test('el registro traduce un error de GoTrue sobre la contrasena', () async {
    final api = _api(
      (r) async => _json({'msg': 'Password is too short', 'error_code': 'x'}, 422),
    );
    await expectLater(
      api.post(
        '/auth/register',
        body: {
          'first_name': 'A',
          'last_name': 'B',
          'email': 'a@b.co',
          'password': 'corta',
          'phone': '3000000',
        },
      ),
      _error(422, 'contraseña'),
    );
  });

  test('restablecer contrasena: fallo 5xx al actualizar es upstream', () async {
    final api = _api((r) async {
      if (r.url.path.endsWith('/verify')) {
        return _json({'access_token': 'tmp'});
      }
      if (r.url.path.endsWith('/logout')) throw http.ClientException('x');
      return http.Response('boom', 503);
    });
    await expectLater(
      api.post(
        '/auth/password-resets',
        body: {
          'email': 'a@b.co',
          'code': '123456',
          'new_password': 'Nueva-Clave-2026',
        },
      ),
      _error(502),
    );
  });

  test('perfil propio: limites de longitud y perfil inexistente', () async {
    final token = _jwt('uuid-1');
    var empty = false;
    final api = _api(
      (r) async => _json(empty ? [] : [{'id': 1}]),
      token: token,
    );
    await expectLater(
      api.patch('/me', body: {'first_name': 'x' * 101}),
      _error(422, '100'),
    );
    await expectLater(api.patch('/me', body: {'phone': 'x' * 40}), _error(422, '32'));
    await expectLater(api.patch('/me', body: {'last_name': ' '}), _error(422));
    expect(await api.patch('/me', body: {'phone': ''}), isNotNull);
    empty = true;
    await expectLater(api.patch('/me', body: {'first_name': 'Ana'}), _error(404));
    // Token con base64 invalido: no hay sujeto y se rechaza.
    final bad = _api((r) async => _json([]), token: 'a.@@@.c');
    await expectLater(bad.patch('/me', body: {'first_name': 'Ana'}), throwsA(isA<ApiException>()));
  });

  test('listas: filtros por cliente y envio, y total sin content-range', () async {
    final seen = <Uri>[];
    final api = _api((r) async {
      seen.add(r.url);
      return _json([]);
    }, token: _jwt('u'));
    final orders = await api.get('/orders', queryParameters: {'customer_id': '3'}) as Map;
    expect(orders['pagination'] ?? orders['total'], anyOf(0, isA<Map>()));
    await api.get('/shipments', queryParameters: {'export_id': '4', 'id': '9'});
    await api.get('/documents', queryParameters: {'export_id': '4'});
    await api.get('/documents');
    expect(seen.any((u) => u.queryParameters['customer_id'] == 'eq.3'), isTrue);
    expect(seen.any((u) => u.queryParameters['export_id'] == 'eq.4'), isTrue);
  });

  test('subida de documentos: 413, 500 y exito con notas', () async {
    final token = _jwt('u');
    final pdf = base64Encode(utf8.encode('%PDF-1.4 contenido'));
    Future<http.Response> Function(http.Request) storage(int status) =>
        (r) async {
          if (r.url.path.contains('/storage/')) {
            return http.Response('x', status);
          }
          return _json({'id': 3, 'document_type': 'invoice'});
        };
    final body = {
      'document_type': 'other_attachment',
      'file_name': 'factura.pdf',
      'content_base64': pdf,
      'notes': '  revisar  ',
    };
    await expectLater(
      _api(storage(413), token: token).post('/exports/1/documents/upload', body: body),
      _error(422),
    );
    await expectLater(
      _api(storage(415), token: token).post('/exports/1/documents/upload', body: body),
      _error(422),
    );
    await expectLater(
      _api(storage(500), token: token).post('/exports/1/documents/upload', body: body),
      throwsA(isA<ApiException>()),
    );
    final ok = await _api(storage(200), token: token)
        .post('/exports/1/documents/upload', body: body);
    expect(ok, isA<Map>());
    // Cuerpo sin notas y registro que devuelve algo que no es un objeto.
    final notMap = _api((r) async {
      if (r.url.path.contains('/storage/')) return http.Response('ok', 200);
      return _json([1, 2]);
    }, token: token);
    await expectLater(
      notMap.post('/exports/1/documents/upload', body: {
        'document_type': 'other_attachment',
        'file_name': 'f.pdf',
        'content_base64': pdf,
      }),
      throwsA(isA<ApiException>()),
    );
  });
}
