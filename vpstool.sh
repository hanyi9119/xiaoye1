#!/bin/bash

# 检查用户是否是root用户
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以root身份运行" 
   exit 1
fi

# 通过iptables进行基本的攻击缓解

# 获取SSH端口号
SSH_PORT=$(sudo grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)

if [ -z "$SSH_PORT" ]; then
    echo "无法获取SSH端口号，使用默认端口22."
    SSH_PORT=22
fi

echo "SSH端口号为：$SSH_PORT"
echo "开始通过iptables进行基本的攻击缓解设置..."

# 限制SSH连接次数
sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set
sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
echo "SSH连接次数被限制为60秒内10次"

# 丢弃ping请求
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
echo "丢弃所有的ping请求"

# 防止SYN洪泛攻击
sudo iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
echo "开启防止SYN洪泛攻击"

# 防止端口扫描
sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
sudo iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
echo "开启防止端口扫描"

# 清除重复的规则
echo "开始清除重复的iptables规则..."
# 获取带行号的iptables规则列表
rules_with_numbers=$(sudo iptables -L INPUT --line-numbers -n | tail -n +2)

# 使用awk处理规则，找出并删除重复的规则
echo "$rules_with_numbers" | awk '
BEGIN {count[0] = 0; dup[0] = 0}
{
    if ($0 != prev) {
        if (count[prev] == 1) {
            # 如果上一条规则是重复的，删除它
            print "sudo iptables -D INPUT", line[prev] > "/dev/stderr"
            system("sudo iptables -D INPUT " line[prev])
        }
        count[$0] = 0
    }
    count[$0]++;
    line[$0] = NR
    prev = $0
}
END {
    if (count[prev] == 1) {
        print "sudo iptables -D INPUT", line[prev] > "/dev/stderr"
        system("sudo iptables -D INPUT " line[prev])
    }
}' >&2

echo "删除iptables重复规则"
# 重新加载规则以确保它们被删除
sudo iptables -t filter -L INPUT -n -v

# 输出所有规则
sudo iptables -L
echo "所有基本攻击缓解规则已应用完成，请检查iptables 规则"
