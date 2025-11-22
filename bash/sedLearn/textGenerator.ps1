Write-Output 'clear the old content...'
# ''>text1
# remove empty line:
Clear-Content .\text1

Write-Output 'generating n lines content'
1..100 | ForEach-Object {
    # $_.ToString()>>.\text1
    # $_.ToString() >> text1
    # "$_"+"line+$(gdt.ticks)">>text1
    "L$($_)$((Get-Date).Ticks)">>.\text1
    # $_
}
# "teset">>text1