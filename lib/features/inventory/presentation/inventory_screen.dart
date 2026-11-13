import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.loadInventory,
    required this.adjustInventory,
    required this.canAdjust,
    this.loadOverview,
  });

  /// Inventario consolidado por producto con la bandera de stock bajo (PLAT-608/617).
  final Future<List<Map<String, dynamic>>> Function()? loadOverview;

  final Future<List<Map<String, dynamic>>> Function(String? query)
  loadInventory;
  final Future<void> Function(int lotId, num delta) adjustInventory;
  final bool canAdjust;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _overview = const [];
  bool _byProduct = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.loadInventory(
        _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final overview = widget.loadOverview == null
          ? const <Map<String, dynamic>>[]
          : await widget.loadOverview!();
      if (mounted) {
        setState(() {
          _items = rows;
          _overview = overview;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el inventario.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _adjust(Map<String, dynamic> lot) async {
    var text = '';
    final delta = await showDialog<num>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ajustar ${lot['lot_code']}'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => text = value,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Cambio de existencias',
            helperText:
                'Usa un número positivo para sumar o negativo para restar.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = num.tryParse(text.trim().replaceAll(',', '.'));
              if (value != null && value != 0) Navigator.pop(context, value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (delta == null) return;
    try {
      await widget.adjustInventory(lot['id'] as int, delta);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo registrar el ajuste.')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _lowStock => [
    for (final row in _overview)
      if (row['is_low_stock'] == true) row,
  ];

  String _productName(Map<String, dynamic> row) =>
      '${row['product_type'] == 'cacao' ? 'Cacao' : 'Café'} ${row['variety'] ?? ''} (${row['quality_grade'] ?? ''})';

  Widget _lowStockChip(BuildContext context) => Chip(
    avatar: Icon(
      Icons.warning_amber_rounded,
      size: 18,
      color: Theme.of(context).colorScheme.error,
    ),
    label: const Text('Stock bajo'),
    visualDensity: VisualDensity.compact,
  );

  Widget _lotList(BuildContext context) {
    final lowIds = {for (final row in _lowStock) row['product_id']};
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          title: Text(
            '${item['lot_code'] ?? 'Lote'} · ${item['product_type'] ?? ''} ${item['product_variety'] ?? ''}'
                .trim(),
          ),
          subtitle: Text(
            '${item['farm_name'] ?? 'Finca sin nombre'} · ${item['supplier_name'] ?? 'Proveedor sin nombre'}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lowIds.contains(item['product_id'])) _lowStockChip(context),
              const SizedBox(width: 8),
              Text(
                '${item['available_quantity'] ?? 0}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.canAdjust)
                IconButton(
                  tooltip: 'Ajustar existencias',
                  onPressed: () => _adjust(item),
                  icon: const Icon(Icons.tune),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _productList(BuildContext context) => ListView.separated(
    itemCount: _overview.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, index) {
      final row = _overview[index];
      final threshold = row['low_stock_threshold'];
      return ListTile(
        title: Text(_productName(row)),
        subtitle: Text(
          '${row['lot_count'] ?? 0} lotes'
          '${threshold == null ? ' · sin umbral mínimo' : ' · umbral mínimo $threshold ${row['base_unit_code'] ?? ''}'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (row['is_low_stock'] == true) _lowStockChip(context),
            const SizedBox(width: 8),
            Text(
              '${row['available_quantity'] ?? 0} ${row['base_unit_code'] ?? ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final low = _lowStock;
    final showOverview = widget.loadOverview != null;
    final list = _byProduct ? _overview : _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: Column(
        children: [
          if (low.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Stock bajo en ${low.length} '
                '${low.length == 1 ? 'producto' : 'productos'}: '
                '${low.map(_productName).join(', ')}.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Buscar lote, producto o finca',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          if (showOverview)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Por lote')),
                  ButtonSegment(value: true, label: Text('Por producto')),
                ],
                selected: {_byProduct},
                onSelectionChanged: (value) =>
                    setState(() => _byProduct = value.first),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: list.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _byProduct
                          ? 'No hay productos para mostrar.'
                          : 'No hay lotes para mostrar.',
                    ),
                  )
                : _byProduct
                ? _productList(context)
                : _lotList(context),
          ),
        ],
      ),
    );
  }
}
