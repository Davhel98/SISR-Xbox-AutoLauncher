param([string]$LogDirectory = "$env:LOCALAPPDATA\SISRXboxAutoLauncher\logs")

$ErrorActionPreference = "Stop"
$RetentionHours = 24

if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
    exit 0
}

$cutoff = (Get-Date).AddHours(-$RetentionHours)

Get-ChildItem -LiteralPath $LogDirectory -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue
