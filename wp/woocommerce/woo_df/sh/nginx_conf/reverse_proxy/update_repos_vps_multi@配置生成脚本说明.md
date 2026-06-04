[toc]

## 关于update_repos_vps_multi配置生成脚本的设计说明

分别描述：**脚本执行流程、参数状态流、配置生成结构、网络转发关系、映射解析逻辑**。

---

## 1. 脚本整体执行流程图

```mermaid
flowchart TD
    A([启动 update_repos_vps_multi.sh]) --> B[初始化默认变量]
    B --> C[解析命令行参数 parse_args]

    C --> D{是否指定 --help?}
    D -- 是 --> D1[输出 usage 帮助信息] --> Z([退出])
    D -- 否 --> E{是否指定 --dev?}

    E -- 是 --> E1[启用开发模式]
    E1 --> E2[DRY_RUN=true]
    E2 --> E3[UPDATE_CODE=false]
    E3 --> E4[UPDATE_CF=false]
    E4 --> E5[RELOAD_NGINX=false]
    E -- 否 --> F[继续]

    E5 --> F

    F --> G{是否指定 --map-file?}
    G -- 是 --> G1[读取映射文件]
    G1 --> G2[逐行解析 B_IP:A_IP]
    G -- 否 --> H[跳过文件读取]

    G2 --> I[合并命令行 -m 映射]
    H --> I

    I --> J{映射数量是否大于 0?}
    J -- 否 --> J1[报错: 必须提供至少一组映射] --> Z
    J -- 是 --> K[规范化日志目录路径]

    K --> L[生成配置文件内容到临时文件]
    L --> M{是否 DRY_RUN?}

    M -- 是 --> M1[输出临时配置内容到 stdout]
    M1 --> M2[删除临时文件]
    M2 --> Z

    M -- 否 --> N{是否 UPDATE_CODE?}
    N -- 是 --> N1[执行 update_repos.sh 更新仓库]
    N -- 否 --> N2[跳过仓库更新]

    N1 --> O[创建 nginx 配置目录和日志目录]
    N2 --> O

    O --> P{是否 UPDATE_CF?}
    P -- 是 --> P1[软链接 update_cf_ip_configs.sh]
    P1 --> P2[执行 Cloudflare real IP 更新脚本]
    P -- 否 --> P3[跳过 CF real IP 更新]

    P2 --> Q[写入 nginx 配置文件]
    P3 --> Q

    Q --> R[展示生成后的配置文件 nl -ba]
    R --> S[执行 nginx -t 检查配置]

    S --> T{是否 RELOAD_NGINX?}
    T -- 是 --> T1[执行 nginx -s reload]
    T -- 否 --> T2[跳过 reload]

    T1 --> Y([完成])
    T2 --> Y
```

---

## 2. 参数与运行模式状态图

```mermaid
stateDiagram-v2
    [*] --> NormalMode

    NormalMode: 默认模式
    NormalMode: UPDATE_CODE=true
    NormalMode: UPDATE_CF=true
    NormalMode: RELOAD_NGINX=true
    NormalMode: DRY_RUN=false

    NormalMode --> DevMode: --dev
    DevMode: 开发/调试模式
    DevMode: DRY_RUN=true
    DevMode: UPDATE_CODE=false
    DevMode: UPDATE_CF=false
    DevMode: RELOAD_NGINX=false

    NormalMode --> DryRunMode: --dry-run
    DryRunMode: 只输出配置
    DryRunMode: 不写文件
    DryRunMode: 不 nginx -t
    DryRunMode: 不 reload

    NormalMode --> NoUpdateCode: --no-update-code
    NoUpdateCode: 跳过仓库更新

    NormalMode --> NoUpdateCF: --no-update-cf
    NoUpdateCF: 跳过 Cloudflare real IP 更新

    NormalMode --> NoReload: --no-reload
    NoReload: 写入配置
    NoReload: 执行 nginx -t
    NoReload: 不 reload

    DevMode --> [*]
    DryRunMode --> [*]
    NoUpdateCode --> [*]
    NoUpdateCF --> [*]
    NoReload --> [*]
```

---

## 3. 映射输入解析逻辑图

```mermaid
flowchart TD
    A[映射输入来源] --> B[-m / --mapping 参数]
    A --> C[--map-file 文件]

    B --> B1[支持单个映射]
    B --> B2[支持逗号分隔多个映射]
    B1 --> B3["10.0.0.11:203.0.113.11"]
    B2 --> B4["10.0.0.11:203.0.113.11,10.0.0.12:203.0.113.12"]

    C --> C1[逐行读取]
    C1 --> C2[跳过空行]
    C2 --> C3[跳过 # 注释]
    C3 --> C4[支持 B_IP:A_IP]
    C3 --> C5[支持 B_IP A_IP]

    B3 --> D[add_mapping_pair]
    B4 --> D
    C4 --> D
    C5 --> D

    D --> E[去掉行尾注释]
    E --> F[识别分隔符]
    F --> G{格式类型}

    G -- 冒号 --> G1[按 : 拆分]
    G -- 空格 --> G2[按空白拆分]
    G -- "=> 或 ->" --> G3[转换成 : 后拆分]

    G1 --> H[得到 B_IP 和 A_IP]
    G2 --> H
    G3 --> H

    H --> I{B_IP 是否合法 IPv4?}
    I -- 否 --> I1[报错退出]
    I -- 是 --> J{A_IP 是否合法 IPv4?}

    J -- 否 --> J1[报错退出]
    J -- 是 --> K["加入 MAPPINGS 数组: B_IP:A_IP"]

    K --> L[后续用于生成 nginx 配置]
```

---

## 4. 生成 nginx 配置的结构图

```mermaid
flowchart TD
    A[generate_nginx_conf] --> B[写入自动生成文件头部注释]
    B --> C[写入生成时间 / 脚本版本 / 配置文件名]
    C --> D[写入当前映射表]

    D --> E[写入 map http_upgrade]
    E --> F[写入 map http_x_forwarded_proto]
    F --> G[写入 log_format cf_proxy_main]

    G --> H[遍历 MAPPINGS 数组]

    H --> I["第 i 组映射: B_i -> A_i"]
    I --> J["生成 upstream a{i}_backend"]
    J --> K["server A_i:80"]
    K --> L["keepalive 32"]

    L --> M["生成 server 块"]
    M --> N["listen B_i:80 default_server"]
    N --> O["access_log b{i}_to_a{i}_access.log"]
    O --> P["error_log b{i}_to_a{i}_error.log"]

    P --> Q[生成健康检查 location /__b_health]
    Q --> R[生成主 location /]

    R --> S["proxy_pass http://a{i}_backend"]
    S --> T["proxy_bind B_i"]
    T --> U[设置 Host / X-Real-IP / X-Forwarded-For]
    U --> V[设置 X-Forwarded-Proto]
    V --> W[设置 Cloudflare 调试头]
    W --> X[设置 WebSocket / SSE 兼容]
    X --> Y[设置超时和上传大小]
    Y --> Z[设置 Debug 响应头]

    Z --> H
```

---

## 5. 生成后的 nginx 配置抽象结构

```mermaid
classDiagram
    class GeneratedNginxConf {
        +auto_generated_header
        +map_connection_upgrade
        +map_proxy_x_forwarded_proto
        +log_format_cf_proxy_main
        +upstream_blocks[]
        +server_blocks[]
    }

    class Mapping {
        +index
        +b_ip
        +a_ip
    }

    class UpstreamBlock {
        +name: aN_backend
        +server: A_N_IP:80
        +keepalive: 32
    }

    class ServerBlock {
        +listen: B_N_IP:80
        +server_name: _
        +access_log
        +error_log
        +health_location
        +proxy_location
    }

    class ProxyLocation {
        +proxy_pass: http://aN_backend
        +proxy_bind: B_N_IP
        +Host header
        +X-Real-IP header
        +X-Forwarded-For header
        +X-Forwarded-Proto header
        +Cloudflare headers
        +WebSocket headers
        +timeout settings
        +debug headers
    }

    GeneratedNginxConf "1" --> "*" Mapping
    Mapping "1" --> "1" UpstreamBlock
    Mapping "1" --> "1" ServerBlock
    ServerBlock "1" --> "1" ProxyLocation
```

---

## 6. 实际网络转发关系图

以你的示例：

```bash
-m '10.0.0.11:203.0.113.11'
-m '10.0.0.12:203.0.113.12'
-m '10.0.0.13:203.0.113.13'
```

对应逻辑如下：

```mermaid
flowchart LR
    Client[Client 浏览器] --> CF[Cloudflare]

    CF --> B1["B 服务器入口 IP<br/>10.0.0.11:80"]
    CF --> B2["B 服务器入口 IP<br/>10.0.0.12:80"]
    CF --> B3["B 服务器入口 IP<br/>10.0.0.13:80"]

    B1 -->|proxy_bind 10.0.0.11| A1["A1 源站<br/>203.0.113.11:80"]
    B2 -->|proxy_bind 10.0.0.12| A2["A2 源站<br/>203.0.113.12:80"]
    B3 -->|proxy_bind 10.0.0.13| A3["A3 源站<br/>203.0.113.13:80"]

    A1 --> Site1[站点/应用 1]
    A2 --> Site2[站点/应用 2]
    A3 --> Site3[站点/应用 3]
```

---

## 7. 单组映射内部请求处理流程

```mermaid
sequenceDiagram
    participant C as Client
    participant CF as Cloudflare
    participant B as B反代服务器 B_i_IP
    participant N as nginx server块
    participant U as upstream a_i_backend
    participant A as A后端源站 A_i_IP

    C->>CF: HTTP/HTTPS 请求 example.com
    CF->>B: 转发请求到 B_i_IP:80
    B->>N: 命中 listen B_i_IP:80 的 server 块

    N->>N: 保留原始 Host
    N->>N: 设置 X-Real-IP
    N->>N: 设置 X-Forwarded-For
    N->>N: 设置 X-Forwarded-Proto
    N->>N: 设置 Cloudflare 调试头

    N->>U: proxy_pass http://a_i_backend
    U->>A: 连接 A_i_IP:80
    Note over N,A: proxy_bind B_i_IP<br/>B 连接 A 时源 IP 固定为 B_i_IP

    A-->>U: 返回响应
    U-->>N: upstream 响应
    N-->>B: 添加 Debug Header
    B-->>CF: 返回响应
    CF-->>C: 返回最终页面
```

---

## 8. `--dev` 模式逻辑图

```mermaid
flowchart TD
    A[用户传入 --dev] --> B[DEV_MODE=true]
    B --> C[DRY_RUN=true]
    C --> D[UPDATE_CODE=false]
    D --> E[UPDATE_CF=false]
    E --> F[RELOAD_NGINX=false]

    F --> G[解析 -m / --map-file 映射]
    G --> H[生成 nginx 配置到临时文件]
    H --> I[cat 输出配置内容]
    I --> J[删除临时文件]
    J --> K[退出]

    K -. 不执行 .-> L[不更新仓库]
    K -. 不执行 .-> M[不更新 cf_realip]
    K -. 不执行 .-> N[不写入 nginx conf]
    K -. 不执行 .-> O[不 nginx -t]
    K -. 不执行 .-> P[不 reload nginx]
```

---

## 9. 一句话总结版

```mermaid
flowchart 
    A["输入: N 组 B_IP:A_IP"] --> B[解析和校验映射]
    B --> C[生成自动注释头]
    C --> D[生成 map 和 log_format]
    D --> E["循环生成 N 个 upstream"]
    E --> F["循环生成 N 个 server"]
    F --> G{运行模式}
    G -- "--dev / --dry-run" --> H[只输出配置]
    G -- "正常模式" --> I[写入 nginx conf]
    I --> J[nginx -t]
    J --> K[nginx -s reload]
```

