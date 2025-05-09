function Get-UsersGroupsCmdlets
{
    $cmds = Get-Command -Module Microsoft.PowerShell.LocalAccounts
    $res = $cmds | ForEach-Object { Get-Alias -Definition $_ } | ^ DisplayName
    return $res
}

function Get-UsersProfileList
{
    $UsersProfileListRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\profileList'
    $res = Get-ChildItem $UsersProfileListRegPath
    #  | Format-List 
    return $res
}