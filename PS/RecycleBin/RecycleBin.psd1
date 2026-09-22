@{
    RootModule = 'RecycleBin.psm1'
    ModuleVersion = '1.0.4'
    GUID = '78b6299a-7b07-44b2-8390-edab552b5287'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: RecycleBin'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-RecycleBin',
        'Move-ToRecycleBinDir',
        'Move-ItemWithTimestampIfNeed',
        'Clear-RecycleBinDir',
        'Move-ToRecycleBin'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CxxuPsModules')
            ProjectUri = 'https://github.com/xuchaoxin1375/scripts'
        }
    }
}
