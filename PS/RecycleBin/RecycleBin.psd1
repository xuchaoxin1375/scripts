@{
    RootModule = 'RecycleBin.psm1'
    ModuleVersion = '1.0.4'
    GUID = '78b6299a-7b07-44b2-8390-edab552b5287'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: RecycleBin'
    PowerShellVersion = '7.0'
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
