class ApiErrorDetail {
  const ApiErrorDetail({this.field, required this.code, required this.message});

  final String? field;
  final String code;
  final String message;
}

class ApiException implements Exception {
  const ApiException({
    this.statusCode,
    required this.code,
    required this.message,
    this.details = const [],
    this.requestId,
  });

  final int? statusCode;
  final String code;
  final String message;
  final List<ApiErrorDetail> details;
  final String? requestId;

  @override
  String toString() => 'ApiException($code): $message';
}
