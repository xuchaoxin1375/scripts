
envsPath="/mnt/d/repos/scripts/linuxShellScripts
linuxShellScripts=$envsPath
tea -a .zshrc<<eof
source $linuxShellScripts/.importer.sh
eof

tea -a .bashrc<<eof
source $linuxShellScripts/.importer.sh
eof

