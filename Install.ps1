param(
    [string]$XboxGamesPath,
    [string]$SisrPath
)

$ErrorActionPreference = "Stop"
$RepoRaw = "https://raw.githubusercontent.com/Davhel98/SISR-Xbox-AutoLauncher/main"
$InstallDir = Join-Path $env:LOCALAPPDATA "SISRXboxAutoLauncher"
$WatcherPath = Join-Path $InstallDir "SISR-Xbox-Watcher.ps1"
$ConfigPath = Join-Path $InstallDir "config.json"
$TaskName = "SISR Xbox AutoLauncher"

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

Write-Host "Downloading watcher..."
Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/src/SISR-Xbox-Watcher.ps1" -OutFile $WatcherPath

$config = [ordered]@{
    XboxGamesPath = [IO.Path]::GetFullPath($XboxGamesPath)
    SisrPath = [IO.Path]::GetFullPath($SisrPath)
    ShutdownDebounceSeconds = 5
}
$config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

$ps = (Get-Command powershell.exe).Source
$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WatcherPath`" -ConfigPath `"$ConfigPath`""
$action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Starts/stops SISR automatically while Xbox games are running." -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Xbox games: $($config.XboxGamesPath)"
Write-Host "SISR:       $($config.SisrPath)"
Write-Host "Task:       $TaskName"
