#!/bin/bash

PIDS=()
TASKS_COUNT=6
MAX_CONCURRENT=2
TIME_LIMIT=2 #任务时间模拟(负数表示随机时间,范围不超过指定数)
SUCCESS=0
FAILED=0
FAILED_TASKS=()
declare -A PID_TASK_MAP # PID -> 任务名 的映射
# tasks=($(seq 1 "$tasks_count"))
mapfile -t tasks < <(seq 1 "$TASKS_COUNT")
# ===定义函数
log() {
    echo -e "[$(date +%T)] $*"
}
run_task() {
    local i="$1"
    log "开始执行任务 $i"

    # 模拟任务，部分会失败
    if [[ $TIME_LIMIT =~ ^- ]]; then
        time_limit=${TIME_LIMIT#-}
        time_consumption=$((RANDOM % time_limit + 1))
    else
        time_limit=$TIME_LIMIT
        time_consumption=$time_limit
    fi
    log "\tTask $i started(time consumption: $time_consumption s)"
    sleep "$time_consumption"
    if ((i % 3 == 0)); then
        exit 1 # 模拟失败
    fi
    exit 0
}
# 统计后台任务状态
# Global:
#    FAILED,SUCCESS,FAILED_TASKS,PID_TASK_MAP
# Arguments:
# 	$1 pid
# 	$2 exit_code
count_status() {
    pid="$1"
    exit_code="$2"
    # echo "进程 $pid (tid: ${PID_TASK_MAP[$pid]} )退出,exit_code=$exit_code"
    # return $exit_code
    if [[ $exit_code -ne 0 ]]; then
        ((FAILED++))
        FAILED_TASKS+=("${PID_TASK_MAP[$pid]}")
        status="FAIL"
    else
        ((SUCCESS++))
        status="SUCCESS"
    fi
    log "进程 $pid (tid: ${PID_TASK_MAP[$pid]} ) 结束,status=$status"
}
# ====开始
start_time=$(date +%s)

for task_id in "${tasks[@]}"; do
    # 控制并发数
    while
        # jobs_count="${#PIDS[@]}"
        jobs_count="$(jobs -rp | wc -l)"
        (("$jobs_count" >= MAX_CONCURRENT))
    do
        # 等待任意一个子进程结束,轮询策略;(扫描一遍进程ip数组,需要设置每次轮序的时间间隔,看哪个进程结束)
        # log "进程数量[$jobs_count]达到上限,等待任意一个完成"
        log "当前任务数达到$jobs_count ;逐个释放..."
        wait -n

    done

    run_task "$task_id" &
    pid=$!
    PIDS+=("$pid")
    PID_TASK_MAP[$pid]="$task_id"
done

log "=====等待剩余任务(所有任务已经创建完毕)"
declare -p PIDS
# declare -p PID_TASK_MAP
for pid in "${PIDS[@]}"; do
    wait "$pid"
    exit_code=$?
    count_status "$pid" "$exit_code"
done

log "================================"
log "Total: ${#tasks[@]}, FAILed: $FAILED"
log "SUCCESS_a: $((${#tasks[@]} - FAILED)),SUCCESS_b: $SUCCESS"
log "failed tasks(ids): ${FAILED_TASKS[*]}"
log "所有任务处理完毕。耗时约: $(($(date +%s) - start_time))秒"
echo "===运行参数说明:"
echo "MAX_CONCURRENT: $MAX_CONCURRENT"
echo "TASKS_COUNT: $TASKS_COUNT"
echo "TIME_LIMIT: $TIME_LIMIT (如果是负数表示随机范围)"
