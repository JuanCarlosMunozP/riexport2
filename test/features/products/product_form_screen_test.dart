import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/products/presentation/product_form_screen.dart';

const _certs = [
  {'id': 1, 'code': 'ORGANIC', 'name': 'Orgánico', 'is_active': true},
  {'id': 2, 'code': 'FAIR_TRADE', 'name': 'Fair Trade', 'is_active': true},
  {'id': 9, 'code': 'LEGACY', 'name': 'Sello heredado', 'is_active': false},
];
const _units = [
  {'code': 'kg', 'name': 'Kilogramo'},
  {'code': 't', 'name': 'Tonelada métrica'},
];

Widget _form({Map<String, dynamic>? product, required SaveProduct onSave}) =>
    MaterialApp(
      home: ProductFormScreen(
        product: product,
        loadCertifications: () async => [
          for (final c in _certs) Map<String, dynamic>.from(c),
        ],
        loadUnits: () async => [
          for (final u in _units) Map<String, dynamic>.from(u),
        ],
        onSave: onSave,
      ),
    );

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(700, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _cafe = {
  'id': 4,
  'type': 'coffee',
  'variety': 'Caturra',
  'quality_grade': 'Excelso',
  'hs_code': '0901.11',
  'base_unit_code': 'kg',
  'low_stock_threshold': 500,
  'humidity_percent': 11.5,
  'certification_ids': [1, 9],
};

void main() {
  // Campos del café: 0 variedad, 1 calidad, 2 HS, 3 umbral, 4 humedad.
  testWidgets(
    'registra un cafe: valida obligatorios y rangos y envia el payload',
    (tester) async {
      _tallView(tester);
      Map<String, Object?>? sent;
      List<int>? certs;
      await tester.pumpWidget(
        _form(
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async {
                sent = fields;
                certs = certificationIds;
              },
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);

      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.text('La variedad es obligatoria.'), findsOneWidget);
      expect(find.text('La calidad es obligatoria.'), findsOneWidget);
      expect(find.text('La humedad es obligatoria.'), findsOneWidget);
      expect(sent, isNull);

      await tester.enterText(fields.at(0), ' Caturra ');
      await tester.enterText(fields.at(1), 'Excelso');
      await tester.enterText(fields.at(2), '09');
      await tester.enterText(fields.at(3), '-5');
      await tester.enterText(fields.at(4), '101');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(
        find.text('El código HS no tiene un formato válido.'),
        findsOneWidget,
      );
      expect(find.text('No puede ser negativo.'), findsOneWidget);
      expect(find.text('Debe estar entre 0 y 100.'), findsOneWidget);

      await tester.enterText(fields.at(2), '0901.11');
      await tester.enterText(fields.at(3), '500');
      await tester.enterText(fields.at(4), '11,5'); // coma decimal
      await tester.tap(find.text('Orgánico'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(sent, {
        'type': 'coffee',
        'base_unit_code': 'kg',
        'variety': 'Caturra',
        'quality_grade': 'Excelso',
        'hs_code': '0901.11',
        'low_stock_threshold': 500,
        'humidity_percent': 11.5,
      });
      expect(certs, [1]);
    },
  );

  testWidgets('registra un cacao con sus campos propios', (tester) async {
    _tallView(tester);
    Map<String, Object?>? sent;
    await tester.pumpWidget(
      _form(
        onSave:
            ({
              required fields,
              required certificationIds,
              required certificationsChanged,
            }) async => sent = fields,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cacao'));
    await tester.pumpAndSettle();
    expect(find.text('Humedad (%)'), findsNothing);
    expect(find.text('Tipo de grano'), findsOneWidget);
    expect(find.text('Fermentación (%)'), findsOneWidget);

    final fields = find.byType(TextFormField);
    // 0 variedad, 1 calidad, 2 HS, 3 umbral, 4 grano, 5 fermentación
    await tester.enterText(fields.at(0), 'Criollo');
    await tester.enterText(fields.at(1), 'Premium');
    await tester.enterText(fields.at(4), 'Criollo fino');
    await tester.enterText(fields.at(5), '120');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Debe estar entre 0 y 100.'), findsOneWidget);
    expect(sent, isNull);

    await tester.enterText(fields.at(5), '85');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(sent, {
      'type': 'cacao',
      'base_unit_code': 'kg',
      'variety': 'Criollo',
      'quality_grade': 'Premium',
      'bean_type': 'Criollo fino',
      'fermentation_percent': 85,
    });
  });

  testWidgets(
    'en edicion el tipo y la unidad no cambian y solo se envia lo modificado',
    (tester) async {
      _tallView(tester);
      Map<String, Object?>? sent;
      bool? certsChanged;
      await tester.pumpWidget(
        _form(
          product: Map<String, dynamic>.from(_cafe),
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async {
                sent = fields;
                certsChanged = certificationsChanged;
              },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar producto'), findsOneWidget);
      expect(
        find.text('El tipo no se puede cambiar una vez registrado.'),
        findsOneWidget,
      );
      expect(find.text('La unidad base no se puede cambiar.'), findsOneWidget);
      final segmented = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(segmented.onSelectionChanged, isNull);
      // La certificación inactiva ya asignada se muestra para poder quitarla.
      expect(find.text('Sello heredado (inactiva)'), findsOneWidget);

      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller?.text,
        '500',
      );
      expect(
        tester.widget<TextFormField>(fields.at(4)).controller?.text,
        '11.5',
      );
      await tester.enterText(fields.at(1), 'Supremo');
      await tester.enterText(fields.at(2), '');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(sent, {'quality_grade': 'Supremo', 'hs_code': null});
      expect(certsChanged, isFalse);
    },
  );

  testWidgets(
    'quitar una certificacion marca el cambio aunque no cambie otro campo',
    (tester) async {
      _tallView(tester);
      Map<String, Object?>? sent;
      List<int>? certs;
      bool? changed;
      await tester.pumpWidget(
        _form(
          product: Map<String, dynamic>.from(_cafe),
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async {
                sent = fields;
                certs = certificationIds;
                changed = certificationsChanged;
              },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sello heredado (inactiva)'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(certs, [1]);
      expect(changed, isTrue);
    },
  );

  testWidgets(
    'muestra el error del servidor al guardar sin cerrar la pantalla',
    (tester) async {
      _tallView(tester);
      var calls = 0;
      await tester.pumpWidget(
        _form(
          product: Map<String, dynamic>.from(_cafe),
          onSave:
              ({
                required fields,
                required certificationIds,
                required certificationsChanged,
              }) async {
                calls++;
                throw const ApiException(
                  statusCode: 409,
                  code: 'CONFLICT',
                  message:
                      'Ya existe un producto con ese tipo, variedad y calidad.',
                );
              },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Castillo');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text('Ya existe un producto con ese tipo, variedad y calidad.'),
        findsOneWidget,
      );
      expect(find.text('Guardar'), findsOneWidget); // la pantalla sigue abierta
    },
  );
}
