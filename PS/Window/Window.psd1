@{
    RootModule = 'Window.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'e94b8337-327e-4fb8-ad59-319a99e3ae72'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Window'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Show-Message'
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
