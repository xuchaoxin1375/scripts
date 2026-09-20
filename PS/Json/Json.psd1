@{
    RootModule = 'Json.psm1'
    ModuleVersion = '1.0.4'
    GUID = '569c1f95-fe2c-40fc-99e0-2422ce752315'
    Author = 'cxxu'
    Description = 'JSON data file read/write/validation for module data files'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Update-DataJsonLastWriteTime',
        'Update-Json',
        'Confirm-DataJson',
        'Get-Json',
        'Get-JsonItemCompleter'
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
