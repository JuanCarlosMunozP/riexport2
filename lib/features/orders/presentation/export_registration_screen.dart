import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

class ExportRegistrationScreen extends StatefulWidget {
  const ExportRegistrationScreen({
    super.key,
    required this.loadOrders,
    required this.loadDestinations,
    required this.loadIncoterms,
    required this.onSave,
  });

  final Future<List<Map<String, dynamic>>> Function() loadOrders;
  final Future<List<Map<String, dynamic>>> Function() loadDestinations;
  final Future<List<Map<String, dynamic>>> Function() loadIncoterms;
  final Future<Object?> Function(Map<String, Object?> export) onSave;

  @override
  State<ExportRegistrationScreen> createState() =>
      _ExportRegistrationScreenState();
}

class _ExportRegistrationScreenState extends State<ExportRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityControllers = <int, TextEditingController>{};
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _destinations = const [];
  List<Map<String, dynamic>> _incoterms = const [];
  int? _orderId;
  String? _destinationCode;
  String? _incotermCode;
  DateTime _exportDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final result = await Future.wait([
        widget.loadOrders(),
        widget.loadDestinations(),
        widget.loadIncoterms(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = result[0];
        _destinations = result[1];
        _incoterms = result[2];
        _orderId = _orders.isEmpty ? null : _orders.first['id'] as int;
        _destinationCode = _destinations.isEmpty
            ? null
            : _destinations.first['code'] as String;
        _setOrderLines();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is ApiException
              ? error.message
              : 'No se pudieron cargar pedidos y catálogos de exportación.';
        });
      }
    }
  }

  Map<String, dynamic>? get _order =>
      _orders.where((item) => item['id'] == _orderId).firstOrNull;

  void _setOrderLines() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    final lines = _order?['lines'];
    if (lines is! List) return;
    for (final line in lines.whereType<Map>()) {
      final id = line['order_line_id'] ?? line['id'];
      if (id is! int) continue;
      final remaining =
          line['remaining_quantity'] as num? ?? line['quantity'] as num? ?? 0;
      if (remaining > 0) {
        _quantityControllers[id] = TextEditingController(text: '$remaining');
      }
    }
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _exportDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => _exportDate = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final order = _order;
    if (order == null) {
      setState(() => _error = 'Selecciona un pedido confirmado.');
      return;
    }
    final sourceLines = (order['lines'] as List).whereType<Map>();
    final lines = <Map<String, Object?>>[];
    for (final source in sourceLines) {
      final lineId = source['order_line_id'] ?? source['id'];
      if (lineId is! int) continue;
      final controller = _quantityControllers[lineId];
      if (controller == null) continue;
      final quantity = num.tryParse(
        controller.text.trim().replaceAll(',', '.'),
      );
      final remaining =
          source['remaining_quantity'] as num? ??
          source['quantity'] as num? ??
          0;
      if (quantity == null ||
          !quantity.isFinite ||
          quantity <= 0 ||
          quantity > remaining) {
        setState(
          () => _error =
              'Cada cantidad debe ser positiva y no superar el saldo disponible.',
        );
        return;
      }
      lines.add({'order_line_id': lineId, 'quantity': quantity});
    }
    if (lines.isEmpty) {
      setState(() => _error = 'El pedido no tiene cantidades disponibles.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final date = DateTime(
        _exportDate.year,
        _exportDate.month,
        _exportDate.day,
      );
      final result = await widget.onSave({
        'order_id': _orderId,
        'destination_country_code': _destinationCode,
        'incoterm_code': _incotermCode,
        'export_date': date.toIso8601String().substring(0, 10),
        'lines': lines,
      });
      if (mounted) {
        Navigator.of(context).pop(result ?? true);
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
          _error = 'No fue posible registrar la exportación.';
          _saving = false;
        });
      }
    }
  }

  String _dateLabel(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Registrar exportación')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DropdownButtonFormField<int>(
                  key: const Key('export-order'),
                  initialValue: _orderId,
                  decoration: const InputDecoration(
                    labelText: 'Pedido confirmado',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final order in _orders)
                      DropdownMenuItem<int>(
                        value: order['id'] as int,
                        child: Text(
                          '${order['order_number']} · ${order['customer_name'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _orderId = value;
                          _setOrderLines();
                        }),
                  validator: (value) =>
                      value == null ? 'Selecciona un pedido.' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('export-destination'),
                  initialValue: _destinationCode,
                  decoration: const InputDecoration(
                    labelText: 'País de destino',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final destination in _destinations)
                      DropdownMenuItem(
                        value: destination['code'] as String,
                        child: Text('${destination['name']}'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _destinationCode = value),
                  validator: (value) =>
                      value == null ? 'Selecciona un país de destino.' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('export-incoterm'),
                  initialValue: _incotermCode,
                  decoration: const InputDecoration(
                    labelText: 'Incoterm (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin especificar'),
                    ),
                    for (final item in _incoterms)
                      DropdownMenuItem(
                        value: item['code'] as String,
                        child: Text('${item['code']} · ${item['name']}'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _incotermCode = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _selectDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    'Fecha de exportación: ${_dateLabel(_exportDate)}',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Líneas y cantidades',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_quantityControllers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('El pedido no tiene cantidades disponibles.'),
                  ),
                for (final source
                    in (_order?['lines'] as List? ?? const []).whereType<Map>())
                  if (_quantityControllers.containsKey(
                    source['order_line_id'] ?? source['id'],
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        key: Key(
                          'export-quantity-${source['order_line_id'] ?? source['id']}',
                        ),
                        controller:
                            _quantityControllers[source['order_line_id'] ??
                                source['id']],
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${source['lot_code'] ?? 'Línea'} · HS ${source['hs_code_snapshot'] ?? source['hs_code'] ?? 'N/D'} · disponible ${source['remaining_quantity'] ?? source['quantity']}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('export-submit'),
                  onPressed:
                      _saving ||
                          _orders.isEmpty ||
                          _destinations.isEmpty ||
                          _quantityControllers.isEmpty
                      ? null
                      : _submit,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Registrar exportación'),
                ),
              ],
            ),
          ),
  );
}
