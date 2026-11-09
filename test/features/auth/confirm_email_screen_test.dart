import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/features/auth/presentation/confirm_email_screen.dart';

void main() {
  testWidgets('valida el código y confirma el correo', (tester) async {
    String? sentEmail;
    String? sentCode;
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => ConfirmEmailScreen(
                initialEmail: 'ana@correo.com',
                onConfirm: ({required email, required code}) async {
                  sentEmail = email;
                  sentCode = code;
                },
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    expect(find.text('Ingresa el código de 6 dígitos.'), findsOneWidget);
    expect(sentCode, isNull);

    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(sentEmail, 'ana@correo.com');
    expect(sentCode, '123456');
    expect(find.textContaining('Correo confirmado'), findsOneWidget);
  });
}
