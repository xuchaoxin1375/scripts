@{
    RootModule = 'Sitemap.psm1'
    ModuleVersion = '1.0.4'
    GUID = '811d646d-aa2f-4c9e-b77c-d2a3349919e9'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Sitemap'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-SourceFromUrls',
        'Get-SitemapFromUrlIndex',
        'Test-SubItem',
        'Get-SitemapFromLocalFiles',
        'Get-UrlFromSitemap',
        'Get-UrlFromSitemapFile'
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
