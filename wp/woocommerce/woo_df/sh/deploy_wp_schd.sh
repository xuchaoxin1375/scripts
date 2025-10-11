#!/bin/bash

LOG_FILE="/srv/uploads/uploader/files/$(date +%Y-%m-%d).log"
chmod +x /deploy.sh
/deploy.sh >> "$LOG_FILE" 2>&1
# bash /deploy.sh  >> "/srv/uploads/$(date +%Y-%m-%d).log" 2>&1