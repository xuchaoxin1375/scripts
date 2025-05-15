

# '-----------------add function below-----------'

function Install-SubModules
{
    foreach ($s in @('backup', 'deploy', 'wifi'))
    {
        $expression = "$PSScriptRoot\$s.ps1"
        . $expression
        Write-Host "$expression"
    }
}

function Get-SpeechVoiceOptions
{
  
    <# 
    .SYNOPSIS
    获取可用的系统语音引擎(可能是不完整的,需要您打开系统设置里找到speech查看可用的语音引擎列表)
    较新的windows(我在24h2上操作过)系统语音引擎管理可以添加自然语言的TTS引擎,这类引擎很逼真,和edge浏览器中的朗读引擎基本同款,不过windows系统里是需要下载,可以离线使用,但是这里的api似乎难以调用自然语音朗读引擎(可惜)
    windows中语音转文字主要用来为无障碍功能服务,比如Narrator(旁白),可以在部分情况下朗读屏幕上的文字,比如设置页面中各个按钮或控件及其说明文字
    #>
    $sapi = New-Object -ComObject SAPI.SpVoice
    $sapi.GetVoices() | ForEach-Object { $_.GetDescription() }

}

function New-TextToSpeech
{
    <# 
        .SYNOPSIS
        通过计算机扬声器大声朗读消息。
        
        .Description
        New-TTS
        windows的报时api是一个阻塞调用者进程的进程,类似于sleep 一段时间(报读文字结束后再回来)
        所以可以考虑用异步job来处理
        
        然而,在函数内部直接使用start-job运行ScriptBlock会有变量传递问题,也就是参数在scriptblock中难以被解析,而是以错误告终
        我们可以为这类需要异步执行的函数配置一个Handler辅助函数,也就是对这个函数再次打包一下;
        或者将核心函数名设置Core后缀,然后用不带Core的函数名包装,这样可以便于其他地方用参数-BgJob来指明后台运行相关任务,而不需要在外部使用Start-Job命令来修饰
        
        虽然使用Start-job 也没有那么不便,相反,还可以让函数更加注重逻辑,而不是什么都干
        
        Start-job 使用-ScriptBlock {}参数编写依然可以使用命令行参数补全功能等,注意不要用字符串(引号包裹命令会难以借助补全)
        然而这种用法的问题仍然是定义在ScriptBlock外的变量无法被Start-job新建的powershell进程识别,造成不便

        幸运的是,我们可以利用Start-job -ArgumentList来传递参数，这样就可以在ScriptBlock中使用变量了
        有两类选择:$input配合 -InputObject <arg>,或者{param($p)} 配合-argumentlist <arg>
        

        .Notes
        Alias: New-TextToSpeechMessage->speech
        
        .EXAMPLE
        New-TextToSpeech -Message 'This is the text I want to have read out loud' -Voice Zira
        
        .EXAMPLE
        # Scriptblock中不含有变量,而只有字面量,而且执行的函数New-TextToSpeech是定义在自动导入模块中,
        因此都是可以被pwsh直接识别的而不依赖于外部定义的变量,可以成功按预期运行
        Start-job -scriptblock {New-TextToSpeech -message "Get Time SetSecondsToZero"}
        .EXAMPLE
        # 下面这个例子中用到了变量$m(不是定义在Scriptblock内),无法被Start-job的ScriptBlock识别，因此出问题
        PS C:\Users\cxxu\Desktop> $m='abc'
        PS C:\Users\cxxu\Desktop>  Start-job -scriptblock {New-TextToSpeech -message $m}
        在 PowerShell 中，变量在不同作用域之间是独立的，因此在 ScriptBlock 中直接使用外部定义的变量 $m 是不行的。你可以通过使用 -ArgumentList 参数将变量传递给 Start-Job 的 ScriptBlock。
        执行以下脚本:可以看到效果
        $m = 'abc'
        Start-Job -ScriptBlock {
            param($message)
            New-TextToSpeech -message $message
        } -ArgumentList $m

        .EXAMPLE
        # 使用$input变量和-InputObject参数
        PS C:\exes> start-job {param($m) New-TextToSpeech -message $input} -InputObject $m

        Id     Name            PSJobTypeName   State         HasMoreData     Location
        --     ----            -------------   -----         -----------     --------
        13     Job13           BackgroundJob   Running       True            localhost
        .EXAMPLE
        #使用{param($message)} 传递参数
        PS C:\exes> start-job {param($m) New-TextToSpeech -message $m} -ArgumentList $m

        Id     Name            PSJobTypeName   State         HasMoreData     Location
        --     ----            -------------   -----         -----------     --------
        9      Job9            BackgroundJob   Running       True            localhost
        .EXAMPLE
        PS C:\Users\cxxu\Desktop>  Start-job -scriptblock {speech -message "$(Get-Time -SetSecondstoZero)"}

        Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
        --     ----            -------------   -----         -----------     --------             -------
        9      Job9            BgJob   Running       True            localhost            speech -message "$(Get-T…

        PS C:\Users\cxxu\Desktop>  Start-job -scriptblock {speech -message "$(Get-Date)"}

        Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
        --     ----            -------------   -----         -----------     --------             -------
        11     Job11           BgJob   Running       True            localhost            speech -message "$(Get-D…
         #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'message')]
        [string]$message,
    
        [Parameter(ParameterSetName = 'Path')]
        $Path = '',
        # [ValidateSet('Zira', 'Huihui', 'David',...)] # 区分大小写!
        [string]$DesktopVoice = 'Zira',
        [switch]$BgJob
    )
    if ($Path)
    {
        $message = Get-Content $Path
    }
    $script = {
        Add-Type -AssemblyName System.Speech
        $speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $Speak.SelectVoice("Microsoft $DesktopVoice Desktop") #使用start-job可能无法识别$DesktopVoice变量
        $speak.Speak($message)
    }
    & $script

    # if ($BgJob)
    # {
    #     # ScriptBlock中无法解析参数变量,建议放到外部显示使用Start-job -scriptblock { New-TextToSpeech ...}的方式来进行后台运行
    #     $j = Start-Job -ScriptBlock $script 
        
    #     return $j
    # }
    # else
    # {
    #     & $script
    # }

}


function ls_eza
{
    <# 
.SYNOPSIS
eza is a modern, maintained replacement for the venerable file-listing command-line program ls that ships with Unix and Linux operating systems, giving it more features and better defaults. It uses colours to distinguish file types and metadata. It knows about symlinks, extended attributes, and Git. And it’s small, fast, and just one single binary.

By deliberately making some decisions differently, eza attempts to be a more featureful, more user-friendly version of ls.
.description
the windows version of eza is very easy to install (just need a good network)
however, in the linux version, the installation may be difficult to success in the first time
.LINK
- https://github.com/eza-community/eza
- https://www.sysgeek.cn/eza-command/
.EXAMPLE
PS>eza -ghil --icons
Mode  Size Date Modified Name
-a--- 331k 18 Mar 18:59   20240318_185950.mp4
-a--- 1.2M 18 Mar 19:10   20240318_191010.mp4
d----    - 10 Mar 23:22   ansel
d-r--    - 18 Mar 19:34  󰉌 Contacts
d-r--    - 18 Mar 19:36   Desktop
.EXAMPLE
PS>eza --icons -TL 2
 .
├──  20240318_185950.mp4
├──  20240318_191010.mp4
├──  ansel
├── 󰉌 Contacts
├──  Desktop
│  ├──  blogs_home.lnk
│  ├──  EM.lnk
│  ├──  math.lnk
│  ├──  neep.lnk
│  └──  四边形加固为刚性结构.ggb
├──  Documents
│  ├──  Apowersoft
│  ├──  Captura

.EXAMPLE
PS>eza --icons -ghilTL 2
Mode  Size Date Modified Name
d----    - 18 Mar 19:34   .
-a--- 331k 18 Mar 18:59  ├──  20240318_185950.mp4
-a--- 1.2M 18 Mar 19:10  ├──  20240318_191010.mp4
d----    - 10 Mar 23:22  ├──  ansel
d-r--    - 18 Mar 19:34  ├── 󰉌 Contacts
d-r--    - 18 Mar 19:36  ├──  Desktop
-a--- 1.4k 17 Jan 10:31  │  ├──  blogs_home.lnk
-a--- 1.4k 19 Jan 14:15  │  ├──  EM.lnk
-a--- 1.4k 19 Jan 14:14  │  ├──  math.lnk
-a--- 1.4k 17 Jan 10:33  │  ├──  neep.lnk
-a---  44k 15 Mar 20:13  │  └──  四边形加固为刚性结构.ggb
d-r--    - 18 Mar 19:34  ├──  Documents
d----    - 18 Mar 18:22  │  ├──  Apowersoft
d----    - 18 Mar 18:03  │  ├──  Captura
#>

    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $deepth = 2
    )
    eza -ghil --icons -TL $deepth

    
}
function Restart-TrafficMonitor
{
    Get-Process 'trafficMonitor*' | Stop-Process
    trafficMonitor 
}
function Get-Fonts()
{
    # [System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')
    (New-Object System.Drawing.Text.InstalledFontCollection).Families
}



function wiki2latex
{
    param(
        [Parameter(ValueFromPipeline)]
        [String]
        $content = (Get-Clipboard)
    )
    process
    {
        $content>$tmp_clipboard
        py "$repos\pythonLearn\scripts\wiki_deal_bracket.py"
        $data_out = (Get-Content $tmp_clipboard)
        # write-host $data_out
        $data_out | Set-Clipboard
    }
}
function ty2latex
{
    <# 
    .SYNOPSIS
    将字符串中的 \(,\) 转换成 $
    将字符串中的 \[,\] 转换成 $$
    .EXAMPLE
    PS>ty2latex '$\left( \frac{1}{2} \right)$'
    #>

    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        $String,
        $Path = "$home\desktop\ty2latex.txt"
    )
    #默认从文件中读取内容
    if (!$String)
    {
        if (Test-Path $Path)
        {
            $String = Get-Content $Path
        }
        $String = Get-Clipboard
    }
    #方案1:正则匹配
    $res = $String -replace '(\\\(\s*)|(\s*\\\))', '$' -replace '(\\\[\s*)|(\s*\\\])', '$$$$'
    #方案2:精准替换(容错性不足,但是规则简单,使用字符串的Replace()函数)
    # $res=$String.replace('\(','$').replace('\)','$').replace('\[','$$').replace('\]','$$')

    # $res = $String 
    $res | Set-Clipboard
    $res
}
function wechat_second
{
    Start-ProgramInSandboxie -Program (Get-ShortcutPath wechat)
}
function startup_register
{
    # 先定位到 HKEY_USERS 下对应的 SID 键
    $SID = 'S-1-5-21-1150093504-2233723087-916622917-1001'
    $keyPath = "Registry::HKEY_USERS\$SID\Software\Microsoft\Windows\CurrentVersion\Run"

    # 列出该路径下的注册表键及其值
    Get-ItemProperty -Path $keyPath
}
# function Get-RandomColorName {
#     <# 
#     .SYNOPSIS
#     随机地从颜色数组中获取一种颜色名字返回
#     #>
#     $colors = @('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White')

#     $colors | Ge-Random
    
# }
function wechat_multiple
{
    <# 
    .SYNOPSIS
    模拟短时间内点击多次微信弹出多个登录窗口
    如果报错,则可能是微信安装路径出错,请检查微信安装路径

    说明:本程序会判断是否已经有微信进程,如果没有微信进程,则直接打开多个登录窗口
    否则会询问用户是否关闭所有微信进程,以便于多开微信
    (因为这里采用的方法要求在没有微信进程的情况下运行才能生效;在未来,微信可能自带支持多开功能,就像多开qq一样方便)
    但是中所周知,微信团队比qq团队要懒,很多地方没有做好,功能比较受限,可能相当长的时间微信不会主动支持多开
    
    .EXAMPLE
    PS C:\repos\scripts> wechat_multiple -multiple_number 2
        wechat is running,stop all wechat process to start multiple wechat?
        Enter 'y' to continue😎('N' to exit the process!)  : y

    PS C:\Program Files\Typora> wechat_multiple
    2 wechat login process were started!😊
    #>

    param(

        # 配置为自己的微信安装目录即可(注意末尾WeChat是目录)
        $wechat_home = '$wechat_home' ,
        # 可以自行指定多开数量
        $multiple_number = 2
    )

    if (Get-Process | Select-String wechat)
    {
        # 读取键盘输入(read input by read-host)
        $Inquery = Read-Host -Prompt "wechat is running,stop all wechat process to start multiple wechat? `n Enter 'y' to continue😎('N' to exit the process!)  "
        if ($Inquery -eq 'y')
        {
            # 关闭微信进程,以便多开微信
            Get-Process wechat | Stop-Process        
        }
        else
        {
            Write-Host 'operation canceled!'
            return
        }
    }
    # 程序的主体部分
    foreach ($i in 1..$multiple_number)
    {
        Start-Process $wechat_home\wechat.exe
    }

    Write-Host "$multiple_number wechat login processes were started!😊"
}


function check_keyboards
{
    powershell.exe { 
        Write-Host $(Get-WinUserLanguageList)
        #  $zh = $l[1].inputMethodTips;
    }
}
function check_zh_keyboards
{
    powershell.exe { 
        $l = Get-WinUserLanguageList
        $zh = $l | Where-Object { $_.languageTag -match 'zh-hans-cn' }
        return $zh
    }
}


function remove_sogou_keyboard
{
    powershell.exe { 
        $l = Get-WinUserLanguageList 
        # $zh = $l[1].inputMethodTips;
        # $zh = check_zh_keyboards#无法直接从pwsh5传递对象回pwsh7
        $zh = $l | Where-Object { $_.languageTag -match 'zh-hans-cn' }
        $zhTips = $zh.inputMethodTips
        Write-Host "list:$l; `nzh:$zh"
        # $sogou_keyboard = $zhTips[1]
        $sogou_keyboard = $zhTips | Where-Object { $_ -like '*e7ea*' }
        Write-Host "sogou:$sogou_keyboard"
        $zhTips.remove($sogou_keyboard)
        Write-Host "now:$zh"

        Set-WinUserLanguageList -LanguageList $l -Force }
}
function add_sogou_keyboard
{
    # param ()
    powershell.exe {
        $sogou_keyboard_tips = '0804:{E7EA138E-69F8-11D7-A6EA-00065B844310}{E7EA138F-69F8-11D7-A6EA-00065B844311}'
        $l = Get-WinUserLanguageList
        $zh = $l | Where-Object { $_.languageTag -match 'zh-hans-cn' }
        Write-Host "list:$l; `nzh:$zh;`nsogou_keyboard_tips:$sogou_keyboard_tips"
        $zhTips = $zh.inputMethodTips
        $zhTips.add($sogou_keyboard_tips)
        Write-Host "now:zh:$zh"
        Set-WinUserLanguageList -LanguageList $l -Force
    }

}

function set_pinyin_default
{
 
    pwsh5 {
        Set-WinDefaultInputMethodOverride -InputTip '0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA0
                  38EC515D7}'
        Write-Host 'done!'
    }
    
}
function remove_en_us_keyboard
{
    powershell.exe { 
        $l = Get-WinUserLanguageList 
        $en = $l | Where-Object { $_.languageTag -match 'en-us' }
        $enTips = $en.inputMethodTips
        $enus_keyboard = $enTips | Where-Object { $_ -like '*0409:00000409*' }
        Write-Host "sogou:$enus_keyboard"
        $enTips.remove($enus_keyboard)
        Write-Host "now:$en"

        Set-WinUserLanguageList -LanguageList $l -Force }
}
function add_en_us_keyboard
{
    # param ()
    powershell.exe {
        $en_keyboard_tips = '{0409:00000409}'
        $l = Get-WinUserLanguageList
        $en = $l | Where-Object { $_.languageTag -match 'en-us' }
        $enTips = $en.inputMethodTips
        $enTips.add($en_keyboard_tips)
        Write-Host "now:en:$en"
        Set-WinUserLanguageList -LanguageList $l -Force
    }

}

function pushToAndroid
{
    param (
        $path,
        $DestinationPath_opt = "$downloadM"
    )
    adb push $path $DestinationPath_opt
}
function downkyi_clickToLaunch
{

    explorer "$bilibiliDownloader_home"
} 

function remove_colors_icons
{
    param (
    )
    # keep the icons but remove colors except black texts
    <# PS C:\Users\cxxu\Downloads\Compressed> h terminal-icons

    Name                              Category  Module                    Synopsis
    ----                              --------  ------                    --------
    Set-TerminalIconsTheme            Function  Terminal-Icons            Set the Terminal-Icons color or icon theme
    Set-TerminalIconsIcon             Function  Terminal-Icons            Set a specific icon in the current Terminal-Icons icon theme or allows…
    #>
    Set-TerminalIconsTheme -DisableColorTheme
    # Remove-Module Terminal-Icons 
}
function ps_group
{
    Get-Process | Group-Object ProcessName | Sort-Object Name
}





function rpg
{
    Remove-Module posh-git
    Remove-Module oh-my-posh  
}

function ord
{

    param(
        $char
    )
    [byte][char]"$char"
}
function chr
{
    param(
        $ascii_value = 0
    )
    [char][int]"$ascii_value"
}

function upload_pubKey
{
    param(
        $source = "$env:sshPub"
        , 
        $user_host = "cxxu@$AlicloudServerIp"
        ,
        $target = '~/.ssh/authorized_keys'
    )
    scp $source "$user_host`:$target"
}

function BT
{
    Start-Process http://123.56.72.67:8888/d97fbc20
}

function colorPicker_vscode
{
    c $blogs\styles\colorPicker.css 
}

function getAssembler_att
{
    param(
        $fileName
    )
    g++ -S $fileName 
}
function getAssemble_intel
{
    param(
        $fileName
    )
    g++ -S -masm=intel $fileName -o "$($fileName)_intel"       
}

function Start-ProgramInSandboxie
{
    <#
    .SYNOPSIS
    在sandboxie沙盒中启动指定的程序

    .PARAMETER InputObject
    当使用管道传递文件名时，此参数接收从管道中传入的字符串（即文件路径）。

    .PARAMETER Program
    指定要读取的文件路径。当直接通过参数指定文件路径时，使用此参数。

    .EXAMPLE

    #>

    # 使用 CmdletBinding 提供默认参数集、支持 ShouldProcess 等特性
    [CmdletBinding(DefaultParameterSetName = 'Pipe')]

    # 定义函数参数
    # 这里定义了两个参数集:Pipe,Program
    # 通过管道符传递文件名时,激活的时前者,否则用参数传递的,激活的是后者
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'Pipe')]
        [string]$InputObject,


        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Program')]
        [string]$Program
        
    )

    # process 区块：处理从管道或其他方式输入的对象
    process
    {
        # 根据当前激活的参数集获取文件内容
        if ($PSCmdlet.ParameterSetName -eq 'Pipe')
        {
            sandbox_start $InputObject
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Program')
        {
            sandbox_start $Program
        }
       
    }
}
function extract_markdown_titiles
{
    <# 
    .synopsis
    extract markdown titles,configs like 
        1.level
        2.indent char
        3.show title text only 
    are available to specifiy.

    .example
    PS C:\> extract_markdown_titiles .\01_导数和微分.md -level 2 -indent_with_chr '*'
    * 一元函数微分
    ** 函数在$x=x_0$导数的定义
    ** 导函数的定义
    ** 导数与微分@微商
    ** 对数函数的导函数
    ** 函数间四则运算组合函数的求导法则
    ** 反函数求导法则
    ** 对数求导法
    ** 微积分和深度学习
    * 导数表示法&导数记号系统
    ** 莱布尼兹记号法@Leibniz's notation
    ** 拉格朗日记号法@Lagrange's notation
    ** 欧拉记号法@Euler's notation
    ** 牛顿记号Newton's notation


    #>
    param(
        # pass content from pipeline
        # [Parameter(ValueFromPipeline)]
        # [String]
        # $content = 'Noting!',

        $file,
        $level = 3,
        $indent_with_chr = '#',
        # copy result to clipborad
        $scb = $true,
        [switch]$title_only

    )
    process
    {
        # write-host $level
    
        # $pattern = '^(#+)(\s+)(\S+)'
        $pattern = '^(#+)(\s+)(.*)'
        Write-Host $file.Length
        if ($file -ne '')
        {
            $content = Get-Content $file 
            Write-Host 'content from file'
        }
        else
        {
            Write-Host 'contents from clipboard'
        }


        $titles_with_level = $content | Where-Object { $_ -match $pattern } 
        # Remove potential excess spaces as they can affect aesthetics 
        # in titles "##[ ]<title content>",the '[]' indicate the space character width
        $titles_with_level = $titles_with_level -replace $pattern, '$1 $3'

        $titles_leveled = $titles_with_level | ForEach-Object {
            $titles_sharps = $_ -replace $pattern, '$1' 
            # write-host "'$titles_sharps'"
            $title_level = $titles_sharps.Length

            # write-host "$title_level;$_"

            if ($title_level -gt $level)
            {
                return
            }
            else
            {
                # 在管道符中通过write的方式将被遍历的元素添加到数组中
                Write-Host $_

            }
        }

        # write-host $titles_leveled
    
        $titles_with_level = $titles_leveled

        $titles = $titles_with_level | ForEach-Object { $_ -replace $pattern, '$3' }
        $res = ''
        if ($title_only)
        {
            $res = $titles
        }
        elseif ($indent_with_chr -eq '#')
        {
        
            $res = $titles_with_level
        }
        else
        {
            $res = $titles_with_level | ForEach-Object {
                $title_level = ( $_ -replace $pattern, '$1' ).Length
                $_ -replace '^(#+)', ($indent_with_chr * $title_level)
            }
        }
        # 根据需要将内容自动复制到剪切板
        if ($scb)
        {
            $res | Set-Clipboard

        }
        return $res 
    }
    
}

function tree_lsd
{
    param(
        $depth_opt = 3
    )
    lsd --tree --depth $depth_opt
}
function ld
{
    lsd -l --color never
}
function l1
{
    lsd -1
}

function update_functions
{

    <# 
    .SYNOPSIS
    # 刷新Basic的函数集
    #>

    
    # 使用import-module命令导入模块来刷新,由于上下文的问题,必须要在shell中直接调用,函数调用不能达到效果
    # Import-Module Basic -Force
    #事实上,.psm1中有的东西错误会被跳过执行,并且不会报错;而.ps1中的东西如果有错,直接无法运行,例如将函数function关键字写错了,后者报错,前者不报错;而在使用import-Module显式导入 .psm1的模块时,如果模块中有错误代码,就会报错
    
    #>
    
    #psm1模块无法像.ps1一样直接在powershell中运行(虽然可以创建一个硬链接别名后缀该为.ps1),但是仍然有上下文问题
    # . $scripts\PS\Basic\update_functions.ps1

    #不知为何,刷新后提示符样式变为PS,这里考虑用posh手动美化样式
    Write-Host '👺run' -NoNewline
    Write-Host ' Import-Module Basic -Force '-NoNewline -BackgroundColor Green
    Write-Host "manully please!`n"
}




function Set-WindowsUpdate
{
    $path = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows'
    #以下命令为强制写入,使用/f
    reg add $path /v WindowsUpdate /t REG_SZ /d '' /f
    reg add 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' /v AUOptions /t REG_DWORD /d 1 /f 
}

function Get-DateTimeNumber
{
    <# 
    .SYNOPSIS
    获取时间,格式为yyyyMMDDHHmmss (仅包含数字)
    获取时间不是很常用,这里给它标记一下
    #>
    $res = Get-Date -Format 'yyyyMMddHHmmss'
    return $res
}
function Get-DateTime
{
    <# 
    .SYNOPSIS
    返回当前日期和时间,包含年,月,日等文字
    #>
    return (Get-Date -DisplayHint DateTime)
}
function Get-Time
{
    <# 
.DESCRIPTION
    使用SetSecondsToZero参数来设置秒数为0,可以让windows语音播报时间为读出小时和分钟,适用于整点报时脚本
 #>
    [CmdletBinding()]
    param(
        $Format = 'HH:mm:ss',
        [switch]$NoSeconds,
        [switch]$SetSecondsToZero,
        [ValidateSet('yyyyMMddHHmmssfff', 'yyyyMMddHHmmss')]$TimeStap
    )

    Write-Verbose $Format
    # $Format = if ($NoSeconds) { $Format -replace ':ss', '' }
    if ($NoSeconds)
    {

        $Format = ($NoSeconds) ? $Format -replace ':ss', '' : $Format
    }
    elseif ($SetSecondsToZero)
    {

        $Format = $Format -replace ':ss', ':00'
    }
    elseif ($TimeStap)
    {
        $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        return $timestamp
    }
    Write-Verbose $Format
    $Time = Get-Date -Format $Format
    return $Time
    
}

function remote_folder
{
    param(
        $hostname_opt = "$AliCloudServerIP",
        $dir = '/home/cxxu/cppCodes'
    )
    code --folder-uri "vscode-remote://ssh-remote+$hostname_opt$dir"
}
function Get-LineNumberWidth
{
    param (
        $content
    )
    [math]::Max([int][math]::Log10($contents.Count) + 1, 2)
}

function Get-ContentNL
{
    <# 
.SYNOPSIS
该函数用于计数地输出文本内容:在每行的开头显示该行是文本中的第几行(行号),以及该行的内容
支持管道符输入被统计对象
#>
    <# 
.EXAMPLE
#常规用法,通过参数指定文本文件路径来计数地输出文本内容
Get-ContentNL -InputData .\r.txt
.EXAMPLE
rvpa .\r.txt |Get-ContentNL
.EXAMPLE
将一个三行的文本字符串作为管道输入，然后将其,显式指出将管道符内容视为字符串而不是路径字符串进行统计
#创建测试多行字符串变量
$mlstr=@'
line1
line2
line3
'@

$mlstr|Get-ContentNL -AsString

.EXAMPLE
计数一个多行字符串变量的行数
PS C:\repos\scripts\PS\Test> $mlstr=@'
>> line1
>> line2
>> line3
>> '@
PS C:\repos\scripts\PS\Test> $mlstr
line1
line2
line3
PS C:\repos\scripts\PS\Test> Get-ContentNL -InputData $mlstr -AsString
1:line1
2:line2
3:line3
.EXAMPLE
#跟踪文本文件内容的变化(每秒刷新一次内容);
Get-ContentNL -InputData .\log.txt -RepetitionInterval 1
.EXAMPLE
#在powershell新窗口中更新
Start-Process powershell -ArgumentList '-NoExit -Command Get-ContentNL -InputData .\log.txt -RepetitionInterval 1'
.EXAMPLE
ls传递给cat读取合并,然后在传给Get-ContentNL来计数处理

PS> ls ab*.cpp|cat|Get-ContentNL -AsString -Verbose
VERBOSE: Checking contents...
1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:    int a, b, c;
7:    cin >> a >> b;
8:    c = a + b;
9:    cout << c << endl;
10:    return 0;
11:}
12:#include <iostream>
13:using namespace std;
14:int main()
15:{
16:
17:
18:    int a, b, c;
19:    cin >> a >> b >> c;
20:    cout << (a + b) * c << endl;
21:    return 0;
22:}
VERBOSE: 2024/9/14 22:03:43
 
.EXAMPLE
#从ls命令通过管道符传递多个文件进行读取
PS🌙[BAT:79%][MEM:48.16% (15.27/31.71)GB][22:03:52]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\Cpp\stars_printer]
PS> ls ab*.cpp|Get-ContentNL
# Start File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:    int a, b, c;
7:    cin >> a >> b;
8:    c = a + b;
9:    cout << c << endl;
10:    return 0;
11:}

# End File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

# Start File(2) [C:\repos\scripts\Cpp\stars_printer\abc.cpp]:

1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:
7:    int a, b, c;
8:    cin >> a >> b >> c;
9:    cout << (a + b) * c << endl;
10:    return 0;
11:}

# End File(2) [C:\repos\scripts\Cpp\stars_printer\abc.cpp]:

.EXAMPLE
通过get-item命令(别名gi)获取字符串对应的文件
PS🌙[BAT:79%][MEM:48.52% (15.39/31.71)GB][22:04:07]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\Cpp\stars_printer]
PS> gi .\ab.cpp|Get-ContentNL
# Start File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:    int a, b, c;
7:    cin >> a >> b;
8:    c = a + b;
9:    cout << c << endl;
10:    return 0;
11:}

# End File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

.Notes
可以设置别名,比如pscatn,psnl
#>
    [CmdletBinding()]
    param(
        # 可以是一个表示文件路径的字符串，也可以是一个需要被统计行数并显示内容的字符串;后者需要追加 -AsString 选项
        [Parameter(
            Mandatory = $false, #这里如果使用这个参数的话，必须要指定非空值,为了增强兼容性,不适用改参数,或者指定为$false
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        # [string]
        [Alias('InputObject')]$InputData,
        
        # [Parameter(ParameterSetName = 'FilePath')]
        # [switch]$AsFilePath,

        # [Parameter(ParameterSetName = 'String')]
        [switch]$AsString,
        # 定时刷新查看文件内容的间隔时间（秒）,0表示一次性查看
        $RepetitionInterval = 0,
        [switch]$Clear,
        $LineSeparator = '#'
        # [switch]$NewShell #todo

    )

    begin
    {
        Write-Verbose 'Checking contents...'
        $itemNumber = 1
        $lineNumber = 0 #为了支持列表输入,对多个文件分别计数,此变量放到process块中
    }

    process
    {
        
        
        if ($AsString)
        # if ($PSCmdlet.ParameterSetName -eq 'String')
        {
            # 如果是字符串，则认为是直接传入的文件内容
            $InputData -split "`n" | ForEach-Object {
                $lineNumber++
                "${lineNumber}:$_"
            }
        }
        else
        {
            # 否则，认为是文件路径,但是还是要检查文件是否存在或者合法
            if (!(Test-Path $InputData -PathType Leaf))
            {
                Write-Error "File does not exist:$($InputData.Trim()) Do you want to consider the Input as a string?(use -AsString option ) "
                return
            }
            $lineNumber = 0

            Write-Host "$LineSeparator Start File($itemNumber) [$_]" -BackgroundColor Yellow -NoNewline
            Write-Host "`n"
            
            try
            {
                if (Test-Path $InputData -PathType Leaf)
                {
                    Get-Content $InputData | ForEach-Object {
                        $lineNumber++
                        "${lineNumber}:$_"
                    }
                }
                else
                {
                    Write-Error "File does not exist: $InputData"
                }
            }
            catch
            {
                Write-Error "An error occurred: $_"
            }

            Write-Host ''
            Write-Host "$LineSeparator End File($itemNumber) [$_]:"-BackgroundColor Blue -NoNewline
            Write-Host "`n"
            $itemNumber++

        }
        # 定时刷新查看指定文件内容
        if ($RepetitionInterval)
        {
            
            while (1)
            {
                # 清空屏幕(上一轮的内容会被覆盖)
                if ($Clear) { Clear-Host }

                # 这里使用递归调用(并且将此处调用的RepetitionInterval指定为不刷新(0),否则嵌套停不下来了)
                Get-ContentNL -InputData $InputData -RepetitionInterval 0
                # 也可以简单使用 
                # Get-Content $InputData
                Start-Sleep $RepetitionInterval
            }

        }
     

    }
    end
    {
        Write-Verbose (Get-DateTime)
    }
}

function Open-AllFiles
{
    <# 
    .synopsis
    open all file that exist in the current directory with default program 
    #>
    # --------------
    <#     if (Test-Path ./Open-AllFilesFiles.ps1)
    {
        Remove-Item Open-AllFilesFiles.ps1 -V
    }
    Get-ChildItem -File | ForEach-Object { ".`/" + $_.Name>>Open-AllFilesFiles.ps1 }
    ./Open-AllFilesFiles.ps1
    write-host 'end the Open-AllFiles script running'
    # 删除临时脚本:
    Remove-Item ./Open-AllFilesFiles.ps1 #>

    # ----------------------

    Get-ChildItem -File | ForEach-Object { Write-Host $_; & $_ }
}

function New-Junction
{
    param(
        $Path,
        [alias('Destination')]$Target
    )
    # Write-Host 'if failed(access Denied), please run the terminal with administor permission.(考虑到部署的门槛，scoope未必可用，您需要手动打开带有管理员权限的terminal进行操作（而不在这里使用sudo;这里提供了参数，您可以传入sudo选项）'
    if (Test-Path $path)
    {
        Write-Host 'removing the existing dir/symbolicLink!'
        Remove-Item -Force -Verbose $path 
        # timer_tips
    }
    if (!(Test-Path $Target))
    {
        Write-Host 'target does not exist!'
        New-Item -ItemType Directory -Force -Verbose $Target
    }

    New-Item -Verbose -Force -ItemType junction -Path $Path -Target (Resolve-Path $Target)
    
}
function Get-BatteryLevel
{
    # get battery charge:
    $charge = Get-CimInstance -ClassName Win32_Battery | Select-Object -ExpandProperty EstimatedChargeRemaining
    return $charge
    # "Current Charge:[ $charge %]."
    # -replace '.*\[(.*)\].*', '$1'
}
function u20
{
    ssh cxxu@u20
}

function vscodeExtListExport
{
    param(
        $fileName = "vscode_list_extt$(Get-Date)"
    )
    code --list-extensions >> $fileName
}
function Get-WslInfo
{
    wsl -l -v
    Write-Host '参考内容:https://blog.csdn.net/xuchaoxin1375/article/details/112004891?ops_request_misc=%257B%2522request%255Fid%2522%253A%2522166341800516782425199224%2522%252C%2522scm%2522%253A%252220140713.130102334.pc%255Fblog.%2522%257D&request_id=166341800516782425199224&biz_id=0&utm_medium=distribute.pc_search_result.none-task-blog-2~blog~first_rank_ecpm_v1~rank_v31_ecpm-1-112004891-null-null.nonecase&utm_term=wsl2&spm=1018.2226.3001.4450'
}


function https3w_start
{
    param(
        $domain
    )
    Start-Process $domain
}

function Get-EdgeUpdaterPath
{
    <# 
    .SYNOPSIS
    获取edge update的路径并返回,通常不会直接调用,而是由Set-EdgeUpdater调用
    #>
    # 以管理员权限打开一个shell窗口,保证防火墙能够顺利配置
    # 创建一个正则表达式对象
    $path_raw = 'reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\edgeupdate /v ImagePath' | Invoke-Expression
    $regex = [regex] '"(.*)"'
    # 对字符串执行匹配并获取所有匹配项
    $all_matches = $regex.Matches($path_raw)
    $edge_updater_path = $all_matches[-1].Value -replace '"', ''

    return $edge_updater_path
    #通常这个路径是:"C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"

}
function Set-EdgeUpdater
{
    <# 
    .SYNOPSIS
    设置edge update是否启用(通过配置防火墙实现)

    .EXAMPLE
    PS>set-EdgeUpdater -Disable

    Rule Name:                            Disable Edge Updates
    ----------------------------------------------------------------------
    Enabled:                              Yes
    Direction:                            Out
    Profiles:                             Domain,Private,Public
    Grouping:
    LocalIP:                              Any
    RemoteIP:                             Any
    Protocol:                             Any
    Edge traversal:                       No
    Action:                               Block
    Ok.

    there is already a rule of disable edge update,enable it...

    Updated 1 rule(s).
    Ok.


    Rule Name:                            Disable Edge Updates
    ----------------------------------------------------------------------
    Enabled:                              Yes
    Direction:                            Out
    Profiles:                             Domain,Private,Public
    Grouping:
    LocalIP:                              Any
    RemoteIP:                             Any
    Protocol:                             Any
    Edge traversal:                       No
    Action:                               Block
    Ok.
    #>
    param(
        [switch]$Enable,
        [switch]$Disable
    )
    $deu = 'Disable Edge Updates'
    if ($Enable)
    {
        #将禁止edge update的规则禁用,就是恢复edge update
        netsh advfirewall firewall set rule name=$deu new enable=no

    }
    elseif ($Disable)
    {
        #方案1:删除防火墙规则(比较简单的做法)
        # netsh advfirewall firewall delete rule name=$deu
        # 方案2:禁用防火墙规则(为了避免反复配置相同的规则,需要一定的判断逻辑,更加安全)
        netsh advfirewall firewall show rule name=$deu
        if ($?)
        {
            Write-Host 'there is already a rule of disable edge update,enable it...'
            netsh advfirewall firewall set rule name=$deu new enable=yes
        }
        else
        {

            Write-Host 'create a new rule of disable edge update...'
            $edge_updater_path = Get-EdgeUpdaterPath
            #修改防火墙需要管理员权限,因此在此操作之前,以管理员权限打开一个shell窗口(如果已经处于管理员窗口,则直接执行下面的语句)
            netsh advfirewall firewall add rule name=$deu dir=out action=block program=$edge_updater_path
        }
    }
    # 配置完检查结果
    netsh advfirewall firewall show rule name=$deu
}


# if ( ( Get-Location | Resolve-Path).ToString() -eq "django" )
function HibernateComputer
{
    param (
        
    )
    Shutdown /h
}
function Stop-ComputerInquery
{
    Write-Host 'the pc will be shutdown '
    # in 3 senconds'
    # write-host '❤️⛔control+c to stop the behaviour...'
    # timer_tips 3
    $Inquery = Read-Host -Prompt ' input y key to continue shutdown!(prevent the unexpected shutdown) '
    if ($Inquery -eq 'y')
    {
        Shutdown /p
    }
}
function SleepComputer
{
    Push-ReposesConfiged 
    rundll32.exe powrprof.dll, SetSuspendState 0, 1, 0
}
function LockScreen
{
    Push-ReposesConfiged 
    rundll32.exe user32.dll, LockWorkStation
}
function shutdown_timer1
{
    <# 
    .SYNOPSIS
    在给定时间内关机,假设以5秒为例,默认5秒
    5秒内可以输入y来继续立即关机,也可以输入n取消关机
    如果没有任何操作,时间到达5秒后自动关机

    函数的缺点是无法通过调用指定倒计时时间,因为start-job实现的函数,无法传递给start-job scriptblock
    如果需要修改,请编辑函数代码,将$timer出现的2个位置都替换为需要的值
    #>
    param(
        $timier = 5 #无法传递给start-job scriptblock,这个参数其实不太有用
    )
    # $log = "$home\shutdown_log.txt"
    # 创建后台作业来处理用户输入
    $job = Start-Job -ScriptBlock {
        # 可以使用日志文件的方式记录$job的运行过程和结果
        # $log = 'c:\users\cxxu\shutdown_log.txt'
        # '准备关机' >> $log
        # Start-Sleep $scriptblock中无法继承shell变量,外部变量$Timier 无法识别,这里睡眠时间要硬编码
        
        $timer = 5 ; #赋值给变量timer
        Start-Sleep $timer
   
        #关机
        Stop-Computer 

    }
    $result = Read-Host 'Do you want to shutdown the computer now? (y/n)' "`n You have $Timier seconds to cancel"

    # 获取作业的结果
    # $result = Receive-Job -Job $job -Wait

    # 根据用户的选择进行处理
    if ($result -eq 'y')
    {
        # 用户选择了'y'，执行关机
        # 'User press [y],Shutting down...' | Tee-Object -Append $log
        Start-Sleep -Seconds 0.5
        
        Stop-Computer  # 实际执行关机时取消注释这行
    }
    elseif ($result -eq 'n')
    {
        # 用户选择了'n'，取消关机
        # 'User press [n],Shutdown cancelled.' | Tee-Object -Append $log
        
        # 清理作业
        Remove-Job -Job $job -Force
    }

}

function shutdown_timer2
{
    <# 
    .SYNOPSIS
    默认5秒后关机,5秒内可以反悔取消关机(按下Ctrl+C取消关机)
    无法提前关机,只能在5秒后触发关机
    #>
    param(
        $Timier = 5 
    )

    Write-Host "You have $Timier seconds to cancel(press Ctrl+C to cancel)" -BackgroundColor Yellow
    Write-Host 'Please ensure all tasks have been saved!' -BackgroundColor Cyan
    timer_tips $Timier
    Write-Host 'shutting down!'
    Start-Sleep 1
    Stop-Computer
    # 打印作业返回的结果

}
# 调用函数测试
# Shutdown-Computer
function Stop-ComputerAfterSyncActions
{
    param(
        [switch]$Force
    )
    # 将笔记和脚本配置上传到云端
    Push-ReposesConfigedFromMainPC
    # 关闭电脑
    Start-Sleep 1.5
    # 尝试关机(普通模式下如果有其他用户登录到该计算机,则无法关机)
    #如果要强制关机，则使用Force选项
    
    if ($Force)
    {
        Write-Host 'shutting down Forcely!'
        Start-Sleep 1.5
        Stop-Computer -Force
    }
    Start-Sleep 1.5
    Stop-Computer
}
function Test-MainPC
{
    <# 
    .SYNOPSIS
    return whether the current Pc is the main PC or not.
    #>
    return (Get-MatherBoardInfo).SerialNumber -eq $PC1

}

function Push-ReposesConfiged
{
    <# 
    .SYNOPSIS
    将常用仓库,比如笔记和脚本配置上传到云端

    .DESCRIPTION
    仓库依赖于powershell环境变量,可以在这里做一次导入判断处理
    本函数一般不会直接调用,而是配合其他函数调用
    #>
    [CmdletBinding()]
    param(
        $repoDirs = ""

        # $repoDirs = $CommonRepos,
        # $CxxuRepos = $CxxuRepos,
        # $CxxuComputers = $CxxuComputers
    )
    #记录当前路径
    Push-Location
    # 将相关配置变量导入到当前shell中
    Update-PwshEnvIfNotYet -Mode Vars
    # 执行仓库目录处理
    if(!$repoDirs)
    {
        $repoDirs = $CommonRepos + $CxxuRepos
        # Write-Verbose $repoDirs
        Write-Verbose $repoDirs.GetEnumerator() -Verbose
    }

    #如果是主PC,则执行云端同步操作(push)
    Write-Host 'try to push the reposes...' -BackgroundColor Yellow
    # 获取repos目录下所有子目录路径
    # $repoDirs = Get-ChildItem -Path $repos -Directory
    # if(Test-CxxuComputer)
    # {
    #     $repoDirs += $CxxuRepos
    # }

    # $repoDirs #指定配置需要同步的仓库目录
  
    # git 不支持多线程并行,所以只能够串行(用不上-parallel参数)
    foreach ($repoDir in $repoDirs)
    {
        # 切换到当前仓库目录
        $p = "$repos\$repoDir"
        Set-Location -Path $p
        Write-Host $P -ForegroundColor Magenta
        # 执行任务
        if (Test-Path -Path '.git')
        {
            # 每次对单个仓库执行更新操作
            gitUpdateReposSimply
        }
        Write-SeparatorLine

        # Get-Location
        # Get-ChildItem | Select-Object -First 3

        # 可选：恢复至原始工作目录，如果你希望脚本执行完毕后回到原始目录
        # Pop-Location
    }

    # 恢复当前路径
    Pop-Location
    # Set-Location $home/desktop
    Write-Verbose "current location is:$(Get-Location)"
    # 如果不需要Pop-Location，这里可以添加注释掉的部分，以便始终回到脚本初始目录
    #Push-Location $initialLocation

}
function Push-ReposesConfigedFromMainPC
{   
    Update-PwshEnvIfNotYet -Mode Vars

    # 检查环境,如果没有则导入环境变量,则导入,否则无法准确判断当前主机是否为主PC
    if (!(Test-MainPC))
    {
        # 如果不是MainPC,则不需要执行同步操作,防止辅PC的版本污染
        Write-Host 'This is not MainPC, do nothing...' -BackgroundColor Yellow
        return $False
    }

    Push-ReposesConfiged
}
function New-File
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (Test-Path $Path)
    {
        # 文件已存在，更新最后写入时间
        (Get-Item $Path).LastWriteTime = Get-Date
    }
    else
    {
        # 文件不存在，创建文件
        New-Item -ItemType File -Path $Path | Out-Null
    }
}
function Set-DoubleOwnerOfRepos
{
    param (
        
    )
    $reps = @('configs', 'blogs', 'scripts')
    
    foreach ($rep in $reps)
    {

        git config --global --add safe.directory "D:/repos/$rep"
    }
    
}
function Test-CxxuComputer
{
    <# 
    .SYNOPSIS
    测试当前机器是否为Cxxu所属或使用的设备
    #>
    param (
        $CxxuComputers = $CxxuComputers
    )
    Update-PwshvarsIfNotYet
    # Update-PwshEnvIfNotYet
    return $env:COMPUTERNAME -in @($CxxuComputers)

    
}

function Update-ReposesConfiged
{
    <# 
    .SYNOPSIS
    从远程仓库拉取最新的配置覆盖本地版本
    .DESCRIPTION
    如果本地在$repos目录下，那么会从gitee clone到$repos目录中

    #>
    [CmdletBinding()]
    param(
        # $repoDirs = '',
        $repoDirs = $CommonRepos,
        $CxxuRepos = $CxxuRepos,
        # 默认读取GlobalConfig中的配置,也可以通过命令行覆盖这个列表(传入$env:ComputerName就可以临时地获取拉取CxxuRepos仓库的权限)
        $CxxuComputers = $CxxuComputers,
        [switch]$Force
    )
    #记录当前路径
    Push-Location

    # 导入环境变量(当前么有导入过),以便本函数确定默认值,即哪些仓库需要同步
    Update-PwshEnvIfNotYet -Mode Vars
    $repoDirs = ($reposDirs) ? $repoDirs : $CommonRepos
    
    Write-Verbose "$repoDirs will be try to update." -Verbose
    # 获取repos目录下所有子目录路径
    # $repoDirs = Get-ChildItem -Path $repos -Directory
    
    $repoDirs = $CommonRepos
    if(Test-CxxuComputer)
    {
        $repoDirs += $CxxuRepos
    }

    foreach ($repoDir in $repoDirs)
    {

        $P = Join-Path -Path $repos -ChildPath $repoDir
        # Set-Location $repos
        Write-Verbose $P
        if (!(Test-Path $P))
        {
            $gitUrl = "$gitee_xuchaoxin1375/$repoDir" #.Trim('\\')
            $Path = "$repos\$repoDir"
            Write-Verbose "[$giturl] will be cloned to [$Path] !" -Verbose
            git clone $gitUrl $Path 
            continue

        }
        # 切换到当前仓库目录
        Set-Location -Path "$repos\$repoDir"
        Write-Host "$repos\$repoDir" 

        # 执行任务
        if (Test-Path -Path '.git')
        {
            # 如果副设备上的仓库被污染，执行清空,然后强制拉取
            # 假设每个仓库的主分支为main(而不是master或其他)
            # git fetch origin
            if ($Force)
            {

                git reset --hard origin/main
            }
            git pull origin main
            # 上述命令对于不会引起冲突的文件或目录不造成影响,只有和云端仓库冲突的文件或目录才会被移除更改
            # 如果想要完全一样,那么执行以下清理命令(清除未跟踪的文件或目录)
            # git clean -fd

            Write-Host "$reposDir was try to updated." -ForegroundColor Cyan
    
        }

    }

    # 恢复当前路径
    Pop-Location
    # Set-Location $home/desktop
    Write-Verbose "current location is:$(Get-Location)"

    #启动新的powershell窗口,使得新的配置生效
    # Start-Process pwsh
}
function reboot
{
    param(
        $timeOut = 0
    )
    # cmd中可以利用shutdown /r重启,/t指定倒计时时间
    # Shutdown /r /t $timeOut
    Restart-Computer
}


function timer_tips
{
    param(

        $i = 5
    )
    while ($i--)
    {
        Start-Sleep -Seconds 1
        Write-Host ($i + 1)

    }
}

function Test-AdminPermission
{
    <#
.SYNOPSIS
    Determines whether the current user has administrative privileges.
    This is a very useful function to prevent misleading error messages casued by a permission insufficiency.

    many actions need admin permission to run,with the common permission it will be failed.In ideail cases,the command return a 'Permission denied' error message,but some other will return other errors which is not cleared as 'Permission denied',Such as :`Set-Acl: Some or all identity references could not be translated.`
    That's not good for us to judge why the action of the command failed.

    so if you now certain function need admin permission, you can use this function to check to exclude many unnecessary error messages.

.DESCRIPTION
    This function uses the [Security.Principal.WindowsIdentity] class to check
    whether the user belongs to the Administrators group. It returns $true if the
    user is a member of the Administrators group and $false otherwise.

.EXAMPLE
    Test-AdminPermission

    This example calls the Test-AdminPermission function and displays the
    result.

.INPUTS
    None. This function does not accept any input.

.OUTPUTS
    System.Boolean

    This function returns a boolean value. If the user is a member of the
    Administrators group, the function returns $true; otherwise, it returns
    $false.
#>

    if (!([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544'))
    {
        
        return $false
    }
    return $true
}

function Test-AdminPermission2
{
    param (
    )
    if ( ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    {
        return $true
    }
    else
    {
        return $false
    }
    
}

function Disable-CredentialGuard 
{

    # 配置注册表以禁用 Credential Guard
    # 确保以管理员权限运行PowerShell
    if (-not(Test-AdminPermission))
    {
        Write-Warning '请以管理员身份运行此脚本。'
        Exit
    }

    # 设置注册表项以禁用Credential Guard相关设置

    # 第一个注册表路径和值
    $regPath1 = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $regName1 = 'LsaCfgFlags'
    $regValue1 = 0

    # 第二个注册表路径和值
    $regPath2 = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    $regName2 = 'LsaCfgFlags'
    $regValue2 = 0

    # 设置第一个注册表项
    New-ItemProperty -Path $regPath1 -Name $regName1 -Value $regValue1 -PropertyType DWord -Force 

    foreach ($p in @($regPath1, $regPath2))
    {

        # 设置第二个注册表项
        if (-not (Test-Path $p))
        {
            New-Item -Path $p -Force 
        }
    }

    New-ItemProperty -Path $regPath2 -Name $regName2 -Value $regValue2 -PropertyType DWord -Force 

    Write-Host '注册表项已设置完成。'
    Write-Host '请重启计算机以使更改生效。'
}

function Set-HostsFile
{
    Write-Host 'entering administrator mode...'
    Write-Host 'try to open hosts file(by vscode...)'
    # Get-AdministratorPrivilege
    sudo c $hosts
}

function NetWorkAccessbility
{
    curl_b -v $baidu
}
function curlBD
{
    curl_b $baidu
}
function pingBD
{
    param (

        $site = $baidu
    )
    ping $site
}
function pingGG
{
    param (
        $domain = $google
    )
    Write-Host $domain
    ping $domain
}
function uploadPic
{
    param (
        $path = ' '
    )
    if ($path -eq ' ')
    {
        Write-Host 'try to upload pictures from clipboard(the default behaviour)'
    }
    $resLink = picgo upload $path | Select-Object -Last 1 
    Set-Clipboard $resLink
    Write-Host "🎶🎶🎶`n$resLink"
}
function jupyter2markdown
{
    param(
        $jupyter_file = './*ipynb',
        $format = 'markdown'
    )
    jupyter nbconvert $jupyter_file --to markdown
}
function uploadPicMarkdown
{
    param (
        $path = ' '
    )
    if ($path -eq ' ')
    {
        Write-Host 'try to upload pictures from clipboard(the default behaviour)'
    }
    $resLink = picgo upload $path | Select-Object -Last 1 
    # Set-Clipboard $resLink
    $markdownPicLink = "![🥰$(Get-Date)]($resLink)"
    Write-Host $markdownPicLink
    Set-Clipboard $markdownPicLink
    Write-Host "🎶🎶🎶`n$resLink"
}
function Write-SeparatorLine
{
    param (
        $borderUnit = '-~',
        $timesOfRepeat = 30
    )
    # $border = ''
    $border = $borderUnit * $timesOfRepeat
    <#     # write-host 50*$borderUnit
    # for ($i = 0; $i -lt $timesOfRepeat; $i++)
    # {
    #     # $border = $border + $borderUnit
    #     $border += $borderUnit
    # } #>
    # write-host $border
    # return语句也会自动打印出来
    return $border
}
#----------------------------
# Write-SeparatorLine > 5
function gcmw
{
    param (
        $pattern
    )
    $wildcardPattern = "*$pattern*"
    Write-Host "🥰result returned by gcm wildcard:$wildcardPattern"
    Write-SeparatorLine
    Get-Command $wildcardPattern
    # write-host "🥰result returned by help"
    Write-SeparatorLine
    # Get-Help $wildcardPattern
    # help $Pattern |Format-Table |write-host

}
# gcmw screen
function mvToNEEPSub
{
    param (
        $obj,
        $desBase
    )
    $des = "$env:Neep`\$desBase"

    Move-Item $obj $des
    Write-Host "displayed:$des = $env:Neep`\$desBase"
}
function clock
{
    node $scripts\jsScripts\clock.js
}
function javav
{
    java -version
}



function EnvironmentRequireTips
{
    Write-Host "💕you are try to run the python script; `n 💕if it does not work, please check the [`py`] command to check the python enviroment to locate the exceptions."
}



function renamePrefix
{
    param (
        $dirName
    )
    EnvironmentRequireTips
    py $scripts\pythonScripts\rename_prefix.py $dirName
}




function search_contents
{
    param(
        #选择需要扫描的目录路径,默认为当前路径
        $path = '.',
        $content_pattern = 'text',
        $file_pattern = '*',
        #使用groupby进行分组(每个文件在匹配到的所有行及其行数统计,所有存在被匹配行的文件总数统计),并将分组结果输出为表格,支持进一步排序
        [switch]$TableViewGroup
    )
    $res = Get-ChildItem -Path $path -R -File -FollowSymlink $file_pattern | Select-String -Pattern $content_pattern
    $sum = $($res | Group-Object -Property Filename).Count
    if ($TableViewGroup)
    {
        $res = $res | Select-Object Filename, LineNumber, Line | Group-Object -Property Filename 
        $res = $res | Format-Table -AutoSize
    }
    Write-Host $res
    Write-Host args: -ForegroundColor DarkMagenta -BackgroundColor Cyan
    $params = "
        path = $path,
        content_pattern = $content_pattern,
        file_pattern = $file_pattern,
        TableViewGroup=$TableViewGroup"
    Write-Host $params -ForegroundColor Yellow

    Write-Host "Total files matched pattern_contents:$sum" -ForegroundColor 'Blue' #-BackgroundColor Yellow

    <# 
    .SYNOPSIS
    扫描指定目录下所有包含特定内容的文件，输出文件名，行号，行内容
    支持切换为分组显示,并将分组结果输出为表格
    .EXAMPLE
    PS 🕰️1:24:27 AM [C:\repos\scripts\testDir] 🔋100%→search_contents  -content_pattern tex

    f1:1:text2
    f1:2:text3
    f1:3:text abc
    f2:1:!text abc
    dir_test\f4:1:text x abc
    args:

            path = .,
            content_pattern = tex,
            file_pattern = *,
            TableViewGroup=False
    Total files matched pattern_contents:4
    .EXAMPLE
    PS 🕰️1:24:29 AM [C:\repos\scripts\testDir] 🔋100%→search_contents  -content_pattern tex -TableViewGroup

    Count Name     Group
    ----- ----     -----
        3 f1       {@{Filename=f1; LineNumber=1; Line=text2}, @{Filename=f1; LineNumber=2; Line=text3}, @{Filename=f1; Lin…
        1 f2       {@{Filename=f2; LineNumber=1; Line=!text abc}}
        1 f4       {@{Filename=f4; LineNumber=1; Line=text x abc}}

    args:

            path = .,
            content_pattern = tex,
            file_pattern = *,
            TableViewGroup=True
    Total files matched pattern_contents:4
    #>
    
}

function aliasEdit
{
    param(
        #[functions,shortcuts]
        $type = 'shortcuts'
    )
    vim $aliases\shortcuts
}







# testing.
function mkdirSafeCd
{
    param(
        $DirectoryName

    )
    if ( Test-Path $DirectoryName)
    {
        Write-Host "directory already exist, now Set-Location to the directory:$DirectoryName"
        Set-Location $DirectoryName
    }
    else
    {
        New-Item -ItemType Directory $DirectoryName
        Set-Location $DirectoryName
    }
}
function Get-IPAddressMainInfo
{
    <# 
    .SYNOPSIS
    按网卡分组列出计算机上的IP地址,一般一个网卡上有一个ipv4地址和一个ipv6地址,但可能更多
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-NetIPAddress |group -Property InterfaceAlias|sort Name

    Count Name                      Group
    ----- ----                      -----
        2 Bluetooth Network Connec… {fe80::6692:33af:a97a:fe2%7, 169.254.134.242}
        2 Ethernet                  {fe80::88bf:2fcf:a049:335c%22, 169.254.21.122}
        2 Local Area Connection* 1  {fe80::5006:155d:e384:f3e2%6, 169.254.136.6}
        2 Local Area Connection* 2  {fe80::4569:8dca:ec45:64c0%17, 192.168.137.1}
        2 Loopback Pseudo-Interfac… {::1, 127.0.0.1}
        2 Tailscale                 {fe80::2f4c:2c3e:13e9:1c81%5, 169.254.83.107}
        2 vEthernet (Default Switc… {fe80::2783:ed62:4b9a:c308%24, 172.27.176.1}
        2 VMware Network Adapter V… {fe80::c538:5a79:d7bf:35de%4, 192.168.174.1}
        2 VMware Network Adapter V… {fe80::6a9a:3215:bace:cd81%20, 192.168.37.1}
        4 Wi-Fi                     {fe80::602a:eb89:bc9c:22bf%3, 240e:379:3fa1:100:a548:a4e1:78ca:27d0, 240e:379:3fa1:100:38d1:ed54:77d5:9710, 192.168.1.178}
    #>
    Get-NetIPAddress | Group-Object -Property InterfaceAlias | Sort-Object Name
}

function Get-IPAddressOfPhysicalAdapter
{
    <#
    .SYNOPSIS
    列出计算机上的物理网络适配器的IP地址(包括传统的Ethernet和Wi-Fi网络适配器)
    .DESCRIPTION
    中英文系统下两类适配器的名字有所不同,ethernet对应以太网,而wi-fi对应WLAN
    通常一台笔记本至少有一个网络适配器,如果是轻薄本可能只有一个无线网络适配器,如果有2个适配器,那么他们也可以同时联网
    但是一般只有其中的一个可以进行网络传输,另一个几乎闲着(例如windows,优先使用跃点数少的那一条网卡线路,而不是连接速率最快的那一条)
    调节跃点数可能可以均衡连个网卡;
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-IPAddressOfPhysicalAdapter -AddressFamily IPv4

    InterfaceAlias IPAddress
    -------------- ---------
    Ethernet       169.254.21.122
    Wi-Fi          192.168.1.178

    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-IPAddressOfPhysicalAdapter -AddressFamily IPv6

    InterfaceAlias IPAddress
    -------------- ---------
    Ethernet       fe80::88bf:2fcf:a049:335c%22
    Wi-Fi          fe80::602a:eb89:bc9c:22bf%3
    Wi-Fi          240e:379:3fa1:100:a548:a4e1:78ca:27d0
    Wi-Fi          240e:379:3fa1:100:38d1:ed54:77d5:9710
    #>
    param(
        [validateset('IPv4', 'IPv6')]$AddressFamily = 'IPv4'
    )
    foreach ($name in @('ethernet', 'wi-fi', 'WLAN', '以太网'))
    {
        Get-NetIPAddress -InterfaceAlias $name -AddressFamily $AddressFamily `
            -ErrorAction SilentlyContinue  
        | Select-Object InterfaceAlias, IPAddress
    }
}
function Get-NetAdapterMainInfo
{
    <# 
    .SYNOPSIS
    获取当前计算机上的网卡的主要信息
    .DESCRIPTION
    您或许想要排序,这没问题,只需要后面用管道符号|引入Sort 命令即可

    .EXAMPLE
    
    PS C:\repos\scripts> Get-NetAdapterMainInfo|Sort-Object status -Descending

    Name                          InterfaceDescription                       MacAddress        Status
    ----                          --------------------                       ----------        ------
    Local Area Connection* 2      Microsoft Wi-Fi Direct Virtual Adapter #2  32-F6-EF-07-2E-61 Up
    Tailscale                     Tailscale Tunnel                                             Up
    VMware Network Adapter VMnet1 VMware Virtual Ethernet Adapter for VMnet1 00-50-56-C0-00-01 Up
    VMware Network Adapter VMnet8 VMware Virtual Ethernet Adapter for VMnet8 00-50-56-C0-00-08 Up
    Wi-Fi                         Intel(R) Wi-Fi 6E AX211 160MHz             30-F6-EF-07-2E-61 Up
    Bluetooth Network Connection  Bluetooth Device (Personal Area Network)   30-F6-EF-07-2E-65 Disconnected
    Ethernet                      Realtek PCIe GbE Family Controller         D4-93-90-34-16-69 Disconnected
    #>
    Get-NetAdapter | Select-Object Name, InterfaceDescription, MacAddress, Status | Sort-Object name
}
function Restart-Explorer
{
    param (
        
    )
    # for powershell ,to restart the explorer just need a cmdlet(more simple than command in cmd like bellow.)
    Stop-Process -Name explorer 
    # taskkill /f /im explorer.exe 
    # Start-Process explorer.exe
}


function Restart-Process
{
   
    <#
.SYNOPSIS
    重启指定的进程。指定参数的形式类似于stop-process,支持管道符
    为了简单起见,没有实现想Get-process 那样tab键自动补全进程名的功能

.DESCRIPTION
    该函数用于重启指定的进程。它可以根据进程的名称、ID 或直接传递的进程对象来停止和重新启动进程。
    特别适用于需要重启 Windows 资源管理器 (explorer.exe) 的情况。
    
.PARAMETER Name
    要重启的进程的名称（不包括扩展名）。例如：'explorer'。

.PARAMETER Id
    要重启的进程的 ID。

.PARAMETER InputObject
    要重启的进程对象。

.EXAMPLE
    Restart-Process -Name 'explorer'
    该示例将重启 Windows 资源管理器。

.EXAMPLE
    Restart-Process -Id 1234
    该示例将重启进程 ID 为 1234 的进程。

.EXAMPLE
    Get-Process -Name 'explorer' | Restart-Process
    该示例将重启通过管道传递的进程对象。

.NOTES
    作者: cxxu1375
#>

    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param (
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0, HelpMessage = 'Enter the name of the process to restart.')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0, HelpMessage = 'Enter the ID of the process to restart.')]
        [int]$Id,

        [Parameter(ParameterSetName = 'ByInputObject', Mandatory = $true, ValueFromPipeline = $true, HelpMessage = 'Enter the process object to restart.')]
        $InputObject
    )
    
    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'ByName')
            {
                # 通过名称获取进程对象
                $process = Get-Process -Name $Name -ErrorAction Stop
              
                
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ById')
            {
                # 通过ID获取进程
                $process = Get-Process -Id $Id -ErrorAction Stop
               
                
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ByInputObject')
            {
                $process = $InputObject
                
            }
            # 获取第一个进程(同一个软件可能创建了多个进程,或者说多个进程可能有共同的ProcessName,这里从中选出一个进程对象)
            $fp = $process[0]
            Write-Verbose $fp
            # 获取进程对应软件的路径
            $s = $fp.Path
            Write-Verbose "Performing the operation `"restart-process`" on target `"$process`" "
            Write-Debug "Process path: $s"
            
            # 重启软件进程:先关闭目标进程,然后根据先前获取的目标进程对应的软件的路径,来启动目标进程
            Stop-Process $process -Verbose:$VerbosePreference 
            Start-Process -FilePath $s -Verbose:$VerbosePreference
        }
        catch
        {
            Write-Error "Failed to restart process. $_"
        }
    }
}

# 调用函数重启进程
# Restart-Process -ProcessName $Name

function pipUpdateIntegration
{
    param (
        
    )
    python -m pip install --upgrade pip
}


# testing...
function c
{
    <# use vscode open specified dir or file #>
    param(
        $dirName = '.'
    )
    # code_pwsh $dirName 
    code $dirName
    # --proxy-pac-url=http://127.0.0.1:1083/proxy.pac
}

function code_proxy
{
    $dirName = '.'
    code $dirName --proxy-pac-url=http://127.0.0.1:1083/proxy.pac
}
# function cdb{
#     cd -
# }



# function predict {
#     Set-PSReadLineOption -PredictionSource History # 设置预测文本来源为历史记A
# }
function Get-ScriptRootPath
{
    <# .synopsis
    获取当前脚本所在的绝对路径 
    #>
    Resolve-Path $PSScriptRoot
}


function status { git status }
function time_show
{
    param (
        
    )
    EnvironmentRequireTips    
    py $scripts\pythonscripts\timer.py
}


function Write-WorkingDir
{
    param(
        $path = './'
    )
    Write-Host "`t 📁❤️function working on dir: $((Resolve-Path $path))..."
    Write-SeparatorLine '..'
}



#(please note that the function name can't not have a same name with a certain Alias).

<# start comman software by name #>


function btm_cxxu
{
    btm --color nord-light
}

<# functions with parameters #>


