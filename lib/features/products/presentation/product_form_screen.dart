import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';

/// Guarda el producto. En alta, [fields] trae el producto completo; en edición,
/// solo los campos que cambiaron. [certificationIds] es la selección final y
/// [certificationsChanged] indica si difiere de la inicial.
typedef SaveProduct =
    Future<void> Function({
      required Map<String, Object?> fields,
      required List<int> certificationIds,
      required bool certificationsChanged,
    });

/// Formulario de registro y edición de productos de café y cacao, con sus
/// certificaciones. El tipo y la unidad base no se editan una vez creado.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.loadCertifications,
    required this.loadUnits,
    required this.onSave,
    this.product,
  });

  final Map<String, dynamic>? product;
  final Future<List<Map<String, dynamic>>> Function() loadCertifications;
  final Future<List<Map<String, dynamic>>> Function() loadUnits;
  final SaveProduct onSave;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  static final _hsPattern = RegExp(r'^[0-9]{4}(\.[0-9]{2}){0,3}$');

  final _formKey = GlobalKey<FormState>();
  late final _variety = TextEditingController(text: _initial('variety'));
  late final _quality = TextEditingController(text: _initial('quality_grade'));
  late final _hs = TextEditingController(text: _initial('hs_code'));
  late final _threshold = TextEditingController(
    text: _initial('low_stock_threshold'),
  );
  late final _humidity = TextEditingController(
    text: _initial('humidity_percent'),
  );
  late final _bean = TextEditingController(text: _initial('bean_type'));
  late final _ferment = TextEditingController(
    text: _initial('fermentation_percent'),
  );

  late String _type = widget.product?['type'] == 'cacao' ? 'cacao' : 'coffee';
  String? _unit;
  late final Set<int> _initialCertifications = {
    if (widget.product?['certification_ids'] is List)
      ...(widget.product!['certification_ids'] as List).whereType<int>(),
  };
  late final Set<int> _selectedCertifications = {..._initialCertifications};
  List<Map<String, dynamic>> _certifications = const [];
  List<Map<String, dynamic>> _units = const [];
  bool _loadingCatalogs = true;
  bool _saving = false;
  String? _catalogError;
  String? _error;

  bool get _isEdit => widget.product != null;

  String _initial(String key) {
    final value = widget.product?[key];
    if (value == null) return '';
    if (value is double && value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return '$value';
  }

  @override
  void initState() {
    super.initState();
    _unit = widget.product?['base_unit_code'] as String?;
    _loadCatalogs();
  }

  @override
  void dispose() {
    _variety.dispose();
    _quality.dispose();
    _hs.dispose();
    _threshold.dispose();
    _humidity.dispose();
    _bean.dispose();
    _ferment.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loadingCatalogs = true;
      _catalogError = null;
    });
    try {
      final results = await Future.wait([
        widget.loadUnits(),
        widget.loadCertifications(),
      ]);
      if (!mounted) return;
      setState(() {
        _units = results[0];
        _certifications = results[1];
        if (_unit == null && _units.isNotEmpty) {
          _unit = '${_units.first['code']}';
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _catalogError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = 'No fue posible cargar los catálogos.');
      }
    } finally {
      if (mounted) setState(() => _loadingCatalogs = false);
    }
  }

  num? _parse(String text) {
    final clean = text.trim().replaceAll(',', '.');
    return clean.isEmpty ? null : num.tryParse(clean);
  }

  String? _requiredText(String? value, String label, int max) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label es obligatoria.';
    if (text.length > max) return 'Máximo $max caracteres.';
    return null;
  }

  String? _percent(String? value, String label) {
    final number = _parse(value ?? '');
    if (number == null) {
      return (value?.trim().isEmpty ?? true)
          ? '$label es obligatoria.'
          : 'Ingresa un número válido.';
    }
    if (number < 0 || number > 100) return 'Debe estar entre 0 y 100.';
    return null;
  }

  Map<String, Object?> _collect() {
    final hs = _hs.text.trim();
    final threshold = _parse(_threshold.text);
    final fields = <String, Object?>{
      'variety': _variety.text.trim(),
      'quality_grade': _quality.text.trim(),
      'hs_code': hs.isEmpty ? null : hs,
      'low_stock_threshold': threshold,
      if (_type == 'coffee')
        'humidity_percent': _parse(_humidity.text)
      else ...{
        'bean_type': _bean.text.trim(),
        'fermentation_percent': _parse(_ferment.text),
      },
    };
    if (!_isEdit) {
      fields.removeWhere((key, value) => value == null);
      return {'type': _type, 'base_unit_code': _unit, ...fields};
    }
    // Edición: solo lo que cambió.
    final product = widget.product!;
    fields.removeWhere((key, value) {
      final old = product[key];
      if (value is num && old is num) return value == old;
      return value == old;
    });
    return fields;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final fields = _collect();
    final certificationsChanged =
        !(_selectedCertifications.length == _initialCertifications.length &&
            _selectedCertifications.containsAll(_initialCertifications));
    if (_isEdit && fields.isEmpty && !certificationsChanged) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        fields: fields,
        certificationIds: _selectedCertifications.toList()..sort(),
        certificationsChanged: certificationsChanged,
      );
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
          _error = 'No fue posible guardar el producto.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F5F0),
    appBar: AppBar(
      title: Text(_isEdit ? 'Editar producto' : 'Registrar producto'),
      backgroundColor: const Color(0xFFF6F5F0),
      leading: IconButton(
        tooltip: 'Volver al catálogo',
        onPressed: _saving
            ? null
            : () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop(false);
                } else {
                  context.go('/products');
                }
              },
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: _loadingCatalogs
          ? const Center(child: CircularProgressIndicator())
          : _catalogError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_catalogError!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadCatalogs,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : _buildForm(),
    ),
  );

  InputDecoration _decoration(String label, {String? hint, String? helper}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
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
              const Text(
                'Tipo de producto',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'coffee',
                    label: Text('Café'),
                    icon: Icon(Icons.coffee_outlined),
                  ),
                  ButtonSegment(
                    value: 'cacao',
                    label: Text('Cacao'),
                    icon: Icon(Icons.cookie_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: _isEdit || _saving
                    ? null
                    : (selection) => setState(() => _type = selection.first),
              ),
              if (_isEdit)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'El tipo no se puede cambiar una vez registrado.',
                    style: TextStyle(color: Color(0xFF68736E), fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _variety,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Variedad'),
                validator: (v) => _requiredText(v, 'La variedad', 120),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quality,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Calidad o grado comercial'),
                validator: (v) => _requiredText(v, 'La calidad', 80),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hs,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: _decoration(
                  'Código HS (opcional)',
                  hint: '0901.11',
                  helper:
                      'Formato: 4 dígitos, con subpartidas de 2 (0901.11.00).',
                ),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  return text.isEmpty || _hsPattern.hasMatch(text)
                      ? null
                      : 'El código HS no tiene un formato válido.';
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('unit-$_unit-${_units.length}'),
                initialValue: _unit,
                isExpanded: true,
                decoration: _decoration(
                  'Unidad base',
                  helper: _isEdit
                      ? 'La unidad base no se puede cambiar.'
                      : null,
                ),
                items: [
                  for (final unit in _units)
                    DropdownMenuItem(
                      value: '${unit['code']}',
                      child: Text('${unit['name']} (${unit['code']})'),
                    ),
                ],
                onChanged: _isEdit || _saving
                    ? null
                    : (value) => setState(() => _unit = value),
                validator: (v) =>
                    v == null ? 'Selecciona la unidad base.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _threshold,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration(
                  'Umbral de stock bajo (opcional)',
                  helper: 'En la unidad base. No puede ser negativo.',
                ),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final number = _parse(text);
                  if (number == null) return 'Ingresa un número válido.';
                  return number < 0 ? 'No puede ser negativo.' : null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                _type == 'coffee' ? 'Datos del café' : 'Datos del cacao',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF193D35),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (_type == 'coffee')
                TextFormField(
                  controller: _humidity,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('Humedad (%)', hint: '11.5'),
                  validator: (v) => _percent(v, 'La humedad'),
                )
              else ...[
                TextFormField(
                  controller: _bean,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration('Tipo de grano'),
                  validator: (v) => _requiredText(v, 'El tipo de grano', 100),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ferment,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('Fermentación (%)', hint: '85'),
                  validator: (v) => _percent(v, 'La fermentación'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Certificaciones',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF193D35),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _buildCertifications(),
              if (_error != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEFEB),
                    border: Border.all(color: const Color(0xFFE9B6A8)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF84382C)),
                  ),
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Guardando…' : 'Guardar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF193D35),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildCertifications() {
    // Activas, más las ya asignadas aunque estén inactivas (para poder quitarlas).
    final visible = [
      for (final c in _certifications)
        if (c['is_active'] == true || _selectedCertifications.contains(c['id']))
          c,
    ];
    if (visible.isEmpty) {
      return const Text(
        'No hay certificaciones disponibles.',
        style: TextStyle(color: Color(0xFF68736E)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in visible)
          if (c['id'] is int)
            FilterChip(
              label: Text(
                '${c['name']}${c['is_active'] == true ? '' : ' (inactiva)'}',
              ),
              selected: _selectedCertifications.contains(c['id']),
              onSelected: _saving
                  ? null
                  : (selected) => setState(() {
                      if (selected) {
                        _selectedCertifications.add(c['id'] as int);
                      } else {
                        _selectedCertifications.remove(c['id']);
                      }
                    }),
            ),
      ],
    );
  }
}
