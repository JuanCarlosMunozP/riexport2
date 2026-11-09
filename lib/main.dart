import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'features/auth/state/auth_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authSession = AuthSession();
  // El backend local vive en memoria: una sesión guardada no sería válida.
  if (usesPersistentSession) await authSession.restore();
  runApp(RiExportApp(authSession: authSession));
}
