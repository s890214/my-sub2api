# =============================================================================
# Sub2API 一体化镜像：把「应用 + PostgreSQL + Redis」三个组件装进同一个容器
# 构建/发布方式与 my-smart-sub 一致（GitHub Actions 自动构建并推送到 Docker Hub）
# =============================================================================

ARG POSTGRES_IMAGE=postgres:18-alpine
ARG APP_IMAGE=weishaw/sub2api:latest

# --- 组件 1：应用本体（官方镜像，CGO_ENABLED=0 静态二进制，直接拷贝） --------
FROM ${APP_IMAGE} AS appsrc

# --- 组件 2/3 的底座：postgres 官方镜像 -------------------------------------
# 选它是因为它本身就是完整的 alpine，且已含 PostgreSQL 服务端与全部运行时依赖；
# Redis 用 apk 装（同一 alpine release，依赖由包管理器自洽解决，避免跨镜像拷
# 二进制的 ICU/OpenSSL 版本错配）。
FROM ${POSTGRES_IMAGE}

ARG VERSION=unknown

RUN set -eux; \
    apk add --no-cache redis su-exec tzdata ca-certificates; \
    mkdir -p /app/data /var/lib/postgresql/data /run/postgresql /data; \
    addgroup -g 1000 sub2api; \
    adduser -u 1000 -D -H -G sub2api -s /bin/sh sub2api; \
    chown -R sub2api:sub2api /app; \
    chown -R postgres:postgres /var/lib/postgresql /run/postgresql

COPY --from=appsrc --chown=sub2api:sub2api /app/sub2api   /app/sub2api
COPY --from=appsrc --chown=sub2api:sub2api /app/resources /app/resources
COPY --from=appsrc                          /app/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

COPY entrypoint.sh /usr/local/bin/allinone-entrypoint.sh
RUN chmod +x /usr/local/bin/allinone-entrypoint.sh \
 && echo "$VERSION" > /app/VERSION

# 关键：应用按相对路径 data/... 读写数据（配置、日志、安装锁、价格缓存），
# cwd 必须是 /app，否则会落到别的目录并报 permission denied。
WORKDIR /app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD wget -q -T 5 -O /dev/null "http://localhost:${SERVER_PORT:-8080}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/allinone-entrypoint.sh"]
