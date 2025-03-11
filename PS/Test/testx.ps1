
# 指定需要被更新插件的wordpress站总目录
# $wp_sites_dir = 'D:\wordpress\'
$wp_sites_dir = 'C:\sites\wp_sites\'
$pattern = '*\wp-content\plugins\*'

# 需要更新的插件(提前解压),下面的数组中一行一个插件目录
$plugin_sources = @'

W:\wp_sites\wp_plugins\price_pay\hellotopay
# W:\wp_sites\wp_plugins\price_pay\public-payment-for-woo
C:\Share\df\wp_sites\wp_plugins\price_pay\woo-nexpay

'@
$plugin_sources = $plugin_sources -replace '#.*', ' ' -replace '[",;\r\n]', ' ' -replace "'" , ' ' -replace '\s+', ' ' 
$plugin_sources = $plugin_sources.Trim() -split ' '

# Write-Output $plugin_sources
# pause
# 列出所有wp-content/plugins插件目录
$plugin_pattern = $pattern.TrimEnd('\*')
Write-Verbose "plugin_pattern: $plugin_pattern"
$plugin_dirs_target = [System.Collections.ArrayList]@()

# 方案1(看使用进度条显示扫描进度)
# $plugin_dirs_target = Get-ChildItem -Path $wp_sites_dir -Recurse -Directory -Filter '*plugins' | Where-Object { $_.FullName -like $plugin_pattern }
$site_dirs = (Get-ChildItem -Directory $wp_sites_dir)
$tasks = $site_dirs.Length

$site_dirs | ForEach-Object -Begin {
    # $i = 0
    Write-Host "Scanning..."
} -Process {
    # Write-Host "scanning [$_] "
    $item = Get-ChildItem -Path $_ -Recurse -Directory -Filter '*plugins' | Where-Object { $_.FullName -like $plugin_pattern }
    if(!$item)
    {
        return
    }

    $i = $plugin_dirs_target.Add($item)
    $completed = (($i) / $tasks * 100) 
    $completed = [math]::Round($completed, 2)
    Write-Progress -Activity "Scanning for plugins" -Status "Scanned $i of $tasks directories($completed %)" -PercentComplete $completed
     
}

Write-Warning "The following directories will be updated: "
Write-Output $plugin_dirs_target | Select-Object -ExpandProperty FullName


 
# 正式修改🎈 可以考虑启用多线程(尤其是pwsh7)
foreach($new_plugin_dir in $plugin_sources)
{

    $plugin_name = Split-Path $new_plugin_dir -Leaf
    # Write-Host $plugin_name
      
    # $filter="plugins"
    $filter = $plugin_name

    Write-Output "Searching for files in $wp_sites_dir (wait for a moment....)"

    # 可以考虑先清空已有目录,然后重新应用复制新的(间接重置同步最新相关目录)
    # Get-ChildItem -Path $wp_sites_dir -Recurse -Directory -Filter $filter | Where-Object { $_.FullName -like $pattern }

    $old_plugin_dirs = Get-ChildItem -Path $wp_sites_dir -Recurse -Directory -Filter $filter | Where-Object { $_.FullName -like $pattern }

    
    Write-Verbose "installing plugin $plugin_name ..." -Verbose

   
    # 清空对应的旧插件(目录)
    foreach($old_plugin in $old_plugin_dirs)
    {
        Write-Verbose "remove $old_plugin.FullName" 
        Remove-Item -Path $old_plugin.FullName -Recurse -Force 
    }
    # 安装新插件到对应目录中
    foreach($target in $plugin_dirs_target)
    {
        Write-Host "Installing(copying) plugin $plugin_name to $target"

        # Copy-Item -Recurse -Path $dir -Destination $wp_sites_dir -Force -WhatIf

        Copy-Item -Recurse -Path $new_plugin_dir -Destination $target -Force

    }

  
}

