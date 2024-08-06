#!/bin/bash


# 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "该脚本必须以 root 权限运行" 1>&2
   exit 1
fi

# 更新系统
apt update && apt upgrade -y

# 检测是否安装iptables，如果没有则安装
if ! command -v iptables &> /dev/null; then
    echo "安装 iptables..."
    apt install -y iptables
fi

# 获取所有网络接口的名称
interfaces=$(route | grep default | awk '{print $8}')

# 提示用户输入带宽值（单位：Mbps），并验证输入是否为有效的数字
while true; do
    read -p "请输入网络带宽（单位：Mbps）： " bandwidth_mbps
    
    # 验证输入是否为有效的数字
    if [[ $bandwidth_mbps =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        break
    else
        echo "无效的输入。请输入一个有效的数字。"
    fi
done

# 计算 80% 的带宽值
maxrate_value=$(echo "$bandwidth_mbps * 0.8" | bc)

# 输出用户输入的带宽和计算出的 maxrate 值
echo "用户输入的带宽：${bandwidth_mbps} Mbps"
echo "计算出的 maxrate 值：${maxrate_value} mbps"

# 备份当前的网络配置
backup_dir="/root/network_backup"
mkdir -p $backup_dir

# 备份当前的 tc 配置
echo "备份当前的 tc 配置..."
for interface in $interfaces; do
    sudo tc qdisc show dev $interface > "$backup_dir/tc_$interface_backup.txt"
done

# 备份 iptables 配置
echo "备份当前的 iptables 配置..."
sudo iptables-save > "$backup_dir/iptables_backup.txt"

# 循环遍历每个网络接口
for interface in $interfaces; do
    # 使用nmcli增加环缓冲的大小
    echo "Setting ring buffer size for interface $interface..."
    sudo nmcli connection modify $interface txqueuelen 10000

    # 调优网络设备积压队列以避免数据包丢弃
    echo "Tuning network device backlog for interface $interface..."
    sudo nmcli connection modify $interface rxqueuelen 10000

    # 增加NIC的传输队列长度
    echo "Increasing NIC transmission queue length for interface $interface..."
    sudo nmcli connection modify $interface transmit-hash-policy layer2+3
done

# 调整网络队列处理算法（Qdiscs），优化TCP重传次数
for interface in $interfaces; do
    echo "Tuning network queue disciplines (Qdiscs) and TCP retransmission for interface $interface..."
    sudo tc qdisc add dev $interface root fq
    echo "Setting maxrate to ${maxrate_value}mbit for interface $interface..."
    sudo tc qdisc change dev $interface root fq maxrate ${maxrate_value}mbit
    echo "Setting burst to 15k for interface $interface..."
    sudo tc qdisc change dev $interface root fq burst 15k
    sudo tc qdisc add dev $interface ingress
    sudo tc filter add dev $interface parent ffff: protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ifb0
    sudo tc qdisc add dev ifb0 root sfq perturb 10
    sudo ip link set dev ifb0 up
    sudo ethtool -K $interface tx off rx off
done

echo "网络配置已更新完成。"
