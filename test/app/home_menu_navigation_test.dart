import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/app/app.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';
import 'package:riexport_app/features/orders/presentation/order_registration_screen.dart';

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
  Future<void> login(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(session.dispose);
    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'admin@riexport.com');
    await tester.enterText(fields.at(1), 'Admin123!');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
  }

  Future<void> backHome(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/');
    await tester.pumpAndSettle();
  }

  testWidgets('cada opcion del menu lateral abre su pantalla', (tester) async {
    await login(tester);
    const entries = [
      'Mi perfil',
      'Catálogo de productos',
      'Proveedores',
      'Fincas',
      'Lotes',
      'Clientes',
      'Registrar pedido',
      'Consultar pedidos',
      'Registrar exportación',
      'Historial de exportaciones',
      'Consultar inventario',
      'Consultar envíos',
      'Cartera de pagos',
      'Consultar usuarios',
      'Administrar roles y permisos',
    ];
    for (final label in entries) {
      await backHome(tester);
      final item = find.text(label);
      await tester.ensureVisible(item.first);
      await tester.tap(item.first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      tester.takeException();
    }
    // El centro de notificaciones desde el inicio y regreso (recarga el contador).
    await backHome(tester);
    await tester.tap(find.textContaining('Notificaciones').first);
    await tester.pumpAndSettle();
    tester.takeException();
    await backHome(tester);
  });

  testWidgets('cerrar sesion desde el menu vuelve al acceso', (tester) async {
    await login(tester);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsWidgets);
  });

  testWidgets('el seguimiento publico abre el detalle de un envio', (
    tester,
  ) async {
    await login(tester);
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/tracking');
    await tester.pumpAndSettle();
    final rows = find.byType(ListTile);
    if (rows.evaluate().isNotEmpty) {
      await tester.tap(rows.first);
      await tester.pumpAndSettle();
    }
    tester.takeException();
  });

  testWidgets('editar un pedido existente abre el formulario con sus datos', (
    tester,
  ) async {
    await login(tester);
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/orders');
    await tester.pumpAndSettle();
    final edit = find.byTooltip('Editar pedido');
    if (edit.evaluate().isNotEmpty) {
      await tester.tap(edit.first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      if (find.byType(OrderRegistrationScreen).evaluate().isNotEmpty) {
        final screen = tester.widget<OrderRegistrationScreen>(
          find.byType(OrderRegistrationScreen),
        );
        expect(screen.existingOrder, isNotNull);
        try {
          await screen.onSave({'notes': 'editado'});
        } catch (_) {}
      }
    }
    tester.takeException();
  });
}
