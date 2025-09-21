FROM linuxserver/firefox:latest

USER root

# 安装依赖
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

RUN apt-get update && \
    apt-get install -y curl unzip supervisor && \
    rm -rf /var/lib/apt/lists/*

# 下载并安装 sing-box
ENV SINGBOX_VERSION=1.11.11

RUN curl -L -o /tmp/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz && \
    mkdir -p /opt/sing-box && \
    tar -xzf /tmp/sing-box.tar.gz -C /opt/sing-box && \
    mv /opt/sing-box/sing-box-${SINGBOX_VERSION}-linux-amd64/sing-box /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/sing-box.tar.gz /opt/sing-box

# 创建配置目录
RUN mkdir -p /etc/sing-box /var/log/supervisor

# 添加 sing-box 配置文件（你需要在构建目录提供 config.json）
COPY config.json /etc/sing-box/config.json

# 添加 supervisor 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 切换回 abc 用户（linuxserver 默认非 root）
# USER abc

# 启动 supervisord 来管理 sing-box 和 firefox
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
