function Read-ProfileMemoryInfo([string]$Serial, [int]$ProcessId) {
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Command adb -CommandType Application).Source)
    foreach ($argument in @('-s', $Serial, 'shell', 'dumpsys', '-t', '5', 'meminfo', "$ProcessId")) {
        $start.ArgumentList.Add($argument)
    }
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(8000)) {
            $process.Kill()
            throw 'ADB meminfo timed out.'
        }
        if ($process.ExitCode -ne 0) { throw "ADB meminfo failed. $($stderr.GetAwaiter().GetResult())" }
        return $stdout.GetAwaiter().GetResult()
    } finally { $process.Dispose() }
}

function ConvertFrom-ProfileMemoryInfo([string]$Raw, [int]$ProcessId, [string]$Package) {
    $identity = [regex]::Escape("** MEMINFO in pid $ProcessId [$Package] **")
    if ($Raw -notmatch "(?m)^$identity[ \t\r]*$") { throw 'Unexpected meminfo PID or package.' }
    $heap = [regex]::Match($Raw, '(?m)^[ \t]*Native Heap[ \t]+(\d+(?:[ \t]+\d+){6,7})[ \t\r]*$')
    $total = [regex]::Match($Raw, '(?m)^[ \t]*TOTAL PSS:[ \t]+(\d+)')
    $graphics = [regex]::Match($Raw, '(?m)^[ \t]*Graphics:[ \t]+(\d+)')
    if (-not $heap.Success -or -not $total.Success) { throw 'Required meminfo fields are missing.' }
    $heapColumns = $heap.Groups[1].Value -split '\s+'
    return [ordered]@{
        nativeHeapPssKiB = [long]$heapColumns[0]
        nativeHeapAllocatedKiB = [long]$heapColumns[-2]
        totalPssKiB = [long]$total.Groups[1].Value
        graphicsKiB = if ($graphics.Success) { [long]$graphics.Groups[1].Value } else { $null }
    }
}

function Get-ProfileMemoryServiceUri([uri]$WebSocketUri) {
    if (-not $WebSocketUri.IsLoopback -or $WebSocketUri.Scheme -ne 'ws' -or
        -not $WebSocketUri.AbsolutePath.EndsWith('/ws')) {
        throw 'Expected a local Flutter VM service WebSocket.'
    }
    $uri = [UriBuilder]::new($WebSocketUri)
    $uri.Scheme = 'http'
    $uri.Path = $uri.Path.Substring(0, $uri.Path.Length - 2)
    return $uri.Uri
}

function Send-ProfileMemoryAck([uri]$ServiceUri, $Checkpoint, [bool]$Sampled) {
    $query = 'isolateId=' + [uri]::EscapeDataString($Checkpoint.isolateId) +
        '&sequence=' + [int]$Checkpoint.sequence + '&sampled=' + $Sampled.ToString().ToLowerInvariant()
    $uri = [uri]::new($ServiceUri, "ext.y300.profileMemoryAck?$query")
    try {
        $response = Invoke-RestMethod -Uri $uri -TimeoutSec 5
    } catch {
        throw 'Flutter VM service acknowledgement request failed.'
    }
    if ($response.acknowledged -ne $true -and $response.result.acknowledged -ne $true) {
        throw 'VM service did not acknowledge the memory sample.'
    }
}
