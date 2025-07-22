
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
function Start-SqlStatement
{
    param (
        $sql
    )
    Get-MySqlDatabaseNameNative | ForEach-Object { 
        $Db = $_
        $useDbSql = "use $Db;"
        
        mysql -uroot -p"$env:MySqlKey_LOCAL" -e ($useDbSql+@'
    UPDATE wp_users SET user_pass = '$wp$2y$10$/gYloEFjcEn4OuIyRYJYi.ilYBU.SoYVsV5av.IFiOwLjpZ7s7lkK';
'@)
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
function mysqlRootLocal
{
    $cli = "mysql $mysqlPrompt -u root -p1"
    Invoke-Expression $cli

}
function mysqlLocal
{
    param (
        $userName
    )
    $cli = " mysql $mysqlPrompt -u $userName -p1"
    Invoke-Expression $cli
}
function mysqlRemote
{
    param (
        $userName,
        $p = '1'
    )
    $cli = "mysql $mysqlPrompt -u $userName -p$p"
    Invoke-Expression $cli
}
function mysqlCxxuAli
{
    $cli = " mysql $mysqlPrompt -u cxxu -h $AliCloudServerIP -p1"
    Invoke-Expression $cli
}
function mysqlRootAli
{
    param (
    )
    $cli = "  mysql $mysqlPrompt -u root -h $AliCloudServerIP -p1"
    Invoke-Expression $cli

}