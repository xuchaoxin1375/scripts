@{
    RootModule = 'TestLinks.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'f3b50f24-9ed4-48be-bfba-c5b40da348a2'
    Author = 'cxxu'
    Description = 'GitHub mirror availability testing'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Test-LinksLinearly',
        'Test-LinksParallel',
        'Test-MirrorAvailability',
        'Get-AvailableGithubMirrors'
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
