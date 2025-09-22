FROM alpine:latest

# 安装最小必要的软件包
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
    # 创建非特权用户
    adduser -D -s /bin/bash vncuser

# 切换到用户目录准备文件
USER vncuser
WORKDIR /home/vncuser

# 下载启动脚本
RUN curl -sSL https://raw.githubusercontent.com/TCGDCP/sap-firefox/main/start.sh -o start.sh && \
    chmod +x start.sh

# 声明暴露的端口
EXPOSE 8080

# 设置默认启动命令
CMD ["./start.sh"]
