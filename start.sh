#!/bin/bash

# 配置变量
export PORT=${PORT:-"8080"}
export VNC_PASSWORD=${VNC_PASSWORD:-"password"}
export RESOLUTION=${RESOLUTION:-"720x1280"}
export GBACKUP_USER=${GBACKUP_USER:-""}
export GBACKUP_REPO=${GBACKUP_REPO:-""}
export GBACKUP_TOKEN=${GBACKUP_TOKEN:-""}
export FIREFOX_DIR="/config"
export BACKUP_DIR="/home/vncuser/firefox-backup"
export AUTO_BACKUP=${AUTO_BACKUP:-"NO"}
export AUTO_RESTORE=${AUTO_RESTORE:-"NO"}
export INTERVAL_IN_SECONDS=${INTERVAL_IN_SECONDS:-"1800"} # 单位为秒,默认30分钟

export UUID=${UUID:-''} # V1需要
export NEZHA_VERSION=${NEZHA_VERSION:-'V1'} # V0 OR V1
export NEZHA_SERVER=${NEZHA_SERVER:-''} # 不填不启用哪吒
export NEZHA_KEY=${NEZHA_KEY:-''} # 不填不启用哪吒
export NEZHA_PORT=${NEZHA_PORT:-'443'}

# 确保配置目录存在并有写权限 设置符号链接及备份还原设置
if [[ -d "$FIREFOX_DIR" ]] && [[ -w "$FIREFOX_DIR" ]]; then
    rm -rf /home/vncuser/.mozilla/firefox 2>/dev/null || true
    ln -sf "$FIREFOX_DIR" /home/vncuser/.mozilla/firefox 2>/dev/null || true
fi
if [[ -n "$GBACKUP_USER" ]] && [[ -n "$GBACKUP_REPO" ]] && [[ -n "$GBACKUP_TOKEN" ]]; then
   export REPO_URL="https://${GBACKUP_TOKEN}@github.com/${GBACKUP_USER}/${GBACKUP_REPO}.git"
else
   export REPO_URL=""
fi

# 解析分辨率
IFS='x' read -ra RES <<< "$RESOLUTION"
VNC_WIDTH="${RES[0]}"
VNC_HEIGHT="${RES[1]}"
VNC_DEPTH="24"

# 计算Firefox窗口大小（全屏）
FIREFOX_WIDTH=$VNC_WIDTH
FIREFOX_HEIGHT=$VNC_HEIGHT

# Firefox 备份
backup_firefox() {
    [[ -z "$REPO_URL" ]] && { echo "❌ 未配置GitHub仓库"; return 0; }

    echo "开始备份Firefox配置到GitHub..."
    echo "仓库: ${GBACKUP_USER}/${GBACKUP_REPO}"

    if [ ! -d "$FIREFOX_DIR" ]; then
        echo "⚠ Firefox配置文件目录不存在，跳过备份"
        return 0
    fi

    # 创建备份目录
    mkdir -p "$BACKUP_DIR/firefox-profile"
    echo "备份时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$BACKUP_DIR/README.md"

    # 复制配置文件到备份目录
    rsync -av --no-t --delete --exclude='Cache' --exclude='cache2' --exclude='thumbnails' \
        "$FIREFOX_DIR" "$BACKUP_DIR/firefox-profile/" >/dev/null 2>&1

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
    git remote add origin "$REPO_URL"

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
    [[ -z "$REPO_URL" ]] && { echo "❌ 未配置GitHub仓库"; return 0; }
    echo "尝试从GitHub恢复Firefox配置..."

    # 清理现有备份目录
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # 进入备份目录
    cd "$BACKUP_DIR"

    # 尝试克隆仓库，明确指定main分支
    echo "从GitHub main分支下载备份..."
    if git clone -b main --single-branch "$REPO_URL" . 2>/dev/null; then
        echo "✅ 成功从main分支克隆仓库"
    fi

    if [ -d "$BACKUP_DIR/firefox-profile" ]; then
        rm -rf "$FIREFOX_DIR"/*

        # 恢复配置
        rsync -av "$BACKUP_DIR/firefox-profile/" /config >/dev/null 2>&1

        # 设置正确的权限
        chown -R vncuser:vncuser "$FIREFOX_DIR" 2>/dev/null || true

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

# 启动前尝试恢复配置
if [[ "$AUTO_RESTORE" == "YES" ]]; then
    restore_firefox
    sleep 10
else
   ⏰ 不执行自动恢复... 如需启用恢复，请设置环境变量: AUTO_RESTORE=YES
fi

echo "🚀 启动Firefox VNC服务..."

# 创建必要的目录
mkdir -p /home/vncuser/.vnc
mkdir -p "$BACKUP_DIR"
chmod 700 /home/vncuser/.vnc

# 设置VNC密码
echo "$VNC_PASSWORD" | x11vnc -storepasswd - > /home/vncuser/.vnc/passwd
chmod 600 /home/vncuser/.vnc/passwd

# 清理旧的锁文件
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

# 创建X11相关目录并设置权限
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
chown vncuser:vncuser /tmp/.X11-unix

# 设置临时目录权限
mkdir -p /home/vncuser/tmp
chmod 700 /home/vncuser/tmp

# 设置TMPDIR环境变量
export TMPDIR=/home/vncuser/tmp

# 在用户目录创建最小化Fluxbox配置
mkdir -p /home/vncuser/.fluxbox
cat > /home/vncuser/.fluxbox/init << EOF
session.screen0.workspaces: 1
session.screen0.workspacewarping: false
session.screen0.toolbar.visible: false
session.screen0.fullMaximization: true
session.screen0.maxDisableMove: false
session.screen0.maxDisableResize: false
session.screen0.defaultDeco: NONE
EOF
chown -R vncuser:vncuser /home/vncuser/.fluxbox

# 在用户目录创建supervisor配置
SUPERVISOR_CONFIG_DIR="/home/vncuser/.supervisor"
mkdir -p "$SUPERVISOR_CONFIG_DIR"

# 创建主supervisor配置文件
cat > "$SUPERVISOR_CONFIG_DIR/supervisord.conf" << EOF
[unix_http_server]
file=$SUPERVISOR_CONFIG_DIR/supervisor.sock

[supervisord]
logfile=$SUPERVISOR_CONFIG_DIR/supervisord.log
pidfile=$SUPERVISOR_CONFIG_DIR/supervisord.pid
nodaemon=true
user=vncuser

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix://$SUPERVISOR_CONFIG_DIR/supervisor.sock

[include]
files = $SUPERVISOR_CONFIG_DIR/conf.d/*.ini
EOF

# 创建配置目录
mkdir -p "$SUPERVISOR_CONFIG_DIR/conf.d"

# 创建应用配置文件
cat > "$SUPERVISOR_CONFIG_DIR/conf.d/firefox-vnc.ini" << EOF
[program:xvfb]
command=Xvfb :0 -screen 0 ${VNC_WIDTH}x${VNC_HEIGHT}x${VNC_DEPTH} +extension RANDR -nolisten tcp -noreset -ac
autorestart=true
priority=100
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=DISPLAY=":0",HOME="/home/vncuser",USER="vncuser"

[program:fluxbox]
command=bash -c 'sleep 3 && fluxbox -display :0'
autorestart=true
priority=150
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=DISPLAY=":0",HOME="/home/vncuser",USER="vncuser"

[program:firefox]
command=bash -c 'sleep 8 && firefox --profile "$FIREFOX_DIR" --width=${VNC_WIDTH} --height=${VNC_HEIGHT}'
autorestart=false
priority=200
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=DISPLAY=":0",HOME="/home/vncuser",USER="vncuser"

[program:x11vnc]
command=bash -c 'sleep 12 && x11vnc -display :0 -forever -shared -passwd "$VNC_PASSWORD" -rfbport 5900 -noxdamage'
autorestart=true
priority=300
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=DISPLAY=":0",HOME="/home/vncuser",USER="vncuser"

[program:novnc]
command=bash -c 'sleep 15 && if [ -d "/usr/share/novnc" ]; then websockify --web /usr/share/novnc '"$PORT"' localhost:5900; else websockify '"$PORT"' localhost:5900; fi'
autorestart=true
priority=400
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=HOME="/home/vncuser",USER="vncuser"
EOF

# npm配置
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

        cat >> "$SUPERVISOR_CONFIG_DIR/conf.d/firefox-vnc.ini" << EOF

[program:nezha]
command=/home/vncuser/npm -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} --report-delay=4 --skip-conn --skip-procs --disable-auto-update
autorestart=true
priority=500
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
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

        cat > /home/vncuser/config.yml << EOF
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
EOF

        cat >> "$SUPERVISOR_CONFIG_DIR/conf.d/firefox-vnc.ini" << EOF

[program:nezha]
command=/home/vncuser/npm -c /home/vncuser/config.yml
autorestart=true
priority=500
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
        ;;
    esac
    echo "npm已配置"
fi

# 定时备份配置
if [[ "$AUTO_BACKUP" == "YES" ]]; then
    INTERVAL_IN_MINUTES=$((INTERVAL_IN_SECONDS / 60))
    echo "⏰ 每 $INTERVAL_IN_MINUTES 分钟自动定时备份已经激活..."

    cat >> "$SUPERVISOR_CONFIG_DIR/conf.d/firefox-vnc.ini" << EOF

[program:backup]
command=bash -c 'sleep 20 && while true; do sleep $INTERVAL_IN_SECONDS; /home/vncuser/start.sh backup; done'
autorestart=true
priority=600
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
else
    echo "⏰ 不执行定时备份... 如需启用定时备份，请设置环境变量: AUTO_BACKUP=YES"
fi

# 启动supervisor
echo "启动supervisor管理所有服务..."
exec supervisord -c "$SUPERVISOR_CONFIG_DIR/supervisord.conf"
