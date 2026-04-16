#!/bin/bash
command -v 'pwsh.exe' 2> /dev/null && alias pwsh=pwsh.exe
alias push_ReposesConfiged="pwsh -c '& {Push-ReposesConfiged ; pause}'"
alias update_ReposesConfiged="pwsh -c '& {Update-ReposesConfiged}'"
