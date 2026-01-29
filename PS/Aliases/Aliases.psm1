<# 
这里存放的是别名的处理函数
定义别名的文件和此文件在同一个目录下,用户可以根据需要自行修改或增加别名
包括函数别名(functions),程序路径(快捷方式shortcuts)别名等
#>
# $scripts = 'C:\repos\scripts'
# $alias_dir = Split-Path $PSScriptRoot 
$alias_dir = $PSScriptRoot
# $alias_dir = "$scripts\PS\aliases"
function Update-PwshAliases
{
    [CmdletBinding()]
    param(
        # [switch]$Fast,
        [switch]$Core
    )
    
    Write-Verbose 'updating aliases!'
    # 这里是载入pwsh环境变量的最初阶段,需要用绝对路径!
    $alias_file_core = @(
        'alias_core.ps1'
    )
    $alias_full = @(
        'functions', 
        'shortcuts'
    )
    if ($Core)
    {

        $alias_file_array = $alias_file_core
    }
    else
    {
        $alias_file_array = $alias_full
    }
    $alias_file_array | ForEach-Object {
        Set-PwshAliasFile $_
    }
    Write-Verbose 'aliases updated!'
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

    # foreach ($line in [System.IO.File]::ReadLines($alias_file)){
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
