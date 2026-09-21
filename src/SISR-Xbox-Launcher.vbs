Option Explicit

Dim shell
Dim fileSystem
Dim installDirectory
Dim watcherPath
Dim configPath
Dim powershellPath
Dim command
Dim exitCode

Function Quote(ByVal value)
    Quote = Chr(34) & value & Chr(34)
End Function

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

installDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
watcherPath = fileSystem.BuildPath(installDirectory, "SISR-Xbox-Watcher.ps1")
configPath = fileSystem.BuildPath(installDirectory, "config.json")
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")

command = Quote(powershellPath) & _
    " -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass" & _
    " -File " & Quote(watcherPath) & _
    " -ConfigPath " & Quote(configPath)

' Window style 0 keeps Console Host hidden. Waiting for PowerShell ensures
' Task Scheduler continues to track the lifetime and exit code of the watcher.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
