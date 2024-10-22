# $Json=$DataJson
$Json = "$configs\wtConf.json"
$res = Get-Content $Json | ConvertFrom-Json
$Names = $res | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
# $Names = $Names | Where-Object { $_ -like "$wordToComplete*" }
foreach ($name in $Names)
{
    $value = $res | Select-Object  $name | Out-String
    if (! $value)
    {
        $value = 'Error:Nested property expand failed'
    }
    Write-Host "$name : $value"

    # [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $value.ToString())
}