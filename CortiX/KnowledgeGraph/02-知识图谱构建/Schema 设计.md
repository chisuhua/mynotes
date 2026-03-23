# Schema 设计

**来源**: 从 `../知识图谱构建.md` 提炼  
**最后更新**: 2026-03-23  
**状态**: 架构评审中

---

## 🏗️ 核心设计理念：3W + 3C 原则

1. **贴合业务 (Business-Aligned)** — 只定义对"科研分析"有用的实体和关系
2. **支持演进 (Evolution-Ready)** — 必须能表达"时间"和"版本"概念，支持 SOTA 更替分析
3. **机器可读 (Machine-Readable)** — 属性类型要明确（数字、字符串、布尔值）

---

## 📐 Schema 设计方案 (V1.0)

### 实体类型 (Entity Types / Nodes)

| 实体类型 | 英文标识 | 核心属性 | 描述与用途 |
|---|---|---|---|
| **文献** | `Paper` | `title`, `year`, `doi`, `venue`, `pdf_url`, `abstract`, `status` (active/deprecated), `sota_metrics` (JSON) | 核心节点。`status` 用于标记是否被推翻 |
| **作者** | `Author` | `name`, `affiliation`, `orcid_id` | 用于分析作者合作网络 |
| **研究任务/领域** | `Task` | `name` (如 "Image Classification"), `dataset_scope` | 用于归类。SOTA 通常是针对特定 Task 的 |
| **数据集** | `Dataset` | `name`, `domain`, `url` | 很多 SOTA 是基于特定数据集的 |
| **评价指标** | `Metric` | `name` (如 "Accuracy"), `direction` (higher_is_better) | 用于量化比较 |
| **技术方法** | `Method` | `name` (如 "Transformer"), `category` | 用于分析技术路线演进 |
| **机构/组织** | `Organization` | `name`, `type` (University/Company) | 归属分析 |

### 关系类型 (Relationship Types / Edges)

| 关系类型 | 英文标识 | 方向 | 属性 | 业务含义 |
|---|---|---|---|---|
| **撰写** | `WRITTEN_BY` | Paper → Author | `order` (第几作者) | 基础关系 |
| **引用** | `CITES` | Paper → Paper | `context_snippet`, `count` | 基础学术网络 |
| **超越/改进** | `SURPASSES` | Paper → Paper | `metric_name`, `improvement_delta`, `dataset` | **核心！** 用于构建 SOTA 演进链 |
| **反驳/争议** | `REFUTES` | Paper → Paper | `reason`, `confidence` | **核心！** 用于冲突检测预警 |
| **提出方法** | `PROPOSES_METHOD` | Paper → Method | - | 技术归因 |
| **使用数据集** | `USES_DATASET` | Paper → Dataset | `split` (train/test) | 实验环境关联 |
| **评测指标** | `ACHIEVES_METRIC` | Paper → Metric | `value` (数值), `dataset` | **关键！** 用于 SOTA 对比 |
| **属于领域** | `BELONGS_TO` | Paper/Method → Task | - | 分类导航 |

---

## 🛠️ Schema 设计实战步骤 (5 步法)

### 第一步：业务场景反推 (Backward Design)
问自己：**"我要回答什么问题？"**
- "过去 3 年 ImageNet 分类的 SOTA 是谁？" → 需要 `ACHIEVES_METRIC` 关系携带 `value` 和 `dataset` 属性
- "哪篇论文推翻了 ResNet 的某个结论？" → 必须设计 `REFUTES` 关系

### 第二步：利用 LLM 辅助生成草稿
将业务文档发给 LLM，让它生成 Schema 草稿

### 第三步：定义属性约束 (Constraints)
- 类型约束：`year` 必须是整数，`doi` 必须是字符串且唯一
- 必填项：`Paper` 必须有 `title` 和 `year`
- 枚举值：`status` 只能是 `['active', 'deprecated', 'retracted']`

### 第四步：可视化建模
使用 Draw.io / Excalidraw / Arrows.app 画出草图

### 第五步：小样本验证 (Pilot Test)
手动标注 5-10 篇论文，尝试写查询语句验证是否能查出想要的结果

---

## 💡 特殊设计建议

### 处理"动态 SOTA"的 Schema 技巧
SOTA 是相对的。不要在 `Paper` 节点上直接写 `is_sota: true`（因为明天可能就变了）。

**正确做法**：在 `SURPASSES` 关系中记录：
```
(PaperA)-[SURPASSES {metric: 'Acc', val: 0.9, on_dataset: 'ImageNet'}]->(PaperB)
```
查询时动态计算"当前最大值"，而不是静态存储标签。

### 处理"结论冲突"的 Schema 技巧
- 在 `REFUTES` 关系上增加 `evidence_snippet` 属性，存储原文中反驳的那句话
- 在 `Paper` 节点增加 `controversy_level` (0-10) 属性，由 Agent 根据被反驳的次数自动计算更新

---

## 📝 Schema 代码示例 (Cypher 风格)

```cypher
// 1. 创建约束
CREATE CONSTRAINT paper_doi IF NOT EXISTS FOR (p:Paper) REQUIRE p.doi IS UNIQUE;
CREATE CONSTRAINT author_orcid IF NOT EXISTS FOR (a:Author) REQUIRE a.orcid_id IS UNIQUE;

// 2. 插入示例数据
MERGE (p1:Paper {doi: "10.1000/paper1", title: "Deep Residual Learning", year: 2015, status: "active"})
MERGE (p2:Paper {doi: "10.1000/paper2", title: "EfficientNet-B7", year: 2019, status: "active"})
MERGE (t:Task {name: "Image Classification"})
MERGE (d:Dataset {name: "ImageNet"})
MERGE (m:Metric {name: "Top-1 Accuracy", direction: "higher"})

// 建立基础关系
MERGE (p1)-[:BELONGS_TO]->(t)
MERGE (p1)-[:USES_DATASET]->(d)
MERGE (p1)-[:ACHIEVES_METRIC {value: 0.76, dataset: "ImageNet"}]->(m)

MERGE (p2)-[:BELONGS_TO]->(t)
MERGE (p2)-[:USES_DATASET]->(d)
MERGE (p2)-[:ACHIEVES_METRIC {value: 0.844, dataset: "ImageNet"}]->(m)

// 建立核心的 SOTA 演进关系
MERGE (p2)-[:SURPASSES {
    metric: "Top-1 Accuracy", 
    value_delta: 0.084, 
    dataset: "ImageNet", 
    claim: "Our model outperforms ResNet by 8.4%"
}]->(p1)
```

---

## 📊 多模态证据扩展 (Evidence-Level Schema)

### 新增实体类型

| 实体类型 | 英文标识 | 核心属性 | 描述 |
|---|---|---|---|
| **图表/可视化** | `Visualization` | `type`, `caption`, `page_num`, `image_url`, `bbox`, `data_json`, `confidence` | 代表论文中的每一个 Figure |
| **表格** | `Table` | `caption`, `page_num`, `html_repr`, `data_json`, `has_sota` | 代表论文中的 Table |
| **模型组件/模块** | `Module` | `name`, `function`, `input_type`, `output_type` | 从架构图中提取 |

### 新增关系类型

| 关系类型 | 方向 | 属性 | 业务含义 |
|---|---|---|---|
| **包含图表** | `Paper` → `Visualization` | `figure_id` | 建立论文与具体图表的关联 |
| **包含表格** | `Paper` → `Table` | `table_id` | 建立论文与具体表格的关联 |
| **数据源自** | `Achievement` → `Visualization`/`Table` | `series_name`, `row_idx`, `col_idx` | **关键！** 将指标数值链接到具体图表单元格 |
| **由...组成** | `Method` → `Module` | `connection_type`, `order` | 从架构图解析方法内部结构 |

---

## 📝 文档变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-03-23 | 从原文档提炼 | 精简核心 Schema 设计内容 |

`// -- 🦊 DevMate | Schema 设计提炼完成 --`
