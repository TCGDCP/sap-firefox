#!/bin/bash

# 配置变量
export PORT=${PORT:-"8080"}
export VNC_PASSWORD=${VNC_PASSWORD:-"password"}
export RESOLUTION=${RESOLUTION:-"720x1280"}
export GBACKUP_USER=${GBACKUP_USER:-""}
export GBACKUP_REPO=${GBACKUP_REPO:-""}
export GBACKUP_TOKEN=${GBACKUP_TOKEN:-""}
export BACKUP_DIR="/home/vncuser/firefox-backup"
export AUTO_BACKUP=${AUTO_BACKUP:-"NO"}
export AUTO_RESTORE=${AUTO_RESTORE:-"NO"}
export INTERVALINSECONDS=${INTERVALINSECONDS:-"1800"} # 单位为秒,默认30分钟

export UUID=${UUID:-''} # V1需要
export NEZHA_VERSION=${NEZHA_VERSION:-'V1'} # V0 OR V1
export NEZHA_SERVER=${NEZHA_SERVER:-''} # 不填不启用哪吒
export NEZHA_KEY=${NEZHA_KEY:-''} # 不填不启用哪吒
export NEZHA_PORT=${NEZHA_PORT:-'443'}

# 解析分辨率
IFS='x' read -ra RES <<< "$RESOLUTION"
VNC_WIDTH="${RES[0]}"
VNC_HEIGHT="${RES[1]}"
VNC_DEPTH="24"

# 计算Firefox窗口大小（全屏）
FIREFOX_WIDTH=$VNC_WIDTH
FIREFOX_HEIGHT=$VNC_HEIGHT

# Firefox备份还原设置
export profile_dir="/home/vncuser/.mozilla/firefox"
mkdir -p "$profile_dir"
if [[ -n "$GBACKUP_USER" ]] && [[ -n "$GBACKUP_REPO" ]] && [[ -n "$GBACKUP_TOKEN" ]]; then
   export repo_url="https://${GBACKUP_TOKEN}@github.com/${GBACKUP_USER}/${GBACKUP_REPO}.git"
else
   export repo_url=""
fi

# Firefox 备份
backup_firefox() {
    [[ -z "$repo_url" ]] && { echo "❌ 未配置GitHub仓库"; return 0; }

    echo "开始备份Firefox配置到GitHub..."
    echo "仓库: ${GBACKUP_USER}/${GBACKUP_REPO}"

    if [ ! -d "$profile_dir" ]; then
        echo "⚠ Firefox配置文件目录不存在，跳过备份"
        return 0
    fi

    # 创建备份目录
    mkdir -p "$BACKUP_DIR/firefox-profile"
    echo "备份时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$BACKUP_DIR/README.md"

    # 复制配置文件到备份目录
    rsync -av --no-t --delete --exclude='Cache' --exclude='cache2' --exclude='thumbnails' \
        "$profile_dir/" "$BACKUP_DIR/firefox-profile/" >/dev/null 2>&1

    # 进入备份目录操作
    cd "$BACKUP_DIR" || { echo "❌ 进入备份目录失败"; return 1; }

    # 初始化Git仓库（如果不存在）
    if [ ! -d ".git" ]; then
        echo "初始化Git仓库..."
        git init --initial-branch=main >/dev/null
        echo "✅ 本地Git仓库初始化完成"
    fi

    # 总是设置Git配置（确保每次都有）
    git config user.email "firefox-backup@docker.container"
    git config user.name "Firefox Backup Bot"
    git remote remove origin 2>/dev/null || true
    git remote add origin "$repo_url"

    # 提交更改
    echo "检查更改..."
    git add . >/dev/null 2>&1

    # 检查是否有更改需要提交
    if git diff --staged --name-only | grep -Ev "(^README\.md$|^\.git/)" | grep -q .; then
        echo "检测到Firefox配置文件更改，提交到GitHub..."

        if git commit -m "Firefox备份 $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1; then
            echo "✅ 提交创建成功"
        else
            echo "❌ 提交创建失败，错误信息如上"
            cd - >/dev/null
            return 1
        fi

        # 推送到GitHub
        echo "推送更改到远程仓库..."
        if git push -u origin main >/dev/null 2>&1; then
            echo "✅ 备份成功推送到 ${GBACKUP_USER}/${GBACKUP_REPO}"
        else
            echo "⚠ 推送失败，尝试强制推送..."
            if git push -f -u origin main >/dev/null 2>&1; then
                echo "✅ 强制推送完成"
            else
                echo "❌ 推送失败，请检查网络和权限"
                cd - >/dev/null
                return 1
            fi
        fi

        echo "📦 备份大小: $(du -sh firefox-profile | cut -f1)"
        echo "✅ 备份完成"
    else
        echo "⚠ 没有检测到Firefox配置文件更改，跳过提交"
    fi

    # 返回主目录
    cd /home/vncuser
}

# Firefox 还原
restore_firefox() {
    [[ -z "$repo_url" ]] && { echo "❌ 未配置GitHub仓库"; return 0; }
    echo "尝试从GitHub恢复Firefox配置..."

    # 清理现有备份目录
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # 进入备份目录
    cd "$BACKUP_DIR"

    # 尝试克隆仓库，明确指定main分支
    echo "从GitHub main分支下载备份..."
    if git clone -b main --single-branch "$repo_url" . 2>/dev/null; then
        echo "✅ 成功从main分支克隆仓库"
    fi

    if [ -d "$BACKUP_DIR/firefox-profile" ]; then
        rm -rf "$profile_dir"

        # 恢复配置
        mkdir -p "$profile_dir"
        rsync -av "$BACKUP_DIR/firefox-profile/" "$profile_dir/" >/dev/null 2>&1

        # 设置正确的权限
        chown -R vncuser:vncuser "$profile_dir" 2>/dev/null || true

        echo "✅ Firefox配置已从GitHub main分支恢复"
        if [ -f "$BACKUP_DIR/README.md" ]; then
            echo "📅 备份信息:"
            cat "$BACKUP_DIR/README.md"
        fi
    else
        echo "⚠ 没有找到可恢复的备份文件，将使用全新配置"
    fi

    # 返回主目录
    cd /home/vncuser
}

# 如果提供了参数，执行相应操作后退出
case "${1:-}" in
    "backup")
        backup_firefox
        exit 0
        ;;
    "restore")
        restore_firefox
        exit 0
        ;;
    "help")
        echo "🔥 Firefox VNC容器备份工具"
        echo "用法: ./start.sh [command]"
        echo ""
        echo "命令:"
        echo "  backup    - 备份Firefox配置到GitHub"
        echo "  restore   - 从GitHub恢复Firefox配置"
        echo "  help      - 显示帮助信息"
        echo ""
        echo "环境变量:"
        echo "  GBACKUP_USER   - GitHub用户名"
        echo "  GBACKUP_REPO   - GitHub仓库名"
        echo "  GBACKUP_TOKEN  - GitHub访问令牌"
        echo "  VNC_PASSWORD   - VNC密码 (默认: password)"
        echo "  RESOLUTION     - 分辨率 (默认: 1280x800)"
        echo ""
        echo "无参数启动VNC服务"
        exit 0
        ;;
esac

# 以下是正常的VNC启动流程
echo "🚀 启动Firefox VNC服务..."

# 创建必要的目录
mkdir -p ~/.vnc
mkdir -p "$BACKUP_DIR"
chmod 700 ~/.vnc

# 设置VNC密码
echo "$VNC_PASSWORD" | x11vnc -storepasswd - > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# 清理旧的锁文件
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

# 启动前尝试恢复配置
[[ "$AUTO_RESTORE" == "YES" ]] && restore_firefox

# 启动虚拟显示
echo "启动X虚拟帧缓冲区 ${RESOLUTION}..."
Xvfb :0 -screen 0 ${VNC_WIDTH}x${VNC_HEIGHT}x${VNC_DEPTH} \
    +extension RANDR \
    +extension GLX \
    +extension RENDER \
    -nolisten tcp \
    -noreset \
    -ac \
    > /tmp/xvfb.log 2>&1 &

# 等待Xvfb启动
sleep 3

# 设置显示环境变量
export DISPLAY=:0

# 等待X服务器完全启动
sleep 2

# 启动Firefox
firefox --no-remote --width=$FIREFOX_WIDTH --height=$FIREFOX_HEIGHT > /tmp/firefox.log 2>&1 &
sleep 8

# 检查Firefox是否正常运行
if ! ps aux | grep firefox | grep -v grep > /dev/null; then
    echo "⚠ Firefox启动失败，尝试重新启动..."
    firefox --no-remote --width=$FIREFOX_WIDTH --height=$FIREFOX_HEIGHT > /tmp/firefox.log 2>&1 &
    sleep 5
else
    echo "启动Firefox (${FIREFOX_WIDTH}x${FIREFOX_HEIGHT})..."
fi

# 启动VNC服务器
echo "启动VNC服务器..."
x11vnc -display :0 \
    -forever \
    -shared \
    -passwd "$VNC_PASSWORD" \
    -rfbport 5900 \
    -noxdamage \
    -geometry ${RESOLUTION} \
    -wait 5 \
    -defer 5 \
    > /tmp/x11vnc.log 2>&1 &

# 启动noVNC
echo "启动noVNC..."
if [ -d "/usr/share/novnc" ]; then
    websockify --web /usr/share/novnc ${PORT} localhost:5900 > /tmp/novnc.log 2>&1 &
else
    websockify ${PORT} localhost:5900 > /tmp/novnc.log 2>&1 &
fi

# 设置定时备份（每30分钟备份一次）
if [[ "$AUTO_BACKUP" == "YES" ]]; then
    INTERVALINMINUTES=$((INTERVALINSECONDS / 60))
    echo "⏰ 每 $INTERVALINMINUTES 分钟自动定时备份已经激活..."
    while true; do
        sleep "$INTERVALINSECONDS"
        backup_firefox
    done &
else
    echo "⏰ 不执行定时备份... 如需启用定时备份，请设置环境变量: AUTO_BACKUP=YES"
fi

if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ]; then
    ARCH=$(uname -m)
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    case "${NEZHA_VERSION}" in
      "V0" )
        if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x64" ]; then
          curl -sSL "https://github.com/kahunama/myfile/releases/download/main/nezha-agent" -o /home/vncuser/npm
        else
          curl -sSL "https://github.com/kahunama/myfile/releases/download/main/nezha-agent_arm" -o /home/vncuser/npm
        fi
        chmod +x /home/vncuser/npm
        if [[ " ${tlsPorts[@]} " =~ " ${NEZHA_PORT} " ]]; then
          NEZHA_TLS="--tls"
        else
          NEZHA_TLS=""
        fi
        /home/vncuser/npm -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} --report-delay=4 --skip-conn --skip-procs --disable-auto-update >/dev/null 2>&1 &
        ;;
      "V1" )
        if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x64" ]; then
          curl -sSL "https://github.com/mytcgd/myfiles/releases/download/main/nezha-agentv1" -o /home/vncuser/npm
        else
          curl -sSL "https://github.com/mytcgd/myfiles/releases/download/main/nezha-agentv1_arm" -o /home/vncuser/npm
        fi
        chmod +x /home/vncuser/npm
        if [[ " ${tlsPorts[@]} " =~ " ${NEZHA_PORT} " ]]; then
          NEZHA_TLS="true"
        else
          NEZHA_TLS="false"
        fi
        cat > config.yml << ABC
client_secret: $NEZHA_KEY
debug: false
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: false
ip_report_period: 1800
report_delay: 4
server: $NEZHA_SERVER:$NEZHA_PORT
skip_connection_count: true
skip_procs_count: true
temperature: false
tls: $NEZHA_TLS
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: $UUID
ABC
        /home/vncuser/npm -c config.yml >/dev/null 2>&1 &
        ;;
    esac
    echo "npm is running"
fi

# 保持容器运行
echo "容器运行中... 按Ctrl+C停止"
echo "手动备份命令: ./start.sh backup"
echo "手动还原命令: ./start.sh restore"
tail -f /dev/null
