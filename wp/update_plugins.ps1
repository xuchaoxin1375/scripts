<# 
.SYNOPSIS
批量查看/删除/更新wordpress站点的插件
.DESCRIPTION
默认更新插件,用户将需要更新的插件目录列在参数$PluginSources中,脚本将自动查找所有wp-content/plugins目录,并更新/安装插件到对应目录中.
.PARAMETER WpSitesDir
指定需要被更新插件的存放各个wordpress站的总目录

.PARAMETER pattern
指定wp站点中的插件目录的匹配模式,默认值*/wp-content/plugins/*的路径
可以进一步截断pattern的末尾`/*`,可以找到以`*/wp-content/plugins`结尾的路径
.PARAMETER Depth
指定扫描深度,默认值为1,通常,相对于不指定合适的数值而言,指定后可以提高扫描速度
.PARAMETER PluginSources
需要更新的插件(提前解压),下面的数组中一行一个插件目录
.PARAMETER RemoveOnly
只清除旧插件,不更新/重新安装新插件
.PARAMETER CheckSpecifiedPluginsDirOnly
只检查指定的插件目录,不清除旧插件,不更新/重新安装新插件

.EXAMPLE
更新或者安装单个插件🎈
# 计算合适的插件源形式(路径或者名称);
注意symbolicLink要谨慎使用(尤其是跟新待上线本地站点的插件时,建议使用Tagfile,或者Copy模式,
否则默认的打包(tar)时默认符号链接会会被不合适的形式打包进去)

$plugin='wp-card-tpay' #插件名字
$installMode="TagFile" # "symbolicLink", "TagFile", "Copy"
$plugin_format=if(test-path $wp_plugins -erroraction SilentlyContinue){"$wp_plugins/$plugin"}else{"$plugin"}
# 更新本地站点(例如已经拷贝到my_wp_sites中的待上线站点;)
. $scripts/wp/update_plugins.ps1 -WpSitesDir $my_wp_sites -PluginSources $plugin_format -InstallMode $installMode

# 只有zw,zsh可以跳过下面语句，其他人(有本地模板库的)都要执行
. $scripts/wp/update_plugins.ps1 -WpSitesDir $wp_sites -PluginSources $plugin_format -InstallMode $installMode

.EXAMPLE
# 更新多个指定插件(插件路径列表)
(执行两个步骤:1.清除旧插件,2.安装新插件)
W:\wp_sites\wp_plugins_function\update_plugins.ps1 -PluginSources @"
W:\wp_sites\wp_plugins\price_pay\paypal-online-payment-for-woocommerce
"@

.EXAMPLE
# 只清除指定插件
$plugin="xpaid_pay"
. $scripts/wp/update_plugins.ps1  -Depth 2 -WpSitesDir $my_wp_sites  -RemovePluginsOfSites -PluginsToRemove $plugin
# zw,zsh可以跳过下面语句
. $scripts/wp/update_plugins.ps1 -Depth 2 -WpSitesDir $wp_sites  -RemovePluginsOfSites -PluginsToRemove $plugin

.EXAMPLE
移除指定插件:采集员:(将此ps1脚本放到桌面)然后执行下面两个语句(记得修改指定插件名称)
$plugin="fulupay-woocommerce"
. $desktop/update_plugins.ps1 -Depth 1 -WpSitesDir $wp_sites    -RemovePluginsOfSites -PluginsToRemove $plugin
. $desktop/update_plugins.ps1 -Depth 1 -WpSitesDir $my_wp_sites    -RemovePluginsOfSites -PluginsToRemove $plugin
#>
[cmdletbinding(SupportsShouldProcess)]
param(

    # 指定需要被更新插件的wordpress站总目录
    # $WpSitesDir = 'D:\wordpress\'
    $WpSitesDir = 'C:\sites\wp_sites\',
    # $WpSitesDir='C:\sites\wp_sites\init' #test demo 
    
    $pattern = '*\wp-content\plugins\*',
    $Depth = 1,#默认扫描深度为1(指定扫描深度可以提高扫描速度)

    
    # 需要更新的插件(提前解压),下面的数组中一行一个插件目录
    $PluginSources = @'
#表示注释
# C:\Share\df\wp_sites\wp_plugins_functions\price_pay\yunzipaycc-for-woocommerce
'@,
    # 通过指定名字来移除插件
    $PluginsToRemove = @'
# mallpay
'@,
    # 只清除旧插件,不更新/重新安装新插件
    [switch]$RemovePluginsOfSites,
    # [switch]$CheckSpecifiedPluginsDirOnly
    # 是否使用符号链接来处理插件的安装/更新
    # [switch]$UseSymbolicLink
    [ValidateSet('Copy', 'SymbolicLink', 'TagFile')]
    $InstallMode = 'TagFile'
)

function split_args
{
    <# 
    .SYNOPSIS
    将可能包含多个的插件目录参数进行分割(假设每个插件目录路径都不含空格或其他特殊字符)
    #>
    param (
        $Params
    )
    # 将各种分隔符替换为空格
    $res = $params -replace '#.*', ' ' -replace '[",;\r\n]', ' ' -replace "'" , ' ' -replace '\s+', ' '
    # 将空格作为分隔符,分割插件目录
    $res = $res.Trim() -split ' '
    return $res
    
    
}
# 参数整理
$plugin_pattern = $pattern.TrimEnd('\*') # 即:*\wp-content\plugins 用来获取以wp-content\plugins结尾的目录
$PluginSources = split_args $PluginSources 
$PluginsToRemove = split_args $PluginsToRemove

# 初始化插件目录的目标路径列表
$plugin_dirs_root_of_sites = [System.Collections.Generic.List[string]]@()

Write-Verbose "plugin_pattern: $plugin_pattern"
# Write-Output $PluginSources

# 列出所有本地模板站根目录下的wp-content/plugins插件目录(各个本地wp站的插件总目录)
## 使用进度条显示扫描进度

# 为了提供大致的进度显示,列出所有$WpSitesDir目录下的一级子目录,并估算任务组总数,作为进度参考
$site_dirs = Get-ChildItem -Directory $WpSitesDir
$tasks = $site_dirs.Count 

$i = 0
#兼容powershell5

function get_plugin_dirs_root_of_sites
{
    <# 
    .SYNOPSIS
    计算所有本地wp站中的插件目录(wp-content\plugins结尾的目录)
    结果会插入到全局变量$plugin_dirs_root_of_sites中
    .DESCRIPTION
    找到的结果可以用做(遍历$plugin_dirs_root_of_sites):
    1.新插件的安装路径
    2.更新/覆盖已有插件
    3.清除指定插件

    #>
    param (
        $site_dirs = $site_dirs,
        $plugin_pattern = $plugin_pattern
    )
    Write-Host "Scanning..."
    foreach ($site in $site_dirs)
    {
        $items = Get-ChildItem -Path $site.FullName -Recurse -Depth $Depth -Directory -Filter '*plugins' | Where-Object { $_.FullName -like $plugin_pattern } | Select-Object -ExpandProperty FullName
        if ($items)
        {
            # $plugin_dirs_root_of_sites.AddRange($item)  # 添加匹配的插件目录
            # $plugin_dirs_root_of_sites += $items  # 添加匹配的插件目录
            foreach ($item in $items)
            {
                Write-Host "Found plugin root directory: $item" -ForegroundColor Green
                $plugin_dirs_root_of_sites.Add($item) *> $null # 添加匹配的插件目录
            }
        }
    
        # 进度条
        $i++
        $completed = [math]::Round(($i / $tasks) * 100, 2)
        Write-Progress -Activity "Scanning for plugins" -Status "Scanned $i of $tasks directories ($completed %)" -PercentComplete $completed
    }
    # 打印计算结果
    # Write-Warning "The following directories were found: "
    # $plugin_dirs_root_of_sites | ForEach-Object { Write-Host $ -ForegroundColor Cyan }
}
get_plugin_dirs_root_of_sites
#powershell7写法
<# 
# $site_dirs | ForEach-Object -Begin {
#     # $i = 0
#     Write-Host "Scanning..."
# }-Process {
#     # Write-Host "scanning [$_] "
#     $item = Get-ChildItem -Path $_ -Recurse -Directory -Filter '*plugins' | Where-Object { $_.FullName -like $plugin_pattern }
#     if(!$item)
#     {
#         return
#     }

#     $i = $plugin_dirs_root_of_sites.Add($item)
#     $completed = (($i) / $tasks * 100) 
#     $completed = [math]::Round($completed, 2)
#     Write-Progress -Activity "Scanning for plugins" -Status "Scanned $i of $tasks directories($completed %)" -PercentComplete $completed
     
# } 
#>

function get_old_plugins_dirs_of_sites
{
    <# 
    .SYNOPSIS
    计算wp站中指定插件名称的插件目录(wp-content\plugins\...的目录)
    #>
    param (
        $filter,
        $plugin_dirs_root_of_sites = $plugin_dirs_root_of_sites,
        $pattern = $pattern
    )
    # Write-Host "$plugin_dirs_root_of_sites !!!"
    $old_plugin_dirs_of_sites = Get-ChildItem -Path $plugin_dirs_root_of_sites -Filter $filter -Depth 3 | Where-Object { $_.FullName -like $pattern }

    
    return $old_plugin_dirs_of_sites
}
function update_plugins
{
    <# 
    .SYNOPSIS
    更新所有站点的插件目录
    先清空已有的指定插件的目录,然后重新应用复制新的(间接重置,实现同步最新相关目录)
    .DESCRIPTION

    通过遍历要操作的插件$PluginSources,对其中的每个插件执行对应的操作
    #>
    param (
        
    )
    
    # 正式修改🎈 可以考虑启用多线程(尤其是pwsh7)
    if ($PluginSources)
    {

    
        foreach($new_plugin_dir in $PluginSources)
        {
   
            $plugin_name = if(Test-Path $new_plugin_dir) { (Split-Path $new_plugin_dir -Leaf) }else { $new_plugin_dir }
            # Write-Host $plugin_name
         
            # $filter="plugins"
            # 如果$new_plugin_dir末尾带有通配符(*),则可能导致找不到目录(因此要使用准确的路径或者插件目录的名称)
            # $filter = $plugin_name
   
            Write-Output "Searching for plugins dir (wait for a moment....)"
   
    
            # 默认模式:移除旧插件,并安装/更新插件
            $old_plugin_dirs_of_sites = get_old_plugins_dirs_of_sites -filter $plugin_name  # 移除wp站中相关的旧插件$plugin_name(目录)
            foreach($old_plugin in $old_plugin_dirs_of_sites)
            {
                Write-Verbose "Remove $($old_plugin.FullName)" -Verbose
                Remove-Item -Path $old_plugin.FullName -Recurse -Force -Confirm:$false 
            }
       
            Write-Verbose "installing plugin[ $plugin_name ]..." -Verbose 
            # 安装新插件到对应目录中
            foreach($target in $plugin_dirs_root_of_sites)
            {
            
                Write-Host "Installing plugin $plugin_name to $target"
           
                # if($UseSymbolicLink)
                if($InstallMode -like "symbolic*")
                {
                    if (Test-Path $new_plugin_dir)
                    {

                        # 使用符号链接代替拷贝
                        New-Item -ItemType SymbolicLink -Path $target/$plugin_name -Value $new_plugin_dir -Force -Verbose 
                        # pause
                    }else{
                        Write-Error "Plugin source directory not found: $new_plugin_dir"
                        return $False
                    }
                }
                elseif($InstallMode -eq "tagfile")
                {
                    # 此时不依赖于源插件目录是否存在
                    New-Item -ItemType File -Path $target/$plugin_name -Force -Verbose
                }
                elseif($InstallMode -eq "copy")
                {
                    # Copy-Item -Recurse -Path $dir -Destination $WpSitesDir -Force -WhatIf
                    Copy-Item -Recurse -Path $new_plugin_dir -Destination $target -Force
                }
           
            }
        
        }
    }
    
}
function remove_plugins
{
    <# 
    .SYNOPSIS
    删除指定插件的目录
    #>

    # Write-Host "$PluginsToRemove"
    foreach($plugin in $PluginsToRemove)
    {
        Write-Host "Removing plugin[ $plugin ] in all sites ..."
        # 计算要被移除指定插件$plugin的所有现有站点中的对应插件目录
        $old_plugin_dirs_of_sites = get_old_plugins_dirs_of_sites -filter $plugin
        Write-Output $old_plugin_dirs_of_sites
        # Pause
        if($old_plugin_dirs_of_sites)
        {

            Remove-Item $old_plugin_dirs_of_sites -Force -Recurse
        }
        else
        {
            Write-Host "No plugin $plugin found." -ForegroundColor Yellow
        }
    }
}

if($RemovePluginsOfSites)
{
    # 只清除旧插件,不更新/重新安装新插件
    Write-Warning "Removing plugins..."
    remove_plugins
}
else
{
    # 更新插件
    Write-Warning "Updating plugins..."
    update_plugins
}


Pause
