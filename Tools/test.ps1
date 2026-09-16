$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$enc = [Text.UTF8Encoding]::new($true)
$source = [IO.File]::ReadAllText((Join-Path $root 'MapRaku.dpr'))
$units = $source.Substring($source.IndexOf('uses'),$source.IndexOf('{$R')-$source.IndexOf('uses'))
$units = $units.Replace('  Vcl.Forms,',"  System.SysUtils,`r`n  MapRakuTestCases in 'Tests\MapRakuTestCases.pas',`r`n  Vcl.Forms,")
$main = @'
begin
  try
    Application.Initialize;
    RunMapTests;
  except on E: Exception do begin Writeln('FAIL: ' + E.Message); Halt(1); end; end;
end.
'@
[IO.File]::WriteAllText((Join-Path $root 'Tests\MapRakuTests.dpr'),"program MapRakuTests;`r`n{`$APPTYPE CONSOLE}`r`n"+$units+$main,$enc)
$project = [IO.File]::ReadAllText((Join-Path $root 'MapRaku.dproj'))
$project = $project.Replace('<MainSource>MapRaku.dpr</MainSource>','<MainSource>Tests\MapRakuTests.dpr</MainSource>')
$project = $project.Replace('<DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>','<DCC_ExeOutput>$(MSBuildProjectDirectory)\TestOutput</DCC_ExeOutput>')
$project = $project.Replace('<DCC_DcuOutput>.\$(Platform)\$(Config)</DCC_DcuOutput>','<DCC_DcuOutput>.\TestOutput\DCU</DCC_DcuOutput>')
[IO.File]::WriteAllText((Join-Path $root 'MapRakuTests.dproj'),$project,$enc)
New-Item -ItemType Directory TestOutput -Force | Out-Null
$buildLine='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild MapRakuTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo'
& $env:ComSpec /d /s /c $buildLine
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item Lib/Skia/Win64/sk4d.dll TestOutput
& ./TestOutput/MapRakuTests.exe -test
exit $LASTEXITCODE
