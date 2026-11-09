import 'local_backend_store.dart';

class _Product {
  _Product({
    required this.id,
    required this.type,
    required this.variety,
    required this.qualityGrade,
    required this.baseUnitCode,
    this.hsCode,
    this.lowStockThreshold,
    this.humidityPercent,
    this.beanType,
    this.fermentationPercent,
    Set<int>? certificationIds,
  }) : certificationIds = certificationIds ?? {};

  final int id;
  final String type; // coffee | cacao (no cambia)
  String variety;
  String qualityGrade;
  final String baseUnitCode; // no cambia
  String? hsCode;
  num? lowStockThreshold;
  num? humidityPercent;
  String? beanType;
  num? fermentationPercent;
  Set<int> certificationIds;
  bool isActive = true;
  DateTime createdAt = DateTime.now().toUtc();
  DateTime updatedAt = DateTime.now().toUtc();
}

/// Catálogo de productos del backend local: mismas reglas y mensajes que las
/// funciones de `database/migrations/*_products_module.sql`.
class LocalProductsStore {
  static final _hsPattern = RegExp(r'^[0-9]{4}(\.[0-9]{2}){0,3}$');
  static String? _defaultHsCode(String type) => switch (type) {
    'coffee' => '0901.11',
    'cacao' => '1801.00',
    _ => null,
  };

  final _units = <String, String>{'kg': 'Kilogramo', 't': 'Tonelada métrica'};
  final _certifications = <Map<String, Object?>>[
    {'id': 1, 'code': 'ORGANIC', 'name': 'Orgánico', 'is_active': true},
    {'id': 2, 'code': 'FAIR_TRADE', 'name': 'Fair Trade', 'is_active': true},
    {
      'id': 3,
      'code': 'RAINFOREST_ALLIANCE',
      'name': 'Rainforest Alliance',
      'is_active': true,
    },
  ];
  final _products = <_Product>[];
  int _nextId = 1;

  // ---- Catálogos --------------------------------------------------------------

  Map<String, Object?> listCertifications() => {
    'items': [for (final c in _certifications) Map<String, Object?>.of(c)],
  };

  Map<String, Object?> listUnits() => {
    'items': [
      for (final entry in _units.entries)
        {'code': entry.key, 'name': entry.value},
    ],
  };

  // ---- Consulta -----------------------------------------------------------------

  Map<String, Object?> list(Map<String, String> query) {
    final limit = (int.tryParse(query['limit'] ?? '') ?? 20).clamp(1, 100);
    final offset = (int.tryParse(query['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
    final text = (query['q'] ?? '').trim().toLowerCase();
    final quality = (query['quality'] ?? '').trim().toLowerCase();
    final type = query['type'];
    final certification = int.tryParse(query['certification_id'] ?? '');
    final active = switch (query['is_active']) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    final matches =
        _products.where((p) {
          if (type == 'coffee' || type == 'cacao') {
            if (p.type != type) return false;
          }
          if (active != null && p.isActive != active) return false;
          if (certification != null &&
              !p.certificationIds.contains(certification)) {
            return false;
          }
          if (quality.isNotEmpty &&
              !p.qualityGrade.toLowerCase().contains(quality)) {
            return false;
          }
          if (text.isNotEmpty &&
              !'${p.variety} ${p.qualityGrade}'.toLowerCase().contains(text)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) {
          final byName = a.variety.toLowerCase().compareTo(
            b.variety.toLowerCase(),
          );
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });
    return {
      'items': [for (final p in matches.skip(offset).take(limit)) _json(p)],
      'pagination': {'total': matches.length, 'limit': limit, 'offset': offset},
    };
  }

  Map<String, Object?> get(int id) => _json(_find(id));

  /// Datos básicos de un producto, o null si no existe (para lotes).
  /// Productos activos con su umbral de stock mínimo (para el inventario consolidado).
  List<Map<String, Object?>> activeStockInfo() => [
    for (final p in _products)
      if (p.isActive)
        {
          'product_id': p.id,
          'product_type': p.type,
          'variety': p.variety,
          'quality_grade': p.qualityGrade,
          'base_unit_code': p.baseUnitCode,
          'low_stock_threshold': p.lowStockThreshold,
        },
  ];

  ({
    String type,
    String variety,
    String quality,
    String? hsCode,
    bool isActive,
  })?
  lookup(int id) {
    final product = _products.where((p) => p.id == id).firstOrNull;
    return product == null
        ? null
        : (
            type: product.type,
            variety: product.variety,
            quality: product.qualityGrade,
            hsCode: product.hsCode,
            isActive: product.isActive,
          );
  }

  // ---- Escritura ----------------------------------------------------------------

  Map<String, Object?> create(Map<String, dynamic>? body) {
    if (body == null) {
      throw LocalBackendError.validation('body', 'La solicitud no es válida.');
    }
    final type = body['type'];
    if (type != 'coffee' && type != 'cacao') {
      throw LocalBackendError.validation(
        'type',
        'El tipo de producto debe ser café o cacao.',
      );
    }
    final allowed = {
      'type',
      'variety',
      'quality_grade',
      'hs_code',
      'base_unit_code',
      'low_stock_threshold',
      'certification_ids',
      ...(type == 'coffee'
          ? {'humidity_percent'}
          : {'bean_type', 'fermentation_percent'}),
    };
    for (final key in body.keys) {
      if (!allowed.contains(key)) {
        throw LocalBackendError.validation(
          key,
          'Campo no permitido para un producto de ${type == 'coffee' ? 'café' : 'cacao'}: $key.',
        );
      }
    }
    final variety = _requiredText(body, 'variety', 'La variedad', 120);
    final quality = _requiredText(body, 'quality_grade', 'La calidad', 80);
    final hs = body.containsKey('hs_code')
        ? _hsCode(body)
        : _defaultHsCode(type);
    final unit = _text(body['base_unit_code']);
    if (unit == null || !_units.containsKey(unit)) {
      throw LocalBackendError.validation(
        'base_unit_code',
        'La unidad base no existe.',
      );
    }
    final threshold = _number(
      body,
      'low_stock_threshold',
      'El umbral de stock bajo',
    );
    if (threshold != null && threshold < 0) {
      throw LocalBackendError.validation(
        'low_stock_threshold',
        'El umbral de stock bajo no puede ser negativo.',
      );
    }

    num? humidity;
    String? bean;
    num? ferment;
    if (type == 'coffee') {
      humidity = _percent(
        body,
        'humidity_percent',
        'La humedad',
        'La humedad es obligatoria para el café.',
        'La humedad debe estar entre 0 y 100.',
      );
    } else {
      bean = _requiredText(
        body,
        'bean_type',
        'El tipo de grano',
        100,
        requiredMessage: 'El tipo de grano es obligatorio para el cacao.',
      );
      ferment = _percent(
        body,
        'fermentation_percent',
        'El porcentaje de fermentación',
        'El porcentaje de fermentación es obligatorio para el cacao.',
        'El porcentaje de fermentación debe estar entre 0 y 100.',
      );
    }
    final certIds = _certificationIds(body['certification_ids']);
    _ensureUnique(type as String, variety, quality, null);

    final product = _Product(
      id: _nextId++,
      type: type,
      variety: variety,
      qualityGrade: quality,
      baseUnitCode: unit,
      hsCode: hs,
      lowStockThreshold: threshold,
      humidityPercent: humidity,
      beanType: bean,
      fermentationPercent: ferment,
      certificationIds: certIds,
    );
    _products.add(product);
    return _json(product);
  }

  Map<String, Object?> update(int id, Map<String, dynamic>? body) {
    final product = _find(id);
    if (body == null || body.isEmpty) {
      throw LocalBackendError.validation(
        'body',
        'Indica al menos un campo para actualizar.',
      );
    }
    final allowed = {
      'type',
      'base_unit_code',
      'variety',
      'quality_grade',
      'hs_code',
      'low_stock_threshold',
      ...(product.type == 'coffee'
          ? {'humidity_percent'}
          : {'bean_type', 'fermentation_percent'}),
    };
    for (final key in body.keys) {
      if (!allowed.contains(key)) {
        throw LocalBackendError.validation(key, 'Campo no permitido: $key.');
      }
    }
    if (body.containsKey('type') && body['type'] != product.type) {
      throw LocalBackendError.validation(
        'type',
        'El tipo de producto no se puede cambiar.',
      );
    }
    if (body.containsKey('base_unit_code') &&
        body['base_unit_code'] != product.baseUnitCode) {
      throw LocalBackendError.validation(
        'base_unit_code',
        'La unidad base no se puede cambiar.',
      );
    }

    // Se valida todo antes de aplicar nada (atomicidad, como la función de la base).
    final variety = body.containsKey('variety')
        ? _requiredText(body, 'variety', 'La variedad', 120)
        : product.variety;
    final quality = body.containsKey('quality_grade')
        ? _requiredText(body, 'quality_grade', 'La calidad', 80)
        : product.qualityGrade;
    final hs = body.containsKey('hs_code')
        ? _hsCode(body)
        : product.hsCode ?? _defaultHsCode(product.type);
    num? threshold = product.lowStockThreshold;
    if (body.containsKey('low_stock_threshold')) {
      threshold = _number(
        body,
        'low_stock_threshold',
        'El umbral de stock bajo',
      );
      if (threshold != null && threshold < 0) {
        throw LocalBackendError.validation(
          'low_stock_threshold',
          'El umbral de stock bajo no puede ser negativo.',
        );
      }
    }
    num? humidity = product.humidityPercent;
    String? bean = product.beanType;
    num? ferment = product.fermentationPercent;
    if (body.containsKey('humidity_percent')) {
      humidity = _percent(
        body,
        'humidity_percent',
        'La humedad',
        'La humedad es obligatoria para el café.',
        'La humedad debe estar entre 0 y 100.',
      );
    }
    if (body.containsKey('bean_type')) {
      bean = _requiredText(
        body,
        'bean_type',
        'El tipo de grano',
        100,
        requiredMessage: 'El tipo de grano es obligatorio para el cacao.',
      );
    }
    if (body.containsKey('fermentation_percent')) {
      ferment = _percent(
        body,
        'fermentation_percent',
        'El porcentaje de fermentación',
        'El porcentaje de fermentación es obligatorio para el cacao.',
        'El porcentaje de fermentación debe estar entre 0 y 100.',
      );
    }
    _ensureUnique(product.type, variety, quality, product.id);

    product
      ..variety = variety
      ..qualityGrade = quality
      ..hsCode = hs
      ..lowStockThreshold = threshold
      ..humidityPercent = humidity
      ..beanType = bean
      ..fermentationPercent = ferment
      ..updatedAt = DateTime.now().toUtc();
    return _json(product);
  }

  Map<String, Object?> setActive(int id, Map<String, dynamic>? body) {
    final product = _find(id);
    final active = body?['is_active'];
    if (active is! bool) {
      throw LocalBackendError.validation(
        'is_active',
        'Indica si el producto debe quedar activo.',
      );
    }
    product
      ..isActive = active
      ..updatedAt = DateTime.now().toUtc();
    return _json(product);
  }

  Map<String, Object?> setCertifications(int id, Map<String, dynamic>? body) {
    final product = _find(id);
    final ids = _certificationIds(
      body?['certification_ids'],
      existing: product.certificationIds,
    );
    product
      ..certificationIds = ids
      ..updatedAt = DateTime.now().toUtc();
    return _json(product);
  }

  // ---- Utilidades -----------------------------------------------------------------

  _Product _find(int id) =>
      _products.where((p) => p.id == id).firstOrNull ??
      (throw LocalBackendError.notFound(
        'No se encontró el producto solicitado.',
      ));

  void _ensureUnique(
    String type,
    String variety,
    String quality,
    int? exceptId,
  ) {
    final duplicated = _products.any(
      (p) =>
          p.id != exceptId &&
          p.type == type &&
          p.variety.toLowerCase() == variety.toLowerCase() &&
          p.qualityGrade.toLowerCase() == quality.toLowerCase(),
    );
    if (duplicated) {
      throw LocalBackendError.conflict(
        'Ya existe un producto con ese tipo, variedad y calidad.',
      );
    }
  }

  String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _requiredText(
    Map<String, dynamic> body,
    String key,
    String label,
    int max, {
    String? requiredMessage,
  }) {
    final text = _text(body[key]);
    if (text == null) {
      throw LocalBackendError.validation(
        key,
        requiredMessage ?? '$label es obligatoria.',
      );
    }
    if (text.length > max) {
      throw LocalBackendError.validation(
        key,
        '$label admite máximo $max caracteres.',
      );
    }
    return text;
  }

  String? _hsCode(Map<String, dynamic> body) {
    final text = _text(body['hs_code']);
    if (text != null && !_hsPattern.hasMatch(text)) {
      throw LocalBackendError.validation(
        'hs_code',
        'El código HS no tiene un formato válido (por ejemplo 0901.11).',
      );
    }
    return text;
  }

  num? _number(Map<String, dynamic> body, String key, String label) {
    final value = body[key];
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw LocalBackendError.validation(
      key,
      '$label debe ser un número válido.',
    );
  }

  num _percent(
    Map<String, dynamic> body,
    String key,
    String label,
    String requiredMessage,
    String rangeMessage,
  ) {
    final value = _number(body, key, label);
    if (value == null) throw LocalBackendError.validation(key, requiredMessage);
    if (value < 0 || value > 100) {
      throw LocalBackendError.validation(key, rangeMessage);
    }
    return value;
  }

  Set<int> _certificationIds(Object? raw, {Set<int>? existing}) {
    if (raw == null) return {};
    if (raw is! List || raw.any((e) => e is! int)) {
      throw LocalBackendError.validation(
        'certification_ids',
        'Las certificaciones deben ser una lista de identificadores.',
      );
    }
    final ids = raw.cast<int>();
    if (ids.length != ids.toSet().length) {
      throw LocalBackendError.validation(
        'certification_ids',
        'No se permiten certificaciones duplicadas.',
      );
    }
    for (final id in ids) {
      final cert = _certifications.where((c) => c['id'] == id).firstOrNull;
      if (cert == null) {
        throw LocalBackendError.validation(
          'certification_ids',
          existing == null
              ? 'Una o más certificaciones no existen o están inactivas.'
              : 'Una o más certificaciones no existen.',
        );
      }
      // Una certificación inactiva puede conservarse, pero no asignarse de nuevo.
      final alreadyAssigned = existing?.contains(id) ?? false;
      if (cert['is_active'] != true && !alreadyAssigned) {
        throw LocalBackendError.validation(
          'certification_ids',
          existing == null
              ? 'Una o más certificaciones no existen o están inactivas.'
              : 'Una o más certificaciones están inactivas.',
        );
      }
    }
    return ids.toSet();
  }

  Map<String, Object?> _json(_Product p) {
    final certs = [
      for (final c in _certifications)
        if (p.certificationIds.contains(c['id']))
          {'id': c['id'], 'code': c['code'], 'name': c['name']},
    ]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return {
      'id': p.id,
      'type': p.type,
      'variety': p.variety,
      'quality_grade': p.qualityGrade,
      'hs_code': p.hsCode,
      'base_unit_code': p.baseUnitCode,
      'base_unit_name': _units[p.baseUnitCode],
      'low_stock_threshold': p.lowStockThreshold,
      'is_active': p.isActive,
      'created_at': p.createdAt.toIso8601String(),
      'updated_at': p.updatedAt.toIso8601String(),
      'humidity_percent': p.humidityPercent,
      'bean_type': p.beanType,
      'fermentation_percent': p.fermentationPercent,
      'certifications': certs,
      'certification_ids': (p.certificationIds.toList()..sort()),
    };
  }
}
