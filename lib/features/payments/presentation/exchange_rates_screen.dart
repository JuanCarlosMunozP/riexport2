import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

/// Tasas de cambio y conversor de montos (PLAT-627–630).
class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({
    super.key,
    required this.loadRates,
    required this.convert,
    this.refreshRates,
    this.addRate,
  });

  final Future<List<Map<String, dynamic>>> Function() loadRates;

  /// Convierte un monto con la última tasa conocida (directa, inversa o vía USD).
  final Future<Map<String, dynamic>> Function(
    num amount,
    String from,
    String to,
  )
  convert;

  /// Consulta el servicio externo y guarda las tasas (`payments.create`).
  final Future<void> Function()? refreshRates;

  /// Registra una tasa manual (`payments.create`).
  final Future<void> Function(Map<String, dynamic> rate)? addRate;

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  final _amount = TextEditingController(text: '100');
  final _from = TextEditingController(text: 'USD');
  final _to = TextEditingController(text: 'EUR');
  List<Map<String, dynamic>> _rates = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.loadRates();
      if (mounted) setState(() => _rates = rows);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las tasas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _convert() async {
    final amount = num.tryParse(_amount.text.trim().replaceAll(',', '.'));
    final from = _from.text.trim().toUpperCase();
    final to = _to.text.trim().toUpperCase();
    final code = RegExp(r'^[A-Z]{3}$');
    if (amount == null || !code.hasMatch(from) || !code.hasMatch(to)) {
      setState(() => _result = 'Indica un monto y dos monedas de 3 letras.');
      return;
    }
    try {
      final r = await widget.convert(amount, from, to);
      if (mounted) {
        setState(
          () => _result =
              '$amount $from = ${r['converted']} $to (tasa ${r['rate']}, ${r['source']})',
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _result = error.message);
    } catch (_) {
      if (mounted) setState(() => _result = 'No se pudo convertir el monto.');
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.refreshRates!();
      await _load();
      if (mounted) _message('Tasas actualizadas.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo actualizar desde el servicio externo.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _add() async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _RateDialog(),
    );
    if (body == null) return;
    try {
      await widget.addRate!(body);
      await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo guardar la tasa.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tasas de cambio'),
      actions: [
        if (widget.refreshRates != null)
          IconButton(
            tooltip: 'Actualizar desde el servicio externo',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.sync),
          ),
        if (widget.addRate != null)
          IconButton(
            tooltip: 'Registrar tasa manual',
            onPressed: _add,
            icon: const Icon(Icons.add),
          ),
      ],
    ),
    body: ListView(
      children: [
        if (_loading || _refreshing) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Conversor', style: Theme.of(context).textTheme.titleMedium),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Monto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _from,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'De'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _to,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'A'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _convert, child: const Text('Convertir')),
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_result!, key: const ValueKey('conversion')),
                ),
            ],
          ),
        ),
        const Divider(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_rates.isEmpty && !_loading && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Todavía no hay tasas registradas.')),
          ),
        for (final rate in _rates)
          ListTile(
            dense: true,
            title: Text(
              '1 ${rate['base_currency_code']} = ${rate['rate']} ${rate['quote_currency_code']}',
            ),
            subtitle: Text(
              '${'${rate['effective_at'] ?? ''}'.split('T').first} · ${rate['source'] ?? ''}',
            ),
          ),
      ],
    ),
  );
}

/// Diálogo de tasa manual: devuelve el cuerpo de `POST /payments/exchange-rates`.
class _RateDialog extends StatefulWidget {
  const _RateDialog();

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  static final _code = RegExp(r'^[A-Z]{3}$');

  final _formKey = GlobalKey<FormState>();
  final _base = TextEditingController(text: 'USD');
  final _quote = TextEditingController();
  final _rate = TextEditingController();

  @override
  void dispose() {
    _base.dispose();
    _quote.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar tasa manual'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _base,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Moneda base'),
            validator: (v) => _code.hasMatch((v ?? '').trim().toUpperCase())
                ? null
                : 'Usa un código de 3 letras.',
          ),
          TextFormField(
            controller: _quote,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Moneda destino'),
            validator: (v) {
              final text = (v ?? '').trim().toUpperCase();
              if (!_code.hasMatch(text)) return 'Usa un código de 3 letras.';
              return text == _base.text.trim().toUpperCase()
                  ? 'Debe ser distinta de la base.'
                  : null;
            },
          ),
          TextFormField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tasa (1 base = x destino)',
            ),
            validator: (v) {
              final parsed = num.tryParse(
                (v ?? '').trim().replaceAll(',', '.'),
              );
              return parsed == null || parsed <= 0
                  ? 'Indica una tasa mayor que cero.'
                  : null;
            },
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
          Navigator.pop(context, {
            'base_currency_code': _base.text.trim().toUpperCase(),
            'quote_currency_code': _quote.text.trim().toUpperCase(),
            'rate': num.parse(_rate.text.trim().replaceAll(',', '.')),
            'source': 'manual',
          });
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
