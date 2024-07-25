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
    SSH_PORT=22
fi

echo "SSH端口号为：$SSH_PORT"
echo "开始通过iptables进行基本的攻击缓解设置..."

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
# 保存当前的iptables INPUT链规则
current_rules=$(sudo iptables-save | grep -v '^#' | grep -v '^:')

# 使用临时文件存储当前的iptables规则
temp_rules_file=$(mktemp)
echo "$current_rules" > "$temp_rules"
echo "已保存当前规则到临时文件：$temp_rules_file"

# 从临时文件重新加载iptables规则，并删除重复的规则
while read -r line; do
    # 跳过空行和注释行
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
        continue
    fi
    # 尝试添加规则，如果规则已存在，则不添加
    if ! sudo iptables-restore < "$temp_rules_file" | grep -q "$line"; then
        echo "$line" | sudo iptables-restore
    fi
done < "$temp_rules_file"

# 移除临时文件
rm "$temp_rules_file"

echo "删除iptables重复规则完成"
# 输出所有规则
sudo iptables -L -n -v
echo "所有基本攻击缓解规则已应用完成，请检查iptables规则"
