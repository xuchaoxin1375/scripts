## 本地建站nginx配置使用说明

批量恢复有序的基础模板站nginx配置文件

```powershell
$range = @(1, 2, 4, 6, 7)
$countries = 'us', 'uk', 'de', 'fr', 'es', 'it'
foreach ($i in $range)
{
    foreach ($c in $countries)
    {
        $domain = "$i.$c"
        $conf = "$nginx_vhosts/${domain}_80.conf"
        Copy-Item $scripts/config/nginx_vhost_template.conf $conf -Verbose
        $content = Get-Content $conf -Raw
        $content = $content -replace 'domain.com', "$domain" -replace 'CgiPort', "$env:CgiPort" 

        $content = $content -replace 'C:/Users/Administrator/Desktop/my_wp_sites', 'C:/sites/wp_sites'
        $content | Set-Content $conf -Verbose
    }
}
```
