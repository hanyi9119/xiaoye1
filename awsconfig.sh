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

    # 安装依赖
    sudo apt update
    sudo apt install cron vnstat bc -y

    # 配置vnstat，使用自动获取的网络接口名称
    sudo sed -i "0,/^;Interface.*/s//Interface $interface_name/" /etc/vnstat.conf
    sudo sed -i "0,/^;UnitMode.*/s//UnitMode 1/" /etc/vnstat.conf
    sudo sed -i "0,/^;MonthRotate.*/s//MonthRotate 1/" /etc/vnstat.conf

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
    (crontab -l ; echo "*/5 * * * * /bin/bash /root/awsconfig/check.sh > /root/awsconfig/shutdown_debug.log 2>&1") | crontab -

    echo "流量限额设置为：${traffic_limit}G"
    echo "实时查看流量数据, 输入：vnstat"
    echo "查看定时任务，输入：crontab -l"
    echo "超额流量数值保存文件 /root/awsconfig/traffic_limit.txt"
    echo "实时流量数据储存文件 /root/awsconfig/shutdown_debug.log"
    echo "实时检测脚本文件 /root/awsconfig/check.sh"
    echo "大功告成！脚本已安装并配置完成。"
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

uninstall_script() {
    sudo systemctl stop vnstat
    sudo systemctl disable vnstat
    sudo rm -rf /var/lib/vnstat
    sudo apt remove -y vnstat bc
    sudo rm -rf /root/awsconfig
    (crontab -l | grep -v '/root/awsconfig/check.sh') | crontab -
    echo "脚本及相关组件已卸载。"
}

# 显示选项菜单
echo "请选择操作："
echo "1. 设置流量限额"
echo "2. 清零统计数据"
echo "3. 查看本月流量"
echo "4. 卸载脚本"
echo -n "请输入选项 (1-4): "
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
        uninstall_script
        ;;
    *)
        echo "无效选项。"
        ;;
esac
