import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';

/// Archivo elegido por la persona usuaria para adjuntar al expediente.
class PickedDocument {
  const PickedDocument(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// Tamaño máximo de un adjunto (PLAT-601); la base y el bucket lo vuelven a exigir.
const maxDossierUploadBytes = 10 * 1024 * 1024;
const dossierUploadExtensions = ['pdf', 'png', 'jpg', 'jpeg'];

Future<PickedDocument?> _pickDocument() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: dossierUploadExtensions,
  );
  if (file == null) return null;
  return PickedDocument(file.name, await file.readAsBytes());
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('No se pudo abrir el enlace.');
  }
}

/// Expediente documental de una exportación (PLAT-603/604): qué documentos ya
/// existen, con su número y versión, y las acciones para emitir o adjuntar los
/// que faltan (factura, packing list, EUR.1 y certificado fitosanitario).
class ExportDossierScreen extends StatefulWidget {
  const ExportDossierScreen({
    super.key,
    required this.exportId,
    required this.loadDocuments,
    required this.downloadDocument,
    this.generateDocument,
    this.uploadDocument,
    this.pickFile = _pickDocument,
    this.openUrl = _openUrl,
  });

  final int exportId;
  final Future<List<Map<String, dynamic>>> Function(int exportId) loadDocuments;

  /// Devuelve la URL firmada de descarga de un documento del expediente.
  final Future<String?> Function(int documentId) downloadDocument;

  /// Emite un documento (`documents.generate`). Null si no tiene permiso.
  final Future<void> Function(int exportId, String documentType)?
  generateDocument;

  /// Adjunta un archivo (`documents.upload`). Null si no tiene permiso.
  final Future<void> Function(
    int exportId,
    String documentType,
    PickedDocument file,
  )?
  uploadDocument;

  final Future<PickedDocument?> Function() pickFile;
  final Future<void> Function(String url) openUrl;

  @override
  State<ExportDossierScreen> createState() => _ExportDossierScreenState();
}

class _ExportDossierScreenState extends State<ExportDossierScreen> {
  static const _required = <(String, String, bool)>[
    ('commercial_invoice', 'Factura comercial', true),
    ('packing_list', 'Packing list', true),
    ('eur1_certificate', 'Certificado de origen EUR.1', true),
    ('phytosanitary_certificate', 'Certificado fitosanitario', false),
  ];
  static const _otherLabels = {
    'export_summary': 'Resumen de exportación',
    'other_attachment': 'Otro adjunto',
  };

  List<Map<String, dynamic>> _documents = const [];
  bool _loading = true;
  String? _busyType;
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
      final rows = await widget.loadDocuments(widget.exportId);
      if (mounted) setState(() => _documents = rows);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el expediente.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Versión más reciente de cada tipo (la lista llega ordenada de nueva a antigua).
  Map<String, Map<String, dynamic>> get _latest {
    final latest = <String, Map<String, dynamic>>{};
    for (final doc in _documents) {
      final type = '${doc['document_type']}';
      final current = latest[type];
      if (current == null ||
          ((doc['version'] as num?) ?? 0) >
              ((current['version'] as num?) ?? 0)) {
        latest[type] = doc;
      }
    }
    return latest;
  }

  void _message(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guard(String type, Future<void> Function() action) async {
    setState(() => _busyType = type);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo completar la operación.');
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  Future<void> _generate(String type) => _guard(type, () async {
    await widget.generateDocument!(widget.exportId, type);
    await _load();
    if (mounted) _message('Documento emitido.');
  });

  Future<void> _upload(String type) => _guard(type, () async {
    final file = await widget.pickFile();
    if (file == null) return;
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    if (!dossierUploadExtensions.contains(extension)) {
      _message('Solo se aceptan archivos PDF, PNG o JPEG.');
      return;
    }
    if (file.bytes.isEmpty || file.bytes.length > maxDossierUploadBytes) {
      _message('El archivo debe pesar entre 1 byte y 10 MB.');
      return;
    }
    await widget.uploadDocument!(widget.exportId, type, file);
    await _load();
    if (mounted) _message('Archivo adjuntado al expediente.');
  });

  Future<void> _download(Map<String, dynamic> doc) async {
    try {
      final url = await widget.downloadDocument(doc['id'] as int);
      if (url == null || !mounted) return;
      try {
        await widget.openUrl(url);
      } catch (_) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Descargar documento'),
            content: SelectableText(
              'Copia este enlace (caduca en 1 hora):\n$url',
            ),
            actions: [
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
      }
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo obtener el documento.');
    }
  }

  String _describe(Map<String, dynamic> doc) {
    final parts = <String>[
      if ('${doc['document_number'] ?? ''}'.isNotEmpty)
        '${doc['document_number']}',
      'v${doc['version']}',
      '${doc['created_at'] ?? ''}'.split('T').first,
      if ('${doc['created_by_name'] ?? ''}'.isNotEmpty)
        '${doc['created_by_name']}',
    ];
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }

  Widget _requiredTile(
    BuildContext context,
    String type,
    String label,
    bool generated,
    Map<String, dynamic>? latest,
  ) {
    final busy = _busyType == type;
    final canAct = generated
        ? widget.generateDocument != null
        : widget.uploadDocument != null;
    return ListTile(
      key: ValueKey('dossier-$type'),
      leading: Icon(
        latest == null ? Icons.radio_button_unchecked : Icons.check_circle,
        color: latest == null ? null : Theme.of(context).colorScheme.primary,
      ),
      title: Text(label),
      subtitle: Text(latest == null ? 'Pendiente' : _describe(latest)),
      trailing: busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (latest != null)
                  IconButton(
                    tooltip: 'Descargar $label',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _download(latest),
                  ),
                if (canAct)
                  IconButton(
                    tooltip: generated
                        ? (latest == null
                              ? 'Emitir $label'
                              : 'Emitir nueva versión de $label')
                        : (latest == null
                              ? 'Adjuntar $label'
                              : 'Adjuntar nueva versión de $label'),
                    icon: Icon(
                      generated
                          ? Icons.picture_as_pdf_outlined
                          : Icons.upload_file_outlined,
                    ),
                    onPressed: () =>
                        generated ? _generate(type) : _upload(type),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    final others = [
      for (final doc in _documents)
        if (!_required.any((entry) => entry.$1 == doc['document_type'])) doc,
    ];
    final done = _required
        .where((entry) => latest.containsKey(entry.$1))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Expediente · exportación #${widget.exportId}'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Documentos requeridos: $done de ${_required.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final (type, label, generated) in _required)
              _requiredTile(context, type, label, generated, latest[type]),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Otros documentos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.generateDocument != null)
              ListTile(
                key: const ValueKey('dossier-export_summary'),
                leading: const Icon(Icons.summarize_outlined),
                title: const Text('Resumen de exportación'),
                subtitle: Text(
                  latest['export_summary'] == null
                      ? 'No emitido'
                      : 'Última: ${_describe(latest['export_summary']!)}',
                ),
                trailing: IconButton(
                  tooltip: 'Emitir resumen de exportación',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: _busyType == null
                      ? () => _generate('export_summary')
                      : null,
                ),
              ),
            if (widget.uploadDocument != null)
              ListTile(
                key: const ValueKey('dossier-other_attachment'),
                leading: const Icon(Icons.attach_file),
                title: const Text('Adjuntar otro documento'),
                subtitle: const Text('PDF, PNG o JPEG de hasta 10 MB'),
                trailing: IconButton(
                  tooltip: 'Adjuntar otro documento',
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: _busyType == null
                      ? () => _upload('other_attachment')
                      : null,
                ),
              ),
            for (final doc in others)
              ListTile(
                dense: true,
                title: Text(
                  _otherLabels['${doc['document_type']}'] ??
                      '${doc['document_type']}',
                ),
                subtitle: Text(
                  '${doc['original_name'] ?? ''} · ${_describe(doc)}',
                ),
                trailing: IconButton(
                  tooltip: 'Descargar',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _download(doc),
                ),
              ),
            if (!_loading && _documents.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('Esta exportación todavía no tiene documentos.'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
