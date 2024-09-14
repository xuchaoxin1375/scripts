function closeColor{
    remove-module get-ChildItemColor
}

function colorSet {
    param (
        
    )
    # modify the color of the inlinePrediction:
    Set-PSReadLineOption -Colors @{"inlineprediction" = "#d0d0cb" }#grayLight(grayDark #babbb4)
    # Set-PSReadLineOption -Colors @{"inlineprediction"="#51ed9c"}#green

    #modify the color of selection:
    Set-PSReadLineOption -Colors @{"selection" = "#0080ff" } 
}