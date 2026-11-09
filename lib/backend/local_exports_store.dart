import 'local_orders_store.dart';
import 'local_origin_store.dart';
import 'local_products_store.dart';

class LocalExportError implements Exception {
  const LocalExportError(this.field, this.message);
  final String field;
  final String message;
}

class LocalExportsStore {
  LocalExportsStore(this.orders, this.origin, this.products);

  final LocalOrdersStore orders;
  final LocalOriginStore origin;
  final LocalProductsStore products;
  final List<Map<String, Object?>> _exports = [];
  int _nextId = 1;

  static const destinations = <Map<String, String>>[
    {'code': 'AR', 'name': 'Argentina'},
    {'code': 'AU', 'name': 'Australia'},
    {'code': 'AT', 'name': 'Austria'},
    {'code': 'BE', 'name': 'Bélgica'},
    {'code': 'BO', 'name': 'Bolivia'},
    {'code': 'BR', 'name': 'Brasil'},
    {'code': 'CA', 'name': 'Canadá'},
    {'code': 'CL', 'name': 'Chile'},
    {'code': 'CN', 'name': 'China'},
    {'code': 'CO', 'name': 'Colombia'},
    {'code': 'CR', 'name': 'Costa Rica'},
    {'code': 'DK', 'name': 'Dinamarca'},
    {'code': 'EC', 'name': 'Ecuador'},
    {'code': 'ES', 'name': 'España'},
    {'code': 'US', 'name': 'Estados Unidos'},
    {'code': 'FR', 'name': 'Francia'},
    {'code': 'DE', 'name': 'Alemania'},
    {'code': 'IT', 'name': 'Italia'},
    {'code': 'JP', 'name': 'Japón'},
    {'code': 'MX', 'name': 'México'},
    {'code': 'NL', 'name': 'Países Bajos'},
    {'code': 'PA', 'name': 'Panamá'},
    {'code': 'PE', 'name': 'Perú'},
    {'code': 'GB', 'name': 'Reino Unido'},
    {'code': 'CH', 'name': 'Suiza'},
    {'code': 'CZ', 'name': 'Chequia'},
    {'code': 'EG', 'name': 'Egipto'},
    {'code': 'SV', 'name': 'El Salvador'},
    {'code': 'AE', 'name': 'Emiratos Árabes Unidos'},
    {'code': 'SK', 'name': 'Eslovaquia'},
    {'code': 'SI', 'name': 'Eslovenia'},
    {'code': 'EE', 'name': 'Estonia'},
    {'code': 'FI', 'name': 'Finlandia'},
    {'code': 'GR', 'name': 'Grecia'},
    {'code': 'GT', 'name': 'Guatemala'},
    {'code': 'HN', 'name': 'Honduras'},
    {'code': 'HK', 'name': 'Hong Kong'},
    {'code': 'HU', 'name': 'Hungría'},
    {'code': 'IN', 'name': 'India'},
    {'code': 'ID', 'name': 'Indonesia'},
    {'code': 'IE', 'name': 'Irlanda'},
    {'code': 'IS', 'name': 'Islandia'},
    {'code': 'IL', 'name': 'Israel'},
    {'code': 'KR', 'name': 'Corea del Sur'},
    {'code': 'LV', 'name': 'Letonia'},
    {'code': 'LT', 'name': 'Lituania'},
    {'code': 'LU', 'name': 'Luxemburgo'},
    {'code': 'MY', 'name': 'Malasia'},
    {'code': 'MT', 'name': 'Malta'},
    {'code': 'MA', 'name': 'Marruecos'},
    {'code': 'NI', 'name': 'Nicaragua'},
    {'code': 'NO', 'name': 'Noruega'},
    {'code': 'NZ', 'name': 'Nueva Zelanda'},
    {'code': 'PY', 'name': 'Paraguay'},
    {'code': 'PL', 'name': 'Polonia'},
    {'code': 'PT', 'name': 'Portugal'},
    {'code': 'DO', 'name': 'República Dominicana'},
    {'code': 'RO', 'name': 'Rumanía'},
    {'code': 'SG', 'name': 'Singapur'},
    {'code': 'ZA', 'name': 'Sudáfrica'},
    {'code': 'SE', 'name': 'Suecia'},
    {'code': 'TH', 'name': 'Tailandia'},
    {'code': 'TW', 'name': 'Taiwán'},
    {'code': 'TR', 'name': 'Turquía'},
    {'code': 'UA', 'name': 'Ucrania'},
    {'code': 'UY', 'name': 'Uruguay'},
    {'code': 'VN', 'name': 'Vietnam'},
  ];

  static const incoterms = <Map<String, String>>[
    {'code': 'EXW', 'name': 'En fábrica'},
    {'code': 'FCA', 'name': 'Franco transportista'},
    {'code': 'CPT', 'name': 'Transporte pagado hasta'},
    {'code': 'CIP', 'name': 'Transporte y seguro pagados hasta'},
    {'code': 'DAP', 'name': 'Entregada en lugar'},
    {'code': 'DPU', 'name': 'Entregada en lugar descargada'},
    {'code': 'DDP', 'name': 'Entregada derechos pagados'},
    {'code': 'FAS', 'name': 'Franco al costado del buque'},
    {'code': 'FOB', 'name': 'Franco a bordo'},
    {'code': 'CFR', 'name': 'Coste y flete'},
    {'code': 'CIF', 'name': 'Coste, seguro y flete'},
  ];

  List<Map<String, Object?>> get all =>
      _exports.map(Map<String, Object?>.from).toList();

  Map<String, Object?> get(int exportId) {
    final export = _exports.where((item) => item['id'] == exportId).firstOrNull;
    if (export == null) {
      throw const LocalExportError('export_id', 'La exportación no existe.');
    }
    return Map<String, Object?>.from(export);
  }

  List<Map<String, Object?>> traceability(int exportId) {
    final export = get(exportId);
    final order = orders.get(export['order_id'] as int);
    final rows = <Map<String, Object?>>[];
    for (final line
        in ((export['lines'] as List?) ?? const []).whereType<Map>()) {
      final orderLineId =
          line['order_line_id'] as int? ?? (line['id'] as int? ?? 0);
      final orderLine = ((order['lines'] as List?) ?? const [])
          .whereType<Map>()
          .where((item) => (item['order_line_id'] ?? item['id']) == orderLineId)
          .firstOrNull;
      final lotId =
          (orderLine?['product_lot_id'] as int?) ??
          (line['product_lot_id'] as int? ?? 0);
      final lot = origin.getLot(lotId);
      final product = products.lookup(lot['product_id'] as int);
      if (product == null) continue;
      rows.add({
        'export_id': export['id'],
        'export_line_id': line['id'] ?? line['order_line_id'],
        'order_line_id': orderLineId,
        'quantity': line['quantity'],
        'hs_code_snapshot':
            line['hs_code_snapshot'] ??
            orderLine?['hs_code_snapshot'] ??
            product.hsCode,
        'lot_id': lot['id'],
        'lot_code': lot['lot_code'],
        'product_id': lot['product_id'],
        'product_type': product.type,
        'product_variety': product.variety,
        'product_quality': product.quality,
        'farm_id': lot['farm_id'],
        'farm_name': lot['farm_name'],
        'country_code': lot['country_code'],
        'latitude': lot['latitude'],
        'longitude': lot['longitude'],
        'supplier_id': lot['supplier_id'],
        'supplier_name': lot['supplier_name'],
      });
    }
    return rows;
  }

  List<Map<String, Object?>> originFarms(int exportId) {
    final rows = traceability(exportId);
    final farmMap = <int, Map<String, Object?>>{};
    for (final row in rows) {
      final farmId = row['farm_id'] as int;
      final entry = farmMap.putIfAbsent(
        farmId,
        () => {
          'export_id': exportId,
          'farm_id': farmId,
          'farm_name': row['farm_name'],
          'country_code': row['country_code'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'supplier_id': row['supplier_id'],
          'supplier_name': row['supplier_name'],
          'total_quantity': 0,
          'lot_count': 0,
        },
      );
      entry['total_quantity'] =
          (entry['total_quantity'] as num) + (row['quantity'] as num);
      entry['lot_count'] = (entry['lot_count'] as int) + 1;
    }
    return farmMap.values.toList();
  }

  Map<String, Object?> generateEudr(int exportId) {
    final export = get(exportId);
    final originRows = traceability(exportId);
    final lineCount = ((export['lines'] as List?) ?? const []).length;
    final issues = <String>[
      if (lineCount == 0) 'La exportación no tiene líneas.',
      if (originRows.length < lineCount)
        'Hay líneas sin lote, finca o proveedor de origen.',
      if (originRows.any(
        (row) => row['latitude'] == null || row['longitude'] == null,
      ))
        'Hay fincas sin coordenadas de geolocalización.',
      if (originRows.any((row) => row['hs_code_snapshot'] == null))
        'Hay líneas sin código arancelario HS.',
    ];
    final result = {
      'export_id': export['id'],
      'export_date': export['export_date'],
      'destination_country_code': export['destination_country_code'],
      'status': export['status'],
      'declaration_date': DateTime.now().toIso8601String().substring(0, 10),
      'line_count': export['line_count'],
      'total_quantity': export['total_quantity'],
      'farm_count': originRows.map((row) => row['farm_id']).toSet().length,
      'supplier_count': originRows
          .map((row) => row['supplier_id'])
          .toSet()
          .length,
      'traceability_valid': issues.isEmpty,
      'issues': issues,
      'hs_codes': originRows
          .map((row) => row['hs_code_snapshot'])
          .whereType<String>()
          .toSet()
          .toList(),
      'origin_farms': originFarms(exportId),
    };
    return result;
  }

  Map<String, Object?> create(Map<String, dynamic>? body) {
    if (body == null ||
        body.keys.any(
          (key) => !{
            'order_id',
            'destination_country_code',
            'incoterm_code',
            'export_date',
            'lines',
          }.contains(key),
        )) {
      throw const LocalExportError('body', 'La solicitud no es válida.');
    }
    final orderId = body['order_id'];
    if (orderId is! int) {
      throw const LocalExportError('order_id', 'Selecciona un pedido.');
    }
    final order = orders.get(orderId);
    if (order['status'] != 'confirmed') {
      throw const LocalExportError(
        'order_id',
        'Solo se pueden exportar pedidos confirmados.',
      );
    }
    final countryCode = body['destination_country_code'] is String
        ? (body['destination_country_code'] as String).toUpperCase()
        : '';
    final destination = destinations
        .where((item) => item['code'] == countryCode)
        .firstOrNull;
    if (destination == null) {
      throw const LocalExportError(
        'destination_country_code',
        'Selecciona un país de destino válido.',
      );
    }
    final rawIncoterm = body['incoterm_code'];
    if (rawIncoterm != null && rawIncoterm is! String) {
      throw const LocalExportError(
        'incoterm_code',
        'El Incoterm no es válido.',
      );
    }
    final incotermCode = rawIncoterm is String
        ? rawIncoterm.trim().toUpperCase()
        : null;
    final incoterm = incotermCode == null || incotermCode.isEmpty
        ? null
        : incoterms.where((item) => item['code'] == incotermCode).firstOrNull;
    if (incotermCode != null && incoterm == null) {
      throw const LocalExportError(
        'incoterm_code',
        'Selecciona un Incoterm válido.',
      );
    }
    final rawDate = body['export_date'];
    final exportDate = rawDate == null
        ? DateTime.now().toIso8601String().substring(0, 10)
        : rawDate is String && DateTime.tryParse(rawDate) != null
        ? DateTime.parse(rawDate).toIso8601String().substring(0, 10)
        : null;
    if (exportDate == null) {
      throw const LocalExportError(
        'export_date',
        'La fecha de exportación no es válida.',
      );
    }
    final lines = body['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 100) {
      throw const LocalExportError('lines', 'Agrega entre 1 y 100 líneas.');
    }

    final orderLines = (order['lines']! as List).cast<Map>();
    final requested = <int, num>{};
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line is! Map ||
          line.keys.any(
            (key) => !{'order_line_id', 'quantity'}.contains(key),
          ) ||
          line['order_line_id'] is! int ||
          line['quantity'] is! num ||
          !(line['quantity'] as num).isFinite ||
          (line['quantity'] as num) <= 0) {
        throw LocalExportError('lines[$index]', 'La línea no es válida.');
      }
      final lineId = line['order_line_id'] as int;
      if (requested.containsKey(lineId)) {
        throw const LocalExportError('lines', 'No repitas líneas del pedido.');
      }
      final orderLine = orderLines
          .where((item) => (item['order_line_id'] ?? item['id']) == lineId)
          .firstOrNull;
      if (orderLine == null) {
        throw const LocalExportError(
          'lines',
          'La línea no pertenece al pedido.',
        );
      }
      final previouslyExported = _exports
          .where((item) => item['order_id'] == orderId)
          .expand((item) => item['lines'] as List)
          .whereType<Map>()
          .where((item) => item['order_line_id'] == lineId)
          .fold<num>(0, (sum, item) => sum + (item['quantity'] as num));
      final quantity = line['quantity'] as num;
      if (previouslyExported + quantity > (orderLine['quantity'] as num)) {
        throw const LocalExportError(
          'lines',
          'La cantidad supera el saldo disponible de la línea del pedido.',
        );
      }
      requested[lineId] = quantity;
    }

    final exportLines = [
      for (final entry in requested.entries)
        {
          'order_line_id': entry.key,
          'product_lot_id': orderLines.firstWhere(
            (item) => (item['order_line_id'] ?? item['id']) == entry.key,
          )['product_lot_id'],
          'quantity': entry.value,
          'hs_code_snapshot':
              orderLines.firstWhere(
                (item) => (item['order_line_id'] ?? item['id']) == entry.key,
              )['hs_code_snapshot'] ??
              products
                  .lookup(
                    orderLines.firstWhere(
                          (item) =>
                              (item['order_line_id'] ?? item['id']) ==
                              entry.key,
                        )['product_id']
                        as int,
                  )
                  ?.hsCode,
        },
    ];
    final export = <String, Object?>{
      'id': _nextId++,
      'order_id': orderId,
      'order_number': order['order_number'],
      'customer_name': order['customer_name'],
      'destination_country_code': countryCode,
      'destination_country_name': destination['name'],
      'incoterm_code': incoterm?['code'],
      'incoterm_name': incoterm?['name'],
      'export_date': exportDate,
      'status': 'draft',
      'lines': exportLines,
      'line_count': exportLines.length,
      'total_quantity': exportLines.fold<num>(
        0,
        (sum, line) => sum + (line['quantity'] as num),
      ),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    _exports.add(export);
    return Map<String, Object?>.from(export);
  }
}
