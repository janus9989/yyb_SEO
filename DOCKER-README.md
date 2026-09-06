# YYB 1.0.5 Docker 部署说明

把 `YYB-BT-Release-1.0.5-linux-amd64.zip` 解压后的目录直接作为构建上下文，打成单容器镜像：
容器内 nginx（`80`）提供前端静态站点并反代 `/api/` 到 Go 后端（`127.0.0.1:8000`）。

## 目录结构

```text
<发行包解压根目录>/
├── backend/                  # Go 后端二进制 + resource/
├── frontend/dist/            # 前端静态资源
├── scripts/                  # 官方脚本 / yyb.env.example
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── .github/workflows/docker-build.yml   # GitHub Actions 构建并推送 GHCR
└── docker/
    ├── nginx-yyb.conf
    ├── docker-entrypoint.sh
    ├── build.sh
    └── .env.example
```

容器内路径固定为 `/opt/yyb`，运行数据（JWT 与加密密钥、头像、二维码、脚本产物、升级缓存）全部在
`/opt/yyb/backend/resource`，已声明为卷，**必须持久化**。

## 1. 构建

**发行包只有 linux/amd64 的后端二进制，因此镜像平台必须钉死为 `linux/amd64`。**
Dockerfile 里已写 `FROM --platform=linux/amd64`，compose 里也加了 `platform: linux/amd64`。

推荐用自带校验和导出的脚本：

```bash
cd <发行包解压根目录>
bash docker/build.sh          # 构建 + 加载到 docker images + 导出 yyb-1.0.5-amd64.tar.gz
SAVE=0 bash docker/build.sh   # 只构建
```

等价的手工命令：

```bash
# 新版 Docker（有 buildx）
docker buildx build --platform linux/amd64 --load -t yyb:1.0.5 .
# 老版 Docker
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build -t yyb:1.0.5 .
# 校验
docker image inspect yyb:1.0.5 --format '{{.Architecture}}/{{.Os}}'   # 应输出 amd64/linux
```

拷到别的机器：

```bash
docker save yyb:1.0.5 | gzip > yyb-1.0.5-amd64.tar.gz   # 源机器
docker load -i yyb-1.0.5-amd64.tar.gz                   # 目标机器
```

镜像基于 `node:22-bookworm-slim`，已内置 Node 22 与 Python 3，满足脚本运行环境要求。
后端二进制是纯 Go 静态编译产物，不依赖 libc。

## 2. 在 GitHub 上构建并推送（GitHub Actions + GHCR）

已提供 `.github/workflows/docker-build.yml`，把本目录作为**仓库根目录**推送到 GitHub 即可用。

- 触发方式：推到 `main`/`master`、打 `v*` 标签、发 Release，或在 Actions 页面手动运行（可自定义 tag，默认 `1.0.5`）。
- 产物：推送到 `ghcr.io/<你的用户名>/<仓库名>`，标签含分支名、短 SHA、语义化版本和 `latest`；同时把镜像打成 `yyb-image-amd64.tar.gz` 作为 Artifacts 供下载（保留 7 天）。
- 平台固定 `linux/amd64`，并显式 `provenance: false` / `sbom: false`，避免多出 `unknown/unknown` 清单导致"平台不匹配"。

两种源码来源，任选其一：

1. **直接把发行包提交进仓库**（最简单）：`backend/`、`frontend/dist/`、`scripts/` 一起提交。
   单文件最大 30MB，未超过 GitHub 100MB 硬限制；介意的话用 Git LFS 管理 `backend/*.linux-amd64`。
2. **构建时下载**：仓库 Settings → Secrets and variables → Actions → Variables 新建
   `YYB_RELEASE_ZIP_URL` 指向发行包下载地址，工作流会自动下载解压再构建，仓库本身保持干净。

首次推送后镜像默认是 private，需要在仓库 Packages 页面把包改成 Public，或者先
`docker login ghcr.io -u <用户名>`（密码用有 `read:packages` 权限的 PAT）再拉取：

```bash
# 拉镜像
docker pull ghcr.io/<用户名>/<仓库名>:1.0.5

# 或者下载 Actions 的 Artifacts 后导入
docker load -i yyb-image-amd64.tar.gz
```

## 3. 启动（MySQL 8 + YYB）

```bash
cp docker/.env.example .env   # 修改端口与数据库密码
docker compose up -d
docker compose logs -f yyb
```

首次会自动建库建表。浏览器打开 `http://<宿主机IP>:8080`，空库会进入安装页面，
按提示填写管理员账号与「当前访问域名对应的授权码」（授权按真实请求 Host 绑定）。

## 4. 只用 SQLite（免 MySQL）

后端同时编译了 sqlite 驱动，单机轻量部署可以不启 MySQL：

```bash
docker run -d --name yyb -p 8080:80 \
  -e YYB_DB_DRIVER=sqlite \
  -v yyb-resource:/opt/yyb/backend/resource \
  yyb:1.0.5
```

DSN 留空时自动指向 `/opt/yyb/backend/resource/db/yyb.db`（在卷中，可持久化）。
生产环境仍建议 MySQL。

## 5. 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `YYB_HOST` | `0.0.0.0` | 容器内必须监听全部网卡，nginx 才能反代 |
| `YYB_PORT` | `8000` | 后端端口，nginx 固定转发到 `127.0.0.1:8000` |
| `YYB_RESOURCE_ROOT` | `/opt/yyb/backend/resource` | 运行数据根目录 |
| `YYB_DB_DRIVER` | `mysql` | `mysql` 或 `sqlite` |
| `YYB_DB_DSN` | 空 | MySQL DSN；sqlite 留空自动填库文件路径 |
| `YYB_JWT_SECRET` | 空 | 留空则首次启动生成并存到 `resource/db`，务必随卷备份 |
| `YYB_TCP_PROXY` | 空 | 全局 TCP 代理 |
| `YYB_SCRIPT_ALLOW_ENV` / `YYB_SCRIPT_ALLOW_NETWORK` / `YYB_SCRIPT_MAX_MEMORY_MB` | — | 脚本运行时限制 |

已存在的 `scripts/yyb.env` 可以挂载进容器，但**Docker `environment` 里的值优先级更高**，
未设置的键才会从文件补齐。

## 6. 常用运维

```bash
# 健康接口
curl -i http://127.0.0.1:8080/api/v1/health

# 导入内置脚本样例
docker exec -it yyb bash /opt/yyb/scripts/import-script-samples.sh

# 备份（运行数据 + 数据库）
docker run --rm -v yyb-resource:/data -v "$PWD:/backup" alpine \
  tar -czf /backup/yyb-resource-$(date +%Y%m%d%H%M%S).tar.gz -C /data .
docker exec yyb-mysql mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" yyb > yyb.sql

# 升级镜像
docker compose build --pull && docker compose up -d
```

## 7. 注意事项

- **不要用容器内的「在线升级」功能**：它会替换容器里的后端二进制和 `frontend/dist`，
  容器重建后即丢失。升级请重新构建镜像。
- 前端是 SPA，nginx 已配置 `try_files $uri $uri/ /index.html;`，刷新不会 404。
- 容器以 root 运行（nginx master 需要），`resource` 卷需可写。
- 生产建议在前置反向代理（Nginx/Caddy/云 LB）上终结 HTTPS，并透传
  `Host` / `X-Forwarded-Proto`，授权域名依赖真实 Host 判定。
- 健康检查命中 `/api/v1/health`，启动宽限 40s。

## 8. 平台不匹配 / 镜像「无法识别」排查

按顺序确认：

```bash
uname -m                                        # 宿主架构，x86_64 才能原生跑本镜像
docker version --format '{{.Server.Arch}}'      # Docker 服务端架构
docker buildx ls                                # 看默认驱动的平台
docker image inspect yyb:1.0.5 --format '{{.Architecture}}/{{.Os}}'
```

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 构建成功但 `docker images` 里看不到 | `docker buildx build` 默认用 `docker-container` 驱动，产物只进 buildx 缓存 | 加 `--load`，或改用 `docker build`；也可以 `docker buildx build ... --output type=docker` |
| `requested image's platform (linux/amd64) does not match detected host platform` | 宿主是 arm64，镜像是 amd64 | 换 x86_64 宿主；或在 arm64 上装 QEMU：`docker run --privileged --rm tonistiigi/binfmt --install amd64`，再 `docker run --platform linux/amd64` |
| `docker load -i xxx.zip` 报非法归档 | zip 是**源码构建上下文**，不是镜像归档 | zip 解压后 `bash docker/build.sh`；镜像归档要用 `docker save` 生成的 `.tar.gz` |
| `exec format error` / `standard_init_linux.go` | 二进制架构与运行平台不符 | 同上，确认是 x86_64 宿主且镜像为 `amd64/linux` |
| 镜像里出现 `unknown/unknown` 清单、`docker load` 后平台显示异常 | buildx 默认写入 provenance / SBOM 证明清单 | 构建加 `--provenance=false`（build-push-action 里再加 `sbom: false`），`docker/build.sh` 与 GitHub 工作流都已处理 |
| 构建时 `manifest unknown` / 拉不到基础镜像 | 网络或镜像源问题 | 配置镜像加速，或把 `node:22-bookworm-slim` 换成可达仓库的同名镜像 |
