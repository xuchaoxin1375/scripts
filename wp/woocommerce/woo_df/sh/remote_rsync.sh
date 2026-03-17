#! /bin/bash
# 支持断点续传,并行传输(按文件夹划分任务)
REMOTE_USER=root
REMOTE_HOST="" # 安全起见,请勿内置默认真实的ip
REMOTE_PATH=""
LOCAL_PATH=""
DRY_RUN=false
JOBS=8

usage="
利用rsync 大批量地传输文件
usage:
  bash $0 [options]

options
  -u,--remote-user      远程服务器上的用户名
  -r,--remote-host      远程服务器地址
  -p,--remote-path      远程路径
  -l,--local-path       本地保存路径
  -j,--jobs,--threads   并行任务数
  -n,--dry-run          预览运行
  -h,--help             打印此帮助

example:
bash $0 -r <remote_ip> -p /www/wwwroot/xcx -l /data/xcx --dry-run
"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u | --remote-user)
      REMOTE_USER="$2"
      shift
      ;;
    -r | --remote-host)
      REMOTE_HOST="$2"
      shift
      ;;
    -p | --remote-path)
      REMOTE_PATH="$2"
      shift
      ;;
    -l | --local-path)
      LOCAL_PATH="$2"
      shift
      ;;
    -j | --jobs | --threads)
      JOBS="$2"
      shift
      ;;
    -n | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      echo "$usage"
      exit 0
      ;;
    -*)
      echo "unkown option [$1]"
      echo "$usage"
      exit 1
      ;;
  esac
  shift
done
echo "args: $REMOTE_HOST,$REMOTE_USER,$REMOTE_PATH,$LOCAL_PATH"
mkdir -p "$LOCAL_PATH" #事先确保目录存在,防止多进程rsync启动竞争创建失败导致退回单线程
# `--whole-file`: 跳过增量算法，"首次"传输时直接整文件复制更快,但这里不建议默认启用,而且不一定显著,还可能同一个命令二次运行,导致混乱
dry_opt=""
[[ $DRY_RUN == true ]] && dry_opt='--dry-run'
# shellcheck disable=SC2029
ssh "$REMOTE_USER@$REMOTE_HOST" "ls $REMOTE_PATH" | xargs -P "$JOBS" -I {} \
  rsync -avP --no-compress $dry_opt \
  -e "ssh -T -c aes128-gcm@openssh.com -o Compression=no" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/{}" "$LOCAL_PATH"
