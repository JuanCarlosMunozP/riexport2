import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.loadProfile,
    required this.saveProfile,
    required this.changeEmail,
  });

  final Future<Object?> Function() loadProfile;

  /// Recibe solo los campos modificados (`first_name`, `last_name`, `phone`).
  final Future<Object?> Function(Map<String, Object?> changes) saveProfile;
  final Future<Object?> Function(String email) changeEmail;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _dataFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _emailController = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _savingData = false;
  bool _savingEmail = false;
  String? _loadError;
  String? _dataError;
  String? _dataSuccess;
  String? _emailError;
  String? _emailSuccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await widget.loadProfile();
      if (response is! Map) throw const FormatException('Invalid profile');
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(response);
      setState(() {
        _profile = profile;
        _firstName.text = '${profile['first_name'] ?? ''}';
        _lastName.text = '${profile['last_name'] ?? ''}';
        _phone.text = '${profile['phone'] ?? ''}';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'No fue posible cargar tu perfil.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveData() async {
    FocusScope.of(context).unfocus();
    if (!_dataFormKey.currentState!.validate()) return;
    final profile = _profile!;
    final phone = _phone.text.trim();
    final changes = <String, Object?>{
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      'phone': phone.isEmpty ? null : phone,
    }..removeWhere((key, value) => value == profile[key]);
    if (changes.isEmpty) {
      setState(() {
        _dataError = null;
        _dataSuccess = 'No hay cambios que guardar.';
      });
      return;
    }
    setState(() {
      _savingData = true;
      _dataError = null;
      _dataSuccess = null;
    });
    try {
      await widget.saveProfile(changes);
      if (!mounted) return;
      setState(() => _dataSuccess = 'Datos actualizados.');
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _dataError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _dataError = 'No fue posible guardar tus datos.');
      }
    } finally {
      if (mounted) setState(() => _savingData = false);
    }
  }

  Future<void> _submitEmail() async {
    FocusScope.of(context).unfocus();
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _savingEmail = true;
      _emailError = null;
      _emailSuccess = null;
    });
    try {
      final response = await widget.changeEmail(_emailController.text.trim());
      final message = response is Map && response['message'] is String
          ? response['message'] as String
          : 'Solicitud enviada.';
      if (!mounted) return;
      _emailController.clear();
      setState(() => _emailSuccess = message);
      // Con confirmación por correo el perfil no cambia hasta confirmarlo.
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _emailError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _emailError = 'No fue posible cambiar el correo.');
      }
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Mi perfil'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a inicio',
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: _loading && _profile == null
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
          ? _buildLoadError()
          : _buildContent(_profile!),
    ),
  );

  Widget _buildLoadError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_loadError ?? 'No fue posible cargar tu perfil.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );

  TextStyle? _sectionStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium
      ?.copyWith(color: const Color(0xFF193D35), fontWeight: FontWeight.w700);

  Widget _buildContent(Map<String, dynamic> profile) {
    final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
        .trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name.isEmpty ? 'Mi perfil' : name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF193D35),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${profile['email'] ?? ''}',
                style: const TextStyle(color: Color(0xFF68736E)),
              ),
              const SizedBox(height: 28),
              Text('Datos personales', style: _sectionStyle(context)),
              const SizedBox(height: 16),
              _buildDataForm(),
              const SizedBox(height: 36),
              Text('Cambiar correo electrónico', style: _sectionStyle(context)),
              const SizedBox(height: 6),
              const Text(
                'Te enviaremos enlaces de confirmación al correo nuevo y, si se '
                'exige, al actual. Seguirás entrando con el actual hasta que '
                'el cambio se confirme.',
                style: TextStyle(color: Color(0xFF68736E), fontSize: 13),
              ),
              const SizedBox(height: 16),
              _buildEmailForm(profile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataForm() => Form(
    key: _dataFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _firstName,
          enabled: !_savingData,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Nombres'),
          validator: _required,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastName,
          enabled: !_savingData,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Apellidos'),
          validator: _required,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phone,
          enabled: !_savingData,
          keyboardType: TextInputType.phone,
          decoration: _decoration('Teléfono (opcional)'),
          validator: (value) =>
              (value?.trim().length ?? 0) > 32 ? 'Máximo 32 caracteres.' : null,
        ),
        if (_dataError != null) ...[
          const SizedBox(height: 16),
          _Banner(message: _dataError!, isError: true),
        ],
        if (_dataSuccess != null) ...[
          const SizedBox(height: 16),
          _Banner(message: _dataSuccess!, isError: false),
        ],
        if (_savingData) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _savingData ? null : _saveData,
          icon: const Icon(Icons.save_outlined),
          label: Text(_savingData ? 'Guardando…' : 'Guardar datos'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF193D35),
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmailForm(Map<String, dynamic> profile) => Form(
    key: _emailFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _emailController,
          enabled: !_savingEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _decoration('Correo nuevo'),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Ingresa el correo nuevo.';
            if (!_emailPattern.hasMatch(email)) {
              return 'Ingresa un correo válido.';
            }
            if (email.toLowerCase() ==
                '${profile['email'] ?? ''}'.toLowerCase()) {
              return 'Ese ya es tu correo actual.';
            }
            return null;
          },
        ),
        if (_emailError != null) ...[
          const SizedBox(height: 16),
          _Banner(message: _emailError!, isError: true),
        ],
        if (_emailSuccess != null) ...[
          const SizedBox(height: 16),
          _Banner(message: _emailSuccess!, isError: false),
        ],
        if (_savingEmail) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _savingEmail ? null : _submitEmail,
          icon: const Icon(Icons.mail_outline_rounded),
          label: Text(_savingEmail ? 'Enviando…' : 'Cambiar correo'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      ],
    ),
  );

  String? _required(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Este campo es obligatorio.';
    if (text.length > 100) return 'Máximo 100 caracteres.';
    return null;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

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
