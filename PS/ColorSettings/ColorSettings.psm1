function closeColor{
    remove-module get-ChildItemColor
}

function colorSet {
    param (
        
    )
    # PSReadLine 未加载(裸会话)直接跳过;inlineprediction 配色需 2.1+(5.1 自带 2.0.0 必炸,已验),selection 2.0 可设
    $rl = Get-Module PSReadLine
    if ($null -eq $rl) { return }
    if ($rl.Version -ge [version]'2.1')
    {
        # modify the color of the inlinePrediction:
        Set-PSReadLineOption -Colors @{"inlineprediction" = "#d0d0cb" }#grayLight(grayDark #babbb4)
        # Set-PSReadLineOption -Colors @{"inlineprediction"="#51ed9c"}#green
    }

    #modify the color of selection:
    Set-PSReadLineOption -Colors @{"selection" = "#0080ff" } 
}