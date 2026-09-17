# 自分で起動した空のDebugアプリだけを操作し、利用者が編集中のプロセスへ接続しない。
param([ValidateSet('Debug','Release')][string]$Config='Debug')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Automation/MapRakuPipe.psm1') -Force
. (Join-Path $root 'Tests/Automation/MapRakuSample.ps1')
. (Join-Path $root 'Tests/Automation/MapRakuPipeChecks.ps1')
if (Get-Process MapRaku -ErrorAction SilentlyContinue) { throw 'Close MapRaku before running isolated pipe tests.' }
$output = Join-Path $root 'TestOutput'
$null = New-Item -ItemType Directory -Path $output -Force
$app = Start-Process -FilePath (Join-Path $root "Win64/$Config/MapRaku.exe") -WorkingDirectory $root -WindowStyle Hidden -PassThru
try {
    $caps = Invoke-MapRakuPipe @{command='get_capabilities'} -TimeoutMs 30000
    Assert-Map ($caps.protocol_version -eq 2) 'Protocol version mismatch'
    Assert-Map ($caps.capabilities.image_transport -eq 'pipe_blob_base64') 'Images must use pipe'
    $schema = Invoke-MapRakuPipe @{command='get_map_schema'}
    Assert-Map ($schema.result.symbols.Count -eq 10) 'Missing symbol schema'
    Check-BlobTransport
    $null = Send-Batch @(@{op='canvas';spec=@{width=1000;height=720;background=16777215}})
    $source = New-MapRakuSampleReference
    [IO.File]::WriteAllBytes((Join-Path $output 'pipe-source.png'),$source)
    $sourceId = Send-MapRakuBlob $source
    $reference = New-MapRakuMutation 'set_reference'
    $reference.blob_id = $sourceId
    $reference.conditions = @{north_clockwise_degrees=0;image_already_oriented=$true;area='架空の中央駅周辺'}
    $null = Invoke-MapRakuPipe $reference
    $null = Invoke-MapRakuPipe @{command='release_blob';blob_id=$sourceId}
    $initial = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    Assert-Map ($initial.document.layers.Count -eq 0) 'Expected empty test document'

    $ops = Get-MapRakuSampleOperations
    $preview = Get-MapRakuTokens
    $preview.command = 'preview_batch'; $preview.operations = @($ops)
    $candidate = (Invoke-MapRakuPipe $preview).candidate.document
    $null = Invoke-MapRakuPipe @{command='validate_document';document=$candidate}
    Assert-Map ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -eq $initial.state_token) 'Preview modified document'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @($ops)
    $first = Invoke-MapRakuPipe $request
    $retry = Invoke-MapRakuPipe $request
    Assert-Map ($first.change.state_token -eq $retry.change.state_token) 'Retry was not idempotent'
    $receipt = Invoke-MapRakuPipe @{command='get_request_result';lookup_id=$request.request_id}
    Assert-Map ($receipt.result.known -and $receipt.result.response.change.applied) 'Missing receipt'
    $request.operations = @(@{op='delete';id='main-road'})
    Assert-Rejected $request 'Request ID collision'
    $baseline = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    $null = Invoke-MapRakuPipe (New-MapRakuMutation 'undo')
    Assert-Map ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -eq $initial.state_token) 'Batch was not one undo'
    $null = Invoke-MapRakuPipe (New-MapRakuMutation 'redo')
    Assert-Map ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -eq $baseline.state_token) 'Redo mismatch'

    Check-BatchFailures
    Check-LockedGroup
    Check-ReferenceFailures
    $null = Send-Batch @(
        @{op='add';spec=@{kind='road';id='connector';vertices=@(@{x=435;y=46},@{x=460;y=160})}},
        @{op='connect';id='connector';endpoint=0;target='main-road';target_endpoint=1}
    )
    $connected = ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.document.layers | Where-Object id -eq 'connector')
    Assert-Map ($connected.vertices[0].x -eq 440 -and $connected.vertices[0].y -eq 50) 'Shared endpoint connection failed'
    $null = Send-Batch @(@{op='delete';id='connector'})
    $null = Send-Batch @(
        @{op='add';spec=@{kind='rectangle';id='temporary';x=0;y=0;width=10;height=10}},
        @{op='add';spec=@{kind='level_boundary';id='temporary-level'}},
        @{op='update';id='main-road';changes=@{width=32}},
        @{op='update';id='hall';changes=@{dx=10;dy=5}},
        @{op='update';id='title';changes=@{text='中央駅周辺 配置例'}}
    )
    $null = Send-Batch @(@{op='delete';id='temporary'},@{op='delete';id='temporary-level'})
    # 経路削除時に参照関係を掃除し、Undoでは関係も復元されることを確認する。
    $beforeDelete = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    $null = Send-Batch @(@{op='delete';id='jr'})
    $deleted = (Invoke-MapRakuPipe @{command='get_document'}).snapshot.document
    Assert-Map (@($deleted.crossingRelations | Where-Object { $_.objectAId -eq 'jr' -or $_.objectBId -eq 'jr' }).Count -eq 0) 'Dangling crossing'
    $null = Invoke-MapRakuPipe (New-MapRakuMutation 'undo')
    Assert-Map ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -eq $beforeDelete.state_token) 'Delete undo mismatch'

    $snap = (Invoke-MapRakuPipe @{command='get_canvas_snapshot';max_edge=1000;include_reference=$false}).snapshot
    $null = Receive-MapRakuBlob $snap.images.overlay_image
    $null = Receive-MapRakuBlob $snap.images.base_image
    $png = Receive-MapRakuBlob $snap.images.composite_image
    [IO.File]::WriteAllBytes((Join-Path $output 'pipe-map-sample.png'),$png)
    # ここでは既知の描画画像を参照入力に往復させ、認識精度とは独立して転送・座標を確認する。
    $blob = Send-MapRakuBlob $png
    $reference = New-MapRakuMutation 'set_reference'
    $reference.blob_id = $blob
    $reference.conditions = @{north_clockwise_degrees=0;image_already_oriented=$true;area='架空の中央駅周辺'}
    $null = Invoke-MapRakuPipe $reference
    $null = Invoke-MapRakuPipe @{command='release_blob';blob_id=$blob}
    $ref = (Invoke-MapRakuPipe @{command='get_reference'}).result
    Assert-Map ($ref.conditions_current -and $ref.conditions.north_clockwise_degrees -eq 0) 'Reference conditions lost'
    $original = Receive-MapRakuBlob (Invoke-MapRakuPipe @{command='get_reference_image'}).result
    Assert-Map ([Convert]::ToBase64String($original) -eq [Convert]::ToBase64String($png)) 'Original reference changed'
    $preview = Get-MapRakuTokens
    $preview.command = 'render_preview'
    $preview.document = (Invoke-MapRakuPipe @{command='get_document'}).snapshot.document
    $preview.max_edge = 1000
    $render = (Invoke-MapRakuPipe $preview).snapshot
    $basePng = Receive-MapRakuBlob $render.images.base_image
    Check-ImagePixels $png $basePng
    [IO.File]::WriteAllBytes((Join-Path $output 'pipe-reference-roundtrip.png'),$basePng)
    $null = Receive-MapRakuBlob $render.images.overlay_image
    $null = Receive-MapRakuBlob $render.images.composite_image
    Assert-Map ($render.images.mapping.document_x_offset -eq -500) 'Coordinate mapping mismatch'

    $save = New-MapRakuMutation 'save_copy'
    $save.path = Join-Path $output 'pipe-map-sample.mapraku'; $save.overwrite = $true
    $null = Invoke-MapRakuPipe $save
    $saved = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    $null = Send-Batch @(@{op='update';id='hall';changes=@{dx=100}})
    $load = New-MapRakuMutation 'load_file'; $load.path = $save.path
    $null = Invoke-MapRakuPipe $load
    Assert-Map ((Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token -eq $saved.state_token) 'Save/load mismatch'
    $null = Invoke-MapRakuPipe (New-MapRakuMutation 'clear_reference')
    Assert-Map (-not (Invoke-MapRakuPipe @{command='get_reference'}).result.conditions_current) 'Reference clear failed'
    $summary = @{status='passed';protocol=2;layers=$saved.document.layers.Count;crossings=$saved.document.crossingRelations.Count;
        checks=@('schema','chunk roundtrip','chunk retries','preview isolation','atomic rollback','request replay','receipt lookup',
            'stale tokens','locked ancestor','all placement kinds','shared endpoint connection','update/delete','undo/redo','reference upload',
            'reference pixels','reference failures','fixed orientation/dimensions','render preview','save/load')}
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $output 'pipe-test-report.json') -Encoding utf8
    Write-Output ($summary | ConvertTo-Json -Depth 10 -Compress)
} finally {
    # テストが起動したPIDだけを終了する。Releaseの保存確認で自動検証を止めない。
    if (-not $app.HasExited) { Stop-Process -Id $app.Id }
}
