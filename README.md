# my-sub2api

把 **Sub2API** 的三个组件（应用 + PostgreSQL + Redis）打成**一个**镜像，用与
[`my-smart-sub`](https://github.com/s890214/my-smart-sub) 相同的模式自动构建发布。

| 组件 | 来源 |
|---|---|
| 应用 | `weishaw/sub2api:latest`（上游官方镜像，静态二进制直接拷贝） |
| PostgreSQL | `postgres:18-alpine`（同时作为镜像底座） |
| Redis | 底座内 `apk add redis`（同一 alpine release，依赖自洽） |

产物：`song88zzz/my-sub2api:latest` 与 `song88zzz/my-sub2api:v<年月日.时分秒>`

## 自动化

`.github/workflows/docker-build.yml`：

- **push / 手动触发**：构建并推送
- **每天 03:00（UTC）定时**：比对三个上游镜像的 digest，**有变化才重建**
- 版本号 = `date -u +%Y%m%d.%H%M%S`，构建时写入镜像内 `/app/VERSION`
- 构建后把 `VERSION` 与 `.last-base-digest`（三个上游 digest 的排序拼接）回写仓库

## 必需的仓库 secrets

和 `my-smart-sub` 一样，需要在 **Settings → Secrets and variables → Actions** 里配置：

| Name | 值 |
|---|---|
| `DOCKERHUB_USERNAME` | `song88zzz` |
| `DOCKERHUB_TOKEN` | Docker Hub 的 Access Token |

也可以命令行：

```bash
gh secret set DOCKERHUB_USERNAME -R s890214/my-sub2api   # 交互输入 song88zzz
gh secret set DOCKERHUB_TOKEN    -R s890214/my-sub2api   # 交互粘贴 token
```

## 运行时需要的环境变量

| 变量 | 说明 |
|---|---|
| `POSTGRES_PASSWORD` | **必填**，内部 PostgreSQL 的密码 |
| `POSTGRES_USER` / `POSTGRES_DB` | 默认 `sub2api` / `sub2api` |
| `REDIS_PASSWORD` | **必填**，内部 Redis 的密码 |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | 首次启动自动创建的管理员（仅首次生效） |
| `JWT_SECRET` / `TOTP_ENCRYPTION_KEY` | 建议固定，否则重启后登录态 / 已有 2FA 失效 |
| `SERVER_PORT` | 容器内监听端口，默认 8080 |
| `PG_MAX_CONNECTIONS` / `PG_SHARED_BUFFERS` / `PG_EFFECTIVE_CACHE_SIZE` / `PG_MAINTENANCE_WORK_MEM` / `PG_WORK_MEM` | PostgreSQL 调参 |
| `REDIS_MAXMEMORY` | 默认 `128mb` |

数据库与 Redis 只监听 `127.0.0.1`，仅容器内可达；**只需发布应用端口**。

## 挂载点

| 容器内 | 说明 |
|---|---|
| `/app/data` | 应用数据（配置、日志、上传、安装锁、价格缓存） |
| `/var/lib/postgresql/data` | PostgreSQL 数据（`PGDATA` 已固定为此路径） |
| `/data` | Redis 数据（AOF） |

## 运行示例

```bash
docker run -d --name sub2api \
  --restart unless-stopped \
  --memory 512m \
  -p 8891:8080 \
  -e POSTGRES_PASSWORD=... \
  -e REDIS_PASSWORD=... \
  -e ADMIN_EMAIL=... -e ADMIN_PASSWORD=... \
  -e JWT_SECRET=... -e TOTP_ENCRYPTION_KEY=... \
  -v /mnt/user/appdata/sub2api:/app/data \
  -v /mnt/user/appdata/sub2api-postgres:/var/lib/postgresql/data \
  -v /mnt/user/appdata/sub2api-redis:/data \
  song88zzz/my-sub2api:latest
```

实测空闲内存占用约 `65MB / 512MB`（PG + Redis + 应用合计，未含 PostgreSQL 缓存页逐步增长）。

## 说明

- 镜像**不是** Sub2API 的 fork，只做打包；上游：<https://github.com/Wei-Shaw/sub2api>
- 底座之所以选 `postgres:18-alpine` 而不是应用镜像：三个上游镜像的 alpine 版本互不相同
  （3.24 / 3.23 / 3.21），跨镜像拷 PostgreSQL 二进制会撞 ICU 78 / libxml2 版本错配；
  以 postgres 为底座、Redis 走 apk，依赖全部由包管理器保证自洽。
- 应用按相对路径 `data/...` 读写数据，因此镜像里固定了 `WORKDIR /app`。
