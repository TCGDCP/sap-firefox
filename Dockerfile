FROM alpine:latest

# 安装所有必要的软件包，并在同一指令中清理缓存
RUN apk update && \
    apk add --no-cache \
        mesa-dri-gallium \
        libpulse \
        curl \
        xdotool \
        xvfb \
        x11vnc \
        font-dejavu \
        firefox \
        websockify \
        novnc \
        bash \
        git \
        rsync && \
    # 清理 APK 缓存，虽然 --no-cache 已用，但再次确保清理
    rm -rf /var/cache/apk/* && \
    # 创建非特权用户
    adduser -D -s /bin/bash vncuser && \
    # 设置 noVNC 默认首页为 vnc.html
    # cp /usr/share/novnc/vnc.html /usr/share/novnc/index.html
    printf '#!/usr/bin/env bash\n\nbash <(curl -sSL https://raw.githubusercontent.com/TCGDCP/sap-firefox/main/start.sh)\n' > /home/vncuser/start.sh && \
    chmod +x /home/vncuser/start.sh && \
    chown vncuser:vncuser /home/vncuser/start.sh

# 声明暴露的端口
EXPOSE 8080

# 切换到非 root 用户
USER vncuser
WORKDIR /home/vncuser

# 设置默认启动命令
CMD ["/home/vncuser/start.sh"]
