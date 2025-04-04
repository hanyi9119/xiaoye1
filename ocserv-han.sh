#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

sh_ver="1.0"
file="/usr/local/sbin/ocserv"
conf_file="/etc/ocserv"
conf="/etc/ocserv/ocserv.conf"
passwd_file="/etc/ocserv/ocpasswd"
log_file="/tmp/ocserv.log"
PID_FILE="/var/run/ocserv.pid"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

#检查系统
check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
	#bit=`uname -m`
}
check_installed_status(){
	[[ ! -e ${file} ]] && echo -e "${Error} ocserv 没有安装，请检查 !" && exit 1
	[[ ! -e ${conf} ]] && echo -e "${Error} ocserv 配置文件不存在，请检查 !" && [[ $1 != "un" ]] && exit 1
}
check_pid(){
	if [[ ! -e ${PID_FILE} ]]; then
		PID=""
	else
		PID=$(cat ${PID_FILE})
	fi
}
Get_ip(){
	ip=$(wget -qO- -t1 -T2 ipinfo.io/ip)
	if [[ -z "${ip}" ]]; then
		ip=$(wget -qO- -t1 -T2 api.ip.sb/ip)
		if [[ -z "${ip}" ]]; then
			ip=$(wget -qO- -t1 -T2 members.3322.org/dyndns/getip)
			if [[ -z "${ip}" ]]; then
				ip="VPS_IP"
			fi
		fi
	fi
}
Set_latest_new_version(){
	echo -e "请输入 要下载安装的 ocserv 版本 [ 格式: x.xx.x ，例如: 0.12.6 或 1.2.4 ]
${Tip} ocserv 版本列表请去这里获取：[ ftp://ftp.infradead.org/pub/ocserv/ ]"
	stty erase '^H' && read -p "(默认回车，自动获取最新版本):" ocserv_ver
	[[ -z "${ocserv_ver}" ]] && check_new_ver
	echo
}
check_new_ver(){
	echo -e "${Info} 开始获取最新版本号..."
	ocserv_ver=$(wget -qO- -t1 -T2 ftp://ftp.infradead.org/pub/ocserv/|grep File|grep -v '.sig'|awk '{print $(NF-2)}'|sed -r 's/.*tar\.xz\">ocserv-(.+)\.tar\.xz<\/a>.*/\1/'|grep -E '[0-9].[0-9].[0-9]'|sort -V | tail -1)
	if [[ -z ${ocserv_ver} ]]; then
		echo -e "${Error} ocserv 最新版本获取失败，请手动获取最新版本号[ ftp://ftp.infradead.org/pub/ocserv/ ]"
		stty erase '^H' && read -p "请输入版本号 [ 格式如 0.12.6 或 1.2.4 ] :" ocserv_ver
		[[ -z "${ocserv_ver}" ]] && echo "取消..." && exit 1
	else
		echo -e "${Info} 检测到 ocserv 最新版本为 [ ${ocserv_ver} ]"
	fi
}
Download_ocserv(){
	mkdir "ocserv" && cd "ocserv"
	wget "ftp://ftp.infradead.org/pub/ocserv/ocserv-${ocserv_ver}.tar.xz"
	[[ ! -s "ocserv-${ocserv_ver}.tar.xz" ]] && echo -e "${Error} ocserv 源码文件下载失败 !" && rm -rf "ocserv/" && rm -rf "ocserv-${ocserv_ver}.tar.xz" && exit 1
	tar -xJf ocserv-${ocserv_ver}.tar.xz && cd ocserv-${ocserv_ver}
	./configure
	make
	make install
	cd .. && cd ..
	rm -rf ocserv/
	
	if [[ -e ${file} ]]; then
		mkdir "${conf_file}"
		wget --no-check-certificate -N -P "${conf_file}" "https://raw.githubusercontent.com/hanyi9119/ocserv/master/ocserv.conf"
		[[ ! -s "${conf}" ]] && echo -e "${Error} ocserv 配置文件下载失败 !" && rm -rf "${conf_file}" && exit 1
	else
		echo -e "${Error} ocserv 编译安装失败，请检查！" && exit 1
	fi
}
Service_ocserv(){
	if ! wget --no-check-certificate https://raw.githubusercontent.com/hanyi9119/ocserv/master/ocserv_debian -O /etc/init.d/ocserv; then
		echo -e "${Error} ocserv 服务 管理脚本下载失败 !" && over
	fi
	chmod +x /etc/init.d/ocserv
	update-rc.d -f ocserv defaults
	echo -e "${Info} ocserv 服务 管理脚本下载完成 !"
}
rand(){
	min=10000
	max=$((60000-$min+1))
	num=$(date +%s%N)
	echo $(($num%$max+$min))
}
Generate_SSL(){
	lalala=$(rand)
	mkdir /tmp/ssl && cd /tmp/ssl
	echo -e 'cn = "'${lalala}'"
organization = "'${lalala}'"
serial = 1
expiration_days = 365
ca
signing_key
cert_signing_key
crl_signing_key' > ca.tmpl
	[[ $? != 0 ]] && echo -e "${Error} 写入SSL证书签名模板失败(ca.tmpl) !" && over
	certtool --generate-privkey --outfile ca-key.pem
	[[ $? != 0 ]] && echo -e "${Error} 生成SSL证书密匙文件失败(ca-key.pem) !" && over
	certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem
	[[ $? != 0 ]] && echo -e "${Error} 生成SSL证书文件失败(ca-cert.pem) !" && over
	
	Get_ip
	if [[ -z "$ip" ]]; then
		echo -e "${Error} 检测外网IP失败 !"
		stty erase '^H' && read -p "请手动输入你的服务器外网IP:" ip
		[[ -z "${ip}" ]] && echo "取消..." && over
	fi
	echo -e 'cn = "'${ip}'"
organization = "'${lalala}'"
expiration_days = 365
signing_key
encryption_key
tls_www_server' > server.tmpl
	[[ $? != 0 ]] && echo -e "${Error} 写入SSL证书签名模板失败(server.tmpl) !" && over
	certtool --generate-privkey --outfile server-key.pem
	[[ $? != 0 ]] && echo -e "${Error} 生成SSL证书密匙文件失败(server-key.pem) !" && over
	certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem
	[[ $? != 0 ]] && echo -e "${Error} 生成SSL证书文件失败(server-cert.pem) !" && over
	
	mkdir /etc/ocserv/ssl
	mv ca-cert.pem /etc/ocserv/ssl/ca-cert.pem
	mv ca-key.pem /etc/ocserv/ssl/ca-key.pem
	mv server-cert.pem /etc/ocserv/ssl/server-cert.pem
	mv server-key.pem /etc/ocserv/ssl/server-key.pem
	cd .. && rm -rf /tmp/ssl/
}
Installation_dependency(){
	[[ ! -e "/dev/net/tun" ]] && echo -e "${Error} 你的VPS没有开启TUN，请联系IDC或通过VPS控制面板打开TUN/TAP开关 !" && exit 1
	if [[ ${release} = "centos" ]]; then
		echo -e "${Error} 本脚本不支持 CentOS 系统 !" && exit 1
	elif [[ ${release} = "debian" ]]; then
		mv /etc/apt/sources.list /etc/apt/sources.list.bak
		wget --no-check-certificate -O "/etc/apt/sources.list" "https://raw.githubusercontent.com/hanyi9119/ocserv/master/us.sources.list"
		apt-get update
		apt-get install vim net-tools pkg-config build-essential libgnutls28-dev libwrap0-dev liblz4-dev libseccomp-dev libreadline-dev libnl-nf-3-dev libev-dev gnutls-bin -y
		rm -rf /etc/apt/sources.list
		mv /etc/apt/sources.list.bak /etc/apt/sources.list
		apt-get update
	else
		apt-get update
		apt-get install vim net-tools pkg-config build-essential libgnutls28-dev libwrap0-dev liblz4-dev libseccomp-dev libreadline-dev libnl-nf-3-dev libev-dev gnutls-bin -y
	fi
}
Install_ocserv(){
	[[ -e ${file} ]] && echo -e "${Error} ocserv 已安装，请检查 !" && exit 1
	Set_latest_new_version
	echo -e "${Info} 开始安装/配置 依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装 配置文件..."
	Download_ocserv
	echo -e "${Info} 开始下载/安装 服务脚本(init)..."
	Service_ocserv
	echo -e "${Info} 开始自签SSL证书..."
	Generate_SSL
	echo -e "${Info} 开始设置账号配置..."
	Read_config
	Set_Config
	echo -e "${Info} 开始设置 iptables防火墙..."
	Set_iptables
	echo -e "${Info} 开始添加 iptables防火墙规则..."
	Add_iptables
	echo -e "${Info} 开始保存 iptables防火墙规则..."
	Save_iptables
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	Start_ocserv
}
Start_ocserv(){
	check_installed_status
	check_pid
	[[ ! -z ${PID} ]] && echo -e "${Error} ocserv 正在运行，请检查 !" && exit 1
	/etc/init.d/ocserv start
	sleep 2s
	check_pid
	[[ ! -z ${PID} ]] && View_Config
}
Stop_ocserv(){
	check_installed_status
	check_pid
	[[ -z ${PID} ]] && echo -e "${Error} ocserv 没有运行，请检查 !" && exit 1
	/etc/init.d/ocserv stop
}
Restart_ocserv(){
	check_installed_status
	check_pid
	[[ ! -z ${PID} ]] && /etc/init.d/ocserv stop
	/etc/init.d/ocserv start
	sleep 2s
	check_pid
	[[ ! -z ${PID} ]] && View_Config
}
Set_ocserv(){
	[[ ! -e ${conf} ]] && echo -e "${Error} ocserv 配置文件不存在 !" && exit 1
	tcp_port=$(cat ${conf}|grep "tcp-port ="|awk -F ' = ' '{print $NF}')
	udp_port=$(cat ${conf}|grep "udp-port ="|awk -F ' = ' '{print $NF}')
	vim ${conf}
	set_tcp_port=$(cat ${conf}|grep "tcp-port ="|awk -F ' = ' '{print $NF}')
	set_udp_port=$(cat ${conf}|grep "udp-port ="|awk -F ' = ' '{print $NF}')
	Del_iptables
	Add_iptables
	Save_iptables
	echo "是否重启 ocserv ? (Y/n)"
	stty erase '^H' && read -p "(默认: Y):" yn
	[[ -z ${yn} ]] && yn="y"
	if [[ ${yn} == [Yy] ]]; then
		Restart_ocserv
	fi
}
Set_username(){
	echo "请输入 要添加的VPN账号 用户名"
	stty erase '^H' && read -p "(默认: admin):" username
	[[ -z "${username}" ]] && username="admin"
	echo && echo -e "	用户名 : ${Red_font_prefix}${username}${Font_color_suffix}" && echo
}
Set_passwd(){
	echo "请输入 要添加的VPN账号 密码"
	stty erase '^H' && read -p "(默认: admin):" userpass
	[[ -z "${userpass}" ]] && userpass="admin"
	echo && echo -e "	密码 : ${Red_font_prefix}${userpass}${Font_color_suffix}" && echo
}
Set_tcp_port(){
	while true
	do
	echo -e "请输入VPN服务端的TCP端口"
	stty erase '^H' && read -p "(默认: 443):" set_tcp_port
	[[ -z "$set_tcp_port" ]] && set_tcp_port="443"
	expr ${set_tcp_port} + 0 &>/dev/null
	if [[ $? -eq 0 ]]; then
		if [[ ${set_tcp_port} -ge 1 ]] && [[ ${set_tcp_port} -le 65535 ]]; then
			echo && echo -e "	TCP端口 : ${Red_font_prefix}${set_tcp_port}${Font_color_suffix}" && echo
			break
		else
			echo -e "${Error} 请输入正确的数字！"
		fi
	else
		echo -e "${Error} 请输入正确的数字！"
	fi
	done
}
Set_udp_port(){
	while true
	do
	echo -e "请输入VPN服务端的UDP端口"
	stty erase '^H' && read -p "(默认: ${set_tcp_port}):" set_udp_port
	[[ -z "$set_udp_port" ]] && set_udp_port="${set_tcp_port}"
	expr ${set_udp_port} + 0 &>/dev/null
	if [[ $? -eq 0 ]]; then
		if [[ ${set_udp_port} -ge 1 ]] && [[ ${set_udp_port} -le 65535 ]]; then
			echo && echo -e "	TCP端口 : ${Red_font_prefix}${set_udp_port}${Font_color_suffix}" && echo
			break
		else
			echo -e "${Error} 请输入正确的数字！"
		fi
	else
		echo -e "${Error} 请输入正确的数字！"
	fi
	done
}
Set_Config(){
	Set_username
	Set_passwd
	echo -e "${userpass}\n${userpass}"|ocpasswd -c ${passwd_file} ${username}
	Set_tcp_port
	Set_udp_port
	sed -i 's/tcp-port = '"$(echo ${tcp_port})"'/tcp-port = '"$(echo ${set_tcp_port})"'/g' ${conf}
	sed -i 's/udp-port = '"$(echo ${udp_port})"'/udp-port = '"$(echo ${set_udp_port})"'/g' ${conf}
}
Read_config(){
	[[ ! -e ${conf} ]] && echo -e "${Error} ocserv 配置文件不存在 !" && exit 1
	conf_text=$(cat ${conf}|grep -v '#')
	tcp_port=$(echo -e "${conf_text}"|grep "tcp-port ="|awk -F ' = ' '{print $NF}')
	udp_port=$(echo -e "${conf_text}"|grep "udp-port ="|awk -F ' = ' '{print $NF}')
	max_same_clients=$(echo -e "${conf_text}"|grep "max-same-clients ="|awk -F ' = ' '{print $NF}')
	max_clients=$(echo -e "${conf_text}"|grep "max-clients ="|awk -F ' = ' '{print $NF}')
}
List_User(){
	[[ ! -e ${passwd_file} ]] && echo -e "${Error} ocserv 账号配置文件不存在 !" && exit 1
	User_text=$(cat ${passwd_file})
	if [[ ! -z ${User_text} ]]; then
		User_num=$(echo -e "${User_text}"|wc -l)
		user_list_all=""
		for((integer = 1; integer <= ${User_num}; integer++))
		do
			user_name=$(echo -e "${User_text}" | awk -F ':*:' '{print $1}' | sed -n "${integer}p")
			user_status=$(echo -e "${User_text}" | awk -F ':*:' '{print $NF}' | sed -n "${integer}p"|cut -c 1)
			if [[ ${user_status} == '!' ]]; then
				user_status="禁用"
			else
				user_status="启用"
			fi
			user_list_all=${user_list_all}"用户名: "${user_name}" 账号状态: "${user_status}"\n"
		done
		echo && echo -e "用户总数 ${Green_font_prefix}"${User_num}"${Font_color_suffix}"
		echo -e ${user_list_all}
	fi
}
Add_User(){
	Set_username
	Set_passwd
	user_status=$(cat "${passwd_file}"|grep "${username}"':*:')
	[[ ! -z ${user_status} ]] && echo -e "${Error} 用户名已存在 ![ ${username} ]" && exit 1
	echo -e "${userpass}\n${userpass}"|ocpasswd -c ${passwd_file} ${username}
	user_status=$(cat "${passwd_file}"|grep "${username}"':*:')
	if [[ ! -z ${user_status} ]]; then
		echo -e "${Info} 账号添加成功 ![ ${username} ]"
	else
		echo -e "${Error} 账号添加失败 ![ ${username} ]" && exit 1
	fi
}
Del_User(){
	List_User
	[[ ${User_num} == 1 ]] && echo -e "${Error} 当前仅剩一个账号配置，无法删除 !" && exit 1
	echo -e "请输入要删除的VPN账号的用户名"
	stty erase '^H' && read -p "(默认取消):" Del_username
	[[ -z "${Del_username}" ]] && echo "已取消..." && exit 1
	user_status=$(cat "${passwd_file}"|grep "${Del_username}"':*:')
	[[ -z ${user_status} ]] && echo -e "${Error} 用户名不存在 ! [${Del_username}]" && exit 1
	ocpasswd -c ${passwd_file} -d ${Del_username}
	user_status=$(cat "${passwd_file}"|grep "${Del_username}"':*:')
	if [[ -z ${user_status} ]]; then
		echo -e "${Info} 删除成功 ! [${Del_username}]"
	else
		echo -e "${Error} 删除失败 ! [${Del_username}]" && exit 1
	fi
}
Modify_User_disabled(){
	List_User
	echo -e "请输入要启用/禁用的VPN账号的用户名"
	stty erase '^H' && read -p "(默认取消):" Modify_username
	[[ -z "${Modify_username}" ]] && echo "已取消..." && exit 1
	user_status=$(cat "${passwd_file}"|grep "${Modify_username}"':*:')
	[[ -z ${user_status} ]] && echo -e "${Error} 用户名不存在 ! [${Modify_username}]" && exit 1
	user_status=$(cat "${passwd_file}" | grep "${Modify_username}"':*:' | awk -F ':*:' '{print $NF}' |cut -c 1)
	if [[ ${user_status} == '!' ]]; then
			ocpasswd -c ${passwd_file} -u ${Modify_username}
			user_status=$(cat "${passwd_file}" | grep "${Modify_username}"':*:' | awk -F ':*:' '{print $NF}' |cut -c 1)
			if [[ ${user_status} != '!' ]]; then
				echo -e "${Info} 启用成功 ! [${Modify_username}]"
			else
				echo -e "${Error} 启用失败 ! [${Modify_username}]" && exit 1
			fi
		else
			ocpasswd -c ${passwd_file} -l ${Modify_username}
			user_status=$(cat "${passwd_file}" | grep "${Modify_username}"':*:' | awk -F ':*:' '{print $NF}' |cut -c 1)
			if [[ ${user_status} == '!' ]]; then
				echo -e "${Info} 禁用成功 ! [${Modify_username}]"
			else
				echo -e "${Error} 禁用失败 ! [${Modify_username}]" && exit 1
			fi
		fi
}
Set_Pass(){
	check_installed_status
	echo && echo -e " 你要做什么？
	
 ${Green_font_prefix} 0.${Font_color_suffix} 列出 账号配置
————————
 ${Green_font_prefix} 1.${Font_color_suffix} 添加 账号配置
 ${Green_font_prefix} 2.${Font_color_suffix} 删除 账号配置
————————
 ${Green_font_prefix} 3.${Font_color_suffix} 启用/禁用 账号配置
 
 注意：添加/修改/删除 账号配置后，VPN服务端会实时读取，无需重启服务端 !" && echo
	stty erase '^H' && read -p "(默认: 取消):" set_num
	[[ -z "${set_num}" ]] && echo "已取消..." && exit 1
	if [[ ${set_num} == "0" ]]; then
		List_User
	elif [[ ${set_num} == "1" ]]; then
		Add_User
	elif [[ ${set_num} == "2" ]]; then
		Del_User
	elif [[ ${set_num} == "3" ]]; then
		Modify_User_disabled
	else
		echo -e "${Error} 请输入正确的数字[1-3]" && exit 1
	fi
}
View_Config(){
	Get_ip
	Read_config
	clear && echo "===================================================" && echo
	echo -e " AnyConnect 配置信息：" && echo
	echo -e " I  P\t\t  : ${Green_font_prefix}${ip}${Font_color_suffix}"
	echo -e " TCP端口\t  : ${Green_font_prefix}${tcp_port}${Font_color_suffix}"
	echo -e " UDP端口\t  : ${Green_font_prefix}${udp_port}${Font_color_suffix}"
	echo -e " 单用户设备数限制 : ${Green_font_prefix}${max_same_clients}${Font_color_suffix}"
	echo -e " 总用户设备数限制 : ${Green_font_prefix}${max_clients}${Font_color_suffix}"
	echo -e "\n 客户端链接请填写 : ${Green_font_prefix}${ip}:${tcp_port}${Font_color_suffix}"
	echo && echo "==================================================="
}
View_Log(){
	[[ ! -e ${log_file} ]] && echo -e "${Error} ocserv 日志文件不存在 !" && exit 1
	echo && echo -e "${Tip} 按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 终止查看日志" && echo
	tail -f ${log_file}
}
Uninstall_ocserv(){
	check_installed_status "un"
	echo "确定要卸载 ocserv ? (y/N)"
	echo
	stty erase '^H' && read -p "(默认: n):" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
		check_pid
		[[ ! -z $PID ]] && kill -9 ${PID} && rm -f ${PID_FILE}
		Read_config
		Del_iptables
		Save_iptables
		update-rc.d -f ocserv remove
		rm -rf /etc/init.d/ocserv
		rm -rf "${conf_file}"
		rm -rf "${log_file}"
		cd '/usr/local/bin' && rm -f occtl
		rm -f ocpasswd
		cd '/usr/local/bin' && rm -f ocserv-fw
		cd '/usr/local/sbin' && rm -f ocserv
		cd '/usr/local/share/man/man8' && rm -f ocserv.8
		rm -f ocpasswd.8
		rm -f occtl.8
		echo && echo "ocserv 卸载完成 !" && echo
	else
		echo && echo "卸载已取消..." && echo
	fi
}
over(){
	update-rc.d -f ocserv remove
	rm -rf /etc/init.d/ocserv
	rm -rf "${conf_file}"
	rm -rf "${log_file}"
	cd '/usr/local/bin' && rm -f occtl
	rm -f ocpasswd
	cd '/usr/local/bin' && rm -f ocserv-fw
	cd '/usr/local/sbin' && rm -f ocserv
	cd '/usr/local/share/man/man8' && rm -f ocserv.8
	rm -f ocpasswd.8
	rm -f occtl.8
	echo && echo "安装过程错误，ocserv 卸载完成 !" && echo
}

Add_iptables() {
    # 检查 TCP 规则是否存在，如果不存在则添加
    if ! iptables -C INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT
    fi

    # 检查 UDP 规则是否存在，如果不存在则添加
    if ! iptables -C INPUT -p udp --dport ${set_udp_port} -j ACCEPT >/dev/null 2>&1; then
        iptables -A INPUT -p udp --dport ${set_udp_port} -j ACCEPT
    fi

    # 检查 IPv6 TCP 规则是否存在，如果不存在则添加
    if ! ip6tables -C INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT >/dev/null 2>&1; then
        ip6tables -A INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT
    fi

    # 检查 IPv6 UDP 规则是否存在，如果不存在则添加
    if ! ip6tables -C INPUT -p udp --dport ${set_udp_port} -j ACCEPT >/dev/null 2>&1; then
        ip6tables -A INPUT -p udp --dport ${set_udp_port} -j ACCEPT
    fi
}

Del_iptables() {
    # 读取 ocserv 配置文件中的端口
    local ocserv_config="/etc/ocserv/ocserv.conf"  # ocserv 配置文件路径
    local set_tcp_port set_udp_port

    # 从配置文件中提取 TCP 端口
    set_tcp_port=$(grep -oP '^tcp-port\s*=\s*\K[0-9]+' "${ocserv_config}" 2>/dev/null)
    if [[ -z "${set_tcp_port}" ]]; then
        set_tcp_port=443  # 如果未找到，使用默认端口 443
    fi

    # 从配置文件中提取 UDP 端口
    set_udp_port=$(grep -oP '^udp-port\s*=\s*\K[0-9]+' "${ocserv_config}" 2>/dev/null)
    if [[ -z "${set_udp_port}" ]]; then
        set_udp_port=443  # 如果未找到，使用默认端口 443
    fi

    # 删除 IPv4 TCP 规则（如果存在）
    if iptables -C INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT >/dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT
    fi

    # 删除 IPv4 UDP 规则（如果存在）
    if iptables -C INPUT -p udp --dport ${set_udp_port} -j ACCEPT >/dev/null 2>&1; then
        iptables -D INPUT -p udp --dport ${set_udp_port} -j ACCEPT
    fi

    # 删除 IPv6 TCP 规则（如果存在）
    if ip6tables -C INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT >/dev/null 2>&1; then
        ip6tables -D INPUT -p tcp --dport ${set_tcp_port} -j ACCEPT
    fi

    # 删除 IPv6 UDP 规则（如果存在）
    if ip6tables -C INPUT -p udp --dport ${set_udp_port} -j ACCEPT >/dev/null 2>&1; then
        ip6tables -D INPUT -p udp --dport ${set_udp_port} -j ACCEPT
    fi

    # 保存当前规则
    sudo iptables-save > /etc/iptables/rules.v4
    sudo ip6tables-save > /etc/iptables/rules.v6
 
    # 定义规则文件路径
    RULES_V4="/etc/iptables/rules.v4"
    RULES_V6="/etc/iptables/rules.v6"

    # 获取网卡名称
    INTERFACE=$(ip link show | awk -F': ' '/state UP/ {print $2}')

    # 删除 /etc/iptables/rules.v4 中所有符合条件的规则
    if [ -f "$RULES_V4" ]; then
        # 删除所有匹配的规则
        sed -i "/-A POSTROUTING -o $INTERFACE -j MASQUERADE/d" "$RULES_V4"
    fi

    # 删除 /etc/iptables/rules.v6 中所有符合条件的规则
    if [ -f "$RULES_V6" ]; then
        # 删除所有匹配的规则
        sed -i "/-A POSTROUTING -o $INTERFACE -j MASQUERADE/d" "$RULES_V6"
    fi

    # 重新加载规则
    sudo netfilter-persistent reload

    # 删除 /etc/sysctl.conf 中的 IPv4 和 IPv6 转发配置
    sed -i '/^net.ipv4.ip_forward = 1$/d' /etc/sysctl.conf
    sed -i '/^net.ipv6.conf.all.forwarding = 1$/d' /etc/sysctl.conf

    # 重新加载 sysctl 配置
    sysctl -p >/dev/null 2>&1;

}

Save_iptables(){
	sudo iptables-save > /etc/iptables/rules.v4
	sudo ip6tables-save > /etc/iptables/rules.v6
}

Set_iptables(){
    echo -e "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    echo -e "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p

    # 自动获取公网通讯的网卡名称
    Network_card=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

    if [[ -z ${Network_card} ]]; then
        echo -e "${Error} 无法自动获取网卡名 !"
        ifconfig_status=$(ifconfig)
        if [[ -z ${ifconfig_status} ]]; then
            stty erase '^H' && read -p "请手动输入你的网卡名(一般为 eth0，OpenVZ则为 venet0):" Network_card
            [[ -z "${Network_card}" ]] && echo "取消..." && exit 1
        else
            ifconfig
            stty erase '^H' && read -p "检测到本服务器的网卡非 eth0 和 venet0 请根据上面输出的网卡信息手动输入你的网卡名:" Network_card
            [[ -z "${Network_card}" ]] && echo "取消..." && exit 1
        fi
    fi

    sudo iptables -t nat -A POSTROUTING -o ${Network_card} -j MASQUERADE
    sudo ip6tables -t nat -A POSTROUTING -o ${Network_card} -j MASQUERADE

    # 创建规则文件目录
    sudo mkdir -p /etc/iptables

    # 创建规则文件
    sudo touch /etc/iptables/rules.v4
    sudo touch /etc/iptables/rules.v6

    # 保存当前规则
    sudo iptables-save > /etc/iptables/rules.v4
    sudo ip6tables-save > /etc/iptables/rules.v6

    # 设置文件权限
    sudo chown root:root /etc/iptables/rules.v4 /etc/iptables/rules.v6
    sudo chmod 600 /etc/iptables/rules.v4 /etc/iptables/rules.v6

    # 安装 iptables-persistent
    # 设置自动保存 IPv4 和 IPv6 规则的选项为 "Yes"
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q iptables-persistent
    
    # 启用 netfilter-persistent 服务
    sudo systemctl enable netfilter-persistent

    # 重启 netfilter-persistent 服务以加载规则
    sudo systemctl restart netfilter-persistent
}

Update_Shell(){
	echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ocserv.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && exit 1
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		stty erase '^H' && read -p "(默认: y):" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ocserv.sh && chmod +x ocserv.sh
			echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
		else
			echo && echo "	已取消..." && echo
		fi
	else
		echo -e "当前已是最新版本[ ${sh_new_ver} ] !"
	fi
}
check_sys
[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1
echo && echo -e " ocserv 小野一键脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  -- xiaoye | love china --
  
 ${Green_font_prefix}0.${Font_color_suffix} 升级脚本
————————————
 ${Green_font_prefix}1.${Font_color_suffix} 安装 ocserv
 ${Green_font_prefix}2.${Font_color_suffix} 卸载 ocserv
————————————
 ${Green_font_prefix}3.${Font_color_suffix} 启动 ocserv
 ${Green_font_prefix}4.${Font_color_suffix} 停止 ocserv
 ${Green_font_prefix}5.${Font_color_suffix} 重启 ocserv
————————————
 ${Green_font_prefix}6.${Font_color_suffix} 设置 账号配置
 ${Green_font_prefix}7.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix}8.${Font_color_suffix} 修改 配置文件
 ${Green_font_prefix}9.${Font_color_suffix} 查看 日志信息
————————————" && echo
if [[ -e ${file} ]]; then
	check_pid
	if [[ ! -z "${PID}" ]]; then
		echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix} 并 ${Green_font_prefix}已启动${Font_color_suffix}"
	else
		echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix} 但 ${Red_font_prefix}未启动${Font_color_suffix}"
	fi
else
	echo -e " 当前状态: ${Red_font_prefix}未安装${Font_color_suffix}"
fi
echo
stty erase '^H' && read -p " 请输入数字 [0-9]:" num
case "$num" in
	0)
	Update_Shell
	;;
	1)
	Install_ocserv
	;;
	2)
	Uninstall_ocserv
	;;
	3)
	Start_ocserv
	;;
	4)
	Stop_ocserv
	;;
	5)
	Restart_ocserv
	;;
	6)
	Set_Pass
	;;
	7)
	View_Config
	;;
	8)
	Set_ocserv
	;;
	9)
	View_Log
	;;
	*)
	echo "请输入正确数字 [0-9]"
	;;
esac
