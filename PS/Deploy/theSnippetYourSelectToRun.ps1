Write-Verbose 'Try to get the lastest version of git portable version...'
    $latestRelease = Invoke-WebRequest -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Method Get | ConvertFrom-Json
    if ($latestRelease)
    {
        
        $LastUrls = $latestRelease.assets | Where-Object { $_.name -like '*PortableGit*' } | Select-Object -ExpandProperty browser_download_url
        $url = @($LastUrls) | Where-Object { $_ -like '*64*' } | Select-Object -First 1
    }
    else
    {
        
        Write-Warning 'Get the lastest version failed.Use default version link'
    }