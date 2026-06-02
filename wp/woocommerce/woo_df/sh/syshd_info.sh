#!/bin/bash
# 功能全面的 Bash 脚本。它会以整洁、带颜色的排版输出 Linux 服务器的系统、CPU、内存、磁盘和网络的核心配置信息。
# 
# 对于有root权限用户,可以使用lshw命令查看信息:
# 简要摘要版（推荐，不然输出会刷屏）
# sudo lshw -short
# 仅查看指定类别的硬件（例如类目为 memory 或 processor）
# sudo lshw -C memory


# 定义颜色常量
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色 (Reset)

echo -e "${YELLOW}==================================================${NC}"
echo -e "${YELLOW}               Linux 服务器配置信息               ${NC}"
echo -e "${YELLOW}==================================================${NC}"

# 1. 系统信息
echo -e "\n${CYAN}[1. 系统与内核信息]${NC}"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo -e "发行版本:    ${GREEN}$PRETTY_NAME${NC}"
else
    echo -e "发行版本:    ${GREEN}$(uname -o)${NC}"
fi
echo -e "内核版本:    ${GREEN}$(uname -r)${NC}"
echo -e "主机名称:    ${GREEN}$(hostname)${NC}"
echo -e "运行时间:    ${GREEN}$(uptime -p)${NC}"

# 2. CPU 信息
echo -e "\n${CYAN}[2. CPU 配置]${NC}"
CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//')
if [ -z "$CPU_MODEL" ]; then
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | uniq | awk -F': ' '{print $2}')
fi
CPU_CORES=$(nproc)
CPU_SOCKETS=$(lscpu | grep "Socket(s):" | awk '{print $2}')
echo -e "CPU 型号:    ${GREEN}$CPU_MODEL${NC}"
echo -e "物理插槽:    ${GREEN}${CPU_SOCKETS:-1}${NC}"
echo -e "逻辑核心数:  ${GREEN}$CPU_CORES${NC}"

# 3. 内存信息
echo -e "\n${CYAN}[3. 内存与 Swap 容量]${NC}"
# 提取物理内存 (Total / Used)
MEM_INFO=$(free -h | grep Mem)
MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
MEM_FREE=$(echo "$MEM_INFO" | awk '{print $7}') # 可用内存

# 提取 Swap
SWAP_INFO=$(free -h | grep Swap)
SWAP_TOTAL=$(echo "$SWAP_INFO" | awk '{print $2}')
SWAP_USED=$(echo "$SWAP_INFO" | awk '{print $3}')

echo -e "物理内存:    总共: ${GREEN}$MEM_TOTAL${NC} | 已用: ${RED}$MEM_USED${NC} | 实际可用: ${GREEN}$MEM_FREE${NC}"
echo -e "Swap 空间:   总共: ${GREEN}$SWAP_TOTAL${NC} | 已用: ${RED}$SWAP_USED${NC}"

# 4. 磁盘挂载与空间
echo -e "\n${CYAN}[4. 磁盘使用率 (仅主要挂载点)]${NC}"
echo -e "${YELLOW}文件系统          容量   已用   可用   已用%   挂载点${NC}"
df -h -x tmpfs -x devtmpfs -x squashfs | grep -v "Filesystem" | while read -r line; do
    echo -e "${GREEN}$line${NC}"
done

# 5. 网络信息
echo -e "\n${CYAN}[5. 网络与 IP 配置]${NC}"
# 获取内网 IP（排除 loopback 和 docker 等虚拟网卡）
INTERNAL_IPS=$(ip -o -4 addr show | awk '{print $2, $4}' | grep -vE 'lo|docker|veth|br-' | awk '{print $2}' | cut -d/ -f1)
echo -e "局域网 IP:"
for ip in $INTERNAL_IPS; do
    echo -e "             - ${GREEN}$ip${NC}"
done

# 获取公网 IP (带 2 秒超时防止卡死)
PUBLIC_IP=$(curl -s --connect-timeout 2 ifconfig.me 2> /dev/null)
if [ -n "$PUBLIC_IP" ]; then
    echo -e "公网 IP:     ${GREEN}$PUBLIC_IP${NC}"
else
    echo -e "公网 IP:     ${RED}获取失败或无外网连接${NC}"
fi

echo -e "\n${YELLOW}==================================================${NC}"
