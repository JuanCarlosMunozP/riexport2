import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import 'role_create_dialog.dart';

typedef LoadRoleCatalog = Future<Object?> Function();
typedef CreateRoleAction =
    Future<Object?> Function(Map<String, Object?> request);
typedef UpdateRoleAction =
    Future<Object?> Function(int roleId, Map<String, Object?> changes);
typedef SetRolePermissionsAction =
    Future<Object?> Function(int roleId, List<String> permissionCodes);
typedef DeactivateRoleAction = Future<Object?> Function(int roleId);

class RolesScreen extends StatefulWidget {
  const RolesScreen({
    super.key,
    required this.loadRoles,
    required this.loadPermissions,
    required this.createRole,
    required this.updateRole,
    required this.setRolePermissions,
    required this.deactivateRole,
  });

  final LoadRoleCatalog loadRoles;
  final LoadRoleCatalog loadPermissions;
  final CreateRoleAction createRole;
  final UpdateRoleAction updateRole;
  final SetRolePermissionsAction setRolePermissions;
  final DeactivateRoleAction deactivateRole;

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _permissions = const [];
  Map<String, dynamic>? _selectedRole;
  Set<String> _selectedCodes = {};
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load({int? selectedId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.loadRoles(),
        widget.loadPermissions(),
      ]);
      final roles = _readItems(results[0]);
      final permissions = _readItems(results[1]);
      final role = roles.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id'] == (selectedId ?? _selectedRole?['id']),
        orElse: () => roles.isEmpty ? null : roles.first,
      );
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _permissions = permissions;
        _select(role);
      });
    } on ApiException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } on FormatException {
      if (mounted) setState(() => _error = 'Respuesta inválida del servidor.');
    } catch (_) {
      if (mounted) setState(() => _error = 'No fue posible cargar los roles.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _readItems(Object? response) {
    if (response is! Map || response['items'] is! List) {
      throw const FormatException('Invalid catalog response');
    }
    return (response['items'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid catalog item');
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  void _select(Map<String, dynamic>? role) {
    _selectedRole = role;
    _name.text = '${role?['name'] ?? ''}';
    _description.text = '${role?['description'] ?? ''}';
    _selectedCodes = {
      if (role?['permission_codes'] is List)
        ...(role!['permission_codes'] as List).whereType<String>(),
    };
  }

  Future<void> _create() async {
    final request = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const RoleCreateDialog(),
    );
    if (!mounted || request == null) return;
    try {
      final result = await widget.createRole(request);
      final id = result is Map ? result['id'] : null;
      await _load(selectedId: id is int ? id : null);
    } on ApiException catch (exception) {
      _showMessage(exception.message);
    } catch (_) {
      _showMessage('No fue posible crear el rol.');
    }
  }

  Future<void> _saveRole() async {
    final role = _selectedRole;
    if (role == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showMessage('El nombre del rol es obligatorio.');
      return;
    }
    final description = _description.text.trim().isEmpty
        ? null
        : _description.text.trim();
    final oldDescription = role['description'];
    final changes = <String, Object?>{};
    if (name != role['name']) changes['name'] = name;
    if (description != oldDescription) changes['description'] = description;
    if (changes.isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.updateRole(role['id'] as int, changes);
      await _load(selectedId: role['id'] as int);
      _showMessage('Rol actualizado.');
    } on ApiException catch (exception) {
      _showMessage(exception.message);
    } catch (_) {
      _showMessage('No fue posible guardar los cambios del rol.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePermissions() async {
    final role = _selectedRole;
    if (role == null) return;
    setState(() => _saving = true);
    try {
      await widget.setRolePermissions(
        role['id'] as int,
        _selectedCodes.toList()..sort(),
      );
      await _load(selectedId: role['id'] as int);
      _showMessage('Permisos del rol actualizados.');
    } on ApiException catch (exception) {
      _showMessage(exception.message);
    } catch (_) {
      _showMessage('No fue posible actualizar los permisos.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    final role = _selectedRole;
    if (role == null || role['name'] == 'administrador') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desactivar rol'),
        content: Text(
          '¿Desactivar “${role['name']}”? No se podrá asignar a nuevos usuarios.',
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
      await widget.deactivateRole(role['id'] as int);
      await _load();
      _showMessage('Rol desactivado.');
    } on ApiException catch (exception) {
      _showMessage(exception.message);
    } catch (_) {
      _showMessage('No fue posible desactivar el rol.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Roles y permisos'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a inicio',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        IconButton(
          tooltip: 'Crear rol',
          onPressed: _loading || _saving ? null : _create,
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton(
          tooltip: 'Actualizar roles',
          onPressed: _loading || _saving ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: _loading && _roles.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _roles.isEmpty
          ? _buildError()
          : _buildContent(),
    ),
  );

  Widget _buildContent() {
    final role = _selectedRole;
    if (role == null) {
      return const Center(child: Text('No hay roles disponibles.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey(role['id']),
                  initialValue: role['id'] as int,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: [
                    for (final item in _roles)
                      DropdownMenuItem<int>(
                        value: item['id'] as int,
                        child: Text(
                          '${item['name']}${item['is_active'] == true ? '' : ' (inactivo)'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (id) {
                          final selected = _roles.where(
                            (item) => item['id'] == id,
                          );
                          if (selected.isNotEmpty) {
                            setState(() => _select(selected.first));
                          }
                        },
                ),
                const SizedBox(height: 22),
                Text(
                  'Datos del rol',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF193D35),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  enabled: !_saving && role['name'] != 'administrador',
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  enabled: !_saving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusLabel(isActive: role['is_active'] == true),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _saveRole,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar datos'),
                    ),
                    if (role['name'] != 'administrador' &&
                        role['is_active'] == true)
                      TextButton.icon(
                        onPressed: _saving ? null : _deactivate,
                        icon: const Icon(Icons.block_rounded),
                        label: const Text('Desactivar rol'),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Permisos',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF193D35),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Text('${_selectedCodes.length} seleccionados'),
                  ],
                ),
                const SizedBox(height: 8),
                for (final permission in _permissions)
                  CheckboxListTile(
                    value: _selectedCodes.contains(permission['code']),
                    onChanged: _saving || role['is_active'] != true
                        ? null
                        : (selected) {
                            setState(() {
                              final code = permission['code'] as String;
                              if (selected == true) {
                                _selectedCodes.add(code);
                              } else {
                                _selectedCodes.remove(code);
                              }
                            });
                          },
                    title: Text(
                      '${permission['code']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${permission['description']}'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving || role['is_active'] != true
                        ? null
                        : _savePermissions,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando…' : 'Guardar permisos'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF193D35),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error ?? 'No fue posible cargar los roles.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isActive ? const Color(0xFFE9F4EB) : const Color(0xFFF1EDEA),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(isActive ? 'Activo' : 'Inactivo'),
  );
}
