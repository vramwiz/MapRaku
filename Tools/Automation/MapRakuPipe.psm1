# アプリへの入出力をNamed Pipeに限定する。画像のローカル保存は受信後の表示用だけに使う。
Set-StrictMode -Version Latest
$script:MapRakuPipeName = 'MapRaku.v1'

function Set-MapRakuEndpoint {
    param([Parameter(Mandatory)][string]$PipeName)
    if ($PipeName -notmatch '^MapRaku\.(v1|Plugin\.[0-9]+\.\{[0-9A-Fa-f-]+\})$') {
        throw 'Invalid MapRaku endpoint name.'
    }
    # 一度選んだ編集セッションへ固定し、閉じた後に他の文書へ自動接続しない。
    $script:MapRakuPipeName = $PipeName
}

function Get-MapRakuEndpoints {
    [IO.Directory]::GetFiles('\\.\pipe\') |
        ForEach-Object { $_.Substring($_.LastIndexOf('\') + 1) } |
        Where-Object { $_ -eq 'MapRaku.v1' -or $_ -like 'MapRaku.Plugin.*' }
}

function Invoke-MapRakuPipe {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Request,
          [int]$TimeoutMs = 15000, [switch]$AllowError)
    $json = ConvertTo-Json -InputObject $Request -Depth 100 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    if ($bytes.Length -gt 4MB) { throw 'Request exceeds 4 MiB.' }
    $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $script:MapRakuPipeName,
        [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    $response = [IO.MemoryStream]::new()
    try {
        $pipe.Connect($TimeoutMs)
        $pipe.ReadMode = [IO.Pipes.PipeTransmissionMode]::Message
        $write = $pipe.WriteAsync($bytes, 0, $bytes.Length)
        if (-not $write.Wait($TimeoutMs)) { throw 'Pipe write timed out; query request_id before retrying.' }
        $buffer = [byte[]]::new(65536)
        do {
            $read = $pipe.ReadAsync($buffer, 0, $buffer.Length)
            if (-not $read.Wait($TimeoutMs)) { throw 'Pipe read timed out; query request_id before retrying.' }
            $count = $read.Result
            if ($count -eq 0) { throw 'Pipe closed before complete response.' }
            $response.Write($buffer, 0, $count)
            if ($response.Length -gt 4MB) { throw 'Response exceeds 4 MiB.' }
        } while (-not $pipe.IsMessageComplete)
        $result = [Text.Encoding]::UTF8.GetString($response.ToArray()) | ConvertFrom-Json -Depth 100
        if ($result.status -ne 'ok' -and -not $AllowError) {
            throw "$($Request.command): $($result.error.code): $($result.error.message)"
        }
        return $result
    } finally {
        # タイムアウトでも接続を閉じ、ワーカーを次の照会へ進める。
        $pipe.Dispose()
        $response.Dispose()
    }
}

function Get-MapRakuTokens {
    $document = Invoke-MapRakuPipe @{ command = 'get_document' }
    $reference = Invoke-MapRakuPipe @{ command = 'get_reference' }
    return @{
        state_token = $document.snapshot.state_token
        background_token = $reference.result.background_token
    }
}

function New-MapRakuMutation {
    param([Parameter(Mandatory)][string]$Command)
    $request = Get-MapRakuTokens
    $request.command = $Command
    $request.request_id = [guid]::NewGuid().ToString()
    $request.apply = $true
    return $request
}

function Send-MapRakuBlob {
    param([Parameter(Mandatory)][byte[]]$Bytes, [string]$Mime = 'image/png')
    $begin = Invoke-MapRakuPipe @{
        command = 'begin_blob'; request_id = [guid]::NewGuid().ToString()
        size = $Bytes.Length; mime = $Mime
    }
    $id = $begin.result.blob_id
    try {
        for ($offset = 0; $offset -lt $Bytes.Length; $offset += $count) {
            $count = [Math]::Min(192KB, $Bytes.Length - $offset)
            $null = Invoke-MapRakuPipe @{
                command = 'write_blob'; blob_id = $id; offset = $offset
                base64 = [Convert]::ToBase64String($Bytes, $offset, $count)
            }
        }
        return $id
    } catch {
        $null = Invoke-MapRakuPipe @{ command = 'release_blob'; blob_id = $id }
        throw
    }
}

function Receive-MapRakuBlob {
    param([Parameter(Mandatory)]$Descriptor, [switch]$Keep)
    $stream = [IO.MemoryStream]::new()
    try {
        while ($stream.Length -lt $Descriptor.size) {
            $response = Invoke-MapRakuPipe @{
                command = 'read_blob'; blob_id = $Descriptor.blob_id
                offset = $stream.Length; count = 192KB
            }
            $chunk = [Convert]::FromBase64String($response.result.base64)
            if ($chunk.Length -eq 0) { throw 'Unexpected empty blob chunk.' }
            $stream.Write($chunk, 0, $chunk.Length)
        }
        $bytes = $stream.ToArray()
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        if ($bytes.Length -ne $Descriptor.size -or $hash -ne $Descriptor.sha256) {
            throw 'Blob integrity check failed.'
        }
        return ,$bytes
    } finally {
        $stream.Dispose()
        if (-not $Keep) {
            $null = Invoke-MapRakuPipe @{ command = 'release_blob'; blob_id = $Descriptor.blob_id }
        }
    }
}

Export-ModuleMember -Function Set-MapRakuEndpoint, Get-MapRakuEndpoints, Invoke-MapRakuPipe, Get-MapRakuTokens, New-MapRakuMutation, Send-MapRakuBlob, Receive-MapRakuBlob
