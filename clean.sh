#!/bin/bash

# 提示用户需要root权限
if [[ $EUID -ne 0 ]]; then
   echo "此脚本需要以root权限运行。" 
   exit 1
fi

# 可配置参数
LOG_FILE="/var/log/tmp_clean.log"  # 日志文件路径
TMP_DIRS="/tmp /var/tmp"           # 需要清理的临时目录

# 记录脚本执行时间
start_time=$(date +%s)
start_time_human=$(date '+%Y-%m-%d %H:%M:%S')

# 创建日志文件
echo "开始清理临时文件: $start_time_human" > "$LOG_FILE"

# 遍历每个临时目录
for dir in $TMP_DIRS; do
    echo "正在清理目录: $dir" >> "$LOG_FILE"
    # 删除7天前的文件
    find "$dir" -type f -mtime +7 -exec rm -rf {} \; 2>&1 | tee -a "$LOG_FILE"
done

# 清理 apt 缓存
echo "清理 apt 缓存..." | tee -a "$LOG_FILE"
apt-get clean

# 清理 apt 缓存的包
echo "清理 apt 缓存的包..." | tee -a "$LOG_FILE"
apt-get autoclean

# 清理 /var/cache 目录下的缓存文件
echo "清理 /var/cache 目录下的缓存文件..." | tee -a "$LOG_FILE"
rm -rf /var/cache/*

# 清理 /var/log 目录下的日志文件
echo "清理 /var/log 目录下的日志文件..." | tee -a "$LOG_FILE"
find /var/log -type f -mmin +60 -exec rm -f {} \;

# 清理 /boot 目录下的旧内核
echo "清理 /boot 目录下的旧内核..." | tee -a "$LOG_FILE"
dpkg --list 'linux-*' | awk '/^ii/{print $2}' | grep -vE "linux-(headers|image)-$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")" | xargs apt-get -y purge

# 清理未被使用的依赖包
echo "清理未被使用的依赖包..." | tee -a "$LOG_FILE"
apt-get autoremove -y

# 清理系统更新时留下的存档文件
echo "清理系统更新时留下的存档文件..." | tee -a "$LOG_FILE"
apt-get -y autoremove --purge

# 清理下载的软件包缓存
echo "清理下载的软件包缓存..." | tee -a "$LOG_FILE"
apt-get clean

# 记录结束时间
end_time=$(date +%s)
end_time_human=$(date '+%Y-%m-%d %H:%M:%S')
echo "清理完成: $end_time_human" >> "$LOG_FILE"

# 计算耗时
echo "共耗时: $((end_time - start_time)) 秒" >> "$LOG_FILE"
