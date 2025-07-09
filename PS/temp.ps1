<# 
.SYNOPSIS
    建议配置免密登录，避免每次都输入密码(ssh 密钥注册)
.DESCRIPTION
    这里直接上传插件文件夹(你需要手动解压,插件可能是zip或者tar.gz)
    也可以添加逻辑来支持上传压缩文件(todo)
    或者指定目录后,添加一个压缩成zip/7z的命令,然后推送到服务器上,最后调用解压和目录复制逻辑

#>
# 定义变量(修改这些变量)
$server = $env:DF_SERVER1               # 服务器IP地址
$username = "root"              # 服务器用户名
# $password = ""              # 服务器密码（不推荐明文存储）

$plugin_dir_name = "yunzipaycc-for-woocommerce"
$remoteDirectory = "/www/wwwroot"        # 服务器目标目录
$phpScript = "install_plugin_cli.php"          # 要执行的服务器上的PHP脚本

$plugin_dir_local = "C:\Share\df\wp_sites\wp_plugins_functions\price_pay\$plugin_dir_name"   # 本地插件目录路径🎈
$plugin_dir = "$remoteDirectory/$plugin_dir_name"    # 服务器目标插件目录🎈

# 将上述目录逐个打印出来
Write-Host "Plugin directory: $plugin_dir_local"
Write-Host "Remote plugin directory: $plugin_dir"

# 上传文件到服务器
Write-Output "Uploading file to server..."
scp -r $plugin_dir_local $username@${server}:"$remoteDirectory" 


# 执行PHP脚本
Write-Output "Executing PHP script...(this need several minutes...)"
ssh $username@$server "php $remoteDirectory/$phpScript $remoteDirectory $plugin_dir "

Write-Output "Done."