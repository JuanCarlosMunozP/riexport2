import '../../../core/roles/role_labels.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

class UserEditScreen extends StatefulWidget {
  const UserEditScreen({
    super.key,
    required this.user,
    required this.onSave,
    this.loadRoles,
    this.loadViewer,
  });

  final Map<String, dynamic> user;
  final Future<void> Function(Map<String, Object?> changes) onSave;

  /// Roles activos. Junto con [loadViewer] activa el selector de rol por nombre;
  /// sin ellos se usa el campo numérico "ID del rol".
  final Future<List<Map<String, dynamic>>> Function()? loadRoles;

  /// Perfil de quien edita (`/me`): `id` y `permission_codes`.
  final Future<Map<String, dynamic>> Function()? loadViewer;

  @override
  State<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(
    text: '${widget.user['first_name'] ?? ''}',
  );
  late final _lastName = TextEditingController(
    text: '${widget.user['last_name'] ?? ''}',
  );
  late final _email = TextEditingController(
    text: '${widget.user['email'] ?? ''}',
  );
  late final _phone = TextEditingController(
    text: '${widget.user['phone'] ?? ''}',
  );
  late final _roleId = TextEditingController(
    text: '${widget.user['role_id'] ?? ''}',
  );
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _roles = const [];
  int? _selectedRoleId;
  bool _canAssignRole = false;
  bool _editingSelf = false;
  bool _loadingRoles = false;
  String? _rolesError;

  bool get _usesRolePicker =>
      widget.loadRoles != null && widget.loadViewer != null;

  @override
  void initState() {
    super.initState();
    _selectedRoleId = widget.user['role_id'] is int
        ? widget.user['role_id'] as int
        : null;
    if (_usesRolePicker) _loadRoleContext();
  }

  Future<void> _loadRoleContext() async {
    setState(() {
      _loadingRoles = true;
      _rolesError = null;
    });
    try {
      final results = await Future.wait([
        widget.loadRoles!(),
        widget.loadViewer!(),
      ]);
      final viewer = results[1] as Map<String, dynamic>;
      final codes = viewer['permission_codes'];
      if (!mounted) return;
      setState(() {
        _roles = results[0] as List<Map<String, dynamic>>;
        _canAssignRole = codes is List && codes.contains('users.assign_role');
        _editingSelf =
            viewer['id'] != null && viewer['id'] == widget.user['id'];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _rolesError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _rolesError = 'No fue posible cargar los roles.');
      }
    } finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _roleId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final changes =
        <String, Object?>{
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'role_id': _usesRolePicker
              ? (_selectedRoleId ?? widget.user['role_id'])
              : int.parse(_roleId.text.trim()),
        }..removeWhere(
          (key, value) =>
              value == widget.user[key] ||
              (key == 'phone' && value == (widget.user[key] ?? '')),
        );
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(changes);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.message;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No fue posible guardar los cambios.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Editar usuario'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver al listado',
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.user['first_name'] ?? ''} ${widget.user['last_name'] ?? ''}'
                          .trim(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: const Color(0xFF193D35),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ID ${widget.user['id'] ?? '—'}',
                      style: const TextStyle(color: Color(0xFF68736E)),
                    ),
                    const SizedBox(height: 26),
                    _field(
                      _firstName,
                      'Nombres',
                      validator: _required,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 18),
                    _field(
                      _lastName,
                      'Apellidos',
                      validator: _required,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 18),
                    _field(
                      _email,
                      'Correo electrónico',
                      keyboardType: TextInputType.emailAddress,
                      readOnly: true,
                      helper:
                          'Solo el titular puede cambiarlo desde Mi perfil.',
                    ),
                    const SizedBox(height: 18),
                    _field(
                      _phone,
                      'Teléfono (opcional)',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 18),
                    if (_usesRolePicker)
                      _buildRolePicker()
                    else
                      _field(
                        _roleId,
                        'ID del rol',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final id = int.tryParse(value?.trim() ?? '');
                          return id == null || id < 1
                              ? 'Ingresa un ID de rol válido.'
                              : null;
                        },
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      _ErrorBanner(message: _error!),
                    ],
                    if (_saving) ...[
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _submit,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Guardando…' : 'Guardar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF193D35),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildRolePicker() {
    if (_loadingRoles) return const LinearProgressIndicator(minHeight: 2);
    if (_rolesError != null) {
      return Row(
        children: [
          Expanded(child: Text(_rolesError!)),
          TextButton(
            onPressed: _loadRoleContext,
            child: const Text('Reintentar'),
          ),
        ],
      );
    }
    final currentId = widget.user['role_id'];
    final items = <DropdownMenuItem<int>>[
      for (final role in _roles)
        if (role['id'] is int)
          DropdownMenuItem<int>(
            value: role['id'] as int,
            child: Text(
              roleLabel(role['name']),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      // El rol actual puede estar inactivo y no venir en la lista de activos.
      if (currentId is int && !_roles.any((role) => role['id'] == currentId))
        DropdownMenuItem<int>(
          value: currentId,
          child: Text(
            '${widget.user['role_name'] != null ? roleLabel(widget.user['role_name']) : 'Rol $currentId'} (actual)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    final canChange = _canAssignRole && !_editingSelf;
    return DropdownButtonFormField<int>(
      initialValue: _selectedRoleId,
      isExpanded: true,
      items: items,
      onChanged: canChange && !_saving
          ? (value) => setState(() => _selectedRoleId = value)
          : null,
      decoration: InputDecoration(
        labelText: 'Rol',
        helperText: canChange
            ? null
            : _editingSelf
            ? 'No puedes cambiar tu propio rol.'
            : 'No tienes permiso para cambiar roles.',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool readOnly = false,
    String? helper,
  }) => TextFormField(
    controller: controller,
    readOnly: readOnly,
    enabled: !readOnly,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );

  String? _required(String? value) =>
      value?.trim().isNotEmpty == true ? null : 'Este campo es obligatorio.';
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEFEB),
      border: Border.all(color: const Color(0xFFE9B6A8)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFF84382C))),
  );
}
