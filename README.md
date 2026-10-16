# my-sub2api

Sub2API 的一体化镜像：应用 + PostgreSQL + Redis 打包在同一个容器内。

## 组件

| 组件 | 来源 |
|---|---|
| 应用 | `weishaw/sub2api:latest` |
| PostgreSQL | `postgres:18-alpine`（同时作为镜像底座） |
| Redis | `apk add redis`（与底座同一 alpine release） |

## 环境变量

| 变量 | 说明 |
|---|---|
| `POSTGRES_PASSWORD` | 必填，内置 PostgreSQL 的密码 |
| `POSTGRES_USER` / `POSTGRES_DB` | 默认 `sub2api` / `sub2api` |
| `DATABASE_PASSWORD` | 应用连接数据库用，须与 `POSTGRES_PASSWORD` 一致 |
| `REDIS_PASSWORD` | 必填，内置 Redis 的密码 |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | 首次启动自动创建的管理员（仅首次生效） |
| `JWT_SECRET` / `TOTP_ENCRYPTION_KEY` | 固定值，否则重启后登录态 / 已有 2FA 失效 |
| `SERVER_PORT` | 容器内监听端口，默认 8080 |
| `PG_MAX_CONNECTIONS` / `PG_SHARED_BUFFERS` / `PG_EFFECTIVE_CACHE_SIZE` / `PG_MAINTENANCE_WORK_MEM` / `PG_WORK_MEM` | PostgreSQL 调参 |
| `REDIS_MAXMEMORY` | 默认 `128mb` |

数据库与 Redis 只监听容器内 `127.0.0.1`，只需发布应用端口。

## 挂载点

| 容器内 | 说明 |
|---|---|
| `/app/data` | 应用数据（配置、日志、上传、安装锁、价格缓存） |
| `/var/lib/postgresql/data` | PostgreSQL 数据（`PGDATA` 固定为此路径） |
| `/data` | Redis 数据（AOF） |

## 运行

```bash
docker run -d --name sub2api \
  --restart unless-stopped \
  -p 8891:8080 \
  -e POSTGRES_PASSWORD=... \
  -e DATABASE_PASSWORD=... \
  -e REDIS_PASSWORD=... \
  -e ADMIN_EMAIL=... -e ADMIN_PASSWORD=... \
  -e JWT_SECRET=... -e TOTP_ENCRYPTION_KEY=... \
  -v /path/to/data:/app/data \
  -v /path/to/pgdata:/var/lib/postgresql/data \
  -v /path/to/redisdata:/data \
  <IMAGE>
```
