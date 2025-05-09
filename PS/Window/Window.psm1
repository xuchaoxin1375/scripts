
<#
.SYNOPSIS
显示一个自定义消息框。

.DESCRIPTION
此函数会显示一个可自定义的消息框,支持设置显示内容、窗口大小和显示时间。
Windows Forms 版本,兼容老系统

.PARAMETER Message
要显示的消息内容。默认为 "Hello, World!"。

.PARAMETER Title
消息框的标题。默认为 "Message"。

.PARAMETER Width
消息框的宽度(像素)。默认为 300。

.PARAMETER Height
消息框的高度(像素)。默认为 200。

.PARAMETER Duration
消息框自动关闭的时间(秒)。如果不设置,消息框将不会自动关闭。

.EXAMPLE
Show-Message -Message "操作成功!" -Title "提示" -Width 400 -Height 250 -Duration 5

.EXAMPLE
Show-Message "这是一个测试消息" -Duration 3
.EXAMPLE
在后台任务创建一个窗口显示当前时间
PS C:\Users\cxxu\Desktop> show-message -Message (Get-Time) -Duration 3 &

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
3      Job3            BackgroundJob   Running       True            localhost            show-message -Message (G…

.NOTES
作者: cxxu
日期: 2024-07-29
#>
function Show-Message
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string]$Message = 'Hello, World!',
        
        [string]$Title = 'Message',
        
        [int]$Width = 300,
        
        [int]$Height = 200,
        
        [int]$Duration
    )

    # 将窗口创建和显示逻辑封装在脚本块中
    $showWindow = {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.Size = New-Object System.Drawing.Size($Width, $Height)
        $form.StartPosition = 'CenterScreen'

        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point(10, 10)
        $label.Size = New-Object System.Drawing.Size(($Width - 20), ($Height - 50))
        $label.Text = $Message
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

        $closeButton = New-Object System.Windows.Forms.Button
        $closeButton.Location = New-Object System.Drawing.Point(($Width - 80), ($Height - 40))
        $closeButton.Size = New-Object System.Drawing.Size(70, 30)
        $closeButton.Text = '关闭'
        $closeButton.Add_Click({ $form.Close() })

        $form.Controls.Add($label)
        $form.Controls.Add($closeButton)

        $timer = $null
        if ($Duration)
        {
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = $Duration * 1000
            $timer.Add_Tick({ $form.Close() })
            $timer.Start()
        }

        # 添加资源清理代码
        $form.Add_FormClosed({
                if ($timer)
                {
                    $timer.Stop()
                    $timer.Dispose()
                }
                $label.Dispose()
                $closeButton.Dispose()
                $form.Dispose()
            })

        $form.Add_Shown({ $form.Activate() })
        [void]$form.ShowDialog()
    }

    # 只有在实际调用函数时才执行窗口创建和显示逻辑
    . $showWindow
}