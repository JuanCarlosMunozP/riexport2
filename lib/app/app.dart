import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../backend/local_backend_client.dart';
import '../backend/supabase_backend_client.dart';
import '../core/api/api_client.dart';
import '../core/config/api_config.dart';
import '../features/auth/state/auth_session.dart';
import 'router/app_router.dart';
import 'state/app_preferences.dart';

/// Con `--dart-define=USE_REMOTE_API=true` la app usa un servidor HTTP externo.
const useRemoteApi = bool.fromEnvironment('USE_REMOTE_API');

/// Backend local disponible en desarrollo; las compilaciones release deben
/// indicar un backend remoto para no incluir las credenciales de demostración.
bool get usesPersistentSession => useRemoteApi || supabaseConfigured;

class RiExportApp extends StatefulWidget {
  const RiExportApp({super.key, required this.authSession});

  final AuthSession authSession;

  @override
  State<RiExportApp> createState() => _RiExportAppState();
}

class _RiExportAppState extends State<RiExportApp> {
  late final http.Client _backend = _createBackend();

  http.Client _createBackend() {
    if (supabaseConfigured) {
      return SupabaseBackendClient(url: supabaseUrl, anonKey: supabaseAnonKey);
    }
    if (kReleaseMode && !useRemoteApi) {
      throw StateError(
        'Configura SUPABASE_URL y SUPABASE_ANON_KEY (o USE_REMOTE_API) '
        'para compilar RiExport en modo release.',
      );
    }
    return LocalBackendClient();
  }

  late final GoRouter _router = createAppRouter(
    initialLocation: widget.authSession.isAuthenticated
        ? AppRoutes.home
        : AppRoutes.login,
    isAuthenticated: () => widget.authSession.isAuthenticated,
    refreshListenable: widget.authSession,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.authSession),
        Provider<ApiClient>(
          create: (context) => ApiClient(
            config: ApiConfig(),
            client: useRemoteApi ? null : _backend,
            tokenProvider: () => context.read<AuthSession>().accessToken,
            onUnauthorized: () => context.read<AuthSession>().expire(),
          ),
          dispose: (_, client) => client.close(),
        ),
        ChangeNotifierProvider(create: (_) => AppPreferences()),
      ],
      child: _RiExportView(router: _router),
    );
  }
}

class _RiExportView extends StatelessWidget {
  const _RiExportView({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppPreferences>(
      builder: (context, preferences, _) => MaterialApp.router(
        title: 'RiExport',
        themeMode: preferences.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF193D35),
            primary: const Color(0xFF193D35),
            secondary: const Color(0xFFB86B43),
            surface: const Color(0xFFF6F5F0),
          ),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        routerConfig: router,
      ),
    );
  }
}
