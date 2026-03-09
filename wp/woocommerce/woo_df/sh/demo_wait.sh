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
running=0
# tasks=($(seq 1 "$tasks_count"))
mapfile -t tasks < <(seq 1 "$tasks_count")

count_status() {
    pid="$1"
    exit_code="$2"
    if [[ $exit_code -ne 0 ]]; then
        ((failed++))
        failed_tasks+=("${pid_task_map[$pid]}")
        status="fail"
    else
        ((success++))
        status="success"
    fi
    log "进程 $pid 结束,status=$status"
}

for task_id in "${tasks[@]}"; do
    # 控制并发数
    while
        jobs_count="${#pids[@]}"
        (("$jobs_count" >= MAX_CONCURRENT))
    do
        # 等待任意一个子进程结束,轮询策略;(扫描一遍进程ip数组,需要设置每次轮序的时间间隔,看哪个进程结束)
        # log "进程数量[$jobs_count]达到上限,等待任意一个完成"
        log "当前任务数达到$jobs_count ;逐个释放..."
        wait -n -p pid
        exit_code=$?
        count_status "$pid" "$exit_code"
        # 跳过从pids数组中移除已完成的任务pid,而在外部统一判断处理
    done

    run_task "$task_id" &
    pid=$!
    pids+=("$pid")
    pid_task_map[$pid]="$task_id"
done

log "=====等待剩余任务"
for pid in "${pids[@]}"; do
    if kill -p "$pid" 2> /dev/null; then
        wait "$pid"
        exit_code=$?
        count_status "$pid" "$exit_code"
    else
        log "进程$pid 已经结束并统计过"
    fi
done

log "================================"
log "Total: ${#tasks[@]}, Failed: $failed"
log "Success_a: $((${#tasks[@]} - failed)),Success_b: $success"
log "Failed tasks(ids): ${failed_tasks[*]}"
