@{
    RootModule = 'TerminalTools.psm1'
    ModuleVersion = '1.0.4'
    GUID = '472cae21-e54b-42dc-8def-2b58b342a9c7'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: TerminalTools'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-LatestWindowsTerminalLink',
        'Install-Scoop',
        'Push-ByScp',
        'scp_to_ali',
        'scp_from_ali',
        'Copy-ItemWithVerbose',
        'predictNo',
        'tree_pwsh',
        'tr_py',
        'mvExcludeFolder',
        'Register-PsUxLazyLoad',
        'Sync-CxxuPredictor'
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
