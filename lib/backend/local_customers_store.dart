import '../core/validation/eori.dart';
import 'local_backend_store.dart';

class _Customer {
  _Customer({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.currencyCode,
    this.contactName,
    this.email,
    this.eori,
  });

  final int id;
  String name;
  String countryCode;
  String currencyCode;
  String? contactName;
  String? email;
  String? eori;
  bool isActive = true;
  final DateTime createdAt = DateTime.now().toUtc();
  DateTime updatedAt = DateTime.now().toUtc();
}

/// Clientes del backend local: mismas reglas y mensajes que las funciones de
/// `database/migrations/*_customers_module.sql` (incluida la validación del EORI).
class LocalCustomersStore {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _fields = {
    'name',
    'contact_name',
    'email',
    'country_code',
    'eori_number',
    'preferred_currency_code',
  };

  final _customers = <_Customer>[];
  final _links = <(int customerId, int profileId)>[];
  int _nextId = 1;

  Map<String, Object?> list(Map<String, String> query) {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
    final text = (query['q'] ?? '').trim().toLowerCase();
    final country = (query['country_code'] ?? '').trim().toUpperCase();
    final active = switch (query['is_active']) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    final matches =
        _customers
            .where(
              (c) =>
                  (active == null || c.isActive == active) &&
                  (country.isEmpty || c.countryCode == country) &&
                  (text.isEmpty ||
                      c.name.toLowerCase().contains(text) ||
                      (c.eori ?? '').toLowerCase().contains(
                        normalizeEori(text)?.toLowerCase() ?? text,
                      )),
            )
            .toList()
          ..sort((a, b) {
            final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return byName != 0 ? byName : a.id.compareTo(b.id);
          });
    return {
      'items': [for (final c in matches.skip(offset).take(limit)) _json(c)],
      'pagination': {'total': matches.length, 'limit': limit, 'offset': offset},
    };
  }

  Map<String, Object?> get(int id) => _json(_find(id));

  Map<String, Object?> create(Map<String, dynamic>? body) {
    if (body == null) {
      throw LocalBackendError.validation('body', 'La solicitud no es válida.');
    }
    _rejectUnknown(body, 'Campo no permitido para un cliente');
    final name =
        _text(body, 'name', 'El nombre', 180) ??
        (throw LocalBackendError.validation(
          'name',
          'El nombre del cliente es obligatorio.',
        ));
    final contact = _text(body, 'contact_name', 'El nombre de contacto', 160);
    final email = _text(
      body,
      'email',
      'El correo',
      254,
      pattern: _emailPattern,
    )?.toLowerCase();
    final country =
        _country(body) ??
        (throw _required('country_code', 'El país es obligatorio.'));
    final currency =
        _currency(body) ??
        (throw _required(
          'preferred_currency_code',
          'La moneda preferida es obligatoria.',
        ));
    final eori = _eori(body, country);
    _ensureUniqueEori(eori, null);

    final customer = _Customer(
      id: _nextId++,
      name: name,
      contactName: contact,
      email: email,
      countryCode: country,
      eori: eori,
      currencyCode: currency,
    );
    _customers.add(customer);
    return _json(customer);
  }

  Map<String, Object?> update(int id, Map<String, dynamic>? body) {
    final customer = _find(id);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _rejectUnknown(body, 'Campo no permitido');

    // Se valida todo antes de aplicar nada (atomicidad, como la función de la base).
    final name = body.containsKey('name')
        ? (_text(body, 'name', 'El nombre', 180) ??
              (throw _required(
                'name',
                'El nombre del cliente es obligatorio.',
              )))
        : customer.name;
    final contact = body.containsKey('contact_name')
        ? _text(body, 'contact_name', 'El nombre de contacto', 160)
        : customer.contactName;
    final email = body.containsKey('email')
        ? _text(
            body,
            'email',
            'El correo',
            254,
            pattern: _emailPattern,
          )?.toLowerCase()
        : customer.email;
    final country = body.containsKey('country_code')
        ? (_country(body) ??
              (throw _required('country_code', 'El país es obligatorio.')))
        : customer.countryCode;
    final currency = body.containsKey('preferred_currency_code')
        ? (_currency(body) ??
              (throw _required(
                'preferred_currency_code',
                'La moneda preferida es obligatoria.',
              )))
        : customer.currencyCode;
    final eori = body.containsKey('eori_number')
        ? _eori(body, country)
        : _eoriFromStored(customer.eori, country);
    _ensureUniqueEori(eori, customer.id);

    final changed =
        name != customer.name ||
        contact != customer.contactName ||
        email != customer.email ||
        country != customer.countryCode ||
        currency != customer.currencyCode ||
        eori != customer.eori;
    if (changed) {
      customer
        ..name = name
        ..contactName = contact
        ..email = email
        ..countryCode = country
        ..currencyCode = currency
        ..eori = eori
        ..updatedAt = DateTime.now().toUtc();
    }
    return _json(customer);
  }

  Map<String, Object?> setActive(int id, Map<String, dynamic>? body) {
    final customer = _find(id);
    final active = body?['is_active'];
    if (active is! bool) {
      throw LocalBackendError.validation(
        'is_active',
        'Indica si el cliente debe quedar activo.',
      );
    }
    if (customer.isActive != active) {
      customer
        ..isActive = active
        ..updatedAt = DateTime.now().toUtc();
    }
    return _json(customer);
  }

  // ---- Cuentas vinculadas ---------------------------------------------------------

  /// Cuentas vinculadas a un cliente (con correo, nombre y si tienen acceso al portal).
  Map<String, Object?> accounts(
    int customerId,
    LocalAccount? Function(int profileId) accountById,
  ) {
    _find(customerId);
    return {
      'items': [
        for (final link in _links.where((l) => l.$1 == customerId))
          if (accountById(link.$2) case final account?)
            {
              'customer_id': customerId,
              'profile_id': account.id,
              'email': account.email,
              'first_name': account.firstName,
              'last_name': account.lastName,
              'account_is_active': account.isActive,
              'has_portal_access': account.hasPortalAccess,
            },
      ],
    };
  }

  /// Vincula la cuenta con ese correo al cliente; mismas reglas que `link_customer_user`.
  Map<String, Object?> link(
    int customerId,
    Map<String, dynamic>? body,
    LocalAccount? Function(String email) accountByEmail,
    LocalAccount? Function(int profileId) accountById,
  ) {
    final customer = _find(customerId);
    final raw = body?['email'];
    final email = raw is String ? raw.trim().toLowerCase() : '';
    if (email.isEmpty) {
      throw LocalBackendError.validation(
        'email',
        'El correo de la cuenta es obligatorio.',
      );
    }
    if (!_emailPattern.hasMatch(email)) {
      throw LocalBackendError.validation(
        'email',
        'El correo de la cuenta no tiene un formato válido.',
      );
    }
    if (!customer.isActive) {
      throw LocalBackendError.validation(
        'customer',
        'El cliente está inactivo.',
      );
    }
    final account = accountByEmail(email);
    if (account == null) {
      throw LocalBackendError.validation(
        'email',
        'No existe una cuenta con ese correo.',
      );
    }
    if (!account.isActive) {
      throw LocalBackendError.validation(
        'email',
        'La cuenta está desactivada.',
      );
    }
    if (_links.contains((customerId, account.id))) {
      throw LocalBackendError.conflict(
        'Esa cuenta ya está vinculada a este cliente.',
      );
    }
    _links.add((customerId, account.id));
    return accounts(customerId, accountById);
  }

  Map<String, Object?> unlink(
    int customerId,
    int profileId,
    LocalAccount? Function(int profileId) accountById,
  ) {
    if (!_links.remove((customerId, profileId))) {
      throw LocalBackendError.notFound('No se encontró el vínculo solicitado.');
    }
    return accounts(customerId, accountById);
  }

  // ---- Utilidades ---------------------------------------------------------------

  _Customer _find(int id) =>
      _customers.where((c) => c.id == id).firstOrNull ??
      (throw LocalBackendError.notFound(
        'No se encontró el cliente solicitado.',
      ));

  LocalBackendError _required(String field, String message) =>
      LocalBackendError.validation(field, message);

  void _rejectUnknown(Map<String, dynamic> body, String message) {
    for (final key in body.keys) {
      if (!_fields.contains(key)) {
        throw LocalBackendError.validation(key, '$message: $key.');
      }
    }
  }

  void _ensureUniqueEori(String? eori, int? exceptId) {
    if (eori == null) return;
    if (_customers.any((c) => c.id != exceptId && c.eori == eori)) {
      throw LocalBackendError.conflict('Ya existe un cliente con ese EORI.');
    }
  }

  String? _country(Map<String, dynamic> body) {
    final value = _text(body, 'country_code', 'El país', 2)?.toUpperCase();
    if (value != null && !RegExp(r'^[A-Z]{2}$').hasMatch(value)) {
      throw LocalBackendError.validation(
        'country_code',
        'El país debe ser un código de 2 letras (por ejemplo CO).',
      );
    }
    return value;
  }

  String? _currency(Map<String, dynamic> body) {
    final value = _text(
      body,
      'preferred_currency_code',
      'La moneda',
      3,
    )?.toUpperCase();
    if (value != null && !RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      throw LocalBackendError.validation(
        'preferred_currency_code',
        'La moneda debe ser un código de 3 letras (por ejemplo USD).',
      );
    }
    return value;
  }

  /// EORI de la solicitud, normalizado y validado contra el país.
  String? _eori(Map<String, dynamic> body, String country) {
    final raw = _text(body, 'eori_number', 'El EORI', 40);
    return _eoriFromStored(normalizeEori(raw), country);
  }

  String? _eoriFromStored(String? eori, String country) {
    final error = validateEori(eori, country);
    if (error != null) {
      throw LocalBackendError.validation('eori_number', error);
    }
    return eori;
  }

  String? _text(
    Map<String, dynamic> body,
    String key,
    String label,
    int max, {
    RegExp? pattern,
  }) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String) {
      throw LocalBackendError.validation(key, '$label debe ser texto.');
    }
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.length > max) {
      throw LocalBackendError.validation(
        key,
        '$label admite máximo $max caracteres.',
      );
    }
    if (pattern != null && !pattern.hasMatch(text)) {
      throw LocalBackendError.validation(
        key,
        '$label no tiene un formato válido.',
      );
    }
    return text;
  }

  Map<String, Object?> _json(_Customer c) => {
    'id': c.id,
    'name': c.name,
    'contact_name': c.contactName,
    'email': c.email,
    'country_code': c.countryCode,
    'eori_number': c.eori,
    'preferred_currency_code': c.currencyCode,
    'is_active': c.isActive,
    'created_at': c.createdAt.toIso8601String(),
    'updated_at': c.updatedAt.toIso8601String(),
  };
}
