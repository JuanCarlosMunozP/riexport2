# Copia database/migrations y la semilla base a supabase/ para poder usar la CLI de Supabase
# (la CLI solo lee supabase/migrations). La copia esta en .gitignore: la fuente es database/.
#
#   .\database\scripts\sync-supabase.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Join-Path $root 'database\migrations'
$target = Join-Path $root 'supabase\migrations'

if (-not (Test-Path $source)) { throw "No existe $source." }
New-Item -ItemType Directory -Force -Path $target | Out-Null
Get-ChildItem -Path $target -Filter '*.sql' | Remove-Item -Force
Copy-Item -Path (Join-Path $source '*.sql') -Destination $target
$count = (Get-ChildItem -Path $target -Filter '*.sql').Count
Write-Host "supabase/migrations sincronizado con $count migracion(es)."
