@{
    RootModule = 'Proxy.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'e62ee49c-58d2-4252-b3e4-a13d3bb340bb'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Proxy'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-ProxyEnvVarSettings',
        'Get-ProxySystemSettings',
        'Set-ProxySystemSettings',
        'Test-Proxy',
        'Set-Proxy'
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
