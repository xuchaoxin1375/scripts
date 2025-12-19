[toc]



在 Nginx 中，你可以通过 `add_header` 指令配合限流状态码，手动向客户端（如 Googlebot）发送 `Retry-After` 头部。

这在 SEO 优化中非常重要，因为它明确告诉 Googlebot：“我现在很忙，请在 **X 秒**后再试”，而不是让爬虫盲目地不断重试。

### 推荐配置方法

由于 `limit_req` 模块在触发限流时会直接中断请求并返回状态码，我们通常需要利用 Nginx 的 `error_page` 机制来拦截 429 错误，并在此处插入 `Retry-After` 头部。

Nginx

```nginx
http {
    # 定义限流区
    limit_req_zone $binary_remote_addr zone=product_limit:10m rate=1r/s;

    server {
        listen 80;
        server_name example.com;

        # 定义 429 错误的处理逻辑
        error_page 429 = @handle_too_many_requests;

        location ~* ^/(product|shop)/ {
            limit_req zone=product_limit burst=5 nodelay;
            limit_req_status 429;
            
            try_files $uri $uri/ /index.php?$args;
        }

        # 命名 location：专门负责返回 429 响应头
        location @handle_too_many_requests {
            # 设置重试时间，单位为秒 (例如 300 秒 = 5 分钟)
            add_header Retry-After 300 always;
            
            # 返回状态码和简单的提示
            return 429 "Too Many Requests. Please try again later.";
        }

        # PHP 处理逻辑...
        location ~ \.php$ {
            # ... fastcgi_pass 等配置 ...
        }
    }
}
```

------

### 配置细节解析

1. error_page 429 = @handle_too_many_requests;

   标准的 limit_req 无法直接在触发瞬间动态添加 Header。通过将 429 错误重定向到一个“内部位置”（Named Location），我们可以自定义响应内容和头部。

2. **`add_header Retry-After 300 always;`**

   - **300**：表示建议客户端在 300 秒后重试。你可以根据服务器负载自行调整。
   - **always**：非常关键。默认情况下 `add_header` 只对 200, 201, 301 等成功码有效。加上 `always` 确保在 429 这种错误码下也能成功发送 Header。

3. Googlebot 的行为

   当 Googlebot 看到这个头部时，它会严格遵守时间窗口，这能极大地保护你的 WooCommerce 数据库不会因为 PHP 进程堆积而崩溃。

------

### 进阶：如何验证配置是否生效？

修改完配置并重启 Nginx 后，你可以使用 `curl` 命令模拟频繁请求来测试：

Bash

```
# 连续执行多次，直到出现 429
curl -I https://yourdomain.com/product/test-item
```

你应该在返回的 HTTP 响应头中看到类似下面的一行：

HTTP/1.1 429 Too Many Requests

Retry-After: 300

------

### ⚠️ 注意事项

- **固定值 vs 动态值**：Nginx 原生配置 `Retry-After` 通常只能设置固定秒数。如果你需要非常复杂的动态调整（比如根据系统 CPU 负载动态计算秒数），则需要配合 Lua 脚本（OpenResty）来实现。
- **不要设置过长**：通常建议设置在 60 到 600 秒之间。设置太长（如几天）可能会导致 Googlebot 暂时放弃抓取该页面。

