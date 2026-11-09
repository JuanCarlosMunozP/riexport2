# Informe de validacion funcional en Android

**Generado:** 2026-11-06
**Proyecto:** `D:\plataforma_exportacion_cafe_cacao`
**Dispositivo:** emulador Android `sdk_gphone64_x86_64`, 1080 x 2340

## Resumen

| Comprobacion | Estado | Codigo | Resultado |
|---|---|---:|---|
| Compilacion e inicio Android | PASS | 0 | APK debug compilado e instalado en `emulator-5554` |
| Analisis estatico | PASS | 0 | `flutter analyze`; sin problemas |
| Suite Flutter completa | FAIL | 1 | `flutter test --reporter expanded`: 298 pasaron, 6 fallaron |
| Pruebas enfocadas: login, confirmacion, clientes y pedidos | PASS | 0 | 31 pruebas pasaron |
| Validacion de campos de registro | PASS | 0 | Prueba enfocada y comprobacion manual en Android |
| Flujo CRUD local de proveedores | PASS | 0 | Registrar, duplicar, editar, inactivar y reactivar |

## Pruebas funcionales en Android

En el emulador se comprobo que:

- El login vacio presenta mensajes obligatorios para correo y contrasena.
- El enlace **Registrate** abre el formulario de registro.
- Al enviar el registro vacio, se muestran errores para nombres, apellidos, correo y contrasenas; el telefono opcional no se marca como requerido.
- La aplicacion permanece activa y no se observaron excepciones Flutter ni ANR durante esta ultima comprobacion.

No se enviaron credenciales ni datos de registro a Supabase; no se probaron autenticacion real, persistencia remota ni flujos que requieren cuenta.

## Fallos reproducibles de la suite completa

1. `test/home_permissions_test.dart` — «el inicio muestra la gestion solo a quien tiene permisos»: esperaba encontrar **Mi perfil**.
2. `test/supabase_backend_test.dart` — «registro: contraseña débil y correo inválido llegan en español y con detalle»: esperaba que el mensaje incluyera **contraseña**; recibio `Usa al menos 12 caracteres con mayúscula, minúscula, número y símbolo.`
3. `test/supabase_backend_test.dart` — «recuperacion: codigo invalido, contrasena debil o repetida se traducen»: esperaba **demasiado débil**; recibio el mismo mensaje de requisitos de contrasena.
4. `test/products_flow_test.dart` — «solo quien tiene products.read ve el catalogo en el inicio»: esperaba encontrar **Mi perfil**.
5. `test/user_registration_screen_test.dart` — «sends the API contract fields and confirms creation»: esperaba el mapa del registro, pero recibio `null`.
6. `test/user_registration_screen_test.dart` — «shows API errors without clearing entered values»: no encontro el mensaje de correo ya registrado.

Los cuatro archivos de pruebas implicados se volvieron a ejecutar en una prueba enfocada: **34 pasaron y los mismos 6 fallaron**. No se modifico codigo de la aplicacion ni de sus pruebas.

## Entorno y alcance

- Flutter: Android emulator disponible; build y ejecucion completados.
- `flutter analyze`: sin problemas.
- Docker CLI presente, pero el daemon no esta disponible: `open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.`
- Node.js `v24.15.0` disponible. Playwright no se uso: el objetivo fue la app Flutter nativa en Android, no una interfaz web.
- La aplicacion usa Supabase cuando hay credenciales configuradas. No se intento probar acceso con credenciales desconocidas.

## Veredicto

```text
environment:
  docker: UNAVAILABLE — open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
  node: AVAILABLE — v24.15.0
  playwright: NOT APPLICABLE — validacion de la app nativa Android
  infra-tier: UNVERIFIED — los flujos probados no requieren contenedores
  browser-tier: SKIPPED — el objetivo es Android nativo; se probaron widgets y dispositivo
startup: PASS — flutter run -d emulator-5554; APK compilado, instalado y pantalla de login visible
integration: FAIL — exit_code: 1; 298 pasaron, 6 fallaron; flutter test --reporter expanded
e2e: PARTIAL — exit_code: 0; validacion de login y registro vacios en Android; sin autenticacion remota
overall: FAIL — build y flujos manuales comprobados; seis fallos reproducibles en la suite completa
```
