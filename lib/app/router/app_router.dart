import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../features/auth/presentation/confirm_email_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/demo_dashboard.dart';
import 'modal_form_page.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/state/auth_session.dart';
import '../../features/products/presentation/product_catalog_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/customers/presentation/customer_accounts_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/customers/presentation/customer_history_screen.dart';
import '../../features/customers/presentation/customer_list_screen.dart';
import '../../features/farms/presentation/farm_form_screen.dart';
import '../../features/farms/presentation/farm_list_screen.dart';
import '../../features/farms/presentation/farms_map_screen.dart';
import '../../features/farms/presentation/location_picker_screen.dart';
import '../../features/farms/presentation/lot_screens.dart';
import '../../features/suppliers/presentation/supplier_form_screen.dart';
import '../../features/suppliers/presentation/supplier_list_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/roles/presentation/roles_screen.dart';
import '../../features/users/presentation/user_registration_screen.dart';
import '../../features/users/presentation/user_edit_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../../features/orders/presentation/order_registration_screen.dart';
import '../../features/orders/presentation/order_list_screen.dart';
import '../../features/orders/presentation/eudr_declaration_screen.dart';
import '../../features/orders/presentation/export_history_screen.dart';
import '../../features/orders/presentation/export_registration_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/logistics/presentation/shipment_form_screen.dart';
import '../../features/logistics/presentation/shipment_list_screen.dart';
import '../../features/logistics/presentation/shipment_timeline_screen.dart';
import '../../features/notifications/presentation/notification_center_screen.dart';
import '../../features/orders/presentation/export_dossier_screen.dart';
import '../../features/payments/presentation/exchange_rates_screen.dart';
import '../../features/payments/presentation/payment_portfolio_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const confirmEmail = '/confirm-email';
  static const profile = '/profile';
  static const products = '/products';
  static const suppliers = '/suppliers';
  static const customers = '/customers';
  static const farms = '/farms';
  static const lots = '/lots';
  static const orders = '/orders';
  static const exports = '/exports';
  static const inventory = '/inventory';
  static const shipments = '/shipments';
  static const tracking = '/tracking';
  static const payments = '/payments';
  static const notifications = '/notifications';
  static const users = '/users';
  static const roles = '/roles';
}

/// [isAuthenticated] y [refreshListenable] activan la guarda de rutas: sin
/// sesión solo se puede estar en el acceso y el registro, y con sesión no se
/// vuelve a ellos. Al cambiar la sesión (por ejemplo, un 401) se reevalúa.
GoRouter createAppRouter({
  String initialLocation = AppRoutes.login,
  bool Function()? isAuthenticated,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: isAuthenticated == null
        ? null
        : (context, state) {
            final path = state.uri.path;
            final isPublic =
                path == AppRoutes.login ||
                path == AppRoutes.register ||
                path == AppRoutes.forgotPassword ||
                path == AppRoutes.resetPassword ||
                path == AppRoutes.confirmEmail;
            final loggedIn = isAuthenticated();
            if (!loggedIn && !isPublic) return AppRoutes.login;
            if (loggedIn && isPublic) return AppRoutes.home;
            return null;
          },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, _) => _HomePlaceholder(
          onLogout: () async {
            final api = context.read<ApiClient>();
            final session = context.read<AuthSession>();
            try {
              await api.post('/auth/logout', signalUnauthorized: false);
            } catch (_) {
              // Revocar la sesión en el servidor es "al mejor esfuerzo": la
              // sesión local se cierra de todos modos.
            }
            return session.clear();
          },
          loadPermissions: () async {
            final me = await context.read<ApiClient>().get('/me');
            final codes = me is Map ? me['permission_codes'] : null;
            return {if (codes is List) ...codes.whereType<String>()};
          },
          loadUnreadCount: () async {
            final page = await context.read<ApiClient>().get(
              '/notifications',
              queryParameters: {'unread': 'true', 'limit': '1'},
            );
            final pagination = page is Map ? page['pagination'] : null;
            final total = pagination is Map ? pagination['total'] : null;
            return total is int ? total : 0;
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, _) => LoginScreen(
          notice: context.read<AuthSession>().sessionExpired
              ? 'Tu sesión expiró. Inicia sesión de nuevo.'
              : null,
          onLogin: (email, password) =>
              context.read<AuthSession>().authenticate(
                context.read<ApiClient>(),
                email: email,
                password: password,
              ),
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgot-password',
        builder: (context, _) => ForgotPasswordScreen(
          onRequest: (email) async {
            await context.read<ApiClient>().post(
              '/auth/password-reset-requests',
              body: {'email': email},
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        name: 'reset-password',
        builder: (context, state) => ResetPasswordScreen(
          initialEmail: state.extra is String ? state.extra as String : null,
          onReset:
              ({required email, required code, required newPassword}) async {
                await context.read<ApiClient>().post(
                  '/auth/password-resets',
                  body: {
                    'email': email,
                    'code': code,
                    'new_password': newPassword,
                  },
                );
              },
        ),
      ),
      GoRoute(
        path: AppRoutes.confirmEmail,
        name: 'confirm-email',
        builder: (context, state) => ConfirmEmailScreen(
          initialEmail: state.extra is String ? state.extra as String : null,
          onConfirm: ({required email, required code}) async {
            await context.read<ApiClient>().post(
              '/auth/email-confirmations',
              body: {'email': email, 'code': code},
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, _) => UserRegistrationScreen(
          onConfirmEmail: (email) =>
              context.push(AppRoutes.confirmEmail, extra: email),
          onRegister: (request) async {
            await context.read<ApiClient>().post(
              '/auth/register',
              body: request,
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        builder: (context, _) => ProfileScreen(
          loadProfile: () => context.read<ApiClient>().get('/me'),
          saveProfile: (changes) =>
              context.read<ApiClient>().patch('/me', body: changes),
          changeEmail: (email) =>
              context.read<ApiClient>().patch('/me', body: {'email': email}),
        ),
      ),
      GoRoute(
        path: AppRoutes.products,
        name: 'products',
        builder: (context, _) => ProductCatalogScreen(
          loadProducts:
              ({
                required limit,
                required offset,
                query,
                type,
                certificationId,
                isActive,
              }) {
                final parameters = <String, String>{
                  'limit': '$limit',
                  'offset': '$offset',
                };
                if (query != null) parameters['q'] = query;
                if (type != null) parameters['type'] = type;
                if (certificationId != null) {
                  parameters['certification_id'] = '$certificationId';
                }
                if (isActive != null) parameters['is_active'] = '$isActive';
                return context.read<ApiClient>().get(
                  '/products',
                  queryParameters: parameters,
                );
              },
          loadCertifications: () => _loadItems(context, '/certifications'),
          loadPermissions: () async {
            final me = await context.read<ApiClient>().get('/me');
            final codes = me is Map ? me['permission_codes'] : null;
            return {if (codes is List) ...codes.whereType<String>()};
          },
          setActive: (productId, isActive) async {
            await context.read<ApiClient>().patch(
              '/products/$productId/status',
              body: {'is_active': isActive},
            );
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.products}/new',
        name: 'product-new',
        builder: (context, _) => ProductFormScreen(
          loadCertifications: () => _loadItems(context, '/certifications'),
          loadUnits: () => _loadItems(context, '/units'),
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async {
                await context.read<ApiClient>().post(
                  '/products',
                  body: {...fields, 'certification_ids': certificationIds},
                );
              },
        ),
      ),
      formRoute(
        path: '${AppRoutes.products}/:productId/edit',
        name: 'product-edit',
        builder: (context, state) {
          final productId = int.tryParse(
            state.pathParameters['productId'] ?? '',
          );
          final extra = state.extra;
          if (productId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Producto no disponible',
              message: 'Abre la edición desde el catálogo de productos.',
            );
          }
          return ProductFormScreen(
            product: extra,
            loadCertifications: () => _loadItems(context, '/certifications'),
            loadUnits: () => _loadItems(context, '/units'),
            onSave:
                ({
                  required fields,
                  required certificationIds,
                  required certificationsChanged,
                }) async {
                  final api = context.read<ApiClient>();
                  if (fields.isNotEmpty) {
                    await api.patch('/products/$productId', body: fields);
                  }
                  if (certificationsChanged) {
                    await api.put(
                      '/products/$productId/certifications',
                      body: {'certification_ids': certificationIds},
                    );
                  }
                },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.suppliers,
        name: 'suppliers',
        builder: (context, _) => SupplierListScreen(
          loadSuppliers: ({required limit, required offset, query, isActive}) {
            final parameters = <String, String>{
              'limit': '$limit',
              'offset': '$offset',
            };
            if (query != null) parameters['q'] = query;
            if (isActive != null) parameters['is_active'] = '$isActive';
            return context.read<ApiClient>().get(
              '/suppliers',
              queryParameters: parameters,
            );
          },
          loadPermissions: () async {
            final me = await context.read<ApiClient>().get('/me');
            final codes = me is Map ? me['permission_codes'] : null;
            return {if (codes is List) ...codes.whereType<String>()};
          },
          setActive: (supplierId, isActive) async {
            await context.read<ApiClient>().patch(
              '/suppliers/$supplierId/status',
              body: {'is_active': isActive},
            );
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.suppliers}/new',
        name: 'supplier-new',
        builder: (context, _) => SupplierFormScreen(
          onSave: (fields) async {
            await context.read<ApiClient>().post('/suppliers', body: fields);
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.suppliers}/:supplierId/edit',
        name: 'supplier-edit',
        builder: (context, state) {
          final supplierId = int.tryParse(
            state.pathParameters['supplierId'] ?? '',
          );
          final extra = state.extra;
          if (supplierId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Proveedor no disponible',
              message: 'Abre la edición desde la lista de proveedores.',
            );
          }
          return SupplierFormScreen(
            supplier: extra,
            onSave: (fields) async {
              await context.read<ApiClient>().patch(
                '/suppliers/$supplierId',
                body: fields,
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.customers,
        name: 'customers',
        builder: (context, _) => CustomerListScreen(
          loadCustomers:
              ({
                required limit,
                required offset,
                query,
                countryCode,
                isActive,
              }) {
                final parameters = <String, String>{
                  'limit': '$limit',
                  'offset': '$offset',
                };
                if (query != null) parameters['q'] = query;
                if (countryCode != null) {
                  parameters['country_code'] = countryCode;
                }
                if (isActive != null) parameters['is_active'] = '$isActive';
                return context.read<ApiClient>().get(
                  '/customers',
                  queryParameters: parameters,
                );
              },
          loadPermissions: () => _loadPermissions(context),
          setActive: (customerId, isActive) async {
            await context.read<ApiClient>().patch(
              '/customers/$customerId/status',
              body: {'is_active': isActive},
            );
          },
        ),
      ),
      GoRoute(
        path: '${AppRoutes.customers}/:customerId/accounts',
        name: 'customer-accounts',
        builder: (context, state) {
          final customerId = int.tryParse(
            state.pathParameters['customerId'] ?? '',
          );
          final extra = state.extra;
          if (customerId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Cliente no disponible',
              message: 'Abre las cuentas desde la lista de clientes.',
            );
          }
          return CustomerAccountsScreen(
            customer: extra,
            loadAccounts: () =>
                _loadItems(context, '/customers/$customerId/accounts'),
            link: (email) async {
              await context.read<ApiClient>().post(
                '/customers/$customerId/accounts',
                body: {'email': email},
              );
            },
            unlink: (profileId) async {
              await context.read<ApiClient>().delete(
                '/customers/$customerId/accounts/$profileId',
              );
            },
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.customers}/:customerId/history',
        name: 'customer-history',
        builder: (context, state) {
          final customerId = int.tryParse(
            state.pathParameters['customerId'] ?? '',
          );
          final extra = state.extra;
          if (customerId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Cliente no disponible',
              message: 'Abre el historial desde la lista de clientes.',
            );
          }
          return CustomerHistoryScreen(
            customer: extra,
            loadHistory: () async {
              final history = await context.read<ApiClient>().get(
                '/customers/$customerId/history',
              );
              return history is Map<String, dynamic>
                  ? history
                  : <String, dynamic>{'available': false};
            },
          );
        },
      ),
      formRoute(
        path: '${AppRoutes.customers}/new',
        name: 'customer-new',
        builder: (context, _) => CustomerFormScreen(
          onSave: (fields) async {
            await context.read<ApiClient>().post('/customers', body: fields);
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.customers}/:customerId/edit',
        name: 'customer-edit',
        builder: (context, state) {
          final customerId = int.tryParse(
            state.pathParameters['customerId'] ?? '',
          );
          final extra = state.extra;
          if (customerId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Cliente no disponible',
              message: 'Abre la edición desde la lista de clientes.',
            );
          }
          return CustomerFormScreen(
            customer: extra,
            onSave: (fields) async {
              await context.read<ApiClient>().patch(
                '/customers/$customerId',
                body: fields,
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.farms,
        name: 'farms',
        builder: (context, _) => FarmListScreen(
          loadFarms: ({required limit, required offset, query, isActive}) {
            final parameters = <String, String>{
              'limit': '$limit',
              'offset': '$offset',
            };
            if (query != null) parameters['q'] = query;
            if (isActive != null) parameters['is_active'] = '$isActive';
            return context.read<ApiClient>().get(
              '/farms',
              queryParameters: parameters,
            );
          },
          loadPermissions: () => _loadPermissions(context),
          setActive: (farmId, isActive) async {
            await context.read<ApiClient>().patch(
              '/farms/$farmId/status',
              body: {'is_active': isActive},
            );
          },
        ),
      ),
      GoRoute(
        path: '${AppRoutes.farms}/map',
        name: 'farms-map',
        builder: (context, _) =>
            FarmsMapLoader(loadFarms: () => _loadActivePage(context, '/farms')),
      ),
      formRoute(
        path: '${AppRoutes.farms}/new',
        name: 'farm-new',
        builder: (context, _) => FarmFormScreen(
          pickLocation: (lat, lon) => _pickOnMap(context, lat, lon),
          loadSuppliers: () async {
            final page = await context.read<ApiClient>().get(
              '/suppliers',
              queryParameters: {'is_active': 'true', 'limit': '100'},
            );
            final items = page is Map ? page['items'] : null;
            return [
              if (items is List)
                for (final item in items)
                  if (item is Map) Map<String, dynamic>.from(item),
            ];
          },
          onSave: (fields) async {
            await context.read<ApiClient>().post('/farms', body: fields);
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.farms}/:farmId/edit',
        name: 'farm-edit',
        builder: (context, state) {
          final farmId = int.tryParse(state.pathParameters['farmId'] ?? '');
          final extra = state.extra;
          if (farmId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Finca no disponible',
              message: 'Abre la edición desde la lista de fincas.',
            );
          }
          return FarmFormScreen(
            farm: extra,
            pickLocation: (lat, lon) => _pickOnMap(context, lat, lon),
            loadSuppliers: () async => const [],
            onSave: (fields) async {
              await context.read<ApiClient>().patch(
                '/farms/$farmId',
                body: fields,
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.lots,
        name: 'lots',
        builder: (context, _) => LotListScreen(
          loadLots: ({required limit, required offset, query}) {
            final parameters = <String, String>{
              'limit': '$limit',
              'offset': '$offset',
            };
            if (query != null) parameters['q'] = query;
            return context.read<ApiClient>().get(
              '/lots',
              queryParameters: parameters,
            );
          },
          loadPermissions: () => _loadPermissions(context),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.lots}/origin',
        name: 'lot-origin',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Lote no disponible',
              message: 'Abre el origen desde la lista de lotes.',
            );
          }
          return TraceabilityMapScreen(
            lines: [extra],
            title: 'Origen del lote',
          );
        },
      ),
      formRoute(
        path: '${AppRoutes.lots}/new',
        name: 'lot-new',
        builder: (context, _) => LotFormScreen(
          loadFarms: () => _loadActivePage(context, '/farms'),
          loadProducts: () => _loadActivePage(context, '/products'),
          onSave: (fields) async {
            await context.read<ApiClient>().post('/lots', body: fields);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.orders,
        name: 'orders',
        builder: (context, _) => FutureBuilder<Set<String>>(
          future: _loadPermissions(context),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return OrderListScreen(
              canTransition: snapshot.data!.contains('orders.transition'),
              canEdit: snapshot.data!.contains('orders.update'),
              onEditOrder: snapshot.data!.contains('orders.update')
                  ? (order) =>
                        context.push('${AppRoutes.orders}/${order['id']}/edit')
                  : null,
              loadOrders: ({query, status}) async {
                final parameters = <String, String>{'limit': '100'};
                if (query != null && query.isNotEmpty) parameters['q'] = query;
                if (status != null) parameters['status'] = status;
                final response = await context.read<ApiClient>().get(
                  '/orders',
                  queryParameters: parameters,
                );
                final items = response is Map ? response['items'] : null;
                return [
                  if (items is List)
                    for (final item in items)
                      if (item is Map) Map<String, dynamic>.from(item),
                ];
              },
              transitionOrder: (id, status) async {
                await context.read<ApiClient>().patch(
                  '/orders/$id/status',
                  body: {'status': status},
                );
              },
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.inventory,
        name: 'inventory',
        builder: (context, _) => FutureBuilder<Set<String>>(
          future: _loadPermissions(context),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return InventoryScreen(
              canAdjust: snapshot.data!.contains('inventory.adjust'),
              loadOverview: () => _loadItems(context, '/inventory/overview'),
              loadInventory: (query) async {
                final response = await context.read<ApiClient>().get(
                  '/inventory',
                  queryParameters: {'limit': '100', 'q': ?query},
                );
                final items = response is Map ? response['items'] : null;
                return [
                  if (items is List)
                    for (final item in items)
                      if (item is Map) Map<String, dynamic>.from(item),
                ];
              },
              adjustInventory: (lotId, delta) async {
                await context.read<ApiClient>().post(
                  '/inventory/adjustments',
                  body: {'product_lot_id': lotId, 'quantity_delta': delta},
                );
              },
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.shipments,
        name: 'shipments',
        builder: (context, _) => FutureBuilder<Set<String>>(
          future: _loadPermissions(context),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final permissions = snapshot.data!;
            final api = context.read<ApiClient>();
            return ShipmentListScreen(
              loadShipments: ({query, status}) => _loadItems(
                context,
                '/shipments',
                {'limit': '100', 'q': ?query, 'status': ?status},
              ),
              onOpenTimeline: (id) =>
                  context.push('${AppRoutes.shipments}/$id/timeline'),
              onOpenMap: (id) => context.push('${AppRoutes.shipments}/$id/map'),
              onCreate: permissions.contains('logistics.create')
                  ? () => context.push('${AppRoutes.shipments}/new')
                  : null,
              onEdit: permissions.contains('logistics.update')
                  ? (shipment) => context.push(
                      '${AppRoutes.shipments}/${shipment['id']}/edit',
                      extra: shipment,
                    )
                  : null,
              updateStatus: permissions.contains('logistics.update')
                  ? (id, change) async {
                      await api.post('/shipments/$id/status', body: change);
                    }
                  : null,
            );
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.shipments}/new',
        name: 'shipment-new',
        builder: (context, _) => ShipmentFormScreen(
          loadExports: () => _loadItems(context, '/exports', {'limit': '100'}),
          onSubmit: (body) async {
            await context.read<ApiClient>().post('/shipments', body: body);
          },
        ),
      ),
      formRoute(
        path: '${AppRoutes.shipments}/:shipmentId/edit',
        name: 'shipment-edit',
        builder: (context, state) {
          final shipment = state.extra;
          final id = int.tryParse(state.pathParameters['shipmentId'] ?? '');
          if (shipment is! Map || id == null) {
            return const _RoutePlaceholder(title: 'Envío no válido');
          }
          return ShipmentFormScreen(
            initial: Map<String, dynamic>.from(shipment),
            onSubmit: (body) async {
              await context.read<ApiClient>().patch(
                '/shipments/$id',
                body: body,
              );
            },
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.shipments}/:shipmentId/timeline',
        name: 'shipment-timeline',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['shipmentId'] ?? '');
          if (id == null) {
            return const _RoutePlaceholder(title: 'Envío no válido');
          }
          return _ShipmentTimelineRoute(shipmentId: id, source: '/shipments');
        },
      ),
      GoRoute(
        path: AppRoutes.tracking,
        name: 'tracking',
        builder: (context, _) => _TrackingList(),
      ),
      GoRoute(
        path: '${AppRoutes.tracking}/:shipmentId',
        name: 'tracking-detail',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['shipmentId'] ?? '');
          if (id == null) {
            return const _RoutePlaceholder(title: 'Envío no válido');
          }
          return _ShipmentTimelineRoute(shipmentId: id, source: '/tracking');
        },
      ),
      GoRoute(
        path: AppRoutes.payments,
        name: 'payments',
        builder: (context, _) => FutureBuilder<Set<String>>(
          future: _loadPermissions(context),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final canCreate = snapshot.data!.contains('payments.create');
            final api = context.read<ApiClient>();
            return PaymentPortfolioScreen(
              loadPortfolio: ({query, status, currency}) => _loadItems(
                context,
                '/payments/portfolio',
                {'q': ?query, 'status': ?status, 'currency': ?currency},
              ),
              onOpenRates: () => context.push('${AppRoutes.payments}/rates'),
              registerPayment: canCreate
                  ? (payment) async {
                      await api.post('/payments/transactions', body: payment);
                    }
                  : null,
              createObligation: canCreate
                  ? (obligation) async {
                      await api.post('/payments/obligations', body: obligation);
                    }
                  : null,
              loadExports: canCreate
                  ? () => _loadItems(context, '/exports', {
                      'limit': '100',
                      'status': 'formalized',
                    })
                  : null,
            );
          },
        ),
      ),
      GoRoute(
        path: '${AppRoutes.payments}/rates',
        name: 'exchange-rates',
        builder: (context, _) => FutureBuilder<Set<String>>(
          future: _loadPermissions(context),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final canCreate = snapshot.data!.contains('payments.create');
            final api = context.read<ApiClient>();
            return ExchangeRatesScreen(
              loadRates: () => _loadItems(context, '/payments/exchange-rates'),
              convert: (amount, from, to) async {
                final result = await api.get(
                  '/payments/convert',
                  queryParameters: {
                    'amount': '$amount',
                    'from': from,
                    'to': to,
                  },
                );
                if (result is! Map) throw StateError('Respuesta no válida');
                return Map<String, dynamic>.from(result);
              },
              refreshRates: canCreate
                  ? () async {
                      await api.post('/payments/exchange-rates/refresh');
                    }
                  : null,
              addRate: canCreate
                  ? (rate) async {
                      await api.post('/payments/exchange-rates', body: rate);
                    }
                  : null,
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, _) {
          final api = context.read<ApiClient>();
          return NotificationCenterScreen(
            refreshAlerts: () async {
              await api.post('/notifications/refresh');
            },
            loadNotifications: ({unreadOnly = false}) => _loadItems(
              context,
              '/notifications',
              {'limit': '100', if (unreadOnly) 'unread': 'true'},
            ),
            markRead: (id) async {
              await api.patch(
                '/notifications/$id',
                body: {'read_at': DateTime.now().toUtc().toIso8601String()},
              );
            },
            markAllRead: () async {
              await api.post('/notifications/read-all');
            },
            onOpenEntity: (type, id) async {
              switch (type) {
                case 'shipment':
                  // El personal con logística ve la línea de tiempo completa; un
                  // cliente externo (solo `portal.read`) abre el seguimiento de
                  // sus envíos, porque la vista de logística no le devuelve nada.
                  final permissions = await _loadPermissions(context);
                  if (!context.mounted) return;
                  context.push(
                    permissions.contains('logistics.read')
                        ? '${AppRoutes.shipments}/$id/timeline'
                        : '${AppRoutes.tracking}/$id',
                  );
                case 'product':
                  context.push(AppRoutes.inventory);
                case 'payment_obligation':
                  context.push(AppRoutes.payments);
              }
            },
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.shipments}/:shipmentId/map',
        name: 'shipment-map',
        builder: (context, state) {
          final shipmentId = int.tryParse(
            state.pathParameters['shipmentId'] ?? '',
          );
          if (shipmentId == null) {
            return const _RoutePlaceholder(title: 'Envío no válido');
          }
          return FutureBuilder(
            future: context.read<ApiClient>().get(
              '/shipments/$shipmentId/origin-farms',
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _RoutePlaceholder(
                  title: 'No se pudo cargar la trazabilidad',
                  message: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final result = snapshot.data;
              final items = result is Map ? result['items'] : null;
              final lines = [
                if (items is List)
                  for (final item in items)
                    if (item is Map) Map<String, dynamic>.from(item),
              ];
              return TraceabilityMapScreen(
                lines: lines,
                title: 'Origen del envío',
              );
            },
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.orders}/new',
        name: 'order-new',
        builder: (context, _) => OrderRegistrationScreen(
          loadCustomers: () => _loadActivePage(context, '/customers'),
          loadLots: () => _loadActivePage(context, '/lots'),
          onSave: (order) =>
              context.read<ApiClient>().post('/orders', body: order),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.orders}/:orderId/edit',
        name: 'order-edit',
        builder: (context, state) {
          final orderId = int.tryParse(state.pathParameters['orderId'] ?? '');
          if (orderId == null) {
            return const _RoutePlaceholder(title: 'Pedido no válido');
          }
          return FutureBuilder(
            future: context.read<ApiClient>().get('/orders/$orderId'),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _RoutePlaceholder(
                  title: 'No se pudo cargar el pedido',
                  message: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData || snapshot.data is! Map) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return OrderRegistrationScreen(
                existingOrder: Map<String, dynamic>.from(snapshot.data! as Map),
                loadCustomers: () => _loadActivePage(context, '/customers'),
                loadLots: () => _loadActivePage(context, '/lots'),
                onSave: (order) => context.read<ApiClient>().patch(
                  '/orders/$orderId',
                  body: order,
                ),
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.exports,
        name: 'exports',
        builder: (context, _) => ExportHistoryScreen(
          onOpenEudr: (id) => context.push('${AppRoutes.exports}/$id/eudr'),
          onOpenDossier: (id) =>
              context.push('${AppRoutes.exports}/$id/documents'),
          onGenerateDocument: (id) async {
            final response = await context.read<ApiClient>().post(
              '/exports/$id/documents',
              body: {'document_type': 'export_summary'},
            );
            return response is Map ? response['download_url'] as String? : null;
          },
          loadExports: ({query, status}) async {
            final response = await context.read<ApiClient>().get(
              '/exports',
              queryParameters: {'limit': '100', 'q': ?query, 'status': ?status},
            );
            final items = response is Map ? response['items'] : null;
            return [
              if (items is List)
                for (final item in items)
                  if (item is Map) Map<String, dynamic>.from(item),
            ];
          },
        ),
      ),
      GoRoute(
        path: '${AppRoutes.exports}/:exportId/documents',
        name: 'export-documents',
        builder: (context, state) {
          final exportId = int.tryParse(state.pathParameters['exportId'] ?? '');
          if (exportId == null) {
            return const _RoutePlaceholder(title: 'Exportación no válida');
          }
          return FutureBuilder<Set<String>>(
            future: _loadPermissions(context),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final permissions = snapshot.data!;
              final api = context.read<ApiClient>();
              return ExportDossierScreen(
                exportId: exportId,
                loadDocuments: (id) =>
                    _loadItems(context, '/exports/$id/documents'),
                downloadDocument: (documentId) async {
                  final response = await api.get(
                    '/documents/$documentId/download',
                  );
                  return response is Map
                      ? response['download_url'] as String?
                      : null;
                },
                generateDocument: permissions.contains('documents.generate')
                    ? (id, type) async {
                        await api.post(
                          '/exports/$id/documents',
                          body: {'document_type': type},
                        );
                      }
                    : null,
                uploadDocument: permissions.contains('documents.upload')
                    ? (id, type, file) async {
                        await api.post(
                          '/exports/$id/documents/upload',
                          body: {
                            'document_type': type,
                            'file_name': file.name,
                            'content_base64': base64Encode(file.bytes),
                          },
                        );
                      }
                    : null,
              );
            },
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.exports}/:exportId/eudr',
        name: 'export-eudr',
        builder: (context, state) => EudrDeclarationScreen(
          exportId: int.tryParse(state.pathParameters['exportId'] ?? '') ?? 0,
          loadDeclaration: (id) async {
            final response = await context.read<ApiClient>().get(
              '/exports/$id/eudr',
            );
            if (response is! Map) throw StateError('Respuesta no válida');
            return Map<String, dynamic>.from(response);
          },
        ),
      ),
      GoRoute(
        path: '${AppRoutes.exports}/new',
        name: 'export-new',
        builder: (context, _) => ExportRegistrationScreen(
          loadOrders: () async {
            final response = await context.read<ApiClient>().get(
              '/orders',
              queryParameters: {'limit': '100', 'status': 'confirmed'},
            );
            final items = response is Map ? response['items'] : null;
            return [
              if (items is List)
                for (final item in items)
                  if (item is Map) Map<String, dynamic>.from(item),
            ];
          },
          loadDestinations: () =>
              _loadItems(context, '/export-catalogs/destinations'),
          loadIncoterms: () =>
              _loadItems(context, '/export-catalogs/incoterms'),
          onSave: (export) =>
              context.read<ApiClient>().post('/exports', body: export),
        ),
      ),
      GoRoute(
        path: AppRoutes.users,
        name: 'users',
        builder: (context, _) => UsersScreen(
          deactivateUser: (userId) async {
            await context.read<ApiClient>().patch('/users/$userId/deactivate');
          },
          reactivateUser: (userId) async {
            await context.read<ApiClient>().patch('/users/$userId/activate');
          },
          loadUsers: ({required limit, required offset, query, isActive}) {
            final parameters = <String, String>{
              'limit': '$limit',
              'offset': '$offset',
            };
            if (query != null) parameters['q'] = query;
            if (isActive != null) parameters['is_active'] = '$isActive';
            return context.read<ApiClient>().get(
              '/users',
              queryParameters: parameters,
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.roles,
        name: 'roles',
        builder: (context, _) => RolesScreen(
          loadRoles: () => context.read<ApiClient>().get(
            '/roles',
            queryParameters: const {'include_inactive': 'true'},
          ),
          loadPermissions: () =>
              context.read<ApiClient>().get('/roles/permissions'),
          createRole: (request) =>
              context.read<ApiClient>().post('/roles', body: request),
          updateRole: (roleId, changes) =>
              context.read<ApiClient>().patch('/roles/$roleId', body: changes),
          setRolePermissions: (roleId, permissionCodes) =>
              context.read<ApiClient>().put(
                '/roles/$roleId/permissions',
                body: {'permission_codes': permissionCodes},
              ),
          deactivateRole: (roleId) =>
              context.read<ApiClient>().patch('/roles/$roleId/deactivate'),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.users}/:userId/edit',
        name: 'user-edit',
        builder: (context, state) {
          final userId = int.tryParse(state.pathParameters['userId'] ?? '');
          final extra = state.extra;
          if (userId == null || extra is! Map<String, dynamic>) {
            return const _RoutePlaceholder(
              title: 'Usuario no disponible',
              message: 'Abre la edición desde el listado de usuarios.',
            );
          }
          return UserEditScreen(
            user: extra,
            onSave: (changes) async {
              await context.read<ApiClient>().patch(
                '/users/$userId',
                body: changes,
              );
            },
            loadRoles: () async {
              final response = await context.read<ApiClient>().get('/roles');
              final items = response is Map ? response['items'] : null;
              return [
                if (items is List)
                  for (final item in items)
                    if (item is Map) Map<String, dynamic>.from(item),
              ];
            },
            loadViewer: () async {
              final me = await context.read<ApiClient>().get('/me');
              return me is Map ? Map<String, dynamic>.from(me) : {};
            },
          );
        },
      ),
    ],
    errorBuilder: (_, state) => _RoutePlaceholder(
      title: 'Página no encontrada',
      message: 'No existe la ruta ${state.uri.path}.',
    ),
  );
}

/// Lista de `items` de un catálogo simple (`/certifications`, `/units`).
Future<List<Map<String, dynamic>>> _loadItems(
  BuildContext context,
  String path, [
  Map<String, String>? queryParameters,
]) async {
  final response = await context.read<ApiClient>().get(
    path,
    queryParameters: queryParameters,
  );
  final items = response is Map ? response['items'] : null;
  return [
    if (items is List)
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// Códigos de permiso de quien tiene la sesión (para mostrar acciones).
Future<Set<String>> _loadPermissions(BuildContext context) async {
  final me = await context.read<ApiClient>().get('/me');
  final codes = me is Map ? me['permission_codes'] : null;
  return {if (codes is List) ...codes.whereType<String>()};
}

/// Primera página (hasta 100) de los registros activos de [path].
Future<List<Map<String, dynamic>>> _loadActivePage(
  BuildContext context,
  String path,
) async {
  final page = await context.read<ApiClient>().get(
    path,
    queryParameters: {'is_active': 'true', 'limit': '100'},
  );
  final items = page is Map ? page['items'] : null;
  return [
    if (items is List)
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// Abre el selector de mapa y devuelve el punto elegido (null si se cancela).
Future<PickedPoint?> _pickOnMap(
  BuildContext context,
  double? latitude,
  double? longitude,
) => Navigator.of(context).push<PickedPoint>(
  MaterialPageRoute(
    builder: (_) => LocationPickerScreen(
      initialLatitude: latitude,
      initialLongitude: longitude,
    ),
  ),
);

class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder({required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(message ?? title)),
    );
  }
}

class _HomePlaceholder extends StatefulWidget {
  const _HomePlaceholder({
    required this.onLogout,
    required this.loadPermissions,
    this.loadUnreadCount,
  });

  final Future<bool> Function() onLogout;
  final Future<Set<String>> Function() loadPermissions;

  /// Cantidad de notificaciones sin leer (insignia en el botón del centro).
  final Future<int> Function()? loadUnreadCount;

  @override
  State<_HomePlaceholder> createState() => _HomePlaceholderState();
}

class _HomePlaceholderState extends State<_HomePlaceholder> {
  bool _isSigningOut = false;
  bool _loadingPermissions = true;
  bool _permissionsFailed = false;
  Set<String> _permissions = const {};
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _loadingPermissions = true;
      _permissionsFailed = false;
    });
    _loadUnread();
    try {
      final permissions = await widget.loadPermissions();
      if (mounted) setState(() => _permissions = permissions);
    } catch (_) {
      // Sin permisos conocidos no se muestran las opciones de gestión.
      if (mounted) setState(() => _permissionsFailed = true);
    } finally {
      if (mounted) setState(() => _loadingPermissions = false);
    }
  }

  Future<void> _loadUnread() async {
    final load = widget.loadUnreadCount;
    if (load == null) return;
    try {
      final count = await load();
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      // El contador es informativo: sin él, el botón se muestra sin insignia.
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    final messenger = ScaffoldMessenger.of(context);
    var tokenRemoved = false;
    try {
      tokenRemoved = await widget.onLogout();
    } finally {
      if (mounted) context.go(AppRoutes.login);
    }
    if (!tokenRemoved) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'La sesión se cerró, pero no se pudo borrar el token guardado.',
          ),
        ),
      );
    }
  }

  /// Ancho desde el que el menú lateral queda fijo; por debajo se abre desde el
  /// botón de menú como cajón (móvil y ventanas estrechas).
  static const double _sidebarBreakpoint = 600;

  List<_NavSection> _sections(BuildContext context, {VoidCallback? before}) {
    _NavItem item(
      String label,
      IconData icon,
      String? permission,
      Future<void> Function() go, {
      int badge = 0,
    }) => _NavItem(
      label: label,
      icon: icon,
      visible: permission == null || _permissions.contains(permission),
      badge: badge,
      onTap: () async {
        before?.call();
        await go();
      },
    );
    Future<void> goTo(String r) async => context.go(r);
    Future<void> pushTo(String r) async => context.push(r);

    return [
      _NavSection('Cuenta', Icons.person_outline, [
        item(
          'Mi perfil',
          Icons.account_circle_outlined,
          null,
          () => goTo(AppRoutes.profile),
        ),
        item(
          _unread > 0 ? 'Notificaciones ($_unread)' : 'Notificaciones',
          Icons.notifications_outlined,
          null,
          () async {
            await context.push(AppRoutes.notifications);
            _loadUnread();
          },
          badge: _unread,
        ),
      ]),
      _NavSection('Catálogo', Icons.inventory_2_outlined, [
        item(
          'Catálogo de productos',
          Icons.inventory_2_outlined,
          'products.read',
          () => goTo(AppRoutes.products),
        ),
        item(
          'Proveedores',
          Icons.local_shipping_outlined,
          'suppliers.read',
          () => goTo(AppRoutes.suppliers),
        ),
        item(
          'Fincas',
          Icons.landscape_outlined,
          'farms.read',
          () => goTo(AppRoutes.farms),
        ),
        item(
          'Lotes',
          Icons.layers_outlined,
          'lots.read',
          () => goTo(AppRoutes.lots),
        ),
        item(
          'Clientes',
          Icons.business_outlined,
          'customers.read',
          () => goTo(AppRoutes.customers),
        ),
      ]),
      _NavSection('Ventas y exportación', Icons.receipt_long_outlined, [
        item(
          'Registrar pedido',
          Icons.receipt_long_outlined,
          'orders.create',
          () => pushTo('${AppRoutes.orders}/new'),
        ),
        item(
          'Consultar pedidos',
          Icons.list_alt_outlined,
          'orders.read',
          () => pushTo(AppRoutes.orders),
        ),
        item(
          'Registrar exportación',
          Icons.flight_takeoff_outlined,
          'exports.create',
          () => pushTo('${AppRoutes.exports}/new'),
        ),
        item(
          'Historial de exportaciones',
          Icons.history_outlined,
          'exports.read',
          () => pushTo(AppRoutes.exports),
        ),
      ]),
      _NavSection('Operación', Icons.warehouse_outlined, [
        item(
          'Consultar inventario',
          Icons.warehouse_outlined,
          'inventory.read',
          () => goTo(AppRoutes.inventory),
        ),
        item(
          'Consultar envíos',
          Icons.local_shipping_outlined,
          'logistics.read',
          () => goTo(AppRoutes.shipments),
        ),
        item(
          'Cartera de pagos',
          Icons.account_balance_wallet_outlined,
          'payments.read',
          () => pushTo(AppRoutes.payments),
        ),
        item(
          'Seguimiento de mis envíos',
          Icons.track_changes_outlined,
          'portal.read',
          () => pushTo(AppRoutes.tracking),
        ),
      ]),
      _NavSection('Administración', Icons.admin_panel_settings_outlined, [
        item(
          'Consultar usuarios',
          Icons.manage_search_rounded,
          'users.read',
          () => goTo(AppRoutes.users),
        ),
        item(
          'Administrar roles y permisos',
          Icons.admin_panel_settings_outlined,
          'roles.read',
          () => goTo(AppRoutes.roles),
        ),
      ]),
    ];
  }

  Widget _menu(BuildContext context, {VoidCallback? before}) => _SidebarMenu(
    sections: _sections(context, before: before),
    loading: _loadingPermissions,
    failed: _permissionsFailed,
    onRetry: _loadPermissions,
    signingOut: _isSigningOut,
    onSignOut: () {
      before?.call();
      _signOut();
    },
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _isSigningOut ? null : _signOut,
            icon: _isSigningOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: Builder(
                  builder: (drawerContext) => _menu(
                    drawerContext,
                    before: () => Navigator.of(drawerContext).pop(),
                  ),
                ),
              ),
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Container(
              width: 280,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(right: BorderSide(color: scheme.outlineVariant)),
              ),
              child: _menu(context),
            ),
          Expanded(child: DemoDashboard(wide: wide)),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.visible,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final bool visible;
  final int badge;
  final Future<void> Function() onTap;
}

class _NavSection {
  const _NavSection(this.title, this.icon, this.items);

  final String title;
  final IconData icon;
  final List<_NavItem> items;
}

/// Menú lateral con secciones que se abren y cierran al hacer clic.
class _SidebarMenu extends StatelessWidget {
  const _SidebarMenu({
    required this.sections,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.signingOut,
    required this.onSignOut,
  });

  final bool signingOut;
  final VoidCallback onSignOut;
  final List<_NavSection> sections;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: _list(context)),
      const Divider(height: 1),
      ListTile(
        leading: signingOut
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout_rounded),
        title: const Text('Cerrar sesión'),
        onTap: signingOut ? null : onSignOut,
      ),
    ],
  );

  Widget _list(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.eco_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text('RiExport', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        for (final section in sections)
          if (section.items.any((i) => i.visible))
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey('nav-${section.title}'),
                initiallyExpanded: true,
                leading: Icon(section.icon),
                title: Text(section.title),
                childrenPadding: const EdgeInsets.only(left: 12),
                children: [
                  for (final item in section.items)
                    if (item.visible)
                      ListTile(
                        dense: true,
                        leading: Badge(
                          isLabelVisible: item.badge > 0,
                          label: Text('${item.badge}'),
                          child: Icon(item.icon),
                        ),
                        title: Text(item.label),
                        onTap: item.onTap,
                      ),
                ],
              ),
            ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (failed)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('No se pudieron cargar tus permisos. Reintentar'),
          ),
      ],
    );
  }
}

/// Línea de tiempo de un envío: [source] es `/shipments` (personal con
/// `logistics.read`) o `/tracking` (cliente externo con `portal.read`).
class _ShipmentTimelineRoute extends StatelessWidget {
  const _ShipmentTimelineRoute({
    required this.shipmentId,
    required this.source,
  });

  final int shipmentId;
  final String source;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final staff = source == '/shipments';
    return FutureBuilder<Set<String>>(
      future: staff ? _loadPermissions(context) : Future.value(const {}),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final canUpdate = snapshot.data!.contains('logistics.update');
        return ShipmentTimelineScreen(
          shipmentId: shipmentId,
          loadShipment: (id) async {
            final rows = await _loadItems(context, source, {'id': '$id'});
            if (rows.isEmpty) throw StateError('Envío no encontrado');
            return rows.first;
          },
          loadEvents: (id) => _loadItems(context, '/shipments/$id/events'),
          updateStatus: canUpdate
              ? (id, change) async {
                  await api.post('/shipments/$id/status', body: change);
                }
              : null,
          addEvent: canUpdate
              ? (id, event) async {
                  await api.post('/shipments/$id/events', body: event);
                }
              : null,
        );
      },
    );
  }
}

/// Seguimiento para el cliente externo (PLAT-637/639): solo sus envíos.
class _TrackingList extends StatefulWidget {
  @override
  State<_TrackingList> createState() => _TrackingListState();
}

class _TrackingListState extends State<_TrackingList> {
  late final Future<List<Map<String, dynamic>>> _future = _loadItems(
    context,
    '/tracking',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seguimiento de mis envíos')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('No se pudo cargar el seguimiento de tus envíos.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('Todavía no tienes envíos.'));
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            return ListTile(
              title: Text(
                'Pedido ${row['order_number'] ?? ''} · ${row['status_label'] ?? row['status']}',
              ),
              subtitle: Text(
                [
                  if ('${row['carrier'] ?? ''}'.isNotEmpty) '${row['carrier']}',
                  if ('${row['tracking_number'] ?? ''}'.isNotEmpty)
                    'Guía ${row['tracking_number']}',
                  if ('${row['last_location'] ?? ''}'.isNotEmpty)
                    'Última ubicación: ${row['last_location']}',
                  if (row['estimated_delivery_at'] != null)
                    'ETA ${row['estimated_delivery_at']}',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/tracking/${row['shipment_id']}'),
            );
          },
        );
      },
    ),
  );
}
