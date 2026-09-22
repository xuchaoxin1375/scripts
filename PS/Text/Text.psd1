@{
    RootModule = 'Text.psm1'
    ModuleVersion = '1.0.4'
    GUID = '0bde055e-d5aa-48b1-bf27-332b9b221194'
    Author = 'cxxu'
    Description = 'Text module: text, encoding, markdown and formatting helpers (split from Tools.psm1)'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-LineDataFromMultilineString',
        'Get-DictView',
        'Remove-TitleOrderFromMarkdownTitle',
        'Rename-FileName',
        'Format-FileSize',
        'Get-CharacterEncoding',
        'Get-CharacterEncodingsGUI',
        'Show-UnicodeConverterWindow',
        'Get-CharCount',
        'regex_tk_tool',
        'Format-IndexObject',
        'Format-EnvItemNumber',
        'Format-DoubleColumn',
        'Convert-MarkdownToHtml'
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
