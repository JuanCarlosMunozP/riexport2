const _defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8001/api/v1',
);

class ApiConfig {
  ApiConfig({
    String baseUrl = _defaultApiBaseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : baseUri = Uri.parse(baseUrl) {
    final isLoopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(baseUri.host.toLowerCase());
    if (!baseUri.isAbsolute ||
        !{'http', 'https'}.contains(baseUri.scheme) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        (baseUri.scheme == 'http' && !isLoopback)) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Debe ser una URL HTTPS válida; HTTP solo se permite en localhost.',
      );
    }
  }

  final Uri baseUri;
  final Duration timeout;

  Uri resolve(String path, {Map<String, String>? queryParameters}) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    final relativePath = path.replaceFirst(RegExp(r'^/+'), '');
    return baseUri
        .replace(path: basePath)
        .resolve(relativePath)
        .replace(queryParameters: queryParameters);
  }
}
