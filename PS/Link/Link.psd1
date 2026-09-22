@{
    RootModule = 'Link.psm1'
    ModuleVersion = '1.0.4'
    GUID = '7a8a2e54-6187-45fc-87b2-14336b6dd0e9'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Link'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'openLink',
        'New-HardLink',
        'New-SymbolicLink',
        'Get-Links',
        'Get-LinksInCriticalPaths'
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
