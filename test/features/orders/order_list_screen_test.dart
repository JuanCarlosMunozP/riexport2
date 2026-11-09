import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/features/orders/presentation/order_list_screen.dart';

void main() {
  testWidgets('muestra pedidos y permite confirmar uno en borrador', (
    tester,
  ) async {
    final orders = <Map<String, dynamic>>[
      {
        'id': 7,
        'order_number': 'PED-2026-000007',
        'status': 'draft',
        'created_at': '2026-10-17',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderListScreen(
          loadOrders: ({query, status}) async => orders
              .where(
                (order) =>
                    (status == null || order['status'] == status) &&
                    (query == null ||
                        '${order['order_number']}'.contains(query)),
              )
              .toList(),
          canTransition: true,
          transitionOrder: (id, status) async {
            expect(id, 7);
            orders.single['status'] = status;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PED-2026-000007'), findsOneWidget);
    expect(find.textContaining('Borrador'), findsOneWidget);
    await tester.tap(find.byTooltip('Cambiar estado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Confirmado'), findsOneWidget);
  });

  testWidgets('filtra por texto y estado y muestra datos relacionados', (
    tester,
  ) async {
    final calls = <(String?, String?)>[];
    final orders = <Map<String, dynamic>>[
      {
        'id': 8,
        'order_number': 'PED-2026-000008',
        'customer_name': 'Finca Andina',
        'status': 'confirmed',
        'created_at': '2026-10-18',
        'line_count': 1,
        'order_total': 250,
        'currency_code': 'EUR',
        'lines': [
          {'lot_code': 'LOTE-A', 'quantity': 5, 'unit_price': 50},
        ],
      },
      {
        'id': 9,
        'order_number': 'PED-2026-000009',
        'customer_name': 'Otro',
        'status': 'draft',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderListScreen(
          loadOrders: ({query, status}) async {
            calls.add((query, status));
            return orders
                .where(
                  (order) =>
                      (status == null || order['status'] == status) &&
                      (query == null ||
                          '${order['customer_name']}'.toLowerCase().contains(
                            query.toLowerCase(),
                          ) ||
                          '${order['order_number']}'.contains(query)),
                )
                .toList();
          },
          transitionOrder: (_, _) async {},
          canTransition: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Finca Andina'), findsOneWidget);
    expect(find.textContaining('LOTE-A'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('orders-search')), 'Andina');
    await tester.pumpAndSettle();
    expect(find.text('PED-2026-000008'), findsOneWidget);
    expect(find.text('PED-2026-000009'), findsNothing);
    await tester.tap(find.byKey(const Key('orders-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmado').last);
    await tester.pumpAndSettle();
    expect(calls.last, ('Andina', 'confirmed'));
    expect(find.textContaining('Total: 250 EUR'), findsOneWidget);
  });

  testWidgets('mantiene el estado cuando falla la transición', (tester) async {
    final orders = <Map<String, dynamic>>[
      {'id': 10, 'order_number': 'PED-10', 'status': 'draft'},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderListScreen(
          loadOrders: ({query, status}) async => orders,
          transitionOrder: (_, _) async => throw StateError('offline'),
          canTransition: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cambiar estado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Borrador'), findsOneWidget);
    expect(find.text('No se pudo cambiar el estado.'), findsOneWidget);
  });

  testWidgets('pide confirmación antes de cancelar y actualiza al aceptar', (
    tester,
  ) async {
    final orders = <Map<String, dynamic>>[
      {'id': 11, 'order_number': 'PED-11', 'status': 'draft'},
    ];
    var transitionCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OrderListScreen(
          loadOrders: ({query, status}) async => orders,
          transitionOrder: (_, status) async {
            transitionCalls++;
            orders.single['status'] = status;
          },
          canTransition: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cambiar estado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar pedido').first);
    await tester.pumpAndSettle();
    expect(transitionCalls, 0);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Borrador'), findsOneWidget);
    await tester.tap(find.byTooltip('Cambiar estado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar pedido').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar pedido').last);
    await tester.pumpAndSettle();
    expect(transitionCalls, 1);
    expect(find.textContaining('Cancelado'), findsOneWidget);
  });

  testWidgets('ofrece editar solamente pedidos en borrador', (tester) async {
    final orders = <Map<String, dynamic>>[
      {'id': 12, 'order_number': 'PED-12', 'status': 'draft'},
      {'id': 13, 'order_number': 'PED-13', 'status': 'confirmed'},
    ];
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: OrderListScreen(
          loadOrders: ({query, status}) async => orders,
          transitionOrder: (_, _) async {},
          canTransition: false,
          canEdit: true,
          onEditOrder: (order) => selected = order,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menus = find.byTooltip('Cambiar estado');
    expect(menus, findsOneWidget);
    await tester.tap(menus.first);
    await tester.pumpAndSettle();
    expect(find.text('Editar pedido'), findsOneWidget);
    await tester.tap(find.text('Editar pedido'));
    await tester.pumpAndSettle();
    expect(selected?['id'], 12);
  });
}
