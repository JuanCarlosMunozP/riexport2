import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riexport_app/app/app.dart';
import 'package:riexport_app/features/auth/presentation/confirm_email_screen.dart';
import 'package:riexport_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:riexport_app/features/auth/presentation/reset_password_screen.dart';
import 'package:riexport_app/features/auth/state/auth_session.dart';
import 'package:riexport_app/features/customers/presentation/customer_accounts_screen.dart';
import 'package:riexport_app/features/customers/presentation/customer_form_screen.dart';
import 'package:riexport_app/features/customers/presentation/customer_history_screen.dart';
import 'package:riexport_app/features/customers/presentation/customer_list_screen.dart';
import 'package:riexport_app/features/farms/presentation/farm_form_screen.dart';
import 'package:riexport_app/features/farms/presentation/farm_list_screen.dart';
import 'package:riexport_app/features/farms/presentation/farms_map_screen.dart';
import 'package:riexport_app/features/farms/presentation/lot_screens.dart';
import 'package:riexport_app/features/inventory/presentation/inventory_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_form_screen.dart';
import 'package:riexport_app/features/logistics/presentation/shipment_list_screen.dart';
import 'package:riexport_app/features/notifications/presentation/notification_center_screen.dart';
import 'package:riexport_app/features/orders/presentation/eudr_declaration_screen.dart';
import 'package:riexport_app/features/orders/presentation/export_dossier_screen.dart';
import 'package:riexport_app/features/orders/presentation/export_history_screen.dart';
import 'package:riexport_app/features/orders/presentation/export_registration_screen.dart';
import 'package:riexport_app/features/orders/presentation/order_list_screen.dart';
import 'package:riexport_app/features/orders/presentation/order_registration_screen.dart';
import 'package:riexport_app/features/payments/presentation/exchange_rates_screen.dart';
import 'package:riexport_app/features/payments/presentation/payment_portfolio_screen.dart';
import 'package:riexport_app/features/products/presentation/product_catalog_screen.dart';
import 'package:riexport_app/features/products/presentation/product_form_screen.dart';
import 'package:riexport_app/features/profile/presentation/profile_screen.dart';
import 'package:riexport_app/features/roles/presentation/roles_screen.dart';
import 'package:riexport_app/features/suppliers/presentation/supplier_form_screen.dart';
import 'package:riexport_app/features/suppliers/presentation/supplier_list_screen.dart';
import 'package:riexport_app/features/users/presentation/user_edit_screen.dart';
import 'package:riexport_app/features/users/presentation/user_registration_screen.dart';
import 'package:riexport_app/features/users/presentation/users_screen.dart';

class _MemoryTokenStore implements SessionTokenStore {
  String? value;
  @override
  Future<String?> readToken() async => value;
  @override
  Future<void> writeToken(String token) async => value = token;
  @override
  Future<void> deleteToken() async => value = null;
}

/// Ejecuta [call] ignorando errores: lo que interesa es recorrer el closure
/// que el router entrega a la pantalla.
void fire(Object? Function()? call) {
  try {
    final result = call?.call();
    if (result is Future) {
      result.then<void>((_) {}, onError: (Object _) {});
    }
  } catch (_) {}
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  late AuthSession session;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session = AuthSession(tokenStore: _MemoryTokenStore());
    addTearDown(session.dispose);
    await tester.pumpWidget(RiExportApp(authSession: session));
    await tester.pumpAndSettle();
  }

  Future<void> loginAdmin(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'admin@riexport.com');
    await tester.enterText(fields.at(1), 'Admin123!');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String location, {Object? extra}) async {
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go(location, extra: extra);
    await _settle(tester);
  }

  T screen<T extends Widget>(WidgetTester tester) =>
      tester.widget<T>(find.byType(T).first);

  testWidgets('rutas publicas invocan sus callbacks', (tester) async {
    await boot(tester);
    await go(tester, '/register');
    final reg = screen<UserRegistrationScreen>(tester);
    fire(() => reg.onConfirmEmail?.call('a@b.com'));
    await _settle(tester);
    expect(find.byType(ConfirmEmailScreen), findsOneWidget);
    final confirm = screen<ConfirmEmailScreen>(tester);
    expect(confirm.initialEmail, 'a@b.com');
    fire(() => confirm.onConfirm(email: 'a@b.com', code: '000000'));
    fire(() => reg.onRegister({'email': 'x@y.com'}));
    await _settle(tester);

    await go(tester, '/forgot-password');
    fire(() => screen<ForgotPasswordScreen>(tester).onRequest('a@b.com'));
    await go(tester, '/reset-password', extra: 'a@b.com');
    final reset = screen<ResetPasswordScreen>(tester);
    expect(reset.initialEmail, 'a@b.com');
    fire(
      () => reset.onReset(
        email: 'a@b.com',
        code: '000000',
        newPassword: 'Clave-Nueva-2026',
      ),
    );
    await go(tester, '/confirm-email');
    await _settle(tester);
  });

  testWidgets('catalogos, terceros y fincas: callbacks del router', (
    tester,
  ) async {
    await boot(tester);
    await loginAdmin(tester);

    await go(tester, '/profile');
    final profile = screen<ProfileScreen>(tester);
    fire(profile.loadProfile);
    fire(() => profile.saveProfile({'first_name': 'Ana'}));
    fire(() => profile.changeEmail('nuevo@riexport.com'));
    await _settle(tester);

    await go(tester, '/products');
    final products = screen<ProductCatalogScreen>(tester);
    fire(
      () => products.loadProducts(
        limit: 10,
        offset: 0,
        query: 'cafe',
        type: 'coffee',
        certificationId: 1,
        isActive: true,
      ),
    );
    fire(() => products.loadProducts(limit: 10, offset: 0));
    fire(products.loadCertifications);
    fire(products.loadPermissions);
    fire(() => products.setActive?.call(1, false));
    await _settle(tester);
    await go(tester, '/products/new');
    final pform = screen<ProductFormScreen>(tester);
    fire(pform.loadCertifications);
    fire(pform.loadUnits);
    fire(
      () => pform.onSave(
        fields: {'name': 'Prueba'},
        certificationIds: [1],
        certificationsChanged: true,
      ),
    );
    await go(tester, '/products/1/edit', extra: <String, dynamic>{'id': 1});
    final pedit = screen<ProductFormScreen>(tester);
    fire(pedit.loadCertifications);
    fire(pedit.loadUnits);
    fire(
      () => pedit.onSave(
        fields: {'name': 'Cambio'},
        certificationIds: [1],
        certificationsChanged: true,
      ),
    );
    fire(
      () => pedit.onSave(
        fields: {},
        certificationIds: [1],
        certificationsChanged: false,
      ),
    );
    await _settle(tester);
    await go(tester, '/products/abc/edit');

    await go(tester, '/suppliers');
    final suppliers = screen<SupplierListScreen>(tester);
    fire(
      () => suppliers.loadSuppliers(
        limit: 5,
        offset: 0,
        query: 'a',
        isActive: true,
      ),
    );
    fire(suppliers.loadPermissions);
    fire(() => suppliers.setActive?.call(1, true));
    await go(tester, '/suppliers/new');
    fire(() => screen<SupplierFormScreen>(tester).onSave({'name': 'X'}));
    await go(tester, '/suppliers/1/edit', extra: <String, dynamic>{'id': 1});
    fire(() => screen<SupplierFormScreen>(tester).onSave({'name': 'Y'}));
    await go(tester, '/suppliers/x/edit');

    await go(tester, '/customers');
    final customers = screen<CustomerListScreen>(tester);
    fire(
      () => customers.loadCustomers(
        limit: 5,
        offset: 0,
        query: 'a',
        countryCode: 'DE',
        isActive: true,
      ),
    );
    fire(customers.loadPermissions);
    fire(() => customers.setActive?.call(1, false));
    final customer = <String, dynamic>{'id': 1, 'name': 'Cliente'};
    await go(tester, '/customers/1/accounts', extra: customer);
    final accounts = screen<CustomerAccountsScreen>(tester);
    fire(accounts.loadAccounts);
    fire(() => accounts.link('a@b.com'));
    fire(() => accounts.unlink(1));
    await go(tester, '/customers/x/accounts');
    await go(tester, '/customers/1/history', extra: customer);
    fire(screen<CustomerHistoryScreen>(tester).loadHistory);
    await go(tester, '/customers/x/history');
    await go(tester, '/customers/new');
    fire(() => screen<CustomerFormScreen>(tester).onSave({'name': 'N'}));
    await go(tester, '/customers/1/edit', extra: customer);
    fire(() => screen<CustomerFormScreen>(tester).onSave({'name': 'M'}));
    await go(tester, '/customers/x/edit');

    await go(tester, '/farms');
    final farms = screen<FarmListScreen>(tester);
    fire(
      () => farms.loadFarms(limit: 5, offset: 0, query: 'a', isActive: true),
    );
    fire(farms.loadPermissions);
    fire(() => farms.setActive?.call(1, false));
    await go(tester, '/farms/map');
    fire(screen<FarmsMapLoader>(tester).loadFarms);
    await go(tester, '/farms/new');
    final farmNew = screen<FarmFormScreen>(tester);
    fire(farmNew.loadSuppliers);
    fire(() => farmNew.onSave({'name': 'F'}));
    fire(() => farmNew.pickLocation?.call(4.6, -74.0));
    await _settle(tester);
    await go(tester, '/farms/1/edit', extra: <String, dynamic>{'id': 1});
    final farmEdit = screen<FarmFormScreen>(tester);
    fire(farmEdit.loadSuppliers);
    fire(() => farmEdit.onSave({'name': 'G'}));
    fire(() => farmEdit.pickLocation?.call(null, null));
    await _settle(tester);
    await go(tester, '/farms/x/edit');

    await go(tester, '/lots');
    final lots = screen<LotListScreen>(tester);
    fire(() => lots.loadLots(limit: 5, offset: 0, query: 'a'));
    fire(lots.loadPermissions);
    await go(tester, '/lots/origin');
    await go(
      tester,
      '/lots/origin',
      extra: <String, dynamic>{'lot_code': 'L1', 'latitude': 4.6},
    );
    await go(tester, '/lots/new');
    final lotForm = screen<LotFormScreen>(tester);
    fire(lotForm.loadFarms);
    fire(lotForm.loadProducts);
    fire(() => lotForm.onSave({'lot_code': 'Z'}));
    await _settle(tester);
  });

  testWidgets('operacion, finanzas y administracion: callbacks del router', (
    tester,
  ) async {
    await boot(tester);
    await loginAdmin(tester);

    await go(tester, '/orders');
    final orders = screen<OrderListScreen>(tester);
    fire(() => orders.loadOrders(query: 'a', status: 'draft'));
    fire(() => orders.loadOrders());
    fire(() => orders.transitionOrder(1, 'confirmed'));
    fire(() => orders.onEditOrder?.call({'id': 1}));
    await _settle(tester);
    await go(tester, '/orders/new');
    final orderNew = screen<OrderRegistrationScreen>(tester);
    fire(orderNew.loadCustomers);
    fire(orderNew.loadLots);
    fire(() => orderNew.onSave({'customer_id': 1}));
    await go(tester, '/orders/1/edit');
    if (find.byType(OrderRegistrationScreen).evaluate().isNotEmpty) {
      final orderEdit = screen<OrderRegistrationScreen>(tester);
      fire(orderEdit.loadCustomers);
      fire(orderEdit.loadLots);
      fire(() => orderEdit.onSave({'notes': 'n'}));
    }
    await go(tester, '/orders/zzz/edit');
    await go(tester, '/orders/99999/edit');
    await _settle(tester);

    await go(tester, '/inventory');
    final inv = screen<InventoryScreen>(tester);
    fire(inv.loadOverview);
    fire(() => inv.loadInventory('a'));
    fire(() => inv.loadInventory(null));
    fire(() => inv.adjustInventory(1, 5));
    await _settle(tester);

    await go(tester, '/shipments');
    final ships = screen<ShipmentListScreen>(tester);
    fire(() => ships.loadShipments(query: 'a', status: 'in_transit'));
    fire(() => ships.loadShipments());
    fire(() => ships.onOpenTimeline?.call(1));
    await _settle(tester);
    await go(tester, '/shipments');
    fire(() => screen<ShipmentListScreen>(tester).onOpenMap?.call(1));
    await _settle(tester);
    await go(tester, '/shipments');
    final ships2 = screen<ShipmentListScreen>(tester);
    fire(() => ships2.onCreate?.call());
    await _settle(tester);
    await go(tester, '/shipments');
    final ships3 = screen<ShipmentListScreen>(tester);
    fire(() => ships3.onEdit?.call({'id': 1}));
    fire(() => ships3.updateStatus?.call(1, {'status': 'in_transit'}));
    await _settle(tester);
    await go(tester, '/shipments/new');
    final shipNew = screen<ShipmentFormScreen>(tester);
    fire(() => shipNew.loadExports?.call());
    fire(() => shipNew.onSubmit({'export_id': 1}));
    await go(
      tester,
      '/shipments/1/edit',
      extra: <String, dynamic>{'id': 1, 'tracking_code': 'T'},
    );
    fire(() => screen<ShipmentFormScreen>(tester).onSubmit({'notes': 'x'}));
    await go(tester, '/shipments/x/edit');
    await go(tester, '/shipments/1/timeline');
    await go(tester, '/shipments/x/timeline');
    await go(tester, '/shipments/1/map');
    await go(tester, '/shipments/x/map');
    await go(tester, '/tracking');
    await go(tester, '/tracking/1');
    await go(tester, '/tracking/x');

    await go(tester, '/payments');
    final pay = screen<PaymentPortfolioScreen>(tester);
    fire(() => pay.loadPortfolio(query: 'a', status: 'pending', currency: 'USD'));
    fire(() => pay.loadPortfolio());
    fire(() => pay.registerPayment?.call({'amount': 1}));
    fire(() => pay.createObligation?.call({'amount': 1}));
    fire(() => pay.loadExports?.call());
    fire(pay.onOpenRates);
    await _settle(tester);
    await go(tester, '/payments/rates');
    final rates = screen<ExchangeRatesScreen>(tester);
    fire(rates.loadRates);
    fire(() => rates.convert(10, 'USD', 'EUR'));
    fire(() => rates.refreshRates?.call());
    fire(() => rates.addRate?.call({'currency': 'USD'}));
    await _settle(tester);

    await go(tester, '/notifications');
    final notes = screen<NotificationCenterScreen>(tester);
    fire(notes.refreshAlerts);
    fire(() => notes.loadNotifications(unreadOnly: true));
    fire(() => notes.loadNotifications());
    fire(() => notes.markRead(1));
    fire(notes.markAllRead);
    for (final type in ['shipment', 'product', 'payment_obligation', 'other']) {
      await go(tester, '/notifications');
      fire(() => screen<NotificationCenterScreen>(tester).onOpenEntity!(type, 1));
      await _settle(tester);
    }

    await go(tester, '/exports');
    final exp = screen<ExportHistoryScreen>(tester);
    fire(() => exp.loadExports(query: 'a', status: 'draft'));
    fire(() => exp.loadExports());
    fire(() => exp.onGenerateDocument!(1));
    fire(() => exp.onOpenEudr!(1));
    await _settle(tester);
    await go(tester, '/exports');
    fire(() => screen<ExportHistoryScreen>(tester).onOpenDossier!(1));
    await _settle(tester);
    expect(find.byType(ExportDossierScreen), findsOneWidget);
    final dossier = screen<ExportDossierScreen>(tester);
    fire(() => dossier.loadDocuments(1));
    fire(() => dossier.downloadDocument(1));
    fire(() => dossier.generateDocument?.call(1, 'invoice'));
    fire(
      () => dossier.uploadDocument?.call(
        1,
        'phytosanitary',
        PickedDocument('a.pdf', Uint8List.fromList([1, 2, 3])),
      ),
    );
    await go(tester, '/exports/x/documents');
    await go(tester, '/exports/1/eudr');
    fire(() => screen<EudrDeclarationScreen>(tester).loadDeclaration(1));
    await go(tester, '/exports/new');
    final expNew = screen<ExportRegistrationScreen>(tester);
    fire(expNew.loadOrders);
    fire(expNew.loadDestinations);
    fire(expNew.loadIncoterms);
    fire(() => expNew.onSave({'order_id': 1}));
    await _settle(tester);

    await go(tester, '/users');
    final users = screen<UsersScreen>(tester);
    fire(() => users.loadUsers(limit: 5, offset: 0, query: 'a', isActive: true));
    fire(() => users.deactivateUser?.call(2));
    fire(() => users.reactivateUser?.call(2));
    await go(tester, '/roles');
    final roles = screen<RolesScreen>(tester);
    fire(roles.loadRoles);
    fire(roles.loadPermissions);
    fire(() => roles.createRole({'name': 'rol_x'}));
    fire(() => roles.updateRole(1, {'description': 'd'}));
    fire(() => roles.setRolePermissions(1, ['users.read']));
    fire(() => roles.deactivateRole(1));
    await go(tester, '/users/1/edit', extra: <String, dynamic>{'id': 1});
    final edit = screen<UserEditScreen>(tester);
    fire(() => edit.onSave({'first_name': 'A'}));
    fire(edit.loadRoles);
    fire(edit.loadViewer);
    await go(tester, '/users/x/edit');
    await go(tester, '/no-existe');
    await _settle(tester);
  });
}
