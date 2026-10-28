# 元画像→確認→画像からデータ化→採用の各段階を、専用に起動した編集画面で検証する。
# 既定は疑似app-server。-Liveだけが実Codexの画像生成・画像読取を実行する。
param([ValidateSet('Debug','Release')][string]$Config='Debug', [switch]$PluginEditor, [switch]$Live)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Automation/MapRakuPipe.psm1') -Force
. (Join-Path $root 'Tests/Automation/MapRakuSample.ps1')
$output=Join-Path $root "TestOutput/ImageGeneration/$Config"
$null=New-Item -ItemType Directory -Path $output -Force
$fixture=Join-Path $root 'TestOutput/Generation/Fixture/MapRakuCodexFixture.exe'
if(-not $Live -and -not (Test-Path -LiteralPath $fixture)){throw 'Run Tools/test-codex-generation.ps1 first.'}
if(-not $PluginEditor -and (Get-Process MapRaku -ErrorAction SilentlyContinue)){throw 'Close MapRaku before isolated image tests.'}
$sourcePath=Join-Path $output 'fixture-source.png'
if(-not $Live){[IO.File]::WriteAllBytes($sourcePath,(New-MapRakuSampleReference))}
function Assert-Image($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Wait-ImageJob {
    $deadline=[DateTime]::UtcNow.AddSeconds($(if($Live){1000}else{25}))
    do {
        Start-Sleep -Milliseconds $(if($Live){1500}else{100})
        $status=(Invoke-MapRakuPipe @{command='generation_status'}).generation
    } while($status.busy -and [DateTime]::UtcNow -lt $deadline)
    Assert-Image (-not $status.busy) 'Image worker still running'
    return $status
}
$modes=if($Live){@('live')}else{@('image_path','image_base64','image_options','image_missing','image_hash_mismatch')}
foreach($mode in $modes){
    $startOptions=@{WorkingDirectory=$root;WindowStyle='Hidden';PassThru=$true}
    if($PluginEditor){
        $startOptions.FilePath=Join-Path $root "TestOutput/Plugin/$Config/MapRakuPluginTests.exe"
        $startOptions.ArgumentList=@('-serve','-test')
    } else {
        $startOptions.FilePath=Join-Path $root "Win64/$Config/MapRaku.exe"
        $startOptions.ArgumentList=@('-test')
    }
    if(-not $Live){$startOptions.Environment=@{CODEX_PIPE_EXE=$fixture;MAPRAKU_CODEX_FIXTURE_MODE=$mode;MAPRAKU_CODEX_FIXTURE_PNG=$sourcePath}}
    $app=Start-Process @startOptions
    try {
        if($PluginEditor){
            $deadline=[DateTime]::UtcNow.AddSeconds(25)
            do {
                $endpoints=@(Get-MapRakuEndpoints | Where-Object {$_ -like "MapRaku.Plugin.$($app.Id).*"})
                if($endpoints.Count -eq 1){break};Start-Sleep -Milliseconds 100
            } while([DateTime]::UtcNow -lt $deadline)
            Assert-Image ($endpoints.Count -eq 1) 'Image test endpoint not unique'
            Set-MapRakuEndpoint $endpoints[0]
        } else {Set-MapRakuEndpoint 'MapRaku.v1'}
        $caps=Invoke-MapRakuPipe @{command='get_capabilities'} -TimeoutMs 30000
        Assert-Image ($caps.process_id -eq $app.Id) 'Wrong image test process'
        $before=(Invoke-MapRakuPipe @{command='get_document'}).snapshot
        $start=New-MapRakuMutation 'generation_start_image'
        $start.request=@{place_query=$(if($Live){'東京都千代田区 東京駅 丸の内口'}else{'通信試験の架空駅'});span_m=1000;north_clockwise_degrees=0;instructions='道路・鉄道・主要施設を優先した、文字の少ない簡略案内図。'}
        $started=(Invoke-MapRakuPipe $start).generation;$id=$started.generation_id
        $status=Wait-ImageJob
        if($mode -eq 'image_missing'){
            Assert-Image ($status.state -eq 'failed' -and -not $status.has_image -and -not $status.can_apply) 'Missing native image notification accepted'
            Write-Output "PASS image workflow $Config $mode"
            continue
        }
        Assert-Image ($status.state -eq 'image_ready' -and $status.can_trace -and -not $status.can_apply) "Image stage failed: $($status.message)"
        Assert-Image ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $before.state_token) 'Image stage modified document'
        $image=(Invoke-MapRakuPipe @{command='generation_get_image'}).generation
        $bytes=Receive-MapRakuBlob $image.image
        [IO.File]::WriteAllBytes((Join-Path $output ($mode+'-source.png')),$bytes)
        Assert-Image ($image.image.sha256 -ceq $status.image_sha256) 'Displayed image hash mismatch'
        Start-Sleep -Milliseconds 300
        Assert-Image ((Invoke-MapRakuPipe @{command='generation_status'}).generation.state -eq 'image_ready') 'Image stage advanced without confirmation'
        $wrong=New-MapRakuMutation 'generation_trace_image';$wrong.generation_id=$id;$wrong.image_sha256='wrong'
        Assert-Image ((Invoke-MapRakuPipe $wrong -AllowError).status -eq 'error') 'Wrong confirmed image accepted'
        $request=(Invoke-MapRakuPipe @{command='generation_get_request'}).generation
        Assert-Image ($request.output_schema.required -contains 'source_image_sha256') 'Trace output identity missing'
        Assert-Image ($request.output_schema.required -contains 'trace_options_token') 'Trace options identity missing'
        Assert-Image ((Invoke-MapRakuPipe @{command='generation_status'}).generation.state -eq 'image_ready') 'Request query changed workflow state'
        if($mode -eq 'image_options'){
            $change=New-MapRakuMutation 'generation_set_trace_options';$change.generation_id=$id;$change.image_sha256=$status.image_sha256
            $change.options=@{zoom=2;pan_x=0.12;pan_y=-0.1;rotation_degrees=450;simplification=80}
            $status=(Invoke-MapRakuPipe $change).generation
            $replay=(Invoke-MapRakuPipe $change).generation
            Assert-Image ($replay.trace_options_token -ceq $status.trace_options_token) 'Option mutation replay mismatch'
            Assert-Image ($status.trace_options.rotation_degrees -eq 90 -and $status.trace_options.simplification -eq 80) 'Rotation normalization or simplification failed'
            $bad=New-MapRakuMutation 'generation_set_trace_options';$bad.generation_id=$id;$bad.image_sha256=$status.image_sha256;$bad.options=@{zoom=0}
            Assert-Image ((Invoke-MapRakuPipe $bad -AllowError).status -eq 'error') 'Zero zoom accepted'
            $bad=New-MapRakuMutation 'generation_set_trace_options';$bad.generation_id=$id;$bad.image_sha256=$status.image_sha256;$bad.options=@{simplification=101}
            Assert-Image ((Invoke-MapRakuPipe $bad -AllowError).status -eq 'error') 'Out-of-range simplification accepted'
            $request=(Invoke-MapRakuPipe @{command='generation_get_request'}).generation
            Assert-Image ($request.request.span_m -eq 500 -and $request.request.north_clockwise_degrees -eq 90) 'Effective range/north metadata mismatch'
            Assert-Image (($request.prompt | ConvertFrom-Json).request.trace_options.simplification -eq 80) 'Simplification not included in model prompt'
            $wrong=New-MapRakuMutation 'generation_trace_image';$wrong.generation_id=$id;$wrong.image_sha256=$status.image_sha256;$wrong.trace_options_token='outdated'
            Assert-Image ((Invoke-MapRakuPipe $wrong -AllowError).status -eq 'error') 'Outdated options accepted'
        }
        $reference=(Invoke-MapRakuPipe @{command='generation_get_trace_image'}).generation
        $traceBytes=Receive-MapRakuBlob $reference.image
        Assert-Image ($reference.image.sha256 -ceq $reference.trace_image_sha256) 'Trace reference blob hash mismatch'
        if($mode -eq 'image_options'){
            Assert-Image ($reference.trace_image_sha256 -cne $image.image.sha256) 'View transform did not alter trace image'
            [IO.File]::WriteAllBytes((Join-Path $output 'transformed-reference.png'),$traceBytes)
        }
        $trace=New-MapRakuMutation 'generation_trace_image';$trace.generation_id=$id;$trace.image_sha256=$status.image_sha256
        $trace.trace_options_token=$reference.trace_options_token
        $null=Invoke-MapRakuPipe $trace;$status=Wait-ImageJob
        if($mode -eq 'image_hash_mismatch'){
            Assert-Image ($status.state -eq 'failed' -and -not $status.can_apply) 'Wrong image in model reply accepted'
            Write-Output "PASS image workflow $Config $mode"
            continue
        }
        Assert-Image ($status.state -eq 'ready' -and $status.can_apply) "Trace failed: $($status.message)"
        $result=(Invoke-MapRakuPipe @{command='generation_get_result'}).generation
        Assert-Image ($result.response.source_image_sha256 -ceq $reference.trace_image_sha256) 'Trace result image mismatch'
        Assert-Image ($result.response.trace_options_token -ceq $reference.trace_options_token) 'Trace result options mismatch'
        Assert-Image ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $before.state_token) 'Trace stage modified document'
        if(-not $Live){
            Assert-Image ($status.repair_attempted -and $result.document.layers.Count -eq 4) 'Trace repair failed'
            $polygon=$result.document.layers | Where-Object id -eq 'fixture-poly'
            $text=$result.document.layers | Where-Object id -eq 'fixture-text'
            Assert-Image ($polygon.type -eq 'shape' -and $polygon.contours[0].vertices.Count -eq 4) 'Editable polygon missing'
            Assert-Image ([Math]::Abs($text.rotation+30) -lt 0.01) 'Text rotation missing'
        }
        Assert-Image (@($result.document.layers | Where-Object type -eq 'image').Count -eq 0) 'Source pasted instead of traced'
        $queried=(Invoke-MapRakuPipe @{command='generation_get_request'}).generation
        Assert-Image ($queried.state -eq 'ready' -and $queried.can_apply -and $queried.candidate_token -ceq $status.candidate_token) 'Read-only request query invalidated ready candidate'
        if($mode -eq 'image_options'){
            $change=New-MapRakuMutation 'generation_set_trace_options';$change.generation_id=$id;$change.image_sha256=$status.image_sha256;$change.options=@{simplification=81}
            $status=(Invoke-MapRakuPipe $change).generation
            Assert-Image ($status.state -eq 'image_ready' -and -not $status.can_apply -and $status.trace_options.zoom -eq 2 -and $status.trace_options.rotation_degrees -eq 90) 'Partial option patch did not preserve view or invalidate candidate'
            $oldApply=New-MapRakuMutation 'generation_apply';$oldApply.generation_id=$id
            Assert-Image ((Invoke-MapRakuPipe $oldApply -AllowError).status -eq 'error') 'Stale candidate adopted after options changed'
            $prepare=New-MapRakuMutation 'generation_prepare_trace';$prepare.generation_id=$id;$prepare.image_sha256=$status.image_sha256
            $null=Invoke-MapRakuPipe $prepare
            $oldReply=New-MapRakuMutation 'generation_submit_result';$oldReply.generation_id=$id;$oldReply.response=$result.response | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
            Assert-Image ((Invoke-MapRakuPipe $oldReply -AllowError).status -eq 'error') 'Reply for stale simplification accepted'
            $trace=New-MapRakuMutation 'generation_trace_image';$trace.generation_id=$id;$trace.image_sha256=$status.image_sha256;$trace.trace_options_token=$status.trace_options_token
            $null=Invoke-MapRakuPipe $trace;$status=Wait-ImageJob
            Assert-Image ($status.state -eq 'ready' -and $status.can_apply) 'Trace after option change failed'
            $result=(Invoke-MapRakuPipe @{command='generation_get_result'}).generation
        }
        $apply=New-MapRakuMutation 'generation_apply';$apply.generation_id=$id;$null=Invoke-MapRakuPipe $apply
        $applied=(Invoke-MapRakuPipe @{command='get_document'}).snapshot
        Assert-Image ($applied.document.layers.Count -eq $result.document.layers.Count) 'Adopted layer count mismatch'
        $null=Invoke-MapRakuPipe (New-MapRakuMutation 'undo')
        Assert-Image ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $before.state_token) 'Image workflow undo failed'
        $null=Invoke-MapRakuPipe (New-MapRakuMutation 'redo')
        Assert-Image ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $applied.state_token) 'Image workflow redo failed'
        if($Live){$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $output 'live-result.json') -Encoding utf8}
    } finally {
        # 自分で起動した試験専用PIDだけを終了し、Releaseの保存確認を残さない。
        if(-not $app.HasExited){Stop-Process -Id $app.Id}
    }
    Write-Output "PASS image workflow $Config $mode"
}
@{config=$Config;plugin_editor=[bool]$PluginEditor;live=[bool]$Live;modes=$modes;status='passed'} | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $output $(if($PluginEditor){'report-plugin.json'}else{'report-standalone.json'})) -Encoding utf8
