function Out-Voice
{
    # define parameters
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $Text,
    
        [ValidateRange(-10, 10)]
        [int]
        $Speed = 0
    )
  
    # do initialization tasks
    begin
    {
        $sapi = New-Object -ComObject Sapi.SPVoice
        $sapi.Rate = $Speed
    }
  
    # process pipeline input
    process
    {
        $null = $sapi.Speak($Text)
    }

    # do cleanup tasks
    end
    {
        # nothing to do
    }
}

'Hello', 'This is a test', 'Hello', 'This is a test', 'Hello', 'This is a test' | Out-Voice -Speed 3