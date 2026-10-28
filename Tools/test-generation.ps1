# 専用に起動した編集画面へパイプ接続し、地名生成の受渡し・拒否・反映を検証する。
# 通常は架空の応答で契約を検証する。-Liveだけが実Codexへ公開地名を送る。
param([ValidateSet('Debug','Release')][string]$Config='Debug', [switch]$PluginEditor, [switch]$Live, [switch]$RequireMap)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Automation/MapRakuPipe.psm1') -Force
function Assert-Generation($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Send-Generation([string]$Command, [hashtable]$Fields=@{}) {
    $request = New-MapRakuMutation $Command
    foreach ($key in $Fields.Keys) { $request[$key] = $Fields[$key] }
    Invoke-MapRakuPipe $request
}
function Reject-Generation([string]$Command, [hashtable]$Fields) {
    $request = New-MapRakuMutation $Command
    foreach ($key in $Fields.Keys) { $request[$key] = $Fields[$key] }
    $response = Invoke-MapRakuPipe $request -AllowError
    Assert-Generation ($response.status -eq 'error') "Invalid request accepted: $Command"
}
function Copy-GenerationReply($Response) {
    $Response | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100
}
if (-not $PluginEditor -and (Get-Process MapRaku -ErrorAction SilentlyContinue)) {
    throw 'Close MapRaku before running isolated generation tests.'
}
$output = Join-Path $root "TestOutput/Generation/$Config"
$null = New-Item -ItemType Directory -Path $output -Force
if ($PluginEditor) {
    $app = Start-Process -FilePath (Join-Path $root "TestOutput/Plugin/$Config/MapRakuPluginTests.exe") -ArgumentList '-serve','-test' -WorkingDirectory $root -WindowStyle Hidden -PassThru
} else {
    $app = Start-Process -FilePath (Join-Path $root "Win64/$Config/MapRaku.exe") -ArgumentList '-test' -WorkingDirectory $root -WindowStyle Hidden -PassThru
}
try {
    if ($PluginEditor) {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            if ($app.HasExited) { throw 'Plugin test editor exited.' }
            $endpoints = @(Get-MapRakuEndpoints | Where-Object { $_ -like "MapRaku.Plugin.$($app.Id).*" })
            if ($endpoints.Count -eq 1) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)
        Assert-Generation ($endpoints.Count -eq 1) 'Plugin endpoint not found uniquely'
        Set-MapRakuEndpoint $endpoints[0]
    }
    $caps = Invoke-MapRakuPipe @{command='get_capabilities'} -TimeoutMs 30000
    Assert-Generation ($caps.process_id -eq $app.Id) 'Wrong process'
    Assert-Generation ($caps.capabilities.commands -contains 'generation_start') 'Missing generation commands'
    $before = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    $input = @{place_query='通信試験用の架空駅 日本語😀';span_m=1200;north_clockwise_degrees=90;instructions="道路と線路を配置。`n2行目は条件の往復確認。"}
    $prepare = New-MapRakuMutation 'generation_prepare'; $prepare.request = $input
    $prepared = (Invoke-MapRakuPipe $prepare).generation
    $retry = (Invoke-MapRakuPipe $prepare).generation
    Assert-Generation ($prepared.generation_id -ceq $retry.generation_id) 'Prepare retry started another generation'
    $id = $prepared.generation_id
    $envelope = (Invoke-MapRakuPipe @{command='generation_get_request'}).generation
    Assert-Generation ($envelope.request.place_query -ceq $input.place_query) 'Japanese place mismatch'
    Assert-Generation ($envelope.request.instructions -ceq $input.instructions) 'Multiline condition mismatch'
    $prompt = $envelope.prompt | ConvertFrom-Json -Depth 100
    Assert-Generation ($prompt.request.generation_id -ceq $id) 'Prompt request ID mismatch'
    Assert-Generation ($prompt.map_contract.origin -eq 'canvas_center') 'Map coordinate contract missing'
    $operations = @{
        operations=@(
            @{op='add';spec=@{kind='road';id='fixture-road';name='通信試験の道路';width=24;vertices=@(@{x=-250;y=0},@{x=250;y=0})}},
            @{op='add';spec=@{kind='jr';id='fixture-jr';name='通信試験の線路';width=12;vertices=@(@{x=0;y=-200},@{x=0;y=200})}},
            @{op='crossing';a='fixture-road';b='fixture-jr';kind=4;upper='fixture-jr';margin=14},
            @{op='add';spec=@{kind='building';id='fixture-hall';name='通信試験の施設';x=130;y=100;width=100;height=50}}
        )
    }
    $reply = @{
        generation_id=$id;outcome='ready';place_label=$input.place_query;latitude=35.0;longitude=139.0
        span_m=1200;north_clockwise_degrees=90;canvas_width=$envelope.request.canvas_width;canvas_height=$envelope.request.canvas_height
        message='通信試験用の架空地図です。実在地点の精度検証ではありません。'
        sources=@(@{title='通信試験の仮出典';url='https://example.invalid/mapraku-fixture'})
        warnings=@('この応答は通信テスト専用');operations_json=($operations | ConvertTo-Json -Depth 100 -Compress)
    }
    $invalid = Copy-GenerationReply $reply; $invalid.generation_id = 'wrong-id'
    Reject-Generation 'generation_submit_result' @{generation_id=$id;response=$invalid}
    $invalid = Copy-GenerationReply $reply; $invalid.north_clockwise_degrees = 0
    Reject-Generation 'generation_submit_result' @{generation_id=$id;response=$invalid}
    $invalid = Copy-GenerationReply $reply; $invalid.canvas_width += 1
    Reject-Generation 'generation_submit_result' @{generation_id=$id;response=$invalid}
    $invalid = Copy-GenerationReply $reply; $invalid.sources = @()
    Reject-Generation 'generation_submit_result' @{generation_id=$id;response=$invalid}
    $invalid = Copy-GenerationReply $reply; $invalid.operations_json = '{"operations":[{"op":"delete","id":"other"}]}'
    Reject-Generation 'generation_submit_result' @{generation_id=$id;response=$invalid}
    $invalid = Copy-GenerationReply $reply; $invalid.operations_json = '{bad json'
    Reject-Generation 'generation_submit_result' @{generation_id=$id;response=$invalid}
    $null = Send-Generation 'generation_submit_result' @{generation_id=$id;response=$reply}
    $result = (Invoke-MapRakuPipe @{command='generation_get_result'}).generation
    Assert-Generation ($result.state -eq 'ready' -and $result.can_apply) 'Valid generation not ready'
    Assert-Generation ($result.document.layers.Count -eq 3) 'Candidate layer count mismatch'
    Assert-Generation ($result.document.crossingRelations.Count -eq 1) 'Crossing relation missing'
    Assert-Generation ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $before.state_token) 'Preview changed document'
    $previewRequest = Get-MapRakuTokens
    $previewRequest.command = 'render_preview'; $previewRequest.document = $result.document; $previewRequest.include_reference = $false
    $preview = (Invoke-MapRakuPipe $previewRequest).snapshot.images
    foreach ($imageName in @('base_image','overlay_image','composite_image')) {
        $bytes = Receive-MapRakuBlob $preview.$imageName
        if ($imageName -eq 'composite_image') { [IO.File]::WriteAllBytes((Join-Path $output 'fixture.png'),$bytes) }
    }
    $applyRequest = New-MapRakuMutation 'generation_apply'; $applyRequest.generation_id = $id
    $null = Invoke-MapRakuPipe $applyRequest; $null = Invoke-MapRakuPipe $applyRequest
    $applied = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    Assert-Generation ($applied.document.layers.Count -eq 3) 'Apply failed'
    $null = Send-Generation 'undo'
    Assert-Generation ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $before.state_token) 'Generation undo failed'
    $null = Send-Generation 'redo'
    Assert-Generation ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -ceq $applied.state_token) 'Generation redo failed'
    # 生成中の編集による上書き拒否。
    $null = Send-Generation 'generation_prepare' @{request=$input}
    $next = (Invoke-MapRakuPipe @{command='generation_get_request'}).generation
    $reply.generation_id = $next.request.generation_id
    $null = Send-Generation 'generation_submit_result' @{generation_id=$reply.generation_id;response=$reply}
    $null = Send-Generation 'apply_batch' @{operations=@(@{op='add';spec=@{kind='text';id='user-change';text='利用者の追記';x=-100;y=100}})}
    Reject-Generation 'generation_apply' @{generation_id=$reply.generation_id}
    # 曖昧な地名を追加確認へ戻し、地図を反映できないことを検証する。
    $null = Send-Generation 'generation_prepare' @{request=$input}
    $next = (Invoke-MapRakuPipe @{command='generation_get_request'}).generation
    $reply.generation_id = $next.request.generation_id; $reply.outcome = 'needs_clarification'
    $reply.operations_json = ''; $reply.sources = @(); $reply.message = '市区町村を指定してください。'
    $null = Send-Generation 'generation_submit_result' @{generation_id=$reply.generation_id;response=$reply}
    Assert-Generation ((Invoke-MapRakuPipe @{command='generation_status'}).generation.state -eq 'needs_clarification') 'Clarification lost'
    Reject-Generation 'generation_apply' @{generation_id=$reply.generation_id}
    if ($Live) {
        $liveInput = @{place_query='東京都千代田区 東京駅 丸の内中央口';span_m=1000;north_clockwise_degrees=0;instructions='主要な道路・鉄道・施設を10～20個程度に絞り、出典を確認してください。'}
        $started = (Send-Generation 'generation_start' @{request=$liveInput}).generation
        $deadline = [DateTime]::UtcNow.AddMinutes(17)
        do {
            Start-Sleep -Seconds 2
            $status = (Invoke-MapRakuPipe @{command='generation_status'}).generation
        } while ($status.busy -and [DateTime]::UtcNow -lt $deadline)
        Assert-Generation (-not $status.busy) 'Live generation still running'
        Assert-Generation ($status.state -in @('ready','needs_clarification')) "Live generation: $($status.state): $($status.message)"
        if ($RequireMap) { Assert-Generation ($status.state -eq 'ready') "Live map generation: $($status.message)" }
        $liveResult = (Invoke-MapRakuPipe @{command='generation_get_result'}).generation
        $liveResult | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $output 'live-result.json') -Encoding utf8
    }
    [pscustomobject]@{config=$Config;host_kind=$caps.host_kind;contract='passed';rejection='passed';preview='passed';undo_redo='passed';live=[bool]$Live} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output ('report-'+$caps.host_kind+'.json')) -Encoding utf8
    Write-Output "PASS generation $Config $($caps.host_kind)"
} finally {
    # 自分で起動した試験用プロセスだけを閉じる。
    if (-not $app.HasExited) { $null = $app.CloseMainWindow(); if (-not $app.WaitForExit(5000)) { Stop-Process -Id $app.Id } }
}
