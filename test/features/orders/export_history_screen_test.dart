import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/features/orders/presentation/export_history_screen.dart';

void main() {
  testWidgets('lista exportaciones y filtra por estado', (tester) async {
    final calls = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ExportHistoryScreen(
          loadExports: ({query, status}) async {
            calls.add(status);
            return [
              {
                'id': 3,
                'order_number': 'PED-2026-000003',
                'customer_name': 'Cliente SA',
                'destination_country_code': 'DE',
                'export_date': '2026-10-20',
                'status': 'formalized',
                'line_count': 2,
                'document_count': 1,
              },
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PED-2026-000003'), findsOneWidget);
    expect(find.text('Formalizada'), findsOneWidget);
    expect(find.textContaining('1 documentos'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrador').last);
    await tester.pumpAndSettle();
    expect(calls, [null, 'draft']);
  });
}
