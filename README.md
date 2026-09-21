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

It installs the watcher under `%LOCALAPPDATA%\SISRXboxAutoLauncher` and creates a Scheduled Task that starts it at user logon.

> Running `irm | iex` executes remote code directly. If you prefer to inspect it first, download `Install.ps1`, review it, then run it locally.

## How it works

The watcher subscribes to Windows process start/stop events and checks running executable paths. Any executable below the configured Xbox Games root counts as an Xbox game.

SISR is only stopped automatically if this watcher started it. If SISR was already running manually, it is left running.

A short shutdown debounce (default: 5 seconds) avoids stopping SISR during launcher/anti-cheat process transitions.

## Configuration

`%LOCALAPPDATA%\SISRXboxAutoLauncher\config.json`

Example:

```json
{
  "XboxGamesPath": "D:\\XboxGames",
  "SisrPath": "C:\\Path\\To\\SISR.exe",
  "ShutdownDebounceSeconds": 5
}
```

Re-run the installer to update the watcher or change paths.

## Logs

`%LOCALAPPDATA%\SISRXboxAutoLauncher\logs\watcher.log`

## Uninstall

```powershell
irm "https://raw.githubusercontent.com/Davhel98/SISR-Xbox-AutoLauncher/main/Uninstall.ps1" | iex
```
