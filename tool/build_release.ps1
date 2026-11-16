# Compilación release endurecida (M1/M7): ofusca el código Dart y separa los
# símbolos de depuración. Las claves NO viven en el código: se pasan por
# variables de entorno o parámetros.
#   .\tool\build_release.ps1 -SupabaseUrl https://xxxx.supabase.co -SupabaseAnonKey <anon> [-Target apk|appbundle]
param(
  [Parameter(Mandatory = $true)][string]$SupabaseUrl,
  [Parameter(Mandatory = $true)][string]$SupabaseAnonKey,
  [ValidateSet('apk', 'appbundle')][string]$Target = 'appbundle'
)
if (-not $SupabaseUrl.StartsWith('https://')) { throw 'SUPABASE_URL debe ser HTTPS.' }
if (-not (Test-Path 'android/key.properties')) {
  Write-Warning 'Falta android/key.properties: el build se firmará con la llave de depuración (no distribuir).'
}
$symbols = 'build/symbols'
New-Item -ItemType Directory -Force $symbols | Out-Null
flutter build $Target --release --obfuscate "--split-debug-info=$symbols" `
  "--dart-define=SUPABASE_URL=$SupabaseUrl" `
  "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
