
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