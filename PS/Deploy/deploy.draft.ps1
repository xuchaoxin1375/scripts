

#使用管理员运行以下内容
#预备
$r = 'C' #一般是C盘,但允许更改
$s = 'D' #可以做必要的修改,比如E盘
$UserName = 'cxxu' #修改此值为你需要修改的用户家目录名字(一般是用户名)
$UserHome = "${r}:\users\$UserName"
$TargetUserHome = "${s}:\Users\$UserName"
$UserHomeBak = "${UserHome}.bak"
Write-Host 'check strings:', $UserName, $UserHome, $UserHomeBak, $TargetUserHome
#常用相关目录
$pf = 'Program Files'
$vscode_home = "${r}:\$pf\Microsoft VS Code"
$vscode_target_home = "${s}:\$pf\Microsoft VS Code"
$vscode_bin = "$vscode_home\bin"


#根目录部署
$items = @(
    'share',
    'repos',
    'exes',
    'Tuba'
     
)
$items | ForEach-Object {
    New-Item -ItemType SymbolicLink -Path "${r}:\$_" -Target "${s}:\$_" -Verbose -Force # -WhatIf 
}

# 家目录部署

Rename-Item -Path $UserHome -NewName $UserHomeBak
New-Item -ItemType SymbolicLink -Path $UserHome -Target $TargetUserHome



# 需要提前载入Cxxu提供的ps模块👺(否则需要手动添加vscode/bin目录到环境变量)
#部署命令行vscode,使得code <path> 命令可用
$env:PSModulePath += ';C:\repos\scripts\PS'
Add-EnvVar -EnvVar Path -NewValue $vscode_bin -Scope Machine

#部署vscode家目录
New-Item -ItemType SymbolicLink -Path $vscode_home -Target $vscode_target_home

# 使用偷懒模式的话,下面就不需要执行了 
# New-Item -ItemType SymbolicLink -Path "$userHome\.vscode" -Target "$TargetUserHome\.vscode"

#部署其他环境
$UserEnv = (Get-ChildItem $configs\env\user*)[0]
$SystemEnv = (Get-ChildItem $configs\env\system*)[0]
Deploy-EnvsByPwsh -SourceFile $UserEnv -Scope User
Deploy-EnvsByPwsh -SourceFile $SystemEnv -Scope Machine

#部署常用软件的配置
Deploy-Shortcuts
Deploy-WtSettings
Deploy-Typora
Deploy-GitConfig
# Deploy-PortableGit 如果前面调用了Deploy-EnvsByPwsh,并且备份中保存了正确的PortableGit,就不需要再使用Deploy-PortableGit语句
# 安装7z
#部署ssh
New-SSHKeyPairs