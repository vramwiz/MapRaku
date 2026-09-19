@echo off
setlocal
set "TARGET=%~dp0..\Lib\Skia\Win64\sk4d.dll"
set "SOURCE=D:\DelphiProg\SYNC_ScreenLayout\Lib\Skia\Win64\sk4d.dll"

if exist "%TARGET%" exit /b 0
if not exist "%SOURCE%" (
    echo Skia runtime not found: "%SOURCE%" 1>&2
    exit /b 1
)
if not exist "%~dp0..\Lib\Skia\Win64" mkdir "%~dp0..\Lib\Skia\Win64" || exit /b 1
copy /Y "%SOURCE%" "%TARGET%" >nul || exit /b 1
exit /b 0
