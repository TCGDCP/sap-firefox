FROM alpine:latest

# 安装所有必要的软件包
RUN apk update && \
    apk add --no-cache \
        mesa-dri-gallium \
        libpulse \
        tzdata \
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
    # 设置时区
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    # 创建非特权用户
    adduser -D -s /bin/bash vncuser

# 复制启动脚本并设置权限
COPY start.sh /home/vncuser/start.sh
RUN chmod +x /home/vncuser/start.sh && \
    chown vncuser:vncuser /home/vncuser/start.sh

# 声明暴露的端口
EXPOSE 8080

# 切换到非 root 用户
USER vncuser
WORKDIR /home/vncuser

# 设置默认启动命令
CMD ["./start.sh"]
