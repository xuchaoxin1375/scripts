@{
    RootModule = 'Web.psm1'
    ModuleVersion = '1.0.4'
    GUID = '69bb0442-f05f-4dac-a788-e1f2d7c93582'
    Author = 'cxxu'
    Description = 'Web module: networking, HTTP servers, nginx sites, domains and downloads (split from Tools.psm1)'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Invoke-RemoteSSH0',
        'Invoke-RemoteSSH',
        'Test-UrlOrHostAvailability',
        'Update-SSNameServers',
        'Add-SSHkeyOnHost',
        'Get-DomainUserDictFromTable',
        'Get-UrlFromMarkdownUrl',
        'Get-MainDomain',
        'Start-XpNginx',
        'Restart-XpPhpStudy',
        'Restart-Nginx',
        'Get-ProcessOfPort',
        'New-LocalSite',
        'Approve-NginxValidVhostsConf',
        'Test-IsIPAddress',
        'Get-DomainUserDictFromTableLite',
        'Get-DomainRoutesMaps',
        'Get-FileFromUrl',
        'Add-NewDomainToHosts',
        'Start-GoogleIndexSearch',
        'Start-HTTPServer',
        'Start-HTTPServerBG',
        'Get-DirectoryListing',
        'Get-MimeType'
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
