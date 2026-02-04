#!/bin/bash
woostify_pattern='/www/wwwroot/*/*/wordpress/wp-content/themes/woostify'
pattern='../../plugins/woocommerce/assets/client/blocks/cart.css'
new_css='/www/cart.css'
cnt=0
for woostify_theme in $woostify_pattern
do
  if [ -e "$woostify_theme" ] ; then
    cnt=$((cnt+1))
    css="$woostify_theme/$pattern"
    # [[ -e $css ]] && echo "[INFO:$cnt] Updating [$css]"
    if [[ -e $css ]] ; then
        cp -fv $new_css $css
    else
        echo "[WARN:$cnt] File not found: [$css]"
    fi
  fi
done
