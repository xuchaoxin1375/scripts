Get-ChildItem -Path $wp_sites/*.* -Directory -Exclude 8.us | ForEach-Object { 
    # wp theme list --path=$_ 
    wp option get wpseo_titles --format=var_export | Select-String "归档"
} 


