# =============================================================================
# Sub2API 一体化镜像：把「应用 + PostgreSQL + Redis」三个组件装进同一个容器
# =============================================================================

ARG POSTGRES_IMAGE=postgres:18-alpine
ARG NODE_IMAGE=node:24-alpine
ARG GOLANG_IMAGE=golang:1.27.2-alpine
ARG SUB2API_REPO=https://github.com/Wei-Shaw/sub2api
# 上游版本由 workflow 按「最新正式 release」传入；此默认值仅用于手动构建
ARG SUB2API_REF=v0.2.17
ARG GOPROXY=https://goproxy.cn,direct
ARG GOSUMDB=sum.golang.google.cn

# --- 0. 拉取上游源码并打补丁 -------------------------------------------------
FROM ${GOLANG_IMAGE} AS src
ARG SUB2API_REPO
ARG SUB2API_REF
RUN apk add --no-cache git
WORKDIR /src
RUN git clone ${SUB2API_REPO} . && git checkout ${SUB2API_REF}
COPY patches/ /patches/
RUN git apply /patches/memory-metric.patch

# --- 1. 前端构建 -------------------------------------------------------------
FROM ${NODE_IMAGE} AS frontend-builder
COPY --from=src /src /src
WORKDIR /src/frontend
RUN corepack enable && corepack prepare pnpm@9 --activate \
 && pnpm install --frozen-lockfile --prefer-offline \
 && pnpm run build

# --- 2. 后端构建（嵌入前端 dist） --------------------------------------------
FROM src AS backend-builder
ARG GOPROXY
ARG GOSUMDB
ARG VERSION=unknown
ENV GOPROXY=${GOPROXY} GOSUMDB=${GOSUMDB}
COPY --from=frontend-builder /src/backend/internal/web/dist /src/backend/internal/web/dist
WORKDIR /src/backend
RUN go mod download \
 && CGO_ENABLED=0 go build -tags embed -trimpath \
      -ldflags "-s -w -X main.Version=${VERSION} -X main.Commit=custom -X main.Date=$(date -u +%Y-%m-%dT%H:%M:%SZ) -X main.BuildType=release" \
      -o /out/sub2api ./cmd/server

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

COPY --from=backend-builder --chown=sub2api:sub2api /out/sub2api /app/sub2api
COPY --from=backend-builder --chown=sub2api:sub2api /src/backend/resources /app/resources
COPY --from=backend-builder /src/deploy/docker-entrypoint.sh /app/docker-entrypoint.sh
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
