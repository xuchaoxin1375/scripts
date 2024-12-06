Add-Type -AssemblyName PresentationFramework

# 定义启动项
$bootEntries = @(
    [PSCustomObject]@{Identifier = '{bootmgr}'; Description = 'Windows Boot Manager' },
    [PSCustomObject]@{Identifier = '{current}'; Description = 'Windows 10' },
    [PSCustomObject]@{Identifier = '{b794f931-144f-11ef-bbb1-dcfb484e80bc}'; Description = 'Windows 10' }
)

# 创建窗口
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Choose Boot Entry" Height="300" Width="450" WindowStartupLocation="CenterScreen"
        Background="White" AllowsTransparency="False" WindowStyle="SingleBorderWindow">
    <Grid>
        <Border Background="White" CornerRadius="10" BorderBrush="Gray" BorderThickness="1" Padding="10">
            <StackPanel>
                <TextBlock Text="Select a system to reboot into:" Margin="10" FontWeight="Bold" FontSize="14"/>
                <ListBox Name="BootEntryList" Margin="10" Background="White" BorderThickness="0">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Border Background="LightBlue" CornerRadius="10" Padding="5" Margin="5">
                                <TextBlock Text="{Binding Description}" Margin="5,0,0,0"/>
                            </Border>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
                <Button Name="RebootButton" Content="Reboot" Margin="10" HorizontalAlignment="Center" Width="100" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
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
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# 获取控件
$listBox = $window.FindName("BootEntryList")
$button = $window.FindName("RebootButton")

# 填充ListBox
$listBox.ItemsSource = $bootEntries

# 定义按钮点击事件
$button.Add_Click({
        $selectedEntry = $listBox.SelectedItem
        if ($null -ne $selectedEntry)
        {
            $identifier = $selectedEntry.Identifier
            Write-Output "Rebooting to: $($selectedEntry.Description) with Identifier $identifier"
            # 调用重启命令 (此处只是示例，实际环境中请谨慎操作)
            # shutdown.exe /r /t 0 /fw /f /d p:4:1 /c "Reboot to $identifier"
        }
        else
        {
            [System.Windows.MessageBox]::Show("Please select an entry to reboot into.", "No Entry Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    })

# 显示窗口
$window.ShowDialog()
