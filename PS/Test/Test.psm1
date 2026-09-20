# 临时函数草稿区(用户专用):随手写、随手测,不受命名规范约束;
# 要导出给命令行用,跑 Sync-ModuleManifest Test -Reload;
# 函数转正(移到正式模块)后记得这里删掉,保持草稿区干净。
function Test-Hello
{
    param (
    )
    Write-Verbose "Hello, World!(Remember Use: Sync-ModuleManifest to sync new functions!)" -Verbose
    
}
