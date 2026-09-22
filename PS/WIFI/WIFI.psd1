@{
    RootModule = 'WIFI.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'e4de022e-3334-4f39-a339-a5871312ce01'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: WIFI'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'wifi_disconnect',
        'wifiList',
        'wifiList_forceByDisconnect_SudoFirst',
        'wifi_wlan_connect',
        'wifi_wlan_reconnect_to',
        'wifi_reconnect_and_test'
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
