import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

typedef LoadLots =
    Future<Object?> Function({
      required int limit,
      required int offset,
      String? query,
    });

/// Lotes registrados, con el origen (finca y geolocalización) de cada uno.
class LotListScreen extends StatefulWidget {
  const LotListScreen({
    super.key,
    required this.loadLots,
    required this.loadPermissions,
    this.openForm,
    this.openOrigin,
  });

  /// Abre el origen del lote en el mapa. Por defecto navega con `go_router`.
  final void Function(Map<String, dynamic> lot)? openOrigin;

  final LoadLots loadLots;
  final Future<Set<String>> Function() loadPermissions;

  /// Abre el formulario y devuelve verdadero si se registró un lote. Por
  /// defecto navega con `go_router`.
  final Future<bool> Function()? openForm;

  @override
  State<LotListScreen> createState() => _LotListScreenState();
}

class _LotListScreenState extends State<LotListScreen> {
  static const _pageSize = 20;

  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  Set<String> _permissions = const {};
  int _total = 0;
  int _offset = 0;
  int _version = 0;
  bool _loading = false;
  String? _error;

  bool get _canCreate => _permissions.contains('lots.create');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadContext();
      _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    try {
      final permissions = await widget.loadPermissions();
      if (mounted) setState(() => _permissions = permissions);
    } catch (_) {
      // Sin esto la pantalla sigue funcionando en modo solo lectura.
    }
  }

  Future<void> _load() async {
    final version = ++_version;
    final query = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.loadLots(
        limit: _pageSize,
        offset: _offset,
        query: query.isEmpty ? null : query,
      );
      if (response is! Map ||
          response['items'] is! List ||
          response['pagination'] is! Map) {
        throw const FormatException('Invalid lots response');
      }
      final total = (response['pagination'] as Map)['total'];
      if (total is! int) throw const FormatException('Invalid pagination');
      final items = [
        for (final item in response['items'] as List)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      if (!mounted || version != _version) return;
      setState(() {
        _items = items;
        _total = total;
      });
    } on ApiException catch (error) {
      if (mounted && version == _version) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && version == _version) {
        setState(() => _error = 'No fue posible cargar los lotes.');
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  Future<void> _openForm() async {
    final router = GoRouter.of(context);
    final saved = widget.openForm != null
        ? await widget.openForm!()
        : (await router.push<bool>('/lots/new')) ?? false;
    if (!mounted || !saved) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Lote registrado.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Lotes'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a inicio',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        if (_canCreate)
          IconButton(
            tooltip: 'Registrar lote',
            onPressed: _openForm,
            icon: const Icon(Icons.add_rounded),
          ),
        IconButton(
          tooltip: 'Actualizar lotes',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () {
                      _offset = 0;
                      _load();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar por código de lote',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(minHeight: 2),
                ] else
                  const SizedBox(height: 16),
                if (_error != null)
                  _buildError()
                else if (!_loading && _items.isEmpty)
                  _buildEmpty()
                else
                  for (final lot in _items)
                    _LotCard(
                      lot: lot,
                      onOrigin: () => widget.openOrigin != null
                          ? widget.openOrigin!(lot)
                          : GoRouter.of(
                              context,
                            ).push('/lots/origin', extra: lot),
                    ),
                if (_error == null && _total > 0) _buildPagination(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildEmpty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Column(
      children: [
        const Icon(Icons.layers_outlined, size: 38, color: Color(0xFF7C8981)),
        const SizedBox(height: 12),
        Text(
          _search.text.trim().isNotEmpty
              ? 'No se encontraron lotes con ese código'
              : 'Aún no hay lotes registrados',
          style: const TextStyle(
            color: Color(0xFF34453E),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _buildError() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 54),
    child: Column(
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 36,
          color: Color(0xFF9B3D2D),
        ),
        const SizedBox(height: 12),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF84382C)),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );

  Widget _buildPagination() {
    final first = _offset + 1;
    final last = (_offset + _items.length).clamp(0, _total);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mostrando $first–$last de $_total',
              style: const TextStyle(color: Color(0xFF68736E), fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Página anterior',
            onPressed: _offset == 0 || _loading
                ? null
                : () {
                    setState(
                      () => _offset = (_offset - _pageSize).clamp(0, _total),
                    );
                    _load();
                  },
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            onPressed: _offset + _items.length >= _total || _loading
                ? null
                : () {
                    setState(() => _offset += _pageSize);
                    _load();
                  },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _LotCard extends StatelessWidget {
  const _LotCard({required this.lot, required this.onOrigin});

  final Map<String, dynamic> lot;
  final VoidCallback onOrigin;

  @override
  Widget build(BuildContext context) {
    final lat = lot['latitude'];
    final lon = lot['longitude'];
    final point = lat is num && lon is num
        ? '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
        : 'Finca sin geolocalización';
    final isCoffee = lot['product_type'] == 'coffee';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E3DC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDE8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isCoffee ? Icons.coffee_outlined : Icons.cookie_outlined,
              color: const Color(0xFF35574A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${lot['lot_code'] ?? ''}',
                  style: const TextStyle(
                    color: Color(0xFF253C33),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${lot['product_variety'] ?? ''} · ${lot['product_quality'] ?? ''}'
                  '  ·  ${lot['farm_name'] ?? ''} (${lot['supplier_name'] ?? ''})',
                  style: const TextStyle(
                    color: Color(0xFF68736E),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  point,
                  style: const TextStyle(
                    color: Color(0xFF35574A),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Ver origen en el mapa',
            onPressed: lat is num && lon is num ? onOrigin : null,
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
    );
  }
}

typedef SaveLot = Future<void> Function(Map<String, Object?> fields);

/// Registro de un lote: producto, finca de origen y código. La geolocalización
/// del lote es la de su finca.
class LotFormScreen extends StatefulWidget {
  const LotFormScreen({
    super.key,
    required this.loadFarms,
    required this.loadProducts,
    required this.onSave,
  });

  final Future<List<Map<String, dynamic>>> Function() loadFarms;
  final Future<List<Map<String, dynamic>>> Function() loadProducts;
  final SaveLot onSave;

  @override
  State<LotFormScreen> createState() => _LotFormScreenState();
}

class _LotFormScreenState extends State<LotFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  int? _productId;
  int? _farmId;
  List<Map<String, dynamic>> _farms = const [];
  List<Map<String, dynamic>> _products = const [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.loadFarms(),
        widget.loadProducts(),
      ]);
      if (!mounted) return;
      setState(() {
        _farms = results[0];
        _products = results[1];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError = 'No fue posible cargar fincas y productos.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _selectedFarm =>
      _farms.where((f) => f['id'] == _farmId).firstOrNull;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'product_id': _productId,
        'farm_id': _farmId,
        'lot_code': _code.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
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
          _error = 'No fue posible registrar el lote.';
          _saving = false;
        });
      }
    }
  }

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Registrar lote'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a lotes',
        onPressed: _saving
            ? null
            : () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop(false);
                } else {
                  context.go('/lots');
                }
              },
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadOptions,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : _buildForm(),
    ),
  );

  Widget _buildForm() {
    final farm = _selectedFarm;
    final lat = farm?['latitude'];
    final lon = farm?['longitude'];
    final origin = farm == null
        ? null
        : lat is num && lon is num
        ? 'Geolocalización del lote (la de su finca): '
              '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
        : 'La finca no tiene geolocalización registrada.';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _farmId,
                  decoration: _decoration('Finca de origen'),
                  items: [
                    for (final f in _farms)
                      if (f['id'] is int)
                        DropdownMenuItem<int>(
                          value: f['id'] as int,
                          child: Text(
                            '${f['name']} · ${f['supplier_name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _farmId = value),
                  validator: (v) =>
                      v == null ? 'La finca es obligatoria.' : null,
                ),
                if (origin != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      origin,
                      style: const TextStyle(
                        color: Color(0xFF68736E),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _productId,
                  decoration: _decoration('Producto'),
                  items: [
                    for (final p in _products)
                      if (p['id'] is int)
                        DropdownMenuItem<int>(
                          value: p['id'] as int,
                          child: Text(
                            '${p['variety']} · ${p['quality_grade']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _productId = value),
                  validator: (v) =>
                      v == null ? 'El producto es obligatorio.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _code,
                  enabled: !_saving,
                  decoration: _decoration(
                    'Código del lote',
                    helper: 'Único dentro de la finca.',
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'El código del lote es obligatorio.';
                    }
                    return text.length > 80 ? 'Máximo 80 caracteres.' : null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF84382C)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
