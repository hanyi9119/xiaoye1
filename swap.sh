#!/bin/bash
rm -f $0
echo 当前swap分区大小为：
id=`free -m | grep "Swap"| awk  '{print $2}'`&& echo Swap：${id}MB
swapoff -a #停止所有的swap分区
echo "请注意：如果当前服务器有swap的话，新建swap后的大小会叠加，所以请酌情添加swap，建议swap为内存的2倍较为适中。"
if [ ! -n "$1" ]; then
	echo "请输入以MB为单位的swap分区大小并回车："
	read swap
	dd if=/dev/zero of=/home/swapfile bs=1M count=$swap
	else
	dd if=/dev/zero of=/home/swapfile bs=1M count=$1
	fi
mkswap /home/swapfile #建立swap的文件系统
swapon /home/swapfile #启用swap文件
echo "/home/swapfile swap swap defaults 0 0" >>/etc/fstab
echo "swap建立完成！"
free -m