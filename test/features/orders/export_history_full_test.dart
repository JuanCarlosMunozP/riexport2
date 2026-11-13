import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/orders/presentation/export_history_screen.dart';

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _row = {
  'id': 3,
  'order_number': 'PED-3',
  'customer_name': 'Cliente SA',
  'destination_country_code': 'DE',
  'export_date': '2026-10-20',
  'status': 'weird',
  'line_count': 2,
};

void main() {
  Widget app({
    required Future<List<Map<String, dynamic>>> Function({
      String? query,
      String? status,
    })
    load,
    void Function(int)? eudr,
    void Function(int)? dossier,
    Future<String?> Function(int)? generate,
  }) => MaterialApp(
    home: ExportHistoryScreen(
      loadExports: load,
      onOpenEudr: eudr,
      onOpenDossier: dossier,
      onGenerateDocument: generate,
    ),
  );

  testWidgets('errores de carga: API y generico', (tester) async {
    await tester.pumpWidget(
      app(
        load: ({query, status}) async => throw const ApiException(
          statusCode: 500,
          code: 'e',
          message: 'Caido',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caido'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      app(load: ({query, status}) async => throw StateError('x')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo cargar el historial de exportaciones.'),
      findsOneWidget,
    );
  });

  testWidgets('sin exportaciones muestra el aviso', (tester) async {
    await tester.pumpWidget(app(load: ({query, status}) async => []));
    await tester.pumpAndSettle();
    expect(find.text('No hay exportaciones registradas.'), findsOneWidget);
  });

  testWidgets('buscar con Enter y con el boton; estado desconocido en crudo', (
    tester,
  ) async {
    final queries = <String?>[];
    await tester.pumpWidget(
      app(
        load: ({query, status}) async {
          queries.add(query);
          return [Map<String, dynamic>.from(_row)];
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('weird'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'PED');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(queries.where((q) => q == 'PED'), isNotEmpty);
  });

  testWidgets('abrir EUDR y expediente desde la fila', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      app(
        load: ({query, status}) async => [Map<String, dynamic>.from(_row)],
        eudr: (id) => opened.add('eudr$id'),
        dossier: (id) => opened.add('doc$id'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Declaración EUDR'));
    await tester.tap(find.byTooltip('Expediente de documentos'));
    expect(opened, ['eudr3', 'doc3']);
  });

  testWidgets('generar PDF: con enlace (copiar) y sin enlace', (tester) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    String? url = 'https://x.test/f.pdf';
    await tester.pumpWidget(
      app(
        load: ({query, status}) async => [Map<String, dynamic>.from(_row)],
        generate: (id) async => url,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generar PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Documento generado'), findsOneWidget);
    await tester.tap(find.text('Copiar enlace'));
    await tester.pump();
    expect(clipboard.single, 'https://x.test/f.pdf');
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();

    url = null;
    await tester.tap(find.byTooltip('Generar PDF'));
    await tester.pumpAndSettle();
    expect(
      find.text('El PDF se guardó en el expediente de la exportación.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
  });

  testWidgets('generar PDF: error de API y generico', (tester) async {
    var api = true;
    await tester.pumpWidget(
      app(
        load: ({query, status}) async => [Map<String, dynamic>.from(_row)],
        generate: (id) async {
          if (api) {
            throw const ApiException(
              statusCode: 409,
              code: 'e',
              message: 'No formalizada',
            );
          }
          throw StateError('x');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generar PDF'));
    await brief(tester);
    expect(find.text('No formalizada'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    api = false;
    await tester.tap(find.byTooltip('Generar PDF'));
    await brief(tester);
    expect(find.text('No se pudo generar el documento.'), findsOneWidget);
  });
}
