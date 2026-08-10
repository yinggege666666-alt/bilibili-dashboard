param(
    [switch]$SkipFetch,
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ApiBase = 'https://api.bilibili.com/x/web-interface/view'
$Bvids = @(
    'BV1o9uy6jEyM',
    'BV1eSMC6TENM',
    'BV1QZM16zEMK',
    'BV1GFVf6sECB',
    'BV1NfKw6AEeo',
    'BV1Tjgk6fEQw',
    'BV1wfT76GEME',
    'BV18egC6NEPm',
    'BV1sh3C6cEXN',
    'BV19wLX61EpR',
    'BV1cbuw6eE16',
    'BV15AdgB4En4',
    'BV1g4Ei6KEWJ',
    'BV15c7h6REzw'
)

$CsvPath = Join-Path $Root 'snapshots.csv'
$JsonPath = Join-Path $Root 'data.json'
$LogPath = Join-Path $Root 'fetch.log'

$ChinaTimeZone = if ($env:OS -eq 'Windows_NT') {
    [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
}
else {
    [TimeZoneInfo]::FindSystemTimeZoneById('Asia/Shanghai')
}

function Get-ChinaNow {
    $utc = [DateTime]::UtcNow
    return [TimeZoneInfo]::ConvertTimeFromUtc($utc, $ChinaTimeZone)
}

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-ChinaNow).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::AppendAllText($LogPath, $line + "`r`n", $encoding)
    Write-Host $line
}

function Get-BiliVideo {
    param([string]$Bvid)
    $uri = "$ApiBase`?bvid=$Bvid"
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
        'Referer'    = 'https://www.bilibili.com/'
        'Accept'     = 'application/json, text/plain, */*'
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
            if ($resp.code -eq 0 -and $null -ne $resp.data) {
                return $resp.data
            }
            throw "API code=$($resp.code) message=$($resp.message)"
        }
        catch {
            $msg = $_.Exception.Message
            if ($attempt -lt 3) {
                Start-Sleep -Seconds 2
            }
            else {
                throw "BVID $Bvid 请求失败: $msg"
            }
        }
    }
}

function Write-CsvAtomically {
    param($Rows)
    $tmp = "$CsvPath.tmp"
    $Rows | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $CsvPath -Force
}

function ConvertTo-EpochDateTime {
    param([long]$EpochSeconds)
    $offset = [DateTimeOffset]::FromUnixTimeSeconds($EpochSeconds)
    $utc = $offset.UtcDateTime
    return [TimeZoneInfo]::ConvertTimeFromUtc($utc, $ChinaTimeZone)
}

function New-EmptyVideo {
    param([string]$Bvid)
    return [ordered]@{
        bvid         = $Bvid
        title        = '（暂无数据）'
        hasData      = $false
        pubdate      = 0
        publishedAt  = ''
        latestTime   = ''
        view         = 0
        reply        = 0
        like         = 0
        coin         = 0
        favorite     = 0
        share        = 0
        hourlyView   = 0
        todayView    = 0
        days         = 0
        dailyAvgView = 0
        rates        = [ordered]@{ reply = 0; like = 0; coin = 0; favorite = 0; share = 0 }
        history      = @()
        hourlyDeltas = @()
        rateTrend    = @()
        dailyAvgTrend = @()
    }
}

function Build-DashboardData {
    $rows = @()
    if (Test-Path -LiteralPath $CsvPath) {
        $rows = @(Import-Csv -LiteralPath $CsvPath)
    }

    $videos = @()
    foreach ($bvid in $Bvids) {
        $videoRows = @($rows | Where-Object { $_.Bvid -eq $bvid } | Sort-Object SnapshotTime)
        if ($videoRows.Count -eq 0) {
            $videos += [pscustomobject](New-EmptyVideo -Bvid $bvid)
            continue
        }

        $latest = $videoRows[-1]
        $pubLocal = ConvertTo-EpochDateTime -EpochSeconds ([long]$latest.Pubdate)
        $latestDate = [DateTime]::ParseExact($latest.SnapshotTime.Substring(0, 10), 'yyyy-MM-dd', $null)
        $days = ($latestDate - $pubLocal.Date).Days + 1
        if ($days -lt 1) { $days = 1 }

        $view = [double][long]$latest.View
        $reply = [double][long]$latest.Reply
        $like = [double][long]$latest.Like
        $coin = [double][long]$latest.Coin
        $favorite = [double][long]$latest.Favorite
        $share = [double][long]$latest.Share

        $prev = @($videoRows | Where-Object { $_.SnapshotTime -lt $latest.SnapshotTime } | Select-Object -Last 1)
        $hourlyView = 0
        if ($prev.Count -gt 0) {
            $delta = [long]$latest.View - [long]$prev[0].View
            if ($delta -gt 0) { $hourlyView = $delta }
        }

        $todayPrefix = $latestDate.ToString('yyyy-MM-dd')
        $firstToday = @($videoRows | Where-Object { $_.SnapshotTime -like "$todayPrefix*" } | Select-Object -First 1)
        $todayView = 0
        if ($firstToday.Count -gt 0) {
            $delta = [long]$latest.View - [long]$firstToday[0].View
            if ($delta -gt 0) { $todayView = $delta }
        }

        $rate = [ordered]@{
            reply    = 0
            like     = 0
            coin     = 0
            favorite = 0
            share    = 0
        }
        if ($view -gt 0) {
            $rate.reply = [Math]::Round(100.0 * $reply / $view, 4)
            $rate.like = [Math]::Round(100.0 * $like / $view, 4)
            $rate.coin = [Math]::Round(100.0 * $coin / $view, 4)
            $rate.favorite = [Math]::Round(100.0 * $favorite / $view, 4)
            $rate.share = [Math]::Round(100.0 * $share / $view, 4)
        }

        $history = @()
        foreach ($r in $videoRows) {
            $history += [ordered]@{
                time     = $r.SnapshotTime
                view     = [long]$r.View
                reply    = [long]$r.Reply
                like     = [long]$r.Like
                coin     = [long]$r.Coin
                favorite = [long]$r.Favorite
                share    = [long]$r.Share
                danmaku  = [long]$r.Danmaku
            }
        }

        $hourlyDeltas = @()
        for ($i = 1; $i -lt $history.Count; $i++) {
            $prev = $history[$i - 1]
            $curr = $history[$i]
            $hourlyDeltas += [ordered]@{
                time     = $curr.time
                view     = [long][Math]::Max(0, [long]$curr.view - [long]$prev.view)
                reply    = [long][Math]::Max(0, [long]$curr.reply - [long]$prev.reply)
                like     = [long][Math]::Max(0, [long]$curr.like - [long]$prev.like)
                coin     = [long][Math]::Max(0, [long]$curr.coin - [long]$prev.coin)
                favorite = [long][Math]::Max(0, [long]$curr.favorite - [long]$prev.favorite)
                share    = [long][Math]::Max(0, [long]$curr.share - [long]$prev.share)
            }
        }

        $rateTrend = @()
        foreach ($h in $history) {
            $hv = [double][long]$h.view
            $hr = 0.0
            $hl = 0.0
            $hc = 0.0
            $hf = 0.0
            $hs = 0.0
            if ($hv -gt 0) {
                $hr = [Math]::Round(100.0 * [double][long]$h.reply / $hv, 4)
                $hl = [Math]::Round(100.0 * [double][long]$h.like / $hv, 4)
                $hc = [Math]::Round(100.0 * [double][long]$h.coin / $hv, 4)
                $hf = [Math]::Round(100.0 * [double][long]$h.favorite / $hv, 4)
                $hs = [Math]::Round(100.0 * [double][long]$h.share / $hv, 4)
            }
            $rateTrend += [ordered]@{
                time     = $h.time
                reply    = $hr
                like     = $hl
                coin     = $hc
                favorite = $hf
                share    = $hs
            }
        }

        $dailyAvgTrend = @()
        $dayIndex = @{}
        foreach ($h in $history) {
            $date = $h.time.Substring(0, 10)
            $day = [DateTime]::ParseExact($date, 'yyyy-MM-dd', $null)
            $dayNum = ($day - $pubLocal.Date).Days + 1
            if ($dayNum -lt 1) { $dayNum = 1 }
            $item = [ordered]@{
                date         = $date
                view         = [long]$h.view
                days         = $dayNum
                dailyAvgView = [Math]::Round([double][long]$h.view / $dayNum, 2)
            }
            if ($dayIndex.ContainsKey($date)) {
                $dailyAvgTrend[$dayIndex[$date]] = $item
            }
            else {
                $dayIndex[$date] = $dailyAvgTrend.Count
                $dailyAvgTrend += $item
            }
        }

        $videos += [pscustomobject][ordered]@{
            bvid         = $bvid
            title        = $latest.Title
            hasData      = $true
            pubdate      = [long]$latest.Pubdate
            publishedAt  = $pubLocal.ToString('yyyy-MM-dd HH:mm:ss')
            latestTime   = $latest.SnapshotTime
            view         = [long]$view
            reply        = [long]$reply
            like         = [long]$like
            coin         = [long]$coin
            favorite     = [long]$favorite
            share        = [long]$share
            hourlyView   = [long]$hourlyView
            todayView    = [long]$todayView
            days         = $days
            dailyAvgView = [Math]::Round($view / $days, 2)
            rates        = $rate
            history      = $history
            hourlyDeltas = $hourlyDeltas
            rateTrend    = $rateTrend
            dailyAvgTrend = $dailyAvgTrend
        }
    }

    $hasDataVideos = @($videos | Where-Object { $_.hasData })
    $rateVideos = @($videos | Where-Object { $_.hasData -and $_.view -gt 0 })

    $summary = [ordered]@{
        videoCount      = $Bvids.Count
        totalView       = 0
        totalReply      = 0
        avgReplyRate    = 0
        avgLikeRate     = 0
        avgCoinRate     = 0
        avgFavoriteRate = 0
        avgShareRate    = 0
    }
    foreach ($v in $hasDataVideos) {
        $summary.totalView += $v.view
        $summary.totalReply += $v.reply
    }
    foreach ($v in $rateVideos) {
        $summary.avgReplyRate += $v.rates.reply
        $summary.avgLikeRate += $v.rates.like
        $summary.avgCoinRate += $v.rates.coin
        $summary.avgFavoriteRate += $v.rates.favorite
        $summary.avgShareRate += $v.rates.share
    }
    if ($rateVideos.Count -gt 0) {
        $summary.avgReplyRate = [Math]::Round($summary.avgReplyRate / $rateVideos.Count, 4)
        $summary.avgLikeRate = [Math]::Round($summary.avgLikeRate / $rateVideos.Count, 4)
        $summary.avgCoinRate = [Math]::Round($summary.avgCoinRate / $rateVideos.Count, 4)
        $summary.avgFavoriteRate = [Math]::Round($summary.avgFavoriteRate / $rateVideos.Count, 4)
        $summary.avgShareRate = [Math]::Round($summary.avgShareRate / $rateVideos.Count, 4)
    }

    $payload = [ordered]@{
        updatedAt = (Get-ChinaNow).ToString('yyyy-MM-dd HH:mm:ss')
        source    = $ApiBase
        order     = $Bvids
        summary   = $summary
        videos    = $videos
    }

    $json = $payload | ConvertTo-Json -Depth 12
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($JsonPath, $json, $utf8NoBom)
}

if (-not $SkipFetch) {
    $now = Get-ChinaNow
    $hour = $now.ToString('yyyy-MM-dd HH:00:00')
    $existingRows = @()
    if (Test-Path -LiteralPath $CsvPath) {
        $existingRows = @(Import-Csv -LiteralPath $CsvPath)
    }

    $newRows = @()
    $fetchedCount = 0
    foreach ($bvid in $Bvids) {
        try {
            $data = Get-BiliVideo -Bvid $bvid
            $stat = $data.stat
            $newRows += [pscustomobject][ordered]@{
                SnapshotTime = $now.ToString('yyyy-MM-dd HH:mm:ss')
                SnapshotHour = $hour
                Bvid         = $bvid
                Title        = $data.title
                View         = [long]$stat.view
                Reply        = [long]$stat.reply
                Like         = [long]$stat.like
                Coin         = [long]$stat.coin
                Favorite     = [long]$stat.favorite
                Share        = [long]$stat.share
                Danmaku      = [long]$stat.danmaku
                Pubdate      = [long]$data.pubdate
            }
            $fetchedCount++
            Write-Log "成功: $bvid 播放=$($stat.view) 评论=$($stat.reply)"
        }
        catch {
            Write-Log "失败: $($_.Exception.Message)"
        }
        Start-Sleep -Milliseconds 500
    }

    if ($fetchedCount -gt 0) {
        $newKeys = @{}
        foreach ($row in $newRows) {
            $newKeys["$($row.Bvid)|$($row.SnapshotHour)"] = $true
        }
        $existingRows = @($existingRows | Where-Object { -not $newKeys.ContainsKey("$($_.Bvid)|$($_.SnapshotHour)") })
        $allRows = @($existingRows) + @($newRows)
        $allRows = @($allRows | Sort-Object SnapshotTime, @{ Expression = { $Bvids.IndexOf($_.Bvid) } })
        Write-CsvAtomically -Rows $allRows
        Write-Log "已写入 $($allRows.Count) 行到 snapshots.csv"
    }
    else {
        Write-Log '本次抓取全部失败，未修改 snapshots.csv'
    }
}

Build-DashboardData
Write-Log "data.json 已更新"
