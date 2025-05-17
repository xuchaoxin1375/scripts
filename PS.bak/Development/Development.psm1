

function EggNew
{
    param (
        $projectDir = "new_egg_$(Get-Date)"
    )
    # 检查目录存在性,以及判空(judgePath/judgeFile/judgeDir)
    if ( Test-Path $projectDir)
    {
        Write-Output "directory already exist, now Set-Location to the directory:$projectDir"
        $itemList = Get-ChildItem $projectDir
        if ($itemList.count -eq 0)
        {
            Set-Location $projectDir
        }
        else
        {
            Write-Output "this folder:$projectDir is not empty, it is adviced to initial eggProject with a new(or empty) folder.returning..."
            return
        }
    }
    else
    {
        New-Item -ItemType Directory $projectDir
        Set-Location $projectDir
    }
    # mkdir $projectDir
    # Set-Location $projectDir
    Write-Output "@😎😎😎creating new egg project in $pwd"
    yarnNode create egg --type=simple
    yarnNode install
    Get-ChildItem
}
function  dj_start_proj
{
    param (
    )
    django-admin.exe startproject $1 $2
    Write-Output $args
}
function env_django2
{
    <# 
    .synopsis
    不切换目录的情况下,快捷开关虚拟环境
    以下代码针对于我本地的django2虚拟环境
    .example
     env_django2 -status on
    #>
    param(
        $venvPath_opt = "$env:pyEnvs\Django2\scripts",
        $status = 'on'
    )
    # 必须在虚拟环境目录下激活才能达到目的(简单设置active文件的别名将会闪退)
    Set-Location $venvPath_opt
    if ($status -eq 'on')
    {
        ./activate
    }
    else
    {
        'try to deactivate the env!'
        deactivate
        'done!'
    }
    # 进入到active所在目录,才可以正确在当前终端正确激活/关闭虚拟环境
    # 激活/关闭虚拟环境后,返回到原来的工作目录中.
    Set-Location -
}

function env_django4
{
    param(
        $status = 'on'
    )
    # Invoke-Expression "$ll_env\scripts\activate"
    # Set-Location $ll_env\scripts
    Set-Location "$DjangoVenvs\django4\scripts"
    if ($status -eq 'on')
    {
        Get-Location
        Write-Output 'try to active the django4 environment...'
        ./activate
        Write-Output 'done!'
    }
    else
    {
        'try to deactivate the env!'
        # ./deactivate
        deactivate
        'done!'
    }
    Set-Location -  
    # 激活虚拟环境需要到虚拟环境所在根目录下执行,故而先做目录切换
    # ./activate

}

function pmg
{
    param(
        $cmd = '',
        $p1 = '',
        $p2 = '',
        $p3 = '',
        $p4 = ''

    )
    py manage.py $cmd $p1 $p2 $p3 $p4 
}
function sqlmigrate
{
    param(
        $appName,
        $migration
    )
    pmg sqlmigrate $appName $migration
}
function showmigrations
{
    param(
        $parameter = ''
    )
    pmg showmigrations $parameter
}
function pmgmk
{
    param (
        $parameter = ''
    )
    pmg makemigrations $parameter
    
}
function pmgmi
{
    param (
        $parameter
    )
    pmg migrate $parameter
}

function Django_env_Home
{
    param (
        
    )
    Set-Location "$repos\PythonLearn\Django_env"
}
function runserver_jango
{
    if (Test-Path 'manage.py')
    {
        
        py manage.py runserver
    }
    else
    {
        Write-Output 'please set-location correctly!'
    }
}
function startapp
{
    param(
        $name
    )
    django-admin.exe startapp $name
}

function cxxuAli_update_alias_envs_vimrc
{
    $pwdir = Get-Location
    linuxShellScripts_
    scp_to_ali -source .\envs.sh -tarGet-ProcessPath_opt ~/linuxShellScripts
    scp_to_ali -source .\alias*.sh -tarGet-ProcessPath_opt ~/linuxShellScripts       
    
    scp_to_ali -source .\.zshrc -tarGet-ProcessPath_opt ~
    scp_to_ali -source .\.vimrc -tarGet-ProcessPath_opt ~
    Set-Location $pwdir
    
}

function CxxuAli { ssh cxxu@$AliCloudServerIP }
function rootAli { ssh root@$AliCloudServerIP }
# function catn_old
# {
#     <# 
#     .Synopsis
#     Mimic Unic / Linux tool nl number lines
   
#     .Description
#     Print file content with numbered lines no original nl options supported
   
#     .Example
#      nl .\food.txt
#     #>
#     param (
#         [parameter(mandatory = $true, Position = 0)]
#         [String]$FileName
#     )

#     process
#     {
#         If (Test-Path $FileName)
#         {
#             # core logic for the function
#             # 关键在于格式化'{0,5} {1}' -f
#             Get-Content $FileName | ForEach-Object { '{0,-5} {1}' -f $_.ReadCount, $_ }
#         }
#     }
# }


function removeLF
{
    <# 移除换行(remove line feed) #>
    param(
        [Parameter(ValueFromPipeline)]
        [String]
        $content = 'Noting!'
    )
    process
    {
        $content -replace '\n|\r', '' | Set-Clipboard 
        return Get-Clipboard
    }
}
function removeSpace
{
    <# 移除空白字符(remove spaces)
    输出并自动复制到截切板中 #>
    param(
        [Parameter(ValueFromPipeline)]
        [String]
        $content = 'Noting!'
    )
    process
    {
        $content -replace '\s*', '' | Set-Clipboard
        return  Get-Clipboard
    }
}
function removeSpaceLF
{
    # removeSpace|removeLF
    <# 移除空白字符和换行符(remove space and line feed)
    输出并自动复制到截切板中 #>
    param(
        [Parameter(ValueFromPipeline)]
        [String]
        $content = 'Noting!'
    )
    process
    {
        $content -replace '\s*|(\n|\r)', '' | Set-Clipboard
        return  Get-Clipboard
    }
}

function navicat_reset_try
{
    Invoke-Expression "$scripts\software_crack_scripts\reset_navicat_try.bat"
}
function tomcat_restart
{
    tomcatshutdown
    tomcat
}
function wmqtt
{
    java -jar $env:wmqtt/wmqttSample.jar
}
# function antlr4
# {
#     param(
#         # [String[]]$params
#         $p1 = '',
#         $p2 = '',
#         $p3 = ''
#     )
#     # java -jar C:\antlr4.jar $params

#     java -jar C:\antlr4.jar $p1 $p2 $p3
# }
#  set proxy for pwsh
