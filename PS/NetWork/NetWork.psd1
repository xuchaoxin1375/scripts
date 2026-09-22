@{
    RootModule = 'NetWork.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'c94f5682-ac5f-46b1-929a-b6468fcbef25'
    Author = 'cxxu'
    Description = '网络发现/共享 + 连通性/IP网卡/图床上传'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Set-NetworkDiscovery',
        'Set-NetworkFileAndPrinterSharing',
        'Get-SmbSessionMainInfo',
        'pushToAndroid',
        'upload_pubKey',
        'https3w_start',
        'Set-HostsFile',
        'NetWorkAccessbility',
        'curlBD',
        'pingBD',
        'pingGG',
        'uploadPicMarkdown',
        'Get-IPAddressMainInfo',
        'Get-IPAddressOfPhysicalAdapter',
        'Get-NetAdapterMainInfo',
        'code_proxy'
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
