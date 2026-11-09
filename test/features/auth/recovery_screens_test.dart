import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:riexport_app/features/auth/presentation/reset_password_screen.dart';

void main() {
  testWidgets(
    'pide el correo, valida el formato y avisa sin revelar si existe',
    (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            onRequest: (email) async => sent.add(email),
          ),
        ),
      );

      await tester.tap(find.text('Enviar código'));
      await tester.pump();
      expect(find.text('Ingresa tu correo electrónico.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'no-es-correo');
      await tester.tap(find.text('Enviar código'));
      await tester.pump();
      expect(
        find.text('Ingresa un correo electrónico válido.'),
        findsOneWidget,
      );
      expect(sent, isEmpty);

      await tester.enterText(find.byType(TextFormField), ' ana@correo.com ');
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();
      expect(sent, ['ana@correo.com']);
      expect(
        find.textContaining('Si existe una cuenta con ese correo'),
        findsOneWidget,
      );
      expect(find.text('Enviar de nuevo'), findsOneWidget);
    },
  );

  testWidgets('muestra el error del servidor al pedir el codigo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ForgotPasswordScreen(
          onRequest: (_) async {
            throw const ApiException(
              statusCode: 429,
              code: 'RATE_LIMIT_EXCEEDED',
              message:
                  'Se excedió el límite de correos. Inténtalo en unos minutos.',
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'ana@correo.com');
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(find.textContaining('límite de correos'), findsOneWidget);
    expect(find.textContaining('Si existe una cuenta'), findsNothing);
  });

  testWidgets('cambia la contrasena con el codigo y valida cada campo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, String>? received;
    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordScreen(
          initialEmail: 'ana@correo.com',
          onReset:
              ({required email, required code, required newPassword}) async {
                received = {
                  'email': email,
                  'code': code,
                  'new_password': newPassword,
                };
              },
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller?.text,
      'ana@correo.com',
    );

    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();
    expect(find.text('Ingresa el código de 6 dígitos.'), findsOneWidget);
    expect(find.text('Ingresa una contraseña.'), findsOneWidget);

    await tester.enterText(fields.at(1), '12ab34'); // solo dígitos
    expect(tester.widget<TextFormField>(fields.at(1)).controller?.text, '1234');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'ClaveNueva-2026');
    await tester.enterText(fields.at(3), 'otra-distinta');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(received, isNull);

    await tester.enterText(fields.at(3), 'ClaveNueva-2026');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();
    expect(received, {
      'email': 'ana@correo.com',
      'code': '123456',
      'new_password': 'ClaveNueva-2026',
    });
  });

  testWidgets('muestra el error de codigo vencido sin cerrar la pantalla', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordScreen(
          initialEmail: 'ana@correo.com',
          onReset:
              ({required email, required code, required newPassword}) async {
                throw const ApiException(
                  statusCode: 400,
                  code: 'INVALID_CODE',
                  message:
                      'El código no es válido o ya venció. Solicita uno nuevo.',
                );
              },
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'ClaveNueva-2026');
    await tester.enterText(fields.at(3), 'ClaveNueva-2026');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no es válido o ya venció'), findsOneWidget);
    expect(find.text('Cambiar contraseña'), findsWidgets);
  });
}
