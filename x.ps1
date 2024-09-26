# Copyright 2022-? Li Junhao (l@x-cmd.com). Licensed under the GNU AFFERO GENERAL PUBLIC LICENSE, Version 3.

Write-Host "INFO: Check if Git-For-Windows is installed"

$gitbash = "bash"
$gitPath = (Get-Command $gitbash -ErrorAction SilentlyContinue).Path
if ($gitPath) { goto startGitBash }

$gitbash = "git-bash"
$gitPath = (Get-Command $gitbash -ErrorAction SilentlyContinue).Path
if ($gitPath) { goto startGitBash }

$gitbash = "$env:USERPROFILE\.x-cmd.root\data\git-for-windows\bin\bash.exe"
if (Test-Path $gitbash) { goto startGitBash }

$gitbash = "$env:ProgramFiles\Git\bin\bash.exe"
if (Test-Path $gitbash) { goto startGitBash }

if (!(Test-Path "$env:USERPROFILE\.x-cmd.root\data\git-for-windows")) {
    Write-Host "INFO: create directory to place git-for-windows -- $env:USERPROFILE\.x-cmd.root\data\git-for-windows"
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.x-cmd.root\data\git-for-windows"
}

:init
Write-Host "INFO: cd into $env:USERPROFILE\.x-cmd.root\data\git-for-windows"
$gitbash = "$env:USERPROFILE\.x-cmd.root\data\git-for-windows\bin\bash.exe"
Set-Location -Path "$env:USERPROFILE\.x-cmd.root\data\git-for-windows"

Write-Host "."
Write-Host "--------------------------------------------------------------------------------------------------------"
Write-Host "STEP 1: Download git-for-windows to $env:USERPROFILE\.x-cmd.root\data\git-for-windows"
Write-Host "--------------------------------------------------------------------------------------------------------"
Write-Host "."

Invoke-WebRequest -Uri "https://gitcode.net/x-cmd-build/git-for-windows/-/releases/v2.41.0/downloads/git-for-windows.7z.exe" -OutFile "git-for-windows.7z.exe"
if ($?) { goto install } else {
    Write-Host "ERROR: Download failure. Press any key to exit."
    Read-Host
    exit 1
}

:install
Write-Host "."
Write-Host "--------------------------------------------------------------------------------------------------------"
Write-Host "STEP 2: Install git-for-windows. It might take a few minutes. Don't close this window."
Write-Host "--------------------------------------------------------------------------------------------------------"
Write-Host "."

Start-Process -FilePath "git-for-windows.7z.exe" -ArgumentList "-y" -Wait
if ($LASTEXITCODE -eq 0) { goto robocopy } else {
    Write-Host "ERROR: Installation failure. Press any key to exit."
    Read-Host
    exit 1
}

:robocopy
Write-Host "."
Write-Host "--------------------------------------------------------------------------------------------------------"
Write-Host "STEP 3: Using robocopy to relocate the git-for-windows folder"
Write-Host "--------------------------------------------------------------------------------------------------------"
Write-Host "."

Start-Process -FilePath "robocopy" -ArgumentList "PortableGit $pwd /E /MOVE /np /nfl /ndl /njh /njs" -Wait
if (Test-Path $gitbash) { goto startGitBash } else {
    Write-Host "ERROR: Fail to install git-for-windows. Press any key to exit."
    exit 1
}

:startGitBash
Write-Host "INFO: start git-bash '$gitbash'"

$initBashScript = "$env:USERPROFILE\.x-cmd.init.bash"
"[ -f `"$HOME/.x-cmd.root/X`" || eval `$(curl https://get.x-cmd.com)" | Out-File -Encoding ASCII $initBashScript

Start-Process -FilePath $gitbash -ArgumentList $initBashScript -Wait
Remove-Item -Path $initBashScript

Start-Process -FilePath $gitbash
