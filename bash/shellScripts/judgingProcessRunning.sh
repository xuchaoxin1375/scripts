#!/bin/bash

# Check if gedit is running
# -x flag only match processes whose name (or command line if -f is
# specified) exactly match the pattern.

pattern="dictd"
if pgrep -x $pattern > /dev/null
then
    echo "$pattern is Running"

else
    echo "$pattern Stopped,try to start $pattern"
    sudo $pattern
fi