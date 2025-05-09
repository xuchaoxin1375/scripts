  cd ~
  #和powershell不同,变量定义时不需要$符号,引用的时候才需要
  conf_dir="/d/repos/scripts/linuxShellScripts"
  ln -s $conf_dir -f
  # 可以考虑备份原有的.zshrc
  # cp .zshrc .zshrc_bak
  # ln采用-f选项,自动删除掉已有的文件.zshrc文件
  
  ln -s $conf_dir/.zshrc .zshrc -f
  source $conf_dir/importer.sh