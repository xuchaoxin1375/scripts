# macOS 上 pwsh 的运行时故障与处置

> 适用：macOS + cmux（Ghostty 终端内核）+ pwsh 7.6.9（随附 PSReadLine 2.4.5）的交互式会话。Windows、其他终端模拟器与其他 pwsh 版本未验证；凡未实测的推断在下文标注为“待验证”。
> 本文只记录进程层与终端层的故障（假死、残留进程空转），启动耗时问题见 [Startup-Optimization.md](Startup-Optimization.md)；模块功能问题见 [Feature-Guide.md](Feature-Guide.md)；shell 配置接线与 mamba/conda 停用记录见 [macOS-Shell-Setup.md](macOS-Shell-Setup.md)。

## 1. 故障一：交互式 pwsh 假死

表现为提示符已经画出，但键入无回显、回车不执行，Ctrl-C 与 Ctrl-D 均无反应；外层通常是 zsh 或其他 shell，pwsh 是它启动的子进程（例如在 pwsh 或 zsh 中再执行 `pwsh`）。

实测判据（2026-11-08，本机）：

- `ps -o stat,%cpu` 显示该进程为 `S+`、CPU 接近 0，说明不是死循环。
- 该会话对应的 `/dev/ttysN` 存在未读输入：用 `FIONREAD` 读到数十字节（本次为 85 字节），且长时间不减少。
- `sample` 采样显示所有线程停在条件变量等待上，包括 `PSReadLine ReadKey Thread` 的 `WaitHandle_WaitMultipleIgnoringSyncContext`。

结论：按键已经进入终端输入队列，但进程侧没有消费者；故障点在 pwsh 的交互读取与重绘链路，不是命令执行阻塞，也不是终端未投递。触发条件尚未用受控实验确认，目前只观察到与“面板失焦、切换面板、嵌套启动”同处一个时间窗（待验证）。

## 2. 故障二：面板关闭后 pwsh 残留并占满 CPU

表现为一个 core 长期 100% 占用、面板已不存在，进程仍在 `ps` 中。实测样本：四个残留 pwsh 中有两个稳定 99% CPU，累计 CPU 时间达 19 分钟；其余两个停在 0% 的空等状态。

判据与取证顺序：

- `ps -Axo pid,ppid,stat,%cpu,etime,tty,command` 中筛选 `pwsh`：`R+`、`%cpu` 接近 99、`tty` 仍指向 `/dev/ttysN`。
- 父进程是 `login -pflq <user> /opt/homebrew/bin/pwsh`，且该 tty 已不属于任何 cmux 面板。
- 从 `/dev/ttysN` 读取立即返回 EOF，说明 pty 的 master 端已经关闭，只剩 pwsh 持有 slave。
- `sample` 显示主线程全部时间在 `SystemNative_ReadStdin` → `__read_nocancel`，即 `read` 立即返回后又重试，形成忙等。

已排除的解释：单纯关闭 pty master 并不必然导致空转。同机实测 `bash -i`、`pwsh -NoProfile`、带完整 profile 的 `pwsh`，以及显式忽略 `SIGHUP` 的 `pwsh`，在 master 关闭后都会正常退出（变为僵尸、0% CPU）。因此残留空转只出现在“面板先消失、进程未被收走”的半关闭状态，属于收尾缺口而非 EOF 语义本身。

## 3. 推荐处置

### 3.1 立即处置

对判定的残留进程执行 `kill -9 <pid>`；其 `login` 父壳会随之退出，不会留下新的僵尸。本次清理四个进程后释放约两个核心的持续占用。

### 3.2 防复发

- 关闭面板前先在会话里执行 `exit`，让 pwsh 走正常退出路径；不要直接关 tab 或窗口。
- 需要嵌套交互式 shell 时，改为在终端里新开面板或标签页，或使用 `tmux` 隔离 pty；避免在 pwsh 内再启动一个交互式 pwsh。
- 新开会话时顺带巡检残留进程（判定片段见 3.3），默认只报告，确认后再终止。
- 上游修复方向：终端应用关闭 surface 时应向子进程组补发 `SIGHUP` → `SIGTERM` → `SIGKILL`；PowerShell 在 stdin 读到 EOF 时应退出，而不是空转或空等。两条都需要分别向上游反馈。

### 3.3 巡检片段

列出候选进程：

```bash
ps -Axo pid,ppid,%cpu,etime,tty,command | grep '[p]wsh'
```

判定 tty 是否还有终端在另一端。该片段只做可读性检查，不读取字节，因此不会吃掉待处理按键：

```python
#!/usr/bin/env python3
# 只读判定：select 不可读 = 终端健在且无积压；可读 = EOF 或按键积压，均为异常候选
import os, select, subprocess

out = subprocess.run(["ps", "-Axo", "pid=,tty=,command="], capture_output=True, text=True).stdout
for line in out.splitlines():
    parts = line.split(None, 2)
    if len(parts) < 3:
        continue
    pid, tty, cmd = parts
    if "pwsh" not in cmd or not tty.startswith("tty"):
        continue
    try:
        fd = os.open("/dev/" + tty, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        continue
    try:
        readable = bool(select.select([fd], [], [], 0)[0])
        print(f"{pid}\t{tty}\t{'候选(EOF或积压)' if readable else '正常'}")
    finally:
        os.close(fd)
```

确认候选后按 3.1 终止。若要把判定做进 `init` 或定时任务，应先补“排除自身会话、排除刚启动会话”的条件，再默认只报告。

## 4. 版本与终端归因（待验证）

故障出现在 pwsh 升级到 7.6.9（PSReadLine 2.4.5）当日，因此版本回归是首要嫌疑，但尚未做对照实验。确认顺序：

- 用 `pwsh -NoProfile` 复现嵌套假死，判断是否与 profile 中的 PSReadLine 选项（`PredictionViewStyle` 等）相关。
- 在 WezTerm 等非 Ghostty 内核终端重复同一操作，判断是否与 cmux 的输入投递或重绘相关。
- 安装旧版 PSReadLine（2.3.6）或回退 pwsh 7.5.x 后重复，判断是否为版本回归。

三项结论出来前，不要把这轮故障归因为 profile 配置，也不要据此改动 `init`。

## 5. 已知缺口

- 托管栈尚未获取。`sample` 只能看到原生的 `read`、`__psynch_cvwait`，看不到托管调用帧；定位到具体调用需要 `dotnet-stack` 或 `dotnet-dump`（本机未安装，安装前需确认下载来源与范围）。
- 假死与“面板失焦、切换、嵌套启动”的时间相关性只有现场观察，没有受控复现；残留学说中的“半关闭状态”同样是现场归纳，未在受控 pty 中复刻。
- 巡检片段基于 tty 可读性判定，对“终端健在但按键积压”的会话同样会报候选，属预期行为，处置前应按 3.1 复核进程来源。
