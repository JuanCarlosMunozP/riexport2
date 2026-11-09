import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

/// Guarda el proveedor. En alta, [fields] trae el proveedor completo; en
/// edición, solo los campos que cambiaron (un opcional vaciado va como null).
typedef SaveSupplier = Future<void> Function(Map<String, Object?> fields);

/// Formulario de registro y edición de proveedores.
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({super.key, required this.onSave, this.supplier});

  final Map<String, dynamic>? supplier;
  final SaveSupplier onSave;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  static final _taxIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]{2,29}$');
  static final _phonePattern = RegExp(r'^\+?[0-9][0-9 ()\-]{5,24}$');
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _initial('business_name'));
  late final _taxId = TextEditingController(text: _initial('tax_id'));
  late final _contact = TextEditingController(text: _initial('contact_name'));
  late final _phone = TextEditingController(text: _initial('phone'));
  late final _email = TextEditingController(text: _initial('email'));
  late final _location = TextEditingController(text: _initial('location'));

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.supplier != null;

  String _initial(String key) => '${widget.supplier?[key] ?? ''}';

  @override
  void dispose() {
    _name.dispose();
    _taxId.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _location.dispose();
    super.dispose();
  }

  String? _required(
    String? value,
    String label,
    String requiredMessage,
    int max, [
    RegExp? pattern,
  ]) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    if (text.length > max) return 'Máximo $max caracteres.';
    if (pattern != null && !pattern.hasMatch(text)) {
      return '$label no tiene un formato válido.';
    }
    return null;
  }

  String? _optional(String? value, int max, [RegExp? pattern, String? label]) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.length > max) return 'Máximo $max caracteres.';
    if (pattern != null && !pattern.hasMatch(text)) {
      return '${label ?? 'El valor'} no tiene un formato válido.';
    }
    return null;
  }

  Map<String, Object?> _collect() {
    String? clean(TextEditingController c) {
      final text = c.text.trim();
      return text.isEmpty ? null : text;
    }

    final fields = <String, Object?>{
      'business_name': _name.text.trim(),
      'tax_id': _taxId.text.trim(),
      'contact_name': clean(_contact),
      'phone': clean(_phone),
      'email': clean(_email)?.toLowerCase(),
      'location': clean(_location),
    };
    if (!_isEdit) {
      fields.removeWhere((key, value) => value == null);
      return fields;
    }
    // Edición: solo lo que cambió (el correo guardado ya viene en minúsculas).
    final supplier = widget.supplier!;
    fields.removeWhere((key, value) => value == supplier[key]);
    return fields;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final fields = _collect();
    if (_isEdit && fields.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(fields);
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
          _error = 'No fue posible guardar el proveedor.';
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
      title: Text(_isEdit ? 'Editar proveedor' : 'Registrar proveedor'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a proveedores',
        onPressed: _saving
            ? null
            : () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop(false);
                } else {
                  context.go('/suppliers');
                }
              },
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Razón social'),
                    validator: (v) => _required(
                      v,
                      'La razón social',
                      'La razón social es obligatoria.',
                      160,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _taxId,
                    enabled: !_saving,
                    decoration: _decoration(
                      'Documento tributario (NIT)',
                      helper: 'Único por proveedor. Ejemplo: 900.123.456-7',
                    ),
                    validator: (v) => _required(
                      v,
                      'El documento tributario',
                      'El documento tributario es obligatorio.',
                      30,
                      _taxIdPattern,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contact,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Nombre de contacto (opcional)'),
                    validator: (v) => _optional(v, 120),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration('Teléfono (opcional)'),
                    validator: (v) =>
                        _optional(v, 25, _phonePattern, 'El teléfono'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _email,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration('Correo (opcional)'),
                    validator: (v) =>
                        _optional(v, 254, _emailPattern, 'El correo'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _location,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration('Ubicación (opcional)'),
                    validator: (v) => _optional(v, 200),
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
      ),
    ),
  );
}
