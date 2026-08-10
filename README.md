# B站视频数据看板

本地看板服务：`http://localhost:8765/`

## 云端部署

- GitHub Actions 每小时运行 `fetch-bilibili.ps1`，更新 `snapshots.csv` 和 `data.json`。
- GitHub Pages 自动发布 `www/index.html` 和 `data.json`。
- 公开网址格式：`https://<用户名>.github.io/<仓库名>/`

## 本地文件

- `fetch-bilibili.ps1`：抓取并生成数据
- `dashboard-server.ps1`：本地网页服务
- `start-dashboard.ps1`：启动看板服务
- `打开看板.bat`：双击打开本地看板
- `snapshots.csv`：按小时快照
- `data.json`：看板数据
