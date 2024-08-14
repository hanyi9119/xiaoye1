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
echo "检测fail2ban,同时开始iptables进行攻击缓解设置..."

# 检查iptables备份文件是否存在
if [ -f "/root/iptables_backup.rules" ]; then
       echo "备份文件已存在，不再重新备份。"
else
          echo "没有找到备份文件，正在创建备份..."
          sudo iptables-save > /root/iptables_backup.rules
       echo "备份已创建：/root/iptables_backup.rules"
       echo "恢复规则请使用：sudo iptables-restore < /root/iptables_backup.rules"
fi


# 检查Fail2ban是否已安装
if ! dpkg -s fail2ban >/dev/null 2>&1; then
    echo "系统未安装Fail2ban，正在安装..."
    # 安装fail2ban
    sudo apt -y update
    sudo apt install -y fail2ban
    
#书写fail2ban配置文件
sudo bash -c "cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 10
bantime = 3600
findtime = 600
EOF"

#安装和启动rsyslog
sudo apt install rsyslog
sudo systemctl start rsyslog
sudo systemctl enable rsyslog
sudo systemctl status rsyslog
sudo systemctl is-active --quiet rsyslog && echo "rsyslog 服务正在运行" || echo "rsyslog 服务未运行"

    #重启fail2ban服务和检查fail2ban状态
    sudo systemctl restart fail2ban
    sudo systemctl status fail2ban
    sudo systemctl is-active --quiet fail2ban && echo "Fail2ban 安装完成正在运行" || echo "Fail2ban 服务未运行"
    echo "Fail2ban安装完成，已经写入配置：600秒内同一个ip错误尝试10次就封禁一个小时"
else
    sudo systemctl status fail2ban
    sudo systemctl is-active --quiet fail2ban && echo "Fail2ban 服务正在运行" || echo "Fail2ban 服务未运行"
    echo "系统已经安装Fail2ban，不再重复安装"
fi

# 跟踪连接状态流量规则插入到第1条
if ! sudo iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    # 插入到第一条，因为我们希望这条规则首先被评估
    sudo iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "已添加规则：状态检测，可以更精细地控制流量，防止半开连接"
else
    echo "已添加跟踪连接状态规则，不再重复添加"
fi

# 将环回接口的输入流量规则插入到第2条
if ! sudo iptables -C INPUT -i lo -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT 2 -i lo -j ACCEPT
    echo "已添加规则：允许环回接口的输入流量"
else
    echo "环回接口输入规则已存在，不再重复添加"
fi

# 将已建立和相关的输出流量规则插入到第3条
if ! sudo iptables -C OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    sudo iptables -I OUTPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "已添加规则：允许已建立和相关的输出流量"
else
    echo "已建立和相关输出规则已存在，不再重复添加"
fi

# 将环回接口的输出流量规则插入到第4条
if ! sudo iptables -C OUTPUT -o lo -j ACCEPT 2>/dev/null; then
    sudo iptables -I OUTPUT 2 -o lo -j ACCEPT
    echo "已添加规则：允许环回接口的输出流量"
else
    echo "环回接口输出规则已存在，不再重复添加"
fi

# 防止端口扫描
if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    echo "已添加规则：开启防止端口扫描 (ALL NONE)"
else
    echo "已添加开启防止端口扫描 (ALL NONE)，不再重复添加"
fi


# 阻止无效的TCP标志组合
if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL FIN,RST,URG -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL FIN,RST,URG -j DROP
    echo "已添加规则：阻止无效的TCP标志组合"
else
    echo "阻止无效的TCP标志组合规则已存在，不再重复添加"
fi

#丢弃无效包
if ! sudo iptables -C INPUT -m state --state INVALID -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -m state --state INVALID -j DROP
    echo "已添加规则：丢弃无效包"
else
    echo "已添加丢弃无效包规则，不再重复添加"
fi

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

#限制SYN每秒钟接受一个同一来源SYN请求，初始突发允许3个请求
if ! sudo iptables -C INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
    echo "已添加规则：限制SYN-Flood攻击，syn连接被限制为每秒钟接受一个同一来源SYN请求，初始突发允许3个请求"
else
    echo "已添加限制SYN-Flood攻击规则，不再重复添加"
fi

# 防止XMAS攻击
if ! sudo iptables -C INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
    echo "已添加规则：防止XMAS Tree攻击"
else
    echo "已添加防止XMAS Tree攻击已添加，不再重复添加"
fi



#防止Smurf攻击
if ! sudo iptables -C INPUT -p icmp --icmp-type address-mask-request -j DROP 2>/dev/null; then
    sudo iptables -A INPUT -p icmp --icmp-type address-mask-request -j DROP
    echo "已添加规则：防止Smurf攻击"
else
    echo "已添加防止Smurf攻击规则，不再重复添加"
fi



#保存iptables规则
iptables-save > /etc/iptables.up.rules
echo -e '#!/bin/bash\n/sbin/iptables-restore < /etc/iptables.up.rules' > /etc/network/if-pre-up.d/iptables
chmod +x /etc/network/if-pre-up.d/iptables

iptables-save > /etc/iptables.up.rules

# 输出所有规则
sudo iptables -L -n -v
echo "所有基本攻击缓解已应用,重启依然生效，请检查iptables规则"
