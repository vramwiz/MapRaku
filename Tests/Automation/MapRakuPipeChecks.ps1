# 異常系で文書が変わらないことを確認し、応答成功だけで安全性を判断しない。
function Assert-Map([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Send-Batch($Operations) {
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @($Operations)
    return Invoke-MapRakuPipe $request
}
function Assert-Rejected($Request, [string]$Label) {
    $before = (Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token
    $result = Invoke-MapRakuPipe $Request -AllowError
    Assert-Map ($result.status -eq 'error') "$Label should fail"
    $after = (Invoke-MapRakuPipe @{command='get_document'}).snapshot.state_token
    Assert-Map ($before -eq $after) "$Label changed the document"
}
function Check-BlobTransport {
    $bytes = [byte[]]::new(500123)
    [Random]::new(42).NextBytes($bytes)
    $id = Send-MapRakuBlob $bytes 'application/octet-stream'
    $descriptor = (Invoke-MapRakuPipe @{command='read_blob';blob_id=$id;count=1}).result
    $received = Receive-MapRakuBlob $descriptor
    Assert-Map ([Convert]::ToBase64String($received) -eq [Convert]::ToBase64String($bytes)) 'Chunk roundtrip mismatch'
    $begin = Invoke-MapRakuPipe @{command='begin_blob';request_id=[guid]::NewGuid().ToString();size=10;mime='image/png'}
    $id = $begin.result.blob_id
    try {
        Assert-Rejected @{command='read_blob';blob_id=$id} 'Incomplete blob read'
        Assert-Rejected @{command='write_blob';blob_id=$id;offset=2;base64='AQID'} 'Out-of-order chunk'
        $chunk = @{command='write_blob';blob_id=$id;offset=0;base64='AQID'}
        $null = Invoke-MapRakuPipe $chunk
        $null = Invoke-MapRakuPipe $chunk
        Assert-Rejected @{command='write_blob';blob_id=$id;offset=0;base64='BAUG'} 'Conflicting chunk retry'
    } finally { $null = Invoke-MapRakuPipe @{command='release_blob';blob_id=$id} }
}
function Check-BatchFailures {
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(
        @{op='update';id='main-road';changes=@{width=90}},
        @{op='delete';id='does-not-exist'}
    )
    Assert-Rejected $request 'Atomic rollback'
    foreach ($spec in @(
        @{kind='road';vertices=@(@{x=1;y=2})},
        @{kind='road';vertices=@(@{x=0;y=0},@{x=100;y=100});width=-1},
        @{kind='building';id='hall'},
        @{kind='building';rotation=12},
        @{kind='jr';color=0;vertices=@(@{x=0;y=0},@{x=20;y=20})},
        @{kind='unknown'}
    )) {
        $request = New-MapRakuMutation 'apply_batch'
        $request.operations = @(@{op='add';spec=$spec})
        Assert-Rejected $request 'Invalid placement'
    }
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='crossing';a='main-road';b='jr';kind=3;upper='missing'})
    Assert-Rejected $request 'Invalid crossing reference'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='update';id='main-road';changes=@{unknown=10}})
    Assert-Rejected $request 'Unknown update attribute'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='update';id='main-road';changes=@{width=31}})
    $request.state_token = 'sha256:stale'
    Assert-Rejected $request 'Concurrent document edit'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='update';id='main-road';changes=@{width=31}})
    $request.background_token = 'stale'
    Assert-Rejected $request 'Concurrent reference edit'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='update';id='main-road';changes=@{width=31}})
    $request.Remove('request_id')
    Assert-Rejected $request 'Missing request ID'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='connect';id='main-road';target='jr';endpoint=1;target_endpoint=0})
    Assert-Rejected $request 'Incompatible endpoint family'
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='canvas';spec=@{width=500;height=500}})
    Assert-Rejected $request 'Fixed reference dimensions'
}
function Check-LockedGroup {
    $snapshot = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    $doc = $snapshot.document
    $hall = $doc.layers | Where-Object id -eq 'hall'
    $hall.locked = $true
    $request = New-MapRakuMutation 'replace_document'
    $request.document = $doc
    $null = Invoke-MapRakuPipe $request
    $request = New-MapRakuMutation 'apply_batch'
    $request.operations = @(@{op='update';id=$hall.layers[1].id;changes=@{text='変更禁止'}})
    Assert-Rejected $request 'Locked ancestor'
    $null = Invoke-MapRakuPipe (New-MapRakuMutation 'undo')
    $after = (Invoke-MapRakuPipe @{command='get_document'}).snapshot
    Assert-Map ($after.state_token -eq $snapshot.state_token) 'Locked-group undo mismatch'
}

function Check-ReferenceFailures {
    $before = (Invoke-MapRakuPipe @{command='get_reference'}).result.background_token
    $bad = Send-MapRakuBlob ([byte[]]@(1,2,3,4))
    try {
        $request = New-MapRakuMutation 'set_reference'
        $request.blob_id = $bad
        $request.conditions = @{north_clockwise_degrees=0;image_already_oriented=$true}
        Assert-Rejected $request 'Invalid PNG'
        $request.request_id = [guid]::NewGuid().ToString()
        $request.conditions = @{north_clockwise_degrees=0;image_already_oriented=$false}
        Assert-Rejected $request 'Unfixed orientation'
    } finally { $null = Invoke-MapRakuPipe @{command='release_blob';blob_id=$bad} }
    Assert-Map ((Invoke-MapRakuPipe @{command='get_reference'}).result.background_token -eq $before) 'Failed reference changed canvas'
    Assert-Rejected @{command='begin_blob';request_id=[guid]::NewGuid().ToString();size=16777217;mime='image/png'} 'Blob size limit'
}

function Check-ImagePixels([byte[]]$Expected, [byte[]]$Actual) {
    $aStream = [IO.MemoryStream]::new($Expected)
    $bStream = [IO.MemoryStream]::new($Actual)
    $a = [Drawing.Bitmap]::new($aStream)
    $b = [Drawing.Bitmap]::new($bStream)
    try {
        Assert-Map ($a.Width -eq $b.Width -and $a.Height -eq $b.Height) 'Reference dimensions changed'
        # 左上・鉄道・川・施設・下端の非対称な位置で上下反転や色変換の誤りを検出する。
        foreach ($point in @(@(10,10),@(80,210),@(785,70),@(560,340),@(340,410),@(820,600),@(550,650))) {
            Assert-Map ($a.GetPixel($point[0],$point[1]).ToArgb() -eq $b.GetPixel($point[0],$point[1]).ToArgb()) 'Reference pixel mismatch'
        }
    } finally { $a.Dispose(); $b.Dispose(); $aStream.Dispose(); $bStream.Dispose() }
}
