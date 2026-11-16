import 'dart:convert';

/// Utilidades de seguridad compartidas por toda la app (OWASP Mobile Top 10).
///
/// - M3: [jwtExpiry] / [isJwtExpired] para no usar tokens vencidos.
/// - M4: [sanitizeText] / [sanitizeJson] para neutralizar caracteres de control
///   y de reordenamiento bidireccional antes de enviar datos al backend.
/// - M5/M8: [isSafeExternalUri] para abrir solo enlaces HTTPS.
/// - M6: [redactSensitive] para que los registros no filtren credenciales.
/// - M3: [LoginThrottle] frena la fuerza bruta desde el cliente.

final RegExp _controlChars = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F'
  r'\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
);

/// Quita caracteres de control, de ancho cero y de reordenamiento
/// bidireccional (se conservan salto de línea y tabulador).
String sanitizeText(String value) => value.replaceAll(_controlChars, '');

bool _isSecretKey(String key) {
  final lower = key.toLowerCase();
  return lower.contains('password') ||
      lower.contains('token') ||
      lower.contains('secret') ||
      lower == 'code' ||
      lower == 'content_base64';
}

/// Sanea recursivamente las cadenas de un cuerpo JSON. Las claves sensibles
/// (contraseñas, tokens, códigos y archivos en base64) no se modifican para no
/// alterar su valor.
Object? sanitizeJson(Object? value, {String? key}) {
  if (value is String) {
    return key != null && _isSecretKey(key) ? value : sanitizeText(value);
  }
  if (value is List) {
    return [for (final item in value) sanitizeJson(item, key: key)];
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: sanitizeJson(entry.value, key: '${entry.key}'),
    };
  }
  return value;
}

/// Solo se abren enlaces HTTPS absolutos, sin credenciales incrustadas.
bool isSafeExternalUri(Uri? uri) =>
    uri != null &&
    uri.isAbsolute &&
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

/// Fecha de expiración (`exp`) de un JWT, o null si no es un JWT legible.
DateTime? jwtExpiry(String token) {
  try {
    final segments = token.split('.');
    if (segments.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    if (payload is! Map || payload['exp'] is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      ((payload['exp'] as num) * 1000).round(),
    );
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}

/// Verdadero solo si [token] es un JWT legible y ya venció.
bool isJwtExpired(String token, {DateTime? now}) {
  final expiry = jwtExpiry(token);
  return expiry != null && !expiry.isAfter(now ?? DateTime.now());
}

final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+');
final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]*',
);
final RegExp _secretPair = RegExp(
  r'''(password|passwd|pwd|secret|token|apikey|api_key|authorization)(["']?\s*[:=]\s*["']?)[^\s,"'&}]+''',
  caseSensitive: false,
);

/// Oculta tokens, JWT y pares `clave=valor` sensibles en un texto de registro.
String redactSensitive(String text) => text
    .replaceAll(_bearer, 'Bearer [REDACTADO]')
    .replaceAll(_jwt, '[JWT-REDACTADO]')
    .replaceAllMapped(
      _secretPair,
      (m) => '${m.group(1)}${m.group(2)}[REDACTADO]',
    );

/// Limita los intentos de inicio de sesión fallidos desde este dispositivo.
class LoginThrottle {
  LoginThrottle({
    this.maxAttempts = 5,
    this.lockout = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration lockout;
  final DateTime Function() _clock;
  int _failures = 0;
  DateTime? _lockedUntil;

  /// Segundos que faltan para poder reintentar; 0 si no hay bloqueo.
  int get secondsRemaining {
    final until = _lockedUntil;
    if (until == null) return 0;
    final left = until.difference(_clock());
    if (left <= Duration.zero) {
      _lockedUntil = null;
      _failures = 0;
      return 0;
    }
    return (left.inMilliseconds / 1000).ceil();
  }

  bool get isLocked => secondsRemaining > 0;

  void recordFailure() {
    if (isLocked) return;
    _failures++;
    if (_failures >= maxAttempts) _lockedUntil = _clock().add(lockout);
  }

  void recordSuccess() {
    _failures = 0;
    _lockedUntil = null;
  }
}
