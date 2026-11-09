import 'dart:convert';

/// Matches the password policy configured in Supabase Auth.
String? validatePasswordPolicy(String password) {
  if (password.isEmpty) return 'Ingresa una contraseña.';
  if (utf8.encode(password).length > 72) {
    return 'La contraseña debe ocupar máximo 72 bytes UTF-8.';
  }
  if (password.length < 12 ||
      !RegExp(r'[a-z]').hasMatch(password) ||
      !RegExp(r'[A-Z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password) ||
      !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'Usa al menos 12 caracteres con mayúscula, minúscula, número y símbolo.';
  }
  return null;
}
