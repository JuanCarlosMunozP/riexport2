import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

/// Primer paso de la recuperación de acceso: pide el correo y solicita el código.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onRequest});

  final Future<void> Function(String email) onRequest;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
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
      await widget.onRequest(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No fue posible enviar el código. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Recuperar acceso'),
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
                    '¿Olvidaste tu contraseña?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF193D35),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escribe el correo de tu cuenta. Te enviaremos un código de '
                    '6 dígitos para crear una contraseña nueva.',
                    style: TextStyle(color: Color(0xFF68736E)),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_sending,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'Correo electrónico',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
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
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _Notice(message: _error!, isError: true),
                  ],
                  if (_sent) ...[
                    const SizedBox(height: 16),
                    const _Notice(
                      message:
                          'Si existe una cuenta con ese correo, te enviamos un '
                          'código. Revisa tu bandeja y la carpeta de spam.',
                      isError: false,
                    ),
                  ],
                  if (_sending) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: const Icon(Icons.mark_email_unread_outlined),
                    label: Text(_sent ? 'Enviar de nuevo' : 'Enviar código'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF193D35),
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () => context.go(
                            '/reset-password',
                            extra: _email.text.trim(),
                          ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Ya tengo un código'),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFFEFEB) : const Color(0xFFE9F4EB),
      border: Border.all(
        color: isError ? const Color(0xFFE9B6A8) : const Color(0xFFB7D8C0),
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: isError ? const Color(0xFF84382C) : const Color(0xFF245A3F),
      ),
    ),
  );
}
