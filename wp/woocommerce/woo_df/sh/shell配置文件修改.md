[toc]



将一些常用的shell函数或者配置添加(直接或间接添加)到shell的配置文件(比如`~/.bashrc`或`~/.zshrc`),可以简化命令行操作

下面是一些典型的配置案例

### 添加brew函数

如果你使用了linuxbrew,并且常常在root用户权限下想要使用brew安装软件,那么可以通过包装一个临时调用其他用户权限使用brew的函数(具体的brew路径取决于你的安装情况)

```bash
brew() {
    local ORIG_DIR="$PWD"
    echo "[INFO] Executing as user 'linuxbrew' in /home/linuxbrew: brew $*"
    cd /home/linuxbrew && sudo -u linuxbrew /home/linuxbrew/.linuxbrew/bin/brew "$@"
    local EXIT_CODE=$?
    cd "$ORIG_DIR" 2>/dev/null || echo "[WARN] Could not return to original directory: $ORIG_DIR"
    return $EXIT_CODE
}
```

### 添加wp函数

```bash
wp() {
  	user='www' #修改为你的系统上存在的一个普通用户的名字,比如宝塔用户可以使用www
    echo "[INFO] Executing as user '$user':wp $*"
    sudo -u $user wp "$@"
    local EXIT_CODE=$?
    return $EXIT_CODE
}
```

然后我们调用的`wp`相当于调用`sudo -u www wp`(借用`www`用户的权限执行`wp`命令),即便是在root用户下也不会因为当前用户是root而被拒绝执行,例如

```bash
   wp theme list
[INFO] Executing as user 'www':wp theme list
+-------+--------+-----------+---------+----------------+-------------+
| name  | status | update    | version | update_version | auto_update |
+-------+--------+-----------+---------+----------------+-------------+
| astra | active | available | 4.11.10 | 4.11.12        | off         |
+-------+--------+-----------+---------+----------------+-------------+
```

