
function Format-IndexObject
{
    <# 
    .SYNOPSIS
    将数组格式化为带行号的表格,第一列为Index(如果不是可以自行select调整)，其他列为原来数组中元素对象的属性列
    .DESCRIPTION
    可以和轻量的Format-DoubleColumn互补,但是不要同时使用它们
    #>
    <# 
    .EXAMPLE
    PS> Get-EnvList -Scope User|Format-IndexObject

    Indexi Scope Name                     Value
    ------ ----- ----                     -----
        1 User  MSYS2_MINGW              C:\msys64\ucrt64\bin
        2 User  NVM_SYMLINK              C:\Program Files\nodejs
        3 User  powershell_updatecheck   LTS
        4 User  GOPATH                   C:\Users\cxxu\go
        5 User  Path                     C:\repos\scripts;...
    #>
    param (
        [parameter(ValueFromPipeline)]
        $InputObject,
        $IndexColumnName = 'Index_i'
    )
    begin
    {
        $index = 1
    }
    process
    {
        foreach ($item in $InputObject)
        {
            # $e=[PSCustomObject]@{
            #     Index = $index
           
            # }
            $item | Add-Member -MemberType NoteProperty -Name $IndexColumnName -Value $index -ErrorAction Break
            $index++
            Write-Debug "$IndexColumnName=$index"
        
            # 使用get-member查看对象结构
            # $item | Get-Member
            $item | Select-Object *
        }
    }
}

function Format-EnvItemNumber
{
    <#
    .SYNOPSIS 
    辅助函数,用于将Get-EnvList(或Get-EnvVar)的返回值转换为带行号的表格
 
     #>
    [OutputType([EnvVar[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [envvar[]] $Envvar,
        #是否显式传入Scope
        $Scope = 'Combined'
    )
    # 对数组做带序号（index）的枚举操作,经常使用此for循环
    begin
    {
        $res = @()
        $index = 1
    }
    process
    {
        # for ($i = 0; $i -lt $Envvar.Count; $i++)
        # {
        #     # 适合普通方式调用,不适合管道传参(对计数不友好,建议用foreach来遍历)
        #     Write-Debug "i=$i" #以管道传参调用本函数是会出现不正确计数,$Envvar总是只有一个元素,不同于不同传参,这里引入index变量来计数
        # } 

        foreach ($env in $Envvar)
        {
            # $env = [PSCustomObject]@{
            #     'Number' = $index 
            #     'Scope'  = $env.Scope
            #     'Name'   = $Env.Name
            #     'Value'  = $Env.Value
            # }
      
            $value = $env | Select-Object -ExpandProperty value 
            $value = $value -split ';' 
            Write-Debug "$($value.count)"
            $tb = $value | Format-DoubleColumn
            $separator = "-End OF-$index-[$($env.Name)]-------------------`n"
            Write-Debug "$env , index=$index"
            $index++
            $res += $tb + $separator
        }
    }
    end
    {
        Write-Debug "count=$($res.count)"
        return $res 
    }
}
function Format-DoubleColumn
{

    <# 
    .SYNOPSIS
    将数组格式化为双列,第一列为Index，第二列为Value,完成元素计数和展示任务
    .DESCRIPTION
    支持管道符,将数组通过管道符传递给此函数即可
    还可以进一步传递结果给Format-table做进一步格式化等操作,比如换行等操作
    #>
    <# 
    .EXAMPLE
    $array = @("Apple", "Banana", "Cherry", "Date", "Elderberry")
    $array | Format-DoubleColumn | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject
    )

    begin
    {
        $index = 1

    }

    process
    {
        # Write-Debug "InputObject Count: $($InputObject.Count)"
        # Write-Debug "InputObject:$inputObject"
        foreach ($item in $InputObject)
        {
            [PSCustomObject]@{
                Index = $index
                Value = $item
            }
            $index++
        }
    }
}
function Set-ExplorerSoftwareIcons
{
    <# 
    .SYNOPSIS
    本命令用于禁用系统Explorer默认的计算机驱动器以外的软件图标,尤其是国内的网盘类软件(百度网盘,夸克网盘,迅雷,以及许多视频类软件)
    也可以撤销禁用
    .PARAMETER Enabled
    是否允许软件设置资源管理器内的驱动器图标
    使用True表示允许
    使用False表示禁用(默认)
    .NOTES
    使用管理员权限执行此命令
    .NOTES
    如果软件是为全局用户安装的,那么还需要考虑HKLM,而不是仅仅考虑HKCU
    ls 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\'
    #>
    <# 
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True
    refresh explorer to check icons
    #禁用其他软件设置资源管理器驱动器图标
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled False
    refresh explorer to check icons
    .EXAMPLE
    显示设置过程信息
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True -Verbose
    # VERBOSE: Enabled Explorer Software Icons (allow Everyone Permission)
    refresh explorer to check icons
    .EXAMPLE
    显示设置过程信息,并且启动资源管理器查看刷新后的图标是否被禁用或恢复
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True -Verbose -RefreshExplorer
    VERBOSE: Enabled Explorer Software Icons (allow Everyone Permission)
    refresh explorer to check icons
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled False -Verbose -RefreshExplorer
    VERBOSE: Disabled Explorer Software Icons (Remove Everyone Group Permission)
    refresh explorer to check icons

    #>
    [CmdletBinding()]
    param (
        [ValidateSet('True', 'False')]$Enabled ,
        [switch]$RefreshExplorer
    )
    $pathUser = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'
    $pathMachine = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'
    function Set-PathPermission
    {
        param (
            $Path
        )
        
        $acl = Get-Acl -Path $path -ErrorAction SilentlyContinue
    
        # 禁用继承并删除所有继承的访问规则
        $acl.SetAccessRuleProtection($true, $false)
    
        # 清除所有现有的访问规则
        $acl.Access | ForEach-Object {
            # $acl.RemoveAccessRule($_) | Out-Null
            $acl.RemoveAccessRule($_) *> $null
        } 
    
    
        # 添加SYSTEM和Administrators的完全控制权限
        $identities = @('NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators')
        if ($Enabled -eq 'True')
        {
            $identities += @('Everyone')
            Write-Verbose "Enabled Explorer Software Icons [$path] (allow Everyone Permission)"
        }
        else
        {
            Write-Verbose "Disabled Explorer Software Icons [$path] (Remove Everyone Group Permission)"
        }
        foreach ($identity in $identities)
        {
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
    
        # 应用新的ACL
        Set-Acl -Path $path -AclObject $acl # -ErrorAction Stop
    }
    foreach ($path in @($pathUser, $pathMachine))
    {
        Set-PathPermission -Path $path
    }
    Write-Host 'refresh explorer to check icons'    
    if ($RefreshExplorer)
    {
        explorer.exe
    }
}
# function invoke-aria2Downloader
# {
#     param (
#         $url,
#         [Alias('spilit')]
#         $s = 16,
        
#         [Alias('max-connection-per-server')]
#         $x = 16,

#         [Alias('min-split-size')]
#         $k = '1M'
#     )
#     aria2c -s $s -x $s -k $k $url
    
# }

function Set-PythonPipSource
{
    param (
        $mirror = 'https://pypi.tuna.tsinghua.edu.cn/simple'
    )
    pip config set global.index-url $mirror
}
function Get-MsysSourceScript
{
    <# 
    .SYNOPSIS
    获取更新msys2下pacman命令的换源脚本,默认换为清华源
    
    .NOTES
    将输出的脚本复制到剪切板,然后粘贴到msys2命令行窗口中执行
    #>
    param (

    )
    $script = { sed -i 's#https\?://mirror.msys2.org/#https://mirrors.tuna.tsinghua.edu.cn/msys2/#g' /etc/pacman.d/mirrorlist* }
    
    return $script.ToString()
}
function Set-CondaSource
{
    param (
        
    )
    
    #备份旧配置,如果有的话
    if (Test-Path "$userprofile\.condarc")
    {
        Copy-Item "$userprofile\.condarc" "$userprofile\.condarc.bak"
    }
    #写入内容
    @'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch-lts: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  deepmodeling: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/
'@ >"$userprofile\.condarc"

    Write-Host 'Check your conda config...'
    conda config --show-sources
}

function Get-BeijingTime
{
    # 获取北京时间的函数
    # 通过API获取北京时间
    $url = 'http://worldtimeapi.org/api/timezone/Asia/Shanghai'
    $response = Invoke-RestMethod -Uri $url
    $beijingTime = [DateTime]$response.datetime
    return $beijingTime
}

function Sync-SystemTime
{
    <#
    .SYNOPSIS
        同步系统时间到 time.windows.com NTP 服务器。
    .DESCRIPTION
        使用 Windows 内置的 w32tm 命令同步本地系统时间到 time.windows.com。
        同步完成后，显示当前系统时间。
        w32tm 是 Windows 中用于管理和配置时间同步的命令行工具。以下是一些常用的 w32tm 命令和参数介绍：

        常用命令
        w32tm /query /status
        显示当前时间服务的状态，包括同步源、偏差等信息。
        w32tm /resync
        强制系统与配置的时间源重新同步。
        w32tm /config /manualpeerlist:"<peers>" /syncfromflags:manual /reliable:YES /update
        配置手动指定的 NTP 服务器列表（如 time.windows.com），并更新设置。
        w32tm /query /peers
        列出当前配置的时间源（NTP 服务器）。
        w32tm /stripchart /computer:<target> /dataonly
        显示与目标计算机之间的时差，类似 ping 的方式。
        注意事项
        运行某些命令可能需要管理员权限。
        确保你的网络设置允许访问 NTP 服务器。
        适用于 Windows Server 和 Windows 客户端版本。
    .NOTES
        需要管理员权限运行。
    .EXAMPLE
    # 调用函数
    # Sync-SystemTime
    #>
    try
    {
        # 配置 NTP 服务器
        w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update
        
        # 同步时间
        w32tm /resync

        # 显示当前时间
        $currentTime = Get-Date
        Write-Output "当前系统时间: $currentTime"
    }
    catch
    {
        Write-Error "无法同步时间: $_"
    }
}

function Update-SystemTime
{
    # 获取北京时间的函数
   

    # 显示当前北京时间
    $beijingTime = Get-BeijingTime
    Write-Output "当前北京时间: $beijingTime"

    # 设置本地时间为北京时间（需要管理员权限）
    # Set-Date -Date $beijingTime
}
function Update-DataJsonLastWriteTime
{
    param (
        $DataJson = $DataJson
    )
    Update-Json -Key LastWriteTime -Value (Get-Date) -DataJson $DataJson
}
function Test-DirectoryEmpty
{
    <# 
    .SYNOPSIS
    判断一个目录是否为空目录
    .PARAMETER directoryPath
    要检查的目录路径
    .PARAMETER CheckNoFile
    如果为true,递归子目录检查是否有文件
    #>
    param (
        [string]$directoryPath,
        [switch]$CheckNoFile
    )

    if (-Not (Test-Path -Path $directoryPath))
    {
        throw "The directory path '$directoryPath' does not exist."
    }
    if ($CheckNoFile)
    {

        $itemCount = (Get-ChildItem -Path $directoryPath -File -Recurse | Measure-Object).Count
    }
    else
    {
        $items = Get-ChildItem -Path $directoryPath
        $itemCount = $items.count
    }
    return $itemCount -eq 0
}
function Update-Json
{
    <# 
    .SYNOPSIS
    提供创建/修改/删除JSON文件中的配置项目的功能
    #>
    [CmdletBinding()]
    param (
        [string]$Key,
        [string]$Value,
        [switch]$Remove,
        [string][Alias('DataJson')]$Path = $DataJson
    )
    
    # 如果配置文件不存在，创建一个空的JSON文件
    if (-Not (Test-Path $Path))
    {
        Write-Verbose "Configuration file '$Path' does not exist. Creating a new one."
        $emptyConfig = @{}
        $emptyConfig | ConvertTo-Json -Depth 32 | Set-Content $Path
    }

    # 读取配置文件
    $config = Get-Content $Path | ConvertFrom-Json

    if ($Remove)
    {
        if ($config.PSObject.Properties[$Key])
        {
            $config.PSObject.Properties.Remove($Key)
            Write-Verbose "Removed '$Key' from '$Path'"
        }
        else
        {
            Write-Verbose "Key '$Key' does not exist in '$Path'"
        }
    }
    else
    {
        # 检查键是否存在，并动态添加新键
        if (-Not $config.PSObject.Properties[$Key])
        {
            $config | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
        }
        else
        {
            $config.$Key = $Value
        }
        Write-Verbose "Updated '$Key' to '$Value' in '$Path'"
    }

    # 保存配置文件
    $config | ConvertTo-Json -Depth 32 | Set-Content $Path
}

function Convert-MarkdownToHtml
{
    <#
    .SYNOPSIS
    将Markdown文件转换为HTML文件。

    .DESCRIPTION
    这个函数使用PowerShell内置的ConvertFrom-Markdown cmdlet将指定的Markdown文件转换为HTML文件。
    它可以处理单个文件或整个目录中的所有Markdown文件。

    .PARAMETER Path
    指定要转换的Markdown文件的路径或包含Markdown文件的目录路径。

    .PARAMETER OutputDirectory
    指定生成的HTML文件的输出目录。如果不指定，将在原始文件的同一位置创建HTML文件。

    .PARAMETER Recurse
    如果指定，将递归处理子目录中的Markdown文件。

    .EXAMPLE
    Convert-MarkdownToHtml -Path "C:\Documents\sample.md"
    将单个Markdown文件转换为HTML文件。

    .EXAMPLE
    Convert-MarkdownToHtml -Path "C:\Documents" -OutputDirectory "C:\Output" -Recurse
    将指定目录及其子目录中的所有Markdown文件转换为HTML文件，并将输出保存到指定目录。

    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    begin
    {
        function Convert-SingleFile
        {
            param (
                [string]$FilePath,
                [string]$OutputDir
            )

            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            $outputPath = if ($OutputDir)
            {
                Join-Path $OutputDir "$fileName.html"
            }
            else
            {
                [System.IO.Path]::ChangeExtension($FilePath, 'html')
            }

            try
            {
                $html = ConvertFrom-Markdown -Path $FilePath | Select-Object -ExpandProperty Html
                $html | Out-File -FilePath $outputPath -Encoding utf8
                Write-Verbose "Successfully converted $FilePath to $outputPath"
            }
            catch
            {
                Write-Error "Failed to convert $FilePath. Error: $_"
            }
        }
    }

    process
    {
        if (Test-Path $Path -PathType Leaf)
        {
            # 单个文件
            Convert-SingleFile -FilePath $Path -OutputDir $OutputDirectory
        }
        elseif (Test-Path $Path -PathType Container)
        {
            # 目录
            $mdFiles = Get-ChildItem -Path $Path -Filter '*.md' -Recurse:$Recurse
            foreach ($file in $mdFiles)
            {
                Convert-SingleFile -FilePath $file.FullName -OutputDir $OutputDirectory
            }
        }
        else
        {
            Write-Error "The specified path does not exist: $Path"
        }
    }
}
function Measure-AlphabeticChars
{

    <#
    .SYNOPSIS
        Counts the number of alphabetic characters in a given string or array of strings.

    .DESCRIPTION
        This function takes a string or an array of strings and counts all the alphabetic characters (A-Z, a-z) in each string.
        It supports both pipeline input and direct parameter input.

    .PARAMETER InputString
        The string or array of strings in which to count the alphabetic characters.
    #>
    <# 
.EXAMPLE
    Measure-AlphabeticChars -InputString "Hello, World!"
    Output: 10

.EXAMPLE
    "Hello, World!" | Measure-AlphabeticChars
    Output: 10

.EXAMPLE
    Measure-AlphabeticChars -InputString @("Hello, World!", "PowerShell 7")
    Output: 10
            10

.EXAMPLE
    @("Hello, World!", "PowerShell 7") | Measure-AlphabeticChars
    Output: 10
            10

.NOTES
    Author: Your Name
    Date: Today's date
    #>


    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$InputString
    )

    process
    {
        foreach ($str in $InputString)
        {
            # Use regex to find all alphabetic characters and count them
            $ms = [regex]::Matches($str, '[a-zA-Z]')
            $ms.Count
        }
    }
}
function Get-Json
{
    <#
.SYNOPSIS
    Reads a specific property from a JSON string or JSON file. If no property is specified, returns the entire JSON object.

.DESCRIPTION
    This function reads a JSON string or JSON file and extracts the value of a specified property. If no property is specified, it returns the entire JSON object.

.PARAMETER JsonInput
    The JSON string or the path to the JSON file.

.PARAMETER Property
    The path to the property whose value needs to be extracted, using dot notation for nested properties.
.EXAMPLE
从多行字符串(符合json格式)中提取JSON属性
#从文件中读取并通过管道符传递时需要使用-Raw选项,否则无法解析json
PS> cat "$home/Data.json" -Raw |Get-Json

ConnectionName IpPrompt
-------- --------
         xxx
 
PS> cat $DataJson -Raw |Get-Json -property IpPrompt
xxx

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}' -Property "name"

    This command extracts the value of the "name" property from the provided JSON string.

.EXAMPLE
    Get-Json -JsonInput "data.json" -Property "user.address.city"

    This command extracts the value of the nested "city" property from the provided JSON file.

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}'

    This command returns the entire JSON object.

.NOTES
    Author: Your Name
    Date: YYYY-MM-DD
#>

    [CmdletBinding()]
    param (
        [Parameter(   ValueFromPipeline = $true)]
        [Alias('DataJson', 'JsonFile', 'Path', 'File')]$JsonInput = $DataJson,

        [Parameter(Position = 0)]
        [string][Alias('Property')]$Key
    )

    # 读取JSON内容

    $jsonContent = if (Test-Path $JsonInput)
    {
        Get-Content -Path $JsonInput -Raw | ConvertFrom-Json
    }
    else
    {
        $JsonInput | ConvertFrom-Json
    }
    # Write-Host $jsonContent

     

    # 如果没有指定属性，则返回整个JSON对象
    if (-not $Key)
    {
        return $jsonContent
    }

    # 提取指定属性的值
    try
    {
        # TODO
        $KeyValue = $jsonContent | Select-Object -ExpandProperty $Key
        # Write-Verbose $KeyValue
        return $KeyValue
    }
    catch
    {
        Write-Error "Failed to extract the property value for '$Key'."
    }
}


function Get-JsonItemCompleter
{
    param(
        $commandName, 
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
        # $cursorPosition
    )
    if ($fakeBoundParameters.containskey('JsonInput'))
    {
        $Json = $fakeBoundParameters['JsonInput']
    
    }
    else
    {
        $Json = $DataJson
    }
    $res = Get-Content $Json | ConvertFrom-Json
    $Names = $res | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    $Names = $Names | Where-Object { $_ -like "$wordToComplete*" }
    foreach ($name in $Names)
    {
        $value = $res | Select-Object $name | Format-List | Out-String
        # $value = Get-Json -JsonInput $Json $name |Out-String
        if (! $value)
        {
            $value = 'Error:Nested property expand failed'
        }

        [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $value.ToString())
    }
}

Register-ArgumentCompleter -CommandName Get-Json -ParameterName Key -ScriptBlock ${function:Get-JsonItemCompleter}
