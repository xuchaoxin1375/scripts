Write-Host "Loading ps env(for *nix)"
$CxxuPSModulePath = "$HOME/repos/scripts/PS"
if ($env:PSModulePath -notlike "*$CxxuPSModulePath*")
{
    $env:PSModulePath += ":$CxxuPSModulePath"
}
# echo $env:PsPrompt
# Set-PsPrompt 已在 init 的步骤表里执行(含 core 变量与别名导入);此处再调一次会让启动多付约 130ms
# AutoRun commands from CxxuPsModules 04/06/2026 14:44:04
init
# PSCompletions/fnm/scoop-search 等可选组件由 init 按组件清单加载；
# 启停用 Enable-CxxuComponent/Disable-CxxuComponent（-Persist 写入 ~/.cxxu/config.psd1），不再改 profile。
# End AutoRun commands from CxxuPsModules
# argc-completions: 启动阶段不再整包注册(本机实测约 250ms),改由 init 的 Set-ArgcCompletions 负责:
# 只设 ARGC_COMPLETIONS_ROOT/PATH 与 Tab 桩,首个 Tab 才调用 Initialize-ArgcCompletions 真正注册。
# 需要改仓库位置时设 $env:ARGC_COMPLETIONS_ROOT 后重开终端;仓库更新后可手动 Initialize-ArgcCompletions -Force。
