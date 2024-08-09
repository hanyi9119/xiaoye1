#!/bin/bash

# 设置文件编码为 UTF-8
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8


######### 自定义常量 ##########

_constant() {
    script_version="v2024-08-04"
    work_dir="/root/speedtemp"
    # node=
    # TaierSpeed CLI，https://github.com/ztelliot/taierspeed-cli
    taier_cli_version="1.7.1"
    taier_cli_amd64_sha256="4a1a45ebad89b02b82f24cf7cb9bbd5c4ba878b0dcb4a2dbed2d532770201aa6"
    taier_cli_arm64_sha256="e99642639eb69bc04d0f8d4de6c3de03778a2a3ab9049c4c7db1c0c7abe7b2b5"
    taier_cli_armv7_sha256="87e7b68efa92051ecc8a4f805db05d7f03c18e55539215f90facd7dbc8bc4edc"
    taier_cli_url="https://res.yserver.ink/speedtest/taierspeed-cli_$taier_cli_arch"
    # 配色
    red='\033[1;31m'
    green='\033[1;32m'
    yellow='\033[1;33m'
    blue='\033[1;34m'
    purple='\033[1;35m'
    cyan='\033[1;36m'
    endc='\033[0m'
    onev4=("5 -n 1" "6 -n 1" "4 -n 1" "5012 -n 1" "5023 -n 1" "5001 -n 1" "1101 -n 1" "1103 -n 1" "1102 -n 1" "161 -n 1")
    fivev4=("5 -n 5" "6 -n 5" "4 -n 5" "5012 -n 5" "5023 -n 5" "5001 -n 5" "1101 -n 5" "1103 -n 5" "1102 -n 5" "161 -n 5")
    tenv4=("5 -n 10" "6 -n 10" "4 -n 10" "5012 -n 10" "5023 -n 10" "5001 -n 10" "1101 -n 10" "1103 -n 10" "1102 -n 10" "161 -n 10")
    onev6=("5 -n 1 -6" "6 -n 1 -6" "4 -n 1 -6" "5012 -n 1 -6" "5023 -n 1 -6" "5001 -n 1 -6" "1101 -n 1 -6" "1103 -n 1 -6" "1102 -n 1 -6" "161 -n 1 -6")
    fivev6=("5 -n 5 -6" "6 -n 5 -6" "4 -n 5 -6" "5012 -n 5 -6" "5023 -n 5 -6" "5001 -n 5 -6" "1101 -n 5 -6" "1103 -n 5 -6" "1102 -n 5 -6" "161 -n 5 -6")
    tenv6=("5 -n 10 -6" "6 -n 10 -6" "4 -n 10 -6" "5012 -n 10 -6" "5023 -n 10 -6" "5001 -n 10 -6" "1101 -n 10 -6" "1103 -n 10 -6" "1102 -n 10 -6" "161 -n 10 -6")
    name=("上海电信" "上海移动" "上海联通" "杭州电信" "杭州移动" "杭州联通" "广州电信" "广州移动" "广州联通" "上海教育")
}
check_ipv4() {
    echo 'Checking ipv4 support(max 10s)'
    v4_support=false
    ipv4=$(curl -4 -s ifconfig.co --connect-timeout 10) 
    if [ -n "$ipv4" ]; then
        v4_support=true
    fi
    echo $v4_support
}
check_ipv6() {
    echo 'Checking ipv6 support(max 10s)'
    v6_support=false
    ipv6=$(curl -6 -s ifconfig.co --connect-timeout 10)
    if [ -n "$ipv6" ]; then
        v6_support=true
    fi
    echo $v6_support
}
########## 横幅 ###########

_print_banner_1() {
    echo "------------------------ 多功能      测速脚本 ------------------------"
    echo -e " Version               : ${green}${script_version}${endc}"
    echo -e " Usage                 : ${yellow}bash <(curl -sL https://raw.githubusercontent.com/hanyi9119/xiaoye1/master/speed.sh)${endc}"
    #echo -e " GitHub                : ${green}https://github.com/i-abc/speedtest${endc}"
    printf "%-72s\n" "-" | sed 's)\s)-)g'
}

_print_banner_2() {
    echo "------------------------ 多功能 自更新 测速脚本 ------------------------"
    echo -e " Version               : ${green}${script_version}${endc}"
    echo -e " Usage                 : ${yellow}bash <(curl -sL https://raw.githubusercontent.com/hanyi9119/xiaoye1/master/speed.sh)${endc}"
    echo -e " Node                  : ${blue}${node_name}${endc}"
    printf "%-72s\n" "-" | sed 's)\s)-)g'
}
_print_banner_3() {
    printf "%-s%-s%-s%-s%-s\n" "测速节点            " "下载/Mbps      " "上传/Mbps      " "延迟/ms      " "抖动/ms"
}


########## 确认架构及其对应版本的程序 ##########

_check_architecture() {
    taier_cli_arch=""
    local arch
    arch="$(uname -m)"
    if [ "$arch" == "x86_64" ]; then
        taier_cli_arch="amd64"
    elif [ "$arch" == "i386" ] || [ "$arch" == "i686" ]; then
        echo "Unsupport architecture"
        exit 1
    elif [ "$arch" == "armv7" ] || [ "$arch" == "armv7l" ]; then
        taier_cli_arch="armv7"
    elif [ "$arch" == "armv6" ]; then
        echo "Unsupport architecture"
        exit 1
    elif [ "$arch" == "armv8" ] || [ "$arch" == "armv8l" ] || [ "$arch" == "aarch64" ] || [ "$arch" == "arm64" ]; then
        taier_cli_arch="arm64"
    fi
}

########## 下载程序 ##########

_download() {
    # 删除可能存在的残余文件
    rm -rf "$work_dir"
    # 创建目录
    mkdir "$work_dir"
    chmod 755 "$work_dir"
    curl  -o "$work_dir"/taierspeed-cli -L "$taier_cli_url"
    chmod +x "$work_dir"/taierspeed-cli
}

########## 检测程序的SHA-256 ##########

_check_sha256() {
    local taier_cli_real_sha256
    taier_cli_real_sha256=$(sha256sum "$work_dir"/taierspeed-cli | awk '{ print $1 }')
    if [ "$taier_cli_real_sha256" != "$(eval "echo \$taier_cli_${taier_cli_arch}_sha256")" ]; then
        printf "${red}%-s${endc}\n" "经检测，taierspeed-cli的SHA-256与官方不符，方便的话欢迎到GitHub反馈"
        exit 1
    fi
}

_check_num() {
    local num_input="$1"
    if [[ "$num_input" =~ ^[0-9]+(\.[0-9]+)?$ ]] && ! [[ "$num_input" =~ ^0+(\.0+)?$ ]]; then
        return 0
    else
        return 1
    fi
}
######### 选择节点列表 #############
_choose() {
    echo -e "${blue}↓    ↓    ↓    ↓    ↓    ↓   测速节点列表   ↓    ↓    ↓    ↓    ↓    ↓${endc}"
    echo '1. 大陆三网 单线程 IPV4'
    echo '2. 大陆三网 5线程  IPV4'
    echo '3. 大陆三网 10线程 IPV4'
    echo '4. 大陆三网 单线程 IPV6'
    echo '5. 大陆三网 5线程 IPV6'
    echo '6. 大陆三网 10线程 IPV6'
    read -p "请选择测速节点（输入序号）: " choose
    case $choose in
        1)
            if [ "$v4_support" == "false" ]; then
                echo 'No v4 support'
                exit 1
            fi
            node=("${onev4[@]}")
            node_name='大陆三网 单线程 IPV4'
            #name=("${onev4name[@]}")
            ;;
        2)
            if [ "$v4_support" == "false" ]; then
                echo 'No v4 support'
                exit 1
            fi
            node=("${fivev4[@]}")
            node_name='大陆三网 五线程 IPV4'
            ;;
        3)
            if [ "$v4_support" == "false" ]; then
                echo 'No v4 support'
                exit 1
            fi
            node=("${tenv4[@]}")
            node_name='大陆三网 十线程 IPV4'
            ;;
        4)
            if [ "$v6_support" == "false" ]; then
                echo 'No v6 support'
                exit 1
            fi
            node=("${onev6[@]}")
            node_name='大陆三网 单线程 IPV6'
            ;;
        5)
            if [ "$v6_support" == "false" ]; then
                echo 'No v6 support'
                exit 1
            fi
            node=("${fivev6[@]}")
            node_name='大陆三网 五线程 IPV6'
            ;;
        6)
            if [ "$v6_support" == "false" ]; then
                echo 'No v6 support'
                exit 1
            fi
            node=("${tenv6[@]}")
            node_name='大陆三网 十线程 IPV6'
            ;;
        *)
            echo "无效的选择，请重新运行脚本并输入有效的序号。"
            exit 1
            ;;
    esac

}
_taierspeed_cli_test() {
    local length=$(( ${#node[@]} - 1 ))
    for ((i=0; i<=length; i++)); do
        line=${node[i]}
        # 执行命令并设置超时
        ${work_dir}/taierspeed-cli --server ${line} -q > "${work_dir}/taierspeed-cli-${i}.log"
        if [ -s "${work_dir}/taierspeed-cli-${i}.log" ]; then
            # 初始化变量
            local download_c="15" upload_c="15" latency_c="13" jitter_c="13"
            local node_name latency jitter download upload
            
            node_name="${name[i]}            "
            latency=$(grep "Latency:" "${work_dir}/taierspeed-cli-${i}.log" | awk '{ print $2 }')
            jitter=$(grep "Latency:" "${work_dir}/taierspeed-cli-${i}.log" | awk -F'[()]' '{ print $2 }' | awk '{ print $1 }')
            download=$(grep "Download:" "${work_dir}/taierspeed-cli-${i}.log" | awk '{ print $2 }')
            upload=$(grep "Upload:" "${work_dir}/taierspeed-cli-${i}.log" | awk '{ print $2 }')
            
            # 检查和格式化输出
            _check_num "$latency" || latency="失败"
            _check_num "$latency" || latency_c="15"
            _check_num "$latency" && latency="$(printf "%.2f" "$latency") ms"
            _check_num "$jitter" || jitter="失败"
            _check_num "$jitter" || jitter_c="15"
            _check_num "$jitter" && jitter="$(printf "%.2f" "$jitter") ms"
            _check_num "$download" || download="失败"
            _check_num "$download" || download_c="17"
            _check_num "$download" && download="$(printf "%.2f" "$download") Mbps"
            _check_num "$upload" || upload="失败"
            _check_num "$upload" || upload_c="17"
            _check_num "$upload" && upload="$(printf "%.2f" "$upload") Mbps"
            [ -s "${work_dir}/taierspeed-cli-${i}.log" ] && _check_output
        fi
    done
}
########## 输出 ##########

_check_output() {
    local i_check_output
    local count_check_output="0"
    for i_check_output in $(echo "$download $upload $latency $jitter"); do
        if [[ "$i_check_output" =~ 失败 ]]; then
            count_check_output=$((count_check_output + 1))
        elif [[ "$i_check_output" =~ 跳过 ]]; then
            count_check_output=$((count_check_output + 1))
        fi
    done
    [ "$count_check_output" -ne 4 ] && printf "${yellow}%-s${green}%-${download_c}s${cyan}%-${upload_c}s${blue}%-${latency_c}s${purple}%-${jitter_c}s${endc}\n" "$node_name" "$download" "$upload" "$latency" "$jitter"
}

########## 删除残余文件 ##########

_rm_dir() {
    rm -rf "$work_dir"
    exit 0
}

########## main ##########

_main() {
    trap '_rm_dir' EXIT SIGINT
    check_ipv4
    check_ipv6
    _check_architecture
    _constant
    _download
    _check_sha256
    clear
    _print_banner_1
    _choose
    clear
    _print_banner_2
    _print_banner_3
    _taierspeed_cli_test
}

_main