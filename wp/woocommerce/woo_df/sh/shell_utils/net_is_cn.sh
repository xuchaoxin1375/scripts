# 获取当前公网出口的国家代码。
#
# 输出：
#   CN、US、JP 等两位国家代码
#
# 返回值：
#   0  获取成功
#   2  所有接口均不可用
#
# 环境变量：
#   NET_COUNTRY_TIMEOUT  单个接口超时时间，默认 4 秒
#   NET_COUNTRY_DIRECT   设为 1 时绕过 curl 显式代理
#
# 示例：
#   net_country
#   NET_COUNTRY_DIRECT=1 net_country
net_country() {
    local timeout="${NET_COUNTRY_TIMEOUT:-4}"
    local body code
    local -a curl_opts=(
        --fail
        --silent
        --show-error
        --location
        --connect-timeout "$timeout"
        --max-time "$timeout"
        --user-agent "net-country-check/1.0"
    )

    # 默认尊重 http_proxy、https_proxy、all_proxy。
    # 设置 NET_COUNTRY_DIRECT=1 可绕过 curl 显式代理。
    if [[ "${NET_COUNTRY_DIRECT:-0}" == "1" ]]; then
        curl_opts+=(--noproxy '*')
    fi

    # 1. country.is
    body=$(curl "${curl_opts[@]}" 'https://api.country.is/' 2>/dev/null) || body=""

    code=$(
        printf '%s' "$body" |
            sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' |
            head -n 1 |
            tr '[:lower:]' '[:upper:]'
    )

    if [[ "$code" =~ ^[A-Z]{2}$ ]]; then
        printf '%s\n' "$code"
        return 0
    fi

    # 2. ipapi.co
    code=$(
        curl "${curl_opts[@]}" \
            'https://ipapi.co/country/' 2>/dev/null |
            tr -d '[:space:]' |
            tr '[:lower:]' '[:upper:]'
    )

    if [[ "$code" =~ ^[A-Z]{2}$ ]]; then
        printf '%s\n' "$code"
        return 0
    fi

    # 3. ifconfig.co
    code=$(
        curl "${curl_opts[@]}" \
            'https://ifconfig.co/country-iso' 2>/dev/null |
            tr -d '[:space:]' |
            tr '[:lower:]' '[:upper:]'
    )

    if [[ "$code" =~ ^[A-Z]{2}$ ]]; then
        printf '%s\n' "$code"
        return 0
    fi

    return 2
}


# 判断当前公网出口是否在国内。
#
# 默认：
#   仅 CN（中国大陆）算国内。
#
# 可通过 NET_CN_CODES 修改：
#   NET_CN_CODES="CN HK MO" net_is_cn
#
# 参数：
#   --print  同时输出国家代码；无法判断时输出 UNKNOWN
#
# 返回值：
#   0  国内
#   1  国外
#   2  无法判断
net_is_cn() {
    local code
    local domestic_codes="${NET_CN_CODES:-CN}"
    local print_result=0

    case "${1:-}" in
        "")
            ;;
        --print)
            print_result=1
            ;;
        *)
            printf '用法：net_is_cn [--print]\n' >&2
            return 64
            ;;
    esac

    if ! code=$(net_country); then
        (( print_result )) && printf 'UNKNOWN\n'
        return 2
    fi

    (( print_result )) && printf '%s\n' "$code"

    case " $domestic_codes " in
        *" $code "*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}