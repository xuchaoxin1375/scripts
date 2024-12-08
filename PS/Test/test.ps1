Add-Type -AssemblyName PresentationFramework

# 创建窗口
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="System Utility (by @Cxxu)" Height="600" Width="450" WindowStartupLocation="CenterScreen"
        Background="White" AllowsTransparency="False" WindowStyle="SingleBorderWindow">
    <Grid>
        <Border Background="White" CornerRadius="10" BorderBrush="Gray" BorderThickness="1" Padding="10">
            <StackPanel>
                <TextBlock Text="Select a system to reboot into (从列表中选择重启项目):" Margin="10" FontWeight="Bold" FontSize="14"/>
                <ListBox Name="BootEntryList" Margin="10" Background="LightBlue" BorderThickness="0">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Border Background="LightGray" CornerRadius="10" Padding="5" Margin="5">
                                <TextBlock Text="{Binding Description}" Margin="5,0,0,0"/>
                            </Border>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
                <Button Name="RebootButton" Content="Reboot | 点击重启" Margin="10" HorizontalAlignment="Center" Width="140" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="#FF2A2A"/>
                            <Setter Property="Foreground" Value="White"/>
                            <Setter Property="FontWeight" Value="Bold"/>
                            <Setter Property="Cursor" Value="Hand"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#FF5555"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
                <Button Name="ShutdownButton" Content="Shutdown and Restart" Width="200" Height="30" Margin="10" HorizontalAlignment="Center" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="#FF2A2A"/>
                            <Setter Property="Foreground" Value="White"/>
                            <Setter Property="FontWeight" Value="Bold"/>
                            <Setter Property="Cursor" Value="Hand"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#FF5555"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
                <TextBlock HorizontalAlignment="Center" Margin="10">
                    <Hyperlink Name="BaiduLink">Baidu</Hyperlink>
                </TextBlock>
                <TextBlock HorizontalAlignment="Center" Margin="10">
                    <Hyperlink Name="GiteeLink">Gitee</Hyperlink>
                </TextBlock>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# 获取控件
$bootEntryList = $window.FindName("BootEntryList")
$rebootButton = $window.FindName("RebootButton")
$shutdownButton = $window.FindName("ShutdownButton")
$baiduLink = $window.FindName("BaiduLink")
$giteeLink = $window.FindName("GiteeLink")

# 填充ListBox示例数据
$bootEntries = @(
    [PSCustomObject]@{Description = 'Windows 10' },
    [PSCustomObject]@{Description = 'Windows 11' },
    [PSCustomObject]@{Description = 'Linux' }
)
$bootEntryList.ItemsSource = $bootEntries

# 定义按钮点击事件
$rebootButton.Add_Click({
        $selectedEntry = $bootEntryList.SelectedItem
        if ($null -ne $selectedEntry)
        {
            $description = $selectedEntry.Description
            Write-Output "Rebooting to: $description"
            # 调用重启命令 (示例，不执行实际操作)
            # Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "0", "/d", "p:4:1", "/c", "Rebooting to $description"
        }
        else
        {
            [System.Windows.MessageBox]::Show("Please select an entry to reboot into.", "No Entry Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    })

$shutdownButton.Add_Click({
        Write-Output "Executing shutdown command"
        Start-Process "shutdown.exe" -ArgumentList "/fw", "/r", "/t", "0"
    })

# 定义链接点击事件
$baiduLink.Add_Click({
        Start-Process "https://www.baidu.com" | Out-Null
    })

$giteeLink.Add_Click({
        Start-Process "https://gitee.com" | Out-Null
    })

# 显示窗口
$window.ShowDialog()
