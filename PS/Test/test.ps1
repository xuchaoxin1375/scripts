$themes = @('woostify', 'astra') #如果是别的主题,可以换成别的名字,比如astra主题就是'astra' 
$themes | ForEach-Object {

    $theme = $_
    $theme_inc = Get-ChildItem /www/wwwroot/*/*.com/wordpress/wp-content/themes/$theme/inc | Select-Object -ExpandProperty FullName
    $theme_inc | ForEach-Object { Copy-Item /www/wwwroot/wp_themes_init/$theme/init.php $_ -v }
}