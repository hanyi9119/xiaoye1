#!/bin/bash

# 提示用户需要root权限
if [[ $EUID -ne 0 ]]; then
   echo "此脚本需要以root权限运行。" 
   exit 1
fi

# 可配置参数
LOG_FILE="/var/log/tmp_clean.log"  # 日志文件路径
TMP_DIRS="/tmp /var/tmp"         # 需要清理的临时目录

# 记录脚本执行时间
start_time=$(date +%Y%m%d_%H%M%S)

# 创建日志文件
echo "开始清理临时文件: $(date)" > "$LOG_FILE"

# 遍历每个临时目录
for dir in $TMP_DIRS; do
    echo "正在清理目录: $dir" >> "$LOG_FILE"
    # 删除7天前的文件
    find "$dir" -type f -mtime +7 -exec rm -rf {} \; 2>&1 | tee -a "$LOG_FILE"
done

# 清理 apt 缓存
echo "清理 apt 缓存..."
sudo apt-get clean

# 清理 apt 缓存的包
echo "清理 apt 缓存的包..."
sudo apt-get autoclean

# 清理 /tmp 目录下的临时文件
echo "清理 /tmp 目录下的临时文件..."
sudo rm -rf /tmp/*

# 清理 /var/tmp 目录下的临时文件
echo "清理 /var/tmp 目录下的临时文件..."
sudo rm -rf /var/tmp/*

# 清理 /var/cache 目录下的缓存文件
echo "清理 /var/cache 目录下的缓存文件..."
sudo rm -rf /var/cache/*

# 清理 /var/log 目录下的日志文件
echo "清理 /var/log 目录下的日志文件..."
sudo find /var/log -type f -mmin +60 -exec rm -f {} \;

# 清理 /boot 目录下的旧内核
echo "清理 /boot 目录下的旧内核..."
dpkg --list 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge

# 清理未被使用的依赖包
echo "清理未被使用的依赖包..."
sudo apt-get autoremove

# 清理系统更新时留下的存档文件
echo "清理系统更新时留下的存档文件..."
sudo apt-get -y autoremove --purge

# 清理下载的软件包缓存
echo "清理下载的软件包缓存..."
sudo apt-get clean


# 记录结束时间
end_time=$(date +%Y%m%d_%H%M%S)
echo "清理完成: $(date)" >> "$LOG_FILE"

# 计算耗时
echo "共耗时: $(( $(date +%s -d "$end_time") - $(date +%s -d "$start_time") )) 秒" >> "$LOG_FILE"
