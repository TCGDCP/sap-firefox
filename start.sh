#!/bin/bash

# 配置变量
VNC_PASSWORD=${VNC_PASSWORD:-"password"}
RESOLUTION=${RESOLUTION:-"1280x800"}
GBACKUP_USER=${GBACKUP_USER:-""}
GBACKUP_REPO=${GBACKUP_REPO:-""}
GBACKUP_TOKEN=${GBACKUP_TOKEN:-""}
BACKUP_DIR="/home/vncuser/firefox-backup"
AUTO_BACKUP=${AUTO_BACKUP:-"NO"}
AUTO_RESTORE=${AUTO_RESTORE:-"NO"}

# 默认端口（Cloud Foundry 提供时使用 $PORT，否则默认 8080）
PORT=${PORT:-"8080"}

# 解析分辨率
IFS='x' read -ra RES <<< "$RESOLUTION"
VNC_WIDTH="${RES[0]}"
VNC_HEIGHT="${RES[1]}"
VNC_DEPTH="24"

# 计算Firefox窗口大小（全屏）
FIREFOX_WIDTH=$VNC_WIDTH
FIREFOX_HEIGHT=$VNC_HEIGHT

# 创建Firefox配置文件
mkdir -p ~/.mozilla/firefox

# GitHub备份/还原功能
backup_restore_firefox() {
    local action=$1

    # 检查GitHub配置是否完整
    if [ -z "$GBACKUP_USER" ] || [ -z "$GBACKUP_REPO" ] || [ -z "$GBACKUP_TOKEN" ]; then
        echo "⚠ GitHub配置不完整，跳过备份/还原"
        echo "  需要设置: GBACKUP_USER, GBACKUP_REPO, GBACKUP_TOKEN"
        return 0
    fi

    local repo_url="https://${GBACKUP_TOKEN}@github.com/${GBACKUP_USER}/${GBACKUP_REPO}.git"
    local profile_dir="$HOME/.mozilla/firefox"

    case $action in
        "backup")
            echo "开始备份Firefox配置到GitHub..."
            echo "仓库: ${GBACKUP_USER}/${GBACKUP_REPO}"

            if [ -d "$profile_dir" ]; then
                # 创建备份目录
                mkdir -p "$BACKUP_DIR/firefox-profile"

                # 复制配置文件到备份目录
                rsync -av --delete --exclude='Cache' --exclude='cache2' --exclude='thumbnails' \
                    "$profile_dir/" "$BACKUP_DIR/firefox-profile/" >/dev/null 2>&1

                # 添加备份信息文件
                echo "备份时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$BACKUP_DIR/README.md"
                echo "容器ID: $(hostname)" >> "$BACKUP_DIR/README.md"
                echo "GitHub仓库: ${GBACKUP_USER}/${GBACKUP_REPO}" >> "$BACKUP_DIR/README.md"
                echo "分辨率: ${RESOLUTION}" >> "$BACKUP_DIR/README.md"

                # 进入备份目录操作
                cd "$BACKUP_DIR"

                # 初始化Git仓库（如果不存在）
                if [ ! -d ".git" ]; then
                    echo "初始化Git仓库..."
                    git init >/dev/null
                    # 设置Git用户信息
                    git config user.email "firefox-backup@docker.container"
                    git config user.name "Firefox Backup Bot"
                    # 设置默认分支为main
                    git config init.defaultBranch main

                    # 创建初始提交
                    if ! git add . >/dev/null 2>&1; then
                        echo "❌ git add 失败"
                        return 1
                    fi
                    git commit -m "初始提交: 创建备份仓库 $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1

                    # 添加远程仓库
                    git remote add origin "$repo_url" >/dev/null 2>&1
                    echo "✅ 本地Git仓库初始化完成"
                else
                    # 确保用户信息正确设置
                    git config user.email "firefox-backup@docker.container"
                    git config user.name "Firefox Backup Bot"
                fi

                # 设置远程仓库URL
                git remote set-url origin "$repo_url"

                # 获取当前分支名称
                CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

                # 提交更改
                echo "提交更改到GitHub..."
                if ! git add . >/dev/null 2>&1; then
                    echo "❌ git add 失败"
                    return 1
                fi

                # 检查是否有更改需要提交
                if ! git diff --staged --quiet; then
                    if git commit -m "Firefox备份 $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1; then
                        echo "✅ 提交创建成功"
                    else
                        echo "❌ 提交创建失败"
                        return 1
                    fi

                    # 尝试推送，处理不同的分支名称情况
                    echo "推送更改到远程仓库..."
                    if git push -u origin "$CURRENT_BRANCH"; then
                        echo "✅ 备份成功推送到 ${GBACKUP_USER}/${GBACKUP_REPO} (分支: $CURRENT_BRANCH)"
                    else
                        echo "⚠ 推送失败，尝试强制推送..."
                        if git push -f origin "$CURRENT_BRANCH"; then
                            echo "✅ 强制推送完成"
                        else
                            echo "❌ 强制推送也失败，请检查："
                            echo "   - GitHub Token 权限"
                            echo "   - 仓库是否存在: ${GBACKUP_USER}/${GBACKUP_REPO}"
                            echo "   - 网络连接"
                            # 显示前几行错误信息
                            git push -f origin "$CURRENT_BRANCH" 2>&1 | head -3
                        fi
                    fi

                    echo "📦 备份大小: $(du -sh firefox-profile | cut -f1)"
                else
                    echo "⚠ 没有检测到文件更改，跳过提交"
                fi

                # 返回原目录
                rm -rf "$BACKUP_DIR"
                cd - > /dev/null

            else
                echo "⚠ Firefox配置文件目录不存在，跳过备份"
            fi
            ;;
        "restore")
            echo "尝试从GitHub恢复Firefox配置..."
            echo "仓库: ${GBACKUP_USER}/${GBACKUP_REPO}"
            echo "分支: main"

            # 清理现有备份目录
            rm -rf "$BACKUP_DIR"
            mkdir -p "$BACKUP_DIR"

            # 进入备份目录
            cd "$BACKUP_DIR"

            # 尝试克隆仓库，明确指定main分支
            echo "从GitHub main分支下载备份..."
            if git clone -b main --single-branch "$repo_url" . 2>/dev/null; then
                echo "✅ 成功从main分支克隆仓库"
            else
                # 如果克隆失败，尝试其他方法
                echo "⚠ 从main分支克隆失败，尝试其他方法..."
                git init >/dev/null
                git config user.email "firefox-backup@docker.container"
                git config user.name "Firefox Backup Bot"
                git remote add origin "$repo_url"

                # 只获取main分支
                git fetch origin main >/dev/null 2>&1

                # 检查main分支是否存在
                if git show-ref --verify --quiet refs/remotes/origin/main; then
                    git checkout -b main origin/main
                    echo "✅ 成功切换到main分支"
                else
                    echo "❌ 从main分支克隆失败，可能的原因："
                    echo "   - 仓库不存在: ${GBACKUP_USER}/${GBACKUP_REPO}"
                    echo "   - Token无效或没有权限"
                    echo "   - main分支不存在"
                    echo "   - 网络连接问题"
                    cd - > /dev/null
                    return 1
                fi
            fi

            # 返回原目录
            cd - > /dev/null

            if [ -d "$BACKUP_DIR/firefox-profile" ]; then
                rm -rf "$profile_dir"

                # 恢复配置
                mkdir -p "$(dirname "$profile_dir")"
                rsync -av "$BACKUP_DIR/firefox-profile/" "$profile_dir/" >/dev/null 2>&1

                # 设置正确的权限
                chown -R vncuser:vncuser "$profile_dir" 2>/dev/null || true

                echo "✅ Firefox配置已从GitHub main分支恢复"
                if [ -f "$BACKUP_DIR/backup-info.txt" ]; then
                    echo "📅 备份信息:"
                    cat "$BACKUP_DIR/backup-info.txt"
                fi
            else
                echo "⚠ 没有找到可恢复的备份文件，将使用全新配置"
            fi
            ;;
        *)
            echo "❌ 未知操作: $action"
            echo "可用操作: backup, restore"
            return 1
            ;;
    esac
}

# 如果提供了参数，执行相应操作后退出
case "${1:-}" in
    "backup")
        backup_restore_firefox "backup"
        exit 0
        ;;
    "restore")
        backup_restore_firefox "restore"
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
echo "📊 设置分辨率: ${RESOLUTION}"

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
case "$AUTO_RESTORE" in
  "YES" )
    if [ -n "$GBACKUP_USER" ] && [ -n "$GBACKUP_REPO" ] && [ -n "$GBACKUP_TOKEN" ]; then
      backup_restore_firefox "restore"
    fi
    ;;
  "NO" )
    echo "⏰ 不执行自动还原... 如需启用自动还原，请设置环境变量: AUTO_RESTORE=YES"
    ;;
esac

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
echo "启动Firefox (${FIREFOX_WIDTH}x${FIREFOX_HEIGHT})..."
firefox --no-remote --width=$FIREFOX_WIDTH --height=$FIREFOX_HEIGHT > /tmp/firefox.log 2>&1 &

# 等待Firefox启动
echo "等待Firefox启动..."
sleep 8

# 检查Firefox是否正常运行
if ! ps aux | grep firefox | grep -v grep > /dev/null; then
    echo "⚠ Firefox启动失败，尝试重新启动..."
    firefox --no-remote --width=$FIREFOX_WIDTH --height=$FIREFOX_HEIGHT > /tmp/firefox.log 2>&1 &
    sleep 5
fi

# 启动VNC服务器
echo "启动VNC服务器..."
x11vnc -display :0 \
    -forever \
    -shared \
    -passwd "$VNC_PASSWORD" \
    -rfbport 5900 \
    -noxdamage \
    -repeat \
    -listen 0.0.0.0 \
    -geometry ${RESOLUTION} \
    -pointer_mode 1 \
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

SERVER_IP=$(curl -s https://speed.cloudflare.com/meta | tr ',' '\n' | grep -E '"clientIp"\s*:\s*"' | sed 's/.*"clientIp"\s*:\s*"\([^"]*\)".*/\1/')
if [[ "${SERVER_IP}" =~ : ]]; then
    IP="[${SERVER_IP}]"
else
    IP="${SERVER_IP}"
fi
echo "🌐 服务器ip地址: $IP"

# 输出连接信息
echo "========================================"
echo "✅ VNC服务已启动！"
echo "🔑 VNC密码: $VNC_PASSWORD"
echo "🌐 访问地址: http://${IP}:${PORT}/vnc.html"
echo "📊 分辨率: $RESOLUTION"
if [ -n "$GBACKUP_USER" ] && [ -n "$GBACKUP_REPO" ]; then
    echo "🔧 GitHub备份: ${GBACKUP_USER}/${GBACKUP_REPO}"
else
    echo "🔧 GitHub备份: 未配置"
fi
echo "========================================"

# 检查进程状态
echo "检查进程状态:"
ps aux | grep -E '(Xvfb|firefox|x11vnc|websockify)' | grep -v grep

# 设置定时备份（每30分钟备份一次）
case "$AUTO_BACKUP" in
  "YES" )
    echo "⏰ 每30分钟自动定时备份已经激活..."
    while true; do
      sleep 1800  # 30分钟
      echo "⏰ 执行定时备份..."
      backup_restore_firefox "backup"
    done &
    ;;
  "NO" )
    echo "⏰ 不执行定时备份... 如需启用定时备份，请设置环境变量: AUTO_BACKUP=YES"
    ;;
esac

# 保持容器运行
echo "容器运行中... 按Ctrl+C停止"
echo "手动备份命令: ./start.sh backup"
echo "手动还原命令: ./start.sh restore"
tail -f /dev/null
