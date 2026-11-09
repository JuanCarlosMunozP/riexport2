import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

/// Cuentas de usuario vinculadas a un cliente: quién puede entrar como ese
/// cliente. Se vincula por el correo de la cuenta; la cuenta debe estar activa
/// y su rol necesita `portal.read` para ver algo.
class CustomerAccountsScreen extends StatefulWidget {
  const CustomerAccountsScreen({
    super.key,
    required this.customer,
    required this.loadAccounts,
    required this.link,
    required this.unlink,
    this.canEdit = true,
  });

  final Map<String, dynamic> customer;
  final Future<List<Map<String, dynamic>>> Function() loadAccounts;
  final Future<void> Function(String email) link;
  final Future<void> Function(int profileId) unlink;
  final bool canEdit;

  @override
  State<CustomerAccountsScreen> createState() => _CustomerAccountsScreenState();
}

class _CustomerAccountsScreenState extends State<CustomerAccountsScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  List<Map<String, dynamic>> _accounts = const [];
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final accounts = await widget.loadAccounts();
      if (mounted) setState(() => _accounts = accounts);
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'No fue posible cargar las cuentas.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _link() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.link(_email.text.trim().toLowerCase());
      _email.clear();
      await _load();
      if (mounted) _message('Cuenta vinculada.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No fue posible vincular la cuenta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink(Map<String, dynamic> account) async {
    final id = account['profile_id'];
    if (id is! int) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desvincular cuenta'),
        content: Text(
          '¿Desvincular ${account['email']}? Dejará de ver los datos de '
          '“${widget.customer['name']}”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.unlink(id);
      await _load();
      if (mounted) _message('Cuenta desvinculada.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No fue posible desvincular la cuenta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Cuentas del cliente'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a clientes',
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
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
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.customer['name'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Estas cuentas entran a la app como este cliente. Para ver '
                  'algo, el rol de la cuenta debe tener el permiso de portal.',
                  style: TextStyle(color: Color(0xFF68736E), fontSize: 13),
                ),
                if (widget.canEdit) ...[
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Correo de la cuenta',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            validator: (v) {
                              final text = v?.trim() ?? '';
                              if (text.isEmpty) {
                                return 'El correo de la cuenta es obligatorio.';
                              }
                              return _emailPattern.hasMatch(text)
                                  ? null
                                  : 'El correo no tiene un formato válido.';
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: FilledButton(
                            onPressed: _busy ? null : _link,
                            child: const Text('Vincular'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_loadError != null)
                  Column(
                    children: [
                      Text(
                        _loadError!,
                        style: const TextStyle(color: Color(0xFF84382C)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  )
                else if (_accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Este cliente aún no tiene cuentas vinculadas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  for (final account in _accounts)
                    _AccountTile(
                      account: account,
                      onUnlink: widget.canEdit && !_busy
                          ? () => _unlink(account)
                          : null,
                    ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.onUnlink});

  final Map<String, dynamic> account;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final warnings = <String>[
      if (account['account_is_active'] == false) 'Cuenta desactivada',
      if (account['has_portal_access'] == false) 'Sin permiso de portal',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E3DC))),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle_outlined, color: Color(0xFF35574A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${account['email'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF253C33),
                  ),
                ),
                Text(
                  '${account['first_name'] ?? ''} ${account['last_name'] ?? ''}'
                      .trim(),
                  style: const TextStyle(
                    color: Color(0xFF68736E),
                    fontSize: 13,
                  ),
                ),
                if (warnings.isNotEmpty)
                  Text(
                    warnings.join(' · '),
                    style: const TextStyle(
                      color: Color(0xFF9A6A2C),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Desvincular cuenta',
            onPressed: onUnlink,
            icon: const Icon(Icons.link_off_rounded),
          ),
        ],
      ),
    );
  }
}
