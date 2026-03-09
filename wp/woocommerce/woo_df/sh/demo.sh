#!/bin/bash
# wait_frist.sh
log() {
    echo -e "[$(date +%T)] $*"
}
pids=()
log "启动5个后台任务"
sleep 1 &
pids+=($!)
sleep 2 &
pids+=($!)
sleep 3 &
pids+=($!)
sleep 4 &
pids+=($!)
sleep 5 &
pids+=($!)
log "$(declare -p pids)"
log "开始wait -n 第一个任务结束"
wait -n -p id
log "\tid1=$id"

log "等待4秒,此时至少3个任务结束"
sleep 4
log "再次wait -n"
wait -n -p id
log "\tid2=$id"
