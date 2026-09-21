param([string]$ConfigPath = "$env:LOCALAPPDATA\SISRXboxAutoLauncher\config.json")

$ErrorActionPreference = "Stop"

$script:xboxProcessIds = New-Object 'System.Collections.Generic.HashSet[int]'
$script:ownedSisrProcessId = $null
$script:creationWatcher = $null
$script:deletionWatcher = $null
$script:creationSourceId = "SISRXbox.ProcessCreated.$([Guid]::NewGuid().ToString('N'))"
$script:deletionSourceId = "SISRXbox.ProcessDeleted.$([Guid]::NewGuid().ToString('N'))"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    $logDir = Join-Path (Split-Path $ConfigPath -Parent) "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logPath = Join-Path $logDir "watcher.log"
    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss'Z'")
    Add-Content -LiteralPath $logPath -Value ("{0} [{1}] {2}" -f $timestamp, $Level, $Message)
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration not found: $ConfigPath"
    }

    Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    ([IO.Path]::GetFullPath($Path)).TrimEnd([char[]]@('\', '/'))
}

function Test-XboxExecutablePath {
    param([AllowNull()][string]$ExecutablePath)

    (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) -and
        $ExecutablePath.StartsWith($script:xboxPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-SisrExecutablePath {
    param([AllowNull()][string]$ExecutablePath)

    (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) -and
        $ExecutablePath.Equals($script:sisrPath, [StringComparison]::OrdinalIgnoreCase)
}

function Get-RunningProcessSnapshots {
    $snapshots = @()

    foreach ($process in [Diagnostics.Process]::GetProcesses()) {
        try {
            $executablePath = $process.MainModule.FileName
            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $snapshots += [pscustomobject]@{
                    ProcessId = $process.Id
                    Name = $process.ProcessName
                    ExecutablePath = $executablePath
                }
            }
        }
        catch {
            # Protected processes may not expose MainModule to a standard user.
        }
        finally {
            $process.Dispose()
        }
    }

    $snapshots
}

function Update-TrackedState {
    param([Parameter(Mandatory = $true)][object[]]$Snapshots)

    $script:xboxProcessIds.Clear()
    foreach ($snapshot in $Snapshots) {
        if (Test-XboxExecutablePath $snapshot.ExecutablePath) {
            $script:xboxProcessIds.Add([int]$snapshot.ProcessId) | Out-Null
        }
    }

    if ($null -ne $script:ownedSisrProcessId) {
        $ownedSisrStillRunning = @($Snapshots | Where-Object {
            $_.ProcessId -eq $script:ownedSisrProcessId -and
            (Test-SisrExecutablePath $_.ExecutablePath)
        }).Count -gt 0

        if (-not $ownedSisrStillRunning) {
            Write-Log "The SISR process started by the watcher is no longer running (PID=$script:ownedSisrProcessId)."
            $script:ownedSisrProcessId = $null
        }
    }
}

function Start-OwnedSisr {
    $process = Start-Process -FilePath $script:sisrPath -PassThru
    try {
        $script:ownedSisrProcessId = $process.Id
    }
    finally {
        $process.Dispose()
    }

    Write-Log "Xbox game detected; SISR started (PID=$script:ownedSisrProcessId)."
}

function Ensure-SisrForTrackedGames {
    if ($script:xboxProcessIds.Count -eq 0) {
        return
    }

    $snapshots = @(Get-RunningProcessSnapshots)
    $sisrProcesses = @($snapshots | Where-Object { Test-SisrExecutablePath $_.ExecutablePath })

    if ($sisrProcesses.Count -eq 0) {
        Start-OwnedSisr
    }
}

function Stop-OwnedSisrIfIdle {
    if ($null -eq $script:ownedSisrProcessId) {
        return
    }

    if ($script:shutdownDebounceSeconds -gt 0) {
        Start-Sleep -Seconds $script:shutdownDebounceSeconds
    }

    $snapshots = @(Get-RunningProcessSnapshots)
    Update-TrackedState $snapshots

    if ($script:xboxProcessIds.Count -gt 0) {
        Write-Log "SISR shutdown cancelled because an Xbox game is running."
        Ensure-SisrForTrackedGames
        return
    }

    if ($null -eq $script:ownedSisrProcessId) {
        return
    }

    $ownedPid = $script:ownedSisrProcessId
    $ownedProcess = @($snapshots | Where-Object {
        $_.ProcessId -eq $ownedPid -and (Test-SisrExecutablePath $_.ExecutablePath)
    })

    if ($ownedProcess.Count -gt 0) {
        Stop-Process -Id $ownedPid -Force -ErrorAction Stop
        Write-Log "No Xbox games remain; SISR stopped (PID=$ownedPid)."
    }

    $script:ownedSisrProcessId = $null
}

function Sync-State {
    $snapshots = @(Get-RunningProcessSnapshots)
    Update-TrackedState $snapshots

    if ($script:xboxProcessIds.Count -gt 0) {
        Ensure-SisrForTrackedGames
    }
    else {
        Stop-OwnedSisrIfIdle
    }
}

function Start-ProcessEventWatchers {
    $creationQuery = New-Object System.Management.WqlEventQuery(
        "__InstanceCreationEvent",
        (New-TimeSpan -Seconds 1),
        "TargetInstance ISA 'Win32_Process'"
    )
    $deletionQuery = New-Object System.Management.WqlEventQuery(
        "__InstanceDeletionEvent",
        (New-TimeSpan -Seconds 1),
        "TargetInstance ISA 'Win32_Process'"
    )

    $script:creationWatcher = New-Object System.Management.ManagementEventWatcher($creationQuery)
    $script:deletionWatcher = New-Object System.Management.ManagementEventWatcher($deletionQuery)

    Register-ObjectEvent -InputObject $script:creationWatcher -EventName EventArrived -SourceIdentifier $script:creationSourceId | Out-Null
    Register-ObjectEvent -InputObject $script:deletionWatcher -EventName EventArrived -SourceIdentifier $script:deletionSourceId | Out-Null
    $script:creationWatcher.Start()
    $script:deletionWatcher.Start()
}

function Stop-ProcessEventWatchers {
    foreach ($watcher in @($script:creationWatcher, $script:deletionWatcher)) {
        if ($null -ne $watcher) {
            try { $watcher.Stop() } catch {}
            try { $watcher.Dispose() } catch {}
        }
    }

    foreach ($sourceId in @($script:creationSourceId, $script:deletionSourceId)) {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue |
            Remove-Event -ErrorAction SilentlyContinue
    }

    $script:creationWatcher = $null
    $script:deletionWatcher = $null
}

function Invoke-EventWatcherLoop {
    Write-Log "Process monitoring mode: ManagementEventWatcher."
    Sync-State
    $nextReconciliation = [DateTime]::UtcNow.AddSeconds($script:reconciliationIntervalSeconds)

    while ($true) {
        $eventRecord = Wait-Event -Timeout 5

        if ($null -ne $eventRecord) {
            try {
                $instance = $eventRecord.SourceEventArgs.NewEvent.TargetInstance
                $processId = [int]$instance.ProcessId
                $executablePath = [string]$instance.ExecutablePath

                if ($eventRecord.SourceIdentifier -eq $script:creationSourceId) {
                    if (Test-XboxExecutablePath $executablePath) {
                        $script:xboxProcessIds.Add($processId) | Out-Null
                        Write-Log "Xbox process started (PID=$processId): $executablePath"
                        Ensure-SisrForTrackedGames
                    }
                }
                elseif ($eventRecord.SourceIdentifier -eq $script:deletionSourceId) {
                    $wasTracked = $script:xboxProcessIds.Remove($processId)
                    if ($wasTracked -or (Test-XboxExecutablePath $executablePath)) {
                        Write-Log "Xbox process stopped (PID=$processId): $executablePath"
                        if ($script:xboxProcessIds.Count -eq 0) {
                            Stop-OwnedSisrIfIdle
                        }
                    }
                }
            }
            finally {
                Remove-Event -EventIdentifier $eventRecord.EventIdentifier -ErrorAction SilentlyContinue
            }
        }

        if ([DateTime]::UtcNow -ge $nextReconciliation) {
            Sync-State
            $nextReconciliation = [DateTime]::UtcNow.AddSeconds($script:reconciliationIntervalSeconds)
        }
    }
}

function Invoke-PollingLoop {
    Write-Log "Process monitoring mode: polling every $script:pollingIntervalSeconds second(s)." "WARN"

    while ($true) {
        Sync-State
        Start-Sleep -Seconds $script:pollingIntervalSeconds
    }
}

try {
    $config = Get-Config
    $script:xboxRoot = Get-NormalizedPath ([string]$config.XboxGamesPath)
    $script:xboxPrefix = $script:xboxRoot + [IO.Path]::DirectorySeparatorChar
    $script:sisrPath = Get-NormalizedPath ([string]$config.SisrPath)
    $script:shutdownDebounceSeconds = if ($null -ne $config.ShutdownDebounceSeconds) {
        [Math]::Max(0, [int]$config.ShutdownDebounceSeconds)
    } else { 5 }
    $script:pollingIntervalSeconds = if ($null -ne $config.PollingIntervalSeconds) {
        [Math]::Max(1, [int]$config.PollingIntervalSeconds)
    } else { 1 }
    $script:reconciliationIntervalSeconds = 30

    if (-not (Test-Path -LiteralPath $script:xboxRoot -PathType Container)) {
        throw "Xbox Games directory not found: $script:xboxRoot"
    }
    if (-not (Test-Path -LiteralPath $script:sisrPath -PathType Leaf)) {
        throw "SISR executable not found: $script:sisrPath"
    }

    Write-Log "Watcher started. XboxGamesPath=$script:xboxRoot; SisrPath=$script:sisrPath"

    $eventWatchersAvailable = $false
    try {
        Start-ProcessEventWatchers
        $eventWatchersAvailable = $true
    }
    catch {
        Write-Log ("ManagementEventWatcher unavailable; using polling fallback. {0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message) "WARN"
        Stop-ProcessEventWatchers
    }

    if ($eventWatchersAvailable) {
        Invoke-EventWatcherLoop
    }
    else {
        Invoke-PollingLoop
    }
}
catch {
    try {
        Write-Log ("FATAL: {0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message) "ERROR"
        if ($_.ScriptStackTrace) {
            Write-Log ("FATAL stack: {0}" -f ($_.ScriptStackTrace -replace "[\r\n]+", " | ")) "ERROR"
        }
    }
    catch {}

    throw
}
finally {
    Stop-ProcessEventWatchers
    try { Write-Log "Watcher stopped." } catch {}
}
