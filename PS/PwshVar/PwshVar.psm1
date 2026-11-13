
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
    配置表达式每次重新求值，变量立即可用。默认在系统临时目录生成按组编译的脚本缓存，
    不修改 conf，不访问网络。源文件时间或大小变化、加载器更新时自动重建缓存。
    缓存检查、构建失败或缓存语法损坏时回退逐行加载；配置表达式报错时不重跑整组。
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
    $groupLoaded = $false
    # 调试输出仍走逐文件入口，保留原有的逐行 Write-Debug。
    if (-not $NoCache -and $DebugPreference -in @('SilentlyContinue', 'Ignore'))
    {
        $group = if ($Core) { 'Core' } elseif ($Fast) { 'Fast' } else { 'Full' }
        $groupCache = Get-PwshVarGroupCache -VarFiles $PwshVarFiles -Group $group
        if ($groupCache)
        {
            try
            {
                . $groupCache
                $groupLoaded = $true
            }
            catch [System.Management.Automation.ParseException]
            {
                # 完整脚本尚未开始执行，语法损坏时才可安全回退，避免重复运行表达式。
                Write-Verbose '变量组缓存语法损坏，本次回退逐文件加载。'
                try { [IO.File]::Delete($groupCache) } catch { Write-Verbose '无法删除损坏的变量组缓存。' }
            }
        }
    }
    if (-not $groupLoaded)
    {
        foreach ($VarFile in $PwshVarFiles)
        {
            Write-Verbose "processing:[$VarFile]"
            Import-PwshVarFile -VarFile $VarFile -NoCache
        }
    }
    # 全量导入后把等级标到 2：VarSet1.conf 固定写 1，若不提升，Test-PsEnvMode -Mode Vars
    # 永远为假，Update-PwshEnvIfNotYet -Mode Vars 会在每次调用时重复导入全量变量。
    # -Core/-Fast 是子集，保持 1；已有更高等级（如 Env=3）时不降级。
    $targetMode = if ($Core -or $Fast) { 1 } else { 2 }
    if ($null -ne $prevEnvMode -and $prevEnvMode -gt $targetMode) { $targetMode = $prevEnvMode }
    Set-Variable -Name PsEnvMode -Value $targetMode -Scope Global
    Write-Verbose 'envs updated!'
    
}

function ConvertTo-PwshVarScriptLine
{
    # 与逐行回退使用相同的转换规则，合并组缓存与单文件缓存共享此入口。
    param([string]$ConfPath)
    foreach ($rawLine in [IO.File]::ReadLines($ConfPath))
    {
        $line = $rawLine
        if (!$line.Contains('=')) { $line = $line -replace '(^.*?) ', '$1=' }
        if ($line.TrimStart() -match '^([a-zA-Z_$])')
        {
            $line -replace '^\s*\$?', '$global:'
        }
    }
}

function Get-PwshVarGroupCache
{
    <#
    .SYNOPSIS
    返回当前变量组的编译缓存路径；构建或校验失败时返回空值，不执行配置。
    #>
    param(
        [Parameter(Mandatory)][string[]]$VarFiles,
        [ValidateSet('Core', 'Fast', 'Full')][string]$Group = 'Core'
    )
    try
    {
        # 路径用可逆的十六进制编码；普通路径避免每个进程首次初始化加密组件的开销。
        $edition = [string]$PSVersionTable.PSEdition
        $rootBytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($PSScriptRoot))
        $pathId = [BitConverter]::ToString($rootBytes).Replace('-', '')
        $cache = [IO.Path]::Combine([IO.Path]::GetTempPath(), "CxxuPwshVarGroup_${pathId}_${Group}_${edition}_$($PSVersionTable.PSVersion.Major).cache.ps1")
        # 超长路径才使用摘要，保留 Windows PowerShell 5.1 的路径长度兼容性。
        if ($cache.Length -gt 240)
        {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $pathId = [BitConverter]::ToString($sha.ComputeHash($rootBytes)).Replace('-', '').Substring(0, 24) }
            finally { $sha.Dispose() }
            $cache = [IO.Path]::Combine([IO.Path]::GetTempPath(), "CxxuPwshVarGroup_${pathId}_${Group}_${edition}_$($PSVersionTable.PSVersion.Major).cache.ps1")
        }
        $sourcePaths = @([IO.Path]::Combine($PSScriptRoot, 'PwshVar.psm1'), [IO.Path]::Combine($PSScriptRoot, 'VarLongStrings.ps1'))
        foreach ($name in $VarFiles) { $sourcePaths += [IO.Path]::Combine($PSScriptRoot, 'confs', "$name.conf") }
        $stamps = foreach ($path in $sourcePaths)
        {
            $file = [IO.FileInfo]::new($path)
            if (-not $file.Exists) { return }
            [string]$file.LastWriteTimeUtc.Ticks + ':' + $file.Length
        }
        # 精确比较时间与长度，文件回退到较旧版本或被删除时也不能沿用旧缓存。
        $header = '# CxxuPwshVarGroup v1 ' + ($VarFiles -join ',') + ' ' + ($stamps -join '|')
        if ([IO.File]::Exists($cache))
        {
            $reader = [IO.File]::OpenText($cache)
            try { $valid = $reader.ReadLine() -eq $header }
            finally { $reader.Dispose() }
            if ($valid) { return $cache }
        }
        Get-CompiledPwshVarGroupFile -Cache $cache -Header $header -VarFiles $VarFiles
    }
    catch
    {
        Write-Verbose ("变量组缓存不可用，本次回退逐文件加载：{0}" -f $_.Exception.Message)
    }
}

function Get-CompiledPwshVarGroupFile
{
    # 构建代码仅在源文件变化时进入，避免正常启动也支付其首次编译成本。
    param([string]$Cache, [string]$Header, [string[]]$VarFiles)
    $pendingCache = $null
    try
    {
        $built = [Text.StringBuilder]::new()
        $null = $built.AppendLine($Header)
        foreach ($name in $VarFiles)
        {
            foreach ($line in (ConvertTo-PwshVarScriptLine -ConfPath ([IO.Path]::Combine($PSScriptRoot, 'confs', "$name.conf"))))
            {
                $null = $built.AppendLine($line)
            }
        }
        $scriptText = $built.ToString()
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$null, [ref]$parseErrors)
        if ($parseErrors.Count) { return }
        # 先写同目录临时文件，再原子替换，避免同时启动多个 pwsh 时读到半份脚本。
        $pendingCache = $cache + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        [IO.File]::WriteAllText($pendingCache, $scriptText, [Text.UTF8Encoding]::new($true))
        if ([IO.File]::Exists($cache))
        {
            [IO.File]::Replace($pendingCache, $cache, [Management.Automation.Language.NullString]::Value)
        }
        else
        {
            try { [IO.File]::Move($pendingCache, $cache) }
            catch [IO.IOException]
            {
                if (-not [IO.File]::Exists($cache)) { throw }
                [IO.File]::Replace($pendingCache, $cache, [Management.Automation.Language.NullString]::Value)
            }
        }
        return $cache
    }
    catch
    {
        Write-Verbose ("变量组缓存构建失败，本次回退逐文件加载：{0}" -f $_.Exception.Message)
        return
    }
    finally
    {
        if ($pendingCache -and [IO.File]::Exists($pendingCache))
        {
            try { [IO.File]::Delete($pendingCache) } catch { Write-Verbose '无法删除本次缓存构建的临时文件。' }
        }
    }
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
            $built = @(ConvertTo-PwshVarScriptLine -ConfPath $ConfPath)
            if ($built.Count -eq 0) { return }
            $parseErrs = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput(($built -join "`n"), [ref]$null, [ref]$parseErrs)
            if ($parseErrs.Count -gt 0) { return }
            [System.IO.File]::WriteAllLines($cache, $built, [System.Text.UTF8Encoding]::new($false))
            . $cache
            return $built
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
