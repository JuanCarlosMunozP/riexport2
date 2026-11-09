import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/app/app.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';

class _MemoryTokenStore implements SessionTokenStore {
  String? value;

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async => value = token;

  @override
  Future<void> deleteToken() async => value = null;
}

void main() {
  testWidgets(
    'catalogo de productos de punta a punta: registrar, editar, inactivar y reactivar',
    (tester) async {
      tester.view.physicalSize = const Size(700, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = AuthSession(tokenStore: _MemoryTokenStore());
      addTearDown(session.dispose);

      await tester.pumpWidget(RiExportApp(authSession: session));
      await tester.pumpAndSettle();
      final login = find.byType(TextFormField);
      await tester.enterText(login.at(0), 'admin@riexport.com');
      await tester.enterText(login.at(1), 'Admin123!');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Catálogo de productos'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay productos registrados'), findsOneWidget);

      // Registrar un café con una certificación.
      await tester.tap(find.byTooltip('Registrar producto'));
      await tester.pumpAndSettle();
      final form = find.byType(TextFormField);
      await tester.enterText(form.at(0), 'Caturra');
      await tester.enterText(form.at(1), 'Excelso');
      await tester.enterText(form.at(2), '0901.11');
      await tester.enterText(form.at(4), '11.5');
      await tester.tap(find.text('Orgánico'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Producto registrado.'), findsOneWidget);
      expect(find.text('Caturra'), findsOneWidget);
      expect(find.textContaining('Humedad 11.5 %'), findsOneWidget);
      expect(find.text('Orgánico'), findsWidgets);

      // Un duplicado se rechaza con el mensaje de la regla.
      await tester.tap(find.byTooltip('Registrar producto'));
      await tester.pumpAndSettle();
      final again = find.byType(TextFormField);
      await tester.enterText(again.at(0), 'caturra');
      await tester.enterText(again.at(1), 'EXCELSO');
      await tester.enterText(again.at(4), '10');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ya existe un producto con ese tipo, variedad y calidad.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Editar la calidad.
      await tester.tap(find.byTooltip('Acciones del producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar producto'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), 'Supremo');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Producto actualizado.'), findsOneWidget);
      expect(find.textContaining('Supremo'), findsOneWidget);

      // Inactivar: sale de "Activos" y aparece en "Inactivos".
      await tester.tap(find.byTooltip('Acciones del producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivar').last);
      await tester.pumpAndSettle();
      expect(find.text('Producto inactivado.'), findsOneWidget);
      expect(find.text('Aún no hay productos registrados'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivos').last);
      await tester.pumpAndSettle();
      expect(find.text('Caturra'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);

      await tester.tap(find.byTooltip('Acciones del producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(find.text('Producto reactivado.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('solo quien tiene products.read ve el catalogo en el inicio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(session.dispose);

    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();
    // Un usuario recién registrado (rol cliente) no tiene permisos de producto.
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Luz');
    await tester.enterText(fields.at(1), 'Mora');
    await tester.enterText(fields.at(2), 'luz@correo.com');
    await tester.enterText(fields.at(4), 'Secreto1234!');
    await tester.enterText(fields.at(5), 'Secreto1234!');
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver a iniciar sesión'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'luz@correo.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'Secreto1234!');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Catálogo de productos'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
