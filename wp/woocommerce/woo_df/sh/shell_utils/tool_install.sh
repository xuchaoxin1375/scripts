#!/usr/bin/env bash
install_fresh() {
    echo "Install fresh-editor from github...(f your network connection is poor, consider using a proxy.)"
    curl https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh | sh
}
