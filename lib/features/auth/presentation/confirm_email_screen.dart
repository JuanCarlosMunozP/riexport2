import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

/// Confirmación de correo tras el registro (PLAT-449): el usuario escribe el
/// código de 6 dígitos que Supabase envía a su correo.
class ConfirmEmailScreen extends StatefulWidget {
  const ConfirmEmailScreen({
    super.key,
    required this.onConfirm,
    this.initialEmail,
  });

  final Future<void> Function({required String email, required String code})
  onConfirm;
  final String? initialEmail;

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _code = TextEditingController();
  bool _sending = false;
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onConfirm(
        email: _email.text.trim(),
        code: _code.text.trim(),
      );
      if (mounted) setState(() => _confirmed = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No fue posible confirmar el correo. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Confirmar correo'),
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
                    'Activa tu cuenta',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF193D35),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escribe el código de 6 dígitos que enviamos a tu correo al registrarte.',
                    style: TextStyle(color: Color(0xFF68736E)),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_sending && !_confirmed,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: _decoration('Correo electrónico'),
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
                  TextFormField(
                    controller: _code,
                    enabled: !_sending && !_confirmed,
                    keyboardType: TextInputType.number,
                    decoration: _decoration('Código de confirmación'),
                    validator: (value) =>
                        RegExp(r'^[0-9]{6,10}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Ingresa el código de 6 dígitos.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_confirmed) ...[
                    const SizedBox(height: 16),
                    const Text('Correo confirmado. Ya puedes iniciar sesión.'),
                  ],
                  if (_sending) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _sending
                        ? null
                        : (_confirmed ? () => context.go('/login') : _submit),
                    icon: Icon(
                      _confirmed ? Icons.login : Icons.mark_email_read_outlined,
                    ),
                    label: Text(
                      _confirmed ? 'Ir a iniciar sesión' : 'Confirmar',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF193D35),
                      minimumSize: const Size.fromHeight(50),
                    ),
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
