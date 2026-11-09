import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../shipment_status.dart';

/// Alta y edición de los datos de transporte de un envío (PLAT-641–643):
/// exportación, transportista, guía, modalidad, contenedor y fecha estimada.
class ShipmentFormScreen extends StatefulWidget {
  const ShipmentFormScreen({
    super.key,
    required this.onSubmit,
    this.loadExports,
    this.initial,
  });

  /// Cuerpo listo para `POST /shipments` o `PATCH /shipments/:id`.
  final Future<void> Function(Map<String, dynamic> body) onSubmit;

  /// Exportaciones disponibles (solo en el alta).
  final Future<List<Map<String, dynamic>>> Function()? loadExports;

  /// Envío existente: el formulario pasa a modo edición.
  final Map<String, dynamic>? initial;

  @override
  State<ShipmentFormScreen> createState() => _ShipmentFormScreenState();
}

class _ShipmentFormScreenState extends State<ShipmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _carrier = TextEditingController(
    text: '${widget.initial?['carrier'] ?? ''}',
  );
  late final _tracking = TextEditingController(
    text: '${widget.initial?['tracking_number'] ?? ''}',
  );
  late final _container = TextEditingController(
    text: '${widget.initial?['container_number'] ?? ''}',
  );
  late final _eta = TextEditingController(
    text: '${widget.initial?['estimated_delivery_at'] ?? ''}',
  );
  late String? _mode = widget.initial?['transport_mode'] as String?;
  List<Map<String, dynamic>> _exports = const [];
  int? _exportId;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    if (!_editing && widget.loadExports != null) _loadExports();
  }

  @override
  void dispose() {
    _carrier.dispose();
    _tracking.dispose();
    _container.dispose();
    _eta.dispose();
    super.dispose();
  }

  Future<void> _loadExports() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.loadExports!();
      if (mounted) {
        setState(() {
          _exports = rows;
          _exportId = rows.isEmpty ? null : rows.first['id'] as int?;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar las exportaciones.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _optionalLength(String? value, int max, String label) =>
      (value ?? '').trim().length > max
      ? '$label admite hasta $max caracteres.'
      : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_editing && _exportId == null) {
      setState(() => _error = 'Selecciona la exportación del envío.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? nullable(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final body = <String, dynamic>{
      if (!_editing) 'export_id': _exportId,
      'carrier': nullable(_carrier),
      'tracking_number': nullable(_tracking),
      'transport_mode': _mode,
      'container_number': nullable(_container),
      'estimated_delivery_at': nullable(_eta),
    };
    try {
      await widget.onSubmit(body);
      if (mounted) Navigator.of(context).maybePop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar el envío.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_editing ? 'Editar transporte' : 'Nuevo envío')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (!_editing)
            DropdownButtonFormField<int>(
              key: const ValueKey('shipment-export'),
              initialValue: _exportId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Exportación'),
              items: [
                for (final e in _exports)
                  DropdownMenuItem(
                    value: e['id'] as int,
                    child: Text(
                      '#${e['id']} · Pedido ${e['order_number'] ?? ''} · ${e['customer_name'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _exportId = value),
            ),
          TextFormField(
            controller: _carrier,
            decoration: const InputDecoration(labelText: 'Transportista'),
            validator: (v) => _optionalLength(v, 120, 'El transportista'),
          ),
          TextFormField(
            controller: _tracking,
            decoration: const InputDecoration(labelText: 'Guía / tracking'),
            validator: (v) => _optionalLength(v, 160, 'La guía'),
          ),
          DropdownButtonFormField<String?>(
            key: const ValueKey('shipment-mode'),
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Modalidad'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin definir')),
              for (final entry in transportModeLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _mode = value),
          ),
          TextFormField(
            controller: _container,
            decoration: const InputDecoration(labelText: 'Contenedor'),
            validator: (v) => _optionalLength(v, 40, 'El contenedor'),
          ),
          TextFormField(
            controller: _eta,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Entrega estimada (AAAA-MM-DD)',
            ),
            validator: (v) {
              final text = (v ?? '').trim();
              if (text.isEmpty) return null;
              return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
                      DateTime.tryParse(text) != null
                  ? null
                  : 'Usa el formato AAAA-MM-DD.';
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    ),
  );
}
