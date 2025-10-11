

function Get-PSConsoleHostHistory
{
    <# 
    .SYNOPSIS
    读取powershell上运行的历史命令行并返回
    可以配合其他过滤工具来查找命令
    .EXAMPLE
    PS> Get-PSConsoleHostHistory|sls group

    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=df_server1
    mysql --defaults-group-suffix=remote1
    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    Get-PowershellConsoleHostHistory|sls group
    Get-PSConsoleHostHistory|sls group
    .EXAMPLE
    PS> Get-PSConsoleHostHistory|sls mysql.*default |Get-ContentNL -AsString
    1:mysql --defaults-group-suffix=_remote1
    2:mysql --defaults-group-suffix=df_server1
    3:mysql --defaults-group-suffix=remote1
    4:mysql --defaults-group-suffix=_remote1
    5:mysql --defaults-group-suffix=_df_server1
    6:mysql --defaults-group-suffix=_df_server1
    7:mysql --defaults-group-suffix=_df_server1
    8:mysql --defaults-group-suffix=_df_server1
    9:mysqld --install MySQL55 --defaults-file="C:\phpstudy_pro\Extensions\MySQL5.5.29\my.ini"
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine][9:43:35][UP:3.54Days]
    PS> Get-PSConsoleHostHistory|sls mysql.*default

    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=df_server1
    mysql --defaults-group-suffix=remote1
    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=_df_server1
    #>
    $res = Get-Content $PSConsoleHostHistory
    return $res
}
function Get-MysqlDbInfo
{
    <# 
    .SYNOPSIS
    获取mysql数据库信息
    .DESCRIPTION
    默认判断数据库是否存在
    如果表存在,可以指定是否显示数据库中的表
    函数会返回查询到的结果,如果不存在,返回结果是假值
    .NOTES
    如果你不想要输出超过一定长度,那么可以配合管道符|select -First n 使用,例如n取5时,显示前5行输出
    .EXAMPLE
    询问mysql数据库中是否名为1.dex的数据库存在
    PS> Get-MysqlDbInfo 1.dex
        WARNING: Database '1.dex' Does not exist!
    .Example
    询问mysql数据库中是否名为1.fr的数据库存在,并显示其中的表(可以配合管道符|select -First n 仅显示前n行)
    #⚡️[Administrator@CXXUDESK][C:\sites\wp_sites_cxxu\2.fr\wp-content\plugins][23:13:34][UP:7.62Days]
    PS> Get-MysqlDbInfo -Name 1.fr -Server localhost -ShowTables -Verbose |select -First 5
    VERBOSE: check 1.fr database on [localhost]
    VERBOSE: mysql -h localhost -u root  -e "SHOW DATABASES LIKE '1.fr';"
    Database '1.fr' exist! ...
    VERBOSE: mysql -h localhost -u root  -e "SHOW TABLES FROM ``1.fr``;"
    VERBOSE: Show tables in 1.fr database....
    Tables_in_1.fr
    wp_actionscheduler_actions
    wp_actionscheduler_claims
    wp_actionscheduler_groups
    wp_actionscheduler_logs
    #>
    [cmdletbinding()]
    param (
        [alias('DatabaseName')]$Name,
        $Server = 'localhost',
        [Alias("P")]$Port = 3306,
        $MySQLUser = 'root',
        $key = "",
        [switch]$ShowTables
    )
    $keyInline = Get-MysqlKeyInline $key
    $db_name_inline = "'$Name'"
    $CheckDBCmd = "mysql -h $Server -P $Port -u $MySQLUser $keyInline -e `"SHOW DATABASES LIKE $db_name_inline;`""
    Write-Verbose "check [$Name] database on [$Server]"
    Write-Verbose $CheckDBCmd 
    $res = $CheckDBCmd | Invoke-Expression

    if ($res -match $Name)
    {
        Write-Host "Database '$Name' exist! ..."
        if($ShowTables)
        {
            $ShowTablesCmd = "mysql -h $Server -P $Port -u $MySQLUser $keyInline -e `"SHOW TABLES FROM ````$Name````;`""
            Write-Verbose $ShowTablesCmd 

            Write-Verbose "Show tables in $Name database...." -Verbose
            $ShowTablesCmd | Invoke-Expression
        }
    }
    else
    {
        Write-Warning "Database '$Name' Does not exist!"
      
    }
    return $res
}

function Import-MysqlFile
{
    <# 
    .SYNOPSIS
    向指定mysql服务器导入mysql文件(运行sql文件)
    
    .PARAMETER server
    写入操作对于数据库影响较大,因此此命令设计为你必须要指定主机(mysql服务器,比如本地(localhost),或则远程的某个服务)
    .PARAMETER SqlFilePath
    要导入的sql文件路径
    .PARAMETER MySqlUser
    mysql用户名,默认为root
    .PARAMETER key
    mysql密码
    你也可以不指定密码,而在mysql中配置文件(比如my.ini或my.cnf)中设置密码,实现免手动指定密码操作数据库
    默认为读取环境变量DF_MysqlKey,指定此参数时,会以你的输入为准,但是这不安全

    .PARAMETER DatabaseName
    如果你指定此参数,那么命令会认为你想要将sql文件导入到指定数据库名
    默认为"",表示你想要执行的语句(sql文件)不要求你后期指定数据库名字,
    例如,你的sql是一些查询数据库基本信息的语句,或者是创建数据库的语句,你不需要在命令行中指定一个数据库
 
    数据库名字;数据库sql导入有两大类,一类不需要指定数据库就可以直接执行的sql;一类是针对特定数据库执行的sql
    例如:
    1.某份sql中是一批数据库创建语句,那么你不需要指定某个数据库名直接就可以执行(如果要创建的数据库已经存在,mysql会提示你对应的数据库已经存在)
    2.有的sql是数据库的备份sql文件,你应该指定一个数据库名称,然后执行导入操作;
    一般而言,这两类数据库sql不能混放在同一个sql文件中

    .EXAMPLE
    Import-MysqlFile -server localhost -SqlFilePath "C:\Users\admin\Desktop\test.sql" -MySqlUser root -key "123456" -DatabaseName "test"
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\Desktop][20:50:51][UP:3.52Days]
    PS> Import-MysqlFile -server localhost -DatabaseName 6.fr -SqlFilePath C:\sites\wp_sites_cxxu\base_sqls\6.es.sql
    VERBOSE: File exist!
    cmd /c " mysql -u root -h localhost -p15a58524d3bd2e49 6.fr < `"C:\sites\wp_sites_cxxu\base_sqls\6.es.sql`" "
    mysql: [Warning] Using a password on the command line interface can be insecure.
    .NOTES
    可以配置默认导入主机和用户等信息
    导入的文件路径是必填的

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        $Server = "localhost",
        $MySqlUser = "root",
        [Alias("MySqlKey")]$key = $env:MySqlKey_LOCAL,
        [alias("File", "Path")]$SqlFilePath,
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias("Name")]$DatabaseName = "",
        [alias("P")]$Port = 3306,
        [switch]$Force
    )
    begin
    {
        
        $keyInline = Get-MysqlKeyInline $key
    }
    process
    {
   
        if(Test-Path $SqlFilePath)
        {
        
            Write-Verbose "Use Mysql server host: $Server"
            Write-Verbose "Sql File exist!" 

            # 如果数据库不存在,则提示创建数据库
            # $db_name_inline_creater = "````$DatabaseName````"
            # $db_name_inline = "'$DatabaseName'"
            # Write-Verbose "$databaseName"
            # Write-Verbose "$db_name_inline"

            # Pause

            # 查询数据库是否存在
            # $CheckDBCmd = "mysql -h $Server -u $MySQLUser $key -e `"SHOW DATABASES LIKE $db_name_inline;`""
            # $CreateDBCmd = "mysql -h $Server -u $MySQLUser $key -e `"CREATE DATABASE $db_name_inline_creater;`""
        
            # Write-Verbose $CheckDBCmd -Verbose
            # Write-Verbose $CreateDBCmd -Verbose
        
            # return 

            # $DBExists = Invoke-Expression $CheckDBCmd
            if(!$DatabaseName )
            {
                Write-Warning "You did not specify the database name!"
                # write-warning "The sql file path Leafbase name will be the default database name!"
                # $DatabaseName = Split-Path $SqlFilePath -LeafBase
            }
            # 如果用户指定了数据库名称,则检查该数据库是否已经存在,并给出测试结果;否则认为要导入的sql不需要事先指定数据库名字
            if($DatabaseName)
            {

                $DBExists = Get-MysqlDbInfo -Name $DatabaseName -Server $Server -Port $Port -MySQLUser $MySqlUser -key $key
            
                if(!$DBExists)
                {
                
                    # Write-Host "数据库不存在!"
                    if($PSCmdlet.ShouldProcess($Server, "Create Database: $DatabaseName ?"))
                    {
                    
                        # Invoke-Expression $CreateDBCmd
                        New-MysqlDB -Name $DatabaseName -Server $Server -Port $Port -MySqlUser $MySqlUser -MysqlKey $key -Confirm:$false
                    }
                }
                else
                {
                    # Get-MysqlDbDescription -Name $DatabaseName -Server $Server
                    Get-MysqlDbInfo -Name $DatabaseName -Server $Server -Port $Port -key $key -ShowTables | Select-Object -First 5
                }
            }
            # 忽略执行失败的sql,强制继续执行剩余sql(比如批量切换数据库中各个表的引擎,部分表无法顺利切换,可以利用-f跳过错误的部分)
            $ForceSql = if($Force) { "-f" } else { "" }
            $expression = "cmd /c `" mysql -h $Server -P $Port -u $MySqlUser  $keyInline $ForceSql $DatabaseName < ```"$SqlFilePath```" `""
            Write-Verbose $expression 

        
            if($Force -or -not $Confirm)
            {
                $ConfirmPreference = "None" 
                # cmd /c $expression
            }
            if($PSCmdlet.ShouldProcess($Server, $expression))
            {

                Invoke-Expression $expression
            }
        }
        else
        {
            Write-Error "Sql File $SqlFilePath not exist!"
            return $False
        }
    }
}
function Remove-MysqlDB
{
    <# 
    .SYNOPSIS
    删除指定的mysql数据库
    .DESCRIPTION
    删除指定的mysql数据库尤其是批量删除通常是一个危险操作,这里使用风险缓解的询问措施(将影响级别调整到'High',默认情况下会要求用户输入确认以继续执行相关操作)
    .EXAMPLE
    从文件中读取数据库名,并删除数据库
    $dbs=Get-DomainUserDictFromTableLite |select -ExpandProperty domain
    通过管道服务的形式,将数据库名数组中指定的数据库传递给Remove-MysqlDB命令逐个进行移除
    $dbs|Remove-MysqlDB  -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        $Server = "localhost",
        $MySqlUser = "root",
        [Alias("MySqlKey")]$key = $env:MySqlKey_LOCAL,
        [alias("P")]$Port = 3306,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias("Name")]
        $DatabaseName,
        [switch]$Force
    )
    begin
    {
        Write-Verbose "Use Mysql server host: $Server"
        Write-Verbose "start remove database $DatabaseName"
        $keyInline = Get-MysqlKeyInline $key
    }
    process
    {

        # DROP DATABASE [IF EXISTS] database_name;
        $command = " mysql -u$MySqlUser -h $Server -P $Port $keyInline -e 'DROP DATABASE IF EXISTS ``$DatabaseName`` ; ' "  
        Write-Verbose $command 
        if($Force -and -not $Confirm)
        {
            $ConfirmPreference = "None"
        }
        if($PSCmdlet.ShouldProcess($DatabaseName, "Remove Database $DatabaseName ?"))
        {
            
            # 将mysql的执行输出丢弃
            Invoke-Expression $command *> $null
            
        }
        Write-Verbose "Database $DatabaseName has been tried to be removed!" -Verbose
        Get-MysqlDbInfo -Name $DatabaseName -Server $Server -Port $Port -key $key
    }
    
}
function Remove-MysqlIsolatedDB
{
    <# 
    .SYNOPSIS
  网站根目录不存在的网站配套的mysql数据库删除
  这是一个专用函数,针对本地wp等批量建站工具链的一个清理工具(数据库用户和密码无需填写,但是需要配置数据库默认行为或者调用的remove-mysqldb命令行的默认参数)
  .NOTES
  这是一个特定专用函数
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $SitesDir = $my_wp_sites
    )
    $domains = Get-DomainUserDictFromTableLite | Select-Object -ExpandProperty domain
    $toBeRemoveNames = [System.Collections.Generic.List[string]]::new()
    # 检查对应网站根目录是否存在
    foreach ($domain in $domains)
    {
        $site_root = "$SitesDir/$domain"
        if(Test-Path $site_root)
        {
            Write-Host "网站根目录存在: $site_root"
        }
        else
        {
            <# Action when all if and elseif conditions are false #>
            Write-Host "网站根目录不存在: $site_root,将被移除同名数据库"
            $toBeRemoveNames.Add($domain)
        }
    }
    $toBeRemoveNames | Remove-MysqlDB 
}
function Export-MysqlFile
{
    <# 
    .synopsis
    导出mysql数据库到文件
    .DESCRIPTION
    #>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias('Name')]$DatabaseName,    
        $OutputDir = $base_sqls,
        $SqlFilePath = "$OutputDir/$DatabaseName.sql",

        $Server = "localhost",
        [alias("P")]$Port = 3306,
        $MySqlUser = "root",
        $key = $env:MySqlKey_LOCAL,
        [switch]$Force,
        # 默认执行备份,使用此选项禁用备份
        [switch]$Backup

    )
    begin
    { 
        Write-Verbose "Use Mysql server host: $Server"
        Write-Verbose "Start Export database $DatabaseName "
    }
    process
    {
        if(Test-Path $SqlFilePath)
        {
            Write-Warning "File already exist!New files will override the old ones!"
            if($Backup)
            {
                # 执行备份
                Write-Verbose "try to rename the old file!(as .bak);" -Verbose

                Rename-Item $SqlFilePath "$SqlFilePath.bak.$(Get-Date -Format 'yyyyMMdd-hhmmss')" -Force:$Force -Verbose
                # try
                # {
                Write-Verbose "The old file has been renamed to $SqlFilePath.bak" -Verbose
                # }
                # catch
                # {
                #     Write-Warning "Failed to rename the old file!(because the $SqlFilePath.bak is also already exist !)"
                #     Write-Warning "Please check and move the file path or delete the old file manually if it will no longer be used."
                #     return
                # }
            }
        }
        Write-Warning "key: [$key](before)"
        $key = Get-MysqlKeyInline $key
        Write-Warning "key: [$key](after)"
        $expression = "mysqldump   -h $Server -P $Port -u $MySqlUser $key '$DatabaseName' > $SqlFilePath "
        Write-Verbose $expression
        Invoke-Expression $expression
    }
}

function Get-MySqlDatabaseNameDotNet
{
    <#
.SYNOPSIS
    连接到指定的 MySQL 服务器并获取所有数据库的名称列表。
    

.DESCRIPTION
    此脚本通过使用 MySql.Data .NET 连接器，建立与 MySQL 数据库服务器的安全连接。
    成功连接后，它会执行一个查询来检索服务器上所有现有数据库的名称，并将结果输出到 PowerShell 控制台。
    脚本会自动处理连接的打开和关闭，以确保资源被正确管理。

.PARAMETER Server
    指定要连接的 MySQL 服务器的主机名或 IP 地址。
    例如："localhost", "192.168.1.100"。

.PARAMETER User
    用于登录 MySQL 服务器的用户名。

.PARAMETER Password
    与指定用户关联的密码。为了安全起见，建议使用安全字符串 (SecureString)。

.PARAMETER Port
    可选参数。指定 MySQL 服务器正在监听的端口。默认值为 3306。

.PARAMETER MySqlConnectorPath
    可选参数。指定 MySql.Data.dll 文件的完整路径。如果 DLL 文件位于标准模块路径或 GAC 中，则此参数不是必需的。
    默认值为 "C:\mysql-connector\MySql.Data.dll"。

.EXAMPLE
    PS C:\> Get-MySqlDatabaseNameDotNet -Server "localhost" -User "root" -Password "your_password"

    说明:
    使用用户名 "root" 和密码 "your_password" 连接到本地 MySQL 服务器，并列出所有数据库的名称。

.EXAMPLE
    PS C:\> $secpass = Read-Host -AsSecureString -Prompt "请输入 MySQL 密码"
    PS C:\> Get-MySqlDatabaseNameDotNet -Server "db.example.com" -User "admin" -Password $secpass -Port 3307

    说明:
    首先，通过 Read-Host 安全地提示用户输入密码。
    然后，使用该密码连接到位于 "db.example.com" 的 MySQL 服务器（端口为 3307），并获取数据库列表。

.OUTPUTS
    [string[]]
    返回一个字符串数组，其中每个字符串都是一个数据库的名称。

.NOTES
    要求: 需要 .NET Framework 和 MySql.Data .NET 连接器。
#>

    [CmdletBinding()]
    param(
        # [Parameter(Mandatory=$true)]
        [string]$Server = 'localhost',

        # [Parameter(Mandatory=$true)]
        [string]$User = 'root',

        # [Parameter(Mandatory=$true)]
        [PSObject]$Password = $env:MySqlKey_LOCAL,

        [Parameter(Mandatory = $false)]
        [uint32]$Port = 3306,

        [Parameter(Mandatory = $false)]
        [string]$MySqlConnectorPath = "C:\Program Files (x86)\MySQL\MySQL Connector NET 9.3\MySql.Data.dll"
    )

    try
    {
        # 加载 MySQL Connector/NET 程序集
        Add-Type -Path $MySqlConnectorPath

        # 将密码从 SecureString 转换为普通字符串（如果需要）
        $plainPassword = if ($Password -is [System.Security.SecureString])
        {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        else
        {
            $Password
        }

        # 构建连接字符串
        $connectionString = "Server=$Server;Port=$Port;Database=mysql;Uid=$User;Pwd=$plainPassword;"

        # 创建 MySQL 连接对象
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)

        # 打开连接
        $connection.Open()

        # 创建命令对象
        $command = $connection.CreateCommand()
        $command.CommandText = "SHOW DATABASES;"

        # 执行查询并获取结果
        $reader = $command.ExecuteReader()

        # 创建一个列表来存储数据库名称
        $databaseNames = [System.Collections.Generic.List[string]]::new()

        Write-Verbose "正在读取数据库列表..."
        while ($reader.Read())
        {
            $databaseNames.Add($reader.GetString(0))
        }

        # 输出结果
        return $databaseNames
    }
    catch
    {
        # 捕获并显示任何错误信息
        Write-Error "发生错误: $($_.Exception.Message)"
    }
    finally
    {
        # 确保无论成功与否都关闭连接
        if ($connection -and $connection.State -eq 'Open')
        {
            $connection.Close()
            Write-Verbose "数据库连接已关闭。"
        }
    }
}

function Get-MySqlDatabaseNameNative
{
    <#
.SYNOPSIS
    通过调用 mysql.exe 命令行工具来获取所有数据库的名称。

.DESCRIPTION
    此函数直接执行本地安装的 mysql.exe 客户端，运行 "SHOW DATABASES;" 命令。
    它通过特定的命令行参数来获取一个没有表头和边框的纯净列表。
    然后，PowerShell 会处理这个原始输出，过滤掉任何空行，最终返回一个干净的数据库名称数组。
    此方法不依赖任何外部 PowerShell 模块或 .NET DLL，但要求 mysql.exe 必须存在于系统中。

.PARAMETER User
    必需参数。用于登录 MySQL 服务器的用户名。

.PARAMETER Password
    必需参数。与指定用户关联的密码。为了安全，建议传入 SecureString 对象。

.PARAMETER Server
    可选参数。指定要连接的 MySQL 服务器的主机名或 IP 地址。默认为 "localhost"。

.PARAMETER Port
    可选参数。MySQL 服务器的端口。默认值为 3306。

.PARAMETER MySqlCliPath
    可选参数。指定 mysql.exe 文件的完整路径。如果 mysql.exe 不在系统的 PATH 环境变量中，则此参数是必需的。
    请根据你的实际安装路径进行修改。
.Notes
    mysql自带的几个数据库(一般为4个),在批处理时通常要跳过它们,避免不当的改动:

        information_schema
        mysql
        performance_schema
        sys

.EXAMPLE
    PS C:\> Get-MySqlDatabaseName-Cli -User "root" -Password "your_password"

    说明:
    使用默认路径的 mysql.exe 连接到本地服务器，并列出所有数据库。

.EXAMPLE
    PS C:\> $secpass = Read-Host -AsSecureString -Prompt "请输入 MySQL 密码"
    PS C:\> Get-MySqlDatabaseName-Cli -User "admin" -Password $secpass -Server "db.example.com" -MySqlCliPath "C:\Program Files\MySQL\MySQL Workbench 8.0 CE\mysql.exe"

    说明:
    安全地输入密码，然后使用指定路径的 mysql.exe 连接到远程服务器，并获取数据库列表。

.OUTPUTS
    [string[]]
    返回一个字符串数组，其中每个字符串都是一个数据库的名称。

.NOTES
    依赖: 必须在本地安装 MySQL 命令行客户端 (mysql.exe)。
#>
    [CmdletBinding()]
    param(
        [string]$User = 'root',

        [PSObject]$Password = $env:MySqlKey_LOCAL,

        [Parameter(Mandatory = $false)]
        [string]$Server = "localhost",

        [Parameter(Mandatory = $false)]
        [uint32]$Port = 3306,

        [Parameter(Mandatory = $false)]
        [string]$MySqlCliPath = "",
        #是否包含系统数据库(自带的数据库)
        [switch]$All
    )

    # 检查 mysql.exe 是否存在
    if ($MySqlCliPath -and -not (Test-Path $MySqlCliPath -PathType Leaf))
    {
        Write-Error "错误: 未在指定路径找到 mysql.exe。请通过 -MySqlCliPath 参数提供正确的路径。"
        return
    }
    else
    {
        $MySqlCliPath = if ($MySqlCliPath) { $MySqlCliPath } else { "mysql.exe" }
    }

    # 将 SecureString 密码转换为纯文本以供命令行使用
    $plainPassword = if ($Password -is [System.Security.SecureString])
    {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    else
    {
        $Password
    }

    # 构建 mysql.exe 的参数列表
    # -N, --skip-column-names: 不输出列名（表头）
    # -B, --batch: 输出更干净的、以制表符分隔的格式，没有边框
    $arguments = @(
        "--host=$Server",
        "--port=$Port",
        "--user=$User",
        "--password=$plainPassword", # 注意: 密码直接跟在 --password= 后面
        "-N",
        "-B",
        "--execute='SHOW DATABASES;'"
        # "--execute=SHOW DATABASES;"
    )

    try
    {
        # 使用 '&' 调用操作符执行命令并捕获标准输出
        # `2>&1` 会将错误流重定向到成功流，以便一并捕获
        Write-Verbose "正在执行: $MySqlCliPath $arguments"
        $rawOutput = "$MySqlCliPath $($arguments -join ' ')" | Invoke-Expression
        # $rawOutput = & $MySqlCliPath $arguments 2>&1

        # 检查进程是否成功执行。$LASTEXITCODE 为 0 表示成功
        if ($LASTEXITCODE -ne 0)
        {
            # 如果 mysql.exe 返回错误，则 $rawOutput 包含错误信息
            throw "MySQL 命令行工具返回错误: $($rawOutput -join "`n")"
        }

        # 提炼输出：过滤掉可能的空行或空白行
        $databaseNames = $rawOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if(!$All)
        {
            $databaseNames = $databaseNames | Where-Object { $_ -notmatch "^(information_schema|mysql|performance_schema|sys)$" }
        }
        return $databaseNames
    }
    catch
    {
        Write-Error $_.Exception.Message
        return $null
    }
}

function Get-MysqlTablesList
{
    <# 
    .SYNOPSIS
    获取mysql数据库表列表
    .DESCRIPTION
    通过mysql命令行工具获取数据库表列表
    支持管道符输入数据库名字,此命令查询给定的数据库中的表列表

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$Server = "localhost",
        [Parameter(Mandatory = $false)]
        [string]$UserName = "root",

        [psobject]$Password = $env:MySqlKey_LOCAL,
        [Parameter(Mandatory = $false)]
        [string]$Port = 3306
    )

    begin
    {
        Write-Verbose "list tables in databases " -Verbose
    }
    process
    {
        $tables = mysql -h $Server -u $UserName -p"$Password" -P $Port -e "use $DatabaseName;show tables" -N -B
        return $tables
    }
}

function Start-MySqlStatementForAllDatabasesTemplate
{
    <# 
    .SYNOPSIS
    批量地为多个数据库批量执行一段sql指令
    .DESCRIPTION
    比如读取本地mysql数据库中所有数据库,然后对这些数据执行同一段sql语句的模板
    .NOTES
    注意参数sql语句比较复杂的时候,建议使用多行字符串
    此外,虽然此函数支持链接远程数据库进行批量操作,但是操作效率低,比本地数据库慢得多
    因为实现方式是遍历所有mysql数据库(比如每个站点的数据库列出),然后逐个利用mysql -e选项执行sql语句,
    这意味着每操作一个数据库,就要连接一次数据库
    因此,通常建议如果要操作服务器上的数据库,则建议在服务器上编写相应的脚本批量操作效率更高

    或者读取原码,替换...为你要执行的sql语句,可以使用@''@包裹多行sql
    +@'
        ....
    '@
    .EXAMPLE
    本地数据库(免密登录直接执行sql语句)
    不给任何参数时,尝试本地免密登录mysql并执行show tables;语句
    Start-MySqlStatementForAllDatabasesTemplate 
    也可以简单追加-Sql指定要执行的sql语句
    .EXAMPLE
    本地数据库(完整参数输入)
    Start-MySqlStatementForAllDatabasesTemplate -Server localhost -MysqlUser root -Mysqlkey $env:MySqlKey_LOCAL -Sql @'
    select * from wp_options WHERE option_name LIKE 'woocommerce_flat_rate_%_settings';
'@
    .EXAMPLE
    远程数据库(完整参数输入)
     Start-MySqlStatementForAllDatabasesTemplate -Server $env:DF_SERVER -MysqlUser rootx -Mysqlkey $env:MySqlKey_DF2  -Sql @'
select * from wp_options WHERE option_name LIKE 'woocommerce_flat_rate_%_settings';
'@
    #>
    param (
        $Server = "localhost",
        $MysqlUser = "root",
        $Mysqlkey = $env:MySqlKey_LOCAL,
        $Port = 3306,
        $Sql='show tables;'
    )
    $dbs = Get-MySqlDatabaseNameNative -Server $Server -User $MysqlUser -Password $Mysqlkey -Port $Port

    $key = Get-MysqlKeyInline $Mysqlkey
    $dbs | ForEach-Object { 
        $Db = $_
        Write-Host "Querying database [$Db]" -ForegroundColor Cyan

        $useDbSql = "use $Db; "
        mysql -u $MysqlUser -h $Server $key -P $Port -e $($useDbSql + $Sql)
        # Write-Host $cmd
    }

}
function Get-MySqlDatabaseNameCmdlet-Deprecated
{
    <#
    .SYNOPSIS
        使用 MySqlCmdlets 模块连接到 MySQL 服务器并获取所有数据库的名称。
        文档尚未研究,credential不熟练,暂时弃用
    .DESCRIPTION
        此函数利用 PowerShell Gallery 中的 MySqlCmdlets 模块来简化与 MySQL 的交互。
        它负责建立连接，执行 "SHOW DATABASES;" 查询，返回数据库名称列表，并自动关闭连接。
        这种方法的好处是模块管理器会自动处理底层驱动程序的依赖，用户无需手动管理 DLL 文件。

    .PARAMETER Server
        指定要连接的 MySQL 服务器的主机名或 IP 地址。

    .PARAMETER User
        用于登录 MySQL 服务器的用户名。

    .PARAMETER Password
        与指定用户关联的密码。为了安全，建议传入 SecureString。

    .PARAMETER Port
        可选参数。MySQL 服务器的端口。默认值为 3306。

    .EXAMPLE
        PS C:\> Get-MySqlDatabaseName-Modern -Server "localhost" -User "root" -Password "your_password"
        说明:
        连接到本地 MySQL 服务器并列出所有数据库的名称。

    .EXAMPLE
        PS C:\> $secpass = Read-Host -AsSecureString -Prompt "请输入 MySQL 密码"
        PS C:\> Get-MySqlDatabaseName-Modern -Server "db.example.com" -User "admin" -Password $secpass -Port 3307
        说明:
        安全地提示用户输入密码，然后使用该密码连接到远程服务器的指定端口，并获取数据库列表。

    .OUTPUTS
        [string[]]
        返回一个字符串数组，其中每个字符串都是一个数据库的名称。

    .NOTES
        依赖: 需要通过 Install-Module 安装 MySqlCmdlets 模块。
    #>

    [CmdletBinding()]
    param(
        [string]$Server = 'localhost',
        [string]$User = 'root',
        [PSObject]$Password = $env:MySqlKey_LOCAL,
        [uint32]$Port = 3306
    )

    # 确保 MySqlCmdlets 模块已安装
    if (-not (Get-Module -ListAvailable -Name MySqlCmdlets))
    {
        Write-Error "请先安装 MySqlCmdlets 模块: Install-Module -Name MySqlCmdlets -Repository PSGallery"
        return @()
    }

    # 构建凭据对象
    $credential = New-Object System.Management.Automation.PSCredential($User, $Password)

    try
    {
        # 定义查询语句
        $query = "SHOW DATABASES;"

        # 使用模块提供的命令执行查询（推荐使用参数化方式）
        $result = Invoke-MySql -Server $Server -Port $Port -Credential $credential -Query $query

        # 提取第一列（数据库名称）并返回数组
        $databaseNames = $result | ForEach-Object { $_.ItemArray[0] }

        return @($databaseNames)
    }
    catch
    {
        Write-Error "执行 MySQL 查询时出错: $($_.Exception.Message)"
        return @()
    }
}
function Start-MysqlConnectionFromConfig
{
    <# 
    .SYNOPSIS
    mysql命令行引用配置文件(my.ini或my.cnf)中的对应链接配置
    此函数作为mysql命令行的简写包装
    .DESCRIPTION
    通过参数 --defaults-group-suffix=_df_server1 指定配置文件的组名，从而引用配置文件中的对应链接配置

    .NOTES
    配置示例:
    假设你的mysql配置中存在名为...df1组(以df1结尾的组名)
    比如:(通常以client-或client_作为组名的开头,前者是推荐的,完整的组名放在中括号[]中)
    [client_df1]
    host=192.168.x.x
    user=yourusername
    password="yourpassword"
    port=yourportnumber

    则可以通过如下命令引用配置文件中的链接配置:
    Start-MysqlConnectionFromConfig df1

    .EXAMPLE
    PS> Start-MysqlConnectionFromConfig df1
    Welcome to the MySQL monitor.  Commands end with ; or \g.

    #>
    param(
        [Parameter(Mandatory = $true)]
        $GroupSuffix
    )
    $GroupSuffix = $GroupSuffix.TrimStart('-')
    $cmd = "mysql --defaults-group-suffix=-$GroupSuffix"
    Write-Debug "Executing command: $cmd" -Debug
    $cmd | Invoke-Expression
}



