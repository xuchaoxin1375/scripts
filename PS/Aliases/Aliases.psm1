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
    <#
    .SYNOPSIS
    加载核心或完整别名文件。
    .DESCRIPTION
    默认使用预编译缓存（按别名文件 mtime 失效）；缓存构建或点源失败时自动回退逐行
    Invoke-Expression。-NoCache 用于排查缓存问题，强制走逐行路径。
    .PARAMETER Core
    只加载 alias_core.ps1（启动首屏使用）；省略时加载 functions 与 shortcuts。
    .PARAMETER NoCache
    禁用预编译缓存，强制逐行加载。
    .EXAMPLE
    Update-PwshAliases -Core
    .EXAMPLE
    Update-PwshAliases -NoCache
    #>
    [CmdletBinding()]
    param(
        # [switch]$Fast,
        [switch]$Core,
        # 禁用预编译缓存（排查用）
        [switch]$NoCache
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
        Set-PwshAliasFile $_ -NoCache:$NoCache
    }
    Write-Verbose 'aliases updated!'
}

function Get-CompiledPwshAliasFile
{
    <#
    .SYNOPSIS
    把别名文件预编译成缓存脚本并点源执行；失败返回 $null，调用方回退逐行路径。
    .DESCRIPTION
    缓存只保存 set-alias 命令，AllScope 在构建时判定一次，避免每次启动逐行
    Get-Content/Get-Alias/Invoke-Expression。缓存失效条件：别名文件比缓存新。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AliasFilePath,
        [Parameter(Mandatory)][string]$AliasFileName
    )
    try
    {
        $cacheName = [IO.Path]::GetFileNameWithoutExtension($AliasFileName)
        # 缓存名带模块目录标识，避免同机多个仓库副本共用同名缓存而读到彼此的旧内容。
        $pathTag = ($alias_dir -replace '[^a-zA-Z0-9]', '_')
        $edition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
        $cache = Join-Path ([IO.Path]::GetTempPath()) "CxxuPwshAlias_${cacheName}_${pathTag}_${edition}_$($PSVersionTable.PSVersion.Major).cache.ps1"
        $sourceTime = (Get-Item -LiteralPath $AliasFilePath -ErrorAction Stop).LastWriteTimeUtc
        $regen = $true
        if (Test-Path -LiteralPath $cache)
        {
            $regen = $sourceTime -gt (Get-Item -LiteralPath $cache).LastWriteTimeUtc
        }
        if ($regen)
        {
            $built = [System.Collections.Generic.List[string]]::new()
            foreach ($rawLine in [System.IO.File]::ReadLines($AliasFilePath))
            {
                $line = $rawLine.ToString()
                if ($line -notmatch '^[\^a-zA-Z]') { continue }
                $aliasName = ($line -split '\s+', 2)[0]
                $existing = Get-Alias -Name $aliasName -ErrorAction Ignore |
                    Where-Object { $_.Name -eq $aliasName } |
                    Select-Object -First 1
                $option = ''
                if ($existing -and ($existing.Options -band [System.Management.Automation.ScopedItemOptions]::AllScope))
                {
                    $option = ' -Option AllScope'
                }
                $built.Add("set-alias $line$option -Scope Global")
            }
            if ($built.Count -eq 0) { return }
            $parseErrs = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput(($built -join "`n"), [ref]$null, [ref]$parseErrs)
            if ($parseErrs.Count -gt 0) { return }
            [System.IO.File]::WriteAllLines($cache, $built, [System.Text.UTF8Encoding]::new($false))
        }
        . $cache
        return $cache
    }
    catch
    {
        return
    }
}

function Set-PwshAliasFile
{
    [CmdletBinding()]
    param (
        $alias_file,
        # 禁用预编译缓存（排查用）
        [switch]$NoCache
    )
    # if ($line.Length -gt 0 -and !$line.startswith('#') )
    if ($VerbosePreference)
    {

        Write-Host "`t$alias_file" -ForegroundColor Magenta
    }
    $aliasFilePath = Join-Path $alias_dir $alias_file

    if (-not $NoCache)
    {
        $cache = Get-CompiledPwshAliasFile -AliasFilePath $aliasFilePath -AliasFileName $alias_file
        if ($cache) { return }
    }

    # foreach ($line in [System.IO.File]::ReadLines($alias_file)){
    [System.IO.File]::ReadLines($aliasFilePath) | ForEach-Object {
        $line = $_.ToString()
         
        Write-Debug $line -ErrorAction Ignore
        if ($line -match '^[\^a-zA-Z]')
        {
            # 5.1 的内置别名(rm/r/ps/h 等)带 AllScope。Set-Alias 默认会去掉 AllScope,
            # 于是报 "The AllScope option cannot be removed";这是非终止错误,别名保持原样,
            # 表现为自定义别名静默失效。这类别名必须显式带 -Option AllScope 才能改定义。
            $aliasName = ($line -split '\s+', 2)[0]
            $existing = Get-Alias -Name $aliasName -ErrorAction Ignore |
                Where-Object { $_.Name -eq $aliasName } |
                Select-Object -First 1
            $option = ''
            if ($existing -and ($existing.Options -band [System.Management.Automation.ScopedItemOptions]::AllScope))
            {
                $option = ' -Option AllScope'
            }
            $line = "set-alias $line$option -Scope Global"
            Write-Debug $line
            Invoke-Expression "`t$line" -ErrorAction Ignore
        }
    }
}
