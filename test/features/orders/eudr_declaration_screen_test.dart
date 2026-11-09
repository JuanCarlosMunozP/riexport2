import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/features/orders/presentation/eudr_declaration_screen.dart';
import 'package:riexport_app/features/orders/presentation/export_history_screen.dart';

void main() {
  testWidgets('muestra una declaración EUDR válida con sus fincas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EudrDeclarationScreen(
          exportId: 7,
          loadDeclaration: (id) async => {
            'declaration_date': '2026-10-30',
            'destination_country_code': 'DE',
            'line_count': 1,
            'farm_count': 1,
            'supplier_count': 1,
            'traceability_valid': true,
            'issues': <String>[],
            'hs_codes': ['0901.11'],
            'origin_farms': [
              {
                'farm_name': 'Finca La Esperanza',
                'supplier_name': 'Café SA',
                'country_code': 'CO',
                'latitude': 4.5,
                'longitude': -75.6,
                'total_quantity': 10,
                'lot_count': 1,
              },
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Trazabilidad completa'), findsOneWidget);
    expect(find.text('0901.11'), findsOneWidget);
    expect(find.text('Finca La Esperanza'), findsOneWidget);
  });

  testWidgets('avisa de los problemas cuando la trazabilidad es incompleta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EudrDeclarationScreen(
          exportId: 7,
          loadDeclaration: (id) async => {
            'traceability_valid': false,
            'issues': ['Hay líneas sin código arancelario HS.'],
            'origin_farms': <Object>[],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Trazabilidad incompleta'), findsOneWidget);
    expect(find.textContaining('sin código arancelario HS'), findsOneWidget);
  });

  testWidgets('el historial abre la EUDR y genera el PDF', (tester) async {
    int? opened;
    int? generated;
    await tester.pumpWidget(
      MaterialApp(
        home: ExportHistoryScreen(
          loadExports: ({query, status}) async => [
            {'id': 3, 'order_number': 'PED-1', 'status': 'draft'},
          ],
          onOpenEudr: (id) => opened = id,
          onGenerateDocument: (id) async {
            generated = id;
            return 'https://example.test/doc.pdf';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Declaración EUDR'));
    expect(opened, 3);
    await tester.tap(find.byTooltip('Generar PDF'));
    await tester.pumpAndSettle();
    expect(generated, 3);
    expect(find.textContaining('https://example.test/doc.pdf'), findsOneWidget);
  });
}
