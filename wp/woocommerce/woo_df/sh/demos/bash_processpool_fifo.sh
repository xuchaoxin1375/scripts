#!/bin/bash
# bash_processpool_fifo.sh
# ============================================
# FIFO 进程池演示
# ============================================

# ---------- 配置(可通过脚本位置参数传递来覆盖默认值) ----------
MAX_JOBS=${1:-3}    # 进程池大小（最大并发数）
TIME_LIMIT=${2:-11} # 任务执行时间限制(如果是-开头,则表示每个任务运行相同的取固定值时间)
TASKS_COUNT=${3:-6} # 总任务数
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
    local time_limit=${2:-$TIME_LIMIT}

    local duration
    if [[ $time_limit =~ ^- ]]; then
        duration=${time_limit#-} # 去掉开头的'-'符号
    else
        duration=$((RANDOM % "$time_limit" + 1)) # 模拟任务执行时间(1-5秒)
    fi
    # local duration=3   # 固定某个秒数
    log "Task-($id) 开始（将耗时 ${duration}s）"
    sleep "$duration"
    log "Task-($id) 完成"
}
# 开始时间
start_time=$(date +%s)
log "===进程池模拟模拟程序开始[线程池大小: $MAX_JOBS,任务数量为: $TASKS_COUNT]==="
if [[ $TIME_LIMIT =~ ^- ]]; then
    log "任务执行时间固定为: ${TIME_LIMIT#-}秒"
else
    log "任务执行时间随机生成，范围是: 1-${TIME_LIMIT}秒"
fi

TASK_FIFO="/tmp/task_fifo_$$_$(date +%s)" # 任务队列的FIFO文件路径，使用PID和时间戳确保唯一
mkfifo "$TASK_FIFO"

# ========== 工作进程（常驻，循环取任务） ==========
# 通过标注重定向标准输入到此worker函数,让内部的read命令读取任务参数;
# 参考调用方式: worker < TASK_FIFO &
worker() {
    local wid=$1
    # workern内部维护一个while循环,让worker可以重复利用,直到接收到退出信号为止.
    while true; do
        # 从任务队列读取一行（阻塞等待）
        local task
        read -r task

        # 收到退出信号

        [[ "$task" == "EXIT" ]] && log "[worker-$wid] 收到退出信号" && break

        log "Worker-$wid 执行任务"
        # 执行任务
        do_task "$task" "$duration"
        # sleep 3
        log "Worker-$wid 任务完成"
    done
}

# ========== 启动固定数量的 Worker ==========
for ((i = 1; i <= MAX_JOBS; i++)); do
    log "启动worker进程: $i"
    worker "$i" < "$TASK_FIFO" & # 所有worker从同一个FIFO读
    WORKER_PIDS+=($!)
done

# ========== 提交任务（写入 FIFO） ==========
{
    # 提交任务,将任务参数(简单假设为任务名) 写入FIFO
    for task_id in $(seq 1 $TASKS_COUNT); do
        echo "T-$task_id"
    done

    # 提示语句重定向到stderr,以免被worker进程从FIFO读到当成任务参数
    log "worker进程创建完毕" 1>&2
    # 发送退出信号（每个worker一个）
    for ((i = 0; i < MAX_JOBS; i++)); do
        echo "EXIT"
    done
    # 可以考虑追加一个退出信号防止部分进程接收不到EXIT信号停不下来.
    # echo "EXIT" 
    log "所有任务提交完毕" 1>&2
} > "$TASK_FIFO"

# ========== 等待所有 Worker 退出 ==========
wait "${WORKER_PIDS[@]}"

rm -f "$TASK_FIFO"

log "======== 所有任务完成 ========"
log "所有任务处理完毕。耗时约: $(($(date +%s) - start_time))秒"
