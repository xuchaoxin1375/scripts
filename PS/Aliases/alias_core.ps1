<#  这里只存放最核心的别名配置,其他普通配置请在functions,shortcuts中配置; 
普通为止需要使用ue来加载这些别名
#>
# prompt promptx
# 用于查看源代码的src命令
src Get-SourceCode
#umo Import-ModuleForce
ue Update-PwshEnvIfNotYet
Add-SSNameServers Update-SSNameServers
Get-PSHistory  Get-PSConsoleHostHistory
nlps Get-ContentNL
Set-PSRLO Set-PSReadLineOption
satjb Start-ThreadJob
touch New-File
# macOS 的 /usr/local/bin/typora 在 Typora 升级后可能是失效符号链接;别名优先于 Application,
# 目标函数由 openApps 按需自动加载,不增加启动开销
typora Start-Typora
