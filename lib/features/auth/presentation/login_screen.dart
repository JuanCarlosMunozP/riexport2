import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin, this.notice});

  final Future<void> Function(String email, String password) onLogin;

  /// Aviso inicial, por ejemplo "Tu sesión expiró".
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onLogin(_emailController.text, _passwordController.text);
      if (mounted) context.go('/');
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No fue posible iniciar sesión. Inténtalo de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F0),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900) {
              return Row(
                children: [
                  const Expanded(flex: 5, child: _BrandPanel()),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 56,
                          vertical: 40,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _buildForm(context, compact: false),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _CompactBrand(),
                      const SizedBox(height: 46),
                      _buildForm(context, compact: true),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) ...[
            Text(
              'Acceso a tu cuenta',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF193D35),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ingresa tus credenciales para continuar.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF68736E),
              ),
            ),
          ] else ...[
            Text(
              'Bienvenido',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF193D35),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inicia sesión para continuar.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF68736E),
              ),
            ),
          ],
          const SizedBox(height: 34),
          const _FieldLabel('Correo electrónico'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: _inputDecoration(
              hint: 'nombre@empresa.com',
              prefix: Icons.mail_outline_rounded,
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Ingresa tu correo electrónico.';
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                return 'Ingresa un correo electrónico válido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          const _FieldLabel('Contraseña'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
            decoration: _inputDecoration(
              hint: 'Ingresa tu contraseña',
              prefix: Icons.lock_outline_rounded,
              suffix: IconButton(
                tooltip: _obscurePassword
                    ? 'Mostrar contraseña'
                    : 'Ocultar contraseña',
                onPressed: () => setState(() {
                  _obscurePassword = !_obscurePassword;
                }),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) =>
                (value ?? '').isEmpty ? 'Ingresa tu contraseña.' : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => context.go('/forgot-password'),
              child: const Text('¿Olvidaste tu contraseña?'),
            ),
          ),
          if (_errorMessage != null || widget.notice != null) ...[
            const SizedBox(height: 18),
            _ErrorBanner(message: _errorMessage ?? widget.notice!),
          ],
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF193D35),
                disabledBackgroundColor: const Color(0xFF82958F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Iniciar sesión'),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(color: Color(0xFFE2E3DC)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '¿No tienes una cuenta?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF68736E),
                ),
              ),
              TextButton(
                onPressed: _isSubmitting ? null : () => context.go('/register'),
                child: const Text('Regístrate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefix,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(prefix, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFD9DDD6)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFD9DDD6)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFB86B43), width: 1.5),
    ),
    errorMaxLines: 2,
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: Color(0xFF34453E),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFF9B3D2D), size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFF84382C), fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _BrandMark(size: 42),
      SizedBox(width: 12),
      _BrandName(dark: true),
    ],
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF193D35),
    padding: const EdgeInsets.all(52),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            _BrandMark(size: 48, light: true),
            SizedBox(width: 14),
            _BrandName(dark: false),
          ],
        ),
        const Spacer(),
        Container(width: 56, height: 4, color: const Color(0xFFD58A5B)),
        const SizedBox(height: 24),
        const Text(
          'Del origen\nal mundo.',
          style: TextStyle(
            color: Color(0xFFF5F2E9),
            fontSize: 46,
            height: 1.12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Gestiona cada etapa de tus exportaciones de café y cacao desde un solo lugar.',
          style: TextStyle(color: Color(0xFFD1DCD4), fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 38),
        const _OriginLine(),
        const Spacer(),
        const Text(
          'CAFÉ  ·  CACAO  ·  TRAZABILIDAD',
          style: TextStyle(
            color: Color(0xFFB9C8BE),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size, this.light = false});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: light ? const Color(0xFFD58A5B) : const Color(0xFF193D35),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
      Icons.spa_outlined,
      size: size * 0.56,
      color: const Color(0xFFFFF9EF),
    ),
  );
}

class _BrandName extends StatelessWidget {
  const _BrandName({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'RiExport',
        style: TextStyle(
          color: dark ? const Color(0xFF193D35) : const Color(0xFFF5F2E9),
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        'CAFÉ & CACAO',
        style: TextStyle(
          color: dark ? const Color(0xFF727B73) : const Color(0xFFB9C8BE),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _OriginLine extends StatelessWidget {
  const _OriginLine();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.location_on_outlined, color: Color(0xFFD58A5B), size: 19),
      SizedBox(width: 9),
      Text(
        'Colombia',
        style: TextStyle(
          color: Color(0xFFF5F2E9),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      SizedBox(width: 15),
      Expanded(child: Divider(color: Color(0xFF557167))),
      SizedBox(width: 15),
      Icon(Icons.public_outlined, color: Color(0xFFD1DCD4), size: 19),
      SizedBox(width: 8),
      Text(
        'Mercados globales',
        style: TextStyle(color: Color(0xFFD1DCD4), fontSize: 13),
      ),
    ],
  );
}
