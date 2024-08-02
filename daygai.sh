#!/bin/bash

# 提示用户输入1-31之间的结算日
read -p "请输入结算日 (1-31): " day

# 检查输入的数字是否在1-31之间
if [[ "$day" =~ ^[0-9]+$ ]] && [ "$day" -ge 1 ] && [ "$day" -le 31 ]; then
    # 确认用户输入
    echo "您输入的结算日为: $day"

    # 配置文件路径
    VNSTAT_CONF="/etc/vnstat.conf"
    
    # 检查配置文件是否存在
    if [ -f "$VNSTAT_CONF" ]; then
        # 备份原配置文件
        cp "$VNSTAT_CONF" "$VNSTAT_CONF.bak"

        # 修改配置文件中的MonthRotate设置
        # 保留行首的分号并设置新的值
        sed -i "s/^;\?MonthRotate[[:space:]]*[0-9]*$/;MonthRotate $day/" "$VNSTAT_CONF"

        echo "vnStat配置已更新，MonthRotate已设置为 $day。"

        # 查找MonthRotate的行号，并输出其前后一行
        line=$(awk '/;MonthRotate/ {print FNR}' "$VNSTAT_CONF" | head -n 1)
        start=$((line - 1))
        end=$((line + 1))
        
        # 输出相关的三行内容
        sed -n "${start},${end}p" "$VNSTAT_CONF"
    else
        echo "错误：无法找到 $VNSTAT_CONF 文件。"
    fi
else
    echo "输入无效。请输入1到31之间的数字。"
fi
