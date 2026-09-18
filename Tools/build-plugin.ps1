# IDEと共通のプロジェクト設定でビルドし、地図プラグインをホストへ配置する。
param([ValidateSet('Debug','Release')][string]$Config = 'Debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$setup = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$buildLine = 'call "' + $setup + '" && msbuild "' + (Join-Path $projectRoot 'SYNC_MapRaku_Filter.dproj') + '" /t:Build /p:Config=' + $Config + ' /p:Platform=Win64 /v:minimal /nologo'
& $env:ComSpec /d /s /c $buildLine
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$outputPath = Join-Path $projectRoot ('Win64\Plugin\' + $Config)
Write-Output ('Plugin: ' + (Join-Path $outputPath 'SYNC_MapRaku_Filter.auf2'))
