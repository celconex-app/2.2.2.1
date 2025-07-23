@echo off
set ICON_PATH=%~dp0celconex_icon.ico
set APP_PATH=%~dp0CelconexInstaller.exe
set SHORTCUT_NAME=Celconex.lnk
set DESKTOP=%USERPROFILE%\Desktop

echo Set oWS = WScript.CreateObject("WScript.Shell") > temp.vbs
echo sLinkFile = "%DESKTOP%\%SHORTCUT_NAME%" >> temp.vbs
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> temp.vbs
echo oLink.TargetPath = "%APP_PATH%" >> temp.vbs
echo oLink.IconLocation = "%ICON_PATH%" >> temp.vbs
echo oLink.Description = "Celconex – Compartir datos móviles" >> temp.vbs
echo oLink.Save >> temp.vbs

cscript //nologo temp.vbs
del temp.vbs

echo ✅ Acceso directo creado en el escritorio.
pause