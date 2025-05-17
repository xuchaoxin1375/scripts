function pipeCounter
{
    begin
    {
        $x = 0
    }
    process
    {
        $x++
    }
    end
    {
        $x
    }
}

# Get-Service | Counter
1..10 | pipeCounter