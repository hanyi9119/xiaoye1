#!/bin/bash

# 检查用户是否是root用户
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以root身份运行" 
   exit 1
fi

# 检查是否安装了iptables-persistent
if ! dpkg -l iptables-persistent &> /dev/null; then
    echo "安装iptables-persistent..."
    apt-get update
    apt-get install -y iptables-persistent
fi

# 保存当前的iptables规则
iptables-save > /etc/iptables/rules.v4

# 启用iptables规则的自动加载
iptables-persistent update


# 获取SSH端口号
SSH_PORT=$(sudo grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi

echo "SSH端口号为：$SSH_PORT"
echo "开始通过iptables进行基本的攻击缓解设置..."

# 限制SSH连接次数
if ! sudo iptables -C INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set
    echo "已添加规则：限制SSH连接次数"
fi

if ! sudo iptables -C INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
    echo "已添加规则：SSH连接次数被限制为60秒内10次"
fi

# 丢弃ping请求
if ! sudo iptables -C INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    echo "已添加规则：丢弃所有的ping请求"
fi

# 防止SYN洪泛攻击
if ! sudo iptables -C INPUT -p tcp ! --syn -m state --state NEW -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
    echo "已添加规则：开启防止SYN洪泛攻击"
fi

# 防止端口扫描
if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    echo "已添加规则：开启防止端口扫描 (ALL NONE)"
fi

if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    echo "已添加规则：开启防止端口扫描 (ALL ALL)"
fi

# 输出所有规则
sudo iptables -L -n -v
echo "所有基本攻击缓解规则已应用完成，请检查iptables规则"
