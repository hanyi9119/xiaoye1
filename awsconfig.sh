#!/bin/bash

# 自动获取第一个活动的网络接口名称
interface_name=$(route | grep default | sed -e 's/.* //' -e 's/:.*//' -e 's/\.[0-9]*$//')

#创建文件夹
mkdir -p /root/awsconfig/

# 检查流量限制参数是否提供
if [ -z "$1" ]; then
    echo "Usage: $0 <traffic_limit>"
    exit 1
fi

# 参数
traffic_limit=$1
echo $traffic_limit > /root/awsconfig/traffic_limit.txt

# 更新包列表并安装cron服务
sudo apt update
sudo apt install cron -y

# 安装依赖
sudo apt install vnstat bc -y

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
(crontab -l ; echo "*/3 * * * * /bin/bash /root/awsconfig/check.sh \$traffic_limit > /root/awsconfig/shutdown_debug.log 2>&1") | crontab -

echo "大功告成！脚本已安装并配置完成。"
