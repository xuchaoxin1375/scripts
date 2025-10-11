# function foos
# {
#    param(
#       [String[]]$params
#    )
#    # java -jar C:\antlr4.jar $params

#    $str = 0
#    $params | ForEach-Object { $str += $_ }
#    Write-Output $str
# }
# foos 1 2 3

Function Get-Foo {
    [CmdletBinding()]
    Param (
       [Parameter(Mandatory=$True)]
       [String[]]$Computer,

       [Parameter(Mandatory=$True)]
       [String]$Data
    )

    "We found $(($Computer | Measure-Object).Count) computers"
}

Get-Foo -Computer a, b, c -Data yes

# We found 3 computers

Get-Foo -Computer a, b, c, d, e, f -Data yes