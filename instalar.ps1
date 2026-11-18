# Instalador del widget de costos Azure (no usa VBScript).
# Crea accesos directos en el Escritorio y en Inicio (auto-arranque) que lanzan
# PowerShell oculto. Útil en equipos donde los .vbs no abren (Windows 11 está
# retirando VBScript) y salen errores como «El formato de información de enlace
# de la aplicación no es válido».
# Uso (clic derecho → «Ejecutar con PowerShell», o desde una consola):
#   powershell -ExecutionPolicy Bypass -File instalar.ps1
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -SinInicio   # sin auto-arranque

param([switch]$SinInicio)

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$widget = Join-Path $dir 'CostosAzureWidget.ps1'
if (-not (Test-Path $widget)) { throw "No encuentro $widget" }

# Quita la marca de «descargado de Internet», que bloquea los scripts.
Get-ChildItem $dir -File | Unblock-File -ErrorAction SilentlyContinue

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $widget

$destinos = @([Environment]::GetFolderPath('Desktop'))
if (-not $SinInicio) { $destinos += [Environment]::GetFolderPath('Startup') }

$shell = New-Object -ComObject WScript.Shell
foreach ($carpeta in $destinos) {
  $lnk = Join-Path $carpeta 'Costos Azure.lnk'
  # Borra accesos viejos que apuntaban a lanzar.vbs.
  Get-ChildItem $carpeta -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $viejo = $shell.CreateShortcut($_.FullName)
      if (("$($viejo.TargetPath) $($viejo.Arguments)") -match 'lanzar\.vbs') { Remove-Item $_.FullName -Force }
    } catch {}
  }
  $s = $shell.CreateShortcut($lnk)
  $s.TargetPath = $ps
  $s.Arguments = $argumentos
  $s.WorkingDirectory = $dir
  $s.WindowStyle = 7   # minimizado: la consola no se ve al arrancar
  $s.IconLocation = "$ps,0"
  $s.Description = 'Widget de costos Azure'
  $s.Save()
  Write-Host "Acceso directo creado: $lnk"
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Host 'Aviso: no encuentro Azure CLI (az). Instálalo y corre «az login» antes de abrir el widget.' -ForegroundColor Yellow
}
Write-Host 'Listo. Abre «Costos Azure» desde el Escritorio.'
