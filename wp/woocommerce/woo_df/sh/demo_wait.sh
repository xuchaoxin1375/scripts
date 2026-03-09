#!/bin/bash

pids=()
tasks_count=10
success=0
failed=0
failed_tasks=()
log() {
    echo -e "[$(date +%T)] $*"
}
run_task() {
    local i="$1"
    log "开始执行任务 $i"

    # 模拟任务，部分会失败
    time_consumption=$((RANDOM % 3 + 1))
    log "\tTask $i started(time consumption: $time_consumption s)"
    sleep "$time_consumption"
    if ((i % 3 == 0)); then
        exit 1 # 模拟失败
    fi
    exit 0
}
#!/bin/bash

MAX_CONCURRENT=4
pids=()
declare -A pid_task_map # PID -> 任务名 的映射
failed=0
failed_tasks=()
# tasks=($(seq 1 "$tasks_count"))
mapfile -t tasks < <(seq 1 "$tasks_count")
for task_id in "${tasks[@]}"; do
    # 控制并发数
    while
        jobs_count="${#pids[@]}"
        (("$jobs_count" >= MAX_CONCURRENT))
    do
        # 等待任意一个子进程结束,轮询策略;(扫描一遍进程ip数组,需要设置每次轮序的时间间隔,看哪个进程结束)
        # log "进程数量[$jobs_count]达到上限,等待任意一个完成"
        wait -n -p pid
        log "进程 $pid 结束"
    done

    run_task "$task_id" &
    pid=$!
    pids+=("$pid")
    pid_task_map[$pid]="$task_id"
done

# 等待剩余任务
for pid in "${pids[@]}"; do
    wait "$pid"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        ((failed++))
        failed_tasks+=("${pid_task_map[$pid]}")
    else
        ((success++))
    fi
done

log "================================"
log "Total: ${#tasks[@]}, Failed: $failed"
log "Success_a: $((${#tasks[@]} - failed)),Success_b: $success"
log "Failed tasks(ids): ${failed_tasks[*]}"

# log "================================"
# log "Total failed: $failed"
# log "Total success: $success"
# log "Failed tasks: ${failed_tasks[*]}"
