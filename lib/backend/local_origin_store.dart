import 'local_backend_store.dart';
import 'local_products_store.dart';
import 'local_suppliers_store.dart';

class _Farm {
  _Farm({
    required this.id,
    required this.supplierId,
    required this.countryCode,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
  });

  final int id;
  final int supplierId; // no cambia
  String countryCode;
  String name;
  String? address;
  num? latitude;
  num? longitude;
  bool isActive = true;
  final DateTime createdAt = DateTime.now().toUtc();
  DateTime updatedAt = DateTime.now().toUtc();
}

class _Lot {
  _Lot({
    required this.id,
    required this.productId,
    required this.farmId,
    required this.lotCode,
  });

  final int id;
  final int productId;
  final int farmId;
  final String lotCode;
  final DateTime createdAt = DateTime.now().toUtc();
}

/// Fincas con geolocalización y lotes del backend local: mismas reglas y
/// mensajes que las funciones de `database/migrations/*_farms_and_lots.sql`.
class LocalOriginStore {
  LocalOriginStore(this._suppliers, this._products);

  final LocalSuppliersStore _suppliers;
  final LocalProductsStore _products;

  static const _farmFields = {
    'supplier_id',
    'country_code',
    'name',
    'address',
    'latitude',
    'longitude',
  };
  static final _countryPattern = RegExp(r'^[A-Z]{2}$');

  final _farms = <_Farm>[];
  final _lots = <_Lot>[];
  int _nextFarmId = 1;
  int _nextLotId = 1;

  // ---- Fincas -------------------------------------------------------------------

  Map<String, Object?> listFarms(Map<String, String> query) {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
    final text = (query['q'] ?? '').trim().toLowerCase();
    final supplier = int.tryParse(query['supplier_id'] ?? '');
    final active = switch (query['is_active']) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    final matches =
        _farms
            .where(
              (f) =>
                  (active == null || f.isActive == active) &&
                  (supplier == null || f.supplierId == supplier) &&
                  (text.isEmpty ||
                      '${f.name} ${_suppliers.lookup(f.supplierId)?.name ?? ''}'
                          .toLowerCase()
                          .contains(text)),
            )
            .toList()
          ..sort((a, b) {
            final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return byName != 0 ? byName : a.id.compareTo(b.id);
          });
    return {
      'items': [for (final f in matches.skip(offset).take(limit)) _farmJson(f)],
      'pagination': {'total': matches.length, 'limit': limit, 'offset': offset},
    };
  }

  Map<String, Object?> getFarm(int id) => _farmJson(_findFarm(id));

  Map<String, Object?> createFarm(Map<String, dynamic>? body) {
    if (body == null) {
      throw LocalBackendError.validation('body', 'La solicitud no es válida.');
    }
    _rejectUnknown(body, _farmFields, 'Campo no permitido para una finca');
    final supplierId = body['supplier_id'];
    if (supplierId is! int || supplierId < 0) {
      throw LocalBackendError.validation(
        'supplier_id',
        'El proveedor es obligatorio.',
      );
    }
    final supplier = _suppliers.lookup(supplierId);
    if (supplier == null) {
      throw LocalBackendError.validation(
        'supplier_id',
        'El proveedor no existe.',
      );
    }
    if (!supplier.isActive) {
      throw LocalBackendError.validation(
        'supplier_id',
        'El proveedor está inactivo.',
      );
    }
    final country = _country(body) ?? (throw _countryRequired());
    final name =
        _text(body, 'name', 'El nombre de la finca', 160) ??
        (throw LocalBackendError.validation(
          'name',
          'El nombre de la finca es obligatorio.',
        ));
    final address = _text(body, 'address', 'La dirección', 300);
    final latitude = _coordinate(body, 'latitude', 'La latitud', 90);
    final longitude = _coordinate(body, 'longitude', 'La longitud', 180);
    _checkPoint(latitude, longitude);
    _ensureUniqueFarm(supplierId, name, null);

    final farm = _Farm(
      id: _nextFarmId++,
      supplierId: supplierId,
      countryCode: country,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
    _farms.add(farm);
    return _farmJson(farm);
  }

  Map<String, Object?> updateFarm(int id, Map<String, dynamic>? body) {
    final farm = _findFarm(id);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    _rejectUnknown(body, _farmFields, 'Campo no permitido');
    if (body.containsKey('supplier_id') &&
        body['supplier_id'] != farm.supplierId) {
      throw LocalBackendError.validation(
        'supplier_id',
        'La finca no se puede pasar a otro proveedor.',
      );
    }

    // Se valida todo antes de aplicar nada (atomicidad, como la función de la base).
    final country = body.containsKey('country_code')
        ? (_country(body) ?? (throw _countryRequired()))
        : farm.countryCode;
    final name = body.containsKey('name')
        ? (_text(body, 'name', 'El nombre de la finca', 160) ??
              (throw LocalBackendError.validation(
                'name',
                'El nombre de la finca es obligatorio.',
              )))
        : farm.name;
    final address = body.containsKey('address')
        ? _text(body, 'address', 'La dirección', 300)
        : farm.address;
    final latitude = body.containsKey('latitude')
        ? _coordinate(body, 'latitude', 'La latitud', 90)
        : farm.latitude;
    final longitude = body.containsKey('longitude')
        ? _coordinate(body, 'longitude', 'La longitud', 180)
        : farm.longitude;
    _checkPoint(latitude, longitude);
    _ensureUniqueFarm(farm.supplierId, name, farm.id);

    final changed =
        country != farm.countryCode ||
        name != farm.name ||
        address != farm.address ||
        latitude != farm.latitude ||
        longitude != farm.longitude;
    if (changed) {
      farm
        ..countryCode = country
        ..name = name
        ..address = address
        ..latitude = latitude
        ..longitude = longitude
        ..updatedAt = DateTime.now().toUtc();
    }
    return _farmJson(farm);
  }

  Map<String, Object?> setFarmActive(int id, Map<String, dynamic>? body) {
    final farm = _findFarm(id);
    final active = body?['is_active'];
    if (active is! bool) {
      throw LocalBackendError.validation(
        'is_active',
        'Indica si la finca debe quedar activa.',
      );
    }
    if (farm.isActive != active) {
      farm
        ..isActive = active
        ..updatedAt = DateTime.now().toUtc();
    }
    return _farmJson(farm);
  }

  // ---- Lotes --------------------------------------------------------------------

  Map<String, Object?> listLots(Map<String, String> query) {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
    final text = (query['q'] ?? '').trim().toLowerCase();
    final farm = int.tryParse(query['farm_id'] ?? '');
    final product = int.tryParse(query['product_id'] ?? '');
    final matches =
        _lots
            .where(
              (l) =>
                  (farm == null || l.farmId == farm) &&
                  (product == null || l.productId == product) &&
                  (text.isEmpty || l.lotCode.toLowerCase().contains(text)),
            )
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));
    return {
      'items': [for (final l in matches.skip(offset).take(limit)) _lotJson(l)],
      'pagination': {'total': matches.length, 'limit': limit, 'offset': offset},
    };
  }

  Map<String, Object?> getLot(int id) => _lotJson(
    _lots.where((l) => l.id == id).firstOrNull ??
        (throw LocalBackendError.notFound(
          'No se encontró el lote solicitado.',
        )),
  );

  Map<String, Object?> createLot(Map<String, dynamic>? body) {
    if (body == null) {
      throw LocalBackendError.validation('body', 'La solicitud no es válida.');
    }
    _rejectUnknown(body, const {
      'product_id',
      'farm_id',
      'lot_code',
    }, 'Campo no permitido para un lote');
    final productId = body['product_id'];
    if (productId is! int || productId < 0) {
      throw LocalBackendError.validation(
        'product_id',
        'El producto es obligatorio.',
      );
    }
    final farmId = body['farm_id'];
    if (farmId is! int || farmId < 0) {
      throw LocalBackendError.validation('farm_id', 'La finca es obligatoria.');
    }
    final code =
        _text(body, 'lot_code', 'El código del lote', 80) ??
        (throw LocalBackendError.validation(
          'lot_code',
          'El código del lote es obligatorio.',
        ));
    final product = _products.lookup(productId);
    if (product == null) {
      throw LocalBackendError.validation(
        'product_id',
        'El producto no existe.',
      );
    }
    if (!product.isActive) {
      throw LocalBackendError.validation(
        'product_id',
        'El producto está inactivo.',
      );
    }
    final farm = _farms.where((f) => f.id == farmId).firstOrNull;
    if (farm == null) {
      throw LocalBackendError.validation('farm_id', 'La finca no existe.');
    }
    if (!farm.isActive) {
      throw LocalBackendError.validation('farm_id', 'La finca está inactiva.');
    }
    final duplicated = _lots.any(
      (l) =>
          l.farmId == farmId && l.lotCode.toLowerCase() == code.toLowerCase(),
    );
    if (duplicated) {
      throw LocalBackendError.conflict(
        'La finca ya tiene un lote con ese código.',
      );
    }
    final lot = _Lot(
      id: _nextLotId++,
      productId: productId,
      farmId: farmId,
      lotCode: code,
    );
    _lots.add(lot);
    return _lotJson(lot);
  }

  // ---- Utilidades ---------------------------------------------------------------

  _Farm _findFarm(int id) =>
      _farms.where((f) => f.id == id).firstOrNull ??
      (throw LocalBackendError.notFound('No se encontró la finca solicitada.'));

  void _rejectUnknown(
    Map<String, dynamic> body,
    Set<String> allowed,
    String message,
  ) {
    for (final key in body.keys) {
      if (!allowed.contains(key)) {
        throw LocalBackendError.validation(key, '$message: $key.');
      }
    }
  }

  void _ensureUniqueFarm(int supplierId, String name, int? exceptId) {
    final duplicated = _farms.any(
      (f) =>
          f.id != exceptId &&
          f.supplierId == supplierId &&
          f.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicated) {
      throw LocalBackendError.conflict(
        'El proveedor ya tiene una finca con ese nombre.',
      );
    }
  }

  LocalBackendError _countryRequired() =>
      LocalBackendError.validation('country_code', 'El país es obligatorio.');

  String? _country(Map<String, dynamic> body) {
    final value = _text(body, 'country_code', 'El país', 2)?.toUpperCase();
    if (value != null && !_countryPattern.hasMatch(value)) {
      throw LocalBackendError.validation(
        'country_code',
        'El país debe ser un código de 2 letras (por ejemplo CO).',
      );
    }
    return value;
  }

  void _checkPoint(num? latitude, num? longitude) {
    if ((latitude == null) != (longitude == null)) {
      throw LocalBackendError.validation(
        'latitude',
        'Informa la latitud y la longitud juntas, o ninguna.',
      );
    }
    if (latitude == 0 && longitude == 0) {
      throw LocalBackendError.validation(
        'latitude',
        'Las coordenadas (0, 0) no son una ubicación válida de finca.',
      );
    }
  }

  /// Coordenada opcional: número (o texto con coma decimal), dentro del rango
  /// y con máximo 6 decimales. Devuelve null si falta.
  num? _coordinate(
    Map<String, dynamic> body,
    String key,
    String label,
    num limit,
  ) {
    final value = body[key];
    if (value == null) return null;
    final num number;
    if (value is num) {
      number = value;
    } else if (value is String) {
      final parsed = num.tryParse(value.trim().replaceAll(',', '.'));
      if (parsed == null) {
        throw LocalBackendError.validation(
          key,
          '$label debe ser un número válido.',
        );
      }
      number = parsed;
    } else {
      throw LocalBackendError.validation(key, '$label debe ser un número.');
    }
    if (!number.isFinite || number < -limit || number > limit) {
      throw LocalBackendError.validation(
        key,
        '$label debe estar entre -$limit y $limit.',
      );
    }
    if ((number - double.parse(number.toStringAsFixed(6))).abs() > 1e-12) {
      throw LocalBackendError.validation(
        key,
        '$label admite como máximo 6 decimales.',
      );
    }
    return number;
  }

  String? _text(Map<String, dynamic> body, String key, String label, int max) {
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
    return text;
  }

  Map<String, Object?> _farmJson(_Farm f) => {
    'id': f.id,
    'supplier_id': f.supplierId,
    'supplier_name': _suppliers.lookup(f.supplierId)?.name,
    'country_code': f.countryCode,
    'name': f.name,
    'address': f.address,
    'latitude': f.latitude,
    'longitude': f.longitude,
    'is_active': f.isActive,
    'created_at': f.createdAt.toIso8601String(),
    'updated_at': f.updatedAt.toIso8601String(),
    'lot_count': _lots.where((l) => l.farmId == f.id).length,
  };

  Map<String, Object?> _lotJson(_Lot l) {
    final farm = _farms.firstWhere((f) => f.id == l.farmId);
    final product = _products.lookup(l.productId);
    return {
      'id': l.id,
      'lot_code': l.lotCode,
      'created_at': l.createdAt.toIso8601String(),
      'product_id': l.productId,
      'product_type': product?.type,
      'product_variety': product?.variety,
      'product_quality': product?.quality,
      'hs_code': product?.hsCode,
      'farm_id': l.farmId,
      'farm_name': farm.name,
      'country_code': farm.countryCode,
      'latitude': farm.latitude,
      'longitude': farm.longitude,
      'supplier_id': farm.supplierId,
      'supplier_name': _suppliers.lookup(farm.supplierId)?.name,
    };
  }
}
