import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_exception.dart';

/// Historial de exportaciones (PLAT-577): lista con búsqueda y filtro por estado.
class ExportHistoryScreen extends StatefulWidget {
  const ExportHistoryScreen({
    super.key,
    required this.loadExports,
    this.onOpenEudr,
    this.onOpenDossier,
    this.onGenerateDocument,
  });

  /// Abre el expediente documental de una exportación (PLAT-603).
  final void Function(int exportId)? onOpenDossier;

  /// Abre la declaración EUDR de una exportación (PLAT-573).
  final void Function(int exportId)? onOpenEudr;

  /// Genera el PDF de la exportación y devuelve la URL de descarga (PLAT-579).
  final Future<String?> Function(int exportId)? onGenerateDocument;

  final Future<List<Map<String, dynamic>>> Function({
    String? query,
    String? status,
  })
  loadExports;

  @override
  State<ExportHistoryScreen> createState() => _ExportHistoryScreenState();
}

class _ExportHistoryScreenState extends State<ExportHistoryScreen> {
  static const _statusLabels = {
    'draft': 'Borrador',
    'formalized': 'Formalizada',
    'cancelled': 'Cancelada',
  };

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
      final rows = await widget.loadExports(
        query: text.isEmpty ? null : text,
        status: _status,
      );
      if (mounted) setState(() => _items = rows);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo cargar el historial de exportaciones.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate(int exportId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await widget.onGenerateDocument!(exportId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Documento generado'),
          content: SelectableText(
            url == null
                ? 'El PDF se guardó en el expediente de la exportación.'
                : 'Descarga el PDF (el enlace caduca en 1 hora):\n$url',
          ),
          actions: [
            if (url != null)
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                child: const Text('Copiar enlace'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo generar el documento.')),
      );
    }
  }

  String _subtitle(Map<String, dynamic> item) {
    final parts = <String>[
      '${item['customer_name'] ?? ''}',
      'Destino ${item['destination_country_code'] ?? '-'}',
      '${item['export_date'] ?? ''}',
      '${item['line_count'] ?? 0} líneas',
    ];
    final docs = item['document_count'];
    if (docs is int) parts.add('$docs documentos');
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Historial de exportaciones')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Buscar pedido, cliente o país',
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
              for (final entry in _statusLabels.entries)
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
              ? const Center(child: Text('No hay exportaciones registradas.'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      title: Text(
                        'Exportación #${item['id']} · Pedido ${item['order_number'] ?? ''}',
                      ),
                      subtitle: Text(_subtitle(item)),
                      trailing: Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (widget.onOpenEudr != null)
                            IconButton(
                              tooltip: 'Declaración EUDR',
                              icon: const Icon(Icons.eco_outlined),
                              onPressed: () =>
                                  widget.onOpenEudr!(item['id'] as int),
                            ),
                          if (widget.onOpenDossier != null)
                            IconButton(
                              tooltip: 'Expediente de documentos',
                              icon: const Icon(Icons.folder_open_outlined),
                              onPressed: () =>
                                  widget.onOpenDossier!(item['id'] as int),
                            ),
                          if (widget.onGenerateDocument != null)
                            IconButton(
                              tooltip: 'Generar PDF',
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              onPressed: () => _generate(item['id'] as int),
                            ),
                          Chip(
                            label: Text(
                              _statusLabels['${item['status']}'] ??
                                  '${item['status'] ?? ''}',
                            ),
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
