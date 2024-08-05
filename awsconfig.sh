#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "该脚本必须以 root 权限运行" 1>&2
   exit 1
fi

# 自动获取第一个活动的网络接口名称
interface_name=$(route | grep default | sed -e 's/.* //' -e 's/:.*//' -e 's/\.[0-9]*$//')

# 创建文件夹
sudo mkdir -p /root/awsconfig/

# 定义函数
set_traffic_limit() {
    echo -n "请输入流量限额（GB）："
    read traffic_limit

    # 检查输入是否为整数
    if ! [[ "$traffic_limit" =~ ^[0-9]+$ ]]; then
        echo "错误：请输入一个有效的整数。"
        exit 1
    fi

    echo $traffic_limit > /root/awsconfig/traffic_limit.txt

    # 安装依赖/设置市区/安装流量监控软件vnstat
    sudo apt update
    sudo apt install  -y timedatectl
    sudo timedatectl set-timezone Asia/Hong_Kong
    sudo apt install cron vnstat bc -y

    # 配置vnstat，使用自动获取的网络接口名称
    sudo sed -i "s/^Interface.*/Interface $interface_name/" /etc/vnstat.conf
    sudo sed -i "s/^# *UnitMode.*/UnitMode 1/" /etc/vnstat.conf
    sudo sed -i "s/^# *MonthRotate.*/MonthRotate 1/" /etc/vnstat.conf

    # 重启vnstat服务
    sudo systemctl enable vnstat
    sudo systemctl restart vnstat

    # 创建自动关机脚本check.sh
    cat << EOF | sudo tee /root/awsconfig/check.sh > /dev/null
#!/bin/bash

# 使用的环境变量
interface_name="$interface_name"
traffic_limit=\$(cat /root/awsconfig/traffic_limit.txt)

# 更新网卡记录
vnstat -i "\$interface_name"

# 获取每月用量
TRAFF_USED=\$(vnstat --oneline b | awk -F';' '{print \$11}')

# 检查是否获取到数据
if [[ -z "\$TRAFF_USED" ]]; then
    echo "Error: Not enough data available yet."
    exit 1
fi

# 将流量转换为GB
CHANGE_TO_GB=\$(echo "scale=2; \$TRAFF_USED / 1073741824" | bc)

# 检查转换后的流量是否为有效数字
if ! [[ "\$CHANGE_TO_GB" =~ ^[0-9]+([.][0-9]+)?\$ ]]; then
    echo "Error: Invalid traffic data."
    exit 1
fi

# 比较流量是否超过阈值
if (( \$(echo "\$CHANGE_TO_GB > \$traffic_limit" | bc -l) )); then
    sudo /usr/sbin/shutdown -h now
fi
EOF

    # 授予权限
    sudo chmod +x /root/awsconfig/check.sh

    # 设置定时任务，每5分钟执行一次检查
    cron_job="*/5 * * * * /bin/bash /root/awsconfig/check.sh > /root/awsconfig/shutdown_debug.log 2>&1"
    (crontab -l | grep -Fxq "$cron_job") || (crontab -l; echo "$cron_job") | crontab -

    echo "流量限额设置为（双向统计）：${traffic_limit}G"
    echo "定时任务计划："
    crontab -l
    echo "月度流量刷新日期MonthRotate的值："
    sed -n '/MonthRotate/ p' /etc/vnstat.conf
    echo "查看流量数据, 输入：vnstat"
    echo "查看定时任务，输入：crontab -l"
    echo "超额流量数值保存文件：/root/awsconfig/traffic_limit.txt"
    echo "实时流量数据储存文件：/root/awsconfig/shutdown_debug.log"
    echo "关机脚本文件：/root/awsconfig/check.sh"    
    echo "大功告成！关机脚本已安装并配置完成。"
}

clear_statistics() {
    sudo systemctl stop vnstat
    sudo rm /var/lib/vnstat/*
    sudo systemctl start vnstat
    echo "统计数据已清零。"
}

view_monthly_traffic() {
    vnstat
}

show_configuration() {
    echo "当前流量限额为（双向统计）: $(cat /root/awsconfig/traffic_limit.txt) GB"
    echo "定时任务计划："
    crontab -l
    echo "iptables规则查询：sudo iptables -L -n -v"      
    echo "iptables断网规则如下"
    sudo iptables -L -n -v
    echo "月度流量刷新日期MonthRotate的值："
    sed -n '/MonthRotate/ p' /etc/vnstat.conf
    echo "配置文件目录：/root/awsconfig"
    echo "超额流量数值保存文件：/root/awsconfig/traffic_limit.txt"
    echo "实时流量数据储存文件：/root/awsconfig/shutdown_debug.log"
    echo "关机脚本文件：/root/awsconfig/check.sh"    
    echo "断网脚本文件：/root/awsconfig/block_traffic.sh"
}

modify_billing_day() {
    # 提示用户输入1-31之间的清零日期
    read -p "请输入清零日期 (1-31): " day

    # 检查输入的数字是否在1-31之间
    if [[ "$day" =~ ^[0-9]+$ ]] && [ "$day" -ge 1 ] && [ "$day" -le 31 ]; then
        # 确认用户输入
        echo "您输入的清零日期为: $day"

        # 配置文件路径
        VNSTAT_CONF="/etc/vnstat.conf"
        
        # 检查配置文件是否存在
        if [ -f "$VNSTAT_CONF" ]; then
            # 备份原配置文件
            cp "$VNSTAT_CONF" "$VNSTAT_CONF.bak"

            # 尝试修改配置文件中的 MonthRotate 设置
            if grep -qE '^\s*MonthRotate[[:space:]]*[0-9]*' "$VNSTAT_CONF"; then
                # 仅修改 MonthRotate 相关的行
                sed -i "s/^\s*MonthRotate[[:space:]]*[0-9]*/MonthRotate $day/" "$VNSTAT_CONF"
                echo "/etc/vnstat.conf 配置已更新，MonthRotate 已设置为 $day。"
                
                # 打印 MonthRotate 行
                grep 'MonthRotate' /etc/vnstat.conf
            else
                echo "未找到 MonthRotate 设置，添加新设置。"
                # 添加 MonthRotate 设置
                echo "MonthRotate $day" >> "$VNSTAT_CONF"
                echo "MonthRotate 设置已添加。"
                grep 'MonthRotate' /etc/vnstat.conf
            fi
        else
            echo "错误：无法找到 $VNSTAT_CONF 文件。"
        fi
    else
        echo "输入无效。请输入1到31之间的数字。"
    fi

    #重启vnstat
    sudo systemctl enable vnstat
    sudo systemctl restart vnstat    
}



uninstall_script() {
    sudo systemctl stop vnstat
    sudo systemctl disable vnstat
    sudo rm -rf /var/lib/vnstat
    sudo apt remove -y vnstat bc
    sudo rm -rf /root/awsconfig/
    (crontab -l | grep -v '/root/awsconfig/check.sh') | crontab -
    (crontab -l | grep -v '/root/awsconfig/block_traffic.sh') | crontab -
    echo "脚本及相关组件已卸载。"
}


block_traffic_except_ssh() {
    echo -n "请输入流量限额（GB）："
    read traffic_limit

    # 检查输入是否为整数
    if ! [[ "$traffic_limit" =~ ^[0-9]+$ ]]; then
        echo "错误：请输入一个有效的整数。"
        exit 1
    fi

    echo $traffic_limit > /root/awsconfig/traffic_limit.txt

    # 安装依赖/设置时区/安装流量监控软件vnstat
    sudo apt update
    sudo apt install -y timedatectl
    sudo timedatectl set-timezone Asia/Hong_Kong
    sudo apt install cron vnstat bc -y

    # 配置vnstat，使用自动获取的网络接口名称
    sudo sed -i "s/^Interface.*/Interface $interface_name/" /etc/vnstat.conf
    sudo sed -i "s/^# *UnitMode.*/UnitMode 1/" /etc/vnstat.conf
    sudo sed -i "s/^# *MonthRotate.*/MonthRotate 1/" /etc/vnstat.conf

    # 重启vnstat服务
    sudo systemctl enable vnstat
    sudo systemctl restart vnstat    

    # 创建断网脚本
    sudo tee /root/awsconfig/block_traffic.sh << 'EOF' > /dev/null
#!/bin/bash

# 使用的环境变量
interface_name="$interface_name"
traffic_limit=$(cat /root/awsconfig/traffic_limit.txt)

# 获取SSH端口
ssh_port=$(grep '^Port ' /etc/ssh/sshd_config | awk '{print $2}')
if [ -z "$ssh_port" ]; then
    ssh_port=22  # 如果没有找到端口号，则默认为22
fi

# 更新网卡记录
vnstat -i "$interface_name"

# 获取每月用量
TRAFF_USED=$(vnstat --oneline b | awk -F';' '{print $11}')

# 检查是否获取到数据
if [[ -z "$TRAFF_USED" ]]; then
    echo "Error: Not enough data available yet."
    exit 1
fi

# 将流量转换为GB
CHANGE_TO_GB=$(echo "scale=2; $TRAFF_USED / 1073741824" | bc)

# 检查转换后的流量是否为有效数字
if ! [[ "$CHANGE_TO_GB" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: Invalid traffic data."
    exit 1
fi

# 比较流量是否超过阈值
if (( $(echo "$CHANGE_TO_GB > $traffic_limit" | bc -l) )); then
    echo "流量超限，开始更新iptables规则..."

    # 检查备份文件是否存在
    if [ -f "/root/awsconfig/iptables_backup.rules" ]; then
       echo "备份文件已存在，不再重新备份。"
    else
          echo "没有找到备份文件，正在创建备份..."
          sudo iptables-save > /root/awsconfig/iptables_backup.rules
       echo "备份已创建：/root/awsconfig/iptables_backup.rules"
    fi


    # 清除所有规则
    sudo iptables -F

    # 允许SSH连接
    sudo iptables -A INPUT -p tcp --dport $ssh_port -j ACCEPT
    sudo iptables -A OUTPUT -p tcp --sport $ssh_port -j ACCEPT

    # 拒绝其他所有流量
    sudo iptables -A INPUT -j DROP
    sudo iptables -A OUTPUT -j DROP

    echo "流量超限，已屏蔽所有连接，仅允许SSH连接。"
fi

EOF

    # 授予脚本执行权限
    sudo chmod +x /root/awsconfig/block_traffic.sh

    # 设置定时任务，每5分钟执行一次检查
    cron_job="*/5 * * * * /bin/bash /root/awsconfig/block_traffic.sh > /root/awsconfig/block_traffic_debug.log 2>&1"
    (crontab -l 2>/dev/null | grep -Fxq "$cron_job") || (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

    echo "流量限额设置为（双向统计）：${traffic_limit}G"
    echo "定时任务计划："
    crontab -l
    echo "iptables规则查询：sudo iptables -L -n -v"      
    echo "iptables断网规则如下"
    sudo iptables -L -n -v
    echo "流量超限时将屏蔽所有连接，仅保留SSH连接。"
    echo "查看定时任务，输入：crontab -l"
    echo "超额流量数值保存文件：/root/awsconfig/traffic_limit.txt" 
    echo "断网脚本文件：/root/awsconfig/block_traffic.sh"
    echo "实时流量数据储存文件：/root/awsconfig/block_traffic_debug.log"
    echo "大功告成！断网脚本已安装并配置完成。"
}




restore_network() {
    # 检查备份文件是否存在
    if [ -f /root/awsconfig/iptables_backup.rules ]; then
        # 恢复备份的iptables规则
        sudo iptables-restore < /root/awsconfig/iptables_backup.rules
        # 删除备份的iptables规则文件
        rm -f /root/awsconfig/iptables_backup.rules
        #输出恢复后的iptables规则
        sudo iptables -L -n -v
        echo "iptables规则已恢复，网络已恢复,建议重启一下：reboot"
    else
        echo "找不到iptables规则的备份文件。无法恢复网络连接。"
    fi
}

# 显示选项菜单
echo "请选择操作：限额流量关机/限额流量断网 二选一"
echo "1. 查看本月流量"
echo "2. 清零统计数据"
echo "3. 限额流量关机"
echo "4. 限额流量断网"
echo "5. 恢复网络连接"
echo "6. 显示定时任务和配置"
echo "7. 修改流量刷新日期"
echo "8. 卸载脚本"
echo -n "请输入选项 (1-8): "
read choice

case $choice in
    1)
        view_monthly_traffic
        ;;
    2)
        clear_statistics
        ;;
    3)
        set_traffic_limit
        ;;
    4)
        block_traffic_except_ssh
        ;;
    5)
        restore_network
        ;;
    6)
        show_configuration
        ;;
    7)
        modify_billing_day
        ;;
    8)
        uninstall_script
        ;;
    *)
        echo "无效选项。"
        ;;
esac

