# Onboarding：装完之后怎么把知识库跑起来

`install.ps1` 做完的是“bm 能跑”；这一步做的是“bm 开始长出一个知识库”。
两条路，按你的情况选一条。

---

## 路线 1：Pi 里 onboard（推荐，仓库里带了这个 skill）

前提：`pi` 已装（npm 可达：`npm i -g @earendil-works/pi-coding-agent`），
并且 `install.ps1` 已经跑过 `bm install pi --yes`。

```
# 新开一个 Pi 会话，然后：
/skill:basic-memory-pi-setup      # 先定路由：哪个目录 = 哪个项目，写 .pi/basic-memory.json
/skill:memory-onboarding          # 再做知识库设计（访谈 → 蓝图 → 建 schema/模板/路由笔记）
```

两者分工：

| Skill | 管什么 | 产出 |
|:--|:--|:--|
| `basic-memory-pi-setup` | 这个工作区写进哪个项目 | `.pi/basic-memory.json`（`project` 路由、hook 开关、capture 策略） |
| `memory-onboarding` | 知识库长什么样 | schema、模板、`instructions/startup-router` 等指导性笔记、种子笔记 |

### `memory-onboarding` 在这里为什么能跑

它有六个阶段，全部靠 `bm` CLI 完成，不需要任何网络：

```
Phase 0  Preflight   bm tool list-projects / bm status
Phase 1  Interview   问你要管什么（任务/人脉/开销/资料…）
Phase 2  Blueprint   给出结构草案，等你点头
Phase 3  Build       schema → 模板 → 指导笔记 → 索引 → 种子笔记
Phase 4  Assistant   写进 AGENTS.md，让每个会话开局就加载 startup-router
Phase 5  Teach       用你自己的真实数据练手
Phase 6  Grow        加新领域、定维护节奏
```

两条硬规则（skill 里反复强调，别省）：

1. 每个笔记类型都要有 **schema**；
2. 每条笔记的 Observations 至少有一条 `[category] value`（例：`- [status] open`），
   否则它只是纯文本，按类别查不到。

另外每次写都要显式带 `--project <名字>`，默认项目是陷阱。

### 装到哪了

```
%USERPROFILE%\.pi\agent\skills\memory-onboarding\        ← 本仓库 skills/ 里的副本
%USERPROFILE%\.pi\agent\packages\basic-memory\           ← bm install pi 放的扩展+skills
```

想手动再放一次：

```powershell
Copy-Item -Recurse -Force .\skills\memory-onboarding "$env:USERPROFILE\.pi\agent\skills\memory-onboarding"
```

---

## 路线 2：不用 Pi，只要 CLI / MCP

```powershell
bm project add main D:\notes\main --default   # 建库并索引
bm status                                      # 看索引就绪度（--wait 等它跑完）
bm tool write-note --title "第一条笔记" --folder Inbox --type note --content "- [status] open" -p main
bm tool search-notes "第一条" -p main
bm mcp --transport stdio                       # 给别的 MCP 客户端用
```

手工建库的最小骨架（不用 onboard skill 也不会太丑）：

1. `instructions/startup-router` 笔记：写清“要做 X 类事，先读哪几篇”；
2. 每个笔记类型一篇 schema 笔记（frontmatter 里带 `schema_entity`）；
3. `AGENTS.md` / 客户端系统提示里指向 startup-router；
4. 目录用复数、大小写固定（`Tasks/`、`People/`），permalink 由路径推导，改路径等于改 ID。

---

## 验证清单

```powershell
bm --version                     # 0.24.1
bm tool list-projects            # 至少一个项目
bm status --json                 # readiness.phase = ready，不是 pending
bm tool recent-activity          # 最近改动的笔记
bm man                           # 内置手册；参数以本地版本为准
```

Pi 侧：

```
/bm-status
/bm-recall 之前做过什么
/bm-capture
```
