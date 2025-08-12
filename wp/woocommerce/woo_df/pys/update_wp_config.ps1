
using namespace System.Collections.Generic
$configs = Get-ChildItem $wp_sites/*.* -Depth 2 -File -Filter wp-config.php | Select-Object -ExpandProperty FullName 

$configs | ForEach-Object {
    
    #修改单个wp-config.php内容(不立刻回写)
    # $Path = ".\wp-config.php"
    $Path = $_
    $strList = [System.Collections.Generic.List[string]]::new()
    Get-Content $Path | ForEach-Object { 
        if( $_ -match '.*Add any custom.*')
        {
            $t = $_ + @"

define('DISABLE_WP_CRON', true);#禁用wp-cron任务,使用系统定时任务代替

"@
        }
        else { $t = $_ } 
        $strList.Add($t)

    } 
    $strList | Set-Content -Path $Path -Encoding UTF8 -Force 
}

# $Path = ".\wp-config.php"
# $strList = [System.Collections.Generic.List[string]]::new()

# Get-Content $Path | ForEach-Object { 
#     if( $_ -match '.*Add any custom.*')
#     {
#         $t = $_ + @"

# define('DISABLE_WP_CRON', true);#禁用wp-cron任务,使用系统定时任务代替

# "@
#     }
#     else { $t = $_ } 
#     $strList.Add($t)

# } 
# $strList | Set-Content -Path $Path -Encoding UTF8 -Force