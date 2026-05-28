#! /bin/bash
# 根据包名(部分名)清理不在需要的包文件,例如网站压缩包
FIND_BASE="/www/wwwroot/xcx/" #可以自行酌情增加精确度,比如添加服务器名到路径中
# 参数解析
args_pos=()
parse_args() {
    usage="
    $0 [options] FIND_BASE
    options:
        -h, --help    显示帮助信息
    "
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            --)
                shift
                break 
                ;;
            -?*)
                echo "Unknown option: " >&2 #输出错误信息到标准错误
                echo "$usage" >&2
                exit 2 #直接退出脚本
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 参数解析并调整完毕
}
parse_args "$@"
set -- "${args_pos[@]}"

FIND_BASE="${1:-$FIND_BASE}" #如果用户提供了参数则覆盖默认值
file_names=(
    thepethutco.com
    useffortlessmart.com
    deindealdorf.com
    cdandscore.com
    wohnmobildeal.com
    germanlifeparts.com
    homepartssolutions.com
    livingaccessoriesde.com
    wisehomeshopping.com
    parislivingshop.com
    usacarpartsexpress.com
    essentiel-hab.com
    ukpartplace.com
    valuehub24.com
    autoteileplus.com
    shoplabgear.com
    foodtrailus.com
    libropulsor.com
    plantacionhogar.com
    german-visionshop.com
    occhialiday.com
    oggitutto.com
    germabeauty.com
    derweinladende.com
    highstreetvault.com
    bladehubus.com
    mesapantry.com
    faitletemps.com
    ateliermaisonfr.com
    klugbuch.com
    leselotse.com
    diversionshop.com
    grabmartpro.com
    toutdedans.com
    sietediasfull.com
    milcosasbuenas.com
    ukplugpro.com
    geschichtenhafen.com
    papierwald.com
    snugbuyuk.com
    laboverte.com
    bearingrevolution-uk.com
    calidadprecioya.com
    todoparatiya.com
    plazageneral.com
    chassfolk.com
    palabraytinta.com
    rinconletras.com
    bookauralive.com
    britstorybox.com
    isleofreads.com
    londonleafs.com
    panierconfiant.com
    quietchapteres.com
    ukbookharbor.com
    monexpert-maison.com
    dolceguida.com
    homedepotly.com
    frtirshop.com
    shop365tir.com
    joyloompro.com
    librosenvivo.com
    elektroplatt.com
    easyfrancedaily.com
    energiefra.com
    buenoshogares.com
    bouquinpassion.com
    ukstudiosupply.com
    homemartfr.com
)
# 检查白名单数组
# declare -p file_names

for name in "${file_names[@]}"; do
    echo "正在尝试清理包含 '$name' 的包文件..."
    # find $FIND_BASE -type f -name "$name.*"  # -exec rm -f {} \;
    find "$FIND_BASE" -type f -regextype posix-extended -regex ".*/$name(\..*)?\.(zip|zst|lz4|7z|gz|gzip)" -exec rm -fv {} +
done
