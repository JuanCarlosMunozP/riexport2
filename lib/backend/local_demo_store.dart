import 'local_backend_store.dart';

/// Datos FICTICIOS de demostración para el modo local (sin Supabase): envíos con su línea de tiempo,
/// cartera de pagos, tasas de cambio y notificaciones. Reflejan lo que carga `database/seeds/demo/seed_demo.sql`
/// y viven solo en memoria: se pierden al cerrar la app.
class LocalDemoStore {
  LocalDemoStore() {
    final now = DateTime.now().toUtc();
    String ago(Duration d) => now.subtract(d).toIso8601String();
    String day(int offset) =>
        now.add(Duration(days: offset)).toIso8601String().split('T').first;

    _shipments.addAll([
      {
        'id': 1,
        'export_id': 1,
        'order_id': 1,
        'order_number': 'PED-DEMO-0001',
        'customer_id': 1,
        'customer_name': 'Importadora Demo GmbH',
        'carrier': 'Maersk (Demo)',
        'tracking_number': 'MSKU-DEMO-0001',
        'status': 'in_customs',
        'transport_mode': 'sea',
        'container_number': 'MSKU1234567',
        'shipped_at': ago(const Duration(days: 18)),
        'estimated_delivery_at': day(6),
        'delivered_at': null,
        'created_at': ago(const Duration(days: 20)),
      },
      {
        'id': 2,
        'export_id': 2,
        'order_id': 2,
        'order_number': 'PED-DEMO-0002',
        'customer_id': 2,
        'customer_name': 'Specialty Roasters Inc. (Demo)',
        'carrier': 'DHL Global Forwarding (Demo)',
        'tracking_number': 'DHL-DEMO-4521',
        'status': 'in_transit',
        'transport_mode': 'air',
        'container_number': null,
        'shipped_at': ago(const Duration(days: 3)),
        'estimated_delivery_at': day(2),
        'delivered_at': null,
        'created_at': ago(const Duration(days: 5)),
      },
      {
        'id': 3,
        'export_id': 3,
        'order_id': 3,
        'order_number': 'PED-DEMO-0003',
        'customer_id': 3,
        'customer_name': 'Koffie Import B.V. (Demo)',
        'carrier': 'MSC (Demo)',
        'tracking_number': 'MSC-DEMO-7788',
        'status': 'planned',
        'transport_mode': 'sea',
        'container_number': 'MSCU7654321',
        'shipped_at': null,
        'estimated_delivery_at': day(30),
        'delivered_at': null,
        'created_at': ago(const Duration(days: 1)),
      },
    ]);

    int eventId = 0;
    void event(
      int shipment,
      String type,
      String text,
      String place,
      Duration d,
    ) {
      _events.add({
        'id': ++eventId,
        'shipment_id': shipment,
        'event_type': type,
        'description': text,
        'location': place,
        'event_at': ago(d),
      });
    }

    event(
      1,
      'planned',
      'Envío planificado con la naviera.',
      'Cartagena, Colombia',
      const Duration(days: 20),
    );
    event(
      1,
      'in_transit',
      'Contenedor cargado y buque zarpado.',
      'Cartagena, Colombia',
      const Duration(days: 18),
    );
    event(
      1,
      'incident',
      'Retraso de 2 días por congestión en puerto.',
      'Algeciras, España',
      const Duration(days: 7),
    );
    event(
      1,
      'in_customs',
      'En despacho de aduana de destino.',
      'Hamburgo, Alemania',
      const Duration(days: 1),
    );
    event(
      2,
      'planned',
      'Reserva de carga aérea confirmada.',
      'Bogotá, Colombia',
      const Duration(days: 5),
    );
    event(
      2,
      'in_transit',
      'Carga despachada en vuelo directo.',
      'Bogotá, Colombia',
      const Duration(days: 3),
    );
    event(
      3,
      'planned',
      'Envío planificado; pendiente de embarque.',
      'Buenaventura, Colombia',
      const Duration(days: 1),
    );
    _nextEventId = eventId + 1;

    _obligations.addAll([
      _obligation(
        1,
        1,
        'PED-DEMO-0001',
        1,
        'Importadora Demo GmbH',
        5760,
        'EUR',
        day(15),
        'FAC-DEMO-001 (café Castillo)',
        2880,
        ago(const Duration(days: 15)),
      ),
      _obligation(
        2,
        2,
        'PED-DEMO-0002',
        2,
        'Specialty Roasters Inc. (Demo)',
        10440,
        'USD',
        day(-6),
        'FAC-DEMO-002 (Geisha)',
        3000,
        ago(const Duration(days: 10)),
      ),
      _obligation(
        3,
        3,
        'PED-DEMO-0003',
        3,
        'Koffie Import B.V. (Demo)',
        13570,
        'EUR',
        day(40),
        'FAC-DEMO-003 (cacao Criollo)',
        0,
        null,
      ),
      _obligation(
        4,
        1,
        'PED-DEMO-0001',
        1,
        'Importadora Demo GmbH',
        800,
        'EUR',
        day(-12),
        'Flete y seguro demo',
        800,
        ago(const Duration(days: 11)),
      ),
    ]);

    _rates.addAll([
      {
        'id': 3,
        'base_currency_code': 'USD',
        'quote_currency_code': 'GBP',
        'rate': 0.79,
        'effective_at': ago(const Duration(days: 1)),
        'source': 'demo',
      },
      {
        'id': 2,
        'base_currency_code': 'USD',
        'quote_currency_code': 'COP',
        'rate': 4100,
        'effective_at': ago(const Duration(days: 1)),
        'source': 'demo',
      },
      {
        'id': 1,
        'base_currency_code': 'USD',
        'quote_currency_code': 'EUR',
        'rate': 0.92,
        'effective_at': ago(const Duration(days: 1)),
        'source': 'demo',
      },
    ]);

    _notifications.addAll([
      {
        'id': 5,
        'notification_type': 'payment_overdue',
        'title': 'Pago vencido: FAC-DEMO-002',
        'body': 'La obligación de 10440.00 USD venció hace 6 días.',
        'entity_type': 'payment_obligation',
        'entity_id': 2,
        'created_at': ago(const Duration(hours: 2)),
        'read_at': null,
      },
      {
        'id': 4,
        'notification_type': 'low_stock',
        'title': 'Stock bajo: Geisha (Demo)',
        'body': 'Quedan 80 kg, por debajo del umbral de 100 kg.',
        'entity_type': 'product_lot',
        'entity_id': 2,
        'created_at': ago(const Duration(hours: 5)),
        'read_at': null,
      },
      {
        'id': 3,
        'notification_type': 'shipment_status',
        'title': 'Envío DHL-DEMO-4521 en tránsito',
        'body': 'Entrega estimada en 2 días.',
        'entity_type': 'shipment',
        'entity_id': 2,
        'created_at': ago(const Duration(hours: 3)),
        'read_at': null,
      },
      {
        'id': 2,
        'notification_type': 'shipment_status',
        'title': 'Envío MSKU-DEMO-0001 en aduana',
        'body': 'El contenedor está en despacho en Hamburgo.',
        'entity_type': 'shipment',
        'entity_id': 1,
        'created_at': ago(const Duration(days: 1)),
        'read_at': ago(const Duration(hours: 20)),
      },
    ]);
    _nextNotificationId = 6;
  }

  static const statuses = <Map<String, Object?>>[
    {
      'code': 'planned',
      'label': 'Planificado',
      'sort_order': 1,
      'is_terminal': false,
    },
    {
      'code': 'in_transit',
      'label': 'En tránsito',
      'sort_order': 2,
      'is_terminal': false,
    },
    {
      'code': 'in_customs',
      'label': 'En aduana',
      'sort_order': 3,
      'is_terminal': false,
    },
    {
      'code': 'delivered',
      'label': 'Entregado',
      'sort_order': 4,
      'is_terminal': true,
    },
    {
      'code': 'cancelled',
      'label': 'Cancelado',
      'sort_order': 5,
      'is_terminal': true,
    },
  ];

  static const _transitions = <String, Set<String>>{
    'planned': {'in_transit', 'cancelled'},
    'in_transit': {'in_customs', 'delivered', 'cancelled'},
    'in_customs': {'in_transit', 'delivered', 'cancelled'},
  };

  final List<Map<String, Object?>> _shipments = [];
  final List<Map<String, Object?>> _events = [];
  final List<Map<String, Object?>> _obligations = [];
  final List<Map<String, Object?>> _rates = [];
  final List<Map<String, Object?>> _notifications = [];
  int _nextEventId = 1;
  int _nextNotificationId = 1;
  int _nextRateId = 100;

  static Map<String, Object?> _obligation(
    int id,
    int exportId,
    String orderNumber,
    int customerId,
    String customer,
    num due,
    String currency,
    String dueDate,
    String reference,
    num paid,
    String? lastPaid,
  ) {
    final balance = due - paid;
    final overdue =
        balance > 0 &&
        DateTime.parse(
          dueDate,
        ).isBefore(DateTime.now().toUtc().subtract(const Duration(days: 1)));
    return {
      'obligation_id': id,
      'export_id': exportId,
      'order_id': exportId,
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_name': customer,
      'amount_due': due,
      'currency_code': currency,
      'due_date': dueDate,
      'reference': reference,
      'amount_paid': paid,
      'balance': balance,
      'last_paid_at': lastPaid,
      'status': balance <= 0
          ? 'paid'
          : overdue
          ? 'overdue'
          : paid > 0
          ? 'partial'
          : 'pending',
      'days_overdue': overdue
          ? DateTime.now().toUtc().difference(DateTime.parse(dueDate)).inDays
          : 0,
    };
  }

  static Map<String, Object?> _page(List<Object?> items) => {
    'items': items,
    'pagination': {'total': items.length, 'limit': 100, 'offset': 0},
  };

  // ---- Envíos y seguimiento -------------------------------------------------

  Map<String, Object?> listShipments(Map<String, String> query) {
    final q = (query['q'] ?? '').trim().toLowerCase();
    final status = query['status'];
    final rows = _shipments.where((s) {
      if (status != null && status.isNotEmpty && s['status'] != status) {
        return false;
      }
      return q.isEmpty ||
          '${s['order_number']} ${s['customer_name']} ${s['carrier']} ${s['tracking_number']}'
              .toLowerCase()
              .contains(q);
    }).toList();
    return _page(rows);
  }

  Map<String, Object?> tracking(Map<String, String> query) {
    final id = int.tryParse(query['id'] ?? '');
    final rows = <Object?>[
      for (final s in _shipments)
        if (id == null || s['id'] == id)
          () {
            final last = _eventsOf(s['id'] as int).firstOrNull;
            return {
              'shipment_id': s['id'],
              'export_id': s['export_id'],
              'order_number': s['order_number'],
              'destination_country_code': 'DE',
              'status': s['status'],
              'status_label': _label(s['status'] as String),
              'carrier': s['carrier'],
              'tracking_number': s['tracking_number'],
              'transport_mode': s['transport_mode'],
              'shipped_at': s['shipped_at'],
              'estimated_delivery_at': s['estimated_delivery_at'],
              'delivered_at': s['delivered_at'],
              'last_event_type': last?['event_type'],
              'last_location': last?['location'],
              'last_event_at': last?['event_at'],
            };
          }(),
    ];
    return _page(rows);
  }

  List<Map<String, Object?>> _eventsOf(int shipmentId) =>
      _events.where((e) => e['shipment_id'] == shipmentId).toList()
        ..sort((a, b) => '${b['event_at']}'.compareTo('${a['event_at']}'));

  String _label(String code) =>
      statuses.firstWhere((s) => s['code'] == code)['label'] as String;

  Map<String, Object?> _shipment(int id) => _shipments.firstWhere(
    (s) => s['id'] == id,
    orElse: () =>
        throw LocalBackendError.notFound('No se encontró el envío solicitado.'),
  );

  Map<String, Object?> listEvents(int shipmentId) {
    _shipment(shipmentId);
    return _page(_eventsOf(shipmentId));
  }

  Map<String, Object?> addEvent(int shipmentId, Map<String, dynamic>? body) {
    _shipment(shipmentId);
    final type = '${body?['event_type'] ?? ''}'.trim();
    if (type.isEmpty) {
      throw LocalBackendError.validation(
        'event_type',
        'Describe el tipo de evento.',
      );
    }
    final id = _nextEventId++;
    _events.add({
      'id': id,
      'shipment_id': shipmentId,
      'event_type': type,
      'description': body?['description'],
      'location': body?['location'],
      'event_at': DateTime.now().toUtc().toIso8601String(),
    });
    return {'id': id};
  }

  Map<String, Object?> updateStatus(
    int shipmentId,
    Map<String, dynamic>? body,
  ) {
    final shipment = _shipment(shipmentId);
    final next = '${body?['status'] ?? ''}';
    final current = shipment['status'] as String;
    if (!(_transitions[current] ?? const {}).contains(next)) {
      throw LocalBackendError.conflict(
        'No se puede pasar de «${_label(current)}» a ese estado.',
      );
    }
    shipment['status'] = next;
    final now = DateTime.now().toUtc().toIso8601String();
    if (next == 'in_transit') shipment['shipped_at'] ??= now;
    if (next == 'delivered') shipment['delivered_at'] = now;
    addEvent(shipmentId, {
      'event_type': next,
      'description': body?['description'] ?? 'Estado: ${_label(next)}.',
      'location': body?['location'],
    });
    _notify(
      'shipment_status',
      'Envío ${shipment['tracking_number']}: ${_label(next)}',
      null,
      'shipment',
      shipmentId,
    );
    return {'shipment_id': shipmentId, 'status': next};
  }

  // ---- Pagos y tasas ---------------------------------------------------------

  Map<String, Object?> portfolio(Map<String, String> query) {
    final status = query['status'];
    final q = (query['q'] ?? '').trim().toLowerCase();
    final currency = (query['currency'] ?? '').toUpperCase();
    final rows = <Object?>[
      for (final o in _obligations)
        if ((status == null || status.isEmpty || o['status'] == status) &&
            (q.isEmpty ||
                '${o['order_number']} ${o['customer_name']} ${o['reference']}'
                    .toLowerCase()
                    .contains(q)))
          {
            ...o,
            if (currency.isNotEmpty) ...{
              'converted_currency': currency,
              'amount_due_converted': _convertOrNull(
                o['amount_due'] as num,
                o['currency_code'] as String,
                currency,
              ),
              'balance_converted': _convertOrNull(
                o['balance'] as num,
                o['currency_code'] as String,
                currency,
              ),
              'rate': _rate(o['currency_code'] as String, currency),
            },
          },
    ];
    return _page(rows);
  }

  num? _rate(String from, String to) {
    if (from == to) return 1;
    num? direct(String a, String b) {
      for (final r in _rates) {
        if (r['base_currency_code'] == a && r['quote_currency_code'] == b) {
          return r['rate'] as num;
        }
      }
      return null;
    }

    final d = direct(from, to);
    if (d != null) return d;
    final inverse = direct(to, from);
    if (inverse != null) return 1 / inverse;
    final fromUsd = from == 'USD'
        ? 1
        : (direct('USD', from) == null ? null : 1 / direct('USD', from)!);
    final toUsd = to == 'USD' ? 1 : direct('USD', to);
    return fromUsd == null || toUsd == null ? null : fromUsd * toUsd;
  }

  num? _convertOrNull(num amount, String from, String to) {
    final rate = _rate(from, to);
    return rate == null
        ? null
        : double.parse((amount * rate).toStringAsFixed(2));
  }

  Map<String, Object?> convert(Map<String, String> query) {
    final amount = num.tryParse(query['amount'] ?? '');
    if (amount == null) {
      throw LocalBackendError.validation('amount', 'Indica un monto numérico.');
    }
    final from = (query['from'] ?? '').toUpperCase();
    final to = (query['to'] ?? '').toUpperCase();
    final rate = _rate(from, to);
    if (rate == null) {
      throw LocalBackendError.notFound(
        'No hay tasa de cambio para $from → $to.',
      );
    }
    return {
      'converted': double.parse((amount * rate).toStringAsFixed(2)),
      'rate': rate,
      'source': 'demo',
    };
  }

  Map<String, Object?> listRates() => _page(_rates);

  Map<String, Object?> addTransaction(Map<String, dynamic>? body) {
    final id = body?['obligation_id'];
    final amount = body?['amount'];
    final o = _obligations.firstWhere(
      (o) => o['obligation_id'] == id,
      orElse: () =>
          throw LocalBackendError.notFound('No se encontró la obligación.'),
    );
    if (amount is! num || amount <= 0) {
      throw LocalBackendError.validation(
        'amount',
        'Indica un monto mayor que cero.',
      );
    }
    if (amount > (o['balance'] as num)) {
      throw LocalBackendError.conflict(
        'El pago supera el saldo de la obligación.',
      );
    }
    final index = _obligations.indexOf(o);
    _obligations[index] = _obligation(
      o['obligation_id'] as int,
      o['export_id'] as int,
      o['order_number'] as String,
      o['customer_id'] as int,
      o['customer_name'] as String,
      o['amount_due'] as num,
      o['currency_code'] as String,
      '${o['due_date']}',
      '${o['reference']}',
      (o['amount_paid'] as num) + amount,
      DateTime.now().toUtc().toIso8601String(),
    );
    return {'id': _nextRateId++};
  }

  Map<String, Object?> addObligation(Map<String, dynamic>? body) {
    final amount = body?['amount_due'];
    if (amount is! num || amount <= 0) {
      throw LocalBackendError.validation(
        'amount_due',
        'Indica un monto mayor que cero.',
      );
    }
    final exportId = body?['export_id'] as int?;
    final reference = _shipments
        .where((s) => s['export_id'] == exportId)
        .firstOrNull;
    final id = _obligations.length + 1;
    _obligations.add(
      _obligation(
        id,
        exportId ?? 0,
        '${reference?['order_number'] ?? 'PED-DEMO-$exportId'}',
        (reference?['customer_id'] as int?) ?? 0,
        '${reference?['customer_name'] ?? 'Cliente demo'}',
        amount,
        '${body?['currency_code'] ?? 'USD'}',
        '${body?['due_date'] ?? DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String().split('T').first}',
        '${body?['reference'] ?? ''}',
        0,
        null,
      ),
    );
    return {'id': id};
  }

  Map<String, Object?> addRate(Map<String, dynamic>? body) {
    final rate = body?['rate'];
    if (rate is! num || rate <= 0) {
      throw LocalBackendError.validation(
        'rate',
        'Indica una tasa mayor que cero.',
      );
    }
    final id = _nextRateId++;
    _rates.insert(0, {
      'id': id,
      'base_currency_code': body?['base_currency_code'],
      'quote_currency_code': body?['quote_currency_code'],
      'rate': rate,
      'effective_at': DateTime.now().toUtc().toIso8601String(),
      'source': body?['source'] ?? 'manual',
    });
    return {'id': id};
  }

  // ---- Notificaciones --------------------------------------------------------

  void _notify(
    String type,
    String title,
    String? body,
    String entity,
    int entityId,
  ) {
    _notifications.insert(0, {
      'id': _nextNotificationId++,
      'notification_type': type,
      'title': title,
      'body': body,
      'entity_type': entity,
      'entity_id': entityId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'read_at': null,
    });
  }

  Map<String, Object?> listNotifications(Map<String, String> query) {
    final unread = query['unread'] == 'true';
    return _page([
      for (final n in _notifications)
        if (!unread || n['read_at'] == null) n,
    ]);
  }

  Map<String, Object?> readAll() {
    var updated = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final n in _notifications) {
      if (n['read_at'] == null) {
        n['read_at'] = now;
        updated++;
      }
    }
    return {'updated': updated};
  }

  Map<String, Object?> markNotification(int id, Map<String, dynamic>? body) {
    final n = _notifications.firstWhere(
      (n) => n['id'] == id,
      orElse: () =>
          throw LocalBackendError.notFound('No se encontró la notificación.'),
    );
    n['read_at'] = body?['read_at'];
    return n;
  }
}
