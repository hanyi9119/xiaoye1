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
    echo "超额流量数值保存文件 /root/awsconfig/traffic_limit.txt"
    echo "实时流量数据储存文件 /root/awsconfig/shutdown_debug.log"
    echo "实时检测脚本文件 /root/awsconfig/check.sh"
    echo "大功告成！脚本已安装并配置完成。"
}

# 创建自动断网脚本
set_network_limit() {
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

    # 获取SSH端口
    ssh_port=$(ss -tnlp | grep sshd | awk '{print $5}' | cut -d: -f2)

    # 创建自动断网脚本checking.sh
    cat << EOF | sudo tee /root/awsconfig/checking.sh > /dev/null
#!/bin/bash

# 使用的环境变量
interface_name="$interface_name"
traffic_limit=\$(cat /root/awsconfig/traffic_limit.txt)
ssh_port=$ssh_port

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
if (( $(echo "$CHANGE_TO_GB > $traffic_limit" | bc -l) )); then
    # 检查并保留SSH端口的规则
    if ! iptables -C INPUT -p tcp --dport $ssh_port -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport $ssh_port -j ACCEPT
    fi

    # 检查并保留本地环回接口的规则
    if ! iptables -C INPUT -i lo -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -i lo -j ACCEPT
    fi

    # 检查并设置默认策略为 DROP
    default_policy=$(iptables -L INPUT --policy | grep -oP '(?<=\().*(?=\))')
    if [ "$default_policy" != "DROP" ]; then
        iptables -P INPUT DROP
    fi
fi

EOF

    # 授予权限
    sudo chmod +x /root/awsconfig/checking.sh

    # 设置定时任务，每5分钟执行一次检查
    cron_job="*/5 * * * * /bin/bash /root/awsconfig/checking.sh > /root/awsconfig/shutdown_debug.log 2>&1"
    (crontab -l | grep -Fxq "$cron_job") || (crontab -l; echo "$cron_job") | crontab -

    echo "流量限额设置为（双向统计）：${traffic_limit}G"
    echo "定时任务计划："
    crontab -l
    echo "月度流量刷新日期MonthRotate的值："
    sed -n '/MonthRotate/ p' /etc/vnstat.conf
    echo "查看流量数据, 输入：vnstat"
    echo "查看定时任务，输入：crontab -l"
    echo "超额流量数值保存文件 /root/awsconfig/traffic_limit.txt"
    echo "实时流量数据储存文件 /root/awsconfig/shutdown_debug.log"
    echo "实时检测脚本文件 /root/awsconfig/checking.sh"
    echo "当前iptables限制规则："
    sudo iptables -L
    echo "大功告成！脚本已安装并配置完成。"
}


# 显示选项菜单
echo "请选择操作："
echo "1. 设置流量限额"
echo "2. 清零统计数据"
echo "3. 查看本月流量"
echo "4. 显示定时任务和配置"
echo "5. 修改流量刷新日期"
echo "6. 卸载脚本"
echo "7. 流量超限就自动断网，仅保留SSH可连接"
echo "8. 恢复网络"
echo -n "请输入选项 (1-8): "
read choice


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
    echo "月度流量刷新日期MonthRotate的值："
    sed -n '/MonthRotate/ p' /etc/vnstat.conf
    echo "配置文件目录：/root/awsconfig"
    echo "超额流量数值保存文件：/root/awsconfig/traffic_limit.txt"
    echo "实时流量数据储存文件：/root/awsconfig/shutdown_debug.log"
    echo "当前iptables限制规则："
    sudo iptables -L
    echo "实时检测脚本文件：/root/awsconfig/check.sh"
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
}



uninstall_script() {
    sudo systemctl stop vnstat
    sudo systemctl disable vnstat
    sudo rm -rf /var/lib/vnstat
    sudo apt remove -y vnstat bc
    sudo rm -rf /root/awsconfig/
    (crontab -l | grep -v '/root/awsconfig/check.sh') | crontab -
    echo "脚本及相关组件已卸载。"
}

# 恢复网络
restore_network() {
    # 允许所有入站流量
    sudo iptables -P INPUT ACCEPT

    # 删除所有 INPUT 链上的规则
    sudo iptables -F INPUT

    echo "网络已恢复，所有入站连接已允许。"
}

# 显示选项菜单
echo "请选择操作："
echo "1. 设置流量限额"
echo "2. 清零统计数据"
echo "3. 查看本月流量"
echo "4. 显示定时任务和配置"
echo "5. 修改流量刷新日期"
echo "6. 卸载脚本"
echo "7. 流量超限就自动断网，仅保留SSH可连接"
echo "8. 恢复网络"
echo -n "请输入选项 (1-8): "
read choice

case $choice in
    1)
        set_traffic_limit
        ;;
    2)
        clear_statistics
        ;;
    3)
        view_monthly_traffic
        ;;
    4)
        show_configuration
        ;;
    5)
        modify_billing_day
        ;;
    6)
        uninstall_script
        ;;
    7)
        set_network_limit
        ;;
    8)
        restore_network
        ;;
    *)
        echo "无效选项。"
        ;;
esac
