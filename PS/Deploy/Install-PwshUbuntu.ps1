github_mirror="${github_mirror:-https://gh-proxy.com}"
###################################
# Prerequisites

# Update the list of packages
sudo apt-get update

# Install pre-requisite packages.
sudo apt-get install -y wget

# Download the PowerShell package file
# 2026-09-24 verified: prefix-style mirrors (see PS/TestLinks/TestLinks.psm1) proxy release assets;
# override with another mirror if this one is slow: github_mirror=https://gh-proxy.org bash Install-PwshUbuntu.ps1
wget "$github_mirror/https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/powershell_7.6.6-1.deb_amd64.deb"

###################################
# Install the PowerShell package
sudo dpkg -i powershell_7.6.6-1.deb_amd64.deb

# Resolve missing dependencies and finish the install (if necessary)
sudo apt-get install -f

# Delete the downloaded package file
rm -f powershell_7.6.6-1.deb_amd64.deb

# Start PowerShell Preview
pwsh