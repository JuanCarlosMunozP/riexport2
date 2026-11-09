import 'package:riexport_app/backend/local_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/config/api_config.dart';

late LocalBackendTestContext _context;

ApiClient get api => _context.api;

String? get token => _context.token;

set token(String? value) => _context.token = value;

Future<void> setUpLocalBackendTest() async {
  _context = LocalBackendTestContext();
  await _context.setUp();
}

class LocalBackendTestContext {
  String? token;

  late final ApiClient api = ApiClient(
    config: ApiConfig(),
    client: LocalBackendClient(),
    tokenProvider: () => token,
  );

  Future<void> setUp() async {
    final login =
        await api.post(
              '/auth/login',
              body: {'email': 'admin@riexport.com', 'password': 'Admin123!'},
            )
            as Map<String, dynamic>;
    token = login['access_token'] as String;
  }
}
