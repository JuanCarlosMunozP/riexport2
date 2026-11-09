import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

typedef LoadProducts =
    Future<Object?> Function({
      required int limit,
      required int offset,
      String? query,
      String? type,
      int? certificationId,
      bool? isActive,
    });

/// Catálogo de productos: consulta, filtros, edición e inactivación.
class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({
    super.key,
    required this.loadProducts,
    required this.loadCertifications,
    required this.loadPermissions,
    this.setActive,
    this.openForm,
  });

  final LoadProducts loadProducts;
  final Future<List<Map<String, dynamic>>> Function() loadCertifications;

  /// Códigos de permiso de quien consulta (para mostrar crear/editar).
  final Future<Set<String>> Function() loadPermissions;
  final Future<void> Function(int productId, bool isActive)? setActive;

  /// Abre el formulario (crear si es null, editar si trae el producto) y
  /// devuelve verdadero si se guardó. Por defecto navega con `go_router`.
  final Future<bool> Function(Map<String, dynamic>? product)? openForm;

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  static const _pageSize = 20;

  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _certifications = const [];
  Set<String> _permissions = const {};
  int _total = 0;
  int _offset = 0;
  int _version = 0;
  String _type = 'all'; // all | coffee | cacao
  String _status = 'active'; // active | inactive | all
  int? _certificationId;
  bool _loading = false;
  String? _error;

  bool get _canCreate => _permissions.contains('products.create');
  bool get _canUpdate => _permissions.contains('products.update');

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
      final results = await Future.wait([
        widget.loadPermissions(),
        widget.loadCertifications(),
      ]);
      if (!mounted) return;
      setState(() {
        _permissions = results[0] as Set<String>;
        _certifications = results[1] as List<Map<String, dynamic>>;
      });
    } catch (_) {
      // Sin esto la pantalla sigue funcionando en modo solo lectura y sin filtro
      // por certificación.
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
      final response = await widget.loadProducts(
        limit: _pageSize,
        offset: _offset,
        query: query.isEmpty ? null : query,
        type: _type == 'all' ? null : _type,
        certificationId: _certificationId,
        isActive: switch (_status) {
          'active' => true,
          'inactive' => false,
          _ => null,
        },
      );
      if (response is! Map ||
          response['items'] is! List ||
          response['pagination'] is! Map) {
        throw const FormatException('Invalid products response');
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
        setState(() => _error = 'No fue posible cargar los productos.');
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  void _applyFilter(VoidCallback change) {
    setState(() {
      change();
      _offset = 0;
    });
    _load();
  }

  Future<void> _openForm(Map<String, dynamic>? product) async {
    final saved = widget.openForm != null
        ? await widget.openForm!(product)
        : await _push(product);
    if (!mounted || !saved) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              product == null
                  ? 'Producto registrado.'
                  : 'Producto actualizado.',
            ),
          ),
        );
    }
  }

  Future<bool> _push(Map<String, dynamic>? product) async {
    final router = GoRouter.of(context);
    final result = product == null
        ? await router.push<bool>('/products/new')
        : await router.push<bool>(
            '/products/${product['id']}/edit',
            extra: product,
          );
    return result ?? false;
  }

  Future<void> _toggleActive(Map<String, dynamic> product) async {
    final setActive = widget.setActive;
    final id = product['id'];
    if (setActive == null || id is! int) return;
    final activate = product['is_active'] != true;
    if (!activate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Inactivar producto'),
          content: Text(
            '¿Inactivar “${product['variety']}”? No se ofrecerá en nuevas '
            'operaciones, pero su historial se conserva.',
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                activate ? 'Producto reactivado.' : 'Producto inactivado.',
              ),
            ),
          );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('No fue posible cambiar el estado.')),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Catálogo de productos'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a inicio',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        if (_canCreate)
          IconButton(
            tooltip: 'Registrar producto',
            onPressed: () => _openForm(null),
            icon: const Icon(Icons.add_rounded),
          ),
        IconButton(
          tooltip: 'Actualizar catálogo',
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
                  for (final product in _items)
                    _ProductCard(
                      product: product,
                      canUpdate: _canUpdate,
                      onEdit: () => _openForm(product),
                      onToggleActive: () => _toggleActive(product),
                    ),
                if (_error == null && _total > 0) _buildPagination(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );

  Widget _buildFilters() {
    final searchField = TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por variedad o calidad',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
    final typeFilter = DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _type,
      decoration: _decoration('Tipo'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Todos')),
        DropdownMenuItem(value: 'coffee', child: Text('Café')),
        DropdownMenuItem(value: 'cacao', child: Text('Cacao')),
      ],
      onChanged: (value) {
        if (value != null) _applyFilter(() => _type = value);
      },
    );
    final certificationFilter = DropdownButtonFormField<int?>(
      isExpanded: true,
      initialValue: _certificationId,
      decoration: _decoration('Certificación'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
        for (final c in _certifications)
          if (c['id'] is int)
            DropdownMenuItem<int?>(
              value: c['id'] as int,
              child: Text('${c['name']}', overflow: TextOverflow.ellipsis),
            ),
      ],
      onChanged: (value) => _applyFilter(() => _certificationId = value),
    );
    final statusFilter = DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _status,
      decoration: _decoration('Estado'),
      items: const [
        DropdownMenuItem(value: 'active', child: Text('Activos')),
        DropdownMenuItem(value: 'inactive', child: Text('Inactivos')),
        DropdownMenuItem(value: 'all', child: Text('Todos')),
      ],
      onChanged: (value) {
        if (value != null) _applyFilter(() => _status = value);
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              typeFilter,
              const SizedBox(height: 12),
              certificationFilter,
              const SizedBox(height: 12),
              statusFilter,
            ],
          );
        }
        return Column(
          children: [
            searchField,
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: typeFilter),
                const SizedBox(width: 12),
                Expanded(child: certificationFilter),
                const SizedBox(width: 12),
                Expanded(child: statusFilter),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmpty() {
    final filtered =
        _search.text.trim().isNotEmpty ||
        _type != 'all' ||
        _certificationId != null ||
        _status != 'active';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 38,
            color: Color(0xFF7C8981),
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'No se encontraron productos con esos filtros'
                : 'Aún no hay productos registrados',
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

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.canUpdate,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> product;
  final bool canUpdate;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final isCoffee = product['type'] == 'coffee';
    final isActive = product['is_active'] == true;
    final certifications = [
      if (product['certifications'] is List)
        for (final c in product['certifications'] as List)
          if (c is Map) '${c['name']}',
    ];
    final details = <String>[
      '${product['quality_grade'] ?? ''}',
      if (product['hs_code'] != null) 'HS ${product['hs_code']}',
      '${product['base_unit_name'] ?? product['base_unit_code'] ?? ''}',
      if (isCoffee && product['humidity_percent'] != null)
        'Humedad ${product['humidity_percent']} %',
      if (!isCoffee && product['bean_type'] != null)
        'Grano ${product['bean_type']}',
      if (!isCoffee && product['fermentation_percent'] != null)
        'Fermentación ${product['fermentation_percent']} %',
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${product['variety'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF253C33),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label: isCoffee ? 'Café' : 'Cacao',
                      color: const Color(0xFFE8EDE8),
                      textColor: const Color(0xFF245A3F),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details.where((d) => d.trim().isNotEmpty).join('  ·  '),
                  style: const TextStyle(
                    color: Color(0xFF68736E),
                    fontSize: 13,
                  ),
                ),
                if (certifications.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in certifications)
                        _Chip(
                          label: name,
                          color: const Color(0xFFFBEFE6),
                          textColor: const Color(0xFF8A4B2C),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Chip(
                label: isActive ? 'Activo' : 'Inactivo',
                color: isActive
                    ? const Color(0xFFE9F4EB)
                    : const Color(0xFFF1EDEA),
                textColor: isActive
                    ? const Color(0xFF245A3F)
                    : const Color(0xFF785044),
              ),
              if (canUpdate)
                PopupMenuButton<String>(
                  tooltip: 'Acciones del producto',
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
