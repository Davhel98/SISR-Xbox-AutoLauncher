param([string]$ConfigPath = "$env:LOCALAPPDATA\SISRXboxAutoLauncher\config.json")

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $logDir = Join-Path (Split-Path $ConfigPath -Parent) "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log = Join-Path $logDir "watcher.log"
    Add-Content -Path $log -Value ("{0:u} {1}" -f (Get-Date), $Message)
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) { throw "Configuration not found: $ConfigPath" }
    Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Get-XboxProcesses([string]$Root) {
    $prefix = ([IO.Path]::GetFullPath($Root)).TrimEnd('\') + '\'
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    })
}

$config = Get-Config
$xboxRoot = ([IO.Path]::GetFullPath($config.XboxGamesPath)).TrimEnd('\')
$sisrPath = [IO.Path]::GetFullPath($config.SisrPath)
$debounce = if ($config.ShutdownDebounceSeconds) { [int]$config.ShutdownDebounceSeconds } else { 5 }
$sisrStartedByWatcher = $false

function Get-SisrProcess {
    $expected = $sisrPath
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.Equals($expected, [StringComparison]::OrdinalIgnoreCase)
    })
}

function Sync-State {
    $games = Get-XboxProcesses $xboxRoot
    $sisr = Get-SisrProcess

    if ($games.Count -gt 0 -and $sisr.Count -eq 0) {
        Start-Process -FilePath $sisrPath
        $script:sisrStartedByWatcher = $true
        Write-Log "Xbox game detected; SISR started."
        return
    }

    if ($games.Count -eq 0 -and $sisr.Count -gt 0 -and $script:sisrStartedByWatcher) {
        Start-Sleep -Seconds $debounce
        if ((Get-XboxProcesses $xboxRoot).Count -eq 0) {
            Get-SisrProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            $script:sisrStartedByWatcher = $false
            Write-Log "No Xbox games remain; SISR stopped."
        }
    }
}

Write-Log "Watcher started. XboxGamesPath=$xboxRoot"
Sync-State

$startSub = Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStartTrace" -SourceIdentifier "SISRXbox.ProcessStart"
$stopSub  = Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStopTrace" -SourceIdentifier "SISRXbox.ProcessStop"

try {
    while ($true) {
        $event = Wait-Event -Timeout 30
        if ($event) {
            Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
            Sync-State
        }
    }
}
finally {
    Unregister-Event -SourceIdentifier "SISRXbox.ProcessStart" -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier "SISRXbox.ProcessStop" -ErrorAction SilentlyContinue
    Write-Log "Watcher stopped."
}
