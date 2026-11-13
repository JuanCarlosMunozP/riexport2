import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/orders/presentation/export_dossier_screen.dart';

Future<void> brief(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ApiException _api(String m) =>
    ApiException(statusCode: 400, code: 'e', message: m);

final _docs = <Map<String, dynamic>>[
  {
    'id': 1,
    'document_type': 'commercial_invoice',
    'document_number': 'FAC-1',
    'version': 1,
    'created_at': '2026-10-01T10:00:00Z',
    'created_by_name': 'Ana',
  },
  {
    'id': 2,
    'document_type': 'commercial_invoice',
    'document_number': 'FAC-1',
    'version': 2,
    'created_at': '2026-10-02T10:00:00Z',
  },
  {
    'id': 3,
    'document_type': 'export_summary',
    'document_number': 'RES-1',
    'version': 1,
    'created_at': '2026-10-03T10:00:00Z',
  },
  {
    'id': 4,
    'document_type': 'other_attachment',
    'original_name': 'foto.png',
    'version': 1,
    'created_at': '2026-10-04T10:00:00Z',
  },
  {
    'id': 5,
    'document_type': 'tipo_raro',
    'original_name': 'x.pdf',
    'version': 1,
    'created_at': '2026-10-05T10:00:00Z',
  },
];

void main() {
  Widget app({
    Future<List<Map<String, dynamic>>> Function(int)? load,
    Future<String?> Function(int)? download,
    Future<void> Function(int, String)? generate,
    Future<void> Function(int, String, PickedDocument)? upload,
    Future<PickedDocument?> Function()? pick,
    Future<void> Function(String)? open,
  }) => MaterialApp(
    home: ExportDossierScreen(
      exportId: 9,
      loadDocuments: load ?? (id) async => _docs,
      downloadDocument: download ?? (id) async => 'https://x.test/$id.pdf',
      generateDocument: generate,
      uploadDocument: upload,
      pickFile: pick ?? () async => null,
      openUrl: open ?? (url) async {},
    ),
  );

  testWidgets('errores de carga: API y generico, y expediente vacio', (
    tester,
  ) async {
    await tester.pumpWidget(app(load: (id) async => throw _api('Caido')));
    await tester.pumpAndSettle();
    expect(find.text('Caido'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(load: (id) async => throw StateError('x')));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar el expediente.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(load: (id) async => []));
    await tester.pumpAndSettle();
    expect(
      find.text('Esta exportación todavía no tiene documentos.'),
      findsOneWidget,
    );
  });

  testWidgets('muestra versiones, otros documentos y descarga con openUrl', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      app(
        generate: (id, type) async {},
        upload: (id, type, file) async {},
        open: (url) async => opened.add(url),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('FAC-1 · v2'), findsOneWidget);
    expect(find.textContaining('Última: RES-1'), findsOneWidget);
    expect(find.text('Otro adjunto'), findsOneWidget);
    expect(find.text('tipo_raro'), findsOneWidget);
    await tester.tap(find.byTooltip('Descargar Factura comercial'));
    await tester.pumpAndSettle();
    expect(opened, ['https://x.test/2.pdf']);
    await tester.tap(find.byTooltip('Descargar').first);
    await tester.pumpAndSettle();
    expect(opened.length, 2);
    await tester.tap(find.byTooltip('Emitir resumen de exportación'));
    await tester.pumpAndSettle();
  });

  testWidgets('si no se puede abrir el enlace ofrece copiarlo', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
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
    await tester.pumpWidget(
      app(open: (url) async => throw StateError('sin navegador')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Descargar').first);
    await tester.pumpAndSettle();
    expect(find.text('Descargar documento'), findsOneWidget);
    await tester.tap(find.text('Copiar enlace'));
    await tester.pump();
    expect(copied, isNotEmpty);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
  });

  testWidgets('descarga: sin URL no hace nada; errores de API y genericos', (
    tester,
  ) async {
    var mode = 'null';
    await tester.pumpWidget(
      app(
        download: (id) async {
          if (mode == 'api') throw _api('Expirado');
          if (mode == 'boom') throw StateError('x');
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Descargar').first);
    await brief(tester);
    expect(find.byType(SnackBar), findsNothing);
    mode = 'api';
    await tester.tap(find.byTooltip('Descargar').first);
    await brief(tester);
    expect(find.text('Expirado'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    mode = 'boom';
    await tester.tap(find.byTooltip('Descargar').first);
    await brief(tester);
    expect(find.text('No se pudo obtener el documento.'), findsOneWidget);
  });

  testWidgets('emitir: exito y errores de API y genericos', (tester) async {
    var mode = 'ok';
    final generated = <String>[];
    await tester.pumpWidget(
      app(
        load: (id) async => [],
        generate: (id, type) async {
          if (mode == 'api') throw _api('Sin pedido');
          if (mode == 'boom') throw StateError('x');
          generated.add(type);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Emitir Factura comercial'));
    await tester.pumpAndSettle();
    expect(generated, ['commercial_invoice']);
    mode = 'api';
    await tester.tap(find.byTooltip('Emitir Packing list'));
    await brief(tester);
    expect(find.text('Sin pedido'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    mode = 'boom';
    await tester.tap(find.byTooltip('Emitir Certificado de origen EUR.1'));
    await brief(tester);
    expect(find.text('No se pudo completar la operación.'), findsOneWidget);
  });

  testWidgets('adjuntar: valida tipo, tamano y sube el archivo', (tester) async {
    PickedDocument? next;
    final uploads = <String>[];
    await tester.pumpWidget(
      app(
        load: (id) async => [],
        pick: () async => next,
        upload: (id, type, file) async => uploads.add('$type:${file.name}'),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> attempt() async {
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await tester.tap(find.byTooltip('Adjuntar Certificado fitosanitario'));
      await brief(tester);
    }

    next = null;
    await attempt();
    expect(uploads, isEmpty);
    next = PickedDocument('virus.exe', Uint8List.fromList([1]));
    await attempt();
    expect(find.text('Solo se aceptan archivos PDF, PNG o JPEG.'), findsOneWidget);
    next = PickedDocument('vacio.pdf', Uint8List(0));
    await attempt();
    expect(
      find.text('El archivo debe pesar entre 1 byte y 10 MB.'),
      findsOneWidget,
    );
    next = PickedDocument(
      'enorme.pdf',
      Uint8List(maxDossierUploadBytes + 1),
    );
    await attempt();
    expect(
      find.text('El archivo debe pesar entre 1 byte y 10 MB.'),
      findsOneWidget,
    );
    next = PickedDocument('sin_extension', Uint8List.fromList([1]));
    await attempt();
    next = PickedDocument('ok.PDF', Uint8List.fromList([1, 2]));
    await attempt();
    expect(uploads, ['phytosanitary_certificate:ok.PDF']);
    expect(find.text('Archivo adjuntado al expediente.'), findsOneWidget);
  });

  testWidgets('adjuntar otro documento desde la seccion de otros', (
    tester,
  ) async {
    final uploads = <String>[];
    await tester.pumpWidget(
      app(
        pick: () async => PickedDocument('a.png', Uint8List.fromList([1])),
        upload: (id, type, file) async => uploads.add(type),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adjuntar otro documento'));
    await brief(tester);
    expect(uploads, ['other_attachment']);
  });
}
