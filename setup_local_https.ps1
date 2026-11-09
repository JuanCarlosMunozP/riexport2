$ErrorActionPreference = 'Stop'

$mkcertCommand = Get-Command mkcert -ErrorAction SilentlyContinue
$mkcertPath = if ($null -ne $mkcertCommand) {
    $mkcertCommand.Source
} else {
    Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\mkcert.exe'
}

if (!(Test-Path -LiteralPath $mkcertPath)) {
    throw 'No se encontró mkcert. Ejecuta: winget install --id FiloSottile.mkcert --exact. Al terminar, abre una terminal nueva, verifica con mkcert -version y vuelve a ejecutar .\setup_local_https.ps1.'
}

$certificateDirectory = Join-Path $PSScriptRoot '.certs-local'
$certificatePath = Join-Path $certificateDirectory 'localhost.pem'
$certificateKeyPath = Join-Path $certificateDirectory 'localhost-key.pem'

New-Item -ItemType Directory -Path $certificateDirectory -Force | Out-Null

$caRoot = (& $mkcertPath -CAROOT).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($caRoot)) {
    throw 'mkcert no pudo localizar su autoridad certificadora local.'
}

$caCertificatePath = Join-Path $caRoot 'rootCA.pem'
if (!(Test-Path -LiteralPath $caCertificatePath)) {
    throw "No se encontró el certificado raíz local: $caCertificatePath"
}

& $mkcertPath `
    -cert-file $certificatePath `
    -key-file $certificateKeyPath `
    localhost 127.0.0.1 ::1
if ($LASTEXITCODE -ne 0) {
    throw 'mkcert no pudo generar el certificado HTTPS local.'
}

& certutil.exe -user -addstore -f Root $caCertificatePath
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Se generó el certificado, pero Windows no confió en la autoridad local. Si cancelaste el aviso de seguridad, vuelve a ejecutar este script y acepta la instalación; sin confianza, el navegador mostrará una advertencia.'
    exit 1
}

Write-Host 'Certificado HTTPS local generado y confiado para este usuario. Ejecuta .\run_web.ps1 y abre https://localhost:5000.'
