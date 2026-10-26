# 内网踩坑清单

按报错信息找。

---

## 安装阶段

### `uv tool install` 报 “No solution found ... basic-memory==0.24.1”
wheel 集合不完整，或者解释器版本不在包里。

```powershell
# 看看到底缺什么
uv tool install --python 3.13 --no-index --offline --no-build `
  --find-links <bundle>\wheels-pure --find-links <bundle>\wheels-cp313 basic-memory==0.24.1 -v
```

包内只有 `wheels-cp312`（CPython 3.12）和 `wheels-cp313`（CPython 3.13）两套二进制轮子。
**3.14 不行**：`basic-memory 0.24.1` 依赖 `litellm<1.92`，而 litellm 1.91.x 的
`Requires-Python` 是 `>=3.10,<3.14`。

### `PYTHON 3.13 not found` / uv 想联网下 Python
`uv python find 3.13 --no-python-downloads` 查一下。真没有就走 GitHub（内网允许）：

```powershell
uv python install 3.13
```

uv 从 `github.com/astral-sh/python-build-standalone` 拉独立构建，不走 python.org。

### 装完 `bm` 找不到
uv 的 shim 在 `%USERPROFILE%\.local\bin`。脚本会把它写进用户 PATH，但**当前窗口不会自动刷新**：

```powershell
$env:Path += ";$env:USERPROFILE\.local\bin"
bm --version
```

### `uv tool install` 说 “Failed to create virtual environment” 之类
多半是 `%LOCALAPPDATA%\uv\cache` 被安全软件锁了。设一个可写目录：

```powershell
$env:UV_CACHE_DIR = "D:\uv-cache"
```

---

## 运行阶段

### `bm update` 失败 —— 预期行为
它去 PyPI 查新版本。内网下必然失败，别修。
升级方式：在内网机器上拿新版本的 bundle（GitHub release），重跑 `install.ps1 -Force`。

### `bm cloud` / `bm ci` / logfire 遥测失败 —— 预期行为
都需要外网。`logfire_enabled` 默认 `False`，不用管；`bm cloud` 只用在你真的买了云服务时。

### 语义检索卡住 / `huggingface.co` 超时
看 [offline-embedding.md](offline-embedding.md)。默认就是没装模型的，只要不显式要向量就不触发。
临时止血：`bm config set default_search_type text`。

### 模型“用着用着不见了”
缓存里的 `snapshots/<rev>/model_optimized.onnx` 是断链（符号链接没解引用）。Basic Memory 判定为
下载损坏会删掉重下，离线环境就表现为模型反复消失。用 `tar -czhf` 打包，见方案 B。

### `bm: OSError: [WinError 10013]` 或端口占用
`bm mcp --transport http` 默认端口被占。换端口：

```powershell
bm mcp --transport http --port 8766
```

### 中文笔记搜不到
`sqlite` FTS5 分词对中文按字切，短查询噪声大。要么用 `bm grep`（按行匹配，不走分词），
要么按方案 C 接内网 embedding 走向量检索。

### SQLite 出现 “database is locked”
两个 bm 进程同时写（Pi 一个 + 手动一个）。先 `bm status` 等后台索引跑完，或关掉多余会话。

---

## Pi 集成

### `bm install pi --yes` 报 “pi is required”
`pi` 不在 PATH。npm 可达就装：

```powershell
npm i -g @earendil-works/pi-coding-agent
```

装好重开窗口再 `bm install pi --yes`。

它做的事是：把 wheel 里内嵌的 Pi 扩展（`extensions/`、`skills/`、`skill-references/`）
拷到 `%USERPROFILE%\.pi\agent\packages\basic-memory`，然后执行
`pi install <那个本地目录>`——纯本地路径，不碰 npm registry。先看预案不会写任何文件：

```powershell
bm install pi --dry-run
```

### PATH 改动没生效 / `-NoPath`
脚本用 `[Environment]::SetEnvironmentVariable(...,"User")` 写用户 PATH，对**新开的**窗口生效。
当前窗口手工：`$env:Path += ";$env:USERPROFILE\.local\bin"`。想自己管就加 `-NoPath`。

### Pi 里看不到 `/bm-status`
扩展注册了但没重启。退出 Pi 重进；仍然没有就查 `%USERPROFILE%\.pi\agent\packages\basic-memory\extensions\index.ts`
是否存在，必要时 `bm install pi --yes --replace`。

### 会话把笔记写进了错误的项目
`--project` 没显式传。用 `/skill:basic-memory-pi-setup` 写死 `.pi/basic-memory.json`，
或每次写都带 `-p <名字>`。改错的项目要 `bm tool delete-note` 清掉，别只改文件。

---

## 想自己重建这个包

见 `scripts/build-bundle.sh`（在能上 PyPI 的机器上跑）。它会重新解析 pin 集合、
逐个下载 win_amd64 轮子、对无轮子的包（`pybars3`、`pymeta3`）现场构建 `py3-none-any`，
最后用 `uv pip install --no-index --offline` 做一次“关闭性验证”，确认没有漏网依赖。
