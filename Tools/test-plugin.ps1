# 実DLLのABIと共通UIを疑似ホストで検証する。AviUtl2本体の操作は行わない。
param([ValidateSet('Debug','Release')][string]$Config = 'Debug')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$encoding = [Text.UTF8Encoding]::new($true)
$source = [IO.File]::ReadAllText((Join-Path $root 'SYNC_MapRaku_Filter.dpr'))
$units = $source.Substring($source.IndexOf('uses'), $source.IndexOf('function InitializePlugin') - $source.IndexOf('uses'))
$units = $units.Replace('  Vcl.Forms,', "  System.SysUtils,`r`n  MapRakuPluginTests in 'Tests\Plugin\MapRakuPluginTests.pas',`r`n  Vcl.Forms,")
$main = @'
begin
  try
    Application.Initialize;
    if FindCmdLineSwitch('serve', True) then ServePluginEditor
    else RunPluginTests(ParamStr(1));
  except
    on E: Exception do begin Writeln('FAIL: ' + E.ClassName + ': ' + E.Message); Halt(1); end;
  end;
end.
'@
$output = Join-Path $root "TestOutput\Plugin\$Config"
$null = New-Item -ItemType Directory -Path $output -Force
$dpr = Join-Path $root 'TestOutput\MapRakuPluginTests.dpr'
# DPR内のパスはプロジェクトルートからの相対指定なのでMSBuild側でルートを使用する。
[IO.File]::WriteAllText($dpr, "program MapRakuPluginTestsRunner;`r`n{`$APPTYPE CONSOLE}`r`n" + $units + $main, $encoding)
$project = [IO.File]::ReadAllText((Join-Path $root 'SYNC_MapRaku_Filter.dproj'))
# テストEXEにはホスト起動・配置イベントを継承させない。
$project = [regex]::Replace($project, '(?s)<(PreBuildEvent|PostBuildEvent|Debugger_HostApplication|Debugger_WorkingDirectory)>.*?</\1>', '')
$project = $project.Replace('<AppType>Library</AppType>', '<AppType>Console</AppType>').Replace('<GenDll>true</GenDll>', '<GenDll>false</GenDll>')
$project = $project.Replace('<MainSource>SYNC_MapRaku_Filter.dpr</MainSource>', '<MainSource>TestOutput\MapRakuPluginTests.dpr</MainSource>')
$project = [regex]::Replace($project, '<DCC_ExeOutput>.*?</DCC_ExeOutput>', "<DCC_ExeOutput>$output</DCC_ExeOutput>")
$project = [regex]::Replace($project, '<DCC_DcuOutput>.*?</DCC_DcuOutput>', "<DCC_DcuOutput>$output\DCU</DCC_DcuOutput>")
$testProject = Join-Path $root 'MapRakuPluginTests.dproj'
[IO.File]::WriteAllText($testProject, $project, $encoding)
$buildLine = 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "' + $testProject + '" /t:Build /p:Config=' + $Config + ' /p:Platform=Win64 /v:minimal /nologo'
& $env:ComSpec /d /s /c $buildLine
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item -LiteralPath (Join-Path $root 'Lib\Skia\Win64\sk4d.dll') -Destination $output
& (Join-Path $output 'MapRakuPluginTests.exe') (Join-Path $root "Win64\Plugin\$Config\SYNC_MapRaku_Filter.auf2") -test
exit $LASTEXITCODE
