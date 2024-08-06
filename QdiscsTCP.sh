#!/bin/bash


# 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "该脚本必须以 root 权限运行" 1>&2
   exit 1
fi

# 更新系统
apt update && apt upgrade -y

# 安装缺失的工具
echo "安装必要的工具..."
apt install -y iptables network-manager ethtool

# 确保 ifb0 设备存在
echo "确保 ifb0 设备存在..."
sudo modprobe ifb
sudo ip link add ifb0 type ifb
sudo ip link set ifb0 up

# 获取主网卡接口名称（假设接口名称以 eth 开头）
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep '^eth')

# 确保有找到接口
if [ -z "$interfaces" ]; then
    echo "没有找到主网卡接口。"
    exit 1
fi

# 备份现有配置
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
    # 调整网络队列处理算法（Qdiscs），优化TCP重传次数
    echo "Tuning network queue disciplines (Qdiscs) and TCP retransmission for interface $interface..."
    sudo tc qdisc add dev $interface root fq
    # 询问用户输入带宽
    read -p "请输入带宽（例如 1000Mbps）： " bandwidth
    # 验证输入是否是数字
    if [[ $bandwidth =~ ^[0-9]+$ ]]; then
        # 计算最大速率为输入带宽的80%
        maxrate=$((bandwidth * 80 / 100))mbit
        echo "用户输入的带宽：$bandwidth Mbps"
        echo "计算出的 maxrate 值：$maxrate"
        echo "Setting maxrate to $maxrate..."
        sudo tc qdisc change dev $interface root fq maxrate $maxrate
        sudo tc qdisc change dev $interface root fq burst 20k
    else
        echo "无效的带宽输入，请输入一个数字。"
        exit 1
    fi
    sudo tc qdisc add dev $interface ingress
    sudo tc filter add dev $interface parent ffff: protocol ip u32 match u32 0 0 action connmark action mirred egress redirect dev ifb0
    sudo tc qdisc add dev ifb0 root sfq perturb 10
    sudo ip link set dev ifb0 up
    sudo ethtool -K $interface tx off rx off
done

echo "网络配置已更新完成。"
