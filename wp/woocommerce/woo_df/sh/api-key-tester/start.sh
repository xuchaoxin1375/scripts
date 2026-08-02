#!/bin/bash
# KeyLens 一键启动/停止本地后端
# 用法: ./start.sh start|stop|status
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=8899
PIDFILE="$DIR/.server.pid"

start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "服务已在运行: http://localhost:$PORT"
    open "http://localhost:$PORT"
    return
  fi
  nohup node "$DIR/server.js" "$PORT" > "$DIR/.server.log" 2>&1 &
  echo $! > "$PIDFILE"
  sleep 1
  if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "✓ 服务已启动: http://localhost:$PORT"
    open "http://localhost:$PORT"
  else
    echo "✕ 启动失败，查看 .server.log"
    rm -f "$PIDFILE"
  fi
}

stop() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    echo "✓ 服务已停止"
  else
    echo "服务未在运行"
  fi
}

status() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "运行中: http://localhost:$PORT"
  else
    echo "未运行"
  fi
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *) echo "用法: $0 start|stop|status" ;;
esac
