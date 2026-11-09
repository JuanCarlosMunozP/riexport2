import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/validation/eori.dart';

/// Guarda el cliente. En alta, [fields] trae el cliente completo; en edición,
/// solo los campos que cambiaron (un opcional vaciado va como null).
typedef SaveCustomer = Future<void> Function(Map<String, Object?> fields);

/// Formulario de registro y edición de clientes, con validación del EORI según
/// el país (obligatorio en la Unión Europea).
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, required this.onSave, this.customer});

  final Map<String, dynamic>? customer;
  final SaveCustomer onSave;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _countryPattern = RegExp(r'^[A-Za-z]{2}$');
  static final _currencyPattern = RegExp(r'^[A-Za-z]{3}$');

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _initial('name'));
  late final _contact = TextEditingController(text: _initial('contact_name'));
  late final _email = TextEditingController(text: _initial('email'));
  late final _country = TextEditingController(text: _initial('country_code'));
  late final _eori = TextEditingController(text: _initial('eori_number'));
  late final _currency = TextEditingController(
    text: widget.customer == null ? 'USD' : _initial('preferred_currency_code'),
  );

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.customer != null;

  String _initial(String key) => '${widget.customer?[key] ?? ''}';

  @override
  void initState() {
    super.initState();
    // El texto de ayuda del EORI depende del país escrito.
    _country.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _country.dispose();
    _eori.dispose();
    _currency.dispose();
    super.dispose();
  }

  bool get _eoriRequired =>
      euCountryCodes.contains(_country.text.trim().toUpperCase());

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
      'name': _name.text.trim(),
      'contact_name': clean(_contact),
      'email': clean(_email)?.toLowerCase(),
      'country_code': _country.text.trim().toUpperCase(),
      'eori_number': normalizeEori(_eori.text),
      'preferred_currency_code': _currency.text.trim().toUpperCase(),
    };
    if (!_isEdit) {
      fields.removeWhere((key, value) => value == null);
      return fields;
    }
    // Edición: solo lo que cambió.
    final customer = widget.customer!;
    fields.removeWhere((key, value) => value == customer[key]);
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
          _error = 'No fue posible guardar el cliente.';
          _saving = false;
        });
      }
    }
  }

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: Text(_isEdit ? 'Editar cliente' : 'Registrar cliente'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a clientes',
        onPressed: _saving
            ? null
            : () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop(false);
                } else {
                  context.go('/customers');
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
                    decoration: _decoration('Nombre o razón social'),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'El nombre del cliente es obligatorio.';
                      }
                      return text.length > 180
                          ? 'Máximo 180 caracteres.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contact,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Contacto comercial (opcional)'),
                    validator: (v) => _optional(v, 160),
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
                    controller: _country,
                    enabled: !_saving,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _decoration(
                      'País (código de 2 letras)',
                      helper: 'Por ejemplo ES, DE, US, CO.',
                    ).copyWith(counterText: ''),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) return 'El país es obligatorio.';
                      return _countryPattern.hasMatch(text)
                          ? null
                          : 'El país debe ser un código de 2 letras.';
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _eori,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _decoration(
                      _eoriRequired ? 'EORI' : 'EORI (opcional)',
                      helper: _eoriRequired
                          ? 'Obligatorio para clientes de la Unión Europea. '
                                '2 letras del país y hasta 15 caracteres, '
                                'por ejemplo ${eoriPrefixFor(_country.text.trim().toUpperCase())}12345678Z.'
                          : 'Identificador de operador económico. Empieza por '
                                'las letras de su país (por ejemplo ES12345678Z).',
                    ),
                    validator: (v) =>
                        validateEori(v, _country.text.trim().toUpperCase()),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _currency,
                    enabled: !_saving,
                    maxLength: 3,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _decoration(
                      'Moneda preferida (código de 3 letras)',
                      helper: 'Por ejemplo USD, EUR, COP.',
                    ).copyWith(counterText: ''),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'La moneda preferida es obligatoria.';
                      }
                      return _currencyPattern.hasMatch(text)
                          ? null
                          : 'La moneda debe ser un código de 3 letras.';
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
      ),
    ),
  );
}
