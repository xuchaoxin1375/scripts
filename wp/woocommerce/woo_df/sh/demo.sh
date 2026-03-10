#!/bin/bash
# wait_twice_pid.sh
log() {
    echo -e "[$(date +%T)] $*"
}
log "启动1个后台任务"
task() {
    time="${1:-2}"
    sleep "$time"
    return 101
}
task 1 &
pid=$!
log "[$pid]start"
log "sleep 3秒,等待后台作业结束"
sleep 3
log "调用jobs -l 检查后台作业情况"
jobs -l
wait $pid
log "作业[$pid]结束;exit code: $?"

log "第二次等待同一个pid,观察返回码"
wait $pid
log "[$pid]exit code: $?"
