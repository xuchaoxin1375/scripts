#!/bin/bash
# bash_processpool_demo.sh
# 这个脚本演示了如何使用bash的后台任务和wait命令来实现一个简单的进程池机制，以控制同时运行的任务数量。
# 脚本命令行参数:(简单起见,且为了突出脚本主题,这里仅设置两个位置参数)

# Arguments:
#   $1 - MAX_JOBS 线程池大小（同时运行的最大任务数）
#   $2 - TIME_LIMIT 模拟任务执行时间的范围(默认11),效果

export MAX_JOBS="${1:-3}"    # 线程池大小（同时运行的最大任务数）
export TIME_LIMIT="${2:-11}" #模拟任务执行时间的范围(默认11),效果是随机生成1到TIME_LIMIT之间的整数作为任务执行时间
export TASKS_COUNT="${3:-6}" # 模拟任务数量(默认6)
# 模拟一组任务(实际任务可能是从文件读取或者扫描目录、数据库或其他来源获取的任务列表)
# tasks=("Task_1" "Task_2" "Task_3" "Task_4" "Task_5" "Task_6")
# tasks=($(seq -f "T%g" 1 "$TASKS_COUNT"))
mapfile -t tasks < <(seq -f "Task_%g" 1 "$TASKS_COUNT")
# 定义一个日志函数，输出带有时间戳的日志信息，参数是日志内容
log() {
    local msg="$1"
    echo "[$(date +%T.%3N)] $msg"
}
loge() {
    local msg="$1"
    echo -e "[$(date +%T.%3N)] $msg" >&2
}
# 定义一个模拟的函数来执行任务(让代码结构更清晰),后台任务结束时输出更加紧凑，传入任务时间和任务名称
# Global:
#   MAX_JOBS 线程池大小
#   TIME_LIMIT 模拟耗时任务到最大时间
# Arguments:
#   $1 - task 任务名称
#   $2 - time_limit
task_func() {
    local task="$1"
    local time_limit="${2:-$TIME_LIMIT}"

    log "[开始] $task"
    # 如果时间是-开头,则表示要取固定值,否则表示随机范围最大值生成一个时间
    if [[ $time_limit =~ ^- ]]; then
        task_time=${time_limit#-} # 去掉开头的'-'符号
    else
        task_time=$((RANDOM % "$time_limit" + 1)) # 模拟任务执行时间(1-5秒)
    fi
    loge "\t\t正在执行 $task / $MAX_JOBS, 预计耗时: ${task_time}s"
    sleep "$task_time" # 模拟耗时操作(随机睡眠5秒以内的时间)
    # demo_job $task_time "$task/$MAX_JOBS" # 这里调用一个模拟的函数来执行任务，传入任务时间和任务名称
    log "[完成] $task"
}
# 开始时间
start_time=$(date +%s)
log "===进程池模拟模拟程序开始[线程池大小: $MAX_JOBS]==="
if [[ $TIME_LIMIT =~ ^- ]]; then
    log "任务执行时间固定为: ${TIME_LIMIT#-}秒"
else
    log "任务执行时间随机生成，范围是: 1-${TIME_LIMIT}秒"
fi

for task in "${tasks[@]}"; do

    jbs=$(jobs -p)
    current_job_num=$(printf "%s " "$jbs" | wc -w)
    loge "\t当前后台任务数: $current_job_num @[${jbs//$'\n'/ }]"
    while [[ $current_job_num -ge $MAX_JOBS ]]; do

        log "进程池已满($MAX_JOBS);阻塞直到任意一个后台任务结束(释放出一个空位),然后继续循环创建新的后台任务."
        wait -n -p completed_pid
        # loge "\t后台任务[PID=$completed_pid]已完成."
        jbs=$(jobs -p)
        loge "\t(wait -n [PID=$completed_pid]已完成.,当前后台任务数: $(jobs -p | wc -l)) @[${jbs//$'\n'/ }]"

        jbs=$(jobs -p)
        current_job_num=$(printf "%s " "$jbs" | wc -w)
        loge "\t当前后台任务数: $current_job_num @[${jbs//$'\n'/ }]"
        # if [[ $current_job_num -ge $MAX_JOBS ]]; then
        # fi
    done
    # 进程池未满,创建新的后台任务
    log "添加: $task 到进程池中"
    (task_func "$task" "$TIME_LIMIT") &

done
# 离开循环后,所有后台任务都已经创建完毕,但是可能还有一些任务在运行中,所以需要等待它们全部完成.
#  最后等待所有剩余任务完成
wait
log "所有任务处理完毕。耗时约: $(($(date +%s) - start_time))秒"
