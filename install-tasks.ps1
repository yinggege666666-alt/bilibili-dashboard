$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$FetchScript = Join-Path $Root 'fetch-bilibili.ps1'
$StartScript = Join-Path $Root 'start-dashboard.ps1'

$FetchTaskName = 'B站数据看板-每小时抓取'
$ServerTaskName = 'B站数据看板-登录启动'

$fetchAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$FetchScript`"" -WorkingDirectory $Root
$fetchTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$fetchSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName $FetchTaskName -Action $fetchAction -Trigger $fetchTrigger -Settings $fetchSettings -Description '每小时抓取B站视频数据并生成看板数据文件' -Force

$serverAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StartScript`"" -WorkingDirectory $Root
$serverTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$serverSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName $ServerTaskName -Action $serverAction -Trigger $serverTrigger -Settings $serverSettings -Description '登录Windows时自动启动B站数据看板网页服务' -Force

Write-Host "已注册计划任务: $FetchTaskName"
Write-Host "已注册计划任务: $ServerTaskName"
