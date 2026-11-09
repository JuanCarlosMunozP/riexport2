import 'local_backend_store.dart';
import 'local_origin_store.dart';
import 'local_products_store.dart';

/// Movimientos y existencias en memoria para el backend local.
class LocalInventoryStore {
  LocalInventoryStore(this.origin, this.products);

  final LocalOriginStore origin;
  final LocalProductsStore products;
  final Map<int, num> _balances = {};
  final List<Map<String, Object?>> _movements = [];

  num available(int lotId) => _balances[lotId] ?? 0;

  Map<String, Object?> list(Map<String, String> query) {
    final lots = origin.listLots({...query, 'limit': '100', 'offset': '0'});
    final items = (lots['items'] as List).cast<Map<String, Object?>>();
    final q = (query['q'] ?? '').trim().toLowerCase();
    final rows = items
        .where(
          (lot) =>
              q.isEmpty ||
              '${lot['lot_code']} ${lot['product_type']} ${lot['farm_name']}'
                  .toLowerCase()
                  .contains(q),
        )
        .map(
          (lot) => {...lot, 'available_quantity': available(lot['id'] as int)},
        )
        .toList();
    return {
      'items': rows,
      'pagination': {'total': rows.length, 'limit': rows.length, 'offset': 0},
    };
  }

  /// Existencias por producto y bandera de stock bajo (`inventory_overview`).
  Map<String, Object?> overview(Map<String, String> query) {
    final lots =
        (origin.listLots({'limit': '100', 'offset': '0'})['items'] as List)
            .cast<Map<String, Object?>>();
    final rows = <Map<String, Object?>>[];
    for (final product in products.activeStockInfo()) {
      final mine = lots.where(
        (lot) => lot['product_id'] == product['product_id'],
      );
      final total = mine.fold<num>(
        0,
        (sum, lot) => sum + available(lot['id'] as int),
      );
      final threshold = product['low_stock_threshold'] as num?;
      rows.add({
        ...product,
        'lot_count': mine.length,
        'available_quantity': total,
        'is_low_stock': threshold != null && total <= threshold,
      });
    }
    if (query['low_stock'] == 'true') {
      rows.removeWhere((row) => row['is_low_stock'] != true);
    }
    rows.sort((a, b) {
      final low =
          (b['is_low_stock'] == true ? 1 : 0) -
          (a['is_low_stock'] == true ? 1 : 0);
      return low != 0 ? low : '${a['variety']}'.compareTo('${b['variety']}');
    });
    return {
      'items': rows,
      'pagination': {'total': rows.length, 'limit': rows.length, 'offset': 0},
    };
  }

  List<Map<String, Object?>> get movements =>
      _movements.map(Map<String, Object?>.from).toList();

  Map<String, Object?> adjust(Map<String, dynamic>? body) {
    if (body == null ||
        body.keys.any(
          (k) => !{'product_lot_id', 'quantity_delta'}.contains(k),
        )) {
      throw LocalBackendError.validation('body', 'La solicitud no es válida.');
    }
    final lotId = body['product_lot_id'];
    final delta = body['quantity_delta'];
    if (lotId is! int || delta is! num || !delta.isFinite || delta == 0) {
      throw LocalBackendError.validation(
        'quantity_delta',
        'Indica un lote y un ajuste numérico distinto de cero.',
      );
    }
    origin.getLot(lotId);
    if (available(lotId) + delta < 0) {
      throw LocalBackendError.validation(
        'quantity_delta',
        'El ajuste no puede dejar existencias negativas.',
      );
    }
    _apply(lotId, delta, 'adjustment');
    return {
      'product_lot_id': lotId,
      'quantity_delta': delta,
      'available_quantity': available(lotId),
    };
  }

  void consume(int lotId, num quantity) {
    if (available(lotId) < quantity) {
      throw const LocalBackendError(
        409,
        'INSUFFICIENT_INVENTORY',
        'No hay existencias suficientes para el lote solicitado.',
      );
    }
    _apply(lotId, -quantity, 'order');
  }

  void restore(int lotId, num quantity) =>
      _apply(lotId, quantity, 'adjustment');

  void applyOrderEdit(int lotId, num delta) {
    if (available(lotId) + delta < 0) {
      throw const LocalBackendError(
        409,
        'INSUFFICIENT_INVENTORY',
        'No hay existencias suficientes para el lote solicitado.',
      );
    }
    _apply(lotId, delta, 'order_edit');
  }

  void _apply(int lotId, num delta, String type) {
    _balances[lotId] = available(lotId) + delta;
    _movements.add({
      'product_lot_id': lotId,
      'quantity_delta': delta,
      'movement_type': type,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
