import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

class OrderRegistrationScreen extends StatefulWidget {
  const OrderRegistrationScreen({
    super.key,
    required this.loadCustomers,
    required this.loadLots,
    required this.onSave,
    this.existingOrder,
  });

  final Future<List<Map<String, dynamic>>> Function() loadCustomers;
  final Future<List<Map<String, dynamic>>> Function() loadLots;
  final Future<Object?> Function(Map<String, Object?> order) onSave;
  final Map<String, dynamic>? existingOrder;

  @override
  State<OrderRegistrationScreen> createState() =>
      _OrderRegistrationScreenState();
}

class _OrderRegistrationScreenState extends State<OrderRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unitPrice = TextEditingController();
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _lots = const [];
  final List<Map<String, Object?>> _lines = [];
  int? _customerId;
  int? _lotId;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _editingLineIndex;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _note.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final result = await Future.wait([
        widget.loadCustomers(),
        widget.loadLots(),
      ]);
      if (!mounted) return;
      setState(() {
        _customers = result[0];
        _lots = result[1];
        _customerId =
            widget.existingOrder?['customer_id'] as int? ??
            (_customers.isEmpty ? null : _customers.first['id'] as int);
        _lotId = _lots.isEmpty ? null : _lots.first['id'] as int;
        _note.text = '${widget.existingOrder?['note'] ?? ''}';
        final existingLines = widget.existingOrder?['lines'];
        if (existingLines is List) {
          _lines.addAll(
            existingLines.whereType<Map>().map(
              (line) => <String, Object?>{
                'product_lot_id': line['product_lot_id'],
                'quantity': line['quantity'],
                'unit_price': line['unit_price'],
              },
            ),
          );
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudieron cargar clientes y lotes.';
        });
      }
    }
  }

  Map<String, dynamic>? get _customer =>
      _customers.where((item) => item['id'] == _customerId).firstOrNull;

  Map<String, dynamic>? get _lot =>
      _lots.where((item) => item['id'] == _lotId).firstOrNull;

  num get _total => _lines.fold<num>(
    0,
    (sum, line) =>
        sum + (line['quantity'] as num) * (line['unit_price'] as num),
  );

  void _addLine() {
    final lot = _lot;
    final quantity = num.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    final price = num.tryParse(_unitPrice.text.trim().replaceAll(',', '.'));
    if (lot == null ||
        quantity == null ||
        !quantity.isFinite ||
        quantity <= 0 ||
        price == null ||
        !price.isFinite ||
        price < 0) {
      setState(
        () => _error = 'Selecciona un lote e indica cantidad y precio válidos.',
      );
      return;
    }
    if (_lines.asMap().entries.any(
      (entry) =>
          entry.key != _editingLineIndex &&
          entry.value['product_lot_id'] == lot['id'],
    )) {
      setState(() => _error = 'Ese lote ya está en el pedido.');
      return;
    }
    setState(() {
      _error = null;
      final line = <String, Object?>{
        'product_lot_id': lot['id'],
        'quantity': quantity,
        'unit_price': price,
      };
      if (_editingLineIndex == null) {
        _lines.add(line);
      } else {
        _lines[_editingLineIndex!] = line;
        _editingLineIndex = null;
      }
      _quantity.text = '1';
      _unitPrice.clear();
    });
  }

  void _editLine(int index) {
    final line = _lines[index];
    setState(() {
      _editingLineIndex = index;
      _lotId = line['product_lot_id'] as int;
      _quantity.text = '${line['quantity']}';
      _unitPrice.text = '${line['unit_price']}';
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      setState(() => _error = 'Agrega al menos una línea al pedido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = await widget.onSave({
        'customer_id': _customerId,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'lines': _lines,
      });
      if (mounted) {
        Navigator.of(context).pop(order ?? true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No fue posible registrar el pedido.';
          _saving = false;
        });
      }
    }
  }

  String _lotLabel(Map<String, dynamic> lot) =>
      '${lot['lot_code']} · ${lot['product_variety'] ?? 'Producto'} ${lot['product_quality'] ?? ''} (${lot['farm_name'] ?? 'Finca'})';

  Widget _lineTile(Map<String, Object?> line) {
    final index = _lines.indexOf(line);
    final lot = _lots
        .where((item) => item['id'] == line['product_lot_id'])
        .firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        lot == null ? 'Lote ${line['product_lot_id']}' : _lotLabel(lot),
      ),
      subtitle: Text(
        '${line['quantity']} × ${line['unit_price']} ${_customer?['preferred_currency_code'] ?? ''}',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Editar línea',
            onPressed: _saving ? null : () => _editLine(index),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Quitar línea',
            onPressed: _saving
                ? null
                : () => setState(() {
                    _lines.remove(line);
                    _editingLineIndex = null;
                  }),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: Text(
        widget.existingOrder == null ? 'Registrar pedido' : 'Editar pedido',
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _customerId,
                    decoration: const InputDecoration(
                      labelText: 'Cliente',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final customer in _customers.where(
                        (c) => c['is_active'] == true,
                      ))
                        DropdownMenuItem(
                          value: customer['id'] as int,
                          child: Text('${customer['name']}'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _customerId = value),
                    validator: (value) =>
                        value == null ? 'Selecciona un cliente activo.' : null,
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Moneda',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      '${_customer?['preferred_currency_code'] ?? '—'} (preferida del cliente)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Productos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _lotId,
                    decoration: const InputDecoration(
                      labelText: 'Lote de origen',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final lot in _lots)
                        DropdownMenuItem(
                          value: lot['id'] as int,
                          child: Text(
                            _lotLabel(lot),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _lotId = value),
                    validator: (value) =>
                        value == null ? 'No hay lotes disponibles.' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _quantity,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _unitPrice,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Precio unitario',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saving || _lots.isEmpty ? null : _addLine,
                      icon: Icon(
                        _editingLineIndex == null ? Icons.add : Icons.check,
                      ),
                      label: Text(
                        _editingLineIndex == null
                            ? 'Agregar línea'
                            : 'Actualizar línea',
                      ),
                    ),
                  ),
                  for (final line in _lines) _lineTile(line),
                  if (_lines.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total estimado: ${_total.toStringAsFixed(2)} ${_customer?['preferred_currency_code'] ?? ''}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    enabled: !_saving,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFF84382C)),
                      ),
                    ),
                  FilledButton(
                    key: const Key('order-submit'),
                    onPressed: _saving || _customers.isEmpty || _lots.isEmpty
                        ? null
                        : _submit,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.existingOrder == null
                                ? 'Registrar pedido'
                                : 'Guardar cambios',
                          ),
                  ),
                ],
              ),
            ),
          ),
  );
}
