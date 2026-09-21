param(
    [string]$XboxGamesPath,
    [string]$SisrPath
)

$ErrorActionPreference = "Stop"
$RepoRaw = "https://raw.githubusercontent.com/Davhel98/SISR-Xbox-AutoLauncher/main"
$InstallDir = Join-Path $env:LOCALAPPDATA "SISRXboxAutoLauncher"
$WatcherPath = Join-Path $InstallDir "SISR-Xbox-Watcher.ps1"
$CleanupPath = Join-Path $InstallDir "SISR-Xbox-LogCleanup.ps1"
$ConfigPath = Join-Path $InstallDir "config.json"
$TaskName = "SISR Xbox AutoLauncher"
$CleanupTaskName = "SISR Xbox AutoLauncher Log Cleanup"

Write-Host "=== SISR Xbox AutoLauncher Installer ===" -ForegroundColor Cyan

while ([string]::IsNullOrWhiteSpace($XboxGamesPath) -or -not (Test-Path -LiteralPath $XboxGamesPath -PathType Container)) {
    if ($XboxGamesPath) { Write-Warning "Directory not found: $XboxGamesPath" }
    $XboxGamesPath = Read-Host "Xbox Games root directory (example D:\XboxGames)"
}

while ([string]::IsNullOrWhiteSpace($SisrPath) -or -not (Test-Path -LiteralPath $SisrPath -PathType Leaf)) {
    if ($SisrPath) { Write-Warning "SISR executable not found: $SisrPath" }
    $SisrPath = Read-Host "Full path to SISR executable"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Stop an existing installation before replacing its scripts. Starting an
# already-running Scheduled Task would otherwise leave the old watcher active.
foreach ($ExistingTaskName in @($TaskName, $CleanupTaskName)) {
    if (Get-ScheduledTask -TaskName $ExistingTaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $ExistingTaskName -ErrorAction SilentlyContinue
    }
}

Write-Host "Downloading watcher and log cleanup scripts..."
Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/src/SISR-Xbox-Watcher.ps1" -OutFile $WatcherPath
Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/src/SISR-Xbox-LogCleanup.ps1" -OutFile $CleanupPath

$config = [ordered]@{
    XboxGamesPath = [IO.Path]::GetFullPath($XboxGamesPath)
    SisrPath = [IO.Path]::GetFullPath($SisrPath)
    ShutdownDebounceSeconds = 5
    PollingIntervalSeconds = 1
}
$config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

$ps = (Get-Command powershell.exe).Source
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

$watcherArguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WatcherPath`" -ConfigPath `"$ConfigPath`""
$watcherAction = New-ScheduledTaskAction -Execute $ps -Argument $watcherArguments
$watcherTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName $TaskName -Action $watcherAction -Trigger $watcherTrigger -Settings $settings -Description "Starts/stops SISR automatically while Xbox games are running." -Force | Out-Null

$cleanupArguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$CleanupPath`""
$cleanupAction = New-ScheduledTaskAction -Execute $ps -Argument $cleanupArguments
$cleanupTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName $CleanupTaskName -Action $cleanupAction -Trigger $cleanupTrigger -Settings $settings -Description "Deletes SISR Xbox AutoLauncher log files older than 24 hours at user logon." -Force | Out-Null

Start-ScheduledTask -TaskName $CleanupTaskName
Start-ScheduledTask -TaskName $TaskName

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Xbox games: $($config.XboxGamesPath)"
Write-Host "SISR:       $($config.SisrPath)"
Write-Host "Watcher:    $TaskName"
Write-Host "Log cleanup:$CleanupTaskName"
