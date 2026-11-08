#!/usr/bin/env python3
"""抓取"输入假死"的 pwsh 现场, 并把 JIT 地址还原成托管方法名.

背景: pwsh 的交互式假死常表现为按键全部堆在 tty 输入队列、进程存活但没人读。
仅靠 `sample` 只能看到 `??? [0x...]` 的 JIT 地址; 若目标进程启动时带有
`DOTNET_PerfMapEnabled=1`, .NET 会把 `<地址, 大小, 方法名>` 写进
`/tmp/perf-<pid>.map`, 本脚本据此还原线程栈。

前置条件:
  - macOS (依赖 /usr/bin/sample)
  - 目标 pwsh 启动前已设置 DOTNET_PerfMapEnabled=1; 启动后再设置无效

用法:
  pwsh_hang_capture.py                 # 自动挑一个 pwsh 进程并抓取
  pwsh_hang_capture.py 12345           # 指定 PID
  pwsh_hang_capture.py --list          # 只列出候选进程, 不抓取
  pwsh_hang_capture.py --all           # 打印全部线程(默认只打印主/管线/ReadKey)
  pwsh_hang_capture.py --seconds 3     # 采样时长, 默认 2 秒
  pwsh_hang_capture.py --keep FILE     # 保留原始 sample 到指定文件

退出码: 0 成功; 1 未找到进程/采样失败; 2 缺少 perf map (栈只剩地址).
"""
import argparse
import bisect
import fcntl
import os
import re
import struct
import subprocess
import sys
import tempfile
import termios

SAMPLE = "/usr/bin/sample"
INTEREST = ("main-thread", "Pipeline Execution Thread", "PSReadLine ReadKey Thread")


def list_pwsh():
    """返回 [(pid, stat, tty, command)], 只保留命令行首段是 pwsh 的进程。"""
    out = subprocess.run(
        ["ps", "-Ao", "pid=,stat=,tty=,command="],
        capture_output=True, text=True, check=True,
    ).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        pid, stat, tty, cmd = parts
        first = cmd.split()[0]
        if os.path.basename(first) == "pwsh":
            rows.append((int(pid), stat, tty, cmd))
    return rows


def load_perfmap(path):
    entries = []
    try:
        fh = open(path, errors="ignore")
    except FileNotFoundError:
        return entries
    with fh:
        for line in fh:
            parts = line.split(None, 2)
            if len(parts) < 3:
                continue
            try:
                start = int(parts[0], 16)
                size = int(parts[1], 16)
            except ValueError:
                continue
            entries.append((start, start + size, parts[2].strip()))
    entries.sort()
    return entries


def symbolize(sample_text, perfmap):
    starts = [e[0] for e in perfmap]

    def lookup(addr):
        i = bisect.bisect_right(starts, addr) - 1
        if i >= 0 and addr < perfmap[i][1]:
            return perfmap[i][2]
        return None

    blocks = []
    for block in re.split(r"\n(?=    \d+ Thread_)", sample_text):
        if not re.match(r"    \d+ Thread_", block):
            continue
        head = block.splitlines()[0].strip()
        frames = []
        for line in block.splitlines():
            hit = re.search(r"\[(0x[0-9a-f]+)\]", line)
            if not hit:
                continue
            name = lookup(int(hit.group(1), 16))
            if name:
                frames.append(name)
        blocks.append((head, frames))
    return blocks


def tty_state(pid):
    """返回 (tty 路径或 None, 进程状态, 输入队列字节数或 None)。

    输入队列用 FIONREAD 读取, 只查看不消费; 队列里堆着字节而进程不读,
    就是"按键已送达但没人处理"的直接证据。
    """
    out = subprocess.run(
        ["ps", "-o", "tty=,stat=", "-p", str(pid)],
        capture_output=True, text=True,
    ).stdout.strip()
    if not out:
        return None, None, None
    parts = out.split()
    tty = parts[0] if parts else None
    stat = parts[1] if len(parts) > 1 else None
    if not tty or tty in ("??", "-"):
        return None, stat, None
    path = tty if tty.startswith("/dev/") else f"/dev/{tty}"
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return path, stat, None
    try:
        queued = struct.unpack("i", fcntl.ioctl(fd, termios.FIONREAD, b"\0\0\0\0"))[0]
        return path, stat, queued
    except OSError:
        return path, stat, None
    finally:
        os.close(fd)


def main():
    ap = argparse.ArgumentParser(
        description="抓取 pwsh 假死现场并用 perf map 还原托管线程栈",
        epilog=(
            "前置: 目标 pwsh 必须在启动前设置 DOTNET_PerfMapEnabled=1"
            "(启动后再设置无效), 并依赖 macOS 的 /usr/bin/sample。\n"
            "失败: 未找到进程返回 1; 缺少 perf map 返回 2, 此时栈中只剩地址。"
        ),
    )
    ap.add_argument("pid", nargs="?", type=int, help="目标 pwsh 的 PID; 省略则自动挑选")
    ap.add_argument("--list", action="store_true", help="只列出候选 pwsh 进程")
    ap.add_argument("--all", action="store_true", help="打印全部线程, 默认只打印关键线程")
    ap.add_argument("--seconds", type=float, default=2.0, help="采样时长, 默认 2 秒")
    ap.add_argument("--keep", metavar="FILE", help="保留原始 sample 输出到文件")
    args = ap.parse_args()

    procs = list_pwsh()
    if args.list:
        if not procs:
            print("没有找到 pwsh 进程")
            return 1
        for pid, stat, tty, cmd in procs:
            print(f"{pid:>7}  {stat:<4} {tty:<8} {cmd}")
        return 0

    if args.pid:
        target = args.pid
    else:
        if not procs:
            print("没有找到 pwsh 进程; 可用 --list 查看", file=sys.stderr)
            return 1
        target = procs[0][0]

    tty, stat, queued = tty_state(target)
    print(f"# PID {target}  state={stat or '?'}  tty={tty or '?'}  "
          f"tty 输入队列={queued if queued is not None else '?'} 字节", flush=True)
    if queued:
        print("# 队列里有未读取的按键, 但进程没在读 -> 输入侧卡住")

    sample_path = args.keep or os.path.join(
        tempfile.gettempdir(), f"pwsh-hang-{target}.sample")
    proc = subprocess.run(
        [SAMPLE, str(target), str(args.seconds), "-file", sample_path],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(f"sample 失败: {proc.stderr.strip() or proc.stdout.strip()}", file=sys.stderr)
        return 1

    perfmap_path = f"/tmp/perf-{target}.map"
    if not os.path.exists(perfmap_path):
        print(f"缺少 {perfmap_path}: 该进程启动时未设置 DOTNET_PerfMapEnabled=1, "
              "只能看到地址。", file=sys.stderr)
        print(f"原始 sample 已保存: {sample_path}", file=sys.stderr)
        return 2

    sample_text = open(sample_path, errors="ignore").read()
    perfmap = load_perfmap(perfmap_path)
    blocks = symbolize(sample_text, perfmap)

    print(f"# perf map: {perfmap_path} ({len(perfmap)} 条映射)")
    shown = 0
    for head, frames in blocks:
        if not args.all and not any(k in head for k in INTEREST):
            continue
        shown += 1
        print(f"\n## {head}")
        if not frames:
            print("   (无可还原的托管帧)")
        for name in frames:
            print(f"   {name}")
    if not shown:
        print("没有匹配到关键线程; 用 --all 查看全部", file=sys.stderr)
    print(f"\n原始 sample: {sample_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
