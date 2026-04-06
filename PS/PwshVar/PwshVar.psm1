
function Import-PwshVarFileTesting
{
    [CmdletBinding()]
    param (
        $VarFile,
        [switch]$AsPwshEnvForHomeVars 
    )
    
    Write-Host "`t$VarFile" -ForegroundColor Cyan
    $VarFilesDir = $PSScriptRoot
    $VarFileFullPath = "$VarFilesDir\${VarFile}.conf"
    
    Get-Content $VarFileFullPath | ForEach-Object {
        $line = $_.ToString()
        if (!$line.Contains('='))
        {
            $line = $line -replace '(^.*?) ', '$1='
        }
        if ($line.TrimStart() -match '^([a-zA-Z_$])')
        {
            $pair = '^\s*\$?', '$global:' 
            $line = $line -replace $pair
            $varName = $line.Split('=')[0].split(':')[1]
            Invoke-Expression $line 

        
            if ($AsPwshEnvForHomeVars)
            {
                if ($line -like '*home=*')
                { 
                  
                    
                    $value = Get-Variable -Name $varName 
                    $env:path += ";$($value.value)"     
                }
            }
        }
        else
        {
            return 
        }
        Write-Debug $line  

    }
         
}


# 将常量写在模块函数外，对于powershell v5来说不友好
# 如果需要兼容windows powershell,需要将他们移入到函数中去

# function Get-VarFilesInner
# {
 
#     return { $VarFilesDir = $PSScriptRoot
#         $PwshVarFilesFast = @(
#             'VarSet1', 
#             'VarSet2'
#             'GlobalConfig'
#         )
#         $PwshVarFilesEnhance = @(
#             'VarSet3', 
#             'VarAndroid',
#             'VarFiles'
#         )
#         $PwshVarFilesFull = $PwshVarFilesFast + $PwshVarFilesEnhance }
# }

# linux 化风格的环境变量

function Update-PwshVars
{
    [CmdletBinding()]
    param(
        [switch]$Fast,
        [switch]$Core
    )
    
    $PwshVarFilesCore = @(
        'VarSet1',
        'Varset2', 
        # 'GlobalConfig'
        ,
        'ConstantString'
    )
    $PwshVarFilesFast = @(
        'VarSet1', 
        'VarSet2'
        # ,
        'GlobalConfig'
        # ,
        'ConstantString'
    )
    $PwshVarFilesWindows = @(

        'VarSet3' 
    )
    $PwshVarFilesEnhance = @(
        'VarAndroid',
        'VarFiles'
    )
    if($IsWindows) { $PwshVarFilesEnhance += $PwshVarFilesWindows }
    $PwshVarFilesFull = $PwshVarFilesFast + $PwshVarFilesEnhance 

    # write-verbose "checking the environment of the windows system (`$env:variables)😊..." 
    Write-Verbose 'updating envs!'
    # 执行这段导入环境变量的逻辑时,不可以使用定义在环境变量文件中的变量,这会出现引用未定义变量的问题
    #注意字符串末尾没有反斜杠,拼接路径的时候需要加一个斜杠
    #🎈在需要添加新的环境变量配置文件时,只需要在PwshVarFiles中追加即可
    # 单独导入长字符串,手动声明为$global:变量

    $express = ". `"$PSScriptRoot\VarLongStrings.ps1`""
    Write-Verbose "executing $express"
    Invoke-Expression $express
    

    # $PwshVarFiles = ($Fast ) ? $PwshVarFilesFast : $PwshVarFilesFull
    if ($core)
    {
        $PwshVarFiles = $PwshVarFilesCore
    }
    elseif ($Fast)
    {
        $PwshVarFiles = $PwshVarFilesFast
    }
    else
    {
        $PwshVarFiles = $PwshVarFilesFull
    }

    # $PSVersion = $PSVersionTable.PSVersion.Major

    
    foreach ($VarFile in $PwshVarFiles) 
    {
        Write-Verbose "processing:[$VarFile]"
        Import-PwshVarFile -VarFile $VarFile # -AsPwshEnvForHomeVars
    }
    Write-Verbose 'envs updated!'
    
}

function Import-PwshVarFile
{
    <# 
    .SYNOPSIS
    从文件中加载pwsh变量,创建基本的pwsh变量环境
    .DESCRIPTION
    由于读取文件涉及到io操作,需要尽快加速此过程,可以使用.Net api 而不是powershell管用方法里读取,尤其是作为pwsh加载任务,需要尽可能高的性能
    但是,如果需要处理的文件不是很大,那么使用.Net api 反而可能更慢
    #>
    [CmdletBinding()]
    param (
        # 虽然可以使用[ValidateSet()]来指定常用的变量定义列表文件名,但是不利于维护,可以先查看Pwsh目录下的文件,然后手动指定一个文件
        # 此外,对于比较熟悉本模块的用户，完全可以直接指定文件名
        $VarFile,
        [switch]$AsPwshEnvForHomeVars 
    )
    # rvpa "$VarFilesDir\$VarFile "
    
    if ($VerbosePreference)
    {

        Write-Host "`t$VarFile" -ForegroundColor Cyan
    }
    # 变量文件存储位置
    $VarFilesDir = $PSScriptRoot + '\confs'
    $VarFileFullPath = "$VarFilesDir\${VarFile}.conf"
    Write-Debug "`t$VarFileFullPath" #-ForegroundColor yellow
    
    # 如果使用parallel处理,定义在变量列表中的变量创建顺序求无法得到保证,可能导致错误!
    # foreach ($line in [System.IO.File]::ReadLines($VarFileFullPath)){ #后面使用continue来跳过不合法的条目)
    Get-Content $VarFileFullPath | ForEach-Object { #后面使用retur来跳过不合法条目
        Write-Debug "content: $line"
        # continue
        $line = $_.ToString()
        # write-verbose $line
        #兼容不带有等号的写法(以空格分割变量名和变量值的写法);
        #这里先将其转换为等号
        if (!$line.Contains('='))
        {
            #将第一个空格替换为等号
            #无论给定的条目是否是一个合法的变量赋值语句,不影响结果的正确性
            $line = $line -replace '(^.*?) ', '$1='
            # 此时合法的条目形如：`VarName=VarValue`
        }
        #兼容不以`$`开头的配置条目(字母或下划线开头的条目),但是注意配置条目之间相互引用的顺序问题
        if ($line.TrimStart() -match '^([a-zA-Z_$])')
        {
            # 注意区别:'[^a-zA-Z_$]'这是排除指定字符的
            # write-verbose "`t"+'$global:$'+$line
            # $line = '$global:' + $line
            $pair = '^\s*\$?', '$global:' #不管条目是以$开头还是以空白字符开头,都会被匹配到,而且会被替换为$global开头
            $line = $line -replace $pair
            # 此时合法的条目形如：`$global:VarName=VarValue`
            $varName = $line.Split('=')[0].split(':')[1]
            # $VarValue = $line.Split('=')[1].trim()
            
            #以下语句形如: $global:posh5_theme_home="$posh5_home\themes"
            Invoke-Expression $line -ErrorAction SilentlyContinue 

        
            # 判断是否要进一步设置为powershell的环境变量(不会影响注册表)
            if ($AsPwshEnvForHomeVars)
            {
                if ($line -like '*home=*')
                {
                  
                    
                    $value = Get-Variable -Name $varName #得到一个psVariable对象,访问.value属性即可得到变量的值
                    $env:path += ";$($value.value)"     
                }
            }
        }
        else
        {
            # continue #(forech-object里continue,return不会直接退出)
            return 

        }
        #激活该变量
        Write-Debug $line #这时一行调试信息
             

    }
         
}


function Import-ANSIColorEnv
{
    
    <# 
    .SYNOPSIS
    向当前运行的powershell导入ANSI颜色环境变量
    .DESCRIPTION
    染色变量使用格式`${color}${text}${Reset}`中，如`${red}这是红色文本${Reset}`
    .EXAMPLE
    PS C:\Users\cxxu\Desktop>  write-Host "${BgbrightBlue}${red}这是蓝色背景红色文本${Reset}"
    这是蓝色背景红色文本
    #>
    
    Import-PwshVarFile -VarFile VarColors

    Write-Host "${Cyan}ANSI Color Environment Variables${Reset}  ${blue}Set${Reset}!"

}