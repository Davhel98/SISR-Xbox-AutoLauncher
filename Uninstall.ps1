$ErrorActionPreference = "Stop"
$TaskNames = @(
    "SISR Xbox AutoLauncher",
    "SISR Xbox AutoLauncher Log Cleanup"
)
$InstallDir = Join-Path $env:LOCALAPPDATA "SISRXboxAutoLauncher"

Write-Host "=== SISR Xbox AutoLauncher Uninstaller ===" -ForegroundColor Cyan

foreach ($TaskName in $TaskNames) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task removed: $TaskName"
    }
}

if (Test-Path $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "Local files removed."
}

Write-Host "Uninstall complete." -ForegroundColor Green
