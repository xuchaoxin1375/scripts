for ($i = 1; $i -le 150; $i++ )
{
    $completed = [math]::Round($i/150 * 100,1)
    Write-Progress -Activity 'Search in Progress' -Status "$completed% Complete:" -PercentComplete $completed
    Start-Sleep -Milliseconds 10
}