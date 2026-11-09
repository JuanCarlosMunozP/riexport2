import 'dart:convert';
import 'dart:math';

import 'local_customers_store.dart';
import 'local_origin_store.dart';
import 'local_demo_store.dart';
import 'local_inventory_store.dart';
import 'local_orders_store.dart';
import 'local_exports_store.dart';
import 'local_products_store.dart';
import 'local_suppliers_store.dart';

/// Cuenta de usuario tal como la ve el vínculo con un cliente.
class LocalAccount {
  const LocalAccount({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isActive,
    required this.hasPortalAccess,
  });

  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final bool isActive;
  final bool hasPortalAccess;
}

class LocalBackendError implements Exception {
  const LocalBackendError(
    this.status,
    this.code,
    this.message, [
    this.details = const [],
  ]);

  factory LocalBackendError.notFound([
    String message = 'El recurso solicitado no existe.',
  ]) => LocalBackendError(404, 'NOT_FOUND', message);

  factory LocalBackendError.conflict(String message, [List<Map>? details]) =>
      LocalBackendError(409, 'CONFLICT', message, details ?? const []);

  factory LocalBackendError.validation(String field, String message) =>
      LocalBackendError(
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
  final List<Map> details;
}

class _User {
  _User({
    required this.id,
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.roleId,
    this.phone,
  });

  final int id;
  String email;
  String password;
  String firstName;
  String lastName;
  String? phone;
  int roleId;
  bool isActive = true;

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'first_name': firstName,
    'last_name': lastName,
    'phone': phone,
    'role_id': roleId,
    'is_active': isActive,
  };
}

class _Role {
  _Role(this.id, this.name, this.description, [Set<String>? permissions])
    : permissions = permissions ?? {};

  final int id;
  String name;
  String? description;
  bool isActive = true;
  Set<String> permissions;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'is_active': isActive,
    'permission_codes': permissions.toList()..sort(),
  };
}

/// Datos y reglas de negocio del backend local (equivalente a los servicios
/// de FastAPI para auth, usuarios y roles). Vive en memoria mientras la app
/// está abierta.
class LocalBackendStore {
  LocalBackendStore({
    this.adminEmail = 'admin@riexport.com',
    this.adminPassword = 'Admin123!',
    this.tokenLifetime = const Duration(minutes: 30),
  }) {
    for (final permission in _permissions) {
      _permissionCodes.add(permission.$1);
    }
    for (final role in _seedRoles) {
      _roles.add(_Role(_nextRoleId++, role.$1, role.$2));
    }
    _roles.first.permissions = {..._permissionCodes};
    for (final role in _roles.skip(1)) {
      role.permissions = switch (role.name) {
        'usuario_comercial' => {
          'customers.read',
          'customers.create',
          'customers.update',
          'orders.read',
          'orders.create',
          'orders.update',
          'orders.transition',
          'exports.read',
          'exports.create',
          'exports.update',
          'documents.read',
          'documents.upload',
          'documents.generate',
          'inventory.read',
          'payments.read',
          'payments.create',
          'logistics.read',
        },
        'encargado_logistico' => {
          'customers.read',
          'orders.read',
          'exports.read',
          'documents.read',
          'inventory.read',
          'inventory.adjust',
          'logistics.read',
          'logistics.create',
          'logistics.update',
        },
        'cliente' => {'portal.read'},
        _ => <String>{},
      };
    }
    _users.add(
      _User(
        id: _nextUserId++,
        email: adminEmail,
        password: adminPassword,
        firstName: 'Administrador',
        lastName: 'RiExport',
        roleId: _roles.first.id,
      ),
    );
  }

  final String adminEmail;
  final String adminPassword;
  final Duration tokenLifetime;

  static const _permissions = [
    ('roles.read', 'Consultar roles y permisos.'),
    ('roles.create', 'Crear roles.'),
    ('roles.update', 'Editar roles.'),
    ('roles.permissions.update', 'Asignar permisos a roles.'),
    ('roles.deactivate', 'Desactivar roles.'),
    ('users.read', 'Consultar usuarios.'),
    ('users.create', 'Registrar usuarios.'),
    ('users.update', 'Editar usuarios.'),
    ('users.deactivate', 'Desactivar usuarios.'),
    ('users.assign_role', 'Asignar o cambiar el rol de un usuario.'),
    ('audit.read', 'Consultar el registro de auditoría.'),
    ('products.read', 'Consultar el catálogo de productos.'),
    ('products.create', 'Registrar productos.'),
    (
      'products.update',
      'Editar, inactivar y asociar certificaciones a productos.',
    ),
    ('suppliers.read', 'Consultar proveedores.'),
    ('suppliers.create', 'Registrar proveedores.'),
    ('suppliers.update', 'Editar e inactivar proveedores.'),
    ('customers.read', 'Consultar clientes.'),
    ('customers.create', 'Registrar clientes.'),
    ('customers.update', 'Editar e inactivar clientes.'),
    ('orders.read', 'Consultar pedidos.'),
    ('orders.create', 'Registrar pedidos.'),
    ('orders.update', 'Editar pedidos en borrador.'),
    ('orders.transition', 'Cambiar el estado de los pedidos.'),
    ('inventory.read', 'Consultar inventario y sus movimientos.'),
    ('inventory.adjust', 'Registrar ajustes manuales de inventario.'),
    ('exports.read', 'Consultar exportaciones.'),
    ('exports.create', 'Registrar exportaciones.'),
    ('exports.update', 'Editar y formalizar exportaciones.'),
    ('documents.read', 'Consultar documentos de exportación.'),
    ('documents.generate', 'Generar documentos de exportación.'),
    ('documents.upload', 'Adjuntar documentos de exportación.'),
    ('logistics.read', 'Consultar envíos y su línea de tiempo.'),
    ('logistics.create', 'Registrar envíos.'),
    ('logistics.update', 'Actualizar envíos y registrar eventos logísticos.'),
    ('payments.read', 'Consultar obligaciones, pagos y tasas de cambio.'),
    ('payments.create', 'Registrar obligaciones y pagos.'),
    (
      'portal.read',
      'Consultar los pedidos, exportaciones, documentos y envíos propios (cliente externo).',
    ),
    ('farms.read', 'Consultar fincas y su geolocalización.'),
    ('farms.create', 'Registrar fincas.'),
    ('farms.update', 'Editar e inactivar fincas.'),
    ('lots.read', 'Consultar lotes de producto.'),
    ('lots.create', 'Registrar lotes de producto.'),
  ];
  static const _seedRoles = [
    (
      'administrador',
      'Gestiona usuarios, roles y permisos; accede al tablero de KPI.',
    ),
    (
      'usuario_comercial',
      'Perfil comercial para productos, clientes, pedidos y exportaciones.',
    ),
    (
      'encargado_logistico',
      'Perfil logístico para transportista, guía y eventos de envío.',
    ),
    ('cliente', 'Cliente externo con acceso limitado a sus propios envíos.'),
  ];
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _permissionCodes = <String>{};

  /// Catálogo de productos (café, cacao y certificaciones).
  final products = LocalProductsStore();
  final suppliers = LocalSuppliersStore();
  final customers = LocalCustomersStore();
  late final origin = LocalOriginStore(suppliers, products);
  late final inventory = LocalInventoryStore(origin, products);
  final demo = LocalDemoStore();
  late final orders = LocalOrdersStore(customers, origin, inventory);
  late final exports = LocalExportsStore(orders, origin, products);
  final _roles = <_Role>[];
  final _users = <_User>[];
  int _nextRoleId = 1;
  int _nextUserId = 1;

  // ---- Autenticación -------------------------------------------------------

  Map<String, Object?> login(Map<String, dynamic>? body) {
    final email = _string(body, 'email')?.trim().toLowerCase() ?? '';
    final password = _string(body, 'password') ?? '';
    final user = _users.where((u) => u.email == email).firstOrNull;
    if (user == null ||
        user.password != password ||
        !user.isActive ||
        !_role(user.roleId).isActive) {
      throw const LocalBackendError(
        401,
        'UNAUTHORIZED',
        'Correo electrónico o contraseña incorrectos.',
      );
    }
    final expiry = DateTime.now().add(tokenLifetime);
    String segment(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token = [
      segment({'alg': 'none', 'typ': 'JWT'}),
      segment({
        'sub': '${user.id}',
        'iss': 'riexport-local',
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      }),
      'local',
    ].join('.');
    return {
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': tokenLifetime.inSeconds,
    };
  }

  /// Valida el token Bearer y devuelve el id del usuario autenticado.
  int requireSession(String? authorization) {
    const unauthorized = LocalBackendError(
      401,
      'UNAUTHORIZED',
      'Se requiere autenticación válida.',
    );
    final token = authorization?.replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    final segments = token?.split('.');
    if (segments == null || segments.length != 3) throw unauthorized;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      final id = int.tryParse('${(payload as Map)['sub']}');
      final exp = payload['exp'];
      if (id == null ||
          exp is! num ||
          !DateTime.fromMillisecondsSinceEpoch(
            (exp * 1000).round(),
          ).isAfter(DateTime.now()) ||
          !_users.any((u) => u.id == id && u.isActive)) {
        throw unauthorized;
      }
      return id;
    } on FormatException {
      throw unauthorized;
    } on TypeError {
      throw unauthorized;
    }
  }

  // ---- Recuperación de acceso ----------------------------------------------

  final _resetCodes = <String, ({String code, DateTime expires})>{};

  /// El backend local no envía correos: devuelve el código en `dev_code` (solo
  /// existe en este backend de desarrollo y pruebas, nunca en Supabase).
  Map<String, Object?> requestPasswordReset(Map<String, dynamic>? body) {
    final email = _email(body, required: true)!;
    final user = _users.where((u) => u.email == email).firstOrNull;
    String? code;
    if (user != null && user.isActive) {
      code = '${100000 + Random.secure().nextInt(900000)}';
      _resetCodes[email] = (
        code: code,
        expires: DateTime.now().add(const Duration(minutes: 30)),
      );
    }
    return {
      'message':
          'Si existe una cuenta con ese correo, te enviamos un código para restablecer tu contraseña.',
      'dev_code': ?code,
    };
  }

  void resetPassword(Map<String, dynamic>? body) {
    final email = _email(body, required: true)!;
    final code = _string(body, 'code')?.trim() ?? '';
    final password = _string(body, 'new_password') ?? '';
    if (password.isEmpty) {
      throw LocalBackendError.validation(
        'new_password',
        'Ingresa una contraseña.',
      );
    }
    if (utf8.encode(password).length > 72) {
      throw LocalBackendError.validation(
        'new_password',
        'La contraseña supera el límite de 72 bytes UTF-8.',
      );
    }
    final entry = _resetCodes[email];
    final user = _users.where((u) => u.email == email).firstOrNull;
    if (entry == null ||
        user == null ||
        entry.code != code ||
        entry.expires.isBefore(DateTime.now())) {
      throw const LocalBackendError(
        400,
        'INVALID_CODE',
        'El código no es válido o ya venció. Solicita uno nuevo.',
      );
    }
    if (user.password == password) {
      throw LocalBackendError.validation(
        'new_password',
        'La nueva contraseña debe ser distinta de la anterior.',
      );
    }
    user.password = password;
    _resetCodes.remove(email); // un solo uso
  }

  /// Exige que la cuenta activa [userId] tenga el permiso [code] (403 si no).
  /// Datos de una cuenta para vincularla a un cliente, o null si no existe.
  LocalAccount? accountByEmail(String email) {
    final user = _users
        .where((u) => u.email == email.trim().toLowerCase())
        .firstOrNull;
    return user == null ? null : _account(user);
  }

  LocalAccount? accountById(int id) {
    final user = _users.where((u) => u.id == id).firstOrNull;
    return user == null ? null : _account(user);
  }

  LocalAccount _account(_User user) => LocalAccount(
    id: user.id,
    email: user.email,
    firstName: user.firstName,
    lastName: user.lastName,
    isActive: user.isActive,
    hasPortalAccess: _role(user.roleId).permissions.contains('portal.read'),
  );

  void requirePermission(int userId, String code) {
    final role = _role(_user(userId).roleId);
    if (!role.isActive || !role.permissions.contains(code)) {
      throw const LocalBackendError(
        403,
        'FORBIDDEN',
        'No tienes permiso para esta operación.',
      );
    }
  }

  bool hasPermission(int userId, String code) =>
      _role(_user(userId).roleId).permissions.contains(code);

  // ---- Perfil propio -------------------------------------------------------

  Map<String, Object?> me(int userId) {
    final user = _user(userId);
    final role = _role(user.roleId);
    return {
      ...user.toJson(),
      'permission_codes': role.isActive
          ? (role.permissions.toList()..sort())
          : [],
    };
  }

  /// Autoedición de nombres y teléfono.
  Map<String, Object?> changeOwnProfile(
    int userId,
    Map<String, dynamic>? body,
  ) {
    final user = _user(userId);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    for (final key in body.keys) {
      if (!{'first_name', 'last_name', 'phone'}.contains(key)) {
        throw LocalBackendError.validation(key, 'Campo no permitido.');
      }
    }
    final firstName = _name(body, 'first_name');
    final lastName = _name(body, 'last_name');
    final phone = body.containsKey('phone') ? _phone(body) : user.phone;
    if (firstName != null) user.firstName = firstName;
    if (lastName != null) user.lastName = lastName;
    user.phone = phone;
    return user.toJson();
  }

  /// En el backend local el cambio de correo se aplica de inmediato (no hay
  /// correo de confirmación que enviar).
  Map<String, Object?> changeOwnEmail(int userId, Map<String, dynamic>? body) {
    final user = _user(userId);
    final email = _email(body, required: true)!;
    if (email == user.email) {
      throw LocalBackendError.validation(
        'email',
        'Ese ya es tu correo electrónico actual.',
      );
    }
    _ensureEmailFree(email, userId);
    user.email = email;
    return {'pending_email': email, 'message': 'Correo actualizado a $email.'};
  }

  // ---- Usuarios ------------------------------------------------------------

  Map<String, Object?> listUsers(Map<String, String> query) {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
    final text = query['q']?.trim().toLowerCase() ?? '';
    final active = switch (query['is_active']) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    final matches = _users.where((user) {
      if (active != null && user.isActive != active) return false;
      if (text.isEmpty) return true;
      return '${user.firstName} ${user.lastName} ${user.email}'
          .toLowerCase()
          .contains(text);
    }).toList();
    return {
      'items': [
        for (final user in matches.skip(offset).take(limit))
          {...user.toJson(), 'role_name': _role(user.roleId).name},
      ],
      'pagination': {'total': matches.length, 'limit': limit, 'offset': offset},
    };
  }

  /// Registro público: no recibe rol; la cuenta se crea con el rol `cliente`.
  Map<String, Object?> register(Map<String, dynamic>? body) {
    final role = _roles.firstWhere((r) => r.name == 'cliente');
    return createUser({...?body, 'role_id': role.id});
  }

  Map<String, Object?> createUser(Map<String, dynamic>? body) {
    final email = _email(body, required: true)!;
    final password = _string(body, 'password') ?? '';
    if (password.isEmpty) {
      throw LocalBackendError.validation('password', 'Ingresa una contraseña.');
    }
    if (utf8.encode(password).length > 72) {
      throw LocalBackendError.validation(
        'password',
        'La contraseña supera el límite de 72 bytes UTF-8.',
      );
    }
    final firstName = _name(body, 'first_name', required: true)!;
    final lastName = _name(body, 'last_name', required: true)!;
    final roleId = _activeRoleId(body, 'role_id', required: true)!;
    _ensureEmailFree(email, null);
    final user = _User(
      id: _nextUserId++,
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      phone: _phone(body),
      roleId: roleId,
    );
    _users.add(user);
    return user.toJson();
  }

  Map<String, Object?> updateUser(
    int id,
    Map<String, dynamic>? body, {
    int? actorId,
  }) {
    final user = _user(id);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    if (body.containsKey('email')) {
      throw LocalBackendError.validation(
        'email',
        'El correo electrónico no se puede cambiar desde la app.',
      );
    }
    final firstName = _name(body, 'first_name');
    final lastName = _name(body, 'last_name');
    final roleId = _activeRoleId(body, 'role_id');
    final changesRole = roleId != null && roleId != user.roleId;
    if (changesRole && actorId != null) {
      // Misma política que la base: nunca el propio rol, con permiso propio, y el
      // rol administrador solo lo gestiona un administrador.
      if (actorId == id) {
        throw LocalBackendError.conflict('No puedes cambiar tu propio rol.');
      }
      final actorRole = _role(_user(actorId).roleId);
      if (!actorRole.permissions.contains('users.assign_role')) {
        throw const LocalBackendError(
          403,
          'FORBIDDEN',
          'No tienes permiso para esta operación.',
        );
      }
      if ((_isAdminRole(roleId) || _isAdminRole(user.roleId)) &&
          actorRole.name != 'administrador') {
        throw LocalBackendError.conflict(
          'Solo un administrador puede asignar o quitar el rol administrador.',
        );
      }
    }
    if (changesRole && user.isActive && _isAdminRole(user.roleId)) {
      _ensureAnotherAdmin(user.roleId);
    }
    if (firstName != null) user.firstName = firstName;
    if (lastName != null) user.lastName = lastName;
    if (roleId != null) user.roleId = roleId;
    if (body.containsKey('phone')) user.phone = _phone(body);
    return user.toJson();
  }

  Map<String, Object?> deactivateUser(int id, int actorId) {
    if (id == actorId) {
      throw LocalBackendError.conflict(
        'No puedes desactivar tu propio usuario.',
      );
    }
    final user = _user(id);
    if (!user.isActive) return user.toJson();
    if (_isAdminRole(user.roleId)) _ensureAnotherAdmin(user.roleId);
    user.isActive = false;
    return user.toJson();
  }

  Map<String, Object?> activateUser(int id) {
    final user = _user(id);
    if (!_role(user.roleId).isActive) {
      throw LocalBackendError.validation(
        'role_id',
        'El rol del usuario está inactivo: asígnale otro antes de reactivarlo.',
      );
    }
    user.isActive = true;
    return user.toJson();
  }

  // ---- Roles y permisos ----------------------------------------------------

  Map<String, Object?> listRoles(Map<String, String> query) {
    final includeInactive = query['include_inactive'] == 'true';
    return {
      'items': [
        for (final role in _roles)
          if (includeInactive || role.isActive) role.toJson(),
      ],
    };
  }

  Map<String, Object?> listPermissions() => {
    'items': [
      for (final permission in _permissions)
        {'code': permission.$1, 'description': permission.$2},
    ],
  };

  Map<String, Object?> createRole(Map<String, dynamic>? body) {
    final name = _roleName(body, required: true)!;
    if (_roles.any((r) => r.name == name)) throw _duplicateRole();
    final role = _Role(_nextRoleId++, name, _description(body));
    _roles.add(role);
    return role.toJson();
  }

  Map<String, Object?> updateRole(int id, Map<String, dynamic>? body) {
    final role = _role(id);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    final name = _roleName(body);
    if (role.name == 'administrador' && name != null && name != role.name) {
      throw LocalBackendError.conflict(
        'No se puede cambiar el nombre del rol administrador del sistema.',
      );
    }
    if (name != null && _roles.any((r) => r.name == name && r.id != id)) {
      throw _duplicateRole();
    }
    if (name != null) role.name = name;
    if (body.containsKey('description')) role.description = _description(body);
    return role.toJson();
  }

  Map<String, Object?> setRolePermissions(int id, Map<String, dynamic>? body) {
    final role = _role(id);
    final raw = body?['permission_codes'];
    if (raw is! List || raw.any((code) => code is! String)) {
      throw LocalBackendError.validation(
        'permission_codes',
        'Indica una lista de permisos.',
      );
    }
    final codes = raw.cast<String>();
    if (codes.length != codes.toSet().length) {
      throw LocalBackendError.validation(
        'permission_codes',
        'No se permiten permisos duplicados.',
      );
    }
    if (!codes.every(_permissionCodes.contains)) {
      throw LocalBackendError.validation(
        'permission_codes',
        'Uno o más permisos no existen.',
      );
    }
    if (role.name == 'administrador' &&
        !codes.toSet().containsAll(_permissionCodes)) {
      throw LocalBackendError.conflict(
        'El rol administrador debe conservar todos los permisos del sistema.',
      );
    }
    role.permissions = codes.toSet();
    return role.toJson();
  }

  Map<String, Object?> deactivateRole(int id) {
    final role = _role(id);
    if (role.name == 'administrador') {
      throw LocalBackendError.conflict(
        'No se puede desactivar el rol administrador del sistema.',
      );
    }
    if (_users.any((u) => u.roleId == id && u.isActive)) {
      throw LocalBackendError.conflict(
        'El rol tiene usuarios activos asignados.',
      );
    }
    role.isActive = false;
    return role.toJson();
  }

  // ---- Utilidades ----------------------------------------------------------

  _User _user(int id) =>
      _users.where((u) => u.id == id).firstOrNull ??
      (throw LocalBackendError.notFound(
        'No se encontró el usuario solicitado.',
      ));

  _Role _role(int id) =>
      _roles.where((r) => r.id == id).firstOrNull ??
      (throw LocalBackendError.notFound('No se encontró el rol solicitado.'));

  bool _isAdminRole(int roleId) => _role(roleId).name == 'administrador';

  void _ensureAnotherAdmin(int adminRoleId) {
    final count = _users
        .where((u) => u.isActive && u.roleId == adminRoleId)
        .length;
    if (count <= 1) {
      throw LocalBackendError.conflict(
        'No se puede dejar el sistema sin un administrador activo.',
      );
    }
  }

  void _ensureEmailFree(String email, int? exceptId) {
    if (_users.any((u) => u.email == email && u.id != exceptId)) {
      throw LocalBackendError.conflict(
        'Ya existe un usuario con ese correo electrónico.',
        [
          {
            'field': 'email',
            'code': 'already_exists',
            'message': 'El correo electrónico ya está registrado.',
          },
        ],
      );
    }
  }

  LocalBackendError _duplicateRole() =>
      LocalBackendError.conflict('Ya existe un rol con ese nombre.', [
        {
          'field': 'name',
          'code': 'already_exists',
          'message': 'El nombre del rol ya está registrado.',
        },
      ]);

  String? _string(Map<String, dynamic>? body, String field) {
    final value = body?[field];
    return value is String ? value : null;
  }

  String? _email(Map<String, dynamic>? body, {bool required = false}) {
    final value = _string(body, 'email')?.trim().toLowerCase();
    if (value == null) {
      if (required || (body?.containsKey('email') ?? false)) {
        throw LocalBackendError.validation(
          'email',
          'Ingresa el correo electrónico.',
        );
      }
      return null;
    }
    if (!_emailPattern.hasMatch(value)) {
      throw LocalBackendError.validation('email', 'Ingresa un correo válido.');
    }
    return value;
  }

  String? _name(
    Map<String, dynamic>? body,
    String field, {
    bool required = false,
  }) {
    final value = _string(body, field)?.trim();
    if (value == null || value.isEmpty) {
      if (required || (body?.containsKey(field) ?? false)) {
        throw LocalBackendError.validation(field, 'Este campo es obligatorio.');
      }
      return null;
    }
    if (value.length > 100) {
      throw LocalBackendError.validation(field, 'Máximo 100 caracteres.');
    }
    return value;
  }

  String? _phone(Map<String, dynamic>? body) {
    final value = _string(body, 'phone')?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.length > 32) {
      throw LocalBackendError.validation('phone', 'Máximo 32 caracteres.');
    }
    return value;
  }

  String? _description(Map<String, dynamic>? body) {
    final value = _string(body, 'description')?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.length > 250) {
      throw LocalBackendError.validation(
        'description',
        'Máximo 250 caracteres.',
      );
    }
    return value;
  }

  String? _roleName(Map<String, dynamic>? body, {bool required = false}) {
    final raw = _string(body, 'name');
    if (raw == null) {
      if (required || (body?.containsKey('name') ?? false)) {
        throw LocalBackendError.validation('name', 'El nombre es obligatorio.');
      }
      return null;
    }
    final name = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (name.length < 2 ||
        name.length > 60 ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw LocalBackendError.validation(
        'name',
        'Usa letras, números y guion bajo en el nombre.',
      );
    }
    return name;
  }

  int? _activeRoleId(
    Map<String, dynamic>? body,
    String field, {
    bool required = false,
  }) {
    final value = body?[field];
    if (value == null) {
      if (required || (body?.containsKey(field) ?? false)) {
        throw LocalBackendError.validation(field, 'Indica el rol.');
      }
      return null;
    }
    final role = value is int
        ? _roles.where((r) => r.id == value).firstOrNull
        : null;
    if (role == null || !role.isActive) {
      throw LocalBackendError.validation(
        field,
        'El rol indicado no existe o está inactivo.',
      );
    }
    return role.id;
  }
}
