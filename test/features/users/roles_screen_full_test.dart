import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/roles/presentation/role_create_dialog.dart';
import 'package:riexport_app/features/roles/presentation/roles_screen.dart';

Map<String, dynamic> _role(int id, String name, {bool active = true}) => {
  'id': id,
  'name': name,
  'description': 'Desc $name',
  'is_active': active,
  'permission_codes': ['users.read'],
};

class _Fixture {
  _Fixture({this.createError, this.updateError, this.permError, this.deactError});

  Object? createError;
  Object? updateError;
  Object? permError;
  Object? deactError;
  Object? rolesResponse;
  Object? loadError;
  int loads = 0;
  List<Map<String, dynamic>> roles = [
    _role(1, 'administrador'),
    _role(2, 'operador'),
    _role(3, 'viejo', active: false),
  ];
  final calls = <String>[];

  Widget app() => MaterialApp(
    home: RolesScreen(
      loadRoles: () async {
        loads++;
        if (loadError != null) throw loadError!;
        return rolesResponse ?? {'items': roles};
      },
      loadPermissions: () async => {
        'items': [
          {'code': 'users.read', 'description': 'Leer'},
          {'code': 'users.update', 'description': 'Editar'},
        ],
      },
      createRole: (request) async {
        calls.add('create:${request['name']}');
        if (createError != null) throw createError!;
        roles.add(_role(9, request['name'] as String));
        return {'id': 9};
      },
      updateRole: (id, changes) async {
        calls.add('update:$id:${changes.keys.join(',')}');
        if (updateError != null) throw updateError!;
        return null;
      },
      setRolePermissions: (id, codes) async {
        calls.add('perm:$id:${codes.join(',')}');
        if (permError != null) throw permError!;
        return null;
      },
      deactivateRole: (id) async {
        calls.add('deact:$id');
        if (deactError != null) throw deactError!;
        return null;
      },
    ),
  );
}

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void clearSnacks(WidgetTester tester) => tester
    .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
    .clearSnackBars();

void main() {

  testWidgets('RoleCreateDialog valida, cancela y devuelve el rol', (
    tester,
  ) async {
    Map<String, Object?>? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<Map<String, Object?>>(
                context: context,
                builder: (_) => const RoleCreateDialog(),
              );
              closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa un nombre para el rol.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);

    closed = false;
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '  nuevo  ');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(result, {'name': 'nuevo', 'description': null});

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'otro');
    await tester.enterText(find.byType(TextFormField).at(1), ' detalle ');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(result, {'name': 'otro', 'description': 'detalle'});
  });

  testWidgets('crear rol: exito, error de API y error generico', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fx = _Fixture();
    await tester.pumpWidget(fx.app());
    await brief(tester);

    Future<void> create(String name) async {
      clearSnacks(tester);
      await tester.tap(find.byTooltip('Crear rol'));
      await brief(tester);
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(dialogFields.last, 'x');
      await tester.enterText(dialogFields.first, name);
      await tester.tap(find.text('Crear'));
      await brief(tester);
    }

    await create('nuevo_rol');
    expect(fx.calls, contains('create:nuevo_rol'));

    fx.createError = const ApiException(statusCode: 409, code: 'e', message: 'Duplicado');
    await create('dup');
    expect(find.text('Duplicado'), findsOneWidget);

    fx.createError = StateError('boom');
    await create('otro');
    expect(find.text('No fue posible crear el rol.'), findsOneWidget);

    // Cancelar el dialogo no llama al backend.
    final before = fx.calls.length;
    await tester.tap(find.byTooltip('Crear rol'));
    await brief(tester);
    await tester.tap(find.text('Cancelar'));
    await brief(tester);
    expect(fx.calls.length, before);
  });

  testWidgets('editar datos, permisos y desactivar con sus errores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fx = _Fixture();
    await tester.pumpWidget(fx.app());
    await brief(tester);

    // Cambiar al rol operador desde el desplegable.
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await brief(tester);
    await tester.tap(find.text('operador').last);
    await brief(tester);
    expect(find.text('Desactivar rol'), findsOneWidget);

    Future<void> tapText(String text) async {
      clearSnacks(tester);
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await brief(tester);
    }

    // Sin cambios: no llama al backend.
    await tapText('Guardar datos');
    expect(fx.calls.where((c) => c.startsWith('update')), isEmpty);

    // Nombre vacio.
    await tester.enterText(find.byType(TextFormField).at(0), '  ');
    await tapText('Guardar datos');
    expect(find.text('El nombre del rol es obligatorio.'), findsOneWidget);

    // Cambia nombre y descripcion (descripcion vacia => null).
    await tester.enterText(find.byType(TextFormField).at(0), 'operador2');
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tapText('Guardar datos');
    expect(fx.calls, contains('update:2:name,description'));
    expect(find.text('Rol actualizado.'), findsOneWidget);

    fx.updateError = const ApiException(statusCode: 400, code: 'e', message: 'Nombre malo');
    await tester.enterText(find.byType(TextFormField).at(0), 'zzz');
    await tapText('Guardar datos');
    expect(find.text('Nombre malo'), findsOneWidget);
    fx.updateError = StateError('x');
    await tester.enterText(find.byType(TextFormField).at(0), 'yyy');
    await tapText('Guardar datos');
    expect(
      find.text('No fue posible guardar los cambios del rol.'),
      findsOneWidget,
    );

    // Permisos.
    await tapText('users.update');
    await tapText('Guardar permisos');
    expect(find.text('Permisos del rol actualizados.'), findsOneWidget);
    expect(fx.calls.any((c) => c.startsWith('perm:2:')), isTrue);
    fx.permError = const ApiException(statusCode: 403, code: 'e', message: 'Sin permiso');
    await tapText('Guardar permisos');
    expect(find.text('Sin permiso'), findsOneWidget);
    fx.permError = StateError('x');
    await tapText('Guardar permisos');
    expect(find.text('No fue posible actualizar los permisos.'), findsOneWidget);

    // Desactivar: cancelar, error de API, error generico y exito.
    await tapText('Desactivar rol');
    await tester.tap(find.text('Cancelar'));
    await brief(tester);
    expect(fx.calls.where((c) => c.startsWith('deact')), isEmpty);
    fx.deactError = const ApiException(statusCode: 409, code: 'e', message: 'En uso');
    await tapText('Desactivar rol');
    await tester.tap(find.text('Desactivar'));
    await brief(tester);
    expect(find.text('En uso'), findsOneWidget);
    fx.deactError = StateError('x');
    await tapText('Desactivar rol');
    await tester.tap(find.text('Desactivar'));
    await brief(tester);
    expect(find.text('No fue posible desactivar el rol.'), findsOneWidget);
    fx.deactError = null;
    await tapText('Desactivar rol');
    await tester.tap(find.text('Desactivar'));
    await brief(tester);
    expect(find.text('Rol desactivado.'), findsOneWidget);

    // Rol inactivo: permisos bloqueados.
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await brief(tester);
    await tester.tap(find.textContaining('viejo').last);
    await brief(tester);
    expect(find.text('Inactivo'), findsOneWidget);
    // Refrescar.
    final loadsBefore = fx.loads;
    await tester.tap(find.byTooltip('Actualizar roles'));
    await brief(tester);
    expect(fx.loads, greaterThan(loadsBefore));
  });

  testWidgets('el administrador no se renombra ni desactiva', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fx = _Fixture();
    await tester.pumpWidget(fx.app());
    await tester.pumpAndSettle();
    expect(find.text('Desactivar rol'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
  });

  testWidgets('errores de carga: API, formato y generico, con reintento', (
    tester,
  ) async {
    final fx = _Fixture()
      ..loadError = const ApiException(statusCode: 500, code: 'e', message: 'Caido');
    await tester.pumpWidget(fx.app());
    await tester.pumpAndSettle();
    expect(find.text('Caido'), findsOneWidget);

    fx.loadError = const FormatException('x');
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Respuesta inválida del servidor.'), findsOneWidget);

    fx.loadError = StateError('x');
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No fue posible cargar los roles.'), findsOneWidget);

    fx.loadError = null;
    fx.rolesResponse = {'items': ['no-es-mapa']};
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Respuesta inválida del servidor.'), findsOneWidget);

    fx.rolesResponse = {'items': <Map<String, dynamic>>[]};
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No hay roles disponibles.'), findsOneWidget);
  });
}
