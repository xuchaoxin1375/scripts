# 不同于aliases.sh
# 本文件中的内容的右值可能涉及到相互引用,而不仅仅是纯粹的字符串赋值,如果顺序不对,会导致达不到预期效果
# 被引用这需要往前写(被频繁引用需要写在文件头部.)
echo "setting the global envs done!"
#注意,指派新的环境变量注意别名环境变量名不是随便取的,要避免某些特殊值,比如aliases这个词不可以直接作为左值: attempt to set associative array to scalar
# export test_env_permanent="permanent!@cxxu"

export d="/mnt/d"
export c="/mnt/c"
export exes="$d/exes"
export repos="$d/repos"
export userProfile="$c/users/cxxu"
export downloads="$userProfile/downloads"
export compressed="$downloads/compressed"

export scripts="~"
export linuxShellScripts="$scripts/linuxShellScripts"
export aliasesConfig="$scripts/linuxShellScripts/aliases.sh"
export aliases_jumper="$linuxShellScripts/aliases_jumper.sh"

# export aliases="$linuxShellScripts/.aliases.sh"