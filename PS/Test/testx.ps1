
# 指定需要被更新插件的wordpress站总目录
# $wp_sites_dir = 'D:\wordpress\'
$wp_sites_dir = 'C:\sites\wp_sites\'

# 需要更新的插件(提前解压),下面的数组中一行一个插件目录
$dir_sources = @(
    "W:\wp_sites\wp_plugins\price_pay\hellotopay"
    "W:\wp_sites\wp_plugins\price_pay\public-payment-for-woo"
    # "C:\Share\df\wp_sites\wp_plugins\price_pay\woo-nexpay"
)
# 可以考虑启用多线程(尤其是pwsh7)
foreach($dir in $dir_sources)
{
    # $dir = $dir_sources[0]

    $dir_name = Split-Path $dir -Leaf
    # Write-Host $dir_name
    
    # $filter="plugins"
    $filter = $dir_name
    $pattern = '*\wp-content\plugins\*'

    Write-Output "Searching for files in $wp_sites_dir (wait for a moment....)"

    # 可以考虑先清空已有目录,然后重新应用复制新的(间接重置同步最新相关目录)
    # Get-ChildItem -Path $wp_sites_dir -Recurse -Directory -Filter $filter | Where-Object { $_.FullName -like $pattern }

    $contents = Get-ChildItem -Path $wp_sites_dir -Recurse -Directory -Filter $filter | Where-Object { $_.FullName -like $pattern }
    Write-Output $contents 
}