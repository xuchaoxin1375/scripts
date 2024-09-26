# for ($i = 1; $i -le 150; $i++ )
# {
#     $completed = [math]::Round($i/150 * 100,1)
#     Write-Progress -Activity 'Search in Progress' -Status "$completed% Complete:" -PercentComplete $completed
#     Start-Sleep -Milliseconds 10
# }

$PSStyle.Progress.View = 'Classic'

foreach ( $i in 1..10 )
{
    Write-Progress -Id 0 "Step $i"
    foreach ( $j in 1..10 )
    {
        Write-Progress -Id 1 -ParentId 0 "Step $i - Substep $j"
        foreach ( $k in 1..10 )
        {
            Write-Progress -Id 2 -ParentId 1 "Step $i - Substep $j - iteration $k"
            Start-Sleep -Milliseconds 150
        }
    }
}