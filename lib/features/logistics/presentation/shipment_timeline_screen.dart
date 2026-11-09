import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../shipment_status.dart';
import 'shipment_list_screen.dart' show showShipmentStatusDialog;

/// Línea de tiempo de un envío (PLAT-636/639). La ven el personal logístico y el
/// cliente dueño del pedido; solo quien tiene `logistics.update` recibe las acciones.
class ShipmentTimelineScreen extends StatefulWidget {
  const ShipmentTimelineScreen({
    super.key,
    required this.shipmentId,
    required this.loadShipment,
    required this.loadEvents,
    this.updateStatus,
    this.addEvent,
  });

  final int shipmentId;
  final Future<Map<String, dynamic>> Function(int shipmentId) loadShipment;
  final Future<List<Map<String, dynamic>>> Function(int shipmentId) loadEvents;
  final Future<void> Function(int shipmentId, Map<String, dynamic> change)?
  updateStatus;
  final Future<void> Function(int shipmentId, Map<String, dynamic> event)?
  addEvent;

  @override
  State<ShipmentTimelineScreen> createState() => _ShipmentTimelineScreenState();
}

class _ShipmentTimelineScreenState extends State<ShipmentTimelineScreen> {
  Map<String, dynamic>? _shipment;
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shipment = await widget.loadShipment(widget.shipmentId);
      final events = await widget.loadEvents(widget.shipmentId);
      if (mounted) {
        setState(() {
          _shipment = shipment;
          _events = events;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error, stack) {
      debugPrint('Seguimiento del envío ${widget.shipmentId}: $error\n$stack');
      if (mounted) {
        setState(
          () => _error = kDebugMode
              ? 'No se pudo cargar el seguimiento del envío ($error).'
              : 'No se pudo cargar el seguimiento del envío.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
      await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message(failure);
    }
  }

  Future<void> _changeStatus() async {
    final options =
        shipmentTransitions['${_shipment?['status']}'] ?? const <String>[];
    if (options.isEmpty) return;
    final change = await showShipmentStatusDialog(
      context,
      options: options,
      title: 'Actualizar estado del envío',
    );
    if (change == null) return;
    await _run(
      () => widget.updateStatus!(widget.shipmentId, change),
      'No se pudo actualizar el estado.',
    );
  }

  Future<void> _addEvent() async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _EventDialog(),
    );
    if (body == null) return;
    await _run(
      () => widget.addEvent!(widget.shipmentId, body),
      'No se pudo registrar el evento.',
    );
  }

  String _eventTitle(Map<String, dynamic> event) {
    final type = '${event['event_type']}';
    return shipmentStatusLabels[type] ?? type;
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final canChange =
        widget.updateStatus != null &&
        (shipmentTransitions['${shipment?['status']}'] ?? const []).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Envío ${shipment?['tracking_number'] ?? '#${widget.shipmentId}'}',
        ),
        actions: [
          if (canChange)
            IconButton(
              tooltip: 'Actualizar estado',
              icon: const Icon(Icons.update),
              onPressed: _changeStatus,
            ),
          if (widget.addEvent != null)
            IconButton(
              tooltip: 'Registrar evento',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _addEvent,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (shipment != null) ...[
              Text(
                'Pedido ${shipment['order_number'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(
                      '${shipment['status_label'] ?? shipmentStatusLabel(shipment['status'])}',
                    ),
                  ),
                  if ('${shipment['carrier'] ?? ''}'.isNotEmpty)
                    Chip(label: Text('${shipment['carrier']}')),
                  if (shipment['transport_mode'] != null)
                    Chip(
                      label: Text(
                        transportModeLabels['${shipment['transport_mode']}'] ??
                            '${shipment['transport_mode']}',
                      ),
                    ),
                  if (shipment['estimated_delivery_at'] != null)
                    Chip(
                      label: Text('ETA ${shipment['estimated_delivery_at']}'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text('Historial', style: Theme.of(context).textTheme.titleMedium),
            if (_events.isEmpty && !_loading && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Todavía no hay eventos para este envío.'),
              ),
            for (var i = 0; i < _events.length; i++)
              _TimelineEntry(
                key: ValueKey('event-${_events[i]['id']}'),
                title: _eventTitle(_events[i]),
                lines: [
                  '${_events[i]['event_at'] ?? ''}'
                      .replaceFirst('T', ' ')
                      .split('.')
                      .first,
                  if ('${_events[i]['location'] ?? ''}'.isNotEmpty)
                    '${_events[i]['location']}',
                  if ('${_events[i]['description'] ?? ''}'.isNotEmpty)
                    '${_events[i]['description']}',
                ],
                isFirst: i == 0,
                isLast: i == _events.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    super.key,
    required this.title,
    required this.lines,
    required this.isFirst,
    required this.isLast,
  });

  final String title;
  final List<String> lines;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : color.withValues(alpha: 0.4),
                  ),
                ),
                Icon(
                  isFirst ? Icons.radio_button_checked : Icons.circle,
                  size: isFirst ? 18 : 10,
                  color: color,
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : color.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  for (final line in lines)
                    Text(line, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDialog extends StatefulWidget {
  const _EventDialog();

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _type = TextEditingController();
  final _location = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _type.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar evento'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _type,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Evento (p. ej. inspección, retraso)',
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Describe el tipo de evento.'
                  : null,
            ),
            TextField(
              controller: _location,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Ubicación (opcional)',
              ),
            ),
            TextField(
              controller: _note,
              maxLength: 1000,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Detalle (opcional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'event_type': _type.text.trim(),
            if (_location.text.trim().isNotEmpty)
              'location': _location.text.trim(),
            if (_note.text.trim().isNotEmpty) 'description': _note.text.trim(),
          });
        },
        child: const Text('Registrar'),
      ),
    ],
  );
}
