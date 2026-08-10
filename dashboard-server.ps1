param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$WebRoot = Join-Path $Root 'www'
$DataFile = Join-Path $Root 'data.json'
$LogPath = Join-Path $Root 'server.log'

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::AppendAllText($LogPath, $line + "`r`n", $encoding)
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
    $listener.Start()
}
catch {
    Write-Log "启动失败: $($_.Exception.Message)"
    exit 1
}

Write-Host "B站数据看板已启动: http://localhost:$Port/"
Write-Log "B站数据看板已启动: http://localhost:$Port/"

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.txt'  = 'text/plain; charset=utf-8'
}

function Send-Response {
    param($Context, [byte[]]$Bytes, [string]$ContentType, [int]$StatusCode = 200)
    $resp = $Context.Response
    $resp.StatusCode = $StatusCode
    $resp.ContentType = $ContentType
    $resp.ContentLength64 = $Bytes.Length
    $resp.Headers.Add('Cache-Control', 'no-store')
    $resp.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $resp.Close()
}

function Send-Text {
    param($Context, [string]$Text, [string]$ContentType, [int]$StatusCode = 200)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Send-Response -Context $Context -Bytes $bytes -ContentType $ContentType -StatusCode $StatusCode
}

function Send-File {
    param($Context, [string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($contentTypes.ContainsKey($ext)) {
        $type = $contentTypes[$ext]
    }
    else {
        $type = 'application/octet-stream'
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Send-Response -Context $Context -Bytes $bytes -ContentType $type
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath

        if ($path -eq '/' -or $path -eq '/index.html') {
            $file = Join-Path $WebRoot 'index.html'
            if (Test-Path -LiteralPath $file) {
                Send-File -Context $ctx -Path $file
            }
            else {
                Send-Text -Context $ctx -Text '<h1>index.html 不存在</h1>' -ContentType 'text/html; charset=utf-8' -StatusCode 404
            }
        }
        elseif ($path -eq '/data.json') {
            if (Test-Path -LiteralPath $DataFile) {
                Send-File -Context $ctx -Path $DataFile
            }
            else {
                Send-Text -Context $ctx -Text '{"error":"数据尚未生成"}' -ContentType 'application/json; charset=utf-8'
            }
        }
        else {
            $relative = $path.TrimStart('/').Replace('/', '\')
            $file = Join-Path $WebRoot $relative
            $full = [System.IO.Path]::GetFullPath($file)
            $webFull = [System.IO.Path]::GetFullPath($WebRoot)
            if ($full.StartsWith($webFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) {
                Send-File -Context $ctx -Path $full
            }
            else {
                Send-Text -Context $ctx -Text '<h1>404 Not Found</h1>' -ContentType 'text/html; charset=utf-8' -StatusCode 404
            }
        }
    }
    catch {
        Write-Log "请求处理错误: $($_.Exception.Message)"
    }
}

$listener.Stop()
