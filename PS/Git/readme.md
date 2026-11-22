# Git 镜像单点配置

把 GitHub 加速前缀收敛到一处：`~/.config/git/github-mirror.inc`，由全局 `includeIf` 只对
`C:\repos` 下的仓库生效。fetch 走当前测速胜出的镜像，push 仍回原站。

## 文件

| 文件 | 作用 |
| --- | --- |
| `~/.config/git/github-mirror.inc` | 当前前缀的 `insteadOf` + `pushInsteadOf`，由脚本生成，不要手工修改 |
| `~/.config/git/github-mirror.json` | 最近一次选择的来源、时间、各候选耗时与失败标记 |
| `~/.gitconfig` | `includeIf "gitdir/i:C:/repos/"` 指向上面的 `.inc` |

## 命令

| 命令 | 作用 |
| --- | --- |
| `Update-GitMirrorConfig` | 选前缀并写 `.inc`；缓存未过期时直接复用，`-Force` 强制重新测速 |
| `Get-GitMirrorStatus` | 只读查看前缀、缓存年龄、`includeIf` 与候选耗时 |
| `gitm fetch/pull/clone` | 包装入口：缓存超过 10 分钟或上次失败时先刷新，再执行 git |
| `Repair-GitMirrorRemoteUrls -WhatIf` | 把旧 remote 里的镜像前缀移除，恢复为 `https://github.com/...` |

普通 `git fetch` 不探测，直接读 `.inc` 缓存；网络型命令失败后改用 `gitm` 或
`Update-GitMirrorConfig -Force` 刷新一次。

## 选择顺序

`Update-GitMirrorConfig` 按以下顺序取前缀：

- 显式 `-Prefix`；
- `$env:PsGithubMirror`（固定值，设置后不测速）；
- 未过期的 `github-mirror.json` 缓存；
- `$env:PsGithubMirrorCandidates` 或 `TestLinks` 内置列表，取 git 传输最快者；
- 全部不可用：空前缀，直连。

候选探测只跑 `git ls-remote --heads` 计时，不测 Release/raw；文件下载仍由各自的下载函数选路。
跨域重定向的候选按不可用处理，避免把仓库路径转给未核验域名。

## 推送保护

`.inc` 里同时写入两条规则：

```gitconfig
[url "https://<当前前缀>/https://github.com/"]
    insteadOf = https://github.com/
[url "https://github.com:443/"]
    pushInsteadOf = https://github.com/
```

`pushInsteadOf` 的 base 必须是 `https://github.com:443/`，不能写成 `https://github.com/`：
同值时 Git 会把它当成无改写，push 仍回退到 `insteadOf` 指向的镜像。

已有的 `remote.*.pushurl` 如果还是 `https://github.com/...`，也会先被 `insteadOf` 改写；
把这类 pushurl 改成 `https://github.com:443/...`，或删掉后交给全局规则。

`git remote -v` 与 `git remote get-url` 显示的是 `insteadOf` 改写后的地址；查看配置原值用
`git config --get remote.origin.url`。

## 已知限制

- 私有仓库在 `C:\repos` 下也会应用镜像前缀；镜像无法获取 GitHub 凭据，通常会认证失败，不会把凭据交给第三方。
- LFS 对象是否随 `.inc` 改写未验证；有 LFS 的仓库先单独测试。
- 只扫描与改写 `RepoRoot` 一层的仓库；嵌套仓库用 `-RepoRoot` 指向具体目录。

## 卸载

```powershell
git config --global --unset-all 'includeIf.gitdir/i:C:/repos/.path'
Remove-Item ~/.config/git/github-mirror.inc, ~/.config/git/github-mirror.json
```

改过 pushurl 的仓库按原样恢复；`git remote -v` 可核对。
