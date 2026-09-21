# SISR Xbox AutoLauncher

Automatically starts SISR when a running executable is located under your Xbox Games directory and stops it after the last Xbox game exits.

## Install

Open **Windows PowerShell** and run:

```powershell
irm "https://raw.githubusercontent.com/Davhel98/SISR-Xbox-AutoLauncher/main/Install.ps1" | iex
```

The installer asks for:

1. The common Xbox Games directory, for example `D:\XboxGames`.
2. The full path to the SISR executable.

It installs the watcher and maintenance scripts under `%LOCALAPPDATA%\SISRXboxAutoLauncher` and creates Scheduled Tasks that run at user logon.

> Running `irm | iex` executes remote code directly. If you prefer to inspect it first, download `Install.ps1`, review it, then run it locally.

## How it works

The watcher uses `System.Management.ManagementEventWatcher` with the non-elevated WMI intrinsic events `__InstanceCreationEvent` and `__InstanceDeletionEvent`. Any running executable below the configured Xbox Games root counts as an Xbox game.

Some Xbox/GDK games installed under `XboxGames` are exposed as running from `C:\Program Files\WindowsApps` instead of their visible installation path. The watcher resolves these projected paths through the local Gaming Services package repository and the Content ID markers stored in each Xbox game directory. No per-game process list is required.

The Scheduled Task runs with the normal permissions of the signed-in user; administrator privileges are not required. If WMI event subscriptions are unavailable in a restricted environment, the watcher automatically falls back to lightweight process polling instead of exiting.

SISR is only stopped automatically if this watcher started it. If SISR was already running manually, it is left running.

A short shutdown debounce (default: 5 seconds) avoids stopping SISR during launcher/anti-cheat process transitions.

The event-driven mode also reconciles its state periodically so that a missed or inaccessible process event cannot leave SISR in the wrong state.

## Automatic log cleanup

At every user logon, the `SISR Xbox AutoLauncher Log Cleanup` Scheduled Task runs once and deletes log files from:

`%LOCALAPPDATA%\SISRXboxAutoLauncher\logs`

whose last-write time is more than 24 hours old. The cleanup task also runs once immediately after installation.

## Configuration

`%LOCALAPPDATA%\SISRXboxAutoLauncher\config.json`

Example:

```json
{
  "XboxGamesPath": "D:\\XboxGames",
  "SisrPath": "C:\\Path\\To\\SISR.exe",
  "ShutdownDebounceSeconds": 5,
  "PollingIntervalSeconds": 1
}
```

Re-run the installer to update the watcher, cleanup script, or configured paths.

## Logs

`%LOCALAPPDATA%\SISRXboxAutoLauncher\logs\watcher.log`

The log records the selected monitoring mode, Xbox process transitions, SISR start/stop actions, fallback activation, and fatal errors.

## SISR

This project is an independent helper utility for [SISR (Steam Input System Redirector)](https://github.com/Alia5/SISR).

SISR is developed by Peter Repukat (Alia5) and is distributed under its own license, the GNU General Public License v3.0 or later.

SISR Xbox AutoLauncher is not affiliated with, endorsed by, or part of the official SISR project. This repository does not distribute or contain SISR itself. Users must obtain SISR separately from the official SISR project.

## License

SISR Xbox AutoLauncher is released under the MIT License. See [LICENSE](LICENSE).

The MIT License applies only to SISR Xbox AutoLauncher and does not apply to SISR or other third-party software.

## Uninstall

```powershell
irm "https://raw.githubusercontent.com/Davhel98/SISR-Xbox-AutoLauncher/main/Uninstall.ps1" | iex
```

The uninstaller removes both Scheduled Tasks and all locally installed files.
