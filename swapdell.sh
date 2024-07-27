#!/bin/bash

# 定义一个数组，存储所有的 swap 文件
declare -a swapfiles

# 从 /proc/swaps 中获取 swap 文件路径
while IFS= read -r line; do
    # 忽略分区和磁盘的 swap 行
    if [[ "$line" == swap* ]]; then
        swapfiles+=("$line")
    fi
done < /proc/swaps

# 遍历数组，关闭并删除每个 swap 文件
for swapfile in "${swapfiles[@]}"; do
    # 从 /proc/swaps 中提取文件路径
    filepath=$(echo "$swapfile" | cut -d' ' -f1)

    # 关闭 swap 文件
    swapoff "$filepath"

    # 删除 swap 文件
    rm -f "$filepath"
    echo "Deleted swap file: $filepath"
done

echo "All swap files have been removed."
