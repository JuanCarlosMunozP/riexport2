import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

/// Historial comercial de un cliente: sus pedidos (con total y exportaciones) y
/// sus exportaciones. Mientras no exista el módulo de pedidos y exportaciones
/// el backend responde `available: false` y se explica en pantalla.
class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({
    super.key,
    required this.customer,
    required this.loadHistory,
  });

  final Map<String, dynamic> customer;
  final Future<Map<String, dynamic>> Function() loadHistory;

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  bool _loading = true;
  String? _error;
  bool _available = true;
  bool _exportsAvailable = true;
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _exports = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static List<Map<String, dynamic>> _maps(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
  ];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await widget.loadHistory();
      if (!mounted) return;
      setState(() {
        _available = history['available'] != false;
        _exportsAvailable = history['exports_available'] != false;
        _orders = _maps(history['orders']);
        _exports = _maps(history['exports']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No fue posible cargar el historial.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _date(Object? value) {
    final text = '$value';
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  static String _money(Object? total, Object? currency) {
    final amount = total is num
        ? total.toStringAsFixed(2)
        : (num.tryParse('$total')?.toStringAsFixed(2) ?? '$total');
    return '$amount ${currency ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: const Text('Historial comercial'),
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
            constraints: const BoxConstraints(maxWidth: 800),
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
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  Column(
                    children: [
                      Text(
                        _error!,
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
                else if (!_available)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'El historial comercial estará disponible cuando se '
                      'activen los módulos de pedidos y exportaciones.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                else ...[
                  _Section(
                    title: 'Pedidos',
                    empty: 'Este cliente aún no tiene pedidos.',
                    children: [
                      for (final order in _orders)
                        _Row(
                          icon: Icons.receipt_long_outlined,
                          title: '${order['order_number'] ?? ''}',
                          subtitle: [
                            _date(order['created_at']),
                            '${order['status'] ?? ''}',
                            _money(
                              order['order_total'],
                              order['currency_code'],
                            ),
                            if (order['export_count'] is num &&
                                (order['export_count'] as num) > 0)
                              '${order['export_count']} exportación(es)',
                          ].where((t) => t.trim().isNotEmpty).join('  ·  '),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Section(
                    title: 'Exportaciones',
                    empty: _exportsAvailable
                        ? 'Este cliente aún no tiene exportaciones.'
                        : 'El historial de exportaciones aún no está disponible.',
                    children: [
                      for (final export in _exports)
                        _Row(
                          icon: Icons.local_shipping_outlined,
                          title:
                              '${export['order_number'] ?? ''} → ${export['destination_country_code'] ?? ''}',
                          subtitle: [
                            _date(export['export_date']),
                            '${export['status'] ?? ''}',
                          ].where((t) => t.trim().isNotEmpty).join('  ·  '),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.children,
  });

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (children.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(empty, style: const TextStyle(color: Color(0xFF68736E))),
        )
      else
        ...children,
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE2E3DC))),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF35574A)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF253C33),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF68736E), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
