import 'local_backend_store.dart';

class _Supplier {
  _Supplier({
    required this.id,
    required this.businessName,
    required this.taxId,
    this.contactName,
    this.phone,
    this.email,
    this.location,
  });

  final int id;
  String businessName;
  String taxId;
  String? contactName;
  String? phone;
  String? email;
  String? location;
  bool isActive = true;
  final DateTime createdAt = DateTime.now().toUtc();
  DateTime updatedAt = DateTime.now().toUtc();
}

/// Proveedores del backend local: mismas reglas y mensajes que las funciones de
/// `database/migrations/*_suppliers_module.sql`.
class LocalSuppliersStore {
  static final _taxIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]{2,29}$');
  static final _phonePattern = RegExp(r'^\+?[0-9][0-9 ()\-]{5,24}$');
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _fields = {
    'business_name',
    'tax_id',
    'contact_name',
    'phone',
    'email',
    'location',
  };

  final _suppliers = <_Supplier>[];
  int _nextId = 1;

  Map<String, Object?> list(Map<String, String> query) {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
    final text = (query['q'] ?? '').trim().toLowerCase();
    final active = switch (query['is_active']) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    final matches =
        _suppliers
            .where(
              (s) =>
                  (active == null || s.isActive == active) &&
                  (text.isEmpty ||
                      s.businessName.toLowerCase().contains(text) ||
                      s.taxId.toLowerCase().contains(text)),
            )
            .toList()
          ..sort((a, b) {
            final byName = a.businessName.toLowerCase().compareTo(
              b.businessName.toLowerCase(),
            );
            return byName != 0 ? byName : a.id.compareTo(b.id);
          });
    return {
      'items': [for (final s in matches.skip(offset).take(limit)) _json(s)],
      'pagination': {'total': matches.length, 'limit': limit, 'offset': offset},
    };
  }

  Map<String, Object?> get(int id) => _json(_find(id));

  /// Nombre y estado de un proveedor, o null si no existe (para fincas).
  ({String name, bool isActive})? lookup(int id) {
    final supplier = _suppliers.where((s) => s.id == id).firstOrNull;
    return supplier == null
        ? null
        : (name: supplier.businessName, isActive: supplier.isActive);
  }

  Map<String, Object?> create(Map<String, dynamic>? body) {
    if (body == null) {
      throw LocalBackendError.validation('body', 'La solicitud no es válida.');
    }
    _rejectUnknown(body, 'Campo no permitido para un proveedor');
    final name = _text(body, 'business_name', 'La razón social', 160);
    final tax = _text(
      body,
      'tax_id',
      'El documento tributario',
      30,
      pattern: _taxIdPattern,
    );
    if (name == null) {
      throw LocalBackendError.validation(
        'business_name',
        'La razón social es obligatoria.',
      );
    }
    if (tax == null) {
      throw LocalBackendError.validation(
        'tax_id',
        'El documento tributario es obligatorio.',
      );
    }
    final contact = _text(body, 'contact_name', 'El nombre de contacto', 120);
    final phone = _text(
      body,
      'phone',
      'El teléfono',
      25,
      pattern: _phonePattern,
    );
    final email = _text(
      body,
      'email',
      'El correo',
      254,
      pattern: _emailPattern,
    )?.toLowerCase();
    final location = _text(body, 'location', 'La ubicación', 200);
    _ensureUnique(tax, null);

    final supplier = _Supplier(
      id: _nextId++,
      businessName: name,
      taxId: tax,
      contactName: contact,
      phone: phone,
      email: email,
      location: location,
    );
    _suppliers.add(supplier);
    return _json(supplier);
  }

  Map<String, Object?> update(int id, Map<String, dynamic>? body) {
    final supplier = _find(id);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _rejectUnknown(body, 'Campo no permitido');

    // Se valida todo antes de aplicar nada (atomicidad, como la función de la base).
    var name = supplier.businessName;
    var tax = supplier.taxId;
    if (body.containsKey('business_name')) {
      name =
          _text(body, 'business_name', 'La razón social', 160) ??
          (throw LocalBackendError.validation(
            'business_name',
            'La razón social es obligatoria.',
          ));
    }
    if (body.containsKey('tax_id')) {
      tax =
          _text(
            body,
            'tax_id',
            'El documento tributario',
            30,
            pattern: _taxIdPattern,
          ) ??
          (throw LocalBackendError.validation(
            'tax_id',
            'El documento tributario es obligatorio.',
          ));
    }
    final contact = body.containsKey('contact_name')
        ? _text(body, 'contact_name', 'El nombre de contacto', 120)
        : supplier.contactName;
    final phone = body.containsKey('phone')
        ? _text(body, 'phone', 'El teléfono', 25, pattern: _phonePattern)
        : supplier.phone;
    final email = body.containsKey('email')
        ? _text(
            body,
            'email',
            'El correo',
            254,
            pattern: _emailPattern,
          )?.toLowerCase()
        : supplier.email;
    final location = body.containsKey('location')
        ? _text(body, 'location', 'La ubicación', 200)
        : supplier.location;
    _ensureUnique(tax, supplier.id);

    final changed =
        name != supplier.businessName ||
        tax != supplier.taxId ||
        contact != supplier.contactName ||
        phone != supplier.phone ||
        email != supplier.email ||
        location != supplier.location;
    if (changed) {
      supplier
        ..businessName = name
        ..taxId = tax
        ..contactName = contact
        ..phone = phone
        ..email = email
        ..location = location
        ..updatedAt = DateTime.now().toUtc();
    }
    return _json(supplier);
  }

  Map<String, Object?> setActive(int id, Map<String, dynamic>? body) {
    final supplier = _find(id);
    final active = body?['is_active'];
    if (active is! bool) {
      throw LocalBackendError.validation(
        'is_active',
        'Indica si el proveedor debe quedar activo.',
      );
    }
    if (supplier.isActive != active) {
      supplier
        ..isActive = active
        ..updatedAt = DateTime.now().toUtc();
    }
    return _json(supplier);
  }

  // ---- Utilidades ---------------------------------------------------------------

  _Supplier _find(int id) =>
      _suppliers.where((s) => s.id == id).firstOrNull ??
      (throw LocalBackendError.notFound(
        'No se encontró el proveedor solicitado.',
      ));

  void _rejectUnknown(Map<String, dynamic> body, String message) {
    for (final key in body.keys) {
      if (!_fields.contains(key)) {
        throw LocalBackendError.validation(key, '$message: $key.');
      }
    }
  }

  void _ensureUnique(String taxId, int? exceptId) {
    final duplicated = _suppliers.any(
      (s) => s.id != exceptId && s.taxId.toLowerCase() == taxId.toLowerCase(),
    );
    if (duplicated) {
      throw LocalBackendError.conflict(
        'Ya existe un proveedor con ese documento tributario.',
      );
    }
  }

  /// Texto opcional recortado: null si falta o queda vacío.
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

  Map<String, Object?> _json(_Supplier s) => {
    'id': s.id,
    'business_name': s.businessName,
    'tax_id': s.taxId,
    'contact_name': s.contactName,
    'phone': s.phone,
    'email': s.email,
    'location': s.location,
    'is_active': s.isActive,
    'created_at': s.createdAt.toIso8601String(),
    'updated_at': s.updatedAt.toIso8601String(),
  };
}
