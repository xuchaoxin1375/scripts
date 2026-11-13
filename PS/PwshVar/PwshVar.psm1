
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
    <#
    .SYNOPSIS
    从配置文件加载预设的 PowerShell 变量。
    .DESCRIPTION
    默认按配置顺序加载完整变量组。Core、Fast 选择原有子集；同时指定时 Core 优先。
    配置表达式每次重新求值，变量立即可用。默认使用系统临时目录中的单文件脚本缓存，
    源配置比缓存新时重建。不修改 conf，不访问网络；缓存不可用时回退逐行加载。
    配置表达式的运行错误直接报告，不通过重复执行配置来回退。
    .PARAMETER Core
    只加载 VarSet1、VarSet2 和 ConstantString，供启动时使用。
    .PARAMETER Fast
    加载 VarSet1、VarSet2、GlobalConfig 和 ConstantString。
    .PARAMETER NoCache
    不读取或写入编译缓存，逐行执行配置，用于排查缓存问题。
    .EXAMPLE
    Update-PwshVars -Core
    .EXAMPLE
    Update-PwshVars -Fast
    .EXAMPLE
    Update-PwshVars
    .EXAMPLE
    Update-PwshVars -Core -NoCache
    .NOTES
    完整变量组将 PsEnvMode 提升到 2，Core/Fast 提升到 1；不降低已有更高等级。
    #>
    [CmdletBinding()]
    param(
        [switch]$Fast,
        [switch]$Core,
        [switch]$NoCache
    )
    
    $PwshVarFilesCore = @(
        'VarSet1',
        'VarSet2',
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

    # 保持长字符串脚本的原始位置与点源作用域，不通过字符串再解析调用。
    . ([IO.Path]::Combine($PSScriptRoot, 'VarLongStrings.ps1'))
    

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

    
    $prevEnvMode = $global:PsEnvMode
    foreach ($VarFile in $PwshVarFiles)
    {
        Write-Verbose "processing:[$VarFile]"
        Import-PwshVarFile -VarFile $VarFile -NoCache:$NoCache
    }
    # 全量导入后把等级标到 2：VarSet1.conf 固定写 1，若不提升，Test-PsEnvMode -Mode Vars
    # 永远为假，Update-PwshEnvIfNotYet -Mode Vars 会在每次调用时重复导入全量变量。
    # -Core/-Fast 是子集，保持 1；已有更高等级（如 Env=3）时不降级。
    $targetMode = if ($Core -or $Fast) { 1 } else { 2 }
    if ($null -ne $prevEnvMode -and $prevEnvMode -gt $targetMode) { $targetMode = $prevEnvMode }
    Set-Variable -Name PsEnvMode -Value $targetMode -Scope Global
    Write-Verbose 'envs updated!'
    
}

function Get-CompiledPwshVarLines
{
    <#
    .SYNOPSIS
    将变量 conf 文件转换为单文件缓存脚本并点源执行，返回可执行行。
    .DESCRIPTION
    源配置比缓存新时重新转换。缓存读取、写入或语法检查失败时返回空值，供调用方逐行回退。
    配置表达式的运行错误向调用方报告，不回退重跑，以免重复执行已发生的副作用。
    .PARAMETER ConfPath
    源 conf 文件的完整路径。
    .PARAMETER VarFile
    缓存文件标识，通常为不含扩展名的配置文件名。
    .EXAMPLE
    Get-CompiledPwshVarLines -ConfPath (Resolve-Path ./PS/PwshVar/confs/VarSet1.conf).Path -VarFile VarSet1
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
            foreach ($rawLine in [System.IO.File]::ReadLines($ConfPath))
            {
                $line = $rawLine
                if (!$line.Contains('=')) { $line = $line -replace '(^.*?) ', '$1=' }
                if ($line.TrimStart() -match '^([a-zA-Z_$])')
                {
                    $built.Add(($line -replace '^\s*\$?', '$global:'))
                }
            }
            if ($built.Count -eq 0) { return }
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput(($built -join "`n"), [ref]$null, [ref]$parseErrors)
            if ($parseErrors.Count) { return }
            # 5.1 将点源执行缓存脚本，中文内容需要 UTF-8 BOM。
            [System.IO.File]::WriteAllLines($cache, $built, [System.Text.UTF8Encoding]::new($true))
            $execLines = $built.ToArray()
        }
        else
        {
            $execLines = Get-Content -LiteralPath $cache -Encoding UTF8 -ErrorAction Stop
        }
    }
    catch
    {
        return
    }
    # 只对尚未执行的语法错误回退；运行错误不能被缓存准备阶段的 catch 吞掉。
    try { . $cache }
    catch [System.Management.Automation.ParseException] { return }
    return $execLines
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
    # 变量文件存储位置(Join-Path 跨平台；反斜杠拼接在 Linux 下解析不出文件，init 会断)
    $VarFilesDir = Join-Path $PSScriptRoot 'confs'
    $VarFileFullPath = Join-Path $VarFilesDir "$VarFile.conf"
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
