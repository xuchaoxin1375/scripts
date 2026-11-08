
<# 😎😎😎😎
.SYNOPSIS
- 优先使用aliases.ps1来配置命令行别名启动软件

- 但是某些软件的启动需要带有参数,这时候才考虑将配置写入到本文件中
- 还有一种情况就是软件会在终端输出一堆日志, 如果不希望看奥输出, 可以配置为函数` software *> $null`进行屏蔽
这将把所有输出屏蔽掉(包括普通日志和错误输出)
    - 例如` clash > $null`

#>
function Set-DefaultAppForExtension
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        [Parameter(Mandatory = $true)]
        [string]$AppPath,
        [Parameter(Mandatory = $true)]
        [string]$ProgID
    )

    $regPath = "HKCU:\Software\Classes\$Extension"
    $commandRegPath = "$regPath\shell\open\command"

    # 检查应用程序路径是否存在
    if (-Not (Test-Path $AppPath))
    {
        Write-Warning '应用程序路径不存在，请检查路径是否正确。'
        return
    }

    # 创建或设置文件扩展名关联
    if (-Not (Test-Path $regPath))
    {
        New-Item -Path $regPath -Force 
    }
    Set-ItemProperty -Path $regPath -Name '(Default)' -Value $ProgID

    # 设置 ProgID 键
    $progIDRegPath = "HKCU:\Software\Classes\$ProgID"
    if (-Not (Test-Path $progIDRegPath))
    {
        New-Item -Path $progIDRegPath -Force 
    }

    # 创建或设置命令
    if (-Not (Test-Path $commandRegPath))
    {
        New-Item -Path $commandRegPath -Force 
    }
    Set-ItemProperty -Path $commandRegPath -Name '(Default)' -Value "`"$AppPath`" `"%1`""

    Write-Host "已将 .$Extension 文件的默认打开方式设置为 $AppPath."
}

# 调用示例
# 为了将 .ps1 文件关联到 PowerShell 7，可以调用：
# Set-DefaultAppForExtension -Extension "ps1" -AppPath "C:\Program Files\PowerShell\7\pwsh.exe" -ProgID "Microsoft.PowerShellScript.1"

function set-PsScriptDefaultRunner
{
    <# 
    .SYNOPSIS
    设置.ps1文件的默认打开方式
    通常powershell7 安装在'C:\program files\powershell\7\pwsh.exe'（for all user)
    .NOTES
    效果可能知识将$program所指的程序加入到打开列表候选,但这已经挺方便的,只需要在弹出的窗口点击总是用该选项打开即可
    #>
    param(
    
        $program = "$pwsh7_home\pwsh.exe",
        $fileType = 'Microsoft.PowerShellScript.1'
    )
    $CommandExpression = 'ftype' + ' ' + "$fileType=`"$Program`" `"%1`""
    cmd /c $CommandExpression
}
function typora_home
{
    param (
        
    )
    Start-Typora $blogs
    
}

function Start-Typora
{
    <#
    .SYNOPSIS
    用 Typora 打开文件、目录，或直接启动 Typora。

    .DESCRIPTION
    macOS 通过 `open -a` 调用 Typora，可同时接受多个目标；省略目标时只启动应用。
    Windows 调用 `typora.exe`（优先使用 `$typora_home` 下的安装路径）。
    支持从管道接收路径，例如 `Get-ChildItem *.md | Start-Typora`。
    `typora` 别名在 `Aliases/alias_core.ps1` 中定义，指向本函数。

    .PARAMETER Path
    要打开的文件或目录；省略时只启动 Typora。

    .EXAMPLE
    Start-Typora .
    # 用 Typora 打开当前目录

    .EXAMPLE
    Get-ChildItem *.md | Start-Typora
    # 批量打开当前目录下的 Markdown 文件
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )

    begin
    {
        $targets = [System.Collections.Generic.List[string]]::new()
    }
    process
    {
        foreach ($item in $Path)
        {
            if (-not [string]::IsNullOrWhiteSpace($item))
            {
                $targets.Add($item)
            }
        }
    }
    end
    {
        # 5.1 无 $IsWindows:Desktop 即 Windows(5.1 只跑 Windows)
        if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
        {
            $exe = if ($typora_home)
            {
                Join-Path $typora_home 'typora.exe'
            }
            else
            {
                'typora.exe'
            }
            if ($targets.Count -eq 0)
            {
                Start-Process -FilePath $exe
            }
            else
            {
                foreach ($target in $targets)
                {
                    Start-Process -FilePath $exe -ArgumentList $target
                }
            }
            return
        }
        if ($IsMacOS -ne $true)
        {
            Write-Error 'Start-Typora 仅支持 Windows 与 macOS。'
            return
        }

        if ($targets.Count -eq 0)
        {
            & open -a '/Applications/Typora.app'
        }
        else
        {
            & open -a '/Applications/Typora.app' $targets
        }
        if ($LASTEXITCODE -ne 0)
        {
            Write-Error "Typora 打开失败(open 退出码 $LASTEXITCODE),请确认已安装 /Applications/Typora.app。"
        }
    }
}

# 压制输出日志
function qq_run
{
    qq *> $null # $null

}

function clash_run
{
    clash *>$null
    # Start-ProcessSilentlyFromShortcut -ShortcutName 'Clash for windows.lnk'
}
function run_silently
{
    param(
        $software
    )
    Invoke-Expression "$software *> `$NULL"
}
function qq
{
    run 'TencentQQ'
    
}

function Start-ProcessSilentlyFromShortcut
{
    param (
        $Path,
        $ShortcutName
    )
    if ($ShortcutName)
    {

        $Path = Get-Command $ShortcutName
    }
    $p = $Path | Select-Object -ExpandProperty Source; 
    #方案1(Start-Process 本就不阻塞,7 的后台 & 是冗余的,去之以兼容 5.1,行为不变)
    Start-Process $p
    #方案2
    # $s = Get-ShortcutLinkInfo $p | Select-Object -ExpandProperty TargetPath; 
    # & $s *>$null
}

function hostsEdit
{
    c $env:hosts
}
function anaconda
{
    C:\ProgramData\Anaconda3\pythonw.exe C:\ProgramData\Anaconda3\cwp.py C:\ProgramData\Anaconda3 C:\ProgramData\Anaconda3\pythonw.exe C:\ProgramData\Anaconda3\Scripts\anaconda-navigator-script.py
}
#explorer there
function condaPrompt
{
    cmd '/K' C:\ProgramData\Anaconda3\Scripts\activate.bat C:\ProgramData\Anaconda3
}
function wireSharkPortable
{
    & $env:exes\wiresharkPortable64\wiresharkPortable64.exe
}
function ept { explorer . }
function wtAs
{
    Start-Process -Verb RunAs wt
}

function NetSpeed
{
    param (
        
    )
    Write-Output 'try to start 360SpeedTest...'
    & $env:360SpeedTest
    Write-Output 'start successful.'
}
function msys2
{
    msys2_shell -defterm -here -no-start -msys
}
