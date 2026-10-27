# Menghentikan & menghapus tugas server Toko (data di %ProgramData%\TokoServer
# TIDAK dihapus). Jalankan sebagai Administrator.
Stop-ScheduledTask -TaskName 'TokoServer' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'TokoServer' -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName 'Toko Server' -ErrorAction SilentlyContinue
Write-Host 'Server Toko dihentikan. Folder data tetap ada.'
