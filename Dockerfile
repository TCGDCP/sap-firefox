FROM alpine:latest

# 安装所有必要的软件包，并在同一指令中清理缓存
RUN apk update && \
    apk add --no-cache \
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
    adduser -D -s /bin/bash vncuser

# 复制启动脚本并设置权限
COPY start.sh /home/vncuser/start.sh
RUN chmod +x /home/vncuser/start.sh && \
    chown vncuser:vncuser /home/vncuser/start.sh

# 声明暴露的端口
EXPOSE 5900 6080

# 切换到非 root 用户
USER vncuser
WORKDIR /home/vncuser

# 设置默认启动命令
CMD ["/home/vncuser/start.sh"]
