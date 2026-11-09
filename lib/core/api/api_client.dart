import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({
    required this.config,
    http.Client? client,
    String? Function()? tokenProvider,
    String Function()? requestIdProvider,
    void Function()? onUnauthorized,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider,
       _requestIdProvider = requestIdProvider,
       _onUnauthorized = onUnauthorized;

  final ApiConfig config;
  final http.Client _client;
  final String? Function()? _tokenProvider;
  final String Function()? _requestIdProvider;

  /// Se invoca cuando el servidor responde 401 a una petición que llevaba token
  /// (sesión vencida o revocada). No se invoca en el inicio de sesión.
  final void Function()? _onUnauthorized;
  int _requestSequence = 0;

  Future<Object?> get(String path, {Map<String, String>? queryParameters}) =>
      _send('GET', path, queryParameters: queryParameters);

  /// [signalUnauthorized] en falso evita que un 401 de esta petición cierre la
  /// sesión como "vencida" (por ejemplo, al cerrar sesión con un token ya vencido).
  Future<Object?> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool signalUnauthorized = true,
  }) => _send(
    'POST',
    path,
    body: body,
    idempotencyKey: idempotencyKey,
    signalUnauthorized: signalUnauthorized,
  );

  Future<Object?> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<Object?> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<Object?> delete(String path, {Object? body}) =>
      _send('DELETE', path, body: body);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Object? body,
    String? idempotencyKey,
    bool signalUnauthorized = true,
  }) async {
    final requestId = _requestIdProvider?.call() ?? _newRequestId();
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Request-ID': requestId,
    };
    final token = _tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = token.startsWith('Bearer ')
          ? token
          : 'Bearer $token';
    }
    if (body != null) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) {
      headers['Idempotency-Key'] = idempotencyKey;
    }

    final request = http.Request(
      method,
      config.resolve(path, queryParameters: queryParameters),
    )..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    try {
      final responseFuture = _client
          .send(request)
          .then(http.Response.fromStream);
      final response = await responseFuture.timeout(config.timeout);
      try {
        return _parseResponse(response, requestId);
      } on ApiException catch (error) {
        if (signalUnauthorized &&
            error.statusCode == 401 &&
            token != null &&
            token.isNotEmpty) {
          _onUnauthorized?.call();
        }
        rethrow;
      }
    } on TimeoutException {
      throw ApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'La solicitud tardó demasiado. Inténtalo de nuevo.',
        requestId: requestId,
      );
    } on http.ClientException {
      throw ApiException(
        code: 'API_CONNECTION_ERROR',
        message: 'No fue posible conectar con el servidor.',
        requestId: requestId,
      );
    }
  }

  Object? _parseResponse(http.Response response, String requestId) {
    final responseRequestId = _headerValue(response.headers, 'x-request-id');
    if (response.statusCode == 204) return null;

    Object? payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw ApiException(
            statusCode: response.statusCode,
            code: 'INVALID_RESPONSE',
            message: 'El servidor devolvió una respuesta no válida.',
            requestId: responseRequestId ?? requestId,
          );
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpException(response, payload, responseRequestId ?? requestId);
    }
    if (response.body.isEmpty) return null;
    return payload;
  }

  ApiException _httpException(
    http.Response response,
    Object? payload,
    String requestId,
  ) {
    if (payload is Map<String, dynamic> && payload['error'] is Map) {
      final error = Map<String, dynamic>.from(payload['error'] as Map);
      final rawDetails = error['details'];
      final details = rawDetails is List
          ? rawDetails.whereType<Map>().map((detail) {
              final values = Map<String, dynamic>.from(detail);
              return ApiErrorDetail(
                field: values['field'] is String
                    ? values['field'] as String
                    : null,
                code: values['code'] is String
                    ? values['code'] as String
                    : 'invalid_value',
                message: values['message'] is String
                    ? values['message'] as String
                    : 'El valor no es válido.',
              );
            }).toList()
          : const <ApiErrorDetail>[];

      return ApiException(
        statusCode: response.statusCode,
        code: error['code'] is String
            ? error['code'] as String
            : _fallbackCode(response.statusCode),
        // Las pantallas muestran `message`: ante un 422 con detalle por campo se
        // usa ese texto (más accionable que "datos no válidos").
        message: response.statusCode == 422 && details.isNotEmpty
            ? details.first.message
            : error['message'] is String
            ? error['message'] as String
            : _fallbackMessage(response.statusCode),
        details: details,
        requestId: error['request_id'] is String
            ? error['request_id'] as String
            : requestId,
      );
    }

    return ApiException(
      statusCode: response.statusCode,
      code: _fallbackCode(response.statusCode),
      message: _fallbackMessage(response.statusCode),
      requestId: requestId,
    );
  }

  String _newRequestId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return 'req_${timestamp}_${_requestSequence++}';
  }

  String _fallbackCode(int statusCode) => switch (statusCode) {
    400 => 'BAD_REQUEST',
    401 => 'UNAUTHORIZED',
    403 => 'FORBIDDEN',
    404 => 'NOT_FOUND',
    409 => 'CONFLICT',
    422 => 'VALIDATION_ERROR',
    429 => 'RATE_LIMIT_EXCEEDED',
    >= 500 => 'INTERNAL_SERVER_ERROR',
    _ => 'HTTP_ERROR',
  };

  String _fallbackMessage(int statusCode) => switch (statusCode) {
    401 => 'Se requiere autenticación válida.',
    403 => 'No tienes permiso para esta operación.',
    404 => 'El recurso solicitado no existe.',
    409 => 'La solicitud entra en conflicto con el estado actual.',
    422 => 'La solicitud contiene datos no válidos.',
    429 => 'Se excedió el límite de solicitudes.',
    >= 500 => 'Ocurrió un error inesperado.',
    _ => 'La solicitud no pudo completarse.',
  };

  String? _headerValue(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  void close() => _client.close();
}
