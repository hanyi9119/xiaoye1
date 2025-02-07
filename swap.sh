#!/bin/bash

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "请以root用户运行此脚本。"
        exit 1
    fi
}

# 获取当前内存大小
get_total_memory() {
    total_memory=$(free -m | awk '/Mem/ {print $2}')
    echo "内存：$total_memory MB"
}

# 获取当前swap分区大小
get_current_swap() {
    current_swap=$(free -m | awk '/Swap/ {print $2}')
    echo "Swap：$current_swap MB"
}

# 创建并启用swap文件
create_swap() {
    local swap_size=$1
    echo "创建${swap_size}MB的swap文件..."
    swapoff -a
    dd if=/dev/zero of=/home/swapfile bs=1M count="$swap_size"
    chmod 600 /home/swapfile
    mkswap /home/swapfile
    swapon /home/swapfile
    echo "/home/swapfile swap swap defaults 0 0" | tee -a /etc/fstab
    echo "swap建立完成！"
}

# 设置 vm.swappiness 值为10
set_swappiness() {
    local TARGET_SWAPPINESS=10
    local SYSCTL_CONF="/etc/sysctl.conf"
    local TEMP_CONF="/tmp/sysctl_temp.conf"

    # 备份原始配置文件
    cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak"

    # 处理现有vm.swappiness配置
    if grep -q "^[[:space:]]*vm.swappiness[[:space:]]*=" "$SYSCTL_CONF"; then
        # 注释所有现有配置
        sed -i '/^[[:space:]]*vm.swappiness[[:space:]]*=/s/^/# /' "$SYSCTL_CONF"
    fi

    # 追加新的配置到文件末尾
    echo "vm.swappiness=$TARGET_SWAPPINESS" >> "$SYSCTL_CONF"

    # 验证配置文件语法
    if sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1; then
        # 语法正确，应用配置
        sysctl -p "$SYSCTL_CONF" >/dev/null
        echo "vm.swappiness 已成功设置为10"
        echo "当前值: $(cat /proc/sys/vm/swappiness)"
    else
        # 恢复备份并报错
        mv "${SYSCTL_CONF}.bak" "$SYSCTL_CONF"
        echo "错误: sysctl配置文件存在语法错误，已恢复原始配置" >&2
        exit 1
    fi
}






# 主逻辑
main() {
    check_root
    get_total_memory
    get_current_swap
    set_swappiness
    
    if [ "$current_swap" -gt 0 ]; then
        double_memory=$((total_memory * 2))
        if [ "$current_swap" -ge "$double_memory" ]; then
            echo "当前swap分区已经是内存的两倍或更大，不需要再建立新的swap文件。"
            exit 0
        fi
    fi

    if [ -z "$1" ]; then
        echo "请输入以MB为单位的swap分区大小并回车："
        read -r swap
    else
        swap=$1
    fi

    if ! [[ "$swap" =~ ^[0-9]+$ ]] || [ "$swap" -le 0 ]; then
        echo "错误：请输入一个有效的正整数。"
        exit 1
    fi

    # 检查磁盘空间是否足够
    required_space=$((swap * 1024)) # 1MB = 1024KB
    available_space=$(df /home | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt "$required_space" ]; then
        echo "错误：磁盘空间不足，无法创建所需大小的swap文件。"
        exit 1
    fi
    
    create_swap "$swap"
    free -m
}

# 执行主逻辑
main "$@"
