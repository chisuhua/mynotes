# 专业领域数据收集工具 - 架构草稿 v0.3

**创建时间**: 2026-03-31  
**作者**: DevMate  
**状态**: ✅ 架构已批准（整合 KnowledgeGraph）  
**项目**: data-collector  

---

## 1. 与 KnowledgeGraph 项目关系

### 1.1 定位

| 项目 | 定位 | 职责 |
|------|------|------|
| **data-collector** | 数据采集前端 | 多源采集、去重、增量添加、领域配置 |
| **KnowledgeGraph** | 统一存储后端 | Schema 定义、知识图谱、UniDAG-Store |
| **UniDAG-Store** | 存储基础设施 | 图存储、事务、查询接口 |

### 1.2 协作关系

```
data-collector (本工具)
    │
    │ 采集数据
    ▼
dc-data-api (统一接入层)
    │
    │ 调用
    ▼
UniDAG-Adapter (存储抽象)
    │
    ├──→ SQLite (原型阶段，data-collector 实现)
    ├──→ ChromaDB (向量索引，data-collector 实现)
    └──→ UniDAG-Store (目标架构，KnowledgeGraph 实现)
```

### 1.3 实施策略

**阶段 1: 原型验证**（data-collector 主导）
- 实现 SQLite + ChromaDB 存储
- 验证采集、去重、增量添加流程
- 为 KnowledgeGraph 提供实践经验

**阶段 2: 存储迁移**（KnowledgeGraph 主导）
- KnowledgeGraph 完成 UniDAG-Store 图查询接口
- data-collector 切换到 UniDAG-Adapter
- 共享 Schema 定义

**阶段 3: 统一存储**（两项目共享）
- 所有数据存入 UniDAG-Store
- 跨项目去重
- 知识图谱查询

---

## 2. Schema 对齐设计

### 2.1 KnowledgeGraph 核心 Schema（参考）

**实体类型**:
| 实体 | 核心属性 |
|------|---------|
| `Paper` | title, year, doi, venue, pdf_url, abstract, status |
| `Author` | name, affiliation, orcid_id |
| `Task` | name (如"Image Classification") |
| `Dataset` | name, domain, url |
| `Metric` | name, direction |
| `Method` | name, category |

**关系类型**:
| 关系 | 方向 | 属性 |
|------|------|------|
| `CITES` | Paper → Paper | context_snippet, count |
| `SURPASSES` | Paper → Paper | metric_name, improvement_delta, dataset |
| `REFUTES` | Paper → Paper | reason, confidence |
| `ACHIEVES_METRIC` | Paper → Metric | value, dataset |

### 2.2 data-collector 扩展 Schema

**新增实体类型**（KnowledgeGraph 未覆盖）:
| 实体 | 核心属性 | 用途 |
|------|---------|------|
| `Patent` | id, title, inventors, assignee, claims, status | 专利数据 |
| `BlogPost` | title, content, author, publish_date, source | 博客文章 |
| `Report` | title, summary, organization, publish_date | 专业报告 |
| `Direction` | name, domain, parent_direction, status | 研究方向状态追踪 |

**新增关系类型**:
| 关系 | 方向 | 属性 |
|------|------|------|
| `COLLECTED_BY` | Any → Direction | collected_at, project |
| `RELATED_TO` | Any → Any | similarity_score |
| `TAGGED_WITH` | Any → Tag | - |

### 2.3 Schema 注册机制

```yaml
# config/schema.yaml
schemas:
  # 对齐 KnowledgeGraph
  - name: Paper
    source: KnowledgeGraph
    version: "1.0"
    extends: false
    
  # data-collector 扩展
  - name: Patent
    source: data-collector
    version: "1.0"
    extends: false
    
  - name: BlogPost
    source: data-collector
    version: "1.0"
    extends: false

# 字段对齐规则
alignment:
  Paper.title: {type: string, required: true}
  Paper.doi: {type: string, unique: true}
  Patent.id: {type: string, unique: true}
```

---

## 3. 技能分层架构（更新版）

```
┌─────────────────────────────────────────────────────────────────┐
│                    应用层（技能编排）                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DC-Researcher 技能                                              │
│  (递归协调器，管理方向队列)                                       │
│         │                                                       │
│         ▼ 调用 (并行)                                            │
│  DC-Collector 技能 × N                                           │
│  (单方向采集协调器)                                              │
│         │                                                       │
│         ▼ 调用 (并行)                                            │
│  DC-Source-* 技能 × M                                            │
│  (具体来源：arXiv/ACL/Kaggle/Google Patents...)                  │
│                                                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    数据接入层 (dc-data-api)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Schema 管理  │  │ 去重检测    │  │ 增量添加    │             │
│  │ (Registry)  │  │ (Dedup)     │  │ (Upsert)    │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ 版本管理    │  │ 访问控制    │  │ 查询接口    │             │
│  │(Versioning) │  │   (ACL)     │  │  (Query)    │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   SQLite        │ │   ChromaDB      │ │   (未来)        │
│ (原型阶段)      │ │ (向量索引)      │ │   UniDAG-Store  │
│                 │ │                 │ │   (KnowledgeGraph)│
│ - papers        │ │ - embeddings    │ │ - 图存储        │
│ - patents       │ │ - similarity    │ │ - 关系查询      │
│ - datasets      │ │ - search        │ │ - SOTA 演进     │
│ - blogs         │ │                 │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## 4. 技能列表（完整版）

| 技能层级 | 技能名称 | 用途 | 调用示例 |
|---------|---------|------|---------|
| **应用层** | `dc-researcher` | 递归研究协调器 | `skill_use dc-researcher domain="AI Agent"` |
| **应用层** | `dc-collector` | 单方向采集协调器 | `skill_use dc-collector domain="AI Agent" subdomain="LLM"` |
| **来源层** | `dc-source-arxiv` | arXiv 采集 | （内部调用） |
| **来源层** | `dc-source-acl` | ACL 采集 | （内部调用） |
| **来源层** | `dc-source-kaggle` | Kaggle 采集 | （内部调用） |
| **来源层** | `dc-source-patents` | 专利采集 | （内部调用） |
| **来源层** | `dc-source-blogs` | 博客采集 | （内部调用） |
| **数据层** | `dc-data-api` | 统一数据接入 | `skill_use dc-data-api action=upsert schema=paper` |
| **查询层** | `dc-query` | AI 对话查询 | `skill_use dc-query "LLM 有哪些论文？"` |
| **展示层** | `dc-mkdocs` | MkDocs 可视化 | `skill_use dc-mkdocs build` |
| **配置层** | `dc-config` | 配置管理 | `skill_use dc-config add-domain` |

---

## 5. 去重策略（4 层检测）

```python
# dc-data-api 内部逻辑
def dedup_check(schema, data):
    # 层级 1: 精确匹配（主键/唯一键）
    if exists(schema, data['id']):
        return {'is_duplicate': True, 'reason': 'id_exists'}
    
    # 层级 2: 业务键匹配（如 title+authors）
    for dedup_key in schema.dedup_keys:
        if exists(schema, **extract_keys(data, dedup_key)):
            return {'is_duplicate': True, 'reason': 'business_key_match'}
    
    # 层级 3: 向量相似度（标题/摘要嵌入）
    embedding = embed(data['title'] + data['abstract'])
    similar = chroma.query(embedding, threshold=0.95)
    if similar:
        return {'is_duplicate': True, 'reason': 'semantic_similar', 'similar_items': similar}
    
    # 层级 4: MinHash 模糊匹配（全文）
    if minhash_similarity(data['content']) > 0.9:
        return {'is_duplicate': True, 'reason': 'fuzzy_match'}
    
    return {'is_duplicate': False}
```

---

## 6. 任务分解（整合 KnowledgeGraph 后）

| Phase | 任务 | 说明 | 预计时间 |
|-------|------|------|---------|
| **Phase 0** | DC-Data-API 设计 | Schema 定义 + 去重接口 | 2 小时 |
| **Phase 1** | 基础架构 | 项目目录 + SQLite 原型 + dc-data-api | 3 小时 |
| **Phase 2** | Collector 核心 | 来源技能 + 多源搜索 | 4 小时 |
| **Phase 3** | Researcher 核心 | 递归调用 + 方向队列 | 3 小时 |
| **Phase 4** | 向量索引 | ChromaDB 集成 | 2 小时 |
| **Phase 5** | AI 查询 | DC-Query 技能 | 2 小时 |
| **Phase 6** | MkDocs | 可视化生成 + ACN 对接 | 2 小时 |
| **Phase 7** | 集成测试 | 端到端测试 | 2 小时 |
| **Phase 8** | KnowledgeGraph 对接 | UniDAG-Adapter 集成 | 待 KnowledgeGraph 完成 |

**总预计**: 20 小时（Phase 8 除外）

---

## 7. 与 KnowledgeGraph 实施对齐

### 7.1 依赖关系

```
KnowledgeGraph Phase 1 (存储层) ──→ data-collector Phase 8 (UniDAG 对接)
         │                                    │
         │ 2 周                               │ 等待中
         ▼                                    ▼
   data-collector Phase 1-7 (独立实施)  ──→ 迁移到 UniDAG-Store
```

### 7.2 经验反哺

data-collector 实施过程中，为 KnowledgeGraph 提供：

1. **去重策略实践** — 4 层检测的实际效果数据
2. **增量添加模式** — Upsert 的边界情况处理
3. **Schema 演进经验** — 如何平滑添加新实体类型
4. **查询模式总结** — 常见查询类型，指导 UniDAG-Store 索引设计

### 7.3 迁移路径

```
阶段 1: SQLite 原型
  ↓ (验证采集流程)
阶段 2: SQLite + ChromaDB
  ↓ (KnowledgeGraph UniDAG-Store 完成)
阶段 3: UniDAG-Adapter → UniDAG-Store
  ↓ (稳定运行)
阶段 4: 完全迁移，废弃 SQLite
```

---

## 8. 下一步行动

### 8.1 架构循环收尾

- [ ] 派给 OpenCode 生成标准化文档
- [ ] 对比评审（mynotes vs 编码仓库）
- [ ] acf-sync 同步

### 8.2 编码循环准备

```bash
# 创建项目目录
mkdir -p /workspace/data-collector/{config,output,state,skills,docs/architecture,.acf/status}

# 初始化 ACF 结构
/workspace/acf-workflow/scripts/init-acf-structure.sh /workspace/data-collector

# 创建 KnowledgeGraph 对接记录
cat > /workspace/data-collector/docs/architecture/KNOWLEDGEGRAPH-INTEGRATION.md << 'EOF'
# KnowledgeGraph 整合计划

**状态**: 等待 KnowledgeGraph Phase 1 完成

**当前存储**: SQLite + ChromaDB（原型）
**目标存储**: UniDAG-Store（知识图谱）

**依赖**: KnowledgeGraph Phase 1 (存储层)
**预计开始**: 2026-04-06 (KnowledgeGraph M1 里程碑)
EOF
```

### 8.3 第一个任务

```bash
skill_use acf-executor \
  task="Task 001: 创建项目目录 + 配置模板 + DC-Data-API 设计" \
  cwd="/workspace/data-collector"
```

---

**版本**: v0.3（整合 KnowledgeGraph）  
**状态**: ✅ 架构已批准，待进入编码循环  
**评审人**: Suhua  
**评审时间**: 2026-03-31 15:20

---

**关键决策**:
1. data-collector 定位为 KnowledgeGraph 的"数据采集前端"
2. 存储层先实现 SQLite 原型，后迁移到 UniDAG-Store
3. Schema 对齐 KnowledgeGraph，扩展 Patent/Blog 等类型
4. 实施经验反哺 KnowledgeGraph 项目
