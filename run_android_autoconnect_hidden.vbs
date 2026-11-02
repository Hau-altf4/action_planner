Option Explicit

Dim fileSystem, shell, scriptDirectory, watcherPath, command

Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
watcherPath = fileSystem.BuildPath(scriptDirectory, "keep_android_connected.ps1")
command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass " & _
  "-WindowStyle Hidden -File " & Chr(34) & watcherPath & Chr(34) & " -Once"

' Window style 0 runs PowerShell without creating a visible console window.
shell.Run command, 0, True
