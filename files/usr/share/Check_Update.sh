#!/bin/bash
# zzXGP & 多项目通用自适应无感升级脚本
# 功能：自动识别插件路径、全架构自适应、无感还原数据

# ================= 配置区域 =================
GITHUB_REPO="qsyjc/immortalwrt-xgp-auto-build"
VERSION_FILE="/etc/lenyu_version"
FILE_PREFIX="immortalWrt"
PROJECT_NAME="zzXGP"
# ============================================

# --- [新功能] 自动识别插件并添加备份路径 ---
auto_append_sysupgrade_conf() {
    echo -e "\033[32m正在扫描插件数据路径并优化备份列表...\033[0m"
    
    # 定义需要强制保留的核心目录
    local backup_list=(
        "/etc/config"               # 所有插件的配置
        "/etc/passwd"               # 系统用户
        "/etc/group"                # 用户组
        "/etc/shadow"               # 密码
        "/etc/shm"                  # 共享内存配置
        "/etc/uhttpd.crt"           # HTTPS 证书
        "/etc/uhttpd.key"
        "/usr/share/passwall"       # 针对特定插件的数据目录
        "/usr/share/ssrplus"
        "/etc/v2ray"
        "/etc/xray"
    )

    # 1. 动态扫描所有 luci-app 开头的插件配置文件
    # 扫描 /etc/config 下的文件，这些通常是插件的核心设置
    for conf in /etc/config/*; do
        if [ -f "$conf" ]; then
            backup_list+=("$conf")
        fi
    done

    # 2. 扫描系统中常见的插件数据存储路径 (持久化数据)
    # 自动寻找常用插件的数据存放位
    local data_dirs=(
        "/usr/lib/lua/luci/controller"
        "/usr/lib/lua/luci/model/cbi"
    )
    
    for dir in "${data_dirs[@]}"; do
        [ -d "$dir" ] && backup_list+=("$dir")
    done

    # 3. 写入 /etc/sysupgrade.conf (去重处理)
    for path in "${backup_list[@]}"; do
        if [ -e "$path" ]; then
            # 检查是否已存在，不存在则添加
            grep -qF "$path" /etc/sysupgrade.conf || echo "$path" >> /etc/sysupgrade.conf
        fi
    done
    
    # 清理重复行并排序
    sort -u /etc/sysupgrade.conf -o /etc/sysupgrade.conf
    echo -e "\033[32m备份列表更新完成，已加入 $(wc -l < /etc/sysupgrade.conf) 个路径。\033[0m"
}

# --- 1. 系统环境深度识别 ---
[ -f "$VERSION_FILE" ] && current_version=$(cat "$VERSION_FILE") || current_version="unknown"
target_type=$(grep 'DISTRIB_TARGET=' /etc/openwrt_release | cut -d \' -f 2 | tr '/' '-')
root_fs=$(mount | grep ' / ' | awk '{print $5}')
case "$root_fs" in
    squashfs) fs_tag="squashfs" ;;
    ext4)     fs_tag="ext4" ;;
    *)        fs_tag="squashfs" ;;
esac
[ -d /sys/firmware/efi ] && boot_tag="efi" || boot_tag="legacy"

# --- 2. 云端参数与版本检查 ---
API_URL="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
DOWNLOAD_DIR="/tmp/upgrade"
mkdir -p $DOWNLOAD_DIR && rm -f $DOWNLOAD_DIR/*

echo -e "--- $PROJECT_NAME 运行环境检测 ---"
echo -e "平台架构: $target_type | 分区格式: $fs_tag | 引导: $boot_tag"
echo -e "当前版本: $current_version"
echo -e "--------------------------"

echo -e "正在联网检查最新固件..."
latest_json=$(wget -qO- -t1 -T5 "$API_URL")
[ -z "$latest_json" ] && echo -e "\033[31m 错误: 无法获取 GitHub 信息！\033[0m" && exit 1

cloud_version=$(echo "$latest_json" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')

# --- 3. 智能匹配引擎 ---
if [[ "$target_type" == *"x86"* ]]; then
    if [ "$boot_tag" == "efi" ]; then
        remote_file_name=$(echo "$latest_json" | grep -oEi "${FILE_PREFIX}-${target_type}-[a-zA-Z0-9_.-]*${fs_tag}-combined-efi\.img\.gz" | head -n 1)
    else
        remote_file_name=$(echo "$latest_json" | grep -vi "efi" | grep -oEi "${FILE_PREFIX}-${target_type}-[a-zA-Z0-9_.-]*${fs_tag}-combined\.img\.gz" | head -n 1)
    fi
else
    remote_file_name=$(echo "$latest_json" | grep -oEi "${FILE_PREFIX}-[a-zA-Z0-9_.-]*${target_type}[a-zA-Z0-9_.-]*istore-${fs_tag}-sysupgrade\.img\.gz" | head -n 1)
    [ -z "$remote_file_name" ] && remote_file_name=$(echo "$latest_json" | grep -oEi "${FILE_PREFIX}-[a-zA-Z0-9_.-]*${target_type}[a-zA-Z0-9_.-]*${fs_tag}-sysupgrade\.img\.gz" | head -n 1)
fi

remote_file_url=$(echo "$latest_json" | grep -oE "https://github.com/[^\"]*$remote_file_name" | head -n 1)

# --- 4. 版本比对 ---
if [ "$current_version" == "$cloud_version" ]; then
    echo -e "\n\033[32m 提示: 已是最新版本 ($current_version)。\033[0m\n"
    exit 0
fi

if [ -z "$remote_file_name" ]; then
    echo -e "\033[31m 错误: 未能在云端找到适配固件包！\033[0m" && exit 1
fi

echo -e "发现新版本: \033[32m$cloud_version\033[0m | 正在下载..."
wget -q --show-progress "$remote_file_url" -O "$DOWNLOAD_DIR/upgrade.img.gz"

# --- 5. 交互升级函数 ---
open_up() {
    echo; clear
    echo -e "\033[33m================================================\033[0m"
    echo -e "\033[32m           $PROJECT_NAME 无感全自动升级             \033[0m"
    echo -e "\033[33m================================================\033[0m"
    
    # 核心步骤：在升级前执行路径扫描写入
    auto_append_sysupgrade_conf
    
    echo -e "\n  [提示]: 系统已自动备份所有插件配置与数据路径。"
    echo -e "  [版本]: $cloud_version"
    echo
    read -n 1 -p " 是否保留配置升级？(建议选 Y 实现无感升级): " num1
    echo
    case $num1 in
        Y|y)
            echo -e "\n\033[32m >>> 正在保留配置升级，等待系统自动还原数据… \033[0m\n"
            sleep 2
            sysupgrade "$DOWNLOAD_DIR/upgrade.img.gz"
            ;;
        N|n)
            echo -e "\n\033[31m >>> 正在清空配置升级（恢复出厂）… \033[0m\n"
            sleep 2
            sysupgrade -n "$DOWNLOAD_DIR/upgrade.img.gz"
            ;;
        *)
            open_up ;;
    esac
}

echo; read -n 1 -p " 确认开始升级流程吗？(Y/N): " num2; echo
[[ "$num2" =~ ^[Yy]$ ]] && open_up || exit 0
