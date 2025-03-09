function Get-ItemMatchedPattern
{
    <#     
    .synopsis
    从指定目录开始查找具有指定名称的目录或文件。列出一般情况下用户比较感兴趣的属性
    .DESCRIPTION
    虽然本函数支持对筛选结果做排序(但是在这里面做排序并不是一个方便的做法)
    建议利用管道符将命令行传递给Sort-object 进行排序操作,可以利用powershell的补全功能指定排序的依据属性
     
    #>
    param(
        [string]$Path = '.',
        [parameter(ParameterSetName = 'Depth')]
        [int]$Depth = 0,
        # [string]$SortProperty = 'LastWriteTime', 
        [int]$First = 10,
        # [switch]$WildCard,
        [switch]$FollowSymlink,
        # [parameter(ParameterSetName = 'Recurse')]
        [switch]$Recurse,
        [switch]$Directory,
        [switch]$File 
    )

    # 检查传递进来的参数
    # $PSBoundParameters
    # 准备传递给ls的参数哈希表(注意,一定是ls可以接受的参数,而sort-object 的参数不要放在这里)
    $gciParams = @{
        Path          = $Path
        Recurse       = $Recurse
        FollowSymlink = $FollowSymlink
        File          = $File
        Directory     = $Directory
    }
    # 如果用户指定了递归搜索的层数,则将其传递给Get-ChildItem,否则认为用户不想指定层数,保持默认(仅在当前层中搜索)
    # Depth参数和Recurse参数共用时,Depth会覆盖Recurse
    if ($Depth -gt 0)
    {
        $gciParams['Depth'] = $Depth
    }
  
    # debug : $res=Get-ItemMatchedPattern-Testing @gciParams
    # return $gciParams

    # 开始查找
    Write-Host 'Start searching...'
    $res = Get-ChildItem @gciParams 
    | Sort-Object -Property $SortProperty -Descending 
    | Select-Object Name, parent,Directory, LastAccessTime, LastWriteTime

    # 进一步过滤
    if ($First)
    {
        $res = $res | Select-Object -First $First
    }

    return $res
}

# 示例调用
# Get-ItemMatchedPattern-Testing -Path '*车*' -Recurse -File -FollowSymlink


# 示例调用
# Get-ItemMatchedPattern -Path './dir1/' -Filter 'css' -Recurse -File -FollowSymlink

function Find-Directory
{
    <# 
    .SYNOPSIS 
    create by chatgpt and improved by cxxu!
    .EXAMPLE

     #>
    param(
        $dirFrom = '.',
        $Filter = ''
    )
    Get-ChildItem -Path $dirFrom -Recurse -Directory -Filter $Filter | Select-Object name, FullName
}

# test the searchString
function searchStrings
{
    <# 
    .Example
    searchStrings replace 
    searchStrings zsh -m 
    #>
    param(
        $Filter ,
        $mode = 's' 
    )
    Write-Output "options:`s` is for singleline string search; `n -m is for multilines search!"
    Write-Output "the default search mode is 's' "
    $pathPrefix = "$env:psPS\LongOrNewStrings\"

    # Write-Output $pathPrefix
    if ($mode -eq 's' -or $mode -eq '-s')
    {
        Write-Output 'you are search in singleLine strings'
        # Select-String -Path $env:psPS\LongOrNewStrings\singleLineStrings -Filter $Filter
        $pathSingle = $pathPrefix + 'singleLineStrings'
        Write-Output "😎search strings in the $pathSingle"
        Select-String -Path $pathSingle -Filter $Filter
    }
    else
    {

        Write-Output 'you are search in MultiLine strings'
        
        # -m (multiLines mode)!!!
        $pathMulti = $pathPrefix + 'multiLines\'
        Write-Output "😎😎search strings in the $pathMulti"
        
        Select-String -Path $($pathMulti + '*') -Filter $Filter
        $FilterLs = "*$Filter*" 
        Get-ChildItem $pathMulti "$FilterLs" | Get-Content 
    
    }
    
}


function search_item
{
    
    param(
        #这个参数传给ls 的-filter ,因此Filter变量也可以命名为filter,或filter_Filter
        $Filter = '',
        #指定要在哪个目录展开扫描    
        $path = '.',

        # 是否显示路径的类型,是一个开关式参数
        [switch]$PathType,
        
        #该参数可以接受ls 同样的参数[注意Filter,path两个参数比较常用,这里要放在外部单独传入]
        $args_ls = '',

        #该参数是select-object处理ls 管道传输过来的对象,常用的字段比如:FullName
        $args_select = ''
    )
    Write-Output "Filter:$Filter"

    $RelativePath = @{
        Name       = 'RelativePath';
        Expression = {
            '.' + ((Resolve-Path $_) -replace ($pwd -replace '\\', '\\'), '') 
        } 
        #这里自定义一个字段用来计算相对路径字段,这里用的是-replace,需要对正则有所了解;
        # 也可以用字符串方法定位和移除文件绝对路径的工作目录部分
    }
    #定义显示路径是文件还是文件夹的字段,比如也可以命名为FileOrDirectory,不要和参数$PathType混淆
    $Type = @{n = 'Type'; e = 
        {
            $_.PSIsContainer ? 'Directory' : 'File' 
        } 
    }
    #利用where过滤掉空字符串参数
    $fields = 'name', ($PathType ? $Type : ''), $RelativePath | Where-Object { $_ -ne '' }
    # Write-Output "[$($fields -join ',')]"
    #使用三元运算符,根据参数$args_select 是否来创建新数组,以便传递给select 筛选需要的字段
    $fields = $args_select -ne '' ? ($fields + $args_select):$fields
    "Get-ChildItem -filter $Filter -R $args_ls" | Invoke-Expression | Select-Object $fields
    

    <# 
    .SYNOPSIS
    从当前目录开始递归查找具有指定名称的文件或者目录,尽可能以紧凑表格的方式列出,允许自定义文件信息字段
    如果指定的字段过多,比如总数达到5个或更多会变成列表式(Name,type,RelativePath)始终显示;也可以用管道符`|ft`强制为表格输出
    当然可以修改代码改变这一默认行为(例如在windows下往往没有后缀名的就是文件夹,显示路径类型可能有点鸡肋,
    但是有时还是有用的,比如我们希望排序,让文件列在前面而目录在后等)
    (需要对ls返回的对象有所了解,结合select 筛选需要的字段)
    显示找到的文件的名称,以及其相对于当前工作目录的路径,可以指定更多字段,当然也支持根据字段进行排序

    有的目录或文件格式往往不要扫描,例如node_modules,可以传入 -Exclude '*node_modules*'(或者配置为默认跳过)

    本函数主要是对ls所作的一个包装,将递归扫描的结果紧凑的显示出来,并且计算了相对路径(如果从当前目录开始扫描)

    .EXAMPLE
    PS 🕰️11:31:45 PM [C:\Users\cxxu\Desktop] 🔋100% search_item -Filter *.txt -args_select basename,fullname
    Filter:*.txt

    Name     RelativePath BaseName FullName
    ----     ------------ -------- --------
    demo.txt .\demo.txt   demo     C:\Users\cxxu\Desktop\demo.txt
    .EXAMPLE
    PS 🕰️12:29:58 PM [C:\repos\scripts] 🔋100% search_item *log -args_select fullname
    Filter:*log

    Name            RelativePath           FullName
    ----            ------------           --------
    aira.log        .\aria\aira.log        C:\repos\scripts\aria\aira.log
    log             .\data\log             C:\repos\scripts\data\log
    log.log         .\data\log\log.log     C:\repos\scripts\data\log\log.log
    20221223(0).log .\Logs\20221223(0).log C:\repos\scripts\Logs\20221223(0).log
    log             .\startup\log          C:\repos\scripts\startup\log
    .EXAMPLE
    PS 🕰️12:30:03 PM [C:\repos\scripts] 🔋100% search_item *log -args_select fullname -PathType
    Filter:*log

    Name            Type      RelativePath           FullName
    ----            ----      ------------           --------
    aira.log        File      .\aria\aira.log        C:\repos\scripts\aria\aira.log
    log             Directory .\data\log             C:\repos\scripts\data\log
    log.log         File      .\data\log\log.log     C:\repos\scripts\data\log\log.log
    20221223(0).log File      .\Logs\20221223(0).log C:\repos\scripts\Logs\20221223(0).log
    log             Directory .\startup\log          C:\repos\scripts\startup\log

    .EXAMPLE
    PS 🕰️12:31:08 PM [C:\repos\scripts] 🔋100% search_item *log -args_select fullname -PathType |sort type

    Name            Type      RelativePath           FullName
    ----            ----      ------------           --------
    log             Directory .\data\log             C:\repos\scripts\data\log
    log             Directory .\startup\log          C:\repos\scripts\startup\log
    aira.log        File      .\aria\aira.log        C:\repos\scripts\aria\aira.log

    .EXAMPLE
    PS 🕰️12:31:26 PM [C:\repos\scripts] 🔋100% search_item *log -args_select fullname -args_ls "-file"
    Filter:*log

    Name            RelativePath           FullName
    ----            ------------           --------
    aira.log        .\aria\aira.log        C:\repos\scripts\aria\aira.log
    log.log         .\data\log\log.log     C:\repos\scripts\data\log\log.log
    20221223(0).log .\Logs\20221223(0).log C:\repos\scripts\Logs\20221223(0).log
    
    .EXAMPLE
    #共有5个字段,因此会变成列表式输出(可能收powershell版本影响)
    PS 🕰️12:53:58 AM [C:\repos\scripts] 🔋100% search_item *log -args_select basename,fullname -pathType
    Filter:*log

    Name         : aira.log
    Type         : File
    RelativePath : .\aria\aira.log
    BaseName     : aira
    FullName     : C:\repos\scripts\aria\aira.log

    Name         : log
    Type         : Directory
    RelativePath : .\data\log
    BaseName     : log
    FullName     : C:\repos\scripts\data\log

    .EXAMPLE
    PS 🕰️12:33:54 PM [C:\repos\scripts] 🔋100% search_item *rename* -args_select basename,fullname -PathType|ft
    Filter:*rename*

    Name                    Type      RelativePath                               BaseName           FullName
    ----                    ----      ------------                               --------           --------
    rename_prefix.data.json File      .\.mypy_cache\3.12\rename_prefix.data.json rename_prefix.data C:\repos\scripts\.mypy…
    rename_prefix.meta.json File      .\.mypy_cache\3.12\rename_pre
    #>
}


function listRecurse
{
    param(
        $path = 'd:/repos/blogs/neep'
    )
    $lst = (Get-ChildItem -Directory $path)
    $len = $lst.Length
    while ($len)
    {
        $lst | ForEach-Object {
            
            listRecurse $_
        } 
    }
}

function searchConstStrWithCatn
{
    param (
        $Filter,
        $path = '.'
    )
    Write-WorkingDir "$path"
    Write-SeparatorLine
    # todo
    # Get-ChildItem $scripts\PS\ConstantStrings -r | ForEach-Object { if ($_.ToString() -like "* $Filter * ") { Write-Output $_ catn $_ } }
    Get-ChildItem $scripts\PS\ConstantStrings -r | 
    ForEach-Object { 
        if (($_.ToString() -like "* $Filter * ") -or ( Select-String -Path $_ -Filter $Filter ) ) 
        { 
            Write-Output $_ 
            Write-SeparatorLine
            # catn 是自定义函数模仿linux cat -n 效果.
            catn $_  
            # 如果使用break,则指打印第一个满足条件的文件
            # break ;
            Write-SeparatorLine

        } 
    }
}

# function Disable-ServiceTesting
# {
#     <# 
#     .SYNOPSIS
#     # 使用管理员权限执行禁用指定服务的命令

#     #>
#     [CmdletBinding()]
#     param (
#         [Parameter( Mandatory = $true,
#             ValueFromPipelineByPropertyName = $true,
#             ParameterSetName = 'Name'
#         )]   
#         [string]$Name,

#         [Parameter( ValueFromPipeline = $true,
#             ParameterSetName = 'InputObject'
#         )]
#         [System.ServiceProcess.ServiceController]$InputObject
#     )
#     if ($PSCmdlet.ParameterSetName -eq 'Name')
#     {
#         Get-ServiceMainInfo $Name
       

#         Set-Service $Name -StartupType Disabled -Verbose -PassThru
#         Stop-Service $Name -Verbose -PassThru
#         # 如果设置成功,返回非空对象,否则返回空
        
#         if (! $?)
#         {
            
#             # 使用管道符处理,比使用Name,InputObject等参数更加方便,不用区分类型
#             Write-Host 'Try to run with sudo '
            
#             if (Test-SudoAvailability)
#             {
                
#                 # 将服务类型设置为手动,并且如果该服务正在运行,则停止运行该服务
#                 sudo pwsh -c Set-Service $Name -StartType Disabled -Verbose
#                 sudo pwsh -c Stop-Service $Name -Verbose
                
#             }
#             else
#             {
#                 Write-Error 'sudo is not available! run it with administrator privileges'
#             }
#         }

#         Get-ServiceMainInfo $Name

#     }
#     elseif ($PSCmdlet.ParameterSetName -eq 'InputObject')
#     {
#         Get-ServiceMainInfo $InputObject
        
#         Set-Service $InputObject -StartupType Disabled -Verbose -PassThru
#         Stop-Service $Inputobject -Verbose -PassThru
#         # 如果设置成功,返回非空对象,否则返回空
        
#         if (! $?)
#         {
            
#             # 使用管道符处理,比使用Name,InputObject等参数更加方便,不用区分类型
#             Write-Host 'Try to run with sudo '
            
#             if (Test-SudoAvailability)
#             {
                
#                 # 将服务类型设置为手动,并且如果该服务正在运行,则停止运行该服务
#                 sudo pwsh -c Set-Service $inputobject -StartType Disabled -Verbose
#                 sudo pwsh -c Stop-Service $InputObject -Verbose
                
#             }
#             else
#             {
#                 Write-Error 'sudo is not available! run it with administrator privileges'
#             }
#         }
#         Get-ServiceMainInfo $InputObject

#     }
# }

function Get-ServiceMainInfo
{
    param (
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Service
    )
    $res = $Service | Get-Service | Select-Object Name, DisplayName, Status, StartType -Verbose
    return $res
}

function Disable-Service
{
    <#
    .SYNOPSIS
    使用管理员权限执行禁用指定服务的命令
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(ValueFromPipeline = $true,
            ParameterSetName = 'InputObject')]
        [System.ServiceProcess.ServiceController]$InputObject
    )

    function Set-ServiceInner
    {
        param (
            [string]$ServiceName
        )

        $info = Get-ServiceMainInfo $ServiceName
        Write-Host $info

        if ($info.Status -eq 'Stopped' -and $info.StartType -eq 'Disabled')
        {
            Write-Host 'Service is already disabled and stopped!' Cyan
            return
        }

        Set-Service $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue -Verbose -Force 
        Stop-Service $ServiceName -ErrorAction SilentlyContinue -Verbose  

        if (! $?)
        {
            Write-Host 'Try to run with sudo ... '
            Write-Host '===Sudo is available===' -ForegroundColor Green
            Write-Host 'Run this Command Again in the following sudo pwsh' -ForegroundColor Magenta
            Write-Host 'Loading sudo pwsh ...' 

            if (Test-SudoAvailability)
            {
                sudo pwsh -c "& { Set-Service -Name '$ServiceName' -StartupType Disabled -Verbose }"
                sudo pwsh -c "& { Stop-Service -Name '$ServiceName' -Verbose }"
            }
            else
            {
                Write-Error 'sudo is not available! Run it with administrator privileges.'
            }
        }
        
        $res = Get-ServiceMainInfo $ServiceName
        Write-Host $res
        # return $res

        # Write-Host $res , '👺'
        # 检查设置是否成功
        $status = $res.Status
        $StartType = $res.StartType
        # Write-Host "Status=$status, StartType=$StartType"
        if ($status -ne 'Stopped' -or $StartType -ne 'Disabled')
        {
            Write-Error 'Failed to disable or stop service! Please retry it in Administrator mode.'
        }
    }

    if ($PSCmdlet.ParameterSetName -eq 'Name')
    {
        Set-ServiceInner -ServiceName $Name
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'InputObject')
    {
        Set-ServiceInner -ServiceName $InputObject.Name
    }

}

function Disable-ServiceBasic
{
    <# 
    .SYNOPSIS
    # 使用管理员权限执行禁用指定服务的命令
    .EXAMPLE
    # 使用参数
    PS C:\Users\cxxu\Desktop> Disable-Service -Service wsearch
    VERBOSE: Performing the operation "Set-Service" on target "Windows Search (wsearch)".
    VERBOSE: Performing the operation "Stop-Service" on target "Windows Search (wsearch)".

    Name    DisplayName     Status StartType
    ----    -----------     ------ ---------
    wsearch Windows Search Stopped  Disabled
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> 'wsearch'|Disable-Service
    VERBOSE: Performing the operation "Set-Service" on target "Windows Search (wsearch)".
    VERBOSE: Performing the operation "Stop-Service" on target "Windows Search (wsearch)".
    Name    DisplayName     Status StartType
    ----    -----------     ------ ---------
    wsearch Windows Search Stopped  Disabled
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> Get-Service -Name WSearch |Disable-Service
    VERBOSE: Performing the operation "Set-Service" on target "Windows Search (WSearch)".
    VERBOSE: Performing the operation "Stop-Service" on target "Windows Search (WSearch)".

    Name    DisplayName     Status StartType
    ----    -----------     ------ ---------
    WSearch Windows Search Stopped  Disabled
    .EXAMPLE
    #非管理员模式下,且sudo可用的情形
    PS C:\Users\cxxu\Desktop> Disable-Service -Service wsearch
    VERBOSE: Performing the operation "Set-Service" on target "Windows Search (wsearch)".
    Set-Service: Service 'Windows Search (wsearch)' cannot be configured due to the following error:
    Access is denied.
    VERBOSE: Performing the operation "Stop-Service" on target "Windows Search (wsearch)".
    Stop-Service: Service 'Windows Search (wsearch)' cannot be stopped due to the following error:
    Cannot open 'wsearch' service on computer '.'.
    Try to run with sudo
    Sudo is available
    Run this Command Again in the following sudo pwsh
    Loading sudo pwsh

    PowerShell 7.4.4
    PS C:\Users\cxxu\Desktop> Disable-Service -Service wsearch
    VERBOSE: Performing the operation "Set-Service" on target "Windows Search (wsearch)".
    VERBOSE: Performing the operation "Stop-Service" on target "Windows Search (wsearch)".
    Status StartType
    ------ ---------
    Stopped  Disabled
    #>
    [CmdletBinding()]
    param (
        [Parameter( 
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromPipeline = $true
        )]   
        $Service
    )
   

    $startType = $Service | Set-Service -StartupType Disabled -Verbose -PassThru
    $status = $Service | Stop-Service -Verbose -PassThru
    # 如果设置成功,返回非空对象,否则返回空
        
    if (! $?)
    {
            
        # 使用管道符处理,比使用Name,InputObject等参数更加方便,不用区分类型
        Write-Host 'Try to run with sudo '

        if (Test-SudoAvailability)
        {
            Write-Host '===Sudo is available===' -ForegroundColor Green
            Write-Host 'Run this Command Again in the following sudo pwsh' -ForegroundColor Magenta
            Write-Host 'Loading sudo pwsh' 
            sudo pwsh 
            # 将服务类型设置为手动,并且如果该服务正在运行,则停止运行该服务
            # sudo pwsh -c "$Service `| Set-Service -StartType Disabled -Verbose"
            # sudo pwsh -c "$Service `| Stop-Service -Verbose "
            
        }
        else
        {
            Write-Error 'sudo is not available! run it with administrator privileges'
            return $startType, $status
        }
    }
    # 检查操作结果
    Get-ServiceMainInfo $Service
}
