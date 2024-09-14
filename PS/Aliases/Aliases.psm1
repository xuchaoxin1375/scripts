$scripts = 'C:\repos\scripts'
$alias_dir = "$scripts\PS\aliases"
function Update-PwshAliases
{
    [CmdletBinding()]param()
    Write-Verbose 'updating aliases!'
    # 这里是载入pwsh环境变量的最初阶段,需要用绝对路径!
    $alias_file_array = @(
        'functions', 
        'shortcuts'
    )
 
    $alias_file_array | ForEach-Object {
        Set-PwshAliasFile $_
    }

}

function Set-PwshAliasFile
{
    [CmdletBinding()]
    param (
        $alias_file
    )
    # if ($line.Length -gt 0 -and !$line.startswith('#') )
    if ($VerbosePreference)
    {

        Write-Host "`t$alias_file" -ForegroundColor Magenta
    }
    $alias_file = "$alias_dir\$alias_file"

    Get-Content $alias_file | ForEach-Object {
        $line = $_.ToString()
         
        Write-Debug $line -ErrorAction Ignore
        if ($line -match '^[\^a-zA-Z]')
        {
            $line = "set-alias $line -Scope Global"
            Write-Debug $line
            Invoke-Expression "`t$line" -ErrorAction Ignore
        }
    }
}
