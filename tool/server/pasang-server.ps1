# Memasang server Toko agar berjalan otomatis saat komputer menyala
# (Task Scheduler, akun SYSTEM, tetap jalan walau tidak ada yang login).
# Jalankan PowerShell sebagai Administrator di folder ini:
#   powershell -ExecutionPolicy Bypass -File .\pasang-server.ps1
param([int]$Port = 8787)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'bin\toko_server.exe'
if (-not (Test-Path $exe)) { throw "toko_server.exe tidak ditemukan: $exe" }

# Salin ke Program Files supaya tidak ikut terhapus bersama folder download.
$target = Join-Path $env:ProgramFiles 'TokoServer'
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Recurse -Force (Join-Path $PSScriptRoot 'bin') $target
Copy-Item -Recurse -Force (Join-Path $PSScriptRoot 'lib') $target
$exe = Join-Path $target 'bin\toko_server.exe'

$action = New-ScheduledTaskAction -Execute $exe -Argument "--port $Port"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'TokoServer' -Action $action `
  -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest `
  -Force | Out-Null

# Izinkan koneksi masuk dari komputer kasir.
New-NetFirewallRule -DisplayName 'Toko Server' -Direction Inbound `
  -Protocol TCP -LocalPort $Port -Action Allow -ErrorAction SilentlyContinue | Out-Null

Start-ScheduledTask -TaskName 'TokoServer'
Start-Sleep -Seconds 3
$data = Join-Path $env:ProgramData 'TokoServer'
Write-Host "Server Toko terpasang dan berjalan di port $Port."
Write-Host "Folder data  : $data (BACKUP folder ini, termasuk toko-server.key)"
Write-Host (Get-Content (Join-Path $data 'KODE-PAIRING.txt') -ErrorAction SilentlyContinue)
