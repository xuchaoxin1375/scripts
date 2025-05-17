function removeGlobal
{
    param (
        $FilePath = './AliasPwsh.ps1'
    )
    # Get-Content ./AliasPwsh.ps1 foreach{ $_.}
    # $buffer = Get-Content $FilePath | ForEach-Object { $_.ToString().TrimEnd('-Scope global') }
    $buffer = Get-Content $FilePath | ForEach-Object {
        $line = $_.ToString();
        # Write-Output $line;
        if ($line.StartsWith('#'))
        {
            continue
        }
        # Write-Output $line.IndexOf('-Scope')

        $indexOfScope = $line.Substring(0, $line.IndexOf('-Scope'))
        Write-Output $indexOfScope
        # $_.ToString().Substring()
    }
    $buffer>'Alias.ps1'
    Get-Content Alias.ps1
}

removeGlobal