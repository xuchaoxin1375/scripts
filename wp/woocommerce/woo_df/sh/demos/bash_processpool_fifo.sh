#!/bin/bash

# ============================================
# FIFO 进程池演示
# ============================================

# ---------- 配置 ----------
MAX_JOBS=3          # 进程池大小（最大并发数）
TASKS_COUNT=6        # 总任务数
# 定义一个日志函数，输出带有时间戳的日志信息，参数是日志内容
log() {
    local msg="$1"
    echo "[$(date +%T.%3N)] $msg"
}
loge() {
    local msg="$1"
    echo -e "[$(date +%T.%3N)] $msg" >&2
}
# ---------- 模拟任务 ----------
do_task() {
    local id=$1
    local duration=$(( RANDOM % 11 + 1 ))   # 随机 1~11 秒
    log "任务 $id 开始（将耗时 ${duration}s）"
    sleep "$duration"
    log "任务 $id 完成"
}
# 开始时间
start_time=$(date +%s)
log "===进程池模拟模拟程序开始[线程池大小: $MAX_JOBS]==="
#!/bin/bash

TASK_FIFO="/tmp/task_fifo_$$"
mkfifo "$TASK_FIFO"

# ========== 工作进程（常驻，循环取任务） ==========
worker() {
    local wid=$1
    while true; do
        # 从任务队列读取一行（阻塞等待）
        local task
        read -r task
        
        # 收到退出信号
        [[ "$task" == "EXIT" ]] && break

        # 执行任务
        local duration=$(( RANDOM % 11 + 1 ))
        log "Worker-$wid 执行任务: $task（${duration}s）"
        sleep "$duration"
        log "Worker-$wid 完成任务: $task"
    done
}

# ========== 启动固定数量的 Worker ==========
for (( i = 1; i <= MAX_JOBS; i++ )); do
    worker "$i" < "$TASK_FIFO" &       # 所有worker从同一个FIFO读
    WORKER_PIDS+=($!)
done

# ========== 提交任务（写入 FIFO） ==========
{
    for task_id in $(seq 1 $TASKS_COUNT); do
        echo "T-$task_id"
    done

    # 发送退出信号（每个worker一个）
    for (( i = 0; i < MAX_JOBS; i++ )); do
        echo "EXIT"
    done
} > "$TASK_FIFO"

# ========== 等待所有 Worker 退出 ==========
wait "${WORKER_PIDS[@]}"

rm -f "$TASK_FIFO"

log "======== 所有任务完成 ========"
log "所有任务处理完毕。耗时约: $(($(date +%s) - start_time))秒"
