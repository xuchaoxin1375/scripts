<# 
.SYNOPSIS 
本地wordpress模板functions.php批量覆盖
递归查找合适的目录将functions.php插件复制到其中
.EXAMPLE
# 采集员的-function_file 指定为$desktop/functions.php
. $desktop/update_functions.ps1 -wp_sites_dir $wp_sites -verbose  # -function_file $desktop/functions.php
. $desktop/update_functions.ps1 -wp_sites_dir $my_wp_sites -verbose  # -function_file $desktop/functions.php

#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    $wp_sites_dir = 'C:\sites\wp_sites',  
    # 默认目录;采集员填写
    # $wp_sites_dir='C:\Users\Administrator\Desktop\my_wp_sites',

    $exclude_dir = "Temp",
    $function_file = 'R:\wp_sites\wp_plugins_functions\functions.php',
    # 设置合适的递归深度可以提高搜索效率,如果为空可以提高搜索深度
    $Depth=3,
    $file_name = 'functions.php',
    $pattern = "*wp-content\themes\*\functions.php"  # 更精确的匹配
)

Write-Host "Searching for files in $wp_sites_dir (wait for a moment....)"
Write-Host "$(Get-Date)"

# 检查目录是否存在
if (!(Test-Path $wp_sites_dir))
{
    Write-Error "The directory $wp_sites_dir does not exist."
    return
}
else
{
    Write-Host "The directory $wp_sites_dir exists."
}

# 获取所有站点目录（排除 $exclude_dir）
$sites = Get-ChildItem -Path $wp_sites_dir -Directory | Where-Object { $_.Name -ne $exclude_dir }
$sites | ForEach-Object { Write-Host "Found site: $($_.FullName)" }

# 收集所有目标文件
$targets = @()
foreach ($site in $sites)
{
    $theme_files = Get-ChildItem -Path $site.FullName -Recurse  -Depth $Depth -File -Filter $file_name |
    Where-Object { $_.FullName -like $pattern }
    $targets += $theme_files
    $theme_files | ForEach-Object { Write-Host "Target file: $($_.FullName)" }
}

# 提示用户确认
Write-Host "Found $($targets.Count) files to update."
if ($targets.Count -eq 0)
{
    Write-Warning "No files matched the pattern. Exiting."
    return
}

# 确认操作
if ($PSCmdlet.ShouldProcess("Update functions.php in $($targets.Count) files"))
{
    $targets | ForEach-Object {
        Copy-Item -Path $function_file -Destination $_.FullName -Verbose -Force -WhatIf:$WhatIfPreference
    }
}

Pause