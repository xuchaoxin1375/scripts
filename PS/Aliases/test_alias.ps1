Write-Output 'updating aliases!'
$aliase_dir = "$env:Scripts\PS\aliases"
$aliase_file_array = 'functions', 'shortcuts'
foreach ($aliase_file in $aliase_file_array)
{

    Get-Content "$aliase_dir\$aliase_file" | ForEach-Object {
        $line = $_.ToString();
        # Write-Output $line
        # if ($line.Length -gt 0 -and !$line.startswith('#') )
        if($line -match '^[a-zA-Z]')
        {
            $line = "set-alias $line -Scope Global"
            #debuger
            # continue (foreach-object 内禁用continue!而应该使用return)
            Invoke-Expression "$line"
            # Write-Output $line
        }
        
    }
 
}