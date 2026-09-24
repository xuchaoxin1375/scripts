## abstract

- The repository is used to save scripts created in my daily life
- The main language of scripts is powershell.The path of the powershell scripts locates in the PS

## Installation & Deployment

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

```

Details:

更具体的说明查看此文档：[部署说明](./PS/Deploy/readme.md)

## 详情

- 中文完整文档[readme_zh.md](readme_zh.md)
- PS 模块集（67 模块）：新用户先读[文档入口地图](./PS/docs/README.md)，agent/维护者先读 [PS/AGENTS.md](./PS/AGENTS.md)，再碰代码
- 新机部署走加速镜像（默认 `gh-proxy.com`，可用列表见 `PS/TestLinks/TestLinks.psm1`，`Get-AvailableGithubMirrors` 可测速）；gitee 只留兼容，不再作为默认源（`irm|iex` 常被拦截），见 [部署指南](./PS/docs/Deploy-Guide.md)
