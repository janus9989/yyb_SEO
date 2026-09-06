# YYB 1.0.5 镜像（linux/amd64）
# 构建上下文 = 发行包解压后的根目录（与 backend/ frontend/ scripts/ 同级）
#
#   bash docker/build.sh
#   或：docker buildx build --platform linux/amd64 --load -t yyb:1.0.5 .
#
# 后端二进制只有 linux/amd64 版本，平台必须钉死，否则在 buildx / Docker Desktop /
# arm64 宿主上会打出架构对不上的镜像。
#
# 基础镜像选 node:22-bookworm-slim：后端二进制是纯 Go 静态编译（无 libc 依赖），
# 同时满足官方教程对脚本运行环境的要求（Node 20+ / Python 3.10+）。
FROM --platform=linux/amd64 node:22-bookworm-slim

ENV TZ=Asia/Shanghai \
    YYB_HOME=/opt/yyb \
    YYB_HOST=0.0.0.0 \
    YYB_PORT=8000 \
    YYB_RESOURCE_ROOT=/opt/yyb/backend/resource \
    YYB_DB_DRIVER=mysql \
    YYB_UPDATE_SERVICE_NAME=yyb

# 1) 系统依赖：nginx 负责静态站点 + 反代 /api/，python3 用于脚本运行环境
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nginx \
        ca-certificates \
        curl \
        procps \
        tzdata \
        python3 \
        python3-pip \
    ; \
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /etc/nginx/sites-enabled/default; \
    mkdir -p /var/cache/nginx /var/log/nginx /run/nginx

# 2) 程序文件
COPY backend/       /opt/yyb/backend/
COPY frontend/dist/ /opt/yyb/frontend/dist/
COPY scripts/       /opt/yyb/scripts/

# 3) nginx 站点配置 + 入口脚本
COPY docker/nginx-yyb.conf      /etc/nginx/conf.d/yyb.conf
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# 4) 权限与运行时目录
RUN set -eux; \
    sed -i 's/\r$//' /opt/yyb/scripts/*.sh /opt/yyb/scripts/yyb-start || true; \
    chmod 755 /usr/local/bin/docker-entrypoint.sh \
              /opt/yyb/backend/yyb-go-linux-amd64 \
              /opt/yyb/backend/yyb-script-samples-linux-amd64; \
    chmod 755 /opt/yyb/scripts/*.sh || true; \
    mkdir -p /opt/yyb/backend/resource/avatars \
             /opt/yyb/backend/resource/db \
             /opt/yyb/backend/resource/qr \
             /opt/yyb/backend/resource/script-artifacts \
             /opt/yyb/backend/resource/static \
             /opt/yyb/backend/resource/templates \
             /opt/yyb/backend/resource/updates/packages \
             /opt/yyb/backend/resource/updates/staging \
             /opt/yyb/backend/resource/updates/backups; \
    nginx -t

# 运行数据（数据库密钥、头像、二维码、脚本产物、升级缓存）落在这里，务必挂卷持久化
VOLUME ["/opt/yyb/backend/resource"]

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
    CMD curl -fsS http://127.0.0.1/api/v1/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
