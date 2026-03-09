#!/bin/bash
log() {
    echo "[$(date +%T)] $*"
}
log "将启动一个后台睡眠2秒的作业."
sleep 2 &
pid=$!

log "回到当前shell,此时后台作业[pid=$pid]尚未结束,调用一次jobs看看."
jobs

log "此时应该提示作业未完成,再调用一次jobs,再次输出和上一次jobs的相同的结果."
jobs

log "现在等待3秒,确保让作业完成(后台作业虽然已经完成了,但是在结果被读取之前,仍然记录着,\
随时可以调用jobs观察,但是观察是一次性的,第一次观察后就不能再次观察到了),且结果易于观察."
sleep 3

log "调用jobs -p 观察,此时仅打印后台任务pid,但是不会显示状态(即便已经结束,也不会被移除)"
jobs -rp

log "再次调用jobs -p 观察[$pid],仍然可以观察到."
jobs -rp

log "调用jobs -l 观察[$pid],此时会显示状态,并且会移除该作业"
jobs -l

log "实验结束[$pid]"
