import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/users/presentation/user_registration_screen.dart';

void main() {
  testWidgets('validates required fields before calling the API', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: UserRegistrationScreen(
          onRegister: (_) async {
            submitted = true;
          },
        ),
      ),
    );

    await tester.tap(find.text('Crear cuenta'));
    await tester.pump();

    expect(find.text('Este campo es obligatorio.'), findsNWidgets(2));
    expect(find.text('Ingresa el correo electrónico.'), findsOneWidget);
    expect(find.text('Ingresa una contraseña.'), findsOneWidget);
    expect(find.text('Confirma la contraseña.'), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('sends the API contract fields and confirms creation', (
    tester,
  ) async {
    Map<String, Object?>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: UserRegistrationScreen(
          onRegister: (request) async {
            submitted = request;
          },
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), ' Ana ');
    await tester.enterText(fields.at(1), ' García ');
    await tester.enterText(fields.at(2), ' ANA@example.com ');
    await tester.enterText(fields.at(3), ' +57 300 1234567 ');
    await tester.enterText(fields.at(4), 'Correct-Horse-9-Staple');
    await tester.enterText(fields.at(5), 'Correct-Horse-9-Staple');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(submitted, {
      'email': 'ANA@example.com',
      'password': 'Correct-Horse-9-Staple',
      'first_name': 'Ana',
      'last_name': 'García',
      'phone': '+57 300 1234567',
    });
    expect(
      find.text(
        'Cuenta creada. Si tu correo requiere confirmación, revísalo antes de iniciar sesión.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<TextFormField>(fields)
          .every((f) => f.controller?.text.isEmpty ?? true),
      isTrue,
    );
  });

  testWidgets('shows API errors without clearing entered values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserRegistrationScreen(
          onRegister: (_) async {
            throw const ApiException(
              statusCode: 409,
              code: 'CONFLICT',
              message: 'El correo electrónico ya está registrado.',
            );
          },
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ana');
    await tester.enterText(fields.at(1), 'García');
    await tester.enterText(fields.at(2), 'ana@example.com');
    await tester.enterText(fields.at(4), 'Correct-Horse-9-Staple');
    await tester.enterText(fields.at(5), 'Correct-Horse-9-Staple');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(
      find.text('El correo electrónico ya está registrado.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextFormField>(fields.at(2)).controller?.text,
      'ana@example.com',
    );
  });

  testWidgets('no envia si las contraseñas no coinciden o superan 72 bytes', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: UserRegistrationScreen(
          onRegister: (_) async {
            submitted = true;
          },
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ana');
    await tester.enterText(fields.at(1), 'García');
    await tester.enterText(fields.at(2), 'ana@example.com');
    await tester.enterText(fields.at(4), 'Una-Clave-Segura-9');
    await tester.enterText(fields.at(5), 'Otra-Clave-Distinta-9');
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);

    final larga = 'Aa1!' * 19;
    await tester.enterText(fields.at(4), larga);
    await tester.enterText(fields.at(5), larga);
    await tester.tap(find.text('Crear cuenta'));
    await tester.pump();
    expect(
      find.text('La contraseña debe ocupar máximo 72 bytes UTF-8.'),
      findsOneWidget,
    );
    expect(submitted, isFalse);
  });
}
