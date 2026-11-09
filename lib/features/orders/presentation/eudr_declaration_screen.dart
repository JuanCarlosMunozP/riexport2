import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

/// Declaración de diligencia debida EUDR de una exportación (PLAT-573).
class EudrDeclarationScreen extends StatefulWidget {
  const EudrDeclarationScreen({
    super.key,
    required this.exportId,
    required this.loadDeclaration,
  });

  final int exportId;
  final Future<Map<String, dynamic>> Function(int exportId) loadDeclaration;

  @override
  State<EudrDeclarationScreen> createState() => _EudrDeclarationScreenState();
}

class _EudrDeclarationScreenState extends State<EudrDeclarationScreen> {
  Map<String, dynamic>? _declaration;
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
      final declaration = await widget.loadDeclaration(widget.exportId);
      if (mounted) setState(() => _declaration = declaration);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo generar la declaración EUDR.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _farms(Map<String, dynamic> declaration) {
    final farms = declaration['origin_farms'];
    return [
      if (farms is List)
        for (final farm in farms)
          if (farm is Map) Map<String, dynamic>.from(farm),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final declaration = _declaration;
    final scheme = Theme.of(context).colorScheme;
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    } else if (declaration == null) {
      body = const SizedBox.shrink();
    } else {
      final hs = declaration['hs_codes'];
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ValidityBanner(
            valid: declaration['traceability_valid'] == true,
            issues: [
              if (declaration['issues'] is List)
                for (final issue in declaration['issues'] as List) '$issue',
            ],
          ),
          const SizedBox(height: 16),
          _row('Fecha de declaración', declaration['declaration_date']),
          _row('País de destino', declaration['destination_country_code']),
          _row('Fecha de exportación', declaration['export_date']),
          _row('Líneas', declaration['line_count']),
          _row('Cantidad total', declaration['total_quantity']),
          _row('Proveedores', declaration['supplier_count']),
          _row('Fincas de origen', declaration['farm_count']),
          _row(
            'Códigos HS',
            hs is List && hs.isNotEmpty ? hs.join(', ') : 'N/D',
          ),
          const SizedBox(height: 16),
          Text(
            'Fincas de origen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final farm in _farms(declaration))
            Card(
              child: ListTile(
                leading: const Icon(Icons.agriculture_outlined),
                title: Text('${farm['farm_name'] ?? 'Finca'}'),
                subtitle: Text(
                  '${farm['supplier_name'] ?? ''} · ${farm['country_code'] ?? ''}\n'
                  '${farm['latitude'] ?? 'sin lat.'}, ${farm['longitude'] ?? 'sin long.'} · '
                  '${farm['total_quantity'] ?? 0} · ${farm['lot_count'] ?? 0} lote(s)',
                ),
                isThreeLine: true,
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Declaración EUDR · Exportación #${widget.exportId}'),
      ),
      body: body,
    );
  }

  Widget _row(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(
          flex: 3,
          child: Text('${value ?? '-'}', textAlign: TextAlign.end),
        ),
      ],
    ),
  );
}

class _ValidityBanner extends StatelessWidget {
  const _ValidityBanner({required this.valid, required this.issues});

  final bool valid;
  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: valid ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  valid
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    valid
                        ? 'Trazabilidad completa: todas las líneas llegan a una finca geolocalizada.'
                        : 'Trazabilidad incompleta: la declaración no es válida.',
                  ),
                ),
              ],
            ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Text('• $issue'),
              ),
          ],
        ),
      ),
    );
  }
}
