#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ipctl"
INSTALL_PATH="/usr/local/sbin/${APP_NAME}"
CONFIG_FILE="/etc/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

ACTION=""
IFACE=""
ADDRESS=""
IMPORT_FILE=""
NO_APPLY=0
KEEP_LIVE=0
YES=0

die() {
  echo "错误: $*" >&2
  exit 1
}

info() {
  echo "[INFO] $*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 运行，例如: sudo $0 $*"
  fi
}

usage() {
  cat <<'EOF'
ipctl - Ubuntu VPS 多 IP 一键绑定工具

用法:
  ipctl install [-i 网卡]
  ipctl add -a IP/CIDR [-i 网卡] [--no-apply]
  ipctl del -a IP/CIDR [-i 网卡] [--keep-live]
  ipctl import -f 文件 [-i 网卡] [--no-apply]
  ipctl list
  ipctl apply
  ipctl reload
  ipctl flush-config --yes
  ipctl -h | --help

动作:
  install             安装脚本到 /usr/local/sbin，并创建 systemd 开机绑定服务
  add                 添加一个 IP/CIDR 到配置，并默认立即绑定
  del                 从配置删除一个 IP/CIDR，并默认立即从网卡移除
  import              从文件批量导入 IP
  list                查看配置中的 IP，以及当前网卡已绑定 IP
  apply               立即应用配置文件中的所有 IP
  reload              重载 systemd，并启用开机自动绑定
  flush-config        清空配置文件，需要 --yes 确认

参数:
  -i, --iface 网卡     指定网卡，例如 eth0、ens3、enp1s0
  -a, --addr IP/CIDR   指定 IP，例如 192.0.2.10/32 或 2001:db8::10/128
  -f, --file 文件      批量导入文件
  --no-apply           只写入配置，不立即绑定
  --keep-live          删除配置时，不立即从网卡移除该 IP
  --yes                用于危险操作确认
  -h, --help           显示帮助

导入文件格式:
  支持每行一个 IP/CIDR:
    192.0.2.10/32
    192.0.2.11/32
    2001:db8::10/128

  也支持每行指定网卡:
    eth0 192.0.2.10/32
    eth0 192.0.2.11/32
    ens3 2001:db8::10/128

  空行和 # 注释会被忽略。

常见用例:
  sudo ipctl install
  sudo ipctl add -a 192.0.2.10/32
  sudo ipctl add -i eth0 -a 192.0.2.11/32
  sudo ipctl import -f ips.txt -i eth0
  sudo ipctl del -a 192.0.2.10/32
  sudo ipctl list
  sudo ipctl apply

说明:
  该脚本使用 ip address add/del 绑定额外 IP，并通过 systemd 在开机后恢复。
  它不会直接修改 Netplan，适合大多数 Ubuntu VPS 多 IP 绑定场景。
EOF
}

detect_iface() {
  local dev
  dev="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  [[ -n "${dev}" ]] || die "无法自动检测默认网卡，请使用 -i 指定，例如 -i eth0"
  echo "${dev}"
}

validate_iface() {
  local dev="$1"
  ip link show "${dev}" >/dev/null 2>&1 || die "网卡不存在: ${dev}"
}

validate_cidr() {
  local cidr="$1"

  [[ "${cidr}" == */* ]] || die "地址必须包含 CIDR 前缀，例如 192.0.2.10/32"

  local prefix="${cidr##*/}"
  [[ "${prefix}" =~ ^[0-9]+$ ]] || die "CIDR 前缀无效: ${cidr}"

  if [[ "${cidr}" == *:* ]]; then
    (( prefix >= 0 && prefix <= 128 )) || die "IPv6 前缀必须在 0-128: ${cidr}"
  else
    (( prefix >= 0 && prefix <= 32 )) || die "IPv4 前缀必须在 0-32: ${cidr}"
  fi
}

ensure_config() {
  touch "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}"
}

normalize_iface() {
  if [[ -n "${IFACE}" ]]; then
    echo "${IFACE}"
  else
    detect_iface
  fi
}

line_exists() {
  local dev="$1"
  local cidr="$2"
  [[ -f "${CONFIG_FILE}" ]] || return 1
  awk -v d="${dev}" -v a="${cidr}" '$1 == d && $2 == a { found=1 } END { exit !found }' "${CONFIG_FILE}"
}

live_exists() {
  local dev="$1"
  local cidr="$2"
  ip -o addr show dev "${dev}" 2>/dev/null | awk '{print $4}' | grep -Fxq "${cidr}"
}

add_live() {
  local dev="$1"
  local cidr="$2"

  validate_iface "${dev}"
  validate_cidr "${cidr}"

  if live_exists "${dev}" "${cidr}"; then
    info "已绑定，跳过: ${dev} ${cidr}"
    return 0
  fi

  ip address add "${cidr}" dev "${dev}"
  info "已绑定: ${dev} ${cidr}"
}

del_live() {
  local dev="$1"
  local cidr="$2"

  validate_iface "${dev}"
  validate_cidr "${cidr}"

  if live_exists "${dev}" "${cidr}"; then
    ip address del "${cidr}" dev "${dev}"
    info "已从网卡移除: ${dev} ${cidr}"
  else
    info "当前未绑定，跳过移除: ${dev} ${cidr}"
  fi
}

add_config() {
  local dev="$1"
  local cidr="$2"

  ensure_config
  validate_iface "${dev}"
  validate_cidr "${cidr}"

  if line_exists "${dev}" "${cidr}"; then
    info "配置已存在，跳过: ${dev} ${cidr}"
  else
    echo "${dev} ${cidr}" >> "${CONFIG_FILE}"
    info "已写入配置: ${dev} ${cidr}"
  fi
}

del_config() {
  local dev="$1"
  local cidr="$2"

  [[ -f "${CONFIG_FILE}" ]] || {
    info "配置文件不存在，无需删除"
    return 0
  }

  local tmp
  tmp="$(mktemp)"

  awk -v d="${dev}" -v a="${cidr}" '!( $1 == d && $2 == a )' "${CONFIG_FILE}" > "${tmp}"
  cat "${tmp}" > "${CONFIG_FILE}"
  rm -f "${tmp}"

  info "已从配置删除: ${dev} ${cidr}"
}

install_self() {
  local dev
  dev="$(normalize_iface)"
  validate_iface "${dev}"

  install -m 0755 "$0" "${INSTALL_PATH}"
  ensure_config

  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Bind extra VPS IP addresses
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${APP_NAME}.service" >/dev/null

  info "已安装脚本: ${INSTALL_PATH}"
  info "已创建服务: ${SERVICE_FILE}"
  info "已启用开机自动绑定服务"
  info "默认检测网卡为: ${dev}"
}

reload_service() {
  systemctl daemon-reload
  systemctl enable "${APP_NAME}.service" >/dev/null
  info "已重载 systemd 并启用 ${APP_NAME}.service"
}

apply_all() {
  [[ -f "${CONFIG_FILE}" ]] || {
    info "配置文件不存在: ${CONFIG_FILE}"
    return 0
  }

  local count=0

  while read -r dev cidr extra; do
    [[ -z "${dev:-}" ]] && continue
    [[ "${dev}" =~ ^# ]] && continue
    [[ -z "${cidr:-}" ]] && continue
    [[ -n "${extra:-}" ]] && die "配置行格式错误: ${dev} ${cidr} ${extra}"

    add_live "${dev}" "${cidr}"
    count=$((count + 1))
  done < "${CONFIG_FILE}"

  info "应用完成，共处理 ${count} 条配置"
}

list_all() {
  echo "配置文件: ${CONFIG_FILE}"
  echo

  if [[ -f "${CONFIG_FILE}" && -s "${CONFIG_FILE}" ]]; then
    echo "已配置的额外 IP:"
    awk 'NF >= 2 && $1 !~ /^#/ { printf "  %-12s %s\n", $1, $2 }' "${CONFIG_FILE}"
  else
    echo "已配置的额外 IP: 无"
  fi

  echo
  echo "当前系统网卡 IP:"
  ip -o addr show | awk '{ printf "  %-12s %s\n", $2, $4 }'
}

import_file() {
  local file="$1"
  local default_dev="$2"

  [[ -f "${file}" ]] || die "导入文件不存在: ${file}"

  local count=0

  while read -r col1 col2 rest; do
    [[ -z "${col1:-}" ]] && continue
    [[ "${col1}" =~ ^# ]] && continue
    [[ -n "${rest:-}" ]] && die "导入文件行格式错误: ${col1} ${col2:-} ${rest}"

    local dev cidr

    if [[ -n "${col2:-}" ]]; then
      dev="${col1}"
      cidr="${col2}"
    else
      dev="${default_dev}"
      cidr="${col1}"
    fi

    add_config "${dev}" "${cidr}"

    if [[ "${NO_APPLY}" -eq 0 ]]; then
      add_live "${dev}" "${cidr}"
    fi

    count=$((count + 1))
  done < "${file}"

  info "导入完成，共处理 ${count} 条"
}

flush_config() {
  [[ "${YES}" -eq 1 ]] || die "清空配置需要加 --yes"
  : > "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}"
  info "已清空配置文件: ${CONFIG_FILE}"
}

parse_args() {
  [[ $# -eq 0 ]] && {
    usage
    exit 0
  }

  ACTION="$1"
  shift || true

  case "${ACTION}" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--iface)
        IFACE="${2:-}"
        [[ -n "${IFACE}" ]] || die "-i/--iface 需要参数"
        shift 2
        ;;
      -a|--addr|--address)
        ADDRESS="${2:-}"
        [[ -n "${ADDRESS}" ]] || die "-a/--addr 需要参数"
        shift 2
        ;;
      -f|--file)
        IMPORT_FILE="${2:-}"
        [[ -n "${IMPORT_FILE}" ]] || die "-f/--file 需要参数"
        shift 2
        ;;
      --no-apply)
        NO_APPLY=1
        shift
        ;;
      --keep-live)
        KEEP_LIVE=1
        shift
        ;;
      --yes)
        YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  case "${ACTION}" in
    install)
      need_root "$@"
      install_self
      ;;

    add)
      need_root "$@"
      [[ -n "${ADDRESS}" ]] || die "add 需要 -a IP/CIDR"
      local dev_add
      dev_add="$(normalize_iface)"
      add_config "${dev_add}" "${ADDRESS}"
      if [[ "${NO_APPLY}" -eq 0 ]]; then
        add_live "${dev_add}" "${ADDRESS}"
      fi
      ;;

    del|delete|remove)
      need_root "$@"
      [[ -n "${ADDRESS}" ]] || die "del 需要 -a IP/CIDR"
      local dev_del
      dev_del="$(normalize_iface)"
      del_config "${dev_del}" "${ADDRESS}"
      if [[ "${KEEP_LIVE}" -eq 0 ]]; then
        del_live "${dev_del}" "${ADDRESS}"
      fi
      ;;

    import)
      need_root "$@"
      [[ -n "${IMPORT_FILE}" ]] || die "import 需要 -f 文件"
      local dev_import
      dev_import="$(normalize_iface)"
      import_file "${IMPORT_FILE}" "${dev_import}"
      ;;

    apply)
      need_root "$@"
      apply_all
      ;;

    list)
      list_all
      ;;

    reload)
      need_root "$@"
      reload_service
      ;;

    flush-config)
      need_root "$@"
      ensure_config
      flush_config
      ;;

    *)
      die "未知动作: ${ACTION}，使用 -h 查看帮助"
      ;;
  esac
}

main "$@"