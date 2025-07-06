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