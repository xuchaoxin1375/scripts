#!/bin/bash
# 这是默认的定时部署脚本,如果路径等参数和此默认值不同的话,请拷贝此文件为你(服务器)的专属配置文件(副本)
# 比如deploy_wp_schd_user1_s1.sh
# 然后修改副本中的参数来实现自定义部署逻辑

# 部署脚本依赖于/www/sh/deploy_wp_full.sh,不过部署代码的时候通常会为你创建/deploy.sh这个路径简化的符号连接.(管理员权限)
# 这里使用后者代替
cat <<eof >/dev/null

# 完整的可用参数请运行命令行获取:    bash /deploy.sh -h  
!以下用法仅供快捷参考

用法: /deploy.sh [选项]
对于多硬盘服务器,可能需要设置--pack-root(可选),--project-home:
选项:
  -p,--pack-root DIR        设置压缩包根目录 (默认: /srv/uploads/uploader/files)
  --db-user USER            设置数据库用户名 (默认: root)
  --db-pass PASS            设置数据库密码
  --user-dir DIR            仅处理指定用户目录
  --deployed-dir DIR        默认存储已部署的包文件(默认: /srv/uploads/uploader/deployed_all)
  -r,--project-home DIR     设置站点所属的项目目录PROJECT_HOME (默认: /www/wwwroot)
  --site-home DIR           设置SERVER_SITE_HOME（自定义站点根目录）
  -h,--help                 显示此帮助信息
eof

LOG_FILE="/srv/uploads/uploader/files/$(date +%Y-%m-%d).log"

bash /deploy.sh >> "$LOG_FILE" 2>&1
# bash /deploy.sh -r /wwwdata/wwwroot >> "$LOG_FILE" 2>&1
