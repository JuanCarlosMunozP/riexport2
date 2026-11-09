import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import 'location_picker_screen.dart';

/// Guarda la finca. En alta, [fields] trae la finca completa; en edición, solo
/// los campos que cambiaron (un opcional vaciado va como null).
typedef SaveFarm = Future<void> Function(Map<String, Object?> fields);

/// Texto de una coordenada → número, aceptando coma decimal. Null si está vacío.
num? parseCoordinate(String text) {
  final clean = text.trim().replaceAll(',', '.');
  return clean.isEmpty ? null : num.tryParse(clean);
}

/// Valida una coordenada opcional: número, dentro de ±[limit] y con máximo
/// 6 decimales (la base de datos guarda NUMERIC(9,6)).
String? validateCoordinate(String? value, String label, num limit) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final number = parseCoordinate(text);
  if (number == null || !number.isFinite) return 'Ingresa un número válido.';
  if (number < -limit || number > limit) {
    return '$label debe estar entre -$limit y $limit.';
  }
  if ((number - double.parse(number.toStringAsFixed(6))).abs() > 1e-12) {
    return 'Máximo 6 decimales.';
  }
  return null;
}

/// Formulario de registro y edición de fincas con su geolocalización.
class FarmFormScreen extends StatefulWidget {
  const FarmFormScreen({
    super.key,
    required this.loadSuppliers,
    required this.onSave,
    this.farm,
    this.pickLocation,
  });

  /// Abre el selector de mapa con el punto actual (si lo hay) y devuelve el
  /// punto elegido o null si se cancela. Sin esto no se ofrece el mapa.
  final Future<PickedPoint?> Function(double? latitude, double? longitude)?
  pickLocation;

  final Map<String, dynamic>? farm;

  /// Proveedores activos entre los que se elige el responsable de la finca.
  final Future<List<Map<String, dynamic>>> Function() loadSuppliers;
  final SaveFarm onSave;

  @override
  State<FarmFormScreen> createState() => _FarmFormScreenState();
}

class _FarmFormScreenState extends State<FarmFormScreen> {
  static final _countryPattern = RegExp(r'^[A-Za-z]{2}$');

  final _formKey = GlobalKey<FormState>();
  late final _country = TextEditingController(
    text: widget.farm == null ? 'CO' : _initial('country_code'),
  );
  late final _name = TextEditingController(text: _initial('name'));
  late final _address = TextEditingController(text: _initial('address'));
  late final _latitude = TextEditingController(text: _initial('latitude'));
  late final _longitude = TextEditingController(text: _initial('longitude'));

  int? _supplierId;
  List<Map<String, dynamic>> _suppliers = const [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

  bool get _isEdit => widget.farm != null;

  String _initial(String key) {
    final value = widget.farm?[key];
    if (value == null) return '';
    if (value is double && value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return '$value';
  }

  @override
  void initState() {
    super.initState();
    _supplierId = widget.farm?['supplier_id'] as int?;
    if (_isEdit) {
      _loading = false;
    } else {
      _loadSuppliers();
    }
  }

  @override
  void dispose() {
    _country.dispose();
    _name.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final suppliers = await widget.loadSuppliers();
      if (mounted) setState(() => _suppliers = suppliers);
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'No fue posible cargar los proveedores.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickOnMap() async {
    // Solo se parte del punto actual si es válido; si no, el mapa abre vacío.
    final lat = validateCoordinate(_latitude.text, 'La latitud', 90) == null
        ? parseCoordinate(_latitude.text)
        : null;
    final lon = validateCoordinate(_longitude.text, 'La longitud', 180) == null
        ? parseCoordinate(_longitude.text)
        : null;
    final point = await widget.pickLocation!(
      lat != null && lon != null ? lat.toDouble() : null,
      lat != null && lon != null ? lon.toDouble() : null,
    );
    if (point == null || !mounted) return;
    setState(() {
      _latitude.text = '${point.latitude}';
      _longitude.text = '${point.longitude}';
    });
  }

  String? _pairError(String? value, TextEditingController other) {
    // Un punto se informa completo o no se informa.
    final mine = (value ?? '').trim().isEmpty;
    final theirs = other.text.trim().isEmpty;
    return mine != theirs && mine
        ? 'Informa latitud y longitud juntas, o ninguna.'
        : null;
  }

  String? _latitudeError(String? value) =>
      validateCoordinate(value, 'La latitud', 90) ??
      _pairError(value, _longitude) ??
      _originError();

  String? _longitudeError(String? value) =>
      validateCoordinate(value, 'La longitud', 180) ??
      _pairError(value, _latitude);

  String? _originError() {
    final lat = parseCoordinate(_latitude.text);
    final lon = parseCoordinate(_longitude.text);
    return lat == 0 && lon == 0
        ? 'Las coordenadas (0, 0) no son una ubicación válida.'
        : null;
  }

  Map<String, Object?> _collect() {
    String? clean(TextEditingController c) {
      final text = c.text.trim();
      return text.isEmpty ? null : text;
    }

    final fields = <String, Object?>{
      'country_code': _country.text.trim().toUpperCase(),
      'name': _name.text.trim(),
      'address': clean(_address),
      'latitude': parseCoordinate(_latitude.text),
      'longitude': parseCoordinate(_longitude.text),
    };
    if (!_isEdit) {
      fields.removeWhere((key, value) => value == null);
      return {'supplier_id': _supplierId, ...fields};
    }
    // Edición: solo lo que cambió.
    final farm = widget.farm!;
    fields.removeWhere((key, value) {
      final old = farm[key];
      if (value is num && old is num) return value == old;
      return value == old;
    });
    return fields;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final fields = _collect();
    if (_isEdit && fields.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(fields);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No fue posible guardar la finca.';
          _saving = false;
        });
      }
    }
  }

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: Text(_isEdit ? 'Editar finca' : 'Registrar finca'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver a fincas',
        onPressed: _saving
            ? null
            : () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop(false);
                } else {
                  context.go('/farms');
                }
              },
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadSuppliers,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : _buildForm(),
    ),
  );

  Widget _buildForm() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isEdit) ...[
                InputDecorator(
                  decoration: _decoration(
                    'Proveedor',
                    helper: 'La finca no se puede pasar a otro proveedor.',
                  ),
                  child: Text('${widget.farm?['supplier_name'] ?? ''}'),
                ),
              ] else
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _supplierId,
                  decoration: _decoration('Proveedor'),
                  items: [
                    for (final s in _suppliers)
                      if (s['id'] is int)
                        DropdownMenuItem<int>(
                          value: s['id'] as int,
                          child: Text(
                            '${s['business_name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _supplierId = value),
                  validator: (value) =>
                      value == null ? 'El proveedor es obligatorio.' : null,
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Nombre de la finca'),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'El nombre de la finca es obligatorio.';
                  }
                  return text.length > 160 ? 'Máximo 160 caracteres.' : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _country,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                maxLength: 2,
                decoration: _decoration(
                  'País (código de 2 letras)',
                  helper: 'Por ejemplo CO, EC, PE.',
                ).copyWith(counterText: ''),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) return 'El país es obligatorio.';
                  return _countryPattern.hasMatch(text)
                      ? null
                      : 'El país debe ser un código de 2 letras.';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _address,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration('Dirección o referencia (opcional)'),
                validator: (v) => (v?.trim().length ?? 0) > 300
                    ? 'Máximo 300 caracteres.'
                    : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'Geolocalización (opcional)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Punto de la finca en grados decimales (WGS84), por ejemplo '
                '2.535 y -75.527. Se informan las dos coordenadas o ninguna.',
                style: TextStyle(color: Color(0xFF68736E), fontSize: 12),
              ),
              if (widget.pickLocation != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Elegir en el mapa'),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _latitude,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: _decoration('Latitud (-90 a 90)'),
                validator: _latitudeError,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _longitude,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: _decoration('Longitud (-180 a 180)'),
                validator: _longitudeError,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Color(0xFF84382C))),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
