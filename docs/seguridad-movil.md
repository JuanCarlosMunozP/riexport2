# Seguridad de la app (OWASP Mobile Top 10)

Controles implementados en el cliente Flutter. La autorización real vive en el
servidor (RLS de Supabase, ver `modelo-autorizacion-rls.md`); el cliente nunca
es la única barrera.

| Riesgo | Control | Dónde |
|---|---|---|
| M1 Credenciales | Claves por `--dart-define` (nada hardcodeado); `credenciales.txt`, `.env*`, `*.jks`, `*.keystore`, `key.properties` en `.gitignore`; firma release desde `android/key.properties`; token en Keychain/Keystore | `lib/backend/supabase_backend_client.dart`, `.gitignore`, `android/app/build.gradle.kts` |
| M2 Cadena de suministro | Versiones fijadas y `pubspec.lock` versionado; revisar con `flutter pub outdated` y `dart pub audit` antes de cada release | `pubspec.yaml` |
| M3 Auth/autorización | No se envía un JWT vencido (cierra sesión local, `SESSION_EXPIRED`); freno de fuerza bruta de login (5 fallos → 30 s); RLS en servidor | `ApiClient`, `AuthSession`, `LoginThrottle` |
| M4 Inyección | Saneo de caracteres de control/bidi/ancho cero en todo cuerpo saliente (excepto contraseñas, tokens, códigos y base64); validación por campo en backend; límite de 10 MB por respuesta; CSP `object-src 'none'; base-uri 'self'; form-action 'self'` en web | `sanitizeJson`, `ApiClient`, `web/index.html` |
| M5 Comunicaciones | HTTPS obligatorio (HTTP solo loopback) en API y Supabase; Android `usesCleartextTraffic=false` + `network_security_config`; iOS ATS sin `NSAllowsArbitraryLoads`; enlaces externos solo HTTPS (`isSafeExternalUri`) | `ApiConfig`, manifiestos |
| M6 Privacidad | `FLAG_SECURE` en release (sin capturas ni vista previa en recientes); logs solo en debug y con `redactSensitive`; sin datos sensibles en mensajes de error | `MainActivity.kt`, `shipment_timeline_screen.dart` |
| M7 Ingeniería inversa | R8 (`isMinifyEnabled`, `isShrinkResources`) + `--obfuscate --split-debug-info` | `build.gradle.kts`, `tool/build_release.ps1` |
| M8 Configuración | `allowBackup=false`, `dataExtractionRules` vacías, sin `debuggable`, única Activity exportada = launcher; el backend local de demo se bloquea en release | `AndroidManifest.xml`, `lib/app/app.dart` |
| M9 Almacenamiento | Token solo en `flutter_secure_storage` (iOS `first_unlock_this_device`); sin `SharedPreferences`; sin copias de seguridad | `SecureSessionTokenStore` |
| M10 Criptografía | Sin cifrado propio ni claves en el código; contraseñas gestionadas por Supabase Auth (bcrypt). El almacén local de demo usa contraseñas en memoria y **no se compila en release** | `GoTrue`, `app.dart` |

## Compilar para producción

```powershell
.\tool\build_release.ps1 -SupabaseUrl https://<proyecto>.supabase.co -SupabaseAnonKey <anon>
```

Guardar `build/symbols` (símbolos para desofuscar trazas) fuera del repositorio.

## Pendiente recomendado (no implementado)

- *Certificate pinning* (requiere decidir el certificado/huella de Supabase y un
  plan de rotación).
- Detección de root/jailbreak y *Play Integrity* / *App Attest*.
- Rotación de la clave anon y revisión de las políticas RLS antes de cada release.
