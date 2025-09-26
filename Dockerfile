FROM alpine:latest

# 安装所有必要的软件包
RUN apk update && \
    apk add --no-cache \
        tzdata \
        curl \
        supervisor \
        xvfb \
        x11vnc \
        fluxbox \
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
    # 设置VNC主页
    cp /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
    # 创建非特权用户
    adduser -D -s /bin/bash vncuser && \
    # 设置firefox持久化目录
    mkdir -p /home/vncuser/.mozilla/firefox && \
    chown -R vncuser:vncuser /home/vncuser/.mozilla/firefox && \
    # 创建/config符号链接，指向Firefox配置目录
    ln -sf /home/vncuser/.mozilla/firefox /config

# 复制启动脚本并设置权限
COPY start.sh /home/vncuser/start.sh
RUN chmod +x /home/vncuser/start.sh && \
    chown -R vncuser:vncuser /home/vncuser/

# 声明暴露的端口
EXPOSE 8080 5900

# 切换到非 root 用户
USER vncuser
WORKDIR /home/vncuser

# 设置默认启动命令
CMD ["./start.sh"]
