#!/bin/bash
if [[ -d "$script_root" ]]; then { echo 'The target dir is already exist! remove old dir...' ; sudo rm "$script_root" -rf ; } ; fi;