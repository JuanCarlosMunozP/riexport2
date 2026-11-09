/// Países de la Unión Europea (ISO 3166-1 alfa-2) donde el EORI es obligatorio.
/// Debe coincidir con `database/migrations/*_customers_module.sql`.
const euCountryCodes = {
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', //
  'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK',
  'SI', 'ES', 'SE',
};

final _eoriFormat = RegExp(r'^[A-Z]{2}[A-Z0-9]{1,15}$');

/// Normaliza un EORI como la base de datos: mayúsculas y sin espacios, guiones
/// ni puntos. Devuelve null si queda vacío.
String? normalizeEori(String? value) {
  final clean = (value ?? '').replaceAll(RegExp(r'[\s.\-]'), '').toUpperCase();
  return clean.isEmpty ? null : clean;
}

/// Prefijo que debe llevar el EORI de un cliente del [countryCode] (Grecia usa EL).
String eoriPrefixFor(String countryCode) =>
    countryCode == 'GR' ? 'EL' : countryCode;

/// Valida un EORI contra el país del cliente, con los mismos mensajes que la
/// función `create_customer` de la base de datos. Devuelve el mensaje de error
/// o null si es válido. [country] vacío o inválido no se valida aquí.
String? validateEori(String? eori, String? country) {
  final normalized = normalizeEori(eori);
  final code = (country ?? '').trim().toUpperCase();
  if (normalized == null) {
    return euCountryCodes.contains(code)
        ? 'El EORI es obligatorio para clientes de la Unión Europea.'
        : null;
  }
  if (!_eoriFormat.hasMatch(normalized)) {
    return 'El EORI no tiene un formato válido: 2 letras de país y hasta 15 '
        'caracteres alfanuméricos (por ejemplo ES12345678Z).';
  }
  if (RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
    final prefix = eoriPrefixFor(code);
    final northernIreland = code == 'GB' && normalized.startsWith('XI');
    if (!normalized.startsWith(prefix) && !northernIreland) {
      return 'El EORI debe empezar por $prefix (el país del cliente).';
    }
  }
  return null;
}
