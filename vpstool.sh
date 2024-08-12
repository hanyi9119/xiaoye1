#!/bin/bash

# 检查用户是否是root用户
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以root身份运行" 
   exit 1
fi


# 获取SSH端口号
SSH_PORT=$(sudo grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi

echo "SSH端口号为：$SSH_PORT"
echo "开始通过iptables进行基本的攻击缓解设置..."

# 检查iptables备份文件是否存在
if [ -f "/root/iptables_backup.rules" ]; then
       echo "备份文件已存在，不再重新备份。"
else
          echo "没有找到备份文件，正在创建备份..."
          sudo iptables-save > /root/iptables_backup.rules
       echo "备份已创建：/root/iptables_backup.rules"
       echo "恢复规则请使用：sudo iptables-restore < /root/iptables_backup.rules"
fi



# 定义一个固定的计数器名称
recent_name="SSH_LIMIT"

# 函数：添加规则如果它尚不存在
add_rule_if_not_exists() {
    local port=$1
    local rule=$2
    if ! sudo iptables -C INPUT -p tcp --dport "$port" $rule 2>/dev/null; then
        echo "添加规则：$rule"
        sudo iptables -A INPUT -p tcp --dport "$port" $rule
    else
        echo "规则已存在：$rule"
    fi
}


# 检查并添加限制SSH连接次数规则
set_rule="-m state --state NEW -m recent --name \"$recent_name\" --set"
add_rule_if_not_exists "$SSH_PORT" "$set_rule"

# 检查并添加限制连接次数的DROP规则
drop_rule="-m state --state NEW -m recent --name \"$recent_name\" --update --seconds 60 --hitcount 10 -j DROP"
add_rule_if_not_exists "$SSH_PORT" "$drop_rule"

# 丢弃ping请求
if ! sudo iptables -C INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    echo "已添加规则：丢弃所有的ping请求"
else
    echo "已添加丢弃所有的ping请求，不再重复添加"
fi

# 防止SYN洪泛攻击
if ! sudo iptables -C INPUT -p tcp ! --syn -m state --state NEW -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
    echo "已添加规则：开启防止SYN洪泛攻击"
else
    echo "已添加开启防止SYN洪泛攻击，不再重复添加"
fi

# 防止端口扫描
if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    echo "已添加规则：开启防止端口扫描 (ALL NONE)"
else
    echo "已添加开启防止端口扫描 (ALL NONE)，不再重复添加"
fi

if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    echo "已添加规则：开启防止端口扫描 (ALL ALL)"
else
    echo "已添加开启防止端口扫描 (ALL ALL)，不再重复添加"
fi

# 防止XMAS攻击
if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
    echo "已添加规则：防止XMAS Tree攻击"
else
    echo "已添加防止XMAS Tree攻击已添加，不再重复添加"
fi

# 跟踪连接状态
if ! sudo iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "已添加规则：状态检测，可以更精细地控制流量，防止半开连接"
else
    echo "已添加跟踪连接状态规则，不再重复添加"
fi

if ! sudo iptables -C INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
    echo "已添加规则：限制SYN-Flood攻击，syn连接被限制为每秒钟接受一个同一来源SYN请求，初始突发允许3个请求"
else
    echo "已添加限制SYN-Flood攻击规则，不再重复添加"
fi

if ! sudo iptables -C INPUT -m state --state INVALID -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -m state --state INVALID -j DROP
    echo "已添加规则：丢弃无效包"
else
    echo "已添加丢弃无效包规则，不再重复添加"
fi


#保存iptables规则
iptables-save > /etc/iptables.up.rules
echo -e '#!/bin/bash\n/sbin/iptables-restore < /etc/iptables.up.rules' > /etc/network/if-pre-up.d/iptables
chmod +x /etc/network/if-pre-up.d/iptables

iptables-save > /etc/iptables.up.rules

# 输出所有规则
sudo iptables -L -n -v
echo "所有基本攻击缓解已应用,重启依然生效，请检查iptables规则"
