import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Punto elegido en el mapa, ya normalizado (ver [normalizePoint]).
typedef PickedPoint = ({double latitude, double longitude});

/// Mosaicos de OpenStreetMap. Es un servidor comunitario con política de uso
/// razonable (https://operations.osmfoundation.org/policies/tiles/): sirve para
/// desarrollo y uso moderado; en producción con mucho tráfico hay que cambiar
/// [LocationPickerScreen.tileLayerBuilder] por un proveedor propio o de pago.
Widget openStreetMapTiles() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.riexport.riexport_app',
);

/// Lleva un punto tocado en el mapa a lo que acepta la base de datos: longitud
/// dentro de -180..180 (el mapa se repite al desplazarse), latitud dentro de
/// -90..90 y 6 decimales.
PickedPoint normalizePoint(LatLng point) {
  double round6(double value) => double.parse(value.toStringAsFixed(6));
  final longitude = ((point.longitude + 180) % 360 + 360) % 360 - 180;
  return (
    latitude: round6(point.latitude.clamp(-90.0, 90.0)),
    longitude: round6(longitude),
  );
}

/// Selector de ubicación: se toca el mapa para colocar el punto y se confirma
/// con "Usar esta ubicación". Devuelve el [PickedPoint] o null si se cancela.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.tileLayerBuilder = openStreetMapTiles,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  /// Capa de mosaicos del mapa; se sustituye en pruebas o para cambiar de proveedor.
  final Widget Function() tileLayerBuilder;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Colombia: vista inicial cuando la finca aún no tiene punto.
  static const _defaultCenter = LatLng(4.57, -74.3);

  PickedPoint? _point;
  String? _notice;

  bool get _hasInitial =>
      widget.initialLatitude != null && widget.initialLongitude != null;

  @override
  void initState() {
    super.initState();
    if (_hasInitial) {
      _point = (
        latitude: widget.initialLatitude!,
        longitude: widget.initialLongitude!,
      );
    }
  }

  void _onTap(LatLng tapped) {
    final point = normalizePoint(tapped);
    setState(() {
      if (point.latitude == 0 && point.longitude == 0) {
        _notice = 'Las coordenadas (0, 0) no son una ubicación válida.';
        return;
      }
      _notice = null;
      _point = point;
    });
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    final center = point == null
        ? _defaultCenter
        : LatLng(point.latitude, point.longitude);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F0),
      appBar: AppBar(
        title: const Text('Elegir ubicación'),
        backgroundColor: const Color(0xFFF6F5F0),
        leading: IconButton(
          tooltip: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
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
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: _hasInitial ? 14 : 5,
                      minZoom: 2,
                      onTap: (_, tapped) => _onTap(tapped),
                    ),
                    children: [
                      widget.tileLayerBuilder(),
                      if (point != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(point.latitude, point.longitude),
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_on,
                                size: 44,
                                color: Color(0xFF9B3D2D),
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
                  Text(
                    point == null
                        ? 'Toca el mapa para colocar la finca.'
                        : 'Latitud ${point.latitude}   Longitud ${point.longitude}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _notice!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF84382C)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: point == null
                        ? null
                        : () => Navigator.of(context).pop(point),
                    child: const Text('Usar esta ubicación'),
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
