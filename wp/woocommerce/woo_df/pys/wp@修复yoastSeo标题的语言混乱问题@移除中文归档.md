[toc]



## abstract

本文讨论:wordpress yoast seo插件中，管理员账号是中文用户，但是网站是面向英语(或者其他语言),由于没有恰当设置,导致google收录的网页标题出现了"归档"中文

单个网站的修复比较简单,登录后台修改,修改相关配置即可,下面讨论批量修改大量网站的情况

## 使用wp-cli批量修复网站

> 不建议直接在数据库中用 SQL 将“归档”替换为空字符串（`""`），**尤其是对 Yoast SEO 的序列化数据（`wp_options` 中的 `wpseo_titles`）**。
>
> ⚠️ 为什么不能直接用 SQL 替换？
>
> Yoast SEO 的设置（如 `wpseo_titles`）是以 **PHP 序列化数组（serialized array）** 的形式存储的。
> 序列化数据不仅包含值，还包含每个字符串的**精确长度**。
>
> 例如：

> `s:12:"归档：作者"; `
>
> 表示：这是一个字符串（`s`），长度为 12 个**字节**（注意：中文 UTF-8 通常占 3 字节/字），内容是“归档：作者”。

### 检查"归档"二字是否存在

```bash
 wp option get wpseo_titles --format=var_export | grep "归档"
```

### 移除"归档"二字

```bash
#!/bin/bash

BASE_DIR="/www/wwwroot" #根据需要修改(网站根目录是否有wordpress层也要注意修改)
MAX_JOBS=32 #根据需要修改
job_count=0
# 让root用户下可以借用普通用权限进行安全wp cli操作
wp() {
  	user='www' #修改为你的系统上存在的一个普通用户的名字,比如宝塔用户可以使用www
    echo "[INFO] Executing as user '$user':wp $*"
    sudo -u $user wp "$@"
    local EXIT_CODE=$?
    return $EXIT_CODE
}
for wpdir in $(find "$BASE_DIR" -type d -path "*/wordpress" -maxdepth 3); do
    (
        echo "正在处理: $wpdir"
        cd "$wpdir"
        if [ -f "$wpdir/wp-config.php" ]; then
            # 在下面定义需要执行的wp_cli命令行
           
          wp eval '
            $titles = get_option("wpseo_titles");
            if (is_array($titles)) {
                foreach ($titles as $k => $v) {
                    if (is_string($v)) {
                        $titles[$k] = str_replace("归档", "", $v);
                    }
                }
                update_option("wpseo_titles", $titles);
                echo "✅ 已清理 \"归档\" 字样。\n";
            }
            '
            if [ $? -eq 0 ]; then
                echo "  ✅ 成功执行wp命令"
            else
                echo "  ❌ 设置失败，请检查该目录的权限或 WP 安装情况"
            fi
        else
            echo "  ⚠️ 未找到 wp-config.php，跳过"
        fi
    ) &
    job_count=$((job_count+1))
    if [ "$job_count" -ge "$MAX_JOBS" ]; then
        wait
        job_count=0
    fi
done
wait
```

