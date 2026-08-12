' Lanza el widget de costos Azure sin ventana de consola
Set sh = CreateObject("Wscript.Shell")
ruta = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ruta & "CostosAzureWidget.ps1""", 0, False
