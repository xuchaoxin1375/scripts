function catn
{
    <# 

    #>
    param (
        $Path = '',
        [Parameter(ValueFromPipeline)]
        [String]
        $content
        # $FileName
 
    )
    begin
    {
        $i = 0;
    }    process
    {

        if ($path -eq '')
        {
            $content | ForEach-Object {
                $i++;
                '{0,-5} {1} ' -f $i, $_ ;
            
            }
        }
        else
        {
            # $content = (Get-Content $Path)
            Get-Content $Path | ForEach-Object {
                $i++;
                '{0,-5} {1} ' -f $i, $_ ;
            
            }
        }
    }
}
1..14 | catn
Get-Content ./dates | catn
#  -Path ./file
catn ./dates