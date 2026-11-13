import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/auth/presentation/confirm_email_screen.dart';
import 'package:riexport_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:riexport_app/features/auth/presentation/login_screen.dart';
import 'package:riexport_app/features/auth/presentation/reset_password_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_form_screen.dart';
import 'package:riexport_app/features/notifications/presentation/notification_center_screen.dart';

ApiException _api(String m) =>
    ApiException(statusCode: 400, code: 'e', message: m);

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpRouted(
  WidgetTester tester,
  Widget screen, {
  String location = '/x',
  Size size = const Size(900, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/x', builder: (_, _) => screen),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('LOGIN')),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const Scaffold(body: Text('OLVIDE')),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  group('ConfirmEmailScreen', () {
    testWidgets('errores de API y genericos, y volver al acceso', (tester) async {
      var mode = 'api';
      await pumpRouted(
        tester,
        ConfirmEmailScreen(
          initialEmail: 'a@b.co',
          onConfirm: ({required email, required code}) async {
            if (mode == 'api') throw _api('Codigo vencido');
            throw StateError('x');
          },
        ),
      );
      await tester.enterText(find.byType(TextFormField).last, '123456');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Codigo vencido'), findsOneWidget);
      mode = 'boom';
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(
        find.text('No fue posible confirmar el correo. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Volver a iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });
  });

  group('ForgotPasswordScreen', () {
    testWidgets('error generico y volver al acceso', (tester) async {
      await pumpRouted(
        tester,
        ForgotPasswordScreen(onRequest: (email) async => throw StateError('x')),
      );
      await tester.enterText(find.byType(TextFormField), 'a@b.co');
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();
      expect(
        find.text('No fue posible enviar el código. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Volver a iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });
  });

  group('LoginScreen', () {
    testWidgets('error generico, envio con Enter y aviso inicial', (
      tester,
    ) async {
      var calls = 0;
      await pumpRouted(
        tester,
        LoginScreen(
          notice: 'Tu sesión expiró.',
          onLogin: (email, password) async {
            calls++;
            throw StateError('x');
          },
        ),
        // QA-03 (corregido): a 900 px el panel de marca ya no desborda.
        size: const Size(900, 1000),
      );
      expect(find.text('Tu sesión expiró.'), findsOneWidget);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'a@b.co');
      await tester.enterText(fields.at(1), 'Secreto1234!');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text('No fue posible iniciar sesión. Inténtalo de nuevo.'),
        findsOneWidget,
      );
    });
  });

  group('ResetPasswordScreen', () {
    testWidgets('alterna la visibilidad y pide otro codigo', (tester) async {
      await pumpRouted(
        tester,
        ResetPasswordScreen(
          initialEmail: 'a@b.co',
          onReset: ({required email, required code, required newPassword}) async {},
        ),
      );
      final toggle = find.byTooltip('Mostrar contraseña');
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle.first);
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.byIcon(Icons.visibility_outlined).first);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Solicitar otro código'));
      await tester.tap(find.text('Solicitar otro código'));
      await tester.pumpAndSettle();
      expect(find.text('OLVIDE'), findsOneWidget);
    });
  });

  group('ShipmentFormScreen', () {
    Widget form({
      Future<List<Map<String, dynamic>>> Function()? loadExports,
      Future<void> Function(Map<String, dynamic>)? onSubmit,
      Map<String, dynamic>? initial,
    }) => MaterialApp(
      home: ShipmentFormScreen(
        loadExports: loadExports,
        onSubmit: onSubmit ?? (body) async {},
        initial: initial,
      ),
    );

    testWidgets('errores al cargar las exportaciones', (tester) async {
      await tester.pumpWidget(
        form(loadExports: () async => throw _api('Sin acceso')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin acceso'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        form(loadExports: () async => throw StateError('x')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudieron cargar las exportaciones.'),
        findsOneWidget,
      );
    });

    testWidgets('sin exportacion no se guarda; cambia exportacion y modalidad', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final saved = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        form(loadExports: () async => [], onSubmit: (b) async => saved.add(b)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Selecciona la exportación del envío.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        form(
          loadExports: () async => [
            {'id': 1, 'order_number': 'PED-1', 'customer_name': 'A'},
            {'id': 2, 'order_number': 'PED-2', 'customer_name': 'B'},
          ],
          onSubmit: (b) async => saved.add(b),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shipment-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('PED-2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shipment-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aéreo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(saved.single['export_id'], 2);
      expect(saved.single['transport_mode'], 'air');
    });

    testWidgets('el guardado muestra errores de API y genericos', (tester) async {
      var api = true;
      await tester.pumpWidget(
        form(
          initial: {'id': 1, 'carrier': 'X', 'status': 'planned'},
          onSubmit: (b) async {
            if (api) throw _api('Guia duplicada');
            throw StateError('x');
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Guia duplicada'), findsOneWidget);
      api = false;
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo guardar el envío.'), findsOneWidget);
    });
  });

  group('NotificationCenterScreen', () {
    testWidgets('error generico al cargar y recarga con tirar para refrescar', (
      tester,
    ) async {
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterScreen(
            loadNotifications: ({unreadOnly = false}) async {
              if (fail) throw StateError('x');
              return [
                {
                  'id': 1,
                  'title': 'Aviso',
                  'message': 'Detalle',
                  'notification_type': 'low_stock',
                },
              ];
            },
            markRead: (id) async {},
            markAllRead: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudieron cargar las notificaciones.'),
        findsOneWidget,
      );
      fail = false;
      await tester.pumpWidget(const SizedBox());
      fail = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterScreen(
            loadNotifications: ({unreadOnly = false}) async => [
              {'id': 1, 'title': 'Aviso', 'notification_type': 'low_stock'},
            ],
            markRead: (id) async {},
            markAllRead: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.fling(find.text('Aviso'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
    });

    testWidgets('marcar todas como leidas: errores de API y genericos', (
      tester,
    ) async {
      var api = true;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterScreen(
            loadNotifications: ({unreadOnly = false}) async => [
              {'id': 1, 'title': 'Aviso', 'read_at': null},
            ],
            markRead: (id) async {},
            markAllRead: () async {
              if (api) throw _api('Sin permiso');
              throw StateError('x');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Marcar todas como leídas'));
      await brief(tester);
      expect(find.text('Sin permiso'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      api = false;
      await tester.tap(find.byTooltip('Marcar todas como leídas'));
      await brief(tester);
      expect(find.text('No se pudieron marcar como leídas.'), findsOneWidget);
    });
  });
}
