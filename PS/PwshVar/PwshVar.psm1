
function Import-PwshVarFileTesting
{
    [CmdletBinding()]
    param (
        $VarFile,
        [switch]$AsPwshEnvForHomeVars 
    )
    
    Write-Host "`t$VarFile" -ForegroundColor Cyan
    $VarFilesDir = $PSScriptRoot
    $VarFileFullPath = "$VarFilesDir\${VarFile}.conf"
    
    Get-Content $VarFileFullPath | ForEach-Object {
        $line = $_.ToString()
        if (!$line.Contains('='))
        {
            $line = $line -replace '(^.*?) ', '$1='
        }
        if ($line.TrimStart() -match '^([a-zA-Z_$])')
        {
            $pair = '^\s*\$?', '$global:' 
            $line = $line -replace $pair
            $varName = $line.Split('=')[0].split(':')[1]
            Invoke-Expression $line 

        
            if ($AsPwshEnvForHomeVars)
            {
                if ($line -like '*home=*')
                { 
                  
                    
                    $value = Get-Variable -Name $varName 
                    $env:path += ";$($value.value)"     
                }
            }
        }
        else
        {
            return 
        }
        Write-Debug $line  

    }
         
}


# 将常量写在模块函数外，对于powershell v5来说不友好
# 如果需要兼容windows powershell,需要将他们移入到函数中去

# function Get-VarFilesInner
# {
 
#     return { $VarFilesDir = $PSScriptRoot
#         $PwshVarFilesFast = @(
#             'VarSet1', 
#             'VarSet2'
#             'GlobalConfig'
#         )
#         $PwshVarFilesEnhance = @(
#             'VarSet3', 
#             'VarAndroid',
#             'VarFiles'
#         )
#         $PwshVarFilesFull = $PwshVarFilesFast + $PwshVarFilesEnhance }
# }

# linux 化风格的环境变量

function Update-PwshVars
{
    [CmdletBinding()]
    param(
        [switch]$Fast,
        [switch]$Core,
        # 透传给 Import-PwshVarFile:禁用预编译缓存(排查用)
        [switch]$NoCache
    )
    
    $PwshVarFilesCore = @(
        'VarSet1',
        'Varset2', 
        # 'GlobalConfig'
        ,
        'ConstantString'
    )
    $PwshVarFilesFast = @(
        'VarSet1', 
        'VarSet2'
        # ,
        'GlobalConfig'
        # ,
        'ConstantString'
    )
    $PwshVarFilesWindows = @(

        'VarSet3' 
    )
    $PwshVarFilesMacOs = @(

        'VarSet3.macos' 
    )
    $PwshVarFilesEnhance = @(
        'VarAndroid',
        'VarFiles'
    )
    # 5.1 无 $IsWindows($null);PSEdition Desktop 即 Windows(5.1 只跑在 Windows 上)
    if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows)
    {
        $PwshVarFilesEnhance += $PwshVarFilesWindows
    }
    elseif($IsMacOS)
    {
        $PwshVarFilesEnhance += $PwshVarFilesMacOs
    }
    $PwshVarFilesFull = $PwshVarFilesFast + $PwshVarFilesEnhance 

    # write-verbose "checking the environment of the windows system (`$env:variables)😊..." 
    Write-Verbose 'updating envs!'
    # 执行这段导入环境变量的逻辑时,不可以使用定义在环境变量文件中的变量,这会出现引用未定义变量的问题
    #注意字符串末尾没有反斜杠,拼接路径的时候需要加一个斜杠
    #🎈在需要添加新的环境变量配置文件时,只需要在PwshVarFiles中追加即可
    # 单独导入长字符串,手动声明为$global:变量

    $express = ". `"$PSScriptRoot\VarLongStrings.ps1`""
    Write-Verbose "executing $express"
    Invoke-Expression $express
    

    # $PwshVarFiles = ($Fast ) ? $PwshVarFilesFast : $PwshVarFilesFull
    if ($core)
    {
        $PwshVarFiles = $PwshVarFilesCore
    }
    elseif ($Fast)
    {
        $PwshVarFiles = $PwshVarFilesFast
    }
    else
    {
        $PwshVarFiles = $PwshVarFilesFull
    }

    # $PSVersion = $PSVersionTable.PSVersion.Major

    
    foreach ($VarFile in $PwshVarFiles) 
    {
        Write-Verbose "processing:[$VarFile]"
        Import-PwshVarFile -VarFile $VarFile -NoCache:$NoCache # -AsPwshEnvForHomeVars
    }
    Write-Verbose 'envs updated!'
    
}

function Get-CompiledPwshVarLines
{
    <#
    .SYNOPSIS
    将变量 conf 文件预编译为缓存脚本并点源执行,返回转换后的可执行行;任何失败返回 $null
    .DESCRIPTION
    转换规则与逐行 Invoke-Expression 完全一致(同一套正则),但整个文件只解析一次。
    缓存失效条件:conf 比缓存新。缓存经 Parser 语法校验,点源失败也会回退,调用方无感。
    #>
    [CmdletBinding()]
    param(
        $ConfPath,
        $VarFile
    )
    try
    {
        $cache = Join-Path ([System.IO.Path]::GetTempPath()) "CxxuPwshVar_$VarFile.cache.ps1"
        $confTime = (Get-Item -LiteralPath $ConfPath -ErrorAction Stop).LastWriteTimeUtc
        $regen = $true
        if (Test-Path -LiteralPath $cache)
        {
            $regen = $confTime -gt (Get-Item -LiteralPath $cache).LastWriteTimeUtc
        }
        if ($regen)
        {
            $built = [System.Collections.Generic.List[string]]::new()
            foreach ($rawLine in ([System.IO.File]::ReadLines($ConfPath)))
            {
                $line = $rawLine.ToString()
                if (!$line.Contains('='))
                {
                    $line = $line -replace '(^.*?) ', '$1='
                }
                if ($line.TrimStart() -match '^([a-zA-Z_$])')
                {
                    $line = $line -replace '^\s*\$?', '$global:'
                    $built.Add($line)
                }
            }
            if ($built.Count -eq 0) { return }
            $parseErrs = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput(($built -join "`n"), [ref]$null, [ref]$parseErrs)
            if ($parseErrs.Count -gt 0) { return }
            [System.IO.File]::WriteAllLines($cache, $built, [System.Text.UTF8Encoding]::new($false))
            . $cache
            return $built.ToArray()
        }
        else
        {
            $cached = Get-Content -LiteralPath $cache
            . $cache
            return $cached
        }
    }
    catch
    {
        return
    }
}
function Import-PwshVarFileLegacy
{
    <#
    .SYNOPSIS
    原始逐行 Invoke-Expression 路径,仅作缓存失败时的回退,语义保持不变
    #>
    [CmdletBinding()]
    param(
        $VarFileFullPath,
        [switch]$AsPwshEnvForHomeVars
    )
    Get-Content $VarFileFullPath | ForEach-Object { #后面使用retur来跳过不合法条目
        Write-Debug "content: $line"
        $line = $_.ToString()
        if (!$line.Contains('='))
        {
            $line = $line -replace '(^.*?) ', '$1='
        }
        if ($line.TrimStart() -match '^([a-zA-Z_$])')
        {
            $pair = '^\s*\$?', '$global:'
            $line = $line -replace $pair
            $varName = $line.Split('=')[0].split(':')[1]
            Invoke-Expression $line -ErrorAction SilentlyContinue
            if ($AsPwshEnvForHomeVars)
            {
                if ($line -like '*home=*')
                {
                    $value = Get-Variable -Name $varName
                    $env:path += ";$($value.value)"
                }
            }
        }
        else
        {
            return
        }
        Write-Debug $line
    }
}
function Import-PwshVarFile
{
    <#
    .SYNOPSIS
    从文件中加载pwsh变量,创建基本的pwsh变量环境
    .DESCRIPTION
    由于读取文件涉及到io操作,需要尽快加速此过程,可以使用.Net api 而不是powershell管用方法里读取,尤其是作为pwsh加载任务,需要尽可能高的性能
    但是,如果需要处理的文件不是很大,那么使用.Net api 反而可能更慢
    .NOTES
    默认启用预编译缓存(见 Get-CompiledPwshVarLines):与逐行执行语义相同但只解析一次;
    用 -NoCache 可回退到原始逐行路径(排查用)。
    #>
    [CmdletBinding()]
    param (
        # 虽然可以使用[ValidateSet()]来指定常用的变量定义列表文件名,但是不利于维护,可以先查看Pwsh目录下的文件,然后手动指定一个文件
        # 此外,对于比较熟悉本模块的用户，完全可以直接指定文件名
        $VarFile,
        [switch]$AsPwshEnvForHomeVars,
        [switch]$NoCache
    )
    if ($VerbosePreference)
    {

        Write-Host "`t$VarFile" -ForegroundColor Cyan
    }
    # 变量文件存储位置
    $VarFilesDir = $PSScriptRoot + '\confs'
    $VarFileFullPath = "$VarFilesDir\${VarFile}.conf"
    Write-Debug "`t$VarFileFullPath" #-ForegroundColor yellow

    $execLines = @()
    if (-not $NoCache)
    {
        # 注意:Get-CompiledPwshVarLines 失败时返回 $null,经 @() 归一化后 Count 为 0,即走回退
        $execLines = @(Get-CompiledPwshVarLines -ConfPath $VarFileFullPath -VarFile $VarFile)
    }
    if ($execLines.Count -eq 0)
    {
        # 如果使用parallel处理,定义在变量列表中的变量创建顺序求无法得到保证,可能导致错误!
        Import-PwshVarFileLegacy -VarFileFullPath $VarFileFullPath -AsPwshEnvForHomeVars:$AsPwshEnvForHomeVars
        return
    }
    # 缓存命中:变量已由点源创建,此处仅处理 home 附加逻辑(调用方目前未启用,保留语义)
    foreach ($line in $execLines)
    {
        if ($AsPwshEnvForHomeVars -and ($line -like '*home=*'))
        {
            $varName = $line.Split('=')[0].split(':')[1]
            $value = Get-Variable -Name $varName
            $env:path += ";$($value.value)"
        }
        Write-Debug $line
    }
}


function Import-ANSIColorEnv
{
    
    <# 
    .SYNOPSIS
    向当前运行的powershell导入ANSI颜色环境变量
    .DESCRIPTION
    染色变量使用格式`${color}${text}${Reset}`中，如`${red}这是红色文本${Reset}`
    .EXAMPLE
    PS C:\Users\cxxu\Desktop>  write-Host "${BgbrightBlue}${red}这是蓝色背景红色文本${Reset}"
    这是蓝色背景红色文本
    #>
    
    Import-PwshVarFile -VarFile VarColors

    Write-Host "${Cyan}ANSI Color Environment Variables${Reset}  ${blue}Set${Reset}!"

}