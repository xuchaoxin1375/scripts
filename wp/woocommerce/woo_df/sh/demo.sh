#!/bin/bash
for i in {1..5}; do {
    task_time=$((RANDOM % 5 + 2))
    echo "start J-$i (time: $task_time s)"
    sleep $task_time
    echo "end J-$i (time: $task_time s)"
} & done
# 只要任务数大于等于 JOBS，就持续等待
JOBS=2
while
    job_cnt=$(jobs -rp | wc -l)
    ((job_cnt >= JOBS))
do
    echo "当前任务数: $job_cnt"
    wait -n
done

wait
echo "所有任务结束"
