#!/bin/bash

# 检查用户是否为root
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户运行此脚本。"
  exit 1
fi

# 删除脚本自身（可选，如果没有特殊需要，通常不建议这样做）
# rm -f $0

echo "当前swap分区大小为："
current_swap=$(free -m | awk '/Swap/ {print $2}')
echo "Swap：$current_swap MB"

if [ "$current_swap" -gt 0 ]; then
    total_memory=$(free -m | awk '/Mem/ {print $2}')
    double_memory=$((total_memory * 2))

    if [ "$current_swap" -ge "$double_memory" ]; then
        echo "当前swap分区已经是内存的两倍或更大，不需要再建立新的swap文件。"
        exit 0
    fi
fi

swapoff -a # 停止所有的swap分区
echo "请注意：如果当前服务器有swap的话，新建swap后的大小会叠加，所以请酌情添加swap，建议swap为内存的2倍较为适中。"

if [ -z "$1" ]; then
    echo "请输入以MB为单位的swap分区大小并回车："
    read -r swap
else
    swap=$1
fi

# 检查用户输入的swap大小是否为正整数
if ! [[ "$swap" =~ ^[0-9]+$ ]] || [ "$swap" -le 0 ]; then
    echo "错误：请输入一个有效的正整数。"
    exit 1
fi

dd if=/dev/zero of=/home/swapfile bs=1M count="$swap" status=progress
mkswap /home/swapfile # 建立swap的文件系统
swapon /home/swapfile # 启用swap文件
echo "/home/swapfile swap swap defaults 0 0" >>/etc/fstab
echo "swap建立完成！"
free -m
