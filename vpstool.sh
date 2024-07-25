#!/bin/bash
# 通过iptables进行基本的攻击缓解

# 获取SSH端口号
SSH_PORT=$(sudo grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)

if [ -z "$SSH_PORT" ]; then
    echo "无法获取SSH端口号，使用默认端口22."
    SSH_PORT=22
fi

echo "SSH端口号为：$SSH_PORT"
echo "开始通过iptables进行基本的攻击缓解..."

# 限制SSH连接次数
sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set
sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP

# 丢弃ping请求
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# 防止SYN洪泛攻击
sudo iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP

# 防止端口扫描
sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
sudo iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

echo "基本攻击缓解规则已应用"
