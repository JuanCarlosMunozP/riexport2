import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/features/roles/presentation/roles_screen.dart';

void main() {
  testWidgets('loads the permission catalog and saves role assignments', (
    tester,
  ) async {
    List<String> assigned = [
      'roles.read',
      'roles.create',
      'roles.update',
      'roles.permissions.update',
      'users.read',
    ];
    List<String>? savedCodes;
    await tester.pumpWidget(
      MaterialApp(
        home: RolesScreen(
          loadRoles: () async => {
            'items': [
              {
                'id': 1,
                'name': 'administrador',
                'description': 'Administra la plataforma.',
                'is_active': true,
                'permission_codes': assigned,
              },
            ],
          },
          loadPermissions: () async => {
            'items': [
              for (final code in [
                'roles.read',
                'roles.create',
                'roles.update',
                'roles.permissions.update',
                'users.read',
              ])
                {'code': code, 'description': 'Permite $code.'},
            ],
          },
          createRole: (_) async => null,
          updateRole: (_, _) async => null,
          setRolePermissions: (_, codes) async {
            savedCodes = codes;
            assigned = codes;
            return null;
          },
          deactivateRole: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Roles y permisos'), findsOneWidget);
    expect(find.text('administrador'), findsNWidgets(2));
    await tester.ensureVisible(find.text('users.read'));
    await tester.tap(find.text('users.read'));
    await tester.ensureVisible(find.text('Guardar permisos'));
    await tester.tap(find.text('Guardar permisos'));
    await tester.pumpAndSettle();

    expect(savedCodes, isNot(contains('users.read')));
    expect(savedCodes, contains('roles.permissions.update'));
  });
}
