
# 配置pypi源
pip config set global.index-url https://mirrors.pku.edu.cn/pypi/web/simple # https://mirrors.aliyun.com/pypi/simple/ # https://pypi.mirrors.ustc.edu.cn/simple/
#配置uv
Deploy-UVConfig
pip install uv
# 查看uv配置
cat $env:APPDATA\uv\uv.toml

pip install -r C:\repos\scripts\wp\woocommerce\woo_df\requirements.txt
# 安装scrapling库
. C:\repos\scripts\wp\woocommerce\woo_df\requirements.scrapling.cmd

# end