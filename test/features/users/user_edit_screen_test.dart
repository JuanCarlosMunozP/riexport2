import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/users/presentation/user_edit_screen.dart';

void main() {
  testWidgets('loads user data and submits only changed fields', (
    tester,
  ) async {
    Map<String, Object?>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: UserEditScreen(
          user: _user,
          onSave: (changes) async => submitted = changes,
        ),
      ),
    );

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Ana María');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(submitted, {'first_name': 'Ana María'});
  });

  testWidgets('validates fields before calling the update endpoint', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UserEditScreen(user: _user, onSave: (_) async => calls++),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('el selector de rol muestra nombres y envia solo el id elegido', (
    tester,
  ) async {
    Map<String, Object?>? sent;
    await tester.pumpWidget(
      _pickerScreen(
        viewer: {
          'id': 99,
          'permission_codes': ['users.assign_role'],
        },
        onSave: (changes) => sent = changes,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rol'), findsWidgets);
    expect(find.text('ID del rol'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestor Comercial').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(sent, {'role_id': 4});
  });

  testWidgets('sin el permiso users.assign_role el selector queda bloqueado', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pickerScreen(
        viewer: {
          'id': 99,
          'permission_codes': ['users.update'],
        },
        onSave: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No tienes permiso para cambiar roles.'), findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(dropdown.onChanged, isNull);
  });

  testWidgets('nadie cambia su propio rol desde la pantalla', (tester) async {
    await tester.pumpWidget(
      _pickerScreen(
        viewer: {
          'id': 5, // el mismo usuario que se edita
          'permission_codes': ['users.assign_role'],
        },
        onSave: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No puedes cambiar tu propio rol.'), findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(dropdown.onChanged, isNull);
  });

  testWidgets('muestra el error de la base al cambiar el rol', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserEditScreen(
          user: _user,
          onSave: (_) async {
            throw const ApiException(
              statusCode: 409,
              code: 'CONFLICT',
              message:
                  'Solo un administrador puede asignar o quitar el rol administrador.',
            );
          },
          loadRoles: () async => [
            {'id': 1, 'name': 'administrador'},
            {'id': 3, 'name': 'cliente'},
          ],
          loadViewer: () async => {
            'id': 99,
            'permission_codes': ['users.assign_role'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administrador').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Solo un administrador puede asignar o quitar el rol administrador.',
      ),
      findsOneWidget,
    );
  });
}

Widget _pickerScreen({
  required Map<String, dynamic> viewer,
  required void Function(Map<String, Object?> changes) onSave,
  Map<String, dynamic>? user,
}) => MaterialApp(
  home: UserEditScreen(
    user: user ?? _user,
    onSave: (changes) async => onSave(changes),
    loadRoles: () async => [
      {'id': 1, 'name': 'administrador'},
      {'id': 3, 'name': 'cliente'},
      {'id': 4, 'name': 'usuario_comercial'},
    ],
    loadViewer: () async => viewer,
  ),
);

final Map<String, dynamic> _user = {
  'id': 5,
  'first_name': 'Ana',
  'last_name': 'Pérez',
  'email': 'ana@example.com',
  'phone': null,
  'role_id': 3,
  'is_active': true,
};
