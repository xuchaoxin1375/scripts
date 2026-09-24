github_mirror="${github_mirror:-https://gh-proxy.com}"
# pwsh 版本收敛到这一处(改一处即全改;也可用环境变量覆盖: pwsh_version=7.6.7 bash Install-PwshUbuntu.ps1)
pwsh_version="${pwsh_version:-7.6.6}"
###################################
# Prerequisites

# Update the list of packages
sudo apt-get update

# Install pre-requisite packages.
sudo apt-get install -y wget

# Download the PowerShell package file
# 2026-09-24 verified: prefix-style mirrors (see PS/TestLinks/TestLinks.psm1) proxy release assets;
# override with another mirror if this one is slow: github_mirror=https://gh-proxy.org bash Install-PwshUbuntu.ps1
wget "$github_mirror/https://github.com/PowerShell/PowerShell/releases/download/v$pwsh_version/powershell_${pwsh_version}-1.deb_amd64.deb"

###################################
# Install the PowerShell package
sudo dpkg -i "powershell_${pwsh_version}-1.deb_amd64.deb"

# Resolve missing dependencies and finish the install (if necessary)
sudo apt-get install -f

# Delete the downloaded package file
rm -f "powershell_${pwsh_version}-1.deb_amd64.deb"

# Start PowerShell Preview
pwsh