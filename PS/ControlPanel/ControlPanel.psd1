@{
    RootModule = 'ControlPanel.psm1'
    ModuleVersion = '1.0.4'
    GUID = '462f9996-6b27-4ff9-ae5c-e71fabd48736'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: ControlPanel'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Start-ControlPanelApplet'
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
