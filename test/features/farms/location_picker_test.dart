import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:riexport_app/features/farms/presentation/farm_form_screen.dart';
import 'package:riexport_app/features/farms/presentation/location_picker_screen.dart';

/// Sin red: la capa de mosaicos se sustituye por un widget vacío.
Widget _noTiles() => const SizedBox.expand();

Future<void> _openPicker(
  WidgetTester tester, {
  double? latitude,
  double? longitude,
  required void Function(PickedPoint?) onResult,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => onResult(
                await Navigator.of(context).push<PickedPoint>(
                  MaterialPageRoute(
                    builder: (_) => LocationPickerScreen(
                      initialLatitude: latitude,
                      initialLongitude: longitude,
                      tileLayerBuilder: _noTiles,
                    ),
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Toque sostenido un instante y espera del doble toque: así lo reconoce flutter_map.
Future<void> _tapMap(WidgetTester tester, [Offset shift = Offset.zero]) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(FlutterMap)) + shift,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  group('normalizePoint', () {
    test('redondea a 6 decimales', () {
      final point = normalizePoint(const LatLng(2.1234567, -75.6543214));
      expect(point.latitude, 2.123457);
      expect(point.longitude, -75.654321);
    });

    test('lleva la longitud del mapa repetido a -180..180', () {
      expect(normalizePoint(const LatLng(10, 190)).longitude, -170);
      expect(normalizePoint(const LatLng(10, -190)).longitude, 170);
      expect(normalizePoint(const LatLng(10, 360)).longitude, 0);
      expect(normalizePoint(const LatLng(10, 180)).longitude, -180);
      expect(normalizePoint(const LatLng(10, -75.5)).longitude, -75.5);
    });

    test('acota la latitud a -90..90', () {
      expect(normalizePoint(const LatLng(91, 10)).latitude, 90);
      expect(normalizePoint(const LatLng(-95, 10)).latitude, -90);
    });

    test('todo punto normalizado pasa la validacion del formulario', () {
      for (final raw in const [
        LatLng(2.1234567, -75.6543214),
        LatLng(-33.9, 540.2),
        LatLng(89.9999999, -179.9999999),
        LatLng(-91, 200),
      ]) {
        final point = normalizePoint(raw);
        expect(
          validateCoordinate('${point.latitude}', 'La latitud', 90),
          isNull,
        );
        expect(
          validateCoordinate('${point.longitude}', 'La longitud', 180),
          isNull,
        );
      }
    });
  });

  group('selector de ubicacion', () {
    testWidgets('sin punto: pide tocar el mapa y no deja confirmar', (
      tester,
    ) async {
      await _openPicker(tester, onResult: (_) {});
      expect(find.text('Toca el mapa para colocar la finca.'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'tocar el mapa coloca el marcador y confirmar devuelve el punto',
      (tester) async {
        PickedPoint? result;
        var closed = false;
        await _openPicker(
          tester,
          onResult: (p) {
            result = p;
            closed = true;
          },
        );
        await _tapMap(tester);
        expect(find.byIcon(Icons.location_on), findsOneWidget);
        expect(find.textContaining('Latitud'), findsOneWidget);

        await tester.tap(find.text('Usar esta ubicación'));
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        final point = result!;
        expect(
          validateCoordinate('${point.latitude}', 'La latitud', 90),
          isNull,
        );
        expect(
          validateCoordinate('${point.longitude}', 'La longitud', 180),
          isNull,
        );
        // El centro inicial es Colombia: un toque en el centro cae cerca de ahi.
        expect(point.latitude, closeTo(4.57, 0.5));
        expect(point.longitude, closeTo(-74.3, 0.5));
      },
    );

    testWidgets('un segundo toque en otro lugar mueve el punto', (
      tester,
    ) async {
      PickedPoint? result;
      await _openPicker(tester, onResult: (p) => result = p);
      await _tapMap(tester);
      final first =
          find.textContaining('Longitud').evaluate().single.widget as Text;

      await _tapMap(tester, const Offset(150, 0));
      final second =
          find.textContaining('Longitud').evaluate().single.widget as Text;
      expect(second.data, isNot(first.data));

      await tester.tap(find.text('Usar esta ubicación'));
      await tester.pumpAndSettle();
      expect(result!.longitude, greaterThan(-74.3), reason: 'se movio al este');
    });

    testWidgets('con un punto inicial lo muestra y cancelar no devuelve nada', (
      tester,
    ) async {
      PickedPoint? result = (latitude: 1, longitude: 1);
      var closed = false;
      await _openPicker(
        tester,
        latitude: 2.535,
        longitude: -75.527,
        onResult: (p) {
          result = p;
          closed = true;
        },
      );
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.text('Latitud 2.535   Longitud -75.527'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancelar'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('confirmar sin tocar devuelve el punto inicial', (
      tester,
    ) async {
      PickedPoint? result;
      await _openPicker(
        tester,
        latitude: 2.535,
        longitude: -75.527,
        onResult: (p) => result = p,
      );
      await tester.tap(find.text('Usar esta ubicación'));
      await tester.pumpAndSettle();
      expect(result, (latitude: 2.535, longitude: -75.527));
    });
  });

  group('formulario de finca con mapa', () {
    Widget form({
      Future<PickedPoint?> Function(double?, double?)? pickLocation,
      Map<String, dynamic>? farm,
      void Function(Map<String, Object?>)? onSave,
    }) => MaterialApp(
      home: FarmFormScreen(
        farm: farm,
        pickLocation: pickLocation,
        loadSuppliers: () async => [
          {'id': 1, 'business_name': 'Proveedor Uno'},
        ],
        onSave: (fields) async => onSave?.call(fields),
      ),
    );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('sin selector de mapa no se ofrece el boton', (tester) async {
      tall(tester);
      await tester.pumpWidget(form());
      await tester.pumpAndSettle();
      expect(find.text('Elegir en el mapa'), findsNothing);
    });

    testWidgets('elegir en el mapa rellena latitud y longitud y se guardan', (
      tester,
    ) async {
      tall(tester);
      Map<String, Object?>? sent;
      double? seenLat = 99;
      await tester.pumpWidget(
        form(
          pickLocation: (lat, lon) async {
            seenLat = lat;
            return (latitude: 2.535, longitude: -75.527);
          },
          onSave: (fields) => sent = fields,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir en el mapa'));
      await tester.pumpAndSettle();
      expect(seenLat, isNull, reason: 'sin punto previo el mapa abre vacio');
      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller?.text,
        '2.535',
      );
      expect(
        tester.widget<TextFormField>(fields.at(4)).controller?.text,
        '-75.527',
      );

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedor Uno').last);
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(0), 'La Esperanza');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(sent, {
        'supplier_id': 1,
        'country_code': 'CO',
        'name': 'La Esperanza',
        'latitude': 2.535,
        'longitude': -75.527,
      });
    });

    testWidgets('parte del punto escrito si es valido y no si es invalido', (
      tester,
    ) async {
      tall(tester);
      final seen = <(double?, double?)>[];
      await tester.pumpWidget(
        form(
          pickLocation: (lat, lon) async {
            seen.add((lat, lon));
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(3), '2,5');
      await tester.enterText(fields.at(4), '-75.5');
      await tester.tap(find.text('Elegir en el mapa'));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(3), '95');
      await tester.tap(find.text('Elegir en el mapa'));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(3), '2.5');
      await tester.enterText(fields.at(4), '');
      await tester.tap(find.text('Elegir en el mapa'));
      await tester.pumpAndSettle();
      expect(seen, [(2.5, -75.5), (null, null), (null, null)]);
    });

    testWidgets('cancelar el mapa no cambia lo escrito', (tester) async {
      tall(tester);
      await tester.pumpWidget(form(pickLocation: (lat, lon) async => null));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(3), '2.5');
      await tester.enterText(fields.at(4), '-75.5');
      await tester.tap(find.text('Elegir en el mapa'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller?.text,
        '2.5',
      );
      expect(
        tester.widget<TextFormField>(fields.at(4)).controller?.text,
        '-75.5',
      );
    });

    testWidgets('en edicion, elegir en el mapa envia las coordenadas nuevas', (
      tester,
    ) async {
      tall(tester);
      Map<String, Object?>? sent;
      await tester.pumpWidget(
        form(
          farm: {
            'id': 1,
            'supplier_id': 1,
            'supplier_name': 'Proveedor Uno',
            'country_code': 'CO',
            'name': 'La Esperanza',
            'latitude': 2.535,
            'longitude': -75.527,
          },
          pickLocation: (lat, lon) async {
            expect((lat, lon), (2.535, -75.527));
            return (latitude: 4.5, longitude: -74.1);
          },
          onSave: (fields) => sent = fields,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir en el mapa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(sent, {'latitude': 4.5, 'longitude': -74.1});
    });
  });
}
