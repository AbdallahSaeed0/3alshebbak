' Starts booking-presales-local.ps1 with no window at all. Task Scheduler runs
' this through wscript.exe (which has no console), because powershell.exe
' flashes a window for a moment even with -WindowStyle Hidden.
' Waits for the script and hands its exit code back to the task.
Dim shell, script, code
Set shell = CreateObject("WScript.Shell")
script = Replace(WScript.ScriptFullName, "booking-presales-hidden.vbs", "booking-presales-local.ps1")
code = shell.Run("powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """", 0, True)
WScript.Quit code
