import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/users/presentation/users_screen.dart';

void main() {
  testWidgets('loads users, debounces search and applies status filter', (
    tester,
  ) async {
    final calls = <({String? query, bool? isActive, int offset})>[];
    await tester.pumpWidget(
      MaterialApp(
        home: UsersScreen(
          loadUsers:
              ({required limit, required offset, query, isActive}) async {
                calls.add((query: query, isActive: isActive, offset: offset));
                return _page([
                  _user(1, 'ana@example.com', isActive: isActive ?? true),
                ], total: 1);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(calls.length, 1);

    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pump(const Duration(milliseconds: 349));
    expect(calls.length, 1);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    expect(calls.last.query, 'ana');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inactivos').last);
    await tester.pumpAndSettle();

    expect(calls.last.isActive, isFalse);
    expect(find.text('Inactivo'), findsOneWidget);
  });

  testWidgets('paginates results', (tester) async {
    final offsets = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: UsersScreen(
          loadUsers:
              ({required limit, required offset, query, isActive}) async {
                offsets.add(offset);
                return offset == 0
                    ? _page(
                        List.generate(
                          20,
                          (index) => _user(index + 1, 'u$index@test.co'),
                        ),
                        total: 21,
                      )
                    : _page([_user(21, 'last@test.co')], total: 21);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mostrando 1–20 de 21'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();

    expect(offsets, [0, 20]);
    expect(find.text('last@test.co'), findsOneWidget);
  });

  testWidgets('edits and deactivates a user from the row actions', (
    tester,
  ) async {
    Map<String, Object?>? updated;
    var editCalls = 0;
    var active = true;
    var deactivationCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UsersScreen(
          loadUsers:
              ({required limit, required offset, query, isActive}) async =>
                  _page([
                    _user(5, 'ana@example.com', isActive: active),
                  ], total: 1),
          editUser: (user) async {
            expect(user['id'], 5);
            editCalls++;
            updated = {'first_name': 'Ana María'};
            return true;
          },
          deactivateUser: (userId) async {
            expect(userId, 5);
            deactivationCalls++;
            active = false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Acciones del usuario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(editCalls, 1);
    expect(updated?['first_name'], 'Ana María');

    await tester.tap(find.byTooltip('Acciones del usuario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
    await tester.pumpAndSettle();

    expect(deactivationCalls, 1);
    expect(find.text('Inactivo'), findsOneWidget);
  });

  testWidgets('shows an empty result message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UsersScreen(
          loadUsers:
              ({required limit, required offset, query, isActive}) async =>
                  _page([], total: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay usuarios para mostrar'), findsOneWidget);
  });

  testWidgets('shows API permission errors and allows retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UsersScreen(
          loadUsers:
              ({required limit, required offset, query, isActive}) async {
                attempts++;
                throw const ApiException(
                  statusCode: 403,
                  code: 'FORBIDDEN',
                  message: 'No tienes permiso para esta operación.',
                );
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No tienes permiso para esta operación.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('un usuario inactivo se reactiva desde las acciones de la fila', (
    tester,
  ) async {
    var active = false;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UsersScreen(
          loadUsers:
              ({required limit, required offset, query, isActive}) async =>
                  _page([
                    _user(5, 'ana@example.com', isActive: active),
                  ], total: 1),
          reactivateUser: (userId) async {
            expect(userId, 5);
            calls++;
            active = true;
          },
          deactivateUser: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inactivo'), findsOneWidget);

    await tester.tap(find.byTooltip('Acciones del usuario'));
    await tester.pumpAndSettle();
    expect(find.text('Desactivar'), findsNothing);
    await tester.tap(find.text('Reactivar'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Usuario reactivado.'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
  });
}

Map<String, Object?> _page(
  List<Map<String, Object?>> items, {
  required int total,
}) => {
  'items': items,
  'pagination': {'limit': 20, 'offset': 0, 'total': total},
};

Map<String, Object?> _user(int id, String email, {bool isActive = true}) => {
  'id': id,
  'email': email,
  'first_name': 'Ana',
  'last_name': 'Pérez',
  'phone': null,
  'role_id': 3,
  'is_active': isActive,
  'created_at': '2026-10-02T10:00:00Z',
  'updated_at': '2026-10-02T10:00:00Z',
};
