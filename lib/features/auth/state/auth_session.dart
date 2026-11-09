import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

abstract interface class SessionTokenStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}

class SecureSessionTokenStore implements SessionTokenStore {
  SecureSessionTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}

class AuthSession extends ChangeNotifier {
  AuthSession({SessionTokenStore? tokenStore})
    : _tokenStore = tokenStore ?? SecureSessionTokenStore();

  final SessionTokenStore _tokenStore;
  String? _accessToken;
  bool _expired = false;

  String? get accessToken => _accessToken;

  /// Verdadero si la última vez que se cerró la sesión fue porque el servidor
  /// rechazó el token (vencido o revocado); la pantalla de acceso lo avisa.
  bool get sessionExpired => _expired;
  bool get isAuthenticated => _accessToken != null;

  Future<void> restore() async {
    try {
      final token = await _tokenStore.readToken();
      if (token != null && _isNotExpiredJwt(token)) {
        _accessToken = token;
      } else if (token != null) {
        await _tokenStore.deleteToken();
      }
    } catch (_) {
      _accessToken = null;
    }
    notifyListeners();
  }

  Future<void> authenticate(
    ApiClient apiClient, {
    required String email,
    required String password,
  }) async {
    final response = await apiClient.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    if (response is! Map<String, dynamic> ||
        response['access_token'] is! String ||
        (response['access_token'] as String).isEmpty ||
        response['token_type'] is! String ||
        (response['token_type'] as String).toLowerCase() != 'bearer' ||
        !_isNotExpiredJwt(response['access_token'] as String)) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message:
            'El servidor devolvió una respuesta de autenticación no válida.',
      );
    }
    final accessToken = response['access_token'] as String;
    await _tokenStore.writeToken(accessToken);
    _accessToken = accessToken;
    _expired = false;
    notifyListeners();
  }

  /// Cierra la sesión porque el servidor rechazó el token. Idempotente: varias
  /// respuestas 401 simultáneas solo cierran la sesión una vez.
  Future<void> expire() async {
    if (_accessToken == null) return;
    _expired = true;
    await clear();
  }

  Future<bool> clear() async {
    _accessToken = null;
    notifyListeners();
    try {
      await _tokenStore.deleteToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isNotExpiredJwt(String token) {
    try {
      final segments = token.split('.');
      if (segments.length != 3) return false;
      final payloadBytes = base64Url.decode(base64Url.normalize(segments[1]));
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is! Map<String, dynamic> || payload['exp'] is! num) {
        return false;
      }
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        ((payload['exp'] as num) * 1000).round(),
      );
      return expiry.isAfter(DateTime.now());
    } on FormatException {
      return false;
    } on RangeError {
      return false;
    }
  }
}
