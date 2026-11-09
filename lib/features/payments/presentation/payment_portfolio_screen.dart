import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

/// Cartera de pagos (PLAT-622–626): obligaciones por exportación con lo pagado,
/// el saldo y su estado; permite registrar pagos y, opcionalmente, ver los
/// montos convertidos a otra moneda (PLAT-630).
class PaymentPortfolioScreen extends StatefulWidget {
  const PaymentPortfolioScreen({
    super.key,
    required this.loadPortfolio,
    this.registerPayment,
    this.createObligation,
    this.loadExports,
    this.onOpenRates,
  });

  final Future<List<Map<String, dynamic>>> Function({
    String? query,
    String? status,
    String? currency,
  })
  loadPortfolio;

  /// Registra un pago (`payments.create`). Null si no tiene permiso.
  final Future<void> Function(Map<String, dynamic> payment)? registerPayment;

  /// Crea una obligación de pago (`payments.create`). Null si no tiene permiso.
  final Future<void> Function(Map<String, dynamic> obligation)?
  createObligation;

  /// Exportaciones sobre las que se puede crear una obligación.
  final Future<List<Map<String, dynamic>>> Function()? loadExports;

  final VoidCallback? onOpenRates;

  @override
  State<PaymentPortfolioScreen> createState() => _PaymentPortfolioScreenState();
}

class _PaymentPortfolioScreenState extends State<PaymentPortfolioScreen> {
  static const statusLabels = {
    'pending': 'Pendiente',
    'partial': 'Pago parcial',
    'overdue': 'Vencido',
    'paid': 'Pagado',
  };
  static const _currencies = ['USD', 'EUR', 'COP', 'GBP'];

  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  String? _status;
  String? _currency;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final text = _search.text.trim();
    try {
      final rows = await widget.loadPortfolio(
        query: text.isEmpty ? null : text,
        status: _status,
        currency: _currency,
      );
      if (mounted) setState(() => _items = rows);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la cartera.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _num(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

  String _money(Object? value, Object? currency) =>
      '${_num(value).toStringAsFixed(2)} $currency';

  /// Saldo pendiente sumado por moneda (y convertido, si hay moneda elegida).
  List<String> get _totals {
    final byCurrency = <String, num>{};
    num converted = 0;
    var anyConverted = false;
    for (final item in _items) {
      final balance = _num(item['balance']);
      if (balance <= 0) continue;
      final currency = '${item['currency_code']}';
      byCurrency[currency] = (byCurrency[currency] ?? 0) + balance;
      if (item['balance_converted'] != null) {
        converted += _num(item['balance_converted']);
        anyConverted = true;
      }
    }
    return [
      for (final entry in byCurrency.entries) _money(entry.value, entry.key),
      if (anyConverted) '≈ ${_money(converted, _currency)}',
    ];
  }

  Future<void> _pay(Map<String, dynamic> item) async {
    final payment = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentDialog(
        orderNumber: '${item['order_number'] ?? ''}',
        currency: '${item['currency_code']}',
        balance: _num(item['balance']),
      ),
    );
    if (payment == null) return;
    try {
      await widget.registerPayment!({
        'obligation_id': item['obligation_id'],
        'currency_code': item['currency_code'],
        ...payment,
      });
      await _load();
      if (mounted) _message('Pago registrado.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo registrar el pago.');
    }
  }

  Future<void> _createObligation() async {
    List<Map<String, dynamic>> exports;
    try {
      exports = await widget.loadExports!();
    } catch (_) {
      if (mounted) _message('No se pudieron cargar las exportaciones.');
      return;
    }
    if (!mounted) return;
    if (exports.isEmpty) {
      _message('No hay exportaciones sobre las que crear una obligación.');
      return;
    }
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ObligationDialog(exports: exports),
    );
    if (body == null) return;
    try {
      await widget.createObligation!(body);
      await _load();
      if (mounted) _message('Obligación creada.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo crear la obligación.');
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      'overdue' => scheme.errorContainer,
      'paid' => scheme.primaryContainer,
      _ => scheme.surfaceContainerHighest,
    };
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cartera de pagos'),
        actions: [
          if (widget.onOpenRates != null)
            IconButton(
              tooltip: 'Tasas de cambio',
              icon: const Icon(Icons.currency_exchange),
              onPressed: widget.onOpenRates,
            ),
        ],
      ),
      floatingActionButton: widget.createObligation == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _createObligation,
              icon: const Icon(Icons.add),
              label: const Text('Nueva obligación'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Buscar pedido, cliente o referencia',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('portfolio-status'),
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (final entry in statusLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      _status = value;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('portfolio-currency'),
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Ver en moneda',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Original'),
                      ),
                      for (final c in _currencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (value) {
                      _currency = value;
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (totals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saldo por cobrar: ${totals.join(' · ')}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _items.isEmpty && !_loading && _error == null
                ? const Center(child: Text('No hay obligaciones de pago.'))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final status = '${item['status']}';
                      final balance = _num(item['balance']);
                      final days = _num(item['days_overdue']);
                      return ListTile(
                        title: Text(
                          'Pedido ${item['order_number'] ?? ''} · ${item['customer_name'] ?? ''}',
                        ),
                        subtitle: Text(
                          [
                            'Total ${_money(item['amount_due'], item['currency_code'])}',
                            'Pagado ${_money(item['amount_paid'], item['currency_code'])}',
                            'Saldo ${_money(balance, item['currency_code'])}',
                            if (item['balance_converted'] != null)
                              '≈ ${_money(item['balance_converted'], item['converted_currency'])}',
                            if (item['due_date'] != null)
                              'Vence ${item['due_date']}',
                            if (days > 0) '$days días de atraso',
                            if ('${item['reference'] ?? ''}'.isNotEmpty)
                              '${item['reference']}',
                          ].join(' · '),
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              label: Text(statusLabels[status] ?? status),
                              backgroundColor: _statusColor(context, status),
                            ),
                            if (widget.registerPayment != null && balance > 0)
                              IconButton(
                                tooltip: 'Registrar pago',
                                icon: const Icon(Icons.payments_outlined),
                                onPressed: () => _pay(item),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo de pago: valida contra el saldo y devuelve `{amount, reference?}`.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.orderNumber,
    required this.currency,
    required this.balance,
  });

  final String orderNumber;
  final String currency;
  final num balance;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.balance.toStringAsFixed(2),
  );
  final _reference = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Registrar pago · pedido ${widget.orderNumber}'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Saldo: ${widget.balance.toStringAsFixed(2)} ${widget.currency}',
          ),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto (${widget.currency})',
            ),
            validator: (value) {
              final parsed = num.tryParse(
                (value ?? '').trim().replaceAll(',', '.'),
              );
              if (parsed == null || parsed <= 0) {
                return 'Indica un monto mayor que cero.';
              }
              if (parsed > widget.balance) {
                return 'El pago supera el saldo de la obligación.';
              }
              return null;
            },
          ),
          TextFormField(
            controller: _reference,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Referencia (opcional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final reference = _reference.text.trim();
          Navigator.pop(context, {
            'amount': num.parse(_amount.text.trim().replaceAll(',', '.')),
            if (reference.isNotEmpty) 'reference': reference,
          });
        },
        child: const Text('Registrar'),
      ),
    ],
  );
}

/// Diálogo de alta de obligación: devuelve el cuerpo de `POST /payments/obligations`.
class _ObligationDialog extends StatefulWidget {
  const _ObligationDialog({required this.exports});

  final List<Map<String, dynamic>> exports;

  @override
  State<_ObligationDialog> createState() => _ObligationDialogState();
}

class _ObligationDialogState extends State<_ObligationDialog> {
  static const _currencies = ['USD', 'EUR', 'COP', 'GBP'];

  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _due = TextEditingController();
  late int? _exportId = widget.exports.first['id'] as int?;
  String _currency = 'USD';

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _due.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva obligación de pago'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _exportId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Exportación'),
              items: [
                for (final e in widget.exports)
                  DropdownMenuItem(
                    value: e['id'] as int,
                    child: Text(
                      '#${e['id']} · ${e['order_number'] ?? ''} · ${e['customer_name'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _exportId = value),
            ),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Monto'),
              validator: (value) {
                final parsed = num.tryParse(
                  (value ?? '').trim().replaceAll(',', '.'),
                );
                return parsed == null || parsed <= 0
                    ? 'Indica un monto mayor que cero.'
                    : null;
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(labelText: 'Moneda'),
              items: [
                for (final c in _currencies)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (value) =>
                  setState(() => _currency = value ?? _currency),
            ),
            TextFormField(
              controller: _due,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Vencimiento (AAAA-MM-DD, opcional)',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
                        DateTime.tryParse(text) != null
                    ? null
                    : 'Usa el formato AAAA-MM-DD.';
              },
            ),
            TextFormField(
              controller: _reference,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'export_id': _exportId,
            'amount_due': num.parse(_amount.text.trim().replaceAll(',', '.')),
            'currency_code': _currency,
            if (_due.text.trim().isNotEmpty) 'due_date': _due.text.trim(),
            if (_reference.text.trim().isNotEmpty)
              'reference': _reference.text.trim(),
          });
        },
        child: const Text('Crear'),
      ),
    ],
  );
}
