# basic-memory-offline

在只能访问 **GitHub + npm** 的内网 Windows 机器上，离线安装
[Basic Memory](https://github.com/basicmachines-co/basic-memory)（`bm` CLI），
并把 Pi 集成和 onboarding skill 一起装好。

- 版本：`basic-memory 0.24.1`
- 目标：Windows x64（win_amd64），CPython **3.12** 或 **3.13**
- 依赖集合：174 个 PyPI 发行包 → **211 个 wheel 文件**（137 个纯 Python 共享 + 3.12/3.13 各 37 个二进制）
- 轮子包体积：解压 166 MB，zip 169 MB（挂在 Release，不进仓库）

不需要 PyPI，不需要外网 Python 安装器，不需要 HuggingFace。

---

## 快速开始

```powershell
git clone https://github.com/wangpanchn/basic-memory-offline.git
cd basic-memory-offline

# 一条命令：拉 Release 里的 wheel 包 → 校验 → uv 离线安装 → 装 Pi 扩展 → 放 onboarding skill
.\install.ps1

# 常见变体
.\install.ps1 -ProjectName main -ProjectPath D:\notes\main   # 顺手建库
.\install.ps1 -PyVersion 3.12                                # 机器上只有 3.12
.\install.ps1 -Bundle C:\temp\basic-memory-0.24.1-win_amd64-wheels.zip   # 手工拷的 zip
```

装完开新窗口，`bm --version` 应该输出 `Basic Memory version: 0.24.1`。

如果 `Invoke-WebRequest` 拉 Release 失败（部分内网只放行 `github.com`，不放行
`release-assets.githubusercontent.com`），手工把
`basic-memory-0.24.1-win_amd64-wheels.zip`（169 MB，sha256
`00f0703c6e24add5dbd538a0a6a0f3dfb344c34d1d0eefb6bf93954aacd56353`）
放到仓库目录下，再跑 `.\install.ps1 -Bundle .\basic-memory-0.24.1-win_amd64-wheels.zip`。

---

## 为什么需要这个仓库：内网到底缺什么

内网只开 GitHub 和 npm。Basic Memory 是个 Python 项目，它自己从 PyPI 装，所以卡在第一层；
装完还有第二层（模型、云服务）。

| 依赖 | 官方获取渠道 | 内网可达 | 本仓库怎么解决 |
|:--|:--|:--:|:--|
| `bm` 本体 + 173 个传递依赖 | PyPI (`pypi.org`, `files.pythonhosted.org`) | ❌ | **211 个 wheel 全量打包**，`uv tool install --no-index --offline` |
| `pybars3` / `pymeta3` | PyPI 只有 sdist（要现场编译） | ❌ | 预先构建成 `py3-none-any` wheel 塞进包里 |
| uv 本体 | GitHub Releases (`astral-sh/uv`) | ✅ | 直接用；没装的话脚本给了下载命令 |
| CPython 解释器 | `python-build-standalone`（GitHub） | ✅ | `uv python install 3.13` 即可，不走 python.org |
| Pi 本体 | npm | ✅ | `npm i -g @earendil-works/pi-coding-agent` |
| Pi 扩展 `@basicmemory/pi-basic-memory` | npm | ✅（但其实不需要） | `bm install pi --yes` 把 wheel 里内嵌的同一份包拷到本地并本地注册，完全不联网 |
| embedding 模型（bge-small 等） | HuggingFace | ❌ | 默认不装、不加载；要语义检索看 `docs/offline-embedding.md`（拷模型 or 接内网 embedding API） |
| `bm update` | PyPI | ❌ | 预期失败。升级 = 换新 bundle 重跑 `install.ps1 -Force` |
| `bm cloud` / `bm ci` / logfire 遥测 | basic-memory.cloud | ❌ | 可选功能，默认关闭，不用管 |
| 在线文档 | docs.basic-memory.cloud | ❌ | `bm man` 是内置手册，参数以本地版本为准 |

一句话：**Python 生态那 174 个包是唯一真正卡死的部分**，其余都能靠 GitHub / npm 绕过。

---

## 目录

```
install.ps1                      # 离线安装器（PowerShell 5.1+，实测思路见 docs/troubleshooting.md）
wheels-manifest.txt              # 211 个 wheel 的 sha256 + pin 集合来源
pins-win_amd64.txt               # 174 个精确 pin（3.12 / 3.13 版本集合相同）
skills/memory-onboarding/        # onboard skill（Pi CLI 版，6 阶段建知识库）
docs/onboarding.md               # 装完之后怎么把知识库跑起来（Pi 两条 skill 的分工）
docs/offline-embedding.md        # 语义检索的三种离线方案
docs/troubleshooting.md          # 报错对照表
scripts/build-bundle.sh          # 在联网机器上重建整个 wheel 包
```

wheel 包本身（`wheels-pure/`、`wheels-cp312/`、`wheels-cp313/`、`SHA256SUMS.txt`）
作为 Release 资产分发：<https://github.com/wangpanchn/basic-memory-offline/releases>

---

## 安装器做了什么

1. 找 wheel 包：脚本同目录 → 已解压目录 → Release 下载；
2. 用 `SHA256SUMS.txt` 校验每个 wheel（不匹配就停）；
3. 检查 `uv`（没有则打印从 GitHub 装的命令）；
4. 选解释器：`uv python find 3.13 --no-python-downloads`，退到 `3.12`，都没有就报错并给两条出路；
5. `uv tool install --python <ver> --no-index --offline --no-build --find-links wheels-pure
   --find-links wheels-cpXY basic-memory==0.24.1 --with socksio`
   —— `--no-build` 保证不会去解 sdist、不会隐式联网；
6. 把 `%USERPROFILE%\.local\bin` 加进用户 PATH，验证 `bm --version`；
7. 可选：`bm project add <名字> <目录>`；
8. `bm install pi --yes`（把 wheel 内嵌的 Pi 扩展 + setup skills 拷到
   `%USERPROFILE%\.pi\agent\packages\basic-memory`，并用本地路径向 Pi 注册）；
9. 把 `skills/memory-onboarding` 拷到 `%USERPROFILE%\.pi\agent\skills\`。

`-SkipPi`、`-Force`、`-NoPath` 可跳过/强制上述任意步。

---

## 装完之后

```powershell
# 知识库
bm project add main D:\notes\main
bm status
bm man                     # 内置手册

# Pi 里（新开一个会话）
/skill:basic-memory-pi-setup     # 定 .pi/basic-memory.json 的项目路由
/skill:memory-onboarding         # 完整 6 阶段：访谈 → 蓝图 → schema/模板/路由笔记 → 教学
```

细节见 [`docs/onboarding.md`](docs/onboarding.md)。

---

## 重建 / 升级 wheel 包

在任意能上 PyPI 的机器上（Linux/macOS 均可，打包产物是 Windows 轮子）：

```bash
VERSION=0.24.1 ./scripts/build-bundle.sh
# 产物：build/dist/basic-memory-0.24.1-win_amd64-wheels.zip
```

脚本做的事：

1. `uv pip compile --python-platform windows` 解析出 3.12 / 3.13 各 174 个 pin；
2. **逐个** `pip download --no-deps --only-binary=:all: --platform win_amd64`
   —— 不能用一次解析式下载：pip 会把 `uvloop ; sys_platform != "win32"`
   这类 marker 按宿主（Linux）求值，直接失败；
3. 对没有 Windows 轮子的包（只有 `pybars3`、`pymeta3`）现场构建 `py3-none-any`；
4. 把两份重复的纯 Python 轮子去重成共享的 `wheels-pure/`（137 个，省 43 MB）；
5. `sha256sum` 出 `SHA256SUMS.txt`，打 zip；
6. 用 `uv pip install --no-index --offline --no-build --python-platform windows`
   做一次**关闭性验证**：本地轮子若能装出完整 363 个包，说明集合没缺口。

升级流程：改 `VERSION` → 重建 → 传新 Release 资产 → 内网机器 `git pull` 后
`.\install.ps1 -Force`。

---

## 已知限制

- **只有 win_amd64**。别的平台要在对应平台重跑 `build-bundle.sh`（改 `PLATFORM` / `PYVERS`）；
- **Python 必须是 3.12 或 3.13**。3.14 不行：`basic-memory 0.24.1` 依赖 `litellm<1.92`，
  而 litellm 1.91.x 声明 `Requires-Python <3.14`；
- `documents` / `pdf` / `redis` / `milvus` 这些 extra 没打进来（默认安装不装它们）。
  需要的话在 `build-bundle.sh` 的 `req.in` 里加，例如 `basic-memory[documents]==0.24.1`；
- 语义检索默认不可用，见 `docs/offline-embedding.md`；
- 本包不含任何凭据、不含 Basic Memory 的配置或笔记数据。

许可：`basic-memory` 本体是 AGPL-3.0-or-later（上游 `basicmachines-co/basic-memory`），
本仓库只做打包与安装脚本，不修改上游代码。
