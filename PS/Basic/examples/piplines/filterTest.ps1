filter Test-PipelineInput
{
    Write-Warning "receiving $_"
    # for example, create IP addresses:
    "10.12.100.$_"
}

Write-Output 'by filter'
1..10 | Test-PipelineInput
filter Test-PipelineInput
{
    Write-Warning "receiving $_"
    # for example, create IP addresses:
    "10.12.100.$_"
}

Write-Output 'by function'
1..10 | Test-PipelineInput
