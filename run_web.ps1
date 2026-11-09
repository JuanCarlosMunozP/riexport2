$ErrorActionPreference = 'Stop'

$certificateDirectory = Join-Path $PSScriptRoot '.certs-local'
$certificatePath = Join-Path $certificateDirectory 'localhost.pem'
$certificateKeyPath = Join-Path $certificateDirectory 'localhost-key.pem'
$webPort = 5000

if (!(Test-Path -LiteralPath $certificatePath) -or
    !(Test-Path -LiteralPath $certificateKeyPath)) {
    throw 'Faltan los certificados HTTPS locales. Ejecuta .\setup_local_https.ps1 y vuelve a iniciar la app.'
}

Push-Location $PSScriptRoot
try {
    flutter run -d web-server `
        --web-hostname localhost `
        --web-port $webPort `
        --web-launch-url "https://localhost:$webPort" `
        --web-tls-cert-path $certificatePath `
        --web-tls-cert-key-path $certificateKeyPath `
        --dart-define-from-file=.env
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
