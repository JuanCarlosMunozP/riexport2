import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/features/farms/presentation/farm_list_screen.dart';
import 'package:riexport_app/features/farms/presentation/farms_map_screen.dart';
import 'package:riexport_app/features/farms/presentation/lot_screens.dart';

Widget _noTiles() => const SizedBox.expand();

Map<String, dynamic> _farm(int id, String name, {Object? lat, Object? lon}) => {
  'id': id,
  'name': name,
  'supplier_name': 'Proveedor Uno',
  'country_code': 'CO',
  'latitude': lat,
  'longitude': lon,
};

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('locatedFarms descarta las fincas sin punto completo', () {
    final farms = [
      _farm(1, 'A', lat: 2.5, lon: -75.5),
      _farm(2, 'B'),
      _farm(3, 'C', lat: 2.5),
      _farm(4, 'D', lat: 0, lon: -78.5),
    ];
    expect(locatedFarms(farms).map((f) => f['id']), [1, 4]);
  });

  group('mapa de fincas', () {
    Widget screen(List<Map<String, dynamic>> farms) => MaterialApp(
      home: FarmsMapScreen(farms: farms, tileLayerBuilder: _noTiles),
    );

    testWidgets(
      'dibuja un marcador por finca con punto y avisa de las que no tienen',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(
          screen([
            _farm(1, 'Norte', lat: 6.2, lon: -75.5),
            _farm(2, 'Sur', lat: 1.2, lon: -77.3),
            _farm(3, 'Sin punto'),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.location_on), findsNWidgets(2));
        expect(
          find.text('2 fincas en el mapa. Toca una para ver sus datos.'),
          findsOneWidget,
        );
        expect(
          find.text('1 finca sin geolocalización no se muestra.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tocar un marcador muestra los datos de la finca y tocar el mapa los oculta',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(
          screen([
            _farm(1, 'Norte', lat: 6.2, lon: -75.5),
            _farm(2, 'Sur', lat: 1.2, lon: -77.3),
          ]),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.location_on).first);
        await tester.pumpAndSettle();
        expect(find.text('Norte'), findsOneWidget);
        expect(find.textContaining('Proveedor Uno'), findsOneWidget);
        expect(find.textContaining('6.2, -75.5'), findsOneWidget);
      },
    );

    testWidgets('una sola finca centra el mapa en ella', (tester) async {
      _view(tester);
      await tester.pumpWidget(
        screen([_farm(1, 'Norte', lat: 6.2, lon: -75.5)]),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(
        find.text('1 finca en el mapa. Tócala para ver sus datos.'),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('varias fincas en el mismo punto no rompen el encuadre', (
      tester,
    ) async {
      _view(tester);
      await tester.pumpWidget(
        screen([
          _farm(1, 'A', lat: 6.2, lon: -75.5),
          _farm(2, 'B', lat: 6.2, lon: -75.5),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    });

    testWidgets(
      'sin ninguna finca geolocalizada lo dice y no dibuja marcadores',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(screen([_farm(1, 'A'), _farm(2, 'B')]));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.location_on), findsNothing);
        expect(
          find.text('Ninguna finca tiene geolocalización.'),
          findsOneWidget,
        );
        expect(
          find.text('2 fincas sin geolocalización no se muestran.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('sin fincas no falla', (tester) async {
      _view(tester);
      await tester.pumpWidget(screen(const []));
      await tester.pumpAndSettle();
      expect(find.text('Ninguna finca tiene geolocalización.'), findsOneWidget);
    });
  });

  group('carga del mapa', () {
    testWidgets('muestra el error con reintento y luego el mapa', (
      tester,
    ) async {
      _view(tester);
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: FarmsMapLoader(
            tileLayerBuilder: _noTiles,
            loadFarms: () async {
              if (fail) {
                throw const ApiException(
                  statusCode: 403,
                  code: 'FORBIDDEN',
                  message: 'No tienes permiso.',
                );
              }
              return [_farm(1, 'Norte', lat: 6.2, lon: -75.5)];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No tienes permiso.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });
  });

  testWidgets('la lista de fincas ofrece ver el mapa', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FarmListScreen(
          loadFarms:
              ({required limit, required offset, query, isActive}) async => {
                'items': <Map<String, Object?>>[],
                'pagination': {'total': 0, 'limit': 20, 'offset': 0},
              },
          loadPermissions: () async => {'farms.read'},
          openMap: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ver fincas en el mapa'));
    expect(opened, 1);
  });

  group('mapa de trazabilidad', () {
    Map<String, dynamic> line(
      int farmId,
      String lot, {
      num? quantity,
      Object? lat = 6.2,
      Object? lon = -75.5,
    }) => {
      'farm_id': farmId,
      'farm_name': 'Finca $farmId',
      'supplier_name': 'Proveedor Uno',
      'country_code': 'CO',
      'latitude': lat,
      'longitude': lon,
      'lot_code': lot,
      'product_variety': 'Caturra',
      'quantity': quantity,
    };

    test('agrupa las lineas por finca con un detalle por lote', () {
      final grouped = groupTraceability([
        line(1, 'N-1', quantity: 100),
        line(1, 'N-2', quantity: 50.5),
        line(2, 'S-1', lat: 1.2, lon: -77.3),
      ]);
      expect(grouped.farms.map((f) => f['name']), ['Finca 1', 'Finca 2']);
      expect(grouped.details[1], [
        'Lote N-1 · Caturra · 100 kg',
        'Lote N-2 · Caturra · 50.5 kg',
      ]);
      expect(grouped.details[2], [
        'Lote S-1 · Caturra',
      ], reason: 'sin cantidad no se inventa una');
    });

    testWidgets(
      'dibuja las fincas de origen y al tocar una muestra sus lotes',
      (tester) async {
        _view(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: TraceabilityMapScreen(
              tileLayerBuilder: _noTiles,
              lines: [
                line(1, 'N-1', quantity: 100),
                line(1, 'N-2', quantity: 50.5),
                line(2, 'S-1', lat: 1.2, lon: -77.3),
                line(3, 'X-1', lat: null, lon: null),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.location_on), findsNWidgets(2));
        expect(
          find.text('1 finca sin geolocalización no se muestra.'),
          findsOneWidget,
        );
        await tester.tap(find.byIcon(Icons.location_on).first);
        await tester.pumpAndSettle();
        expect(find.text('Finca 1'), findsOneWidget);
        expect(find.text('Lote N-1 · Caturra · 100 kg'), findsOneWidget);
        expect(find.text('Lote N-2 · Caturra · 50.5 kg'), findsOneWidget);
      },
    );

    testWidgets('un lote cuya finca no tiene punto no dibuja marcadores', (
      tester,
    ) async {
      _view(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: TraceabilityMapScreen(
            tileLayerBuilder: _noTiles,
            lines: [line(1, 'X-1', lat: null, lon: null)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.location_on), findsNothing);
      expect(find.text('Ninguna finca tiene geolocalización.'), findsOneWidget);
    });
  });

  group('origen del lote desde la lista', () {
    Map<String, Object?> lot(int id, {Object? lat, Object? lon}) => {
      'id': id,
      'lot_code': 'L-$id',
      'product_type': 'coffee',
      'product_variety': 'Caturra',
      'product_quality': 'Excelso',
      'farm_name': 'Finca',
      'supplier_name': 'Proveedor',
      'latitude': lat,
      'longitude': lon,
    };

    testWidgets('el boton abre el origen solo si la finca tiene punto', (
      tester,
    ) async {
      _view(tester);
      Map<String, dynamic>? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: LotListScreen(
            loadPermissions: () async => {'lots.read'},
            openOrigin: (lot) => opened = lot,
            loadLots: ({required limit, required offset, query}) async => {
              'items': [lot(1, lat: 2.5, lon: -75.5), lot(2)],
              'pagination': {'total': 2, 'limit': 20, 'offset': 0},
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final buttons = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Ver origen en el mapa',
      );
      expect(buttons, findsNWidgets(2));
      expect(tester.widget<IconButton>(buttons.last).onPressed, isNull);
      await tester.tap(buttons.first);
      expect(opened?['lot_code'], 'L-1');
    });
  });
}
