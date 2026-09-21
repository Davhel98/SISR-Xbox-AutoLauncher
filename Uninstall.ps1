$ErrorActionPreference = "Stop"
$TaskName = "SISR Xbox AutoLauncher"
$InstallDir = Join-Path $env:LOCALAPPDATA "SISRXboxAutoLauncher"

Write-Host "=== SISR Xbox AutoLauncher Uninstaller ===" -ForegroundColor Cyan

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task removed."
}

if (Test-Path $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "Local files removed."
}

Write-Host "Uninstall complete." -ForegroundColor Green
