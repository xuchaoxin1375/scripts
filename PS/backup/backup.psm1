


function Backup-ScoopApps
{
    param (
        $outFile = "$configs\scoop_apps.json"
    )
    scoop export | Tee-Object $outFile | Out-Host -Paging
    
}
function Backup-Shortcuts
{
    param (
        $Path = '.'
    )
    $shortcuts = "$configs\Shortcuts"
    if (-not (Test-Path -Path $shortCuts))
    {
        mkdir $shortcuts
    }
    Copy-Item -Path $Path\*.lnk -Destination $shortcuts -Verbose -ErrorAction Continue
}
function Deploy-Shortcuts
{
    param (
        $Path = "$env:userprofile\desktop"
    )
    Update-PwshEnvIfNotYet
    
    Copy-Item $configs\Shortcuts\*.lnk -Destination $Path -Verbose -ErrorAction Continue
    
}

function Backup-UserConfig
{
    <# 
    .SYNOPSIS
    backup the user home .xxx files
    Be caution:only copy the .file not .dir,so the junction(symbolickLink) would not affect this operation.
    #>
    
    param(

        # $Path = "$configs\user",
        # $Destination = "$configs\user"

    )
    Update-PwshEnvIfNotYet -Mode Vars
    # Get-ChildItem $target_path
    $path = "$home\.config\"
    $Destination = "$configs\user\.config"
    Copy-Item -Path $path -Destination $Destination -Recurse -Force -Verbose 
}

function Backup-CppVscode
{
    cpFVR $env:repos\cpp\acmconsoleapps\.vscode $configs\CppVscodeConfig
}

function Backup-PicgoConfig
{
    param (
        
    )
    Write-Verbose 'for CLI part'
    cpFVR $env:picgo_CLI_config\*.json $configs\PicgoConfigs
    Write-Verbose 'for GUI part'
    cpFVR $env:picGo_Conf\data.json $configs\PicgoConfigs
}

function Backup-TyporaConf
{
    Write-Verbose 'deprecated! please considering the symlink!'
    # cpFVR $env:APPDATA\Typora\themes $configs\Typora\Themes
    # cpFVR $env:APPDATA\Typora\conf $configs\Typora\conf
}

function Backup-VsCodeSettings
{
    cpFV $env:vscodeConfHome\*.json $configs\vscodeSettings
    cpFVR $env:vscodeConfHome\snippets $configs\vscodeSettings
}
function Backup-GitConfig
{
    Update-PwshEnvIfNotYet 
    Copy-Item $env:userProfile\.gitconfig $configs\user -Verbose -Force
    
}

function Backup-WtSettings
{
    Update-PwshEnvIfNotYet -Mode Vars
    
    Copy-Item -Path $wtConf_Home\settings.json -Destination $configs\wtConf.json -Verbose 
    # hard "$configs\wtConf.json" "$wtConf_Home\settings.json"

}


function Backup-PwshProfile
{
    <# 
    .SYNOPSIS
    这个函数在只有一个盘符的计算机没有太大用处，特比是现在的系统都支持符号连接或者硬链接，这使得我们可将配置文件放到一个仓库中维护和备份


    当我们迁移到一台新设备或者重装系统后，可以使用对应的部署函数将软件的配置文件指向到配置文件所在仓库即可
    这样修改某些文件时也可以避免管理员权限的问题，修改和维护更加方便和灵活，备份和部署也是更加方便
    #>
    Copy-Item -Force -Verbose $profile.AllUsersAllHosts $env:repos\configs
}


function Backup-EnvsRegistry
{
    <# 
    .SYNOPSIS
    备份环境变量
    .DESCRIPTION
    通过导出相关注册表的方式来备份系统环境变量
    用户环境变量也可以类似的备份,但是用户的注册表是区分用户的而且用户id并不直观,例如
        Computer\HKEY_USERS\S-1-5-21-1150093504-2233723087-916622917-1001\Environment
        这个用户id在我试验的时候对应的是cxxu这个用户名
        如果确实有需要,可以在注册表regedit.exe中搜索用户环境变量独有的关键词(可以打开系统环境变量界面或者使用命令行查看当前用户设置的的环境变量,例如执行:[System.Environment]::GetEnvironmentVariables('User')
        )
    而系统级别的环境变量会相对好识别,HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment
    也可以用命令行 [System.Environment]::GetEnvironmentVariables('Machine')查看
    #>
    param (
        $Dir = ''
    )
    # Write-Verbose $env:envRegedit "`\ncontent has been set to clipborad😊"
    # Set-Clipboard $env:envRegedit
    # regedit.exe
    # 备份文件名字带有时间戳，方便我们辨别不同的备份时期（虽然我们有git备份天然具有时间属性信息，但是文件名上带有时间会更加直观）
    Update-PwshEnvIfNotYet -Mode Vars
    $fileName = "env_reg_$(Get-DateTimeNumber).reg"
    if ($Dir -eq '')
    {

        $file = "$configs\env\$fileName"
    }
    else
    {
        $file = "$Dir\$fileName"
    }
    
    reg export 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' $file
    Write-Verbose 'Done!🎈'
    Get-Content $file -Head 5
    
}

function Backup-EnvsByPwsh
{
    [CmdletBinding()]
    param(
        # 备份用户环境变量和系统环境变量选项,使用All表示都备份
        [validateset('User', 'Machine', 'All')]$Scope = 'All',
        # 将备份的环境变量文件保存到指定目录下
        $Directory = ''

    )
    <# 
    .SYNOPSIS
    备份用户环境变量和系统环境变量
    #>
    # 检查powershell 环境变量
    Update-PwshEnvIfNotYet
    
    # 获取环境变量文件保存目录目录
    if (!$Directory)
    {
        $Directory = "$configs\env"
    }
    function getEnvs
    {
        param (
            #直接访问外部函数的参数不够灵活
            $Scope 
            # $Directory
        )
        $EnvVars = [System.Environment]::GetEnvironmentVariables($Scope)
        $EnvVars = $EnvVars.GetEnumerator() | Select-Object Name, Value
        # 设置备份的数据文件名字的格式
        $EnvVarsPath = "$Directory\${Scope}@$(Get-Date -Format 'yyyy-MM-dd--HH-mm-ss').csv"
        Write-Host "Files will be saved in : $EnvVarsPath"
        # 将数据保存成csv格式的文件中
        $EnvVars | Export-Csv $EnvVarsPath
        # 查看保存结果
        # Write-Verbose $EnvVars
        if ($VerbosePreference)
        {
            # Write-Host $EnvVars
            $EnvVars
        }
    }
    # 备份环境变量
    if ($Scope -eq 'All')
    {

        getEnvs -Scope 'User'
        getEnvs -Scope 'Machine'
    }
    else
    {
        # 单次调用
        getEnvs -Scope $Scope
    }
    
}

function Backup-Links
{
    [CmdletBinding()]
    param (
        # $saveToPath = 'c:\users\cxxu\desktop\links'
        $saveToPath = "$configs\symbolic_links.ps1"
        # $deploy=$False
    )
    Update-PwshEnvIfNotYet -Mode Vars
    Write-Verbose "writing to path:$saveToPath..."
    # $buffer = Get-ChildItem | Sort-Object -Property Name | Select-Object linktype, name, target | Where-Object { $_.Target }  
    Write-Verbose 'get symbolicks...'
    $buffer = Get-Links

    # Write-Verbose 'check the buffer'
    # Write-Verbose $buffer
    # Write-Verbose "creating or reseting the file $saveTopath ..."
    # ''> $saveToPath  
    
    Write-SeparatorLine '<<'
      
    # Write-Verbose '😎:setting the row content of the target file(with header lines.)...'
    # Write-Verbose 'removing headers...'
    # (Get-Content $saveToPath | Select-Object -Skip 3 ) | Out-File -Verbose -Force $saveToPath
    # Write-Verbose 'removing top three line (header lines)...'
    # $buffer = $buffer | Format-Table -HideTableHeaders
    $buffer>$saveToPath
    
    Write-Verbose "display and check the contents of backed up file $saveToPath :"
    Get-Content $saveToPath
    Write-SeparatorLine '>>'

    Write-Host "itemsCount: $($buffer.count)"

}