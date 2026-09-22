@{
    RootModule = 'FileSystem.psm1'
    ModuleVersion = '1.0.4'
    GUID = '62949e73-dd5d-416a-bc20-bec551e97a34'
    Author = 'cxxu'
    Description = 'File/dir measure and daily ops: robocopy wrapper + browse/search/link'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Add-Extension',
        'Get-NonEmptySubdirectories',
        'Remove-EmptyDirectories',
        'Get-PsIOItemInfo',
        'Get-Size',
        'Get-ItemSizeSorted',
        'Get-ChildItemNameQuatation',
        'Test-DirectoryEmpty',
        'Remove-RobocopyMirEmpty',
        'Copy-Robocopy',
        'ls_eza',
        'extract_markdown_titiles',
        'tree_lsd',
        'ld',
        'l1',
        'remote_folder',
        'Get-LineNumberWidth',
        'Get-ContentNL',
        'Open-AllFiles',
        'New-Junction',
        'New-File',
        'mvToNEEPSub',
        'renamePrefix',
        'search_contents',
        'aliasEdit',
        'mkdirSafeCd',
        'c',
        'Get-ScriptRootPath',
        'Write-WorkingDir'
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
