param([ValidateSet('Debug','Release')][string]$Config = 'Debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$setup = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$buildLine = 'call "' + $setup + '" && msbuild "' + (Join-Path $projectRoot 'MapRaku.dproj') + '" /t:Build /p:Config=' + $Config + ' /p:Platform=Win64 /v:minimal /nologo'
& $env:ComSpec /d /s /c $buildLine
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$outputPath = Join-Path $projectRoot ('Win64\' + $Config)
Copy-Item -LiteralPath (Join-Path $projectRoot 'Lib\Skia\Win64\sk4d.dll') -Destination $outputPath
