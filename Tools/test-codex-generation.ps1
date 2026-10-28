# 専用の疑似app-serverを使い、実パイプでの自動修正と実行中止を再現する。モデルは呼ばない。
param([ValidateSet('Debug','Release')][string]$Config='Debug')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Automation/MapRakuPipe.psm1') -Force
$output = Join-Path $root 'TestOutput/Generation/Fixture'
$null = New-Item -ItemType Directory -Path $output -Force
$encoding = [Text.UTF8Encoding]::new($true)
$fixtureSource = Join-Path $root 'Tests/Generation/MapRakuCodexFixture.dpr'
[IO.File]::WriteAllText($fixtureSource,[IO.File]::ReadAllText($fixtureSource),$encoding)
$project = [IO.File]::ReadAllText((Join-Path $root 'MapRaku.dproj'))
$project = $project.Replace('<MainSource>MapRaku.dpr</MainSource>',"<MainSource>$fixtureSource</MainSource>")
$project = $project.Replace('<AppType>Application</AppType>','<AppType>Console</AppType>')
$project = [regex]::Replace($project,'<Icon_MainIcon>.*?</Icon_MainIcon>','')
$project = [regex]::Replace($project,'<DCC_ExeOutput>.*?</DCC_ExeOutput>',"<DCC_ExeOutput>$output</DCC_ExeOutput>")
$project = [regex]::Replace($project,'<DCC_DcuOutput>.*?</DCC_DcuOutput>',"<DCC_DcuOutput>$output/DCU</DCC_DcuOutput>")
$projectPath = Join-Path $output 'MapRakuCodexFixture.dproj'
[IO.File]::WriteAllText($projectPath,$project,$encoding)
$buildLine = 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "' + $projectPath + '" /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo'
& $env:ComSpec /d /s /c $buildLine
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$fixtureExe = Join-Path $output 'MapRakuCodexFixture.exe'
foreach ($mode in @('repair','tamper','wait')) {
    $app = Start-Process -FilePath (Join-Path $root "TestOutput/Plugin/$Config/MapRakuPluginTests.exe") -ArgumentList '-serve','-test' -WorkingDirectory $root -WindowStyle Hidden -PassThru -Environment @{
        CODEX_PIPE_EXE=$fixtureExe; MAPRAKU_CODEX_FIXTURE_MODE=$mode
    }
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            $endpoints = @(Get-MapRakuEndpoints | Where-Object { $_ -like "MapRaku.Plugin.$($app.Id).*" })
            if ($endpoints.Count -eq 1) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($endpoints.Count -ne 1) { throw 'Fixture test endpoint not found uniquely' }
        Set-MapRakuEndpoint $endpoints[0]
        $before = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
        $start = New-MapRakuMutation 'generation_start'
        $start.request = @{place_query='通信試験の架空駅';span_m=1000;north_clockwise_degrees=0}
        $started = (Invoke-MapRakuPipe $start).generation
        if (-not $started.busy) { throw 'Worker was not started' }
        if ($mode -eq 'wait') {
            # turn/startの応答待ちでも中止でき、元文書を変更しないことを検証する。
            Start-Sleep -Milliseconds 700
            $cancel = New-MapRakuMutation 'generation_cancel'; $cancel.generation_id = $started.generation_id
            $null = Invoke-MapRakuPipe $cancel
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            Start-Sleep -Milliseconds 100
            $status = (Invoke-MapRakuPipe @{command='generation_status'}).generation
        } while ($status.busy -and [DateTime]::UtcNow -lt $deadline)
        if ($status.busy) { throw "Fixture worker did not finish: $mode" }
        if ($mode -eq 'repair') {
            if ($status.state -ne 'ready' -or -not $status.repair_attempted) { throw "Repair failed: $($status.message)" }
            $result = (Invoke-MapRakuPipe @{command='generation_get_result'}).generation
            if ($result.document.layers.Count -ne 2 -or -not $result.can_apply) { throw 'Repaired candidate mismatch' }
            if ($result.source -ne 'codex_app_server' -or $result.generation_id -cne $started.generation_id) { throw 'Repair changed session identity' }
        } elseif ($mode -eq 'tamper') {
            if ($status.state -ne 'failed' -or -not $status.repair_attempted) { throw 'Repair changed geography without rejection' }
        } elseif ($status.state -ne 'cancelled') { throw "Cancel failed: $($status.state)" }
        if ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -cne $before.state_token) { throw 'Worker changed live document' }
        Write-Output "PASS simulated app-server $mode $Config"
    } finally {
        if (-not $app.HasExited) { $null=$app.CloseMainWindow(); if (-not $app.WaitForExit(5000)) { Stop-Process -Id $app.Id } }
    }
}
@{simulated_repair='passed';repair_geography_protection='passed';simulated_cancel='passed';config=$Config} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $output 'transport-report.json') -Encoding utf8
