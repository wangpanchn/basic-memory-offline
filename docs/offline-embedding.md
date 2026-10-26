# 离线/内网环境下的语义检索（embedding）

默认安装**不含**任何向量模型文件。只有当你显式让 Basic Memory 生成或查询向量时，它才会：

1. 用 `fastembed` 加载本地 ONNX 模型；
2. 模型不在缓存里 → 去 `huggingface.co` / `cdn-lfs.huggingface.co` 下载。

内网这两条路都不通，所以有三个选择。**不做任何事也完全能跑**：全文检索（FTS5）正常，
`bm grep`、`bm find`、`bm tool search-notes`（不传 `--vector/--hybrid`）都不需要模型。

---

## 方案 A（推荐）：只用全文检索，把语义检索关掉

```powershell
bm config set default_search_type text
```

这样 `search-notes` 默认走 text，`bm reindex` 也不会去碰 embeddings。
以后想开再说。注意：**不要**手动跑 `bm reindex --embeddings`，一定会卡在模型下载。

---

## 方案 B：把模型文件拷进来，完全离线加载

模型只是一堆文件，`fastembed` 支持指定缓存目录，HuggingFace 支持纯离线模式。

### B1. 在一台能上外网的机器上把模型拉下来

```bash
# 任意一台能联网的机器（Linux/macOS/Windows 都行，架构不影响，模型是 ONNX 数据文件）
uv tool install basic-memory
bm project add tmp ~/bm-tmp
bm reindex --embeddings -p tmp        # 触发一次下载；失败也无所谓，只要模型落盘
```

模型落在 Basic Memory 数据目录下的 `fastembed_cache`：

| 平台 | 默认路径 |
|:--|:--|
| Windows | `%USERPROFILE%\.basic-memory\fastembed_cache` |
| Linux/macOS | `~/.basic-memory/fastembed_cache` |

目录结构（HF hub 风格，靠符号链接串联，**拷贝时必须解引用**）：

```
fastembed_cache/
└── models--Qdrant--bge-small-zh-v1.5/
    ├── blobs/<sha256>                    # 真正的数据
    ├── refs/main
    ├── snapshots/<rev>/model_optimized.onnx -> ../../blobs/<sha256>
    ├── snapshots/<rev>/tokenizer.json
    ├── snapshots/<rev>/config.json
    ├── snapshots/<rev>/tokenizer_config.json
    ├── snapshots/<rev>/special_tokens_map.json
    └── trees/<rev>.json
```

对应关系：配置里的 `BAAI/bge-small-zh-v1.5` 在 fastembed 里映射到 HF 仓库
`Qdrant/bge-small-zh-v1.5`，所以目录名是 `models--Qdrant--bge-small-zh-v1.5`。
英文默认模型是 `models--Qdrant--bge-small-en-v1.5-onnx-Q`。

### B2. 打包（解引用符号链接，这是唯一容易翻车的点）

```bash
# 在联网机器上：-h 让 tar 跟随符号链接，把真实内容打进去
cd ~/.basic-memory
tar -czhf fastembed-cache.tgz fastembed_cache
```

Windows 上如果 `tar` 不可用，用 `robocopy` 复制到 U 盘（Windows 侧 HF 缓存本身就是普通文件，
不是符号链接）。**不要**用 zip 直接打包 Linux 上的缓存目录，zip 默认会把符号链接存成链接或者碎文件。

### B3. 在内网机器上解包 + 指路 + 断网模式

```powershell
# 1) 解到任意位置，例如 D:\bm\fastembed_cache
mkdir D:\bm -Force
tar -xzf fastembed-cache.tgz -C D:\bm

# 2) 告诉 Basic Memory 模型在哪（写 config.json，最稳）
bm config set semantic_embedding_cache_dir "D:\bm\fastembed_cache"

# 3) 让 HuggingFace 库彻底不联网，缺失就直接报错而不是卡住
setx HF_HUB_OFFLINE 1
setx TRANSFORMERS_OFFLINE 1
$env:HF_HUB_OFFLINE="1"; $env:TRANSFORMERS_OFFLINE="1"

# 4) 验证：确认 snapshots 下的 model_optimized.onnx 是真文件而不是断链
Get-ChildItem -Recurse "D:\bm\fastembed_cache\models--*\snapshots" | Select-Object FullName,Length

# 5) 现在才允许跑 embeddings
bm reindex --embeddings
bm grep "某个词" --semantic
```

**为什么必须解引用**：Basic Memory 会检查该模型每个 snapshot 目录里是否有
`model_optimized.onnx`。文件在但断链 = 判定为“下载损坏”，会**主动删掉**这个模型目录
重新下载 —— 在离线环境里表现成“用着用着模型没了”。所以第 4 步的 `Length` 不能是 0。

缓存目录也可以通过环境变量给：`FASTEMBED_CACHE_PATH` 或
`BASIC_MEMORY_SEMANTIC_EMBEDDING_CACHE_DIR`（优先级高于 config.json 的默认值）。

---

## 方案 C：用内网的 OpenAI 兼容 embedding 接口

如果内网里有 vLLM / Xinference / Ollama / 公司网关之类提供 `/v1/embeddings`，完全不需要本地模型：

```powershell
bm config set semantic_embedding_provider openai
bm config set semantic_embedding_api_base "http://10.0.0.9:8000/v1"
bm config set semantic_embedding_api_key "not-needed"
bm config set semantic_embedding_model "bge-m3"          # 网关上的模型名
bm config set semantic_embedding_dimensions 1024          # 必须和模型输出维度一致
bm reindex --embeddings
```

要求：

- `semantic_embedding_dimensions` 必须与模型真实维度一致，写错会向量落库报错；
- 建库之后**换模型/换维度**要 `bm reset` 或至少 `bm reindex --full --embeddings`，否则新旧向量不可比；
- `semantic_embedding_provider` 只接受 `fastembed`（默认）/ `openai` / `litellm` 三个值。

---

## 附：reranker 也是模型下载大户

`reranker_enabled` 默认 `False`，保持关闭即可。开启后默认 `fastembed` 的
`jinaai/jina-reranker-v1-tiny-en` 同样要下载（缓存路径同上），内网下一样会卡。
除非你按方案 B/C 一起处理，否则别开。
