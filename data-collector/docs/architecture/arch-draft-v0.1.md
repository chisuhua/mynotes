# 专业领域数据收集工具 - 架构草稿 v0.2

**创建时间**: 2026-03-31  
**作者**: DevMate  
**状态**: ✅ 老板评审通过（待补充查询+可视化）  
**项目**: data-collector  

---

## 1. 需求摘要（Interview 结果）

| 决策点 | 选择 | 说明 |
|--------|------|------|
| Q1. 优先级 | A - 快速验证 | 先实现核心功能，后续重构 |
| Q2. 领域范围 | B - 通用设计 | 支持任意领域配置 |
| Q3. 交付物 | C - 两者都要 | 代码 + 配置 + 文档 + 测试 |
| Q4. 向量索引 | B - ChromaDB | 独立方案，更灵活 |
| Q5. 执行模式 | B - 定时任务 | OpenClaw cron + 手动触发 |

**额外需求**:
1. 技能化实现（可组合、可定时）
2. 配置文件定义载体类型 + 领域来源
3. Collector 技能（多源搜索 + 去重 + 推荐）
4. Researcher 技能（递归调用 Collector + 状态管理）

---

## 2. 核心概念

### 2.1 载体类型（Carrier）

| 载体类型 | 示例来源 | 提取字段 |
|---------|---------|---------|
| `paper` | arXiv, ACL, NeurIPS | title, abstract, authors, pdf_url |
| `patent` | Google Patents, 国家专利局 | title, inventors, claims, status |
| `dataset` | Kaggle, HuggingFace, UCI | name, description, size, license |
| `academic` | Google Scholar, Semantic Scholar | citations, h_index, publications |
| `report` | Gartner, McKinsey, 智库 | title, summary, publish_date, price |
| `blog` | Medium, Substack, 个人博客 | title, content, tags, publish_date |

### 2.2 领域配置（Domain）

```yaml
domain: "AI Agent"
subdomains:
  - "LLM Agent"
  - "Multi-Agent System"
  - "Agent Memory"
  - "Agent Planning"
carriers:
  - type: paper
    sources:
      - name: arXiv
        url: "https://arxiv.org/search/"
        query_param: "query={keyword}&searchtype=all"
      - name: ACL Anthology
        url: "https://aclanthology.org/"
        query_param: "q={keyword}"
  - type: blog
    sources:
      - name: Medium
        url: "https://medium.com/search"
        query_param: "q={keyword}"
```

### 2.3 方向状态（Direction State）

| 状态 | 说明 | 存储位置 |
|------|------|---------|
| `pending` | 待搜索 | `state/pending.jsonl` |
| `in_progress` | 搜索中 | `state/in_progress.json` |
| `completed` | 已完成 | `state/completed.jsonl` |
| `skipped` | 跳过（去重） | `state/skipped.jsonl` |

**搜索深度**: 默认 2 级（Researcher 配置）
**搜索广度**: 每级最多 N 个子方向（可配置）

---

## 3. 系统架构

### 3.0 与 ACN 项目对接

**参考项目**: `acn-content`, `acn-web-mkdocs`

**对接方式**:
| 功能 | ACN 项目 | data-collector | 对接方式 |
|------|---------|---------------|---------|
| 内容存储 | `acn-content/sources/` | `data-collector/output/raw/` | 符号链接或统一输出目录 |
| MkDocs 配置 | `acn-web-mkdocs/mkdocs.yml` | `data-collector/mkdocs.yml` | 复用主题配置，独立站点 |
| 数据来源 | agent-news/paper-daily | paper/patent/dataset/blog | 扩展配置格式 |
| 导航结构 | 按日期导航 | 按领域 + 方向导航 | 自定义导航生成器 |

**整合建议**:
- 方案 A: data-collector 作为 ACN 的数据源插件，输出到 `acn-content/sources/`
- 方案 B: 独立站点，通过 MkDocs 多站点部署
- **推荐**: 方案 A（复用 ACN 的 MkDocs 配置和部署流程）

---

### 3.1 组件视图（完整版）

```
┌─────────────────────────────────────────────────────────────────┐
│                    专业领域数据收集工具                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              配置管理技能 (DC-Config)                    │   │
│  │  - 载体类型配置 (carriers.yaml)                          │   │
│  │  - 领域配置 (domains/*.yaml)                             │   │
│  │  - 状态配置 (state/*.jsonl)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │  DC-Collector   │              │  DC-Researcher  │          │
│  │  (采集器)       │◄─────────────│  (研究员)       │          │
│  │                 │   递归调用    │                 │          │
│  │ - 多源搜索      │              │ - 方向管理      │          │
│  │ - 去重检查      │              │ - 深度控制      │          │
│  │ - 关键字提取    │              │ - 广度控制      │          │
│  │ - 子方向推荐    │              │ - 状态追踪      │          │
│  │ - 相关方向推荐  │              │                 │          │
│  └────────┬────────┘              └─────────────────┘          │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  数据处理管道                            │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │   │
│  │  │ 清洗器    │→ │ 提取器    │→ │ 索引器    │           │   │
│  │  │ (Cleaner) │  │(Extractor)│  │ (Indexer) │           │   │
│  │  └───────────┘  └───────────┘  └────┬──────┘           │   │
│  └─────────────────────────────────────┼───────────────────┘   │
│                                        │                       │
│           ┌────────────────────────────┼───────────────────┐   │
│           ▼                            ▼                   ▼   │
│  ┌─────────────────┐      ┌─────────────────┐  ┌───────────┐  │
│  │  ChromaDB       │      │  原始数据存储   │  │  MkDocs   │  │
│  │  (向量索引)     │      │  (output/raw/)  │  │  可视化  │  │
│  └────────┬────────┘      └────────┬────────┘  └────┬──────┘  │
│           │                       │                 │          │
│           │                       │                 │          │
│           ▼                       ▼                 ▼          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              DC-Query (AI 对话查询技能)                   │   │
│  │  - 向量检索 (ChromaDB)                                   │   │
│  │  - 自然语言查询                                          │   │
│  │  - 查询引导（推荐子方向/相关方向）                        │   │
│  │  - 结果聚合与摘要                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ACN 项目对接层                               │   │
│  │  - 输出目录对接：output/raw/ → acn-content/sources/     │   │
│  │  - MkDocs 配置复用：导航自动生成                         │   │
│  │  - 数据格式兼容：Markdown + Frontmatter                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 技能设计

### 4.0 技能列表总览

| 技能名称 | 用途 | 调用方式 | 输出 |
|---------|------|---------|------|
| `dc-config` | 配置管理 | `skill_use dc-config add-domain ...` | 配置文件更新 |
| `dc-collector` | 单方向采集 | `skill_use dc-collector domain="..." subdomain="..."` | 报告 + 索引 |
| `dc-researcher` | 递归研究 | `skill_use dc-researcher domain="..." root="..."` | 汇总报告 |
| `dc-query` | AI 对话查询 | `skill_use dc-query "LLM Agent 有哪些论文？"` | 查询结果 + 引导 |
| `dc-mkdocs` | 可视化生成 | `skill_use dc-mkdocs build` | MkDocs 站点 |

---

### 4.1 Collector 技能

**输入**:
```json
{
  "domain": "AI Agent",
  "subdomain": "LLM Agent",
  "carrier_type": "paper",
  "keyword": "autonomous agent planning",
  "dedup_check": true
}
```

**处理流程**:
1. 读取领域配置 → 获取来源列表
2. 去重检查 → 查询 `state/completed.jsonl`
3. 多源搜索 → 并行请求各来源
4. 数据提取 → 统一字段格式
5. 关键字提取 → LLM 生成
6. 子方向推荐 → 基于关键字聚类
7. 相关方向推荐 → 基于语义相似度
8. 更新状态 → 写入 `state/completed.jsonl`
9. 生成报告 → Markdown + JSON

**输出**:
```json
{
  "status": "success",
  "results_count": 25,
  "subdomains_recommended": ["Agent Planning", "Task Decomposition"],
  "related_domains": ["Reinforcement Learning", "Symbolic Reasoning"],
  "report_path": "output/reports/2026-03-31-llm-agent-paper.md",
  "indexed_count": 25
}
```

---

### 4.2 Researcher 技能

**输入**:
```json
{
  "domain": "AI Agent",
  "root_subdomain": "LLM Agent",
  "max_depth": 2,
  "breadth_per_level": 5,
  "carrier_types": ["paper", "blog"]
}
```

**处理流程**:
1. 初始化方向队列 → `state/pending.jsonl`
2. 读取状态 → 跳过已完成的
3. BFS/DFS 遍历:
   - 调用 Collector 收集当前方向
   - 获取子方向推荐
   - 加入待搜索队列（去重）
   - 深度 +1，检查是否达到 max_depth
4. 生成汇总报告

**状态管理**:
```json
{
  "domain": "AI Agent",
  "root": "LLM Agent",
  "start_time": "2026-03-31T10:00:00Z",
  "current_depth": 1,
  "max_depth": 2,
  "directions": {
    "completed": ["LLM Agent", "Agent Memory"],
    "pending": ["Agent Planning", "Tool Use"],
    "skipped": ["LLM Agent"]  // 去重
  },
  "results": {
    "total_collected": 150,
    "total_indexed": 148,
    "reports_generated": 5
  }
}
```

---

### 4.3 DC-Query 技能（AI 对话查询）⭐

**输入**:
```json
{
  "query": "LLM Agent 方向有哪些最新论文？",
  "domain": "AI Agent",
  "top_k": 10,
  "enable_guidance": true
}
```

**处理流程**:
1. **意图识别** — 解析查询类型（论文/专利/数据集/博客）
2. **向量检索** — ChromaDB 相似度搜索（top_k）
3. **结果聚合** — 按相关性排序 + 去重
4. **查询引导**（如 enable_guidance=true）:
   - 推荐子方向："您可能还对以下子方向感兴趣：Agent Planning, Tool Use"
   - 推荐相关方向："相关方向：Reinforcement Learning, Symbolic Reasoning"
   - 深度建议："已搜索 2 级，是否继续深入 Agent Planning？"
5. **生成回答** — Markdown 格式 + 引用来源

**输出**:
```markdown
## 查询结果：LLM Agent 最新论文

**检索范围**: AI Agent > LLM Agent  
**时间范围**: 最近 30 天  
**结果数量**: 10 篇

###  Top 3 推荐

1. **[论文标题]**(链接)
   - 作者：XXX et al.
   - 来源：arXiv:2026.03.xxx
   - 摘要：...
   - 相关度：95%

2. ...

### 💡 查询引导

**推荐子方向**:
- Agent Planning（3 篇相关论文）
- Tool Use（2 篇相关论文）

**相关方向**:
- Reinforcement Learning
- Multi-Agent System

**下一步建议**:
- "查看 Agent Planning 方向的论文"
- "搜索 LLM Agent 的数据集"
- "导出为 Markdown 报告"
```

**与 ChromaDB 集成**:
```python
# 伪代码
def query(query_text, domain, top_k=10):
    # 1. 生成查询嵌入
    query_embedding = embed(query_text)
    
    # 2. ChromaDB 检索（带过滤）
    results = chroma_collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
        where={"domain": domain}
    )
    
    # 3. 生成引导建议
    if enable_guidance:
        subdomains = suggest_subdomains(results)
        related = suggest_related_domains(domain)
    
    return format_results(results, guidance)
```

---

### 4.4 DC-MkDocs 技能（可视化导航）⭐

**输入**:
```json
{
  "output_dir": "output/mkdocs/",
  "link_to_acn": true,
  "auto_nav": true
}
```

**处理流程**:
1. **读取采集数据** — 扫描 `output/raw/` 目录
2. **生成导航结构** — 按领域/子方向/载体类型组织
3. **生成 MkDocs 配置** — `mkdocs.yml` + `nav` 配置
4. **生成索引页面** — `index.md`（概览 + 快速导航）
5. **生成分类页面** — 按载体类型分页（paper/patent/blog）
6. **（可选）链接到 ACN** — 符号链接到 `acn-content/sources/`

**输出结构**（参考 ACN）:
```
output/mkdocs/
├── mkdocs.yml              # 自动生成的配置
├── index.md                # 首页（概览 + 导航）
├── docs/
│   ├── ai-agent/
│   │   ├── index.md        # AI Agent 领域首页
│   │   ├── llm-agent/
│   │   │   ├── index.md    # LLM Agent 子方向
│   │   │   ├── papers.md   # 论文列表
│   │   │   └── blogs.md    # 博客列表
│   │   └── agent-memory/
│   └── llm/
└── overrides/
    └── main.html           # 自定义主题（可选）
```

**MkDocs 配置模板**（参考 ACN）:
```yaml
site_name: Data Collector Dashboard
site_description: 专业领域数据收集可视化
theme:
  name: material
  features:
    - navigation.tabs
    - navigation.sections
    - search

nav:
  - 首页：index.md
  - AI Agent:
    - LLM Agent:
      - 论文：docs/ai-agent/llm-agent/papers.md
      - 博客：docs/ai-agent/llm-agent/blogs.md
    - Agent Memory: ...
  - 使用指南：usage.md
```

**与 ACN 对接**:
```bash
# 方案 A: 符号链接（推荐）
ln -sf /workspace/data-collector/output/raw/ \
        /workspace/acn-content/sources/data-collector/

# 方案 B: 独立站点
skill_use dc-mkdocs build --output /workspace/data-collector/output/mkdocs/
cd /workspace/data-collector/output/mkdocs/ && mkdocs serve
```

---

### 4.5 DC-Config 技能

**功能**:
- 添加/编辑载体类型
- 添加/编辑领域配置
- 查看配置状态
- 验证配置合法性

**命令**:
```bash
# 添加载体来源
skill_use dc-config add-carrier --type paper --name arXiv --url "..."

# 添加领域
skill_use dc-config add-domain --name "AI Agent" --subdomains "LLM Agent,..."

# 查看配置
skill_use dc-config list-domains
skill_use dc-config list-carriers

# 验证配置
skill_use dc-config validate
```

**配置文件格式**:
```yaml
# config/carriers.yaml
carriers:
  paper:
    name: 学术论文
    icon: 📄
    fields: [title, abstract, authors, pdf_url, publish_date]
    sources:
      - name: arXiv
        url: "https://arxiv.org/search/"
        query_param: "query={keyword}&searchtype=all"
      - name: ACL Anthology
        url: "https://aclanthology.org/"
        
  patent:
    name: 专利
    icon: ™️
    fields: [title, inventors, assignee, claims, status]
    sources:
      - name: Google Patents
        url: "https://patents.google.com/"
      - name: 国家专利局
        url: "http://cpquery.cnipa.gov.cn/"
        
  dataset:
    name: 数据集
    icon: 📊
    fields: [name, description, size, license, download_url]
    sources:
      - name: Kaggle
        url: "https://www.kaggle.com/datasets"
      - name: HuggingFace
        url: "https://huggingface.co/datasets"
```

---

## 5. 配置结构

```
/workspace/data-collector/
├── config/
│   ├── carriers.yaml        # 载体类型定义
│   ├── domains/
│   │   ├── ai-agent.yaml    # AI Agent 领域配置
│   │   ├── llm.yaml         # LLM 领域配置
│   │   └── ...
│   └── researcher.yaml      # Researcher 默认配置
├── state/
│   ├── pending.jsonl        # 待搜索方向
│   ├── in_progress.json     # 当前搜索中
│   ├── completed.jsonl      # 已完成（去重用）
│   └── skipped.jsonl        # 已跳过
├── output/
│   ├── raw/                 # 原始采集数据
│   ├── indexed/             # ChromaDB 索引
│   └── reports/             # 生成的报告
└── skills/
    ├── dc-collector/
    ├── dc-researcher/
    └── dc-config/
```

---

## 6. OpenClaw 集成

### 6.1 定时任务配置（cron）

**配置位置**: `~/.openclaw/openclaw.json` 或通过 `cron add` 命令

```json5
{
  "cron": {
    "jobs": [
      {
        "id": "data-collector-daily",
        "name": "数据收集 - 每日自动",
        "schedule": {
          "kind": "cron",
          "expr": "0 6 * * *",  // 每日 6:00
          "tz": "Asia/Shanghai"
        },
        "payload": {
          "kind": "agentTurn",
          "message": "skill_use dc-researcher domain=\"AI Agent\" root_subdomain=\"LLM Agent\" max_depth=2",
          "model": "qwen3.5-plus",
          "timeoutSeconds": 3600
        },
        "sessionTarget": "isolated",
        "enabled": true
      },
      {
        "id": "data-collector-mkdocs",
        "name": "数据收集 - 生成可视化",
        "schedule": {
          "kind": "cron",
          "expr": "0 7 * * *",  // 每日 7:00（收集完成后）
          "tz": "Asia/Shanghai"
        },
        "payload": {
          "kind": "agentTurn",
          "message": "skill_use dc-mkdocs build --link-to-acn",
          "model": "qwen3.5-plus",
          "timeoutSeconds": 600
        },
        "sessionTarget": "isolated",
        "enabled": true
      }
    ]
  }
}
```

**手动触发**:
```bash
# 完整研究流程
skill_use dc-researcher domain="AI Agent" root_subdomain="LLM Agent"

# 单次采集
skill_use dc-collector domain="AI Agent" subdomain="LLM Agent" carrier_type="paper"

# AI 查询
skill_use dc-query "LLM Agent 方向有哪些最新论文？"

# 生成可视化
skill_use dc-mkdocs build --output /workspace/data-collector/output/mkdocs/

# 查看状态
skill_use dc-status
```

```json5
// ~/.openclaw/openclaw.json
{
  "cron": {
    "jobs": [
      {
        "name": "data-collector-daily",
        "schedule": { "kind": "cron", "expr": "0 6 * * *" },
        "payload": {
          "kind": "agentTurn",
          "message": "skill_use dc-researcher domain=\"AI Agent\" root_subdomain=\"LLM Agent\""
        },
        "sessionTarget": "isolated"
      }
    ]
  }
}
```

### 6.2 手动触发

```bash
# 完整研究流程
skill_use dc-researcher domain="AI Agent" root_subdomain="LLM Agent"

# 单次采集
skill_use dc-collector domain="AI Agent" subdomain="LLM Agent" carrier_type="paper"

# 查看状态
skill_use dc-status
```

---

## 7. 技术选型

| 组件 | 选型 | 理由 |
|------|------|------|
| 向量数据库 | ChromaDB | 轻量、Python 原生、支持本地存储 |
| Web 采集 | Playwright + requests | Playwright 处理 JS，requests 处理简单 API |
| 关键字提取 | LLM (qwen3.5-plus) | 语义理解准确 |
| 去重算法 | MinHash + LSH | 近似去重，支持模糊匹配 |
| 配置格式 | YAML | 人类可读，支持注释 |
| 状态存储 | JSONL | 流式写入，易于追加 |

---

## 8. 任务分解（更新版）

### Phase 1: 基础架构（预计 2 小时）
- [ ] **Task 001**: 创建项目目录 + 配置模板
- [ ] **Task 002**: 实现 DC-Config 技能（载体/领域配置）
- [ ] **Task 003**: 实现状态管理模块（JSONL 存储）

### Phase 2: Collector 核心（预计 3 小时）
- [ ] **Task 004**: 实现多源搜索框架（Playwright + requests）
- [ ] **Task 005**: 实现去重检查模块（MinHash + LSH）
- [ ] **Task 006**: 实现关键字提取（LLM 调用）
- [ ] **Task 007**: 实现子方向/相关方向推荐

### Phase 3: Researcher 核心（预计 2 小时）
- [ ] **Task 008**: 实现方向队列管理（BFS/DFS）
- [ ] **Task 009**: 实现递归调用逻辑
- [ ] **Task 010**: 实现深度/广度控制

### Phase 4: 数据存储与索引（预计 2 小时）
- [ ] **Task 011**: 实现 ChromaDB 索引（向量存储）
- [ ] **Task 012**: 实现报告生成（Markdown + JSON）
- [ ] **Task 013**: 配置 OpenClaw cron（定时任务）

### Phase 5: AI 对话查询（预计 2 小时）⭐
- [ ] **Task 014**: 实现 DC-Query 技能（向量检索）
- [ ] **Task 015**: 实现意图识别（查询类型解析）
- [ ] **Task 016**: 实现查询引导（推荐子方向/相关方向）

### Phase 6: MkDocs 可视化（预计 2 小时）⭐
- [ ] **Task 017**: 实现 DC-MkDocs 技能（导航生成）
- [ ] **Task 018**: 生成 MkDocs 配置模板
- [ ] **Task 019**: ACN 项目对接（符号链接/配置复用）

### Phase 7: 集成测试与文档（预计 1 小时）
- [ ] **Task 020**: 端到端测试（Collector → Researcher → Query）
- [ ] **Task 021**: 编写使用文档
- [ ] **Task 022**: 配置示例与演示

**总预计**: 14 小时（可分 2-3 天完成）

---

## 8.1 并行执行策略

**可并行任务**:
- Phase 2 (Task 004-007) ↔ Phase 3 (Task 008-010) — 独立模块
- Phase 5 (Task 014-016) ↔ Phase 6 (Task 017-019) — 独立功能

**依赖关系**:
```
Task 001-003 (基础) → Task 004-007 (Collector) → Task 008-010 (Researcher)
                     Task 011-013 (存储)      → Task 014-016 (Query)
                     Task 017-019 (MkDocs) — 独立
```

---

## 9. ACN 项目对接方案

### 9.1 对接方式比较

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| **A: 符号链接** | 简单、实时同步、复用 ACN 配置 | 目录结构需兼容 | ⭐⭐⭐⭐⭐ |
| B: 数据复制 | 完全独立、灵活定制 | 需额外同步步骤 | ⭐⭐⭐ |
| C: API 对接 | 解耦、可扩展 | 实现复杂度高 | ⭐⭐ |

**推荐方案**: A（符号链接）

---

### 9.2 符号链接方案实现

**步骤 1: 创建对接目录**
```bash
# 在 acn-content 中创建符号链接
ln -sf /workspace/data-collector/output/raw/ \
        /workspace/acn-content/sources/data-collector/

# 验证链接
ls -la /workspace/acn-content/sources/ | grep data-collector
```

**步骤 2: 更新 ACN 配置**
```yaml
# acn-content/config/sources.yaml
sources:
  - id: data-collector
    name: Data Collector
    path: sources/data-collector/
    type: markdown
    description: 专业领域数据收集（论文/专利/数据集/博客）
    icon: 🔍
    enabled: true
```

**步骤 3: 更新 ACN MkDocs 导航**
```yaml
# acn-web-mkdocs/mkdocs.yml
nav:
  - 首页：index.md
  - Agent News: sources/agent-news/
  - Data Collector:
    - AI Agent: sources/data-collector/ai-agent/
    - LLM: sources/data-collector/llm/
  - 使用指南：usage.md
```

**步骤 4: 数据格式兼容**
```markdown
---
# Frontmatter（ACN 兼容格式）
title: "LLM Agent 最新论文收集"
date: 2026-03-31
domain: AI Agent
subdomain: LLM Agent
carrier_type: paper
tags: [LLM, Agent, Planning]
source: arXiv
---

# 正文内容

## 收集概览
- **方向**: LLM Agent
- **时间**: 2026-03-31
- **来源**: arXiv, ACL, NeurIPS
- **数量**: 25 篇

## 论文列表
...
```

---

### 9.3 导航自动生成

**dc-mkdocs 技能输出**:
```python
# 伪代码
def generate_nav():
    # 扫描 output/raw/ 目录
    domains = scan_domains("output/raw/")
    
    # 生成导航结构
    nav = [{"首页": "index.md"}]
    for domain in domains:
        domain_nav = {domain["name"]: []}
        for subdomain in domain["subdomains"]:
            subdomain_nav = {
                subdomain["name"]: [
                    f"docs/{domain['id']}/{subdomain['id']}/papers.md",
                    f"docs/{domain['id']}/{subdomain['id']}/blogs.md"
                ]
            }
            domain_nav[domain["name"]].append(subdomain_nav)
        nav.append(domain_nav)
    
    # 更新 mkdocs.yml
    update_mkdocs_config(nav)
```

---

### 9.4 查询技能与 ACN 搜索集成

**方案**: DC-Query 提供 API，ACN 搜索页面调用

**实现方式**:
1. DC-Query 输出 JSON 结果到 `output/query-results/`
2. ACN 前端通过 JavaScript 读取并展示
3. 或：FastAPI 后端统一提供查询接口（未来扩展）

---

## 10. 风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| 网站反爬 | 中 | 中 | Playwright + 速率限制 + 代理池 |
| 去重误判 | 低 | 中 | MinHash 阈值可调 + 人工复核 |
| 递归过深 | 中 | 低 | 硬编码 max_depth=3 |
| ChromaDB 内存 | 低 | 中 | 分片索引 + 定期清理 |
| ACN 目录结构变更 | 低 | 中 | 符号链接抽象层 + 配置适配 |

---

## 10. 待确认问题

**请老板评审以下决策点**:

| 决策点 | 选项 A | 选项 B | 我的建议 |
|--------|--------|--------|---------|
| D1. 搜索算法 | BFS（广度优先） | DFS（深度优先） | A（先覆盖更多子方向） |
| D2. 去重阈值 | MinHash相似度>0.8 | MinHash 相似度>0.9 | B（更严格，避免遗漏） |
| D3. 报告格式 | 仅 Markdown | Markdown + JSON | B（JSON 便于后续处理） |
| D4. 状态持久化 | 每次更新立即写入 | 批量写入（每 10 个方向） | A（更安全，防丢失） |

---

## 11. 下一步

**老板评审后**:
1. ✅ 确认架构 → 派给 OpenCode 生成标准化文档
2. 🔄 需要调整 → 修改本草稿 → 重新评审
3. ⏭️ 评审通过 → acf-sync 同步 → 进入编码循环

---

**版本**: v0.2（架构通过 + 查询/可视化补充）  
**状态**: ✅ 架构已批准，待进入编码循环  
**评审人**: Suhua  
**评审时间**: 2026-03-31 14:30  

---

## 12. 下一步行动

### 12.1 架构循环收尾

- [ ] **DevMate**: 派给 OpenCode 生成标准化架构文档
- [ ] **OpenCode**: `/zcf/arch-doc "专业领域数据收集工具"`
- [ ] **DevMate**: 对比评审（mynotes vs 编码仓库）
- [ ] **DevMate**: acf-sync 同步 → 进入编码循环

### 12.2 编码循环准备

**项目目录初始化**:
```bash
# 创建项目目录
mkdir -p /workspace/data-collector/{config,output,state,skills,docs/architecture,.acf/status}

# 初始化 ACF 结构
/workspace/acf-workflow/scripts/init-acf-structure.sh /workspace/data-collector

# 创建符号链接（ACN 对接）
ln -sf /workspace/data-collector/output/raw/ \
        /workspace/acn-content/sources/data-collector/
```

**第一个任务**:
```bash
skill_use acf-executor \
  task="Task 001: 创建项目目录 + 配置模板" \
  cwd="/workspace/data-collector"
```

---

**架构定稿后更新**:
- 架构文档位置：`/workspace/data-collector/docs/architecture/`
- 实施计划：`/workspace/data-collector/.acf/temp/implementation-plan.md`
- 状态追踪：`/workspace/data-collector/.acf/status/current-task.md`
