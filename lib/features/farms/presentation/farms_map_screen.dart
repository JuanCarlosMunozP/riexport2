import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_exception.dart';
import 'location_picker_screen.dart' show openStreetMapTiles;

/// Fincas con coordenadas, listas para dibujar. Descarta las que no tienen punto.
List<Map<String, dynamic>> locatedFarms(Iterable<Map<String, dynamic>> farms) =>
    [
      for (final farm in farms)
        if (farm['latitude'] is num && farm['longitude'] is num) farm,
    ];

/// Mapa con las fincas indicadas: un marcador por finca y, al tocarlo, sus datos.
/// Sirve para cualquier conjunto de fincas (todas las activas hoy; las de un
/// envío o exportación cuando exista ese módulo).
class FarmsMapScreen extends StatefulWidget {
  const FarmsMapScreen({
    super.key,
    required this.farms,
    this.title = 'Fincas en el mapa',
    this.details = const {},
    this.tileLayerBuilder = openStreetMapTiles,
  });

  /// Líneas de texto extra que se muestran al tocar cada finca (clave: id de la finca).
  final Map<Object?, List<String>> details;

  final List<Map<String, dynamic>> farms;
  final String title;
  final Widget Function() tileLayerBuilder;

  @override
  State<FarmsMapScreen> createState() => _FarmsMapScreenState();
}

class _FarmsMapScreenState extends State<FarmsMapScreen> {
  Map<String, dynamic>? _selected;

  LatLng _point(Map<String, dynamic> farm) => LatLng(
    (farm['latitude'] as num).toDouble(),
    (farm['longitude'] as num).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    final located = locatedFarms(widget.farms);
    final missing = widget.farms.length - located.length;
    final points = [for (final farm in located) _point(farm)];
    final distinct = points.toSet();
    final options = distinct.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(48),
              maxZoom: 14,
            ),
            minZoom: 2,
            onTap: (_, _) => setState(() => _selected = null),
          )
        : MapOptions(
            initialCenter: points.isEmpty
                ? const LatLng(4.57, -74.3) // Colombia
                : points.first,
            initialZoom: points.isEmpty ? 5 : 12,
            minZoom: 2,
            onTap: (_, _) => setState(() => _selected = null),
          );
    final selected = _selected;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F0),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFFF6F5F0),
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/farms');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlutterMap(
                    options: options,
                    children: [
                      widget.tileLayerBuilder(),
                      MarkerLayer(
                        markers: [
                          for (final farm in located)
                            Marker(
                              point: _point(farm),
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                onTap: () => setState(() => _selected = farm),
                                child: Tooltip(
                                  message: '${farm['name']}',
                                  child: Icon(
                                    Icons.location_on,
                                    size: 44,
                                    color: identical(farm, selected)
                                        ? const Color(0xFF9B3D2D)
                                        : const Color(0xFF35574A),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const Positioned(
                    right: 8,
                    bottom: 4,
                    child: Text(
                      '© colaboradores de OpenStreetMap',
                      style: TextStyle(fontSize: 11, color: Color(0xFF34453E)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selected != null) ...[
                    Text(
                      '${selected['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${selected['supplier_name'] ?? ''}',
                        '${selected['country_code'] ?? ''}',
                        '${selected['latitude']}, ${selected['longitude']}',
                      ].where((t) => t.trim().isNotEmpty).join('  ·  '),
                      style: const TextStyle(
                        color: Color(0xFF68736E),
                        fontSize: 13,
                      ),
                    ),
                    for (final line
                        in widget.details[selected['id']] ?? const <String>[])
                      Text(
                        line,
                        style: const TextStyle(
                          color: Color(0xFF35574A),
                          fontSize: 13,
                        ),
                      ),
                  ] else
                    Text(
                      located.isEmpty
                          ? 'Ninguna finca tiene geolocalización.'
                          : located.length == 1
                          ? '1 finca en el mapa. Tócala para ver sus datos.'
                          : '${located.length} fincas en el mapa. Toca una para ver sus datos.',
                    ),
                  if (missing > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        missing == 1
                            ? '1 finca sin geolocalización no se muestra.'
                            : '$missing fincas sin geolocalización no se muestran.',
                        style: const TextStyle(
                          color: Color(0xFF9A6A2C),
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carga las fincas y muestra el mapa; con indicador de carga y reintento.
class FarmsMapLoader extends StatefulWidget {
  const FarmsMapLoader({
    super.key,
    required this.loadFarms,
    this.tileLayerBuilder = openStreetMapTiles,
  });

  final Future<List<Map<String, dynamic>>> Function() loadFarms;
  final Widget Function() tileLayerBuilder;

  @override
  State<FarmsMapLoader> createState() => _FarmsMapLoaderState();
}

class _FarmsMapLoaderState extends State<FarmsMapLoader> {
  List<Map<String, dynamic>>? _farms;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _farms = null;
      _error = null;
    });
    try {
      final farms = await widget.loadFarms();
      if (mounted) setState(() => _farms = farms);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No fue posible cargar las fincas.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final farms = _farms;
    if (farms != null) {
      return FarmsMapScreen(
        farms: farms,
        tileLayerBuilder: widget.tileLayerBuilder,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F0),
      appBar: AppBar(
        title: const Text('Fincas en el mapa'),
        backgroundColor: const Color(0xFFF6F5F0),
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/farms');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Fincas de origen y detalle de trazabilidad a partir de líneas con la forma de
/// `export_traceability` / `lot_catalog`: farm_id, farm_name, supplier_name,
/// country_code, latitude, longitude, lot_code, product_variety y, si hay,
/// quantity. Agrupa las líneas por finca.
({List<Map<String, dynamic>> farms, Map<Object?, List<String>> details})
groupTraceability(Iterable<Map<String, dynamic>> lines) {
  final farms = <Object?, Map<String, dynamic>>{};
  final details = <Object?, List<String>>{};
  for (final line in lines) {
    final id = line['farm_id'];
    farms.putIfAbsent(
      id,
      () => {
        'id': id,
        'name': line['farm_name'],
        'supplier_name': line['supplier_name'],
        'country_code': line['country_code'],
        'latitude': line['latitude'],
        'longitude': line['longitude'],
      },
    );
    final quantity = line['quantity'];
    details
        .putIfAbsent(id, () => [])
        .add(
          [
            'Lote ${line['lot_code'] ?? ''}',
            '${line['product_variety'] ?? ''}',
            if (quantity is num) '$quantity kg',
          ].where((t) => t.trim().isNotEmpty).join(' · '),
        );
  }
  return (farms: farms.values.toList(), details: details);
}

/// Mapa de trazabilidad: dibuja el origen (fincas) de las líneas dadas y, al
/// tocar una finca, sus lotes y cantidades. Hoy se abre para un lote; con el
/// módulo de exportaciones se alimentará con `export_traceability`.
class TraceabilityMapScreen extends StatelessWidget {
  const TraceabilityMapScreen({
    super.key,
    required this.lines,
    this.title = 'Origen en el mapa',
    this.tileLayerBuilder = openStreetMapTiles,
  });

  final List<Map<String, dynamic>> lines;
  final String title;
  final Widget Function() tileLayerBuilder;

  @override
  Widget build(BuildContext context) {
    final grouped = groupTraceability(lines);
    return FarmsMapScreen(
      farms: grouped.farms,
      details: grouped.details,
      title: title,
      tileLayerBuilder: tileLayerBuilder,
    );
  }
}
