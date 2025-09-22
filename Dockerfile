FROM alpine:latest

# 安装软件包
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
        rsync

# 创建用户
RUN adduser -D -s /bin/bash vncuser

# 复制启动脚本
COPY start.sh /home/vncuser/start.sh
RUN chmod +x /home/vncuser/start.sh

EXPOSE 8080

USER vncuser
WORKDIR /home/vncuser

CMD ["./start.sh"]
