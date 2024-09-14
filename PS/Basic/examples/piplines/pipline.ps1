function Test-PipelineInput
{
 
    param
    (
 
        [Parameter(ValueFromPipeline = $true)]
        $Text
    )
 
    Write-Host "$Text"
}
# "demo of pipline"|Test-PipelineInput
1..5|Test-PipelineInput

function Test-PipelineInput
{
 
    param
    (
 
        [Parameter(ValueFromPipeline = $true)]
        $Text
    )
 
    Begin {}
 
    Process
    {
 
        Write-Host "$Text"
 
    }
 
    End {}
 
}
1..5|Test-PipelineInput