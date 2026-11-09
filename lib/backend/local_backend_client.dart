import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_orders_store.dart';
import 'local_exports_store.dart';
import 'local_backend_store.dart';
import 'local_demo_store.dart';

/// Cliente HTTP que resuelve las rutas de la API dentro de la propia app.
///
/// Reemplaza al servidor FastAPI: [ApiClient] sigue construyendo peticiones
/// `/auth`, `/me`, `/users` y `/roles`, y este cliente las atiende sobre
/// [LocalBackendStore] sin red.
class LocalBackendClient extends http.BaseClient {
  LocalBackendClient({LocalBackendStore? store})
    : _store = store ?? LocalBackendStore();

  final LocalBackendStore _store;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final requestId = request.headers['X-Request-ID'] ?? 'local';
    try {
      final payload = body.isEmpty ? null : jsonDecode(body);
      final result = _route(
        request.method,
        request.url.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList(),
        request.url.queryParameters,
        payload,
        request.headers['Authorization'],
      );
      return _response(result.status, result.body, requestId);
    } on LocalBackendError catch (error) {
      return _response(error.status, {
        'error': {
          'code': error.code,
          'message': error.message,
          'details': error.details,
          'request_id': requestId,
        },
      }, requestId);
    } on FormatException {
      return _response(400, {
        'error': {
          'code': 'BAD_REQUEST',
          'message': 'La solicitud no es JSON válido.',
          'request_id': requestId,
        },
      }, requestId);
    }
  }

  _Result _route(
    String method,
    List<String> segments,
    Map<String, String> query,
    Object? payload,
    String? authorization,
  ) {
    // La URL base es `/api/v1`; las rutas de dominio empiezan tras ese prefijo.
    final path = segments.length >= 2 && segments.first == 'api'
        ? segments.sublist(2)
        : segments;
    if (path.isEmpty) throw LocalBackendError.notFound();
    final json = payload is Map<String, dynamic> ? payload : null;

    switch (path.first) {
      case 'auth':
        if (method == 'POST' && path.length == 2 && path[1] == 'login') {
          return _Result(200, _store.login(json));
        }
        if (method == 'POST' && path.length == 2 && path[1] == 'register') {
          return _Result(201, _store.register(json));
        }
        if (method == 'POST' && path.length == 2 && path[1] == 'logout') {
          return const _Result(204, null);
        }
        if (method == 'POST' &&
            path.length == 2 &&
            path[1] == 'password-reset-requests') {
          return _Result(202, _store.requestPasswordReset(json));
        }
        if (method == 'POST' &&
            path.length == 2 &&
            path[1] == 'email-confirmations') {
          // El modo local no exige confirmar el correo: las cuentas nacen activas.
          return const _Result(200, {
            'message': 'Correo confirmado. Ya puedes iniciar sesión.',
          });
        }
        if (method == 'POST' &&
            path.length == 2 &&
            path[1] == 'password-resets') {
          _store.resetPassword(json);
          return const _Result(204, null);
        }
      case 'me':
        final me = _store.requireSession(authorization);
        if (path.length == 1 && method == 'GET') {
          return _Result(200, _store.me(me));
        }
        if (path.length == 1 && method == 'PATCH') {
          final isEmail = json?.containsKey('email') ?? false;
          return _Result(
            200,
            isEmail
                ? _store.changeOwnEmail(me, json)
                : _store.changeOwnProfile(me, json),
          );
        }
      case 'users':
        final actor = _store.requireSession(authorization);
        if (path.length == 1) {
          if (method == 'GET') return _Result(200, _store.listUsers(query));
          if (method == 'POST') return _Result(201, _store.createUser(json));
        }
        final userId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (userId != null && path.length == 2 && method == 'PATCH') {
          return _Result(200, _store.updateUser(userId, json, actorId: actor));
        }
        if (userId != null &&
            path.length == 3 &&
            path[2] == 'deactivate' &&
            method == 'PATCH') {
          return _Result(
            200,
            _store.deactivateUser(userId, _store.requireSession(authorization)),
          );
        }
        if (userId != null &&
            path.length == 3 &&
            path[2] == 'activate' &&
            method == 'PATCH') {
          return _Result(200, _store.activateUser(userId));
        }
      case 'products':
        final productActor = _store.requireSession(authorization);
        final productId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(productActor, 'products.read');
          return _Result(200, _store.products.list(query));
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(productActor, 'products.create');
          return _Result(201, _store.products.create(json));
        }
        if (productId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(productActor, 'products.read');
          return _Result(200, _store.products.get(productId));
        }
        if (productId != null && path.length == 2 && method == 'PATCH') {
          _store.requirePermission(productActor, 'products.update');
          return _Result(200, _store.products.update(productId, json));
        }
        if (productId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'PATCH') {
          _store.requirePermission(productActor, 'products.update');
          return _Result(200, _store.products.setActive(productId, json));
        }
        if (productId != null &&
            path.length == 3 &&
            path[2] == 'certifications' &&
            method == 'PUT') {
          _store.requirePermission(productActor, 'products.update');
          return _Result(
            200,
            _store.products.setCertifications(productId, json),
          );
        }
      case 'suppliers':
        final supplierActor = _store.requireSession(authorization);
        final supplierId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(supplierActor, 'suppliers.read');
          return _Result(200, _store.suppliers.list(query));
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(supplierActor, 'suppliers.create');
          return _Result(201, _store.suppliers.create(json));
        }
        if (supplierId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(supplierActor, 'suppliers.read');
          return _Result(200, _store.suppliers.get(supplierId));
        }
        if (supplierId != null && path.length == 2 && method == 'PATCH') {
          _store.requirePermission(supplierActor, 'suppliers.update');
          return _Result(200, _store.suppliers.update(supplierId, json));
        }
        if (supplierId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'PATCH') {
          _store.requirePermission(supplierActor, 'suppliers.update');
          return _Result(200, _store.suppliers.setActive(supplierId, json));
        }
      case 'customers':
        final customerActor = _store.requireSession(authorization);
        final customerId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(customerActor, 'customers.read');
          return _Result(200, _store.customers.list(query));
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(customerActor, 'customers.create');
          return _Result(201, _store.customers.create(json));
        }
        if (customerId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(customerActor, 'customers.read');
          return _Result(200, _store.customers.get(customerId));
        }
        if (customerId != null && path.length == 2 && method == 'PATCH') {
          _store.requirePermission(customerActor, 'customers.update');
          return _Result(200, _store.customers.update(customerId, json));
        }
        if (customerId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'PATCH') {
          _store.requirePermission(customerActor, 'customers.update');
          return _Result(200, _store.customers.setActive(customerId, json));
        }
        if (customerId != null &&
            path.length == 3 &&
            path[2] == 'history' &&
            method == 'GET') {
          _store.requirePermission(customerActor, 'customers.read');
          _store.customers.get(customerId); // 404 si no existe
          final orders = _store.orders.all
              .where((order) => order['customer_id'] == customerId)
              .toList();
          final orderIds = orders.map((order) => order['id']).toSet();
          final exports = _store.exports.all
              .where((item) => orderIds.contains(item['order_id']))
              .toList();
          return _Result(200, {
            'available': true,
            'orders': orders,
            'exports_available': true,
            'exports': exports,
          });
        }
        if (customerId != null && path.length == 3 && path[2] == 'accounts') {
          if (method == 'GET') {
            _store.requirePermission(customerActor, 'customers.read');
            return _Result(
              200,
              _store.customers.accounts(customerId, _store.accountById),
            );
          }
          if (method == 'POST') {
            _store.requirePermission(customerActor, 'customers.update');
            return _Result(
              201,
              _store.customers.link(
                customerId,
                json,
                _store.accountByEmail,
                _store.accountById,
              ),
            );
          }
        }
        final profileId = path.length == 4 ? int.tryParse(path[3]) : null;
        if (customerId != null &&
            profileId != null &&
            path[2] == 'accounts' &&
            method == 'DELETE') {
          _store.requirePermission(customerActor, 'customers.update');
          return _Result(
            200,
            _store.customers.unlink(customerId, profileId, _store.accountById),
          );
        }
      case 'orders':
        final orderActor = _store.requireSession(authorization);
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(orderActor, 'orders.read');
          final status = query['status'];
          final customerId = int.tryParse(query['customer_id'] ?? '');
          final needle = query['q']?.trim().toLowerCase();
          final rows = _store.orders.all.where((order) {
            if (status != null && order['status'] != status) return false;
            if (customerId != null && order['customer_id'] != customerId) {
              return false;
            }
            if (needle != null && needle.isNotEmpty) {
              final number = '${order['order_number']}'.toLowerCase();
              final customer = '${order['customer_name']}'.toLowerCase();
              if (!number.contains(needle) && !customer.contains(needle)) {
                return false;
              }
            }
            return true;
          }).toList();
          return _Result(200, {
            'items': rows,
            'pagination': {
              'total': rows.length,
              'limit': rows.length,
              'offset': 0,
            },
          });
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(orderActor, 'orders.create');
          try {
            return _Result(201, _store.orders.create(json));
          } on LocalOrderError catch (error) {
            throw LocalBackendError.validation(error.field, error.message);
          }
        }
        final orderId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (orderId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(orderActor, 'orders.read');
          try {
            return _Result(200, _store.orders.get(orderId));
          } on LocalOrderError catch (error) {
            throw LocalBackendError.notFound(error.message);
          }
        }
        if (orderId != null && path.length == 2 && method == 'PATCH') {
          _store.requirePermission(orderActor, 'orders.update');
          try {
            return _Result(200, _store.orders.update(orderId, json));
          } on LocalOrderError catch (error) {
            throw LocalBackendError.validation(error.field, error.message);
          }
        }
        if (orderId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'PATCH') {
          _store.requirePermission(orderActor, 'orders.transition');
          try {
            return _Result(200, _store.orders.transition(orderId, json));
          } on LocalOrderError catch (error) {
            throw LocalBackendError.validation(error.field, error.message);
          }
        }
      case 'inventory':
        final inventoryActor = _store.requireSession(authorization);
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(inventoryActor, 'inventory.read');
          return _Result(200, _store.inventory.list(query));
        }
        if (path.length == 2 && path[1] == 'overview' && method == 'GET') {
          _store.requirePermission(inventoryActor, 'inventory.read');
          return _Result(200, _store.inventory.overview(query));
        }
        if (path.length == 2 && path[1] == 'adjustments' && method == 'POST') {
          _store.requirePermission(inventoryActor, 'inventory.adjust');
          return _Result(201, _store.inventory.adjust(json));
        }
      case 'exports':
        final exportActor = _store.requireSession(authorization);
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(exportActor, 'exports.read');
          final exportStatus = query['status'];
          final exportNeedle = query['q']?.trim().toLowerCase();
          final exportRows = _store.exports.all.where((row) {
            if (exportStatus != null && row['status'] != exportStatus) {
              return false;
            }
            if (exportNeedle == null || exportNeedle.isEmpty) return true;
            return [
              row['order_number'],
              row['customer_name'],
              row['destination_country_code'],
            ].any((v) => '$v'.toLowerCase().contains(exportNeedle));
          }).toList();
          return _Result(200, {
            'items': exportRows,
            'pagination': {
              'total': exportRows.length,
              'limit': 100,
              'offset': 0,
            },
          });
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(exportActor, 'exports.create');
          try {
            return _Result(201, _store.exports.create(json));
          } on LocalExportError catch (error) {
            throw LocalBackendError.validation(error.field, error.message);
          }
        }
        final exportId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (exportId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(exportActor, 'exports.read');
          try {
            return _Result(200, _store.exports.get(exportId));
          } on LocalExportError catch (error) {
            throw LocalBackendError.notFound(error.message);
          }
        }
        if (exportId != null &&
            path.length == 3 &&
            method == 'GET' &&
            (path[2] == 'traceability' || path[2] == 'origin-farms')) {
          _store.requirePermission(exportActor, 'exports.read');
          try {
            final items = path[2] == 'traceability'
                ? _store.exports.traceability(exportId)
                : _store.exports.originFarms(exportId);
            return _Result(200, {'items': items});
          } on LocalExportError catch (error) {
            throw LocalBackendError.notFound(error.message);
          }
        }
        if (exportId != null &&
            path.length == 3 &&
            method == 'POST' &&
            path[2] == 'documents') {
          _store.requirePermission(exportActor, 'exports.read');
          throw const LocalBackendError(
            501,
            'NOT_IMPLEMENTED',
            'La generación de PDF requiere Supabase (Edge Function); no está disponible en modo local.',
          );
        }
        if (exportId != null &&
            path.length == 3 &&
            method == 'GET' &&
            path[2] == 'eudr') {
          _store.requirePermission(exportActor, 'exports.read');
          try {
            return _Result(200, _store.exports.generateEudr(exportId));
          } on LocalExportError catch (error) {
            throw LocalBackendError.notFound(error.message);
          }
        }
      case 'export-catalogs':
        final catalogActor = _store.requireSession(authorization);
        if (method == 'GET' && path.length == 2) {
          if (!_store.hasPermission(catalogActor, 'exports.create') &&
              !_store.hasPermission(catalogActor, 'exports.read')) {
            _store.requirePermission(catalogActor, 'exports.create');
          }
          final items = switch (path[1]) {
            'destinations' => LocalExportsStore.destinations,
            'incoterms' => LocalExportsStore.incoterms,
            _ => null,
          };
          if (items != null) return _Result(200, {'items': items});
        }
      case 'shipments':
        final logisticsActor = _store.requireSession(authorization);
        _store.requirePermission(logisticsActor, 'logistics.read');
        final demoShipmentId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          return _Result(200, _store.demo.listShipments(query));
        }
        if (path.length == 3 && path[2] == 'origin-farms' && method == 'GET') {
          return const _Result(200, {'items': <Object?>[]});
        }
        if (demoShipmentId != null && path.length == 3 && path[2] == 'events') {
          if (method == 'GET') {
            return _Result(200, _store.demo.listEvents(demoShipmentId));
          }
          if (method == 'POST') {
            _store.requirePermission(logisticsActor, 'logistics.update');
            return _Result(201, _store.demo.addEvent(demoShipmentId, json));
          }
        }
        if (demoShipmentId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'POST') {
          _store.requirePermission(logisticsActor, 'logistics.update');
          return _Result(200, _store.demo.updateStatus(demoShipmentId, json));
        }
      case 'shipment-statuses':
        _store.requireSession(authorization);
        if (method == 'GET') {
          return _Result(200, {
            'items': LocalDemoStore.statuses,
            'pagination': {'total': 5, 'limit': 100, 'offset': 0},
          });
        }
      case 'tracking':
        final trackingActor = _store.requireSession(authorization);
        _store.requirePermission(trackingActor, 'portal.read');
        if (method == 'GET') return _Result(200, _store.demo.tracking(query));
      case 'payments':
        final paymentActor = _store.requireSession(authorization);
        final p1 = path.length >= 2 ? path[1] : '';
        if (method == 'GET') {
          _store.requirePermission(paymentActor, 'payments.read');
          switch (p1) {
            case 'portfolio':
              return _Result(200, _store.demo.portfolio(query));
            case 'convert':
              return _Result(200, _store.demo.convert(query));
            case 'exchange-rates':
              return _Result(200, _store.demo.listRates());
          }
        }
        if (method == 'POST') {
          _store.requirePermission(paymentActor, 'payments.create');
          switch (p1) {
            case 'exchange-rates':
              if (path.length == 3 && path[2] == 'refresh') {
                // Sin internet/servicio externo en modo local: se conservan las tasas demo.
                return const _Result(200, {
                  'source': 'demo',
                  'saved': <Object?>[],
                });
              }
              return _Result(201, _store.demo.addRate(json));
            case 'transactions':
              return _Result(201, _store.demo.addTransaction(json));
            case 'obligations':
              return _Result(201, _store.demo.addObligation(json));
          }
        }
      case 'notifications':
        _store.requireSession(authorization);
        final notificationId = path.length == 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          return _Result(200, _store.demo.listNotifications(query));
        }
        if (path.length == 2 && path[1] == 'read-all' && method == 'POST') {
          return _Result(200, _store.demo.readAll());
        }
        if (path.length == 2 && path[1] == 'refresh' && method == 'POST') {
          return const _Result(200, {'skipped': true});
        }
        if (notificationId != null && method == 'PATCH') {
          return _Result(
            200,
            _store.demo.markNotification(notificationId, json),
          );
        }
      case 'farms':
        final farmActor = _store.requireSession(authorization);
        final farmId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(farmActor, 'farms.read');
          return _Result(200, _store.origin.listFarms(query));
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(farmActor, 'farms.create');
          return _Result(201, _store.origin.createFarm(json));
        }
        if (farmId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(farmActor, 'farms.read');
          return _Result(200, _store.origin.getFarm(farmId));
        }
        if (farmId != null && path.length == 2 && method == 'PATCH') {
          _store.requirePermission(farmActor, 'farms.update');
          return _Result(200, _store.origin.updateFarm(farmId, json));
        }
        if (farmId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'PATCH') {
          _store.requirePermission(farmActor, 'farms.update');
          return _Result(200, _store.origin.setFarmActive(farmId, json));
        }
      case 'lots':
        final lotActor = _store.requireSession(authorization);
        final lotId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (path.length == 1 && method == 'GET') {
          _store.requirePermission(lotActor, 'lots.read');
          return _Result(200, _store.origin.listLots(query));
        }
        if (path.length == 1 && method == 'POST') {
          _store.requirePermission(lotActor, 'lots.create');
          return _Result(201, _store.origin.createLot(json));
        }
        if (lotId != null && path.length == 2 && method == 'GET') {
          _store.requirePermission(lotActor, 'lots.read');
          return _Result(200, _store.origin.getLot(lotId));
        }
      case 'certifications':
        _store.requireSession(authorization);
        if (path.length == 1 && method == 'GET') {
          return _Result(200, _store.products.listCertifications());
        }
      case 'units':
        _store.requireSession(authorization);
        if (path.length == 1 && method == 'GET') {
          return _Result(200, _store.products.listUnits());
        }
      case 'roles':
        _store.requireSession(authorization);
        if (path.length == 1) {
          if (method == 'GET') return _Result(200, _store.listRoles(query));
          if (method == 'POST') return _Result(201, _store.createRole(json));
        }
        if (path.length == 2 && path[1] == 'permissions' && method == 'GET') {
          return _Result(200, _store.listPermissions());
        }
        final roleId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (roleId != null && path.length == 2 && method == 'PATCH') {
          return _Result(200, _store.updateRole(roleId, json));
        }
        if (roleId != null && path.length == 3 && method == 'PUT') {
          if (path[2] == 'permissions') {
            return _Result(200, _store.setRolePermissions(roleId, json));
          }
        }
        if (roleId != null &&
            path.length == 3 &&
            path[2] == 'deactivate' &&
            method == 'PATCH') {
          return _Result(200, _store.deactivateRole(roleId));
        }
    }
    throw LocalBackendError.notFound();
  }

  http.StreamedResponse _response(int status, Object? body, String requestId) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-request-id': requestId,
        },
      );
}

class _Result {
  const _Result(this.status, this.body);

  final int status;
  final Object? body;
}
