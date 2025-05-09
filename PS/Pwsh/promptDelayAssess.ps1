# 测量 Prompt 函数执行多次的平均时间
$iterations = 10
$DurationArrays = (1..$iterations | ForEach-Object { Measure-Command { Prompt } })
$DurationSum = ($DurationArrays | ForEach-Object { $_.TotalSeconds }) | Measure-Object -Sum
$averageDuration = $DurationSum.Sum / ($DurationArrays.Count)
Write-Host $averageDuration