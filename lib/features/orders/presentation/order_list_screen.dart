import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({
    super.key,
    required this.loadOrders,
    required this.transitionOrder,
    required this.canTransition,
    this.canEdit = false,
    this.onEditOrder,
  });

  final Future<List<Map<String, dynamic>>> Function({
    String? query,
    String? status,
  })
  loadOrders;
  final Future<void> Function(int id, String status) transitionOrder;
  final bool canTransition;
  final bool canEdit;
  final ValueChanged<Map<String, dynamic>>? onEditOrder;

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _status;
  bool _transitioning = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final orders = await widget.loadOrders(
        query: _query.trim().isEmpty ? null : _query.trim(),
        status: _status,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _orders = orders;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = 'No se pudieron cargar los pedidos.');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _transition(Map<String, dynamic> order, String status) async {
    if (_transitioning) return;
    setState(() => _transitioning = true);
    try {
      await widget.transitionOrder(order['id'] as int, status);
      if (!mounted) return;
      setState(() {
        order['status'] = status;
        _error = null;
      });
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cambiar el estado.');
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _requestTransition(
    Map<String, dynamic> order,
    String status,
  ) async {
    if (status == 'cancelled') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancelar pedido'),
          content: Text(
            '¿Confirmas la cancelación de ${order['order_number'] ?? 'este pedido'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar pedido'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _transition(order, status);
  }

  String _statusLabel(Object? status) => switch (status) {
    'draft' => 'Borrador',
    'confirmed' => 'Confirmado',
    'cancelled' => 'Cancelado',
    _ => 'Desconocido',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pedidos')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('orders-search'),
                  decoration: const InputDecoration(
                    labelText: 'Buscar pedido o cliente',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    _query = value;
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('orders-status-filter'),
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                    DropdownMenuItem(
                      value: 'confirmed',
                      child: Text('Confirmado'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelado'),
                    ),
                  ],
                  onChanged: (value) {
                    _status = value;
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_orders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No hay pedidos registrados.')),
                  ),
                for (final order in _orders)
                  Card(
                    child: ListTile(
                      title: Text('${order['order_number'] ?? 'Pedido'}'),
                      subtitle: Text(
                        [
                          if (order['customer_name'] != null)
                            '${order['customer_name']}',
                          '${order['created_at'] ?? ''}',
                          'Estado: ${_statusLabel(order['status'])}',
                          if (order['line_count'] != null)
                            'Líneas: ${order['line_count']}',
                          if (order['order_total'] != null)
                            'Total: ${order['order_total']} ${order['currency_code'] ?? ''}',
                          if (order['lines'] is List)
                            for (final line in order['lines'] as List)
                              if (line is Map)
                                '• ${line['lot_code'] ?? 'Lote'}: ${line['quantity']} × ${line['unit_price']}',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing:
                          ((widget.canEdit &&
                                      order['status'] == 'draft' &&
                                      widget.onEditOrder != null) ||
                                  (widget.canTransition &&
                                      order['status'] != 'cancelled')) &&
                              !_transitioning
                          ? PopupMenuButton<String>(
                              tooltip: 'Cambiar estado',
                              onSelected: (action) {
                                if (action == 'edit') {
                                  widget.onEditOrder?.call(order);
                                } else {
                                  _requestTransition(order, action);
                                }
                              },
                              itemBuilder: (_) => [
                                if (widget.canEdit &&
                                    order['status'] == 'draft' &&
                                    widget.onEditOrder != null)
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar pedido'),
                                  ),
                                if (widget.canTransition &&
                                    order['status'] == 'draft')
                                  const PopupMenuItem(
                                    value: 'confirmed',
                                    child: Text('Confirmar'),
                                  ),
                                if (widget.canTransition)
                                  const PopupMenuItem(
                                    value: 'cancelled',
                                    child: Text('Cancelar pedido'),
                                  ),
                              ],
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
  );
}
