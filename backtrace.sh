#!/bin/bash

# ============================================
# 回国线路路由追踪脚本 (简洁版 + 线路识别)
# 功能: 自动检测并安装 nexttrace，测试国内核心 DNS 回程路由，自动识别高端线路
# 安全: 测试目标均为运营商官方核心 DNS，安全可靠
# 顺序: 北京(电信/联通/移动) -> 上海(电信/联通/移动) -> 深圳(电信/联通/移动) -> 成都教育网
# 依赖: curl
# ============================================

# --- 检查并安装 nexttrace ---
if ! command -v nexttrace &> /dev/null; then
    echo "nexttrace 未安装，正在安装..."
    curl -fsSL https://nxtrace.org/nt | bash
    echo "安装完成。"
fi

# --- 定义分隔线函数 ---
next() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}

# --- 线路识别函数（经典模式输出）---
detect_premium_line() {
    local output="$1"
    if echo "$output" | grep -qE "\b59\.43\.[0-9]+\.[0-9]+\b" && ! echo "$output" | grep -qE "\b202\.97\.[0-9]+\.[0-9]+\b"; then
        echo "   ✨ 线路: 电信 CN2 GIA"
        return
    fi
    if echo "$output" | grep -qE "\b202\.97\.[0-9]+\.[0-9]+\b" && echo "$output" | grep -qE "\b59\.43\.[0-9]+\.[0-9]+\b"; then
        echo "   ⚡ 线路: 电信 CN2 GT"
        return
    fi
    if echo "$output" | grep -qE "\b(218\.105\.|210\.51\.)[0-9]+\.[0-9]+\b"; then
        echo "   ✨ 线路: 联通 AS9929 (CUII)"
        return
    fi
    if echo "$output" | grep -qE "\b223\.120\.[0-9]+\.[0-9]+\b" || echo "$output" | grep -qi "AS58807"; then
        echo "   ✨ 线路: 移动 CMIN2"
        return
    fi
    if echo "$output" | grep -qi "AS10099"; then
        echo "   ✨ 线路: 联通 AS10099"
        return
    fi
    # 未匹配到高端线路，无输出
}

# --- 按城市分组，每个城市内顺序：电信、联通、移动 ---
# 格式: "城市+运营商:IP"
declare -a test_items=(
    "北京电信:219.141.147.210"
    "北京联通:202.106.50.1"
    "北京移动:221.179.155.161"
    "上海电信:202.96.209.133"
    "上海联通:210.22.97.1"
    "上海移动:211.136.112.200"
    "深圳电信:58.60.188.222"
    "深圳联通:210.21.196.6"
    "深圳移动:120.196.165.24"
    "成都教育网:202.112.14.151"
)

# --- 开始测试 ---
clear
next
echo "🔒 测试目标均为运营商官方核心 DNS，安全可靠"
next

for item in "${test_items[@]}"; do
    name="${item%:*}"
    ip="${item#*:}"
    echo "【$name】"
    output=$(sudo nexttrace -M "$ip" 2>&1)
    echo "$output"
    line_hint=$(detect_premium_line "$output")
    if [ -n "$line_hint" ]; then
        echo "$line_hint"
    fi
    next
done

echo "✅ 所有测试完成。"