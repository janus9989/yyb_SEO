# YYB 1.0.5 宝塔 Linux amd64 完整底包

本包用于新服务器首次部署，不用于直接覆盖已有运行目录。

包内包含：

- Linux amd64 Go 后端主程序。
- 内置脚本样例导入工具。
- 已修复生产白屏问题的前端 `dist`。
- 宝塔安装、启动、停止、重启、systemd 和 Nginx 配置。
- 宝塔部署教程与 1.0.5 版本更新内容。

不包含数据库、运行日志、账号、会话、头像、二维码、授权码、密钥、密码或升级缓存。

快速开始：

```bash
cd /www/wwwroot/yyb
bash scripts/install.sh
vim scripts/yyb.env
bash scripts/start.sh
curl -i http://127.0.0.1:8000/api/v1/health
```

完整步骤见 `docs/宝塔部署教程.md`。
