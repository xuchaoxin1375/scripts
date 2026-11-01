#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 脚本名称: notify-email.sh
# 功能描述: 读取 probe.sh 生成的通知文件,通过既有 SMTP 发信服务投递邮件.
#           消息格式为: 第一行主题,其余为正文.
# 用法:     ./notify-email.sh < 消息文件
#           ./notify-email.sh --test --env ./notify.env
# 退出码:   0 投递成功; 1 配置或投递失败; 2 用法错误
# 注意:     本文件换行必须为 LF.凭据只从环境文件读取,不写入命令行参数或日志.
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly SCRIPT_DIR
readonly VERSION="20261101.01"

ENV_FILE="${NOTIFY_ENV:-$SCRIPT_DIR/notify.env}"
TEST_MODE=false
SUBJECT=""
BODY=""

log() {
  printf '[%s] INFO:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
$SCRIPT_NAME [version:$VERSION] - 拨测通知邮件发送适配器.

说明:
  从标准输入读取消息,第一行为邮件主题,其余行为正文.
  通过 notify.env 中配置的 SMTP 服务发送,不启动本地邮件服务器.
  凭据只从环境文件读取,脚本不输出密码.

用法:
  $SCRIPT_NAME < 消息文件
  $SCRIPT_NAME --test [--env FILE]

选项:
  --env FILE   指定环境文件,默认 $SCRIPT_DIR/notify.env
  --test       发送一封测试邮件,不读取标准输入
  --help       显示本帮助
  --version    显示版本

环境文件字段:
  SMTP_URL        必需,例如 smtps://smtp.example.com:465
  SMTP_USER       可选,SMTP 用户名;与 SMTP_PASS 同时使用
  SMTP_PASS       可选,SMTP 密码或授权码
  SMTP_STARTTLS   可选,值为 1 时要求 STARTTLS,适用于 smtp:// 入口
  SMTP_CA_BUNDLE  可选,自定义 CA 证书路径
  MAIL_FROM       必需,发件人地址
  MAIL_TO         必需,收件人地址,多个地址用逗号分隔
  MAIL_TIMEOUT    可选,发送超时秒数,默认 30

退出码:
  0 投递成功;1 配置或投递失败;2 用法错误
EOF
}

while (($# > 0)); do
  case "$1" in
  --env)
    [[ $# -ge 2 ]] || die "--env 缺少参数"
    ENV_FILE="$2"
    shift
    ;;
  --test)
    TEST_MODE=true
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --version)
    printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
    exit 0
    ;;
  *)
    usage >&2
    die "未知参数: $1"
    ;;
  esac
  shift
done

if [[ ! -r $ENV_FILE ]]; then
  die "无法读取环境文件: $ENV_FILE"
fi

env_perms="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || printf 'unknown')"
case "$env_perms" in
600 | 400) ;;
unknown) warn "无法确认环境文件权限: $ENV_FILE" ;;
*) warn "环境文件权限为 $env_perms,建议收紧为 600: $ENV_FILE" ;;
esac

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

[[ -n ${SMTP_URL:-} ]] || die "SMTP_URL 未配置"
[[ -n ${MAIL_FROM:-} ]] || die "MAIL_FROM 未配置"
[[ $MAIL_FROM == *@* ]] || die "MAIL_FROM 地址格式不正确"
[[ -n ${MAIL_TO:-} ]] || die "MAIL_TO 未配置"
if [[ -n ${SMTP_USER:-} && -z ${SMTP_PASS:-} ]]; then
  die "已配置 SMTP_USER 但缺少 SMTP_PASS"
fi
if [[ -n ${SMTP_PASS:-} && -z ${SMTP_USER:-} ]]; then
  die "已配置 SMTP_PASS 但缺少 SMTP_USER"
fi

MAIL_TIMEOUT="${MAIL_TIMEOUT:-30}"
[[ $MAIL_TIMEOUT =~ ^[0-9]+$ ]] || die "MAIL_TIMEOUT 应为整数秒"

if [[ $TEST_MODE == true ]]; then
  SUBJECT="[拨测] 测试邮件"
  BODY="这是一封由 uptime_checks 发送的测试邮件。
时间: $(date '+%Y-%m-%d %H:%M:%S %z')
主机: $(uname -n 2>/dev/null || printf 'unknown')

收到本邮件说明 SMTP 发信配置可用。"
else
  IFS= read -r SUBJECT || true
  BODY="$(cat)"
fi

SUBJECT="${SUBJECT//$'\r'/}"
SUBJECT="${SUBJECT//$'\n'/ }"
[[ -n $SUBJECT ]] || die "消息缺少主题行"

recipients=()
IFS=', ' read -r -a recipients <<<"$MAIL_TO"
if ((${#recipients[@]} == 0)); then
  die "MAIL_TO 未解析出有效收件人"
fi
for rcpt in "${recipients[@]}"; do
  [[ $rcpt == *@* ]] || die "收件人地址格式不正确: $rcpt"
done

if [[ $SUBJECT == *[![:print:]]* ]] || LC_ALL=C grep -q '[^ -~]' <<<"$SUBJECT"; then
  encoded_subject="=?UTF-8?B?$(printf '%s' "$SUBJECT" | base64 | tr -d '\n')?="
else
  encoded_subject="$SUBJECT"
fi

from_domain="${MAIL_FROM#*@}"
[[ $from_domain == "$MAIL_FROM" ]] && from_domain="localhost"

build_message() {
  printf 'From: %s\n' "$MAIL_FROM"
  printf 'To: %s\n' "$MAIL_TO"
  printf 'Subject: %s\n' "$encoded_subject"
  printf 'Date: %s\n' "$(date -R)"
  printf 'Message-ID: <%s.%s@%s>\n' "$(date +%s)" "$$" "$from_domain"
  printf 'MIME-Version: 1.0\n'
  printf 'Content-Type: text/plain; charset=UTF-8\n'
  printf 'Content-Transfer-Encoding: 8bit\n'
  printf '\n'
  printf '%s\n' "$BODY"
}

message_crlf="$(build_message | sed 's/$/\r/')"

curl_args=(
  --disable
  --silent
  --show-error
  --max-time "$MAIL_TIMEOUT"
  --url "$SMTP_URL"
  --mail-from "$MAIL_FROM"
  --upload-file -
)
for rcpt in "${recipients[@]}"; do
  curl_args+=(--mail-rcpt "$rcpt")
done
if [[ ${SMTP_STARTTLS:-0} == 1 ]]; then
  curl_args+=(--ssl-reqd)
fi
if [[ -n ${SMTP_CA_BUNDLE:-} ]]; then
  [[ -r $SMTP_CA_BUNDLE ]] || die "SMTP_CA_BUNDLE 不可读: $SMTP_CA_BUNDLE"
  curl_args+=(--cacert "$SMTP_CA_BUNDLE")
fi
if [[ -n ${SMTP_USER:-} ]]; then
  curl_args+=(--user "$SMTP_USER:$SMTP_PASS")
fi

if ! printf '%s\r\n' "$message_crlf" | curl "${curl_args[@]}"; then
  die "邮件投递失败,请检查 SMTP 地址、凭据、网络与收件人限制"
fi

log "邮件已提交: $SUBJECT"
