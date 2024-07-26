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

# 主逻辑
main() {
    check_root
    get_total_memory
    get_current_swap

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
    required_space=$(swap * 1024 * 1024) # 1MB = 1024KB = 1024*1024Bytes
    available_space=$(df /home | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$available_space" -lt "$required_space" ]; then
        echo "错误：磁盘空间不足，无法创建所需大小的swap文件。"
        exit 1
    fi

    create_swap "$swap"
    free -m
}

# 执行主逻辑
main
