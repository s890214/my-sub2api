#!/bin/sh
# =============================================================================
# Sub2API 一体化启动器：在一个容器内按顺序拉起 PostgreSQL -> Redis -> Sub2API
# 任一依赖退出则整体退出，交给 Docker 的重启策略
# =============================================================================
set -eu

log() { printf '[allinone] %s\n' "$*"; }

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
export PGDATA

mkdir -p "$PGDATA" /run/postgresql
chown -R postgres:postgres "$PGDATA" /run/postgresql 2>/dev/null || true

# ---------------------------------------------------------------- PostgreSQL
log "启动 PostgreSQL..."
# 官方入口脚本要求以 root 运行，它会自己 gosu 降权到 postgres；已初始化的数据
# 目录会被自动识别并跳过 initdb。
/usr/local/bin/docker-entrypoint.sh postgres \
  -c "max_connections=${PG_MAX_CONNECTIONS:-60}" \
  -c "shared_buffers=${PG_SHARED_BUFFERS:-64MB}" \
  -c "effective_cache_size=${PG_EFFECTIVE_CACHE_SIZE:-256MB}" \
  -c "maintenance_work_mem=${PG_MAINTENANCE_WORK_MEM:-32MB}" \
  -c "work_mem=${PG_WORK_MEM:-4MB}" \
  -c "listen_addresses=127.0.0.1" &
PG_PID=$!

log "等待 PostgreSQL 就绪..."
n=0
until pg_isready -h 127.0.0.1 -p 5432 -U "${POSTGRES_USER:-sub2api}" -q; do
  n=$((n + 1))
  [ "$n" -ge 90 ] && { log "PostgreSQL 启动超时"; exit 1; }
  kill -0 "$PG_PID" 2>/dev/null || { log "PostgreSQL 进程已退出"; exit 1; }
  sleep 1
done
log "PostgreSQL 就绪"

# --------------------------------------------------------------------- Redis
log "启动 Redis..."
mkdir -p /data
redis-server --dir /data --bind 127.0.0.1 --protected-mode no \
  --save 60 1 --appendonly yes --appendfsync everysec \
  --requirepass "${REDIS_PASSWORD}" \
  --maxmemory "${REDIS_MAXMEMORY:-128mb}" --maxmemory-policy noeviction &
REDIS_PID=$!

n=0
until redis-cli -h 127.0.0.1 -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning ping 2>/dev/null | grep -q PONG; do
  n=$((n + 1))
  [ "$n" -ge 30 ] && { log "Redis 启动超时"; exit 1; }
  kill -0 "$REDIS_PID" 2>/dev/null || { log "Redis 进程已退出"; exit 1; }
  sleep 1
done
log "Redis 就绪"

# ------------------------------------------------------------------- Sub2API
log "启动 Sub2API..."
/app/docker-entrypoint.sh /app/sub2api &
APP_PID=$!

while kill -0 "$APP_PID" 2>/dev/null; do
  if ! kill -0 "$PG_PID" 2>/dev/null; then
    log "PostgreSQL 已退出，停容器"
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$REDIS_PID" 2>/dev/null; then
    log "Redis 已退出，停容器"
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 10
done

wait "$APP_PID"
