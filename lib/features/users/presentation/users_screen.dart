import '../../../core/roles/role_labels.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

typedef LoadUsers =
    Future<Object?> Function({
      required int limit,
      required int offset,
      String? query,
      bool? isActive,
    });

class UsersScreen extends StatefulWidget {
  const UsersScreen({
    super.key,
    required this.loadUsers,
    this.deactivateUser,
    this.reactivateUser,
    this.editUser,
  });

  final LoadUsers loadUsers;
  final Future<void> Function(int userId)? deactivateUser;
  final Future<void> Function(int userId)? reactivateUser;
  final Future<bool> Function(Map<String, dynamic> user)? editUser;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  static const _pageSize = 20;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _users = const [];
  int _total = 0;
  int _offset = 0;
  int _requestVersion = 0;
  bool? _isActive;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _offset = 0;
      _loadUsers();
    });
  }

  void _onStatusChanged(String? value) {
    if (value == null) return;
    setState(() {
      _isActive = switch (value) {
        'active' => true,
        'inactive' => false,
        _ => null,
      };
      _offset = 0;
    });
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final version = ++_requestVersion;
    final query = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.loadUsers(
        limit: _pageSize,
        offset: _offset,
        query: query.isEmpty ? null : query,
        isActive: _isActive,
      );
      final page = _parsePage(response);
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _users = page.items;
        _total = page.total;
      });
    } on ApiException catch (error) {
      if (mounted && version == _requestVersion) {
        setState(() => _errorMessage = error.message);
      }
    } on FormatException {
      if (mounted && version == _requestVersion) {
        setState(() {
          _errorMessage = 'El servidor devolvió una respuesta no válida.';
        });
      }
    } catch (_) {
      if (mounted && version == _requestVersion) {
        setState(() {
          _errorMessage =
              'No fue posible cargar los usuarios. Inténtalo de nuevo.';
        });
      }
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _isLoading = false);
      }
    }
  }

  _UserPage _parsePage(Object? response) {
    if (response is! Map<String, dynamic> ||
        response['items'] is! List ||
        response['pagination'] is! Map) {
      throw const FormatException('Invalid users response');
    }
    final pagination = Map<String, dynamic>.from(response['pagination'] as Map);
    final rawItems = response['items'] as List;
    final items = rawItems.map((item) {
      if (item is! Map) throw const FormatException('Invalid user item');
      return Map<String, dynamic>.from(item);
    }).toList();
    final total = pagination['total'];
    if (total is! int) throw const FormatException('Invalid pagination');
    return _UserPage(items: items, total: total);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Usuarios'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a inicio',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar lista',
          onPressed: _isLoading ? null : _loadUsers,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Consultar usuarios',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF193D35),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildFilters(constraints.maxWidth),
                  if (_isLoading) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(minHeight: 2),
                  ] else
                    const SizedBox(height: 16),
                  if (_errorMessage != null)
                    _buildError()
                  else if (!_isLoading && _users.isEmpty)
                    _buildEmptyState()
                  else if (_users.isNotEmpty)
                    _buildUserList()
                  else
                    const SizedBox(height: 160),
                  if (_errorMessage == null && _total > 0) _buildPagination(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildFilters(double availableWidth) {
    final searchField = TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre o correo',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: Colors.white,
        border: _inputBorder(),
        enabledBorder: _inputBorder(),
        focusedBorder: _inputBorder(focused: true),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
    final statusFilter = DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _isActive == null
          ? 'all'
          : _isActive!
          ? 'active'
          : 'inactive',
      decoration: InputDecoration(
        labelText: 'Estado',
        filled: true,
        fillColor: Colors.white,
        border: _inputBorder(),
        enabledBorder: _inputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Todos')),
        DropdownMenuItem(value: 'active', child: Text('Activos')),
        DropdownMenuItem(value: 'inactive', child: Text('Inactivos')),
      ],
      onChanged: _onStatusChanged,
    );
    if (availableWidth < 480) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [searchField, const SizedBox(height: 12), statusFilter],
      );
    }
    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 12),
        SizedBox(width: 158, child: statusFilter),
      ],
    );
  }

  OutlineInputBorder _inputBorder({bool focused = false}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(
      color: focused ? const Color(0xFFB86B43) : const Color(0xFFD9DDD6),
      width: focused ? 1.5 : 1,
    ),
  );

  Widget _buildUserList() => Column(
    children: [
      for (final user in _users)
        _UserRow(
          user: user,
          onEdit: () => _editUser(user),
          onDeactivate: () => _deactivateUser(user),
          onReactivate: () => _reactivateUser(user),
        ),
    ],
  );

  Future<void> _editUser(Map<String, dynamic> user) async {
    final userId = user['id'];
    if (userId is! int) return;
    final bool saved;
    if (widget.editUser != null) {
      saved = await widget.editUser!(user);
    } else {
      final router = GoRouter.of(context);
      saved =
          await router.push<bool>('/users/$userId/edit', extra: user) ?? false;
    }
    if (!mounted || !saved) return;
    await _loadUsers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario actualizado correctamente.')),
      );
    }
  }

  Future<void> _reactivateUser(Map<String, dynamic> user) async {
    final reactivate = widget.reactivateUser;
    final userId = user['id'];
    if (reactivate == null || userId is! int) return;
    try {
      await reactivate(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Usuario reactivado.')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fue posible reactivar al usuario.')),
        );
      }
    }
  }

  Future<void> _deactivateUser(Map<String, dynamic> user) async {
    final deactivate = widget.deactivateUser;
    final userId = user['id'];
    if (deactivate == null || userId is! int) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desactivar usuario'),
        content: Text(
          '¿Desactivar a ${user['first_name'] ?? ''} ${user['last_name'] ?? ''}? '
          'No podrá iniciar sesión, pero su historial se conservará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await deactivate(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Usuario desactivado.')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible desactivar al usuario.'),
          ),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    final searched = _searchController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(
            searched ? Icons.search_off_rounded : Icons.people_outline_rounded,
            size: 38,
            color: const Color(0xFF7C8981),
          ),
          const SizedBox(height: 12),
          Text(
            searched
                ? 'No se encontraron usuarios'
                : 'No hay usuarios para mostrar',
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
          _errorMessage!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF84382C)),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadUsers,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );

  Widget _buildPagination() {
    final first = _offset + 1;
    final last = (_offset + _users.length).clamp(0, _total);
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
            onPressed: _offset == 0 || _isLoading
                ? null
                : () {
                    setState(
                      () => _offset = (_offset - _pageSize).clamp(0, _total),
                    );
                    _loadUsers();
                  },
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            onPressed: _offset + _users.length >= _total || _isLoading
                ? null
                : () {
                    setState(() => _offset += _pageSize);
                    _loadUsers();
                  },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _UserPage {
  const _UserPage({required this.items, required this.total});

  final List<Map<String, dynamic>> items;
  final int total;
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.onEdit,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
        .trim();
    final isActive = user['is_active'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
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
              Icons.person_outline_rounded,
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
                  name.isEmpty ? 'Usuario' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF253C33),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${user['email'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF68736E),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID ${user['id'] ?? '—'}  ·  Rol ${user['role_name'] != null ? roleLabel(user['role_name']) : (user['role_id'] ?? '—')}',
                  style: const TextStyle(
                    color: Color(0xFF7A837D),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 68, minHeight: 26),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              PopupMenuButton<String>(
                tooltip: 'Acciones del usuario',
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'deactivate') onDeactivate();
                  if (action == 'activate') onReactivate();
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
                  if (isActive)
                    const PopupMenuItem(
                      value: 'deactivate',
                      child: ListTile(
                        leading: Icon(Icons.person_off_outlined),
                        title: Text('Desactivar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  else
                    const PopupMenuItem(
                      value: 'activate',
                      child: ListTile(
                        leading: Icon(Icons.person_add_alt_1_outlined),
                        title: Text('Reactivar'),
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
