import 'local_customers_store.dart';
import 'local_origin_store.dart';
import 'local_inventory_store.dart';

class LocalOrderError implements Exception {
  const LocalOrderError(this.field, this.message);
  final String field;
  final String message;
}

/// Implementacion en memoria del registro de pedidos para el modo local.
class LocalOrdersStore {
  LocalOrdersStore(this.customers, this.origin, this.inventory);

  final LocalCustomersStore customers;
  final LocalOriginStore origin;
  final LocalInventoryStore inventory;
  final List<Map<String, Object?>> _orders = [];
  int _nextId = 1;
  int _nextLineId = 1;

  Map<String, Object?> create(Map<String, dynamic>? body) {
    if (body == null ||
        body.keys.any(
          (key) => !{'customer_id', 'note', 'lines'}.contains(key),
        )) {
      throw const LocalOrderError('body', 'La solicitud no es válida.');
    }
    final customerId = body['customer_id'];
    if (customerId is! int) {
      throw const LocalOrderError('customer_id', 'Selecciona un cliente.');
    }
    final customer = customers.get(customerId);
    if (customer['is_active'] != true) {
      throw const LocalOrderError('customer_id', 'El cliente está inactivo.');
    }
    final lines = body['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 50) {
      throw const LocalOrderError('lines', 'Agrega entre 1 y 50 líneas.');
    }
    final note = body['note'];
    if (note != null && (note is! String || note.length > 1000)) {
      throw const LocalOrderError(
        'note',
        'La nota admite hasta 1000 caracteres.',
      );
    }

    // Valida todas las lineas antes de guardar el pedido (operacion atomica).
    final cleanLines = <Map<String, Object?>>[];
    final requestedByLot = <int, num>{};
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line is! Map ||
          line.keys.any(
            (key) =>
                !{'product_lot_id', 'quantity', 'unit_price'}.contains(key),
          )) {
        throw LocalOrderError('lines[$index]', 'La línea no es válida.');
      }
      final lotId = line['product_lot_id'];
      final quantity = line['quantity'];
      final price = line['unit_price'];
      if (lotId is! int ||
          quantity is! num ||
          !quantity.isFinite ||
          quantity <= 0 ||
          price is! num ||
          !price.isFinite ||
          price < 0) {
        throw LocalOrderError(
          'lines[$index]',
          'Lote, cantidad o precio no válido.',
        );
      }
      final lot = origin.getLot(lotId);
      requestedByLot.update(
        lotId,
        (amount) => amount + quantity,
        ifAbsent: () => quantity,
      );
      final lineId = _nextLineId++;
      cleanLines.add({
        'id': lineId,
        'order_line_id': lineId,
        'product_lot_id': lotId,
        'lot_code': lot['lot_code'],
        'product_name':
            '${lot['product_type'] ?? ''} ${lot['product_variety'] ?? ''} ${lot['product_quality'] ?? ''}'
                .trim(),
        'farm_name': lot['farm_name'],
        'product_id': lot['product_id'],
        'quantity': quantity,
        'unit_price': price,
        'currency_code': customer['preferred_currency_code'],
        'hs_code_snapshot': lot['hs_code'] as String?,
      });
    }

    for (final entry in requestedByLot.entries) {
      if (inventory.available(entry.key) < entry.value) {
        throw const LocalOrderError(
          'lines',
          'No hay existencias suficientes para uno de los lotes.',
        );
      }
    }
    for (final entry in requestedByLot.entries) {
      inventory.consume(entry.key, entry.value);
    }

    final id = _nextId++;
    final order = <String, Object?>{
      'id': id,
      'order_number':
          'PED-${DateTime.now().year}-${id.toString().padLeft(6, '0')}',
      'customer_id': customerId,
      'customer_name': customer['name'],
      'currency_code': customer['preferred_currency_code'],
      'status': 'draft',
      'status_history': [
        {
          'from_status': null,
          'to_status': 'draft',
          'changed_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      'note': note is String && note.trim().isNotEmpty ? note.trim() : null,
      'lines': cleanLines,
      'line_count': cleanLines.length,
      'order_total': cleanLines.fold<num>(
        0,
        (sum, line) =>
            sum + (line['quantity'] as num) * (line['unit_price'] as num),
      ),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    _orders.add(order);
    return Map<String, Object?>.from(order);
  }

  List<Map<String, Object?>> get all =>
      _orders.map(Map<String, Object?>.from).toList();

  Map<String, Object?> get(int id) {
    final order = _orders.where((item) => item['id'] == id).firstOrNull;
    if (order == null) {
      throw const LocalOrderError('order_id', 'El pedido no existe.');
    }
    return Map<String, Object?>.from(order);
  }

  Map<String, Object?> update(int id, Map<String, dynamic>? body) {
    if (body == null ||
        body.keys.any(
          (key) => !{'customer_id', 'note', 'lines'}.contains(key),
        )) {
      throw const LocalOrderError('body', 'La solicitud no es válida.');
    }
    final order = _orders.where((item) => item['id'] == id).firstOrNull;
    if (order == null) {
      throw const LocalOrderError('order_id', 'El pedido no existe.');
    }
    if (order['status'] != 'draft') {
      throw const LocalOrderError(
        'status',
        'Solo se pueden editar pedidos en borrador.',
      );
    }
    final customerId = body['customer_id'];
    if (customerId is! int) {
      throw const LocalOrderError('customer_id', 'Selecciona un cliente.');
    }
    final customer = customers.get(customerId);
    if (customer['is_active'] != true) {
      throw const LocalOrderError('customer_id', 'El cliente está inactivo.');
    }
    final lines = body['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 50) {
      throw const LocalOrderError('lines', 'Agrega entre 1 y 50 líneas.');
    }
    final note = body['note'];
    if (note != null && (note is! String || note.length > 1000)) {
      throw const LocalOrderError(
        'note',
        'La nota admite hasta 1000 caracteres.',
      );
    }

    final oldLines = (order['lines']! as List).cast<Map<String, Object?>>();
    final oldQuantities = <int, num>{};
    for (final line in oldLines) {
      final lotId = line['product_lot_id'] as int;
      oldQuantities.update(
        lotId,
        (quantity) => quantity + (line['quantity'] as num),
        ifAbsent: () => line['quantity'] as num,
      );
    }

    final replacement = <Map<String, Object?>>[];
    final newQuantities = <int, num>{};
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line is! Map ||
          line.keys.any(
            (key) =>
                !{'product_lot_id', 'quantity', 'unit_price'}.contains(key),
          )) {
        throw LocalOrderError('lines[$index]', 'La línea no es válida.');
      }
      final lotId = line['product_lot_id'];
      final quantity = line['quantity'];
      final price = line['unit_price'];
      if (lotId is! int ||
          quantity is! num ||
          !quantity.isFinite ||
          quantity <= 0 ||
          price is! num ||
          !price.isFinite ||
          price < 0) {
        throw LocalOrderError(
          'lines[$index]',
          'Lote, cantidad o precio no válido.',
        );
      }
      final lot = origin.getLot(lotId);
      newQuantities.update(
        lotId,
        (amount) => amount + quantity,
        ifAbsent: () => quantity,
      );
      replacement.add({
        'id': 0,
        'order_line_id': 0,
        'product_lot_id': lotId,
        'lot_code': lot['lot_code'],
        'product_name':
            '${lot['product_type'] ?? ''} ${lot['product_variety'] ?? ''} ${lot['product_quality'] ?? ''}'
                .trim(),
        'farm_name': lot['farm_name'],
        'product_id': lot['product_id'],
        'quantity': quantity,
        'unit_price': price,
        'currency_code': customer['preferred_currency_code'],
        'hs_code_snapshot': lot['hs_code'] as String?,
      });
    }

    for (final lotId in {...oldQuantities.keys, ...newQuantities.keys}) {
      final difference =
          (newQuantities[lotId] ?? 0) - (oldQuantities[lotId] ?? 0);
      if (difference > 0 && inventory.available(lotId) < difference) {
        throw const LocalOrderError(
          'lines',
          'No hay existencias suficientes para uno de los lotes.',
        );
      }
    }
    for (final lotId in {...oldQuantities.keys, ...newQuantities.keys}) {
      final difference =
          (oldQuantities[lotId] ?? 0) - (newQuantities[lotId] ?? 0);
      if (difference != 0) inventory.applyOrderEdit(lotId, difference);
    }

    for (final line in replacement) {
      final lineId = _nextLineId++;
      line['id'] = lineId;
      line['order_line_id'] = lineId;
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    order
      ..['customer_id'] = customerId
      ..['customer_name'] = customer['name']
      ..['currency_code'] = customer['preferred_currency_code']
      ..['note'] = note is String && note.trim().isNotEmpty ? note.trim() : null
      ..['lines'] = replacement
      ..['line_count'] = replacement.length
      ..['order_total'] = replacement.fold<num>(
        0,
        (sum, line) =>
            sum + (line['quantity'] as num) * (line['unit_price'] as num),
      )
      ..['updated_at'] = updatedAt;
    return Map<String, Object?>.from(order);
  }

  Map<String, Object?> transition(int id, Map<String, dynamic>? body) {
    if (body == null ||
        body.keys.any((key) => !{'status', 'note'}.contains(key))) {
      throw const LocalOrderError('body', 'La solicitud no es válida.');
    }
    final order = _orders.where((item) => item['id'] == id).firstOrNull;
    if (order == null) {
      throw const LocalOrderError('order_id', 'El pedido no existe.');
    }
    final target = body['status'];
    final note = body['note'];
    if (target is! String || !{'confirmed', 'cancelled'}.contains(target)) {
      throw const LocalOrderError(
        'status',
        'El estado solicitado no es válido.',
      );
    }
    if (note != null && (note is! String || note.length > 500)) {
      throw const LocalOrderError(
        'note',
        'La nota admite hasta 500 caracteres.',
      );
    }
    final current = order['status'];
    if (current == target ||
        current == 'cancelled' ||
        (current == 'confirmed' && target != 'cancelled')) {
      throw const LocalOrderError(
        'status',
        'La transición de estado no está permitida.',
      );
    }
    final changedAt = DateTime.now().toUtc().toIso8601String();
    final history =
        List<Map<String, Object?>>.from(order['status_history']! as List)..add({
          'from_status': current,
          'to_status': target,
          'note': note is String && note.trim().isNotEmpty ? note.trim() : null,
          'changed_at': changedAt,
        });
    order['status'] = target;
    order['status_history'] = history;
    order['updated_at'] = changedAt;
    if (target == 'cancelled') {
      for (final line in order['lines']! as List) {
        final item = line as Map;
        inventory.restore(
          item['product_lot_id'] as int,
          item['quantity'] as num,
        );
      }
    }
    return Map<String, Object?>.from(order);
  }
}
