function Get-FolderSize
{
    begin
    {
        $x = 0
    }
    process
    {
        if ($_ -is [System.IO.FileInfo])
        { 
            Write-Output "size is $($_.length)"
            $x += $_.Length 
        }
    }
    end
    {
        $x
    }
}
Get-ChildItem -Path ./ -Filter '*.ps1' -File | Get-FolderSize