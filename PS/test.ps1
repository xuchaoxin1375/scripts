$Scheme='auto'
$ReverseMode='base'
Write-Verbose "Scheme initial value: [$Scheme]." -Verbose
if ($Scheme -ne 'auto')
{
    if($Scheme )
    {
        $Scheme += "://"
    }
}
else
{
    if ($ReverseMode -eq 'base')
    {
        $Scheme = "http://"
    }
    else
    {
        $Scheme = ""
    }
}
Write-Verbose "Scheme prefix for proxy_pass: [$Scheme]" -Verbose