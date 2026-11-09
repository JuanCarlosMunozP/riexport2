import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

typedef LoadSuppliers =
    Future<Object?> Function({
      required int limit,
      required int offset,
      String? query,
      bool? isActive,
    });

/// Proveedores: consulta, registro, edición e inactivación.
class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({
    super.key,
    required this.loadSuppliers,
    required this.loadPermissions,
    this.setActive,
    this.openForm,
  });

  final LoadSuppliers loadSuppliers;

  /// Códigos de permiso de quien consulta (para mostrar crear/editar).
  final Future<Set<String>> Function() loadPermissions;
  final Future<void> Function(int supplierId, bool isActive)? setActive;

  /// Abre el formulario (alta si es null, edición si trae el proveedor) y
  /// devuelve verdadero si se guardó. Por defecto navega con `go_router`.
  final Future<bool> Function(Map<String, dynamic>? supplier)? openForm;

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  static const _pageSize = 20;

  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  Set<String> _permissions = const {};
  int _total = 0;
  int _offset = 0;
  int _version = 0;
  String _status = 'active'; // active | inactive | all
  bool _loading = false;
  String? _error;

  bool get _canCreate => _permissions.contains('suppliers.create');
  bool get _canUpdate => _permissions.contains('suppliers.update');

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

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _offset = 0;
      _load();
    });
  }

  Future<void> _load() async {
    final version = ++_version;
    final query = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.loadSuppliers(
        limit: _pageSize,
        offset: _offset,
        query: query.isEmpty ? null : query,
        isActive: switch (_status) {
          'active' => true,
          'inactive' => false,
          _ => null,
        },
      );
      if (response is! Map ||
          response['items'] is! List ||
          response['pagination'] is! Map) {
        throw const FormatException('Invalid suppliers response');
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
        setState(() => _error = 'No fue posible cargar los proveedores.');
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openForm(Map<String, dynamic>? supplier) async {
    final saved = widget.openForm != null
        ? await widget.openForm!(supplier)
        : await _push(supplier);
    if (!mounted || !saved) return;
    await _load();
    if (mounted) {
      _message(
        supplier == null ? 'Proveedor registrado.' : 'Proveedor actualizado.',
      );
    }
  }

  Future<bool> _push(Map<String, dynamic>? supplier) async {
    final router = GoRouter.of(context);
    final result = supplier == null
        ? await router.push<bool>('/suppliers/new')
        : await router.push<bool>(
            '/suppliers/${supplier['id']}/edit',
            extra: supplier,
          );
    return result ?? false;
  }

  Future<void> _toggleActive(Map<String, dynamic> supplier) async {
    final setActive = widget.setActive;
    final id = supplier['id'];
    if (setActive == null || id is! int) return;
    final activate = supplier['is_active'] != true;
    if (!activate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Inactivar proveedor'),
          content: Text(
            '¿Inactivar “${supplier['business_name']}”? Su historial se '
            'conserva y se puede reactivar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Inactivar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await setActive(id, activate);
      await _load();
      if (mounted) {
        _message(activate ? 'Proveedor reactivado.' : 'Proveedor inactivado.');
      }
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No fue posible cambiar el estado.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Proveedores'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a inicio',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        if (_canCreate)
          IconButton(
            tooltip: 'Registrar proveedor',
            onPressed: () => _openForm(null),
            icon: const Icon(Icons.add_rounded),
          ),
        IconButton(
          tooltip: 'Actualizar proveedores',
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
                _buildFilters(),
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
                  for (final supplier in _items)
                    _SupplierCard(
                      supplier: supplier,
                      canUpdate: _canUpdate,
                      onEdit: () => _openForm(supplier),
                      onToggleActive: () => _toggleActive(supplier),
                    ),
                if (_error == null && _total > 0) _buildPagination(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildFilters() {
    final search = TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por razón social o documento',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
    final status = DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _status,
      decoration: InputDecoration(
        labelText: 'Estado',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'active', child: Text('Activos')),
        DropdownMenuItem(value: 'inactive', child: Text('Inactivos')),
        DropdownMenuItem(value: 'all', child: Text('Todos')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _status = value;
          _offset = 0;
        });
        _load();
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 640
          ? Column(children: [search, const SizedBox(height: 12), status])
          : Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 12),
                Expanded(child: status),
              ],
            ),
    );
  }

  Widget _buildEmpty() {
    final filtered = _search.text.trim().isNotEmpty || _status != 'active';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 38,
            color: Color(0xFF7C8981),
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'No se encontraron proveedores con esos filtros'
                : 'Aún no hay proveedores registrados',
            style: const TextStyle(
              color: Color(0xFF34453E),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.canUpdate,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> supplier;
  final bool canUpdate;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final isActive = supplier['is_active'] == true;
    final details = <String>[
      'NIT ${supplier['tax_id'] ?? ''}',
      if (supplier['contact_name'] != null) '${supplier['contact_name']}',
      if (supplier['phone'] != null) '${supplier['phone']}',
      if (supplier['email'] != null) '${supplier['email']}',
      if (supplier['location'] != null) '${supplier['location']}',
    ];
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
            child: const Icon(
              Icons.local_shipping_outlined,
              color: Color(0xFF35574A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${supplier['business_name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF253C33),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details.join('  ·  '),
                  style: const TextStyle(
                    color: Color(0xFF68736E),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFE9F4EB)
                      : const Color(0xFFF1EDEA),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isActive ? 'Activo' : 'Inactivo',
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF245A3F)
                        : const Color(0xFF785044),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canUpdate)
                PopupMenuButton<String>(
                  tooltip: 'Acciones del proveedor',
                  onSelected: (action) {
                    if (action == 'edit') onEdit();
                    if (action == 'toggle') onToggleActive();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: ListTile(
                        leading: Icon(
                          isActive
                              ? Icons.block_rounded
                              : Icons.check_circle_outline_rounded,
                        ),
                        title: Text(isActive ? 'Inactivar' : 'Reactivar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.more_vert_rounded),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
