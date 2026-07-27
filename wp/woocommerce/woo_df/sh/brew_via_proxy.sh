#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/brew-via-proxy <brew arguments...>

Run one Homebrew command against the official Git, API, and bottle endpoints
through an explicit HTTP proxy. Existing shell mirror settings are not changed.

Environment:
  HOMEBREW_PROXY_URL  Proxy URL (default: http://127.0.0.1:7890)

Examples:
  ./scripts/brew-via-proxy install gdu
  ./scripts/brew-via-proxy reinstall --force-bottle fd
  HOMEBREW_PROXY_URL=http://127.0.0.1:7890 ./scripts/brew-via-proxy update
EOF
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

command -v brew >/dev/null 2>&1 || {
  printf '%s\n' 'ERROR: brew was not found in PATH.' >&2
  exit 1
}

proxy_url="${HOMEBREW_PROXY_URL:-http://127.0.0.1:7890}"
case "${proxy_url}" in
  http://*|https://*) ;;
  *)
    printf '%s\n' 'ERROR: HOMEBREW_PROXY_URL must use http:// or https://.' >&2
    exit 2
    ;;
esac

export HTTP_PROXY="${proxy_url}"
export HTTPS_PROXY="${proxy_url}"
export http_proxy="${proxy_url}"
export https_proxy="${proxy_url}"

export HOMEBREW_BREW_GIT_REMOTE="https://github.com/Homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://github.com/Homebrew/homebrew-core.git"
export HOMEBREW_API_DOMAIN="https://formulae.brew.sh/api"
export HOMEBREW_BOTTLE_DOMAIN="https://ghcr.io/v2/homebrew/core"

# Do not send credentials intended for a private artifact mirror to GHCR.
unset HOMEBREW_ARTIFACT_DOMAIN
unset HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN
unset HOMEBREW_DOCKER_REGISTRY_TOKEN

exec brew "$@"
