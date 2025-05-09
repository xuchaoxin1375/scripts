<# 
.SYNOPSIS
    建议配置免密登录，避免每次都输入密码(ssh 密钥注册)
.DESCRIPTION
    这里直接上传插件文件夹(你需要手动解压,插件可能是zip或者tar.gz)
    也可以添加逻辑来支持上传压缩文件(todo)

#>
# 定义变量(修改这些变量)
$server = $env:DF_SERVER1               # 服务器IP地址
$username = "root"              # 服务器用户名
# $password = ""              # 服务器密码（不推荐明文存储）
$plugin_dir_local = "W:\wp_sites\wp_plugins\price_pay\gbpay_cvv"   # 本地文件路径🎈
$phpScript = "install_plugin_cli.php"          # 要执行的PHP脚本

$remoteDirectory = "/www/wwwroot"        # 服务器目标目录
$plugin_dir = "/www/wwwroot/gbpay_cvv"    # 服务器目标插件目录



# 上传文件到服务器
Write-Output "Uploading file to server..."
scp -r $plugin_dir_local $username@${server}:"$remoteDirectory" 


# 执行PHP脚本
Write-Output "Executing PHP script...(this need several minutes...)"
ssh $username@$server "php $remoteDirectory/$phpScript $remoteDirectory $plugin_dir "

Write-Output "Done."