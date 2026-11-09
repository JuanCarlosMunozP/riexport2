import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Credenciales públicas de Supabase, tomadas del `.env` con
/// `--dart-define-from-file=.env`. Si faltan, la app usa el backend local.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get supabaseConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

/// Backend de la app sobre Supabase (Auth + PostgREST), sin servidor propio.
///
/// Atiende las mismas rutas que [LocalBackendClient] (`/auth`, `/me`, `/users`,
/// `/roles`), de modo que [ApiClient] y las pantallas no cambian. Las reglas de
/// negocio y los permisos los aplica la base (ver `database/migrations/`).
class SupabaseBackendClient extends http.BaseClient {
  SupabaseBackendClient({
    required String url,
    required this.anonKey,
    http.Client? inner,
  }) : _base = _validatedBaseUri(url),
       _inner = inner ?? http.Client();

  static Uri _validatedBaseUri(String url) {
    final uri = Uri.parse(url);
    final isLoopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(uri.host.toLowerCase());
    if (!uri.isAbsolute ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme == 'http' && !isLoopback)) {
      throw ArgumentError.value(
        url,
        'url',
        'Supabase requiere HTTPS; HTTP solo se permite en localhost.',
      );
    }
    return Uri.parse(url.endsWith('/') ? url : '$url/');
  }

  final Uri _base;
  final String anonKey;
  final http.Client _inner;

  static const _roleSelect =
      'id,name,description,is_active,role_permission(permission_code)';
  static const _productSelect =
      'id,type,variety,quality_grade,hs_code,base_unit_code,base_unit_name,'
      'low_stock_threshold,is_active,created_at,updated_at,humidity_percent,'
      'bean_type,fermentation_percent,certifications,certification_ids';
  static const _supplierSelect =
      'id,business_name,tax_id,contact_name,phone,email,location,is_active,'
      'created_at,updated_at';
  static const _customerSelect =
      'id,name,contact_name,email,country_code,eori_number,'
      'preferred_currency_code,is_active,created_at,updated_at';
  static const _farmSelect =
      'id,supplier_id,supplier_name,country_code,name,address,latitude,'
      'longitude,is_active,created_at,updated_at,lot_count';
  static const _lotSelect =
      'id,lot_code,created_at,product_id,product_type,product_variety,'
      'product_quality,farm_id,farm_name,country_code,latitude,longitude,'
      'supplier_id,supplier_name';
  static const _userSelect =
      'id,email,first_name,last_name,phone,role_id,is_active';
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final requestId = request.headers['X-Request-ID'] ?? 'supabase';
    try {
      final payload = body.isEmpty ? null : jsonDecode(body);
      final json = payload is Map<String, dynamic> ? payload : null;
      final path = request.url.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      final trimmed = path.length >= 2 && path.first == 'api'
          ? path.sublist(2)
          : path;
      final result = await _route(
        request.method,
        trimmed,
        request.url.queryParameters,
        json,
        request.headers['Authorization'],
      );
      return _response(result.status, result.body, requestId);
    } on _Failure catch (failure) {
      return _response(failure.status, {
        'error': {
          'code': failure.code,
          'message': failure.message,
          'details': failure.details,
          'request_id': requestId,
        },
      }, requestId);
    } on FormatException {
      return _response(502, {
        'error': {
          'code': 'INVALID_RESPONSE',
          'message': 'Supabase devolvió una respuesta no válida.',
          'request_id': requestId,
        },
      }, requestId);
    }
  }

  @override
  void close() => _inner.close();

  // ---- Rutas ---------------------------------------------------------------

  Future<_Result> _route(
    String method,
    List<String> path,
    Map<String, String> query,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (path.isEmpty) throw _Failure.notFound();
    switch (path.first) {
      case 'auth':
        if (method == 'POST' && path.length == 2) {
          if (path[1] == 'login') return _login(body);
          if (path[1] == 'register') return _register(body);
          if (path[1] == 'logout') return _logout(authorization);
          if (path[1] == 'password-reset-requests') {
            return _requestPasswordReset(body);
          }
          if (path[1] == 'password-resets') return _resetPassword(body);
          if (path[1] == 'email-confirmations') return _confirmEmail(body);
        }
      case 'me':
        if (path.length == 1 && method == 'GET') return _me(authorization);
        if (path.length == 1 && method == 'PATCH') {
          return _updateMe(body, authorization);
        }
      case 'users':
        if (path.length == 1 && method == 'GET') {
          return _listUsers(query, authorization);
        }
        final userId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (userId != null && path.length == 2 && method == 'PATCH') {
          return _updateUser(userId, body, authorization);
        }
        if (userId != null &&
            path.length == 3 &&
            path[2] == 'deactivate' &&
            method == 'PATCH') {
          return _updateUser(userId, {'is_active': false}, authorization);
        }
        if (userId != null &&
            path.length == 3 &&
            path[2] == 'activate' &&
            method == 'PATCH') {
          return _updateUser(userId, {'is_active': true}, authorization);
        }
      case 'products':
        if (path.length == 1 && method == 'GET') {
          return _listProducts(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createProduct(body, authorization);
        }
        final productId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (productId != null) {
          if (path.length == 2 && method == 'GET') {
            return _Result(200, await _productRow(productId, authorization));
          }
          if (path.length == 2 && method == 'PATCH') {
            return _updateProduct(productId, body, authorization);
          }
          if (path.length == 3 && path[2] == 'status' && method == 'PATCH') {
            return _setProductActive(productId, body, authorization);
          }
          if (path.length == 3 &&
              path[2] == 'certifications' &&
              method == 'PUT') {
            return _setProductCertifications(productId, body, authorization);
          }
        }
      case 'suppliers':
        if (path.length == 1 && method == 'GET') {
          return _listSuppliers(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createSupplier(body, authorization);
        }
        final supplierId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (supplierId != null) {
          if (path.length == 2 && method == 'GET') {
            return _Result(200, await _supplierRow(supplierId, authorization));
          }
          if (path.length == 2 && method == 'PATCH') {
            return _updateSupplier(supplierId, body, authorization);
          }
          if (path.length == 3 && path[2] == 'status' && method == 'PATCH') {
            return _setSupplierActive(supplierId, body, authorization);
          }
        }
      case 'customers':
        if (path.length == 1 && method == 'GET') {
          return _listCustomers(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createCustomer(body, authorization);
        }
        final customerId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (customerId != null) {
          if (path.length == 2 && method == 'GET') {
            return _Result(200, await _customerRow(customerId, authorization));
          }
          if (path.length == 2 && method == 'PATCH') {
            return _updateCustomer(customerId, body, authorization);
          }
          if (path.length == 3 && path[2] == 'status' && method == 'PATCH') {
            return _setCustomerActive(customerId, body, authorization);
          }
          if (path.length == 3 && path[2] == 'history' && method == 'GET') {
            return _customerHistory(customerId, authorization);
          }
          if (path.length == 3 && path[2] == 'accounts') {
            if (method == 'GET') {
              return _customerAccounts(customerId, authorization);
            }
            if (method == 'POST') {
              _checked(
                await _call(
                  'POST',
                  'rest/v1/rpc/link_customer_user',
                  body: {
                    'p_customer_id': customerId,
                    'p_email': body?['email'] is String ? body!['email'] : '',
                  },
                  token: _bearer(authorization),
                ),
              );
              final accounts = await _customerAccounts(
                customerId,
                authorization,
              );
              return _Result(201, accounts.body);
            }
          }
          final profileId = path.length == 4 ? int.tryParse(path[3]) : null;
          if (profileId != null &&
              path[2] == 'accounts' &&
              method == 'DELETE') {
            _checked(
              await _call(
                'POST',
                'rest/v1/rpc/unlink_customer_user',
                body: {'p_customer_id': customerId, 'p_profile_id': profileId},
                token: _bearer(authorization),
              ),
            );
            return _customerAccounts(customerId, authorization);
          }
        }
      case 'orders':
        if (path.length == 1 && method == 'GET') {
          return _listOrders(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createOrder(body, authorization);
        }
        final orderId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (orderId != null && path.length == 2 && method == 'GET') {
          return _orderRow(orderId, authorization);
        }
        if (orderId != null && path.length == 2 && method == 'PATCH') {
          return _updateOrder(orderId, body, authorization);
        }
        if (orderId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'PATCH') {
          return _transitionOrder(orderId, body, authorization);
        }
      case 'export-catalogs':
        if (path.length == 2 && method == 'GET') {
          final table = switch (path[1]) {
            'destinations' => 'export_destination',
            'incoterms' => 'incoterm',
            _ => null,
          };
          if (table != null) {
            return _page(
              table,
              {
                'select': 'code,name',
                'is_active': 'eq.true',
                'order': 'name.asc',
              },
              100,
              0,
              authorization,
            );
          }
        }
      case 'inventory':
        if (path.length == 1 && method == 'GET') {
          return _listInventory(query, authorization);
        }
        if (path.length == 2 && path[1] == 'overview' && method == 'GET') {
          return _page(
            'inventory_overview',
            {
              'select': '*',
              if (query['low_stock'] == 'true') 'is_low_stock': 'eq.true',
              'order': 'is_low_stock.desc,variety.asc',
            },
            100,
            0,
            authorization,
          );
        }
        if (path.length == 2 && path[1] == 'adjustments' && method == 'POST') {
          if (body == null) {
            throw _Failure.validation('body', 'La solicitud no es válida.');
          }
          final result = _checked(
            await _call(
              'POST',
              'rest/v1/rpc/adjust_lot_inventory',
              body: {'p': body},
              token: _bearer(authorization),
            ),
          );
          return _Result(201, {'id': result});
        }
      case 'exports':
        if (path.length == 1 && method == 'GET') {
          return _listExports(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          if (body == null) {
            throw _Failure.validation('body', 'La solicitud no es válida.');
          }
          final result = _checked(
            await _call(
              'POST',
              'rest/v1/rpc/create_customer_export',
              body: {'p': body},
              token: _bearer(authorization),
            ),
          );
          if (result is! Map) throw _Failure.upstream();
          return _Result(201, Map<String, dynamic>.from(result));
        }
        final exportId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (exportId != null && path.length == 3 && method == 'GET') {
          final view = switch (path[2]) {
            'traceability' => 'export_traceability',
            'origin-farms' => 'export_origin_farms',
            _ => null,
          };
          if (view != null) {
            return _listExportMap(view, 'export_id', exportId, authorization);
          }
          if (path[2] == 'eudr') {
            final result = _checked(
              await _call(
                'POST',
                'rest/v1/rpc/export_eudr_declaration',
                body: {'p_export_id': exportId},
                token: _bearer(authorization),
              ),
            );
            if (result is! Map) throw _Failure.upstream();
            return _Result(200, Map<String, dynamic>.from(result));
          }
        }
        if (exportId != null && path.length == 3 && path[2] == 'documents') {
          if (method == 'GET') return _exportDossier(exportId, authorization);
          if (method == 'POST') {
            return _generateDocument(exportId, body, authorization);
          }
        }
        if (exportId != null &&
            path.length == 4 &&
            path[2] == 'documents' &&
            path[3] == 'upload' &&
            method == 'POST') {
          return _uploadDocument(exportId, body, authorization);
        }
      case 'shipments':
        if (path.length == 1 && method == 'GET') {
          return _listShipments(query, authorization);
        }
        final shipmentId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (shipmentId != null &&
            path.length == 3 &&
            path[2] == 'origin-farms' &&
            method == 'GET') {
          return _listExportMap(
            'shipment_origin_farms',
            'shipment_id',
            shipmentId,
            authorization,
          );
        }
        if (path.length == 1 && method == 'POST') {
          return _insertRow('shipment', body, authorization);
        }
        if (shipmentId != null && path.length == 2 && method == 'PATCH') {
          if (body == null ||
              body.isEmpty ||
              body.keys.any((key) => !_shipmentEditable.contains(key))) {
            throw _Failure.validation(
              'body',
              'Solo se pueden editar los datos de transporte.',
            );
          }
          return _updateRow('shipment', shipmentId, {
            ...body,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, authorization);
        }
        if (shipmentId != null &&
            path.length == 3 &&
            path[2] == 'status' &&
            method == 'POST') {
          if (body == null) {
            throw _Failure.validation('body', 'La solicitud no es válida.');
          }
          final result = await _rpc('update_shipment_status', {
            'p': {...body, 'shipment_id': shipmentId},
          }, authorization);
          if (result is! Map) throw _Failure.upstream();
          return _Result(200, Map<String, dynamic>.from(result));
        }
        if (shipmentId != null && path.length == 3 && path[2] == 'events') {
          if (method == 'GET') {
            return _page(
              'shipment_event',
              {
                'select': '*',
                'shipment_id': 'eq.$shipmentId',
                'order': 'event_at.desc',
              },
              100,
              0,
              authorization,
            );
          }
          if (method == 'POST') {
            if (body == null) {
              throw _Failure.validation('body', 'La solicitud no es válida.');
            }
            final id = await _rpc('add_shipment_event', {
              'p': {...body, 'shipment_id': shipmentId},
            }, authorization);
            return _Result(201, {'id': id});
          }
        }
      case 'shipment-statuses':
        if (path.length == 1 && method == 'GET') {
          return _page(
            'shipment_status',
            {'select': '*', 'order': 'sort_order.asc'},
            100,
            0,
            authorization,
          );
        }
      case 'tracking':
        if (path.length == 1 && method == 'GET') {
          final trackedId = int.tryParse(query['id'] ?? '');
          return _page(
            'customer_shipment_tracking',
            {
              'select': '*',
              if (trackedId != null) 'shipment_id': 'eq.$trackedId',
              'order': 'last_event_at.desc.nullslast',
            },
            100,
            0,
            authorization,
          );
        }
      case 'payments':
        if (path.length == 2 && path[1] == 'portfolio' && method == 'GET') {
          return _paymentPortfolio(query, authorization);
        }
        if (path.length == 2 && path[1] == 'convert' && method == 'GET') {
          final amount = num.tryParse(query['amount'] ?? '');
          if (amount == null) {
            throw _Failure.validation('amount', 'Indica un monto numérico.');
          }
          final result = await _rpc('convert_amount', {
            'p_amount': amount,
            'p_from': (query['from'] ?? '').toUpperCase(),
            'p_to': (query['to'] ?? '').toUpperCase(),
          }, authorization);
          if (result is! Map) throw _Failure.upstream();
          return _Result(200, Map<String, dynamic>.from(result));
        }
        if (path.length == 3 &&
            path[1] == 'exchange-rates' &&
            path[2] == 'refresh' &&
            method == 'POST') {
          final result = _checked(
            await _call(
              'POST',
              'functions/v1/refresh-exchange-rates',
              body: const <String, Object?>{},
              token: _bearer(authorization),
            ),
          );
          return _Result(
            200,
            result is Map ? Map<String, dynamic>.from(result) : {'saved': []},
          );
        }
        if (path.length == 2 &&
            path[1] == 'exchange-rates' &&
            method == 'POST') {
          if (body == null) {
            throw _Failure.validation('body', 'La solicitud no es válida.');
          }
          final id = await _rpc('register_exchange_rate', {
            'p': body,
          }, authorization);
          return _Result(201, {'id': id});
        }
        if (path.length == 2 && path[1] == 'obligations') {
          if (method == 'GET') {
            return _page(
              'payment_obligation',
              {'select': '*', 'order': 'due_date.asc,id.asc'},
              100,
              0,
              authorization,
            );
          }
          if (method == 'POST') {
            return _insertRow('payment_obligation', body, authorization);
          }
        }
        if (path.length == 2 && path[1] == 'transactions') {
          if (method == 'GET') {
            return _page(
              'payment_transaction',
              {'select': '*', 'order': 'paid_at.desc,id.desc'},
              100,
              0,
              authorization,
            );
          }
          if (method == 'POST') {
            return _insertRow('payment_transaction', body, authorization);
          }
        }
        if (path.length == 2 &&
            path[1] == 'exchange-rates' &&
            method == 'GET') {
          return _page(
            'exchange_rate',
            {'select': '*', 'order': 'effective_at.desc,id.desc'},
            100,
            0,
            authorization,
          );
        }
      case 'documents':
        if (path.length == 1 && method == 'GET') {
          return _exportDossier(
            int.tryParse(query['export_id'] ?? ''),
            authorization,
          );
        }
        final documentId = path.length == 3 ? int.tryParse(path[1]) : null;
        if (documentId != null && path[2] == 'download' && method == 'GET') {
          return _documentDownload(documentId, authorization);
        }
      case 'notifications':
        if (path.length == 1 && method == 'GET') {
          return _page(
            'notification',
            {
              'select': '*',
              if (query['unread'] == 'true') 'read_at': 'is.null',
              'order': 'created_at.desc,id.desc',
            },
            (int.tryParse(query['limit'] ?? '') ?? 100).clamp(1, 100),
            0,
            authorization,
          );
        }
        if (path.length == 2 && path[1] == 'read-all' && method == 'POST') {
          final count = await _rpc(
            'mark_all_notifications_read',
            const <String, Object?>{},
            authorization,
          );
          return _Result(200, {'updated': count});
        }
        if (path.length == 2 && path[1] == 'refresh' && method == 'POST') {
          final result = await _rpc(
            'run_scheduled_alerts',
            const <String, Object?>{},
            authorization,
          );
          return _Result(
            200,
            result is Map
                ? Map<String, dynamic>.from(result)
                : {'skipped': true},
          );
        }
        final notificationId = path.length == 2 ? int.tryParse(path[1]) : null;
        if (notificationId != null && method == 'PATCH') {
          if (body == null || body.keys.any((key) => key != 'read_at')) {
            throw _Failure.validation(
              'body',
              'Solo se permite actualizar read_at.',
            );
          }
          return _updateRow(
            'notification',
            notificationId,
            body,
            authorization,
          );
        }
      case 'farms':
        if (path.length == 1 && method == 'GET') {
          return _listFarms(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createFarm(body, authorization);
        }
        final farmId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (farmId != null) {
          if (path.length == 2 && method == 'GET') {
            return _Result(200, await _farmRow(farmId, authorization));
          }
          if (path.length == 2 && method == 'PATCH') {
            return _updateFarm(farmId, body, authorization);
          }
          if (path.length == 3 && path[2] == 'status' && method == 'PATCH') {
            return _setFarmActive(farmId, body, authorization);
          }
        }
      case 'lots':
        if (path.length == 1 && method == 'GET') {
          return _listLots(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createLot(body, authorization);
        }
        final lotId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (lotId != null && path.length == 2 && method == 'GET') {
          return _Result(200, await _lotRow(lotId, authorization));
        }
      case 'certifications':
        if (path.length == 1 && method == 'GET') {
          return _simpleList(
            'certification',
            'id,code,name,is_active',
            'name.asc',
            authorization,
          );
        }
      case 'units':
        if (path.length == 1 && method == 'GET') {
          return _simpleList(
            'unit_of_measure',
            'code,name',
            'code.asc',
            authorization,
          );
        }
      case 'roles':
        if (path.length == 1 && method == 'GET') {
          return _listRoles(query, authorization);
        }
        if (path.length == 1 && method == 'POST') {
          return _createRole(body, authorization);
        }
        if (path.length == 2 && path[1] == 'permissions' && method == 'GET') {
          return _listPermissions(authorization);
        }
        final roleId = path.length >= 2 ? int.tryParse(path[1]) : null;
        if (roleId != null && path.length == 2 && method == 'PATCH') {
          return _updateRole(roleId, body, authorization);
        }
        if (roleId != null &&
            path.length == 3 &&
            path[2] == 'permissions' &&
            method == 'PUT') {
          return _setRolePermissions(roleId, body, authorization);
        }
        if (roleId != null &&
            path.length == 3 &&
            path[2] == 'deactivate' &&
            method == 'PATCH') {
          return _updateRole(roleId, {'is_active': false}, authorization);
        }
    }
    throw _Failure.notFound();
  }

  // ---- Autenticación -------------------------------------------------------

  Future<_Result> _login(Map<String, dynamic>? body) async {
    final email = _text(body, 'email')?.trim().toLowerCase() ?? '';
    final password = _text(body, 'password') ?? '';
    if (email.isEmpty || password.isEmpty) throw _Failure.invalidCredentials();

    final response = await _call(
      'POST',
      'auth/v1/token',
      query: {'grant_type': 'password'},
      body: {'email': email, 'password': password},
    );
    final data = _decode(response);
    if (response.statusCode >= 400) {
      final code = data is Map ? data['error_code'] ?? data['code'] : null;
      if (code == 'email_not_confirmed') {
        throw const _Failure(
          401,
          'UNAUTHORIZED',
          'Confirma tu correo electrónico antes de iniciar sesión.',
        );
      }
      if (response.statusCode >= 500) throw _Failure.upstream();
      throw _Failure.invalidCredentials();
    }
    if (data is! Map || data['access_token'] is! String) {
      throw _Failure.upstream();
    }
    final token = data['access_token'] as String;

    // La cuenta debe estar activa y con un rol activo.
    final profile = await _call(
      'GET',
      'rest/v1/profile',
      query: {'select': 'is_active,role(is_active)', 'limit': '1'},
      token: token,
    );
    final rows = _decode(profile);
    if (profile.statusCode >= 400 || rows is! List || rows.isEmpty) {
      throw _Failure.invalidCredentials();
    }
    final row = rows.first as Map;
    final role = row['role'];
    if (row['is_active'] != true ||
        (role is Map && role['is_active'] != true)) {
      throw _Failure.invalidCredentials();
    }
    return _Result(200, {
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': data['expires_in'] ?? 3600,
    });
  }

  Future<_Result> _register(Map<String, dynamic>? body) async {
    final email = _text(body, 'email')?.trim().toLowerCase() ?? '';
    final password = _text(body, 'password') ?? '';
    final firstName = _text(body, 'first_name')?.trim() ?? '';
    final lastName = _text(body, 'last_name')?.trim() ?? '';
    final phone = _text(body, 'phone')?.trim();
    if (!_emailPattern.hasMatch(email)) {
      throw _Failure.validation('email', 'Ingresa un correo válido.');
    }
    if (firstName.isEmpty) {
      throw _Failure.validation('first_name', 'Este campo es obligatorio.');
    }
    if (lastName.isEmpty) {
      throw _Failure.validation('last_name', 'Este campo es obligatorio.');
    }
    if (password.isEmpty) {
      throw _Failure.validation('password', 'Ingresa una contraseña.');
    }

    final response = await _call(
      'POST',
      'auth/v1/signup',
      body: {
        'email': email,
        'password': password,
        // El rol no se envía: el trigger de la base asigna siempre "cliente".
        'data': {
          'first_name': firstName,
          'last_name': lastName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      },
    );
    if (response.statusCode >= 400) {
      final data = _decode(response);
      final code = data is Map ? data['error_code'] ?? data['code'] : null;
      if (code == 'user_already_exists' || code == 'email_exists') {
        throw _Failure.conflict(
          'Ya existe un usuario con ese correo electrónico.',
        );
      }
      if (code == 'weak_password') {
        throw _Failure.validation(
          'password',
          'Usa al menos 12 caracteres con mayúscula, minúscula, número y símbolo.',
        );
      }
      if (code == 'over_email_send_rate_limit' || response.statusCode == 429) {
        throw const _Failure(
          429,
          'RATE_LIMIT_EXCEEDED',
          'Se excedió el límite de correos. Inténtalo más tarde.',
        );
      }
      if (response.statusCode >= 500) throw _Failure.upstream();
      // Supabase responde en inglés: se traduce a un mensaje accionable.
      final detail = (_message(data) ?? '').toLowerCase();
      if (detail.contains('password')) {
        throw _Failure.validation('password', 'Ingresa una contraseña válida.');
      }
      throw _Failure.validation('email', 'Ingresa un correo válido.');
    }
    return const _Result(201, {'message': 'Cuenta creada.'});
  }

  /// Revoca la sesión en Supabase Auth (solo este dispositivo). Sin token no hay
  /// nada que revocar. Si falla, el cierre local ya basta: el llamador lo ignora.
  Future<_Result> _logout(String? authorization) async {
    final token = _bearer(authorization);
    if (token != null && token.isNotEmpty) {
      await _call(
        'POST',
        'auth/v1/logout',
        query: {'scope': 'local'},
        token: token,
      );
    }
    return const _Result(204, null);
  }

  // ---- Recuperación de acceso (código de un solo uso por correo) -------------

  /// Pide el código. La respuesta es siempre la misma, exista o no la cuenta,
  /// para no revelar qué correos están registrados.
  Future<_Result> _requestPasswordReset(Map<String, dynamic>? body) async {
    final email = _text(body, 'email')?.trim().toLowerCase() ?? '';
    if (!_emailPattern.hasMatch(email)) {
      throw _Failure.validation('email', 'Ingresa un correo válido.');
    }
    final response = await _call(
      'POST',
      'auth/v1/recover',
      body: {'email': email},
    );
    final data = response.statusCode >= 400 ? _decode(response) : null;
    final code = data is Map ? data['error_code'] ?? data['code'] : null;
    if (response.statusCode == 429 ||
        code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      throw const _Failure(
        429,
        'RATE_LIMIT_EXCEEDED',
        'Se excedió el límite de correos. Inténtalo en unos minutos.',
      );
    }
    if (response.statusCode >= 500) throw _Failure.upstream();
    return const _Result(202, {
      'message':
          'Si existe una cuenta con ese correo, te enviamos un código para restablecer tu contraseña.',
    });
  }

  /// PLAT-449: canjea el código de 6 dígitos enviado al correo del registro y
  /// descarta la sesión que Supabase abre al verificarlo.
  Future<_Result> _confirmEmail(Map<String, dynamic>? body) async {
    final email = _text(body, 'email')?.trim().toLowerCase() ?? '';
    final code = _text(body, 'code')?.trim() ?? '';
    if (!_emailPattern.hasMatch(email)) {
      throw _Failure.validation('email', 'Ingresa un correo válido.');
    }
    if (!RegExp(r'^[0-9]{6,10}$').hasMatch(code)) {
      throw _Failure.validation('code', 'Ingresa el código de 6 dígitos.');
    }
    final verified = await _call(
      'POST',
      'auth/v1/verify',
      body: {'type': 'signup', 'email': email, 'token': code},
    );
    if (verified.statusCode == 429) {
      throw const _Failure(
        429,
        'RATE_LIMIT_EXCEEDED',
        'Demasiados intentos. Inténtalo en unos minutos.',
      );
    }
    if (verified.statusCode >= 500) throw _Failure.upstream();
    final session = verified.statusCode < 400 ? _decode(verified) : null;
    final token = session is Map ? session['access_token'] : null;
    if (token is! String || token.isEmpty) {
      throw const _Failure(
        400,
        'INVALID_CODE',
        'El código no es válido o ya venció. Regístrate de nuevo o solicita otro.',
      );
    }
    try {
      await _call(
        'POST',
        'auth/v1/logout',
        query: {'scope': 'local'},
        token: token,
      );
    } on Object {
      // La cuenta ya quedó confirmada; el cierre de la sesión temporal es de mejor esfuerzo.
    }
    return const _Result(200, {
      'message': 'Correo confirmado. Ya puedes iniciar sesión.',
    });
  }

  /// Canjea el código (sesión temporal de Supabase), cambia la contraseña y
  /// cierra esa sesión temporal.
  Future<_Result> _resetPassword(Map<String, dynamic>? body) async {
    final email = _text(body, 'email')?.trim().toLowerCase() ?? '';
    final code = _text(body, 'code')?.trim() ?? '';
    final password = _text(body, 'new_password') ?? '';
    if (!_emailPattern.hasMatch(email)) {
      throw _Failure.validation('email', 'Ingresa un correo válido.');
    }
    if (!RegExp(r'^[0-9]{6,10}$').hasMatch(code)) {
      throw _Failure.validation('code', 'Ingresa el código de 6 dígitos.');
    }
    if (password.isEmpty) {
      throw _Failure.validation('new_password', 'Ingresa una contraseña.');
    }

    const invalidCode = _Failure(
      400,
      'INVALID_CODE',
      'El código no es válido o ya venció. Solicita uno nuevo.',
    );
    final verified = await _call(
      'POST',
      'auth/v1/verify',
      body: {'type': 'recovery', 'email': email, 'token': code},
    );
    if (verified.statusCode == 429) {
      throw const _Failure(
        429,
        'RATE_LIMIT_EXCEEDED',
        'Demasiados intentos. Inténtalo en unos minutos.',
      );
    }
    if (verified.statusCode >= 500) throw _Failure.upstream();
    final session = verified.statusCode < 400 ? _decode(verified) : null;
    final token = session is Map ? session['access_token'] : null;
    if (token is! String || token.isEmpty) throw invalidCode;

    final updated = await _call(
      'PUT',
      'auth/v1/user',
      body: {'password': password},
      token: token,
    );
    // La sesión temporal del canje no debe quedar abierta (mejor esfuerzo).
    try {
      await _call(
        'POST',
        'auth/v1/logout',
        query: {'scope': 'local'},
        token: token,
      );
    } on Object {
      // El cambio de contraseña ya se resolvió; no se reporta este fallo.
    }
    if (updated.statusCode >= 400) {
      final data = _decode(updated);
      final reason = data is Map ? data['error_code'] ?? data['code'] : null;
      if (reason == 'weak_password') {
        throw _Failure.validation(
          'new_password',
          'Usa al menos 12 caracteres con mayúscula, minúscula, número y símbolo.',
        );
      }
      if (reason == 'same_password') {
        throw _Failure.validation(
          'new_password',
          'La nueva contraseña debe ser distinta de la anterior.',
        );
      }
      if (updated.statusCode >= 500) throw _Failure.upstream();
      throw invalidCode;
    }
    return const _Result(204, null);
  }

  // ---- Perfil propio -------------------------------------------------------

  Future<_Result> _me(String? authorization) async {
    final token = _bearer(authorization);
    final uid = _subject(token);
    if (token == null || uid == null) {
      throw const _Failure(
        401,
        'UNAUTHORIZED',
        'Se requiere autenticación válida.',
      );
    }
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/profile',
        query: {
          'select':
              '$_userSelect,role(is_active,role_permission(permission_code))',
          'auth_user_id': 'eq.$uid',
          'limit': '1',
        },
        token: token,
      ),
    );
    if (rows is! List || rows.isEmpty) {
      // La base no devuelve el perfil propio si la cuenta fue desactivada: la
      // sesión ya no es válida y la app debe cerrarla.
      throw const _Failure(
        401,
        'UNAUTHORIZED',
        'Tu cuenta no está activa. Inicia sesión de nuevo o contacta al administrador.',
      );
    }
    // Los permisos salen del rol del usuario; un rol inactivo no concede ninguno.
    final row = Map<String, dynamic>.from(rows.first as Map);
    final role = row.remove('role');
    final links = role is Map && role['is_active'] == true
        ? role['role_permission']
        : null;
    row['permission_codes'] = [
      if (links is List)
        for (final link in links)
          if (link is Map && link['permission_code'] is String)
            link['permission_code'] as String,
    ]..sort();
    return _Result(200, row);
  }

  /// `PATCH /me`: o bien cambia el correo (flujo con confirmación), o bien los
  /// datos personales (nombres y teléfono); nunca ambos en la misma petición.
  Future<_Result> _updateMe(Map<String, dynamic>? body, String? authorization) {
    const profileFields = {'first_name', 'last_name', 'phone'};
    final hasEmail = body?.containsKey('email') ?? false;
    final hasProfile = body?.keys.any(profileFields.contains) ?? false;
    if (hasEmail && hasProfile) {
      throw _Failure.validation(
        'body',
        'Cambia el correo y los datos personales por separado.',
      );
    }
    return hasEmail
        ? _changeOwnEmail(body, authorization)
        : _updateOwnProfile(body, authorization);
  }

  /// Autoedición de nombres y teléfono. La base solo permite esos campos al
  /// titular (política `profile_update_self` y trigger `profile_guard`).
  Future<_Result> _updateOwnProfile(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final token = _bearer(authorization);
    final uid = _subject(token);
    if (token == null || uid == null) {
      throw const _Failure(
        401,
        'UNAUTHORIZED',
        'Se requiere autenticación válida.',
      );
    }
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    final changes = <String, Object?>{};
    for (final entry in body.entries) {
      final value = entry.value is String ? (entry.value as String).trim() : '';
      switch (entry.key) {
        case 'first_name' || 'last_name':
          if (value.isEmpty) {
            throw _Failure.validation(entry.key, 'Este campo es obligatorio.');
          }
          if (value.length > 100) {
            throw _Failure.validation(entry.key, 'Máximo 100 caracteres.');
          }
          changes[entry.key] = value;
        case 'phone':
          if (value.length > 32) {
            throw _Failure.validation('phone', 'Máximo 32 caracteres.');
          }
          changes['phone'] = value.isEmpty ? null : value;
        default:
          throw _Failure.validation(entry.key, 'Campo no permitido.');
      }
    }
    final rows = _checked(
      await _call(
        'PATCH',
        'rest/v1/profile',
        query: {'auth_user_id': 'eq.$uid', 'select': _userSelect},
        body: changes,
        token: token,
        headers: {'Prefer': 'return=representation'},
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró tu perfil.');
    }
    return _Result(200, rows.first);
  }

  /// Cambia el correo del propio titular con Supabase Auth. El cambio queda
  /// pendiente hasta confirmarlo desde el enlace enviado al correo nuevo; un
  /// trigger de la base copia entonces el correo confirmado a `profile`.
  Future<_Result> _changeOwnEmail(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final token = _bearer(authorization);
    if (token == null || _subject(token) == null) {
      throw const _Failure(
        401,
        'UNAUTHORIZED',
        'Se requiere autenticación válida.',
      );
    }
    final email = _text(body, 'email')?.trim().toLowerCase() ?? '';
    if (!_emailPattern.hasMatch(email)) {
      throw _Failure.validation('email', 'Ingresa un correo válido.');
    }
    final response = await _call(
      'PUT',
      'auth/v1/user',
      body: {'email': email},
      token: token,
    );
    if (response.statusCode >= 400) {
      Object? data;
      try {
        data = _decode(response);
      } on FormatException {
        data = null;
      }
      final code = data is Map ? data['error_code'] ?? data['code'] : null;
      if (response.statusCode == 401 || code == 'bad_jwt') {
        throw const _Failure(
          401,
          'UNAUTHORIZED',
          'Tu sesión expiró. Inicia sesión de nuevo.',
        );
      }
      if (code == 'email_exists') {
        throw _Failure.conflict(
          'Ya existe un usuario con ese correo electrónico.',
        );
      }
      if (code == 'same_email') {
        throw _Failure.validation(
          'email',
          'Ese ya es tu correo electrónico actual.',
        );
      }
      if (code == 'over_email_send_rate_limit' || response.statusCode == 429) {
        throw const _Failure(
          429,
          'RATE_LIMIT_EXCEEDED',
          'Se excedió el límite de correos. Inténtalo más tarde.',
        );
      }
      if (response.statusCode >= 500) throw _Failure.upstream();
      throw _Failure.validation('email', _message(data) ?? 'Correo no válido.');
    }
    return _Result(200, {
      'pending_email': email,
      'message':
          'Te enviamos enlaces de confirmación: revisa el correo nuevo ($email) '
          'y también el actual, si se te pide. El cambio se aplica al confirmarlo.',
    });
  }

  /// `sub` (id de Supabase Auth) del JWT de la sesión, sin validar la firma:
  /// solo sirve para filtrar; la autorización real la aplica la base (RLS).
  String? _subject(String? token) {
    final segments = token?.split('.');
    if (segments == null || segments.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      final sub = payload is Map ? payload['sub'] : null;
      return sub is String && sub.isNotEmpty ? sub : null;
    } on FormatException {
      return null;
    }
  }

  // ---- Usuarios ------------------------------------------------------------

  Future<_Result> _listUsers(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': '$_userSelect,role_name',
      'order': 'id.asc',
      'limit': '$limit',
      'offset': '$offset',
    };
    final active = query['is_active'];
    if (active == 'true' || active == 'false') {
      params['is_active'] = 'eq.$active';
    }
    final text = _cleanText(query['q']);
    if (text.isNotEmpty) {
      params['or'] =
          '(first_name.ilike.*$text*,last_name.ilike.*$text*,email.ilike.*$text*)';
    }
    // La vista `admin_user_list` (security_invoker) añade el nombre del rol y
    // respeta las mismas políticas RLS que la tabla `profile`.
    final response = await _call(
      'GET',
      'rest/v1/admin_user_list',
      query: params,
      token: _bearer(authorization),
      headers: {'Prefer': 'count=exact'},
    );
    final rows = _checked(response);
    if (rows is! List) throw _Failure.upstream();
    final range = response.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last) ?? rows.length;
    return _Result(200, {
      'items': rows,
      'pagination': {'total': total, 'limit': limit, 'offset': offset},
    });
  }

  Future<_Result> _updateUser(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    final changes = <String, Object?>{};
    for (final entry in body.entries) {
      switch (entry.key) {
        case 'first_name' || 'last_name':
          final value = entry.value is String
              ? (entry.value as String).trim()
              : '';
          if (value.isEmpty) {
            throw _Failure.validation(entry.key, 'Este campo es obligatorio.');
          }
          changes[entry.key] = value;
        case 'phone':
          final value = entry.value is String
              ? (entry.value as String).trim()
              : '';
          changes['phone'] = value.isEmpty ? null : value;
        case 'role_id':
          if (entry.value is! int) {
            throw _Failure.validation('role_id', 'Indica el rol.');
          }
          changes['role_id'] = entry.value;
        case 'is_active':
          changes['is_active'] = entry.value == true;
        case 'email':
          // El correo es la credencial de Supabase Auth: no se edita desde la app.
          throw _Failure.validation(
            'email',
            'El correo electrónico no se puede cambiar desde la app.',
          );
        default:
          throw _Failure.validation(entry.key, 'Campo no permitido.');
      }
    }
    final response = await _call(
      'PATCH',
      'rest/v1/profile',
      query: {'id': 'eq.$id', 'select': _userSelect},
      body: changes,
      token: _bearer(authorization),
      headers: {'Prefer': 'return=representation'},
    );
    final rows = _checked(response);
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el usuario solicitado.');
    }
    return _Result(200, rows.first);
  }

  // ---- Productos -----------------------------------------------------------

  Future<_Result> _simpleList(
    String table,
    String select,
    String order,
    String? authorization,
  ) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/$table',
        query: {'select': select, 'order': order},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List) throw _Failure.upstream();
    return _Result(200, {'items': rows});
  }

  Future<_Result> _listProducts(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': _productSelect,
      'order': 'variety.asc,id.asc',
      'limit': '$limit',
      'offset': '$offset',
    };
    final type = query['type'];
    if (type == 'coffee' || type == 'cacao') params['type'] = 'eq.$type';
    final active = query['is_active'];
    if (active == 'true' || active == 'false') {
      params['is_active'] = 'eq.$active';
    }
    final certification = int.tryParse(query['certification_id'] ?? '');
    if (certification != null) {
      params['certification_ids'] = 'cs.{$certification}';
    }
    String clean(String? value) => _cleanText(value);
    final quality = clean(query['quality']);
    if (quality.isNotEmpty) params['quality_grade'] = 'ilike.*$quality*';
    final text = clean(query['q']);
    if (text.isNotEmpty) {
      params['or'] = '(variety.ilike.*$text*,quality_grade.ilike.*$text*)';
    }
    final response = await _call(
      'GET',
      'rest/v1/product_catalog',
      query: params,
      token: _bearer(authorization),
      headers: {'Prefer': 'count=exact'},
    );
    final rows = _checked(response);
    if (rows is! List) throw _Failure.upstream();
    final range = response.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last) ?? rows.length;
    return _Result(200, {
      'items': rows,
      'pagination': {'total': total, 'limit': limit, 'offset': offset},
    });
  }

  Future<Object?> _productRow(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/product_catalog',
        query: {'id': 'eq.$id', 'select': _productSelect},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el producto solicitado.');
    }
    return rows.first;
  }

  Future<_Result> _createProduct(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final id = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/create_product',
        body: {'p': body},
        token: _bearer(authorization),
      ),
    );
    if (id is! int) throw _Failure.upstream();
    return _Result(201, await _productRow(id, authorization));
  }

  Future<_Result> _updateProduct(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/update_product',
        body: {'p_id': id, 'p': body},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _productRow(id, authorization));
  }

  Future<_Result> _setProductActive(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final active = body?['is_active'];
    if (active is! bool) {
      throw _Failure.validation(
        'is_active',
        'Indica si el producto debe quedar activo.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/set_product_active',
        body: {'p_id': id, 'p_active': active},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _productRow(id, authorization));
  }

  Future<_Result> _setProductCertifications(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final ids = body?['certification_ids'];
    if (ids is! List || ids.any((e) => e is! int)) {
      throw _Failure.validation(
        'certification_ids',
        'Las certificaciones deben ser una lista de identificadores.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/set_product_certifications',
        body: {'p_id': id, 'p_ids': ids},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _productRow(id, authorization));
  }

  // ---- Proveedores ---------------------------------------------------------

  Future<_Result> _listSuppliers(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': _supplierSelect,
      'order': 'business_name.asc,id.asc',
      'limit': '$limit',
      'offset': '$offset',
    };
    final active = query['is_active'];
    if (active == 'true' || active == 'false') {
      params['is_active'] = 'eq.$active';
    }
    final text = (query['q'] ?? '')
        .replaceAll(RegExp(r'[,()*%\\]'), ' ')
        .trim();
    if (text.isNotEmpty) {
      params['or'] = '(business_name.ilike.*$text*,tax_id.ilike.*$text*)';
    }
    final response = await _call(
      'GET',
      'rest/v1/supplier',
      query: params,
      token: _bearer(authorization),
      headers: {'Prefer': 'count=exact'},
    );
    final rows = _checked(response);
    if (rows is! List) throw _Failure.upstream();
    final range = response.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last) ?? rows.length;
    return _Result(200, {
      'items': rows,
      'pagination': {'total': total, 'limit': limit, 'offset': offset},
    });
  }

  Future<Object?> _supplierRow(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/supplier',
        query: {'id': 'eq.$id', 'select': _supplierSelect},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el proveedor solicitado.');
    }
    return rows.first;
  }

  Future<_Result> _createSupplier(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final id = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/create_supplier',
        body: {'p': body},
        token: _bearer(authorization),
      ),
    );
    if (id is! int) throw _Failure.upstream();
    return _Result(201, await _supplierRow(id, authorization));
  }

  Future<_Result> _updateSupplier(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/update_supplier',
        body: {'p_id': id, 'p': body},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _supplierRow(id, authorization));
  }

  Future<_Result> _setSupplierActive(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final active = body?['is_active'];
    if (active is! bool) {
      throw _Failure.validation(
        'is_active',
        'Indica si el proveedor debe quedar activo.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/set_supplier_active',
        body: {'p_id': id, 'p_active': active},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _supplierRow(id, authorization));
  }

  // ---- Clientes ------------------------------------------------------------

  Future<_Result> _listCustomers(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': _customerSelect,
      'order': 'name.asc,id.asc',
      'limit': '$limit',
      'offset': '$offset',
    };
    final active = query['is_active'];
    if (active == 'true' || active == 'false') {
      params['is_active'] = 'eq.$active';
    }
    final country = (query['country_code'] ?? '').trim().toUpperCase();
    if (RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      params['country_code'] = 'eq.$country';
    }
    final text = _cleanText(query['q']);
    if (text.isNotEmpty) {
      // El EORI se guarda normalizado: se busca también con el texto normalizado.
      final eori = text.replaceAll(RegExp(r'[\s.\-]'), '').toUpperCase();
      params['or'] =
          '(name.ilike.*$text*${eori.isEmpty ? '' : ',eori_number.ilike.*$eori*'})';
    }
    final response = await _call(
      'GET',
      'rest/v1/customer',
      query: params,
      token: _bearer(authorization),
      headers: {'Prefer': 'count=exact'},
    );
    final rows = _checked(response);
    if (rows is! List) throw _Failure.upstream();
    final range = response.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last) ?? rows.length;
    return _Result(200, {
      'items': rows,
      'pagination': {'total': total, 'limit': limit, 'offset': offset},
    });
  }

  /// Historial comercial: pedidos y exportaciones del cliente. Las vistas
  /// dependen de módulos que aún no existen (database/drafts/customer_history.sql);
  /// mientras falten, PostgREST responde 404 y se informa `available: false`.
  Future<_Result> _customerHistory(
    int customerId,
    String? authorization,
  ) async {
    final orders = await _call(
      'GET',
      'rest/v1/customer_order_history',
      query: {
        'customer_id': 'eq.$customerId',
        'select':
            'order_id,order_number,status,currency_code,created_at,'
            'order_total,export_count,last_export_date',
        'order': 'created_at.desc',
      },
      token: _bearer(authorization),
    );
    if (orders.statusCode == 404) {
      return const _Result(200, {
        'available': false,
        'orders': <Object?>[],
        'exports': <Object?>[],
      });
    }
    final orderRows = _checked(orders);
    final exports = await _call(
      'GET',
      'rest/v1/customer_export_history',
      query: {
        'customer_id': 'eq.$customerId',
        'select':
            'export_id,order_id,order_number,destination_country_code,'
            'export_date,status',
        'order': 'export_date.desc',
      },
      token: _bearer(authorization),
    );
    final exportRows = exports.statusCode == 404
        ? <Object?>[]
        : _checked(exports);
    if (orderRows is! List || exportRows is! List) throw _Failure.upstream();
    return _Result(200, {
      'available': true,
      'exports_available': exports.statusCode != 404,
      'orders': orderRows,
      'exports': exportRows,
    });
  }

  Future<_Result> _customerAccounts(
    int customerId,
    String? authorization,
  ) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/customer_account_link',
        query: {
          'customer_id': 'eq.$customerId',
          'select':
              'customer_id,profile_id,email,first_name,last_name,'
              'account_is_active,has_portal_access',
          'order': 'email.asc',
        },
        token: _bearer(authorization),
      ),
    );
    if (rows is! List) throw _Failure.upstream();
    return _Result(200, {'items': rows});
  }

  Future<Object?> _customerRow(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/customer',
        query: {'id': 'eq.$id', 'select': _customerSelect},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el cliente solicitado.');
    }
    return rows.first;
  }

  Future<_Result> _createCustomer(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final id = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/create_customer',
        body: {'p': body},
        token: _bearer(authorization),
      ),
    );
    if (id is! int) throw _Failure.upstream();
    return _Result(201, await _customerRow(id, authorization));
  }

  Future<_Result> _createOrder(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final result = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/create_customer_order',
        body: {'p': body},
        token: _bearer(authorization),
      ),
    );
    if (result is! Map) throw _Failure.upstream();
    return _Result(201, Map<String, dynamic>.from(result));
  }

  Future<_Result> _orderRow(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/customer_order_details',
        query: {
          'id': 'eq.$id',
          'select':
              'id,order_number,customer_id,customer_name,status,currency_code,note,created_at,updated_at,line_count,order_total,lines',
        },
        token: _bearer(authorization),
      ),
    );
    if (rows is! List) throw _Failure.upstream();
    if (rows.isEmpty) throw _Failure.notFound('No se encontró el pedido.');
    return _Result(200, Map<String, dynamic>.from(rows.first as Map));
  }

  Future<_Result> _updateOrder(
    int orderId,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null ||
        body.keys.any(
          (key) => !{'customer_id', 'note', 'lines'}.contains(key),
        )) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final result = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/update_customer_order',
        body: {
          'p': {'order_id': orderId, ...body},
        },
        token: _bearer(authorization),
      ),
    );
    if (result is! Map) throw _Failure.upstream();
    return _Result(200, Map<String, dynamic>.from(result));
  }

  Future<_Result> _listOrders(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final filters = <String, String>{};
    final status = query['status'];
    if (status != null) {
      if (!{'draft', 'confirmed', 'cancelled'}.contains(status)) {
        throw _Failure.validation(
          'status',
          'El estado del pedido no es válido.',
        );
      }
      filters['status'] = 'eq.$status';
    }
    final customerId = int.tryParse(query['customer_id'] ?? '');
    if (customerId != null) filters['customer_id'] = 'eq.$customerId';
    final rawQuery = query['q']?.trim();
    if (rawQuery != null && rawQuery.isNotEmpty) {
      final normalizedQuery = rawQuery.replaceAll(
        RegExp(r'[^\p{L}\p{N} ._#-]', unicode: true),
        '',
      );
      final safeQuery = normalizedQuery.substring(
        0,
        normalizedQuery.length > 80 ? 80 : normalizedQuery.length,
      );
      if (safeQuery.isNotEmpty) {
        filters['or'] =
            '(order_number.ilike.*$safeQuery*,customer_name.ilike.*$safeQuery*)';
      }
    }
    final response = await _call(
      'GET',
      'rest/v1/customer_order_details',
      query: {
        ...filters,
        'select':
            'id,order_number,customer_id,customer_name,status,currency_code,note,created_at,line_count,order_total,lines',
        'order': 'created_at.desc',
        'limit': '$limit',
        'offset': '$offset',
      },
      token: _bearer(authorization),
      headers: {'Prefer': 'count=exact'},
    );
    final rows = _checked(response);
    if (rows is! List) throw _Failure.upstream();
    final range = response.headers['content-range'];
    final total = range == null
        ? rows.length
        : int.tryParse(range.split('/').last) ?? rows.length;
    return _Result(200, {
      'items': rows,
      'pagination': {'total': total, 'limit': limit, 'offset': offset},
    });
  }

  Future<_Result> _transitionOrder(
    int orderId,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null ||
        body.keys.any((key) => !{'status', 'note'}.contains(key))) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final result = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/transition_customer_order',
        body: {
          'p': {'order_id': orderId, ...body},
        },
        token: _bearer(authorization),
      ),
    );
    if (result is! Map) throw _Failure.upstream();
    return _Result(200, Map<String, dynamic>.from(result));
  }

  Future<_Result> _updateCustomer(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/update_customer',
        body: {'p_id': id, 'p': body},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _customerRow(id, authorization));
  }

  Future<_Result> _setCustomerActive(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final active = body?['is_active'];
    if (active is! bool) {
      throw _Failure.validation(
        'is_active',
        'Indica si el cliente debe quedar activo.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/set_customer_active',
        body: {'p_id': id, 'p_active': active},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _customerRow(id, authorization));
  }

  // ---- Fincas y lotes ------------------------------------------------------

  Future<_Result> _page(
    String table,
    Map<String, String> params,
    int limit,
    int offset,
    String? authorization,
  ) async {
    final response = await _call(
      'GET',
      'rest/v1/$table',
      query: {...params, 'limit': '$limit', 'offset': '$offset'},
      token: _bearer(authorization),
      headers: {'Prefer': 'count=exact'},
    );
    final rows = _checked(response);
    if (rows is! List) throw _Failure.upstream();
    final range = response.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last) ?? rows.length;
    return _Result(200, {
      'items': rows,
      'pagination': {'total': total, 'limit': limit, 'offset': offset},
    });
  }

  Future<_Result> _insertRow(
    String table,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final rows = _checked(
      await _call(
        'POST',
        'rest/v1/$table',
        body: body,
        token: _bearer(authorization),
        headers: {'Prefer': 'return=representation'},
      ),
    );
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw _Failure.upstream();
    }
    return _Result(201, Map<String, dynamic>.from(rows.first as Map));
  }

  Future<_Result> _updateRow(
    String table,
    int id,
    Map<String, dynamic> body,
    String? authorization,
  ) async {
    final rows = _checked(
      await _call(
        'PATCH',
        'rest/v1/$table',
        query: {'id': 'eq.$id'},
        body: body,
        token: _bearer(authorization),
        headers: {'Prefer': 'return=representation'},
      ),
    );
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw _Failure.notFound();
    }
    return _Result(200, Map<String, dynamic>.from(rows.first as Map));
  }

  static String _cleanText(String? value) {
    final cleaned = (value ?? '').replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    return cleaned.substring(0, cleaned.length > 80 ? 80 : cleaned.length);
  }

  Future<_Result> _listFarms(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': _farmSelect,
      'order': 'name.asc,id.asc',
    };
    final active = query['is_active'];
    if (active == 'true' || active == 'false') {
      params['is_active'] = 'eq.$active';
    }
    final supplier = int.tryParse(query['supplier_id'] ?? '');
    if (supplier != null) params['supplier_id'] = 'eq.$supplier';
    final text = _cleanText(query['q']);
    if (text.isNotEmpty) {
      params['or'] = '(name.ilike.*$text*,supplier_name.ilike.*$text*)';
    }
    return _page('farm_catalog', params, limit, offset, authorization);
  }

  Future<Object?> _farmRow(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/farm_catalog',
        query: {'id': 'eq.$id', 'select': _farmSelect},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró la finca solicitada.');
    }
    return rows.first;
  }

  Future<_Result> _createFarm(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final id = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/create_farm',
        body: {'p': body},
        token: _bearer(authorization),
      ),
    );
    if (id is! int) throw _Failure.upstream();
    return _Result(201, await _farmRow(id, authorization));
  }

  Future<_Result> _updateFarm(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/update_farm',
        body: {'p_id': id, 'p': body},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _farmRow(id, authorization));
  }

  Future<_Result> _setFarmActive(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final active = body?['is_active'];
    if (active is! bool) {
      throw _Failure.validation(
        'is_active',
        'Indica si la finca debe quedar activa.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/set_farm_active',
        body: {'p_id': id, 'p_active': active},
        token: _bearer(authorization),
      ),
    );
    return _Result(200, await _farmRow(id, authorization));
  }

  Future<_Result> _listLots(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{'select': _lotSelect, 'order': 'id.desc'};
    final farm = int.tryParse(query['farm_id'] ?? '');
    if (farm != null) params['farm_id'] = 'eq.$farm';
    final product = int.tryParse(query['product_id'] ?? '');
    if (product != null) params['product_id'] = 'eq.$product';
    final text = _cleanText(query['q']);
    if (text.isNotEmpty) params['lot_code'] = 'ilike.*$text*';
    return _page('lot_catalog', params, limit, offset, authorization);
  }

  Future<_Result> _listInventory(
    Map<String, String> query,
    String? authorization,
  ) async {
    final lotsResult = await _listLots(query, authorization);
    final page = Map<String, dynamic>.from(lotsResult.body as Map);
    final lots = (page['items'] as List).cast<Map>();
    if (lots.isEmpty) return lotsResult;
    final ids = lots.map((lot) => '${lot['id']}').join(',');
    final availability = _checked(
      await _call(
        'GET',
        'rest/v1/lot_inventory_availability',
        query: {
          'select': 'product_lot_id,available_quantity',
          'product_lot_id': 'in.($ids)',
        },
        token: _bearer(authorization),
      ),
    );
    if (availability is! List) throw _Failure.upstream();
    final byLot = <String, Object?>{
      for (final row in availability.whereType<Map>())
        '${row['product_lot_id']}': row['available_quantity'],
    };
    page['items'] = [
      for (final lot in lots)
        {
          ...Map<String, dynamic>.from(lot),
          'available_quantity': byLot['${lot['id']}'] ?? 0,
        },
    ];
    return _Result(200, page);
  }

  Future<_Result> _listExports(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': '*',
      'order': 'export_date.desc,id.desc',
    };
    final status = query['status'];
    if (status != null) {
      if (!{'draft', 'formalized', 'cancelled'}.contains(status)) {
        throw _Failure.validation(
          'status',
          'El estado de la exportación no es válido.',
        );
      }
      params['status'] = 'eq.$status';
    }
    final q = _cleanText(query['q']);
    if (q.isNotEmpty) {
      params['or'] =
          '(order_number.ilike.*$q*,customer_name.ilike.*$q*,destination_country_code.ilike.*$q*)';
    }
    return _page('export_history', params, limit, offset, authorization);
  }

  Future<_Result> _listShipments(
    Map<String, String> query,
    String? authorization,
  ) async {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 100000);
    final params = <String, String>{
      'select': '*',
      'order': 'created_at.desc,id.desc',
    };
    final status = query['status'];
    if (status != null) {
      if (!{
        'planned',
        'in_transit',
        'in_customs',
        'delivered',
        'cancelled',
      }.contains(status)) {
        throw _Failure.validation(
          'status',
          'El estado del envío no es válido.',
        );
      }
      params['status'] = 'eq.$status';
    }
    final exportId = int.tryParse(query['export_id'] ?? '');
    if (exportId != null) params['export_id'] = 'eq.$exportId';
    final shipmentId = int.tryParse(query['id'] ?? '');
    if (shipmentId != null) params['id'] = 'eq.$shipmentId';
    final q = _cleanText(query['q']);
    if (q.isNotEmpty) {
      params['or'] =
          '(order_number.ilike.*$q*,customer_name.ilike.*$q*,tracking_number.ilike.*$q*)';
    }
    return _page('shipment_catalog', params, limit, offset, authorization);
  }

  Future<_Result> _listExportMap(
    String view,
    String key,
    int id,
    String? authorization,
  ) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/$view',
        query: {'select': '*', key: 'eq.$id'},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List) throw _Failure.upstream();
    return _Result(200, {'items': rows});
  }

  static const _generatedTypes = {
    'export_summary',
    'commercial_invoice',
    'packing_list',
    'eur1_certificate',
  };
  static const _uploadedTypes = {
    'phytosanitary_certificate',
    'other_attachment',
  };
  static const _shipmentEditable = {
    'carrier',
    'tracking_number',
    'estimated_delivery_at',
    'transport_mode',
    'container_number',
  };
  static const _maxUploadBytes = 10 * 1024 * 1024;
  static const _uploadMimeByExtension = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
  };

  /// Llama a una función SQL (`rest/v1/rpc/<name>`) con la sesión del usuario.
  Future<Object?> _rpc(
    String name,
    Map<String, Object?> body,
    String? authorization,
  ) async => _checked(
    await _call(
      'POST',
      'rest/v1/rpc/$name',
      body: body,
      token: _bearer(authorization),
    ),
  );

  /// URL firmada de corta duración para un objeto del bucket privado.
  Future<String> _signedUrl(String objectPath, String? authorization) async {
    final signed = _checked(
      await _call(
        'POST',
        'storage/v1/object/sign/export-documents/$objectPath',
        body: {'expiresIn': 3600},
        token: _bearer(authorization),
      ),
    );
    final relative = signed is Map ? signed['signedURL'] : null;
    if (relative is! String) throw _Failure.upstream();
    return _base
        .resolve('storage/v1${relative.startsWith('/') ? '' : '/'}$relative')
        .toString();
  }

  /// PLAT-579/588/593/597: invoca la Edge Function `generate-document` y devuelve
  /// una URL firmada de corta duración para descargar el PDF del bucket privado.
  Future<_Result> _generateDocument(
    int exportId,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final type = body?['document_type'] ?? 'export_summary';
    if (!_generatedTypes.contains(type)) {
      throw _Failure.validation(
        'document_type',
        'El tipo de documento no se puede generar.',
      );
    }
    final response = await _call(
      'POST',
      'functions/v1/generate-document',
      body: {'export_id': exportId, 'document_type': type},
      token: _bearer(authorization),
    );
    final document = _checked(response);
    if (document is! Map || document['object_path'] is! String) {
      throw _Failure.upstream();
    }
    return _Result(201, {
      ...Map<String, dynamic>.from(document),
      'download_url': await _signedUrl(
        document['object_path'] as String,
        authorization,
      ),
    });
  }

  /// PLAT-603: documentos del expediente (más recientes primero).
  Future<_Result> _exportDossier(int? exportId, String? authorization) => _page(
    'export_dossier',
    {
      'select': '*',
      if (exportId != null) 'export_id': 'eq.$exportId',
      'order': 'created_at.desc,id.desc',
    },
    100,
    0,
    authorization,
  );

  Future<_Result> _documentDownload(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/export_dossier',
        query: {'select': 'id,object_path,original_name', 'id': 'eq.$id'},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw _Failure.notFound('El documento no existe o no tienes acceso.');
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return _Result(200, {
      'id': id,
      'original_name': row['original_name'],
      'download_url': await _signedUrl(
        row['object_path'] as String,
        authorization,
      ),
    });
  }

  /// PLAT-600/601/602: carga un adjunto (p. ej. certificado fitosanitario) al
  /// bucket privado y lo registra en el expediente. Valida tipo y tamaño antes de
  /// subir; la base vuelve a validarlos al registrar.
  Future<_Result> _uploadDocument(
    int exportId,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final type = body?['document_type'] ?? 'phytosanitary_certificate';
    if (!_uploadedTypes.contains(type)) {
      throw _Failure.validation(
        'document_type',
        'El tipo de documento no se puede adjuntar.',
      );
    }
    final name = '${body?['file_name'] ?? ''}'.trim();
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    final mime = _uploadMimeByExtension[extension];
    if (mime == null) {
      throw _Failure.validation(
        'file_name',
        'Solo se aceptan archivos PDF, PNG o JPEG.',
      );
    }
    final List<int> bytes;
    try {
      bytes = base64Decode('${body?['content_base64'] ?? ''}');
    } on FormatException {
      throw _Failure.validation('content_base64', 'El archivo no es válido.');
    }
    if (bytes.isEmpty) {
      throw _Failure.validation('content_base64', 'El archivo está vacío.');
    }
    if (bytes.length > _maxUploadBytes) {
      throw _Failure.validation(
        'content_base64',
        'El archivo no puede superar 10 MB.',
      );
    }
    final random = Random.secure();
    final unique = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final objectPath = 'uploads/$exportId/${unique}_$safeName';
    final token = _bearer(authorization);

    final upload = http.Request(
      'POST',
      _base.resolve('storage/v1/object/export-documents/$objectPath'),
    );
    upload.headers.addAll({
      'apikey': anonKey,
      'Authorization': 'Bearer ${token ?? anonKey}',
      'Content-Type': mime,
      'x-upsert': 'false',
    });
    upload.bodyBytes = bytes;
    final uploaded = await http.Response.fromStream(await _inner.send(upload));
    if (uploaded.statusCode >= 400) {
      if (uploaded.statusCode == 413 || uploaded.statusCode == 415) {
        throw _Failure.validation(
          'content_base64',
          'El archivo supera el tamaño o el tipo permitido.',
        );
      }
      _checked(uploaded);
      throw _Failure.upstream();
    }

    try {
      final document = await _rpc('register_export_document', {
        'p': {
          'export_id': exportId,
          'document_type': type,
          'object_path': objectPath,
          'original_name': name,
          'mime_type': mime,
          'byte_size': bytes.length,
          if ('${body?['notes'] ?? ''}'.trim().isNotEmpty)
            'notes': '${body?['notes']}'.trim(),
        },
      }, authorization);
      if (document is! Map) throw _Failure.upstream();
      return _Result(201, Map<String, dynamic>.from(document));
    } on Object {
      // No quedó en el expediente: se retira el archivo para no dejar huérfanos.
      await _call(
        'DELETE',
        'storage/v1/object/export-documents/$objectPath',
        token: token,
      );
      rethrow;
    }
  }

  /// PLAT-625/630: cartera con filtros y, opcionalmente, convertida a otra moneda.
  Future<_Result> _paymentPortfolio(
    Map<String, String> query,
    String? authorization,
  ) async {
    final params = <String, String>{
      'select': '*',
      'order': 'due_date.asc.nullslast,obligation_id.asc',
    };
    final status = query['status'];
    if (status != null) {
      if (!{'pending', 'partial', 'overdue', 'paid'}.contains(status)) {
        throw _Failure.validation('status', 'El estado no es válido.');
      }
      params['status'] = 'eq.$status';
    }
    final q = _cleanText(query['q']);
    if (q.isNotEmpty) {
      params['or'] =
          '(order_number.ilike.*$q*,customer_name.ilike.*$q*,reference.ilike.*$q*)';
    }
    final currency = (query['currency'] ?? '').toUpperCase();
    if (currency.isNotEmpty && !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw _Failure.validation('currency', 'La moneda no es válida.');
    }
    final page = await _page(
      'payment_portfolio',
      params,
      100,
      0,
      authorization,
    );
    if (currency.isEmpty) return page;
    final converted = await _rpc('payment_portfolio_in', {
      'p_currency': currency,
    }, authorization);
    final byId = <String, Map>{
      if (converted is List)
        for (final row in converted.whereType<Map>())
          '${row['obligation_id']}': row,
    };
    final body = Map<String, dynamic>.from(page.body as Map);
    body['items'] = [
      for (final item in (body['items'] as List).whereType<Map>())
        {
          ...Map<String, dynamic>.from(item),
          'converted_currency': currency,
          'amount_due_converted':
              byId['${item['obligation_id']}']?['amount_due_converted'],
          'balance_converted':
              byId['${item['obligation_id']}']?['balance_converted'],
          'rate': byId['${item['obligation_id']}']?['rate'],
        },
    ];
    return _Result(200, body);
  }

  Future<Object?> _lotRow(int id, String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/lot_catalog',
        query: {'id': 'eq.$id', 'select': _lotSelect},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el lote solicitado.');
    }
    return rows.first;
  }

  Future<_Result> _createLot(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null) {
      throw _Failure.validation('body', 'La solicitud no es válida.');
    }
    final id = _checked(
      await _call(
        'POST',
        'rest/v1/rpc/create_lot',
        body: {'p': body},
        token: _bearer(authorization),
      ),
    );
    if (id is! int) throw _Failure.upstream();
    return _Result(201, await _lotRow(id, authorization));
  }

  // ---- Roles y permisos ----------------------------------------------------

  Future<_Result> _listRoles(
    Map<String, String> query,
    String? authorization,
  ) async {
    final params = <String, String>{'select': _roleSelect, 'order': 'id.asc'};
    if (query['include_inactive'] != 'true') params['is_active'] = 'eq.true';
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/role',
        query: params,
        token: _bearer(authorization),
      ),
    );
    if (rows is! List) throw _Failure.upstream();
    return _Result(200, {
      'items': [for (final row in rows) _role(row)],
    });
  }

  Future<_Result> _listPermissions(String? authorization) async {
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/permission',
        query: {'select': 'code,description', 'order': 'code.asc'},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List) throw _Failure.upstream();
    return _Result(200, {'items': rows});
  }

  Future<_Result> _createRole(
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final name = _roleName(_text(body, 'name'));
    final description = _text(body, 'description')?.trim();
    final rows = _checked(
      await _call(
        'POST',
        'rest/v1/role',
        query: {'select': _roleSelect},
        body: {
          'name': name,
          'description': description == null || description.isEmpty
              ? null
              : description,
        },
        token: _bearer(authorization),
        headers: {'Prefer': 'return=representation'},
        duplicateMessage: 'Ya existe un rol con ese nombre.',
      ),
    );
    if (rows is! List || rows.isEmpty) throw _Failure.upstream();
    return _Result(201, _role(rows.first));
  }

  Future<_Result> _updateRole(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    if (body == null || body.isEmpty) {
      throw _Failure.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    final changes = <String, Object?>{};
    if (body.containsKey('name')) {
      changes['name'] = _roleName(_text(body, 'name'));
    }
    if (body.containsKey('description')) {
      final value = _text(body, 'description')?.trim();
      changes['description'] = value == null || value.isEmpty ? null : value;
    }
    if (body.containsKey('is_active')) {
      changes['is_active'] = body['is_active'] == true;
    }
    final rows = _checked(
      await _call(
        'PATCH',
        'rest/v1/role',
        query: {'id': 'eq.$id', 'select': _roleSelect},
        body: changes,
        token: _bearer(authorization),
        headers: {'Prefer': 'return=representation'},
        duplicateMessage: 'Ya existe un rol con ese nombre.',
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el rol solicitado.');
    }
    return _Result(200, _role(rows.first));
  }

  Future<_Result> _setRolePermissions(
    int id,
    Map<String, dynamic>? body,
    String? authorization,
  ) async {
    final codes = body?['permission_codes'];
    if (codes is! List || codes.any((code) => code is! String)) {
      throw _Failure.validation(
        'permission_codes',
        'Indica una lista de permisos.',
      );
    }
    _checked(
      await _call(
        'POST',
        'rest/v1/rpc/set_role_permissions',
        body: {'p_role_id': id, 'p_codes': codes},
        token: _bearer(authorization),
      ),
    );
    final rows = _checked(
      await _call(
        'GET',
        'rest/v1/role',
        query: {'id': 'eq.$id', 'select': _roleSelect},
        token: _bearer(authorization),
      ),
    );
    if (rows is! List || rows.isEmpty) {
      throw _Failure.notFound('No se encontró el rol solicitado.');
    }
    return _Result(200, _role(rows.first));
  }

  // ---- Utilidades ----------------------------------------------------------

  Map<String, Object?> _role(Object? row) {
    final map = Map<String, dynamic>.from(row as Map);
    final links = map['role_permission'];
    final codes = [
      if (links is List)
        for (final link in links)
          if (link is Map && link['permission_code'] is String)
            link['permission_code'] as String,
    ]..sort();
    return {
      'id': map['id'],
      'name': map['name'],
      'description': map['description'],
      'is_active': map['is_active'],
      'permission_codes': codes,
    };
  }

  String _roleName(String? raw) {
    final name = (raw ?? '').trim().toLowerCase().replaceAll(' ', '_');
    if (!RegExp(r'^[a-z][a-z0-9_]{1,59}$').hasMatch(name)) {
      throw _Failure.validation(
        'name',
        'Usa letras, números y guion bajo en el nombre.',
      );
    }
    return name;
  }

  String? _text(Map<String, dynamic>? body, String field) {
    final value = body?[field];
    return value is String ? value : null;
  }

  String? _bearer(String? authorization) => authorization?.replaceFirst(
    RegExp(r'^Bearer\s+', caseSensitive: false),
    '',
  );

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Devuelve el JSON de una respuesta PostgREST o lanza el error de la API.
  Object? _checked(http.Response response, {String? duplicateMessage}) {
    if (response.statusCode < 400) return _decode(response);
    Object? data;
    try {
      data = _decode(response);
    } on FormatException {
      data = null;
    }
    final code = data is Map ? '${data['code']}' : '';
    final message = _message(data);
    if (response.statusCode == 401 || code == 'PGRST303') {
      throw const _Failure(
        401,
        'UNAUTHORIZED',
        'Tu sesión expiró. Inicia sesión de nuevo.',
      );
    }
    if (response.statusCode == 403 || code == '42501') {
      throw const _Failure(
        403,
        'FORBIDDEN',
        'No tienes permiso para esta operación.',
      );
    }
    if (code == '23505') {
      throw _Failure.conflict(
        duplicateMessage ?? 'Ya existe un registro con esos datos.',
      );
    }
    if (code == 'P0001') {
      throw _Failure.conflict(message ?? 'La operación no está permitida.');
    }
    if (code == 'P0002') throw _Failure.notFound(message ?? 'No encontrado.');
    if (code == '22023' || code == '23503' || code == '23514') {
      throw _Failure.validation('body', message ?? 'Datos no válidos.');
    }
    if (response.statusCode >= 500) throw _Failure.upstream();
    throw _Failure(
      response.statusCode,
      'BAD_REQUEST',
      'La solicitud no pudo completarse.',
    );
  }

  String? _message(Object? data) {
    if (data is! Map) return null;
    final value = data['message'] ?? data['msg'] ?? data['error_description'];
    return value is String ? value : null;
  }

  Future<http.Response> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? token,
    Map<String, String>? headers,
    String? duplicateMessage,
  }) async {
    final request = http.Request(
      method,
      _base.resolve(path).replace(queryParameters: query),
    );
    request.headers.addAll({
      'apikey': anonKey,
      'Authorization': 'Bearer ${token ?? anonKey}',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _inner.send(request));
    if (duplicateMessage != null && response.statusCode == 409) {
      throw _Failure.conflict(duplicateMessage);
    }
    return response;
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

class _Failure implements Exception {
  const _Failure(
    this.status,
    this.code,
    this.message, [
    this.details = const [],
  ]);

  factory _Failure.notFound([
    String message = 'El recurso solicitado no existe.',
  ]) => _Failure(404, 'NOT_FOUND', message);
  factory _Failure.conflict(String message) =>
      _Failure(409, 'CONFLICT', message);
  factory _Failure.invalidCredentials() => const _Failure(
    401,
    'UNAUTHORIZED',
    'Correo electrónico o contraseña incorrectos.',
  );
  factory _Failure.upstream() => const _Failure(
    502,
    'INTERNAL_SERVER_ERROR',
    'Supabase no respondió como se esperaba. Inténtalo de nuevo.',
  );
  factory _Failure.validation(String field, String message) => _Failure(
    422,
    'VALIDATION_ERROR',
    'La solicitud contiene datos no válidos.',
    [
      {'field': field, 'code': 'invalid_value', 'message': message},
    ],
  );

  final int status;
  final String code;
  final String message;
  final List<Map<String, String>> details;
}
