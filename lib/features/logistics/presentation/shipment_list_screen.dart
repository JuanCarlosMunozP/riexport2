import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../shipment_status.dart';

/// Envíos (PLAT-632–636, 641–643): búsqueda, filtro por estado y acciones para
/// actualizar el estado, editar el transporte y abrir línea de tiempo o mapa.
class ShipmentListScreen extends StatefulWidget {
  const ShipmentListScreen({
    super.key,
    required this.loadShipments,
    this.updateStatus,
    this.onCreate,
    this.onEdit,
    this.onOpenTimeline,
    this.onOpenMap,
  });

  final Future<List<Map<String, dynamic>>> Function({
    String? query,
    String? status,
  })
  loadShipments;

  /// Cambia el estado (`logistics.update`). Null si no tiene permiso.
  final Future<void> Function(int shipmentId, Map<String, dynamic> change)?
  updateStatus;
  final VoidCallback? onCreate;
  final void Function(Map<String, dynamic> shipment)? onEdit;
  final void Function(int shipmentId)? onOpenTimeline;
  final void Function(int shipmentId)? onOpenMap;

  @override
  State<ShipmentListScreen> createState() => _ShipmentListScreenState();
}

class _ShipmentListScreenState extends State<ShipmentListScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  String? _status;
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
    final text = _search.text.trim();
    try {
      final rows = await widget.loadShipments(
        query: text.isEmpty ? null : text,
        status: _status,
      );
      if (mounted) setState(() => _items = rows);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los envíos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> shipment) async {
    final options = shipmentTransitions['${shipment['status']}'] ?? const [];
    if (options.isEmpty) return;
    final change = await showShipmentStatusDialog(
      context,
      options: options,
      title:
          'Estado del envío ${shipment['tracking_number'] ?? '#${shipment['id']}'}',
    );
    if (change == null) return;
    try {
      await widget.updateStatus!(shipment['id'] as int, change);
      await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo actualizar el estado.');
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _subtitle(Map<String, dynamic> item) {
    final mode = item['transport_mode'];
    final eta = item['estimated_delivery_at'];
    return [
      '${item['customer_name'] ?? ''}',
      '${item['carrier'] ?? ''}',
      if (mode != null) transportModeLabels['$mode'] ?? '$mode',
      if (eta != null) 'ETA $eta',
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Envíos')),
    floatingActionButton: widget.onCreate == null
        ? null
        : FloatingActionButton.extended(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo envío'),
          ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Buscar pedido, cliente o guía',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: _load,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String?>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Estado'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              for (final entry in shipmentStatusLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              _status = value;
              _load();
            },
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
          child: _items.isEmpty && !_loading && _error == null
              ? const Center(child: Text('No hay envíos registrados.'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final id = item['id'] as int;
                    final canChange =
                        widget.updateStatus != null &&
                        (shipmentTransitions['${item['status']}'] ?? const [])
                            .isNotEmpty;
                    return ListTile(
                      title: Text(
                        '${item['tracking_number'] ?? 'Envío #$id'} · Pedido ${item['order_number'] ?? ''}',
                      ),
                      subtitle: Text(_subtitle(item)),
                      onTap: widget.onOpenTimeline == null
                          ? null
                          : () => widget.onOpenTimeline!(id),
                      trailing: Wrap(
                        spacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(shipmentStatusLabel(item['status'])),
                          ),
                          if (canChange)
                            IconButton(
                              tooltip: 'Actualizar estado',
                              icon: const Icon(Icons.update),
                              onPressed: () => _changeStatus(item),
                            ),
                          if (widget.onEdit != null)
                            IconButton(
                              tooltip: 'Editar transporte',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => widget.onEdit!(item),
                            ),
                          if (widget.onOpenMap != null)
                            IconButton(
                              tooltip: 'Ver trazabilidad en el mapa',
                              onPressed: () => widget.onOpenMap!(id),
                              icon: const Icon(Icons.map_outlined),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

/// Diálogo para elegir el nuevo estado de un envío, con ubicación y nota opcionales.
/// Devuelve el cuerpo de `POST /shipments/:id/status` o null si se cancela.
Future<Map<String, dynamic>?> showShipmentStatusDialog(
  BuildContext context, {
  required List<String> options,
  required String title,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _StatusDialog(options: options, title: title),
);

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.options, required this.title});

  final List<String> options;
  final String title;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  final _location = TextEditingController();
  final _description = TextEditingController();
  late String _selected = widget.options.first;

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('new-status'),
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Nuevo estado'),
            items: [
              for (final code in widget.options)
                DropdownMenuItem(
                  value: code,
                  child: Text(shipmentStatusLabel(code)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _selected = value ?? _selected),
          ),
          TextField(
            controller: _location,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: 'Ubicación (opcional)',
            ),
          ),
          TextField(
            controller: _description,
            maxLength: 1000,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'status': _selected,
          if (_location.text.trim().isNotEmpty)
            'location': _location.text.trim(),
          if (_description.text.trim().isNotEmpty)
            'description': _description.text.trim(),
        }),
        child: const Text('Actualizar'),
      ),
    ],
  );
}
