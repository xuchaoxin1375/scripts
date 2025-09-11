#扫描出所有astra目录(可以通过查看$ts变量来确定扫描出来的路径是否正确)
$ts = Get-ChildItem /www/wwwroot/*/*.com/wordpress/wp-content/themes/astra | Select-Object -ExpandProperty FullName
#遍历所有astra目录,然后用最新包中的内容覆盖老astra目录中的内容即可
$ts | ForEach-Object { 
    # Remove-Item $_ -Recurse -Force
    cp /www/wwwroot/themes_astra_4.11/astra/* $_  -rf -v
} 