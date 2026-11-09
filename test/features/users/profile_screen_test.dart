import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/profile/presentation/profile_screen.dart';

const _profile = {
  'id': 7,
  'email': 'ana@example.com',
  'first_name': 'Ana',
  'last_name': 'Perez',
};

Widget _screen({
  Future<Object?> Function(String email)? changeEmail,
  Future<Object?> Function(Map<String, Object?> changes)? saveProfile,
}) => MaterialApp(
  home: ProfileScreen(
    loadProfile: () async => _profile,
    saveProfile: saveProfile ?? (_) async => _profile,
    changeEmail: changeEmail ?? (_) async => {'message': 'ok'},
  ),
);

// Campos: 0 nombres, 1 apellidos, 2 teléfono, 3 correo nuevo.
Finder _field(int index) => find.byType(TextFormField).at(index);

void main() {
  testWidgets('muestra el perfil y valida el correo nuevo', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _screen(
        changeEmail: (_) async {
          calls++;
          return {};
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Perez'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);

    await tester.ensureVisible(find.text('Cambiar correo').last);
    await tester.tap(find.text('Cambiar correo').last);
    await tester.pump();
    expect(find.text('Ingresa el correo nuevo.'), findsOneWidget);

    await tester.enterText(_field(3), 'ANA@example.com');
    await tester.ensureVisible(find.text('Cambiar correo').last);
    await tester.tap(find.text('Cambiar correo').last);
    await tester.pump();
    expect(find.text('Ese ya es tu correo actual.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('envia el correo nuevo y muestra la confirmacion', (
    tester,
  ) async {
    String? sent;
    await tester.pumpWidget(
      _screen(
        changeEmail: (email) async {
          sent = email;
          return {'message': 'Te enviamos un enlace de confirmación.'};
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field(3), ' nuevo@example.com ');
    await tester.ensureVisible(find.text('Cambiar correo').last);
    await tester.tap(find.text('Cambiar correo').last);
    await tester.pumpAndSettle();

    expect(sent, 'nuevo@example.com');
    expect(find.text('Te enviamos un enlace de confirmación.'), findsOneWidget);
  });

  testWidgets('muestra los errores del servidor sin cerrar la pantalla', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        changeEmail: (_) async {
          throw const ApiException(
            statusCode: 409,
            code: 'CONFLICT',
            message: 'Ya existe un usuario con ese correo electrónico.',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field(3), 'otro@example.com');
    await tester.ensureVisible(find.text('Cambiar correo').last);
    await tester.tap(find.text('Cambiar correo').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Ya existe un usuario con ese correo electrónico.'),
      findsOneWidget,
    );
    expect(find.text('Ana Perez'), findsOneWidget);
  });

  testWidgets('guarda solo los datos personales que cambiaron', (tester) async {
    Map<String, Object?>? sent;
    await tester.pumpWidget(
      _screen(
        saveProfile: (changes) async {
          sent = changes;
          return _profile;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(_field(0)).controller?.text, 'Ana');
    await tester.enterText(_field(0), ' Ana María ');
    await tester.enterText(_field(2), ' 311 555 ');
    await tester.ensureVisible(find.text('Guardar datos'));
    await tester.tap(find.text('Guardar datos'));
    await tester.pumpAndSettle();

    expect(sent, {'first_name': 'Ana María', 'phone': '311 555'});
    expect(find.text('Datos actualizados.'), findsOneWidget);
  });

  testWidgets('valida los datos personales y avisa si no hay cambios', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _screen(
        saveProfile: (_) async {
          calls++;
          return _profile;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Guardar datos'));
    await tester.tap(find.text('Guardar datos'));
    await tester.pumpAndSettle();
    expect(find.text('No hay cambios que guardar.'), findsOneWidget);

    await tester.enterText(_field(1), '');
    await tester.tap(find.text('Guardar datos'));
    await tester.pumpAndSettle();
    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('muestra el error del servidor al guardar los datos', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        saveProfile: (_) async {
          throw const ApiException(
            statusCode: 403,
            code: 'FORBIDDEN',
            message: 'No tienes permiso para esta operación.',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field(0), 'Otra');
    await tester.ensureVisible(find.text('Guardar datos'));
    await tester.tap(find.text('Guardar datos'));
    await tester.pumpAndSettle();

    expect(find.text('No tienes permiso para esta operación.'), findsOneWidget);
    expect(find.text('Guardar datos'), findsOneWidget);
  });
}
