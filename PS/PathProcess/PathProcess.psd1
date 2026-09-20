@{
    RootModule = 'PathProcess.psm1'
    ModuleVersion = '1.0.4'
    GUID = '8a446fc7-896a-4465-9716-4e31934ec6ae'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: PathProcess'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Compress-PathDots',
        'Get-AbsPath',
        'Get-RelativePath',
        'Get-PathStyleByDotNet',
        'Get-PathStyle'
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
