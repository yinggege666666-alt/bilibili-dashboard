param(
    [switch]$OpenBrowser,
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$ServerScript = Join-Path $Root 'dashboard-server.ps1'
$Url = "http://localhost:$Port/"

function Test-DashboardPort {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $Port)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

if (-not (Test-DashboardPort)) {
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ServerScript`" -Port $Port"
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WorkingDirectory $Root -WindowStyle Hidden | Out-Null

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-DashboardPort) { break }
    }
}

if (Test-DashboardPort) {
    if ($OpenBrowser) {
        Start-Process $Url
    }
    Write-Host "B站数据看板已启动: $Url"
    exit 0
}

Write-Host '看板启动失败，请查看 server.log'
exit 1
