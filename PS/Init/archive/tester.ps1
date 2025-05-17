$start = Get-Date
$start | pwsh -c {
    # $input[0].GetType()
    $start = $input | Select-Object -ExpandProperty datetime
    # Write-Host $start
    $end = Get-Date
    $duration = $end - [datetime]$start
    $duration.TotalSeconds
    
}