import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/validation/password_policy.dart';

typedef ResetPasswordAction =
    Future<void> Function({
      required String email,
      required String code,
      required String newPassword,
    });

/// Segundo paso: correo + código recibido + contraseña nueva.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.onReset,
    this.initialEmail,
  });

  final ResetPasswordAction onReset;
  final String? initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _hidePassword = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onReset(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada. Inicia sesión con la nueva.'),
        ),
      );
      context.go('/login');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No fue posible cambiar la contraseña. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Contraseña nueva'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a iniciar sesión',
        onPressed: () => context.go('/login'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Crea tu contraseña nueva',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF193D35),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ingresa el código de 6 dígitos que te enviamos por correo. '
                    'Sirve una sola vez y vence en 1 hora.',
                    style: TextStyle(color: Color(0xFF68736E)),
                  ),
                  const SizedBox(height: 24),
                  _field(
                    _email,
                    'Correo electrónico',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) {
                        return 'Ingresa tu correo electrónico.';
                      }
                      return _emailPattern.hasMatch(email)
                          ? null
                          : 'Ingresa un correo electrónico válido.';
                    },
                  ),
                  const SizedBox(height: 16),
                  _field(
                    _code,
                    'Código de 6 dígitos',
                    keyboardType: TextInputType.number,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (value) =>
                        RegExp(r'^[0-9]{6,10}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Ingresa el código de 6 dígitos.',
                  ),
                  const SizedBox(height: 16),
                  _field(
                    _password,
                    'Contraseña nueva',
                    obscure: _hidePassword,
                    suffix: IconButton(
                      tooltip: _hidePassword
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    validator: (value) {
                      return validatePasswordPolicy(value ?? '');
                    },
                  ),
                  const SizedBox(height: 16),
                  _field(
                    _confirmation,
                    'Confirmar contraseña',
                    obscure: _hidePassword,
                    validator: (value) {
                      if ((value ?? '').isEmpty) {
                        return 'Confirma la contraseña.';
                      }
                      return value == _password.text
                          ? null
                          : 'Las contraseñas no coinciden.';
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEFEB),
                        border: Border.all(color: const Color(0xFFE9B6A8)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFF84382C)),
                      ),
                    ),
                  ],
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: const Icon(Icons.lock_reset_rounded),
                    label: Text(_saving ? 'Guardando…' : 'Cambiar contraseña'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF193D35),
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go('/forgot-password'),
                    child: const Text('Solicitar otro código'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    Widget? suffix,
  }) => TextFormField(
    controller: controller,
    enabled: !_saving,
    obscureText: obscure,
    keyboardType: keyboardType,
    inputFormatters: formatters,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}
