import 'package:flutter/material.dart';

/// Resumen de ejemplo para la pantalla de inicio: cifras y listas ficticias
/// del negocio de exportación de café y cacao, para que el área principal no
/// quede vacía. No se lee de ningún backend.
class DemoDashboard extends StatelessWidget {
  const DemoDashboard({super.key, required this.wide});

  final bool wide;

  static const _kpis = <_Kpi>[
    _Kpi(
      'Pedidos activos',
      '12',
      'Café y cacao en preparación',
      Icons.receipt_long_outlined,
    ),
    _Kpi(
      'Envíos en tránsito',
      '3',
      'Hamburgo, Róterdam y Amberes',
      Icons.directions_boat_outlined,
    ),
    _Kpi(
      'Stock disponible',
      '18,4 t',
      '11,2 t café · 7,2 t cacao',
      Icons.warehouse_outlined,
    ),
    _Kpi(
      'Cobros pendientes',
      'USD 84.300',
      '2 vencidos esta semana',
      Icons.account_balance_wallet_outlined,
    ),
  ];

  static const _orders = <_Row>[
    _Row(
      'PED-2026-0148',
      'Importadora Demo GmbH · 4,5 t café pergamino',
      'En preparación',
    ),
    _Row(
      'PED-2026-0147',
      'Nordic Beans AB · 2,0 t cacao fino de aroma',
      'Confirmado',
    ),
    _Row(
      'PED-2026-0145',
      'Café del Valle Ltd · 6,0 t café excelso',
      'En aduana',
    ),
    _Row('PED-2026-0141', 'Choco Atelier SA · 1,2 t cacao CCN-51', 'Entregado'),
  ];

  static const _shipments = <_Row>[
    _Row(
      'ENV-0032 · Buenaventura → Hamburgo',
      'Llegada estimada 21 nov',
      'En tránsito',
    ),
    _Row(
      'ENV-0031 · Cartagena → Róterdam',
      'Llegada estimada 18 nov',
      'En aduana',
    ),
    _Row(
      'ENV-0034 · Buenaventura → Amberes',
      'Salida planificada 28 nov',
      'Planificado',
    ),
  ];

  static const _lowStock = <_Row>[
    _Row('Café pergamino · Lote HU-114', 'Finca El Mirador, Huila', '420 kg'),
    _Row(
      'Cacao fermentado · Lote SA-032',
      'Finca La Esperanza, Santander',
      '310 kg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.eco_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text('Inicio'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Resumen de la operación · datos de ejemplo',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 900
                      ? 4
                      : (c.maxWidth >= 520 ? 2 : 1);
                  const gap = 12.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final k in _kpis)
                        SizedBox(width: w, child: _KpiCard(k)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, c) {
                  final twoCols = c.maxWidth >= 800;
                  final left = _Panel('Pedidos recientes', _orders);
                  final right = Column(
                    children: [
                      _Panel('Envíos en curso', _shipments),
                      const SizedBox(height: 12),
                      _Panel('Lotes con poco stock', _lowStock),
                    ],
                  );
                  return twoCols
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 12),
                            Expanded(child: right),
                          ],
                        )
                      : Column(
                          children: [left, const SizedBox(height: 12), right],
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value, this.hint, this.icon);

  final String label;
  final String value;
  final String hint;
  final IconData icon;
}

class _Row {
  const _Row(this.title, this.subtitle, this.trailing);

  final String title;
  final String subtitle;
  final String trailing;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.kpi);

  final _Kpi kpi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(kpi.icon, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kpi.label, style: text.labelMedium),
                  Text(kpi.value, style: text.titleLarge),
                  Text(kpi.hint, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel(this.title, this.rows);

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final r in rows)
              ListTile(
                dense: true,
                title: Text(r.title),
                subtitle: Text(r.subtitle),
                trailing: Text(
                  r.trailing,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
