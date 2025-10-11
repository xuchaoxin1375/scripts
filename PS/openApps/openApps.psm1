
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
    typora $blogs
    
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
    #方案1
    Start-Process $p &
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
