# PKGM 溯源体系规格

**版本**: V1.0  
**日期**: 2026-04-14  
**状态**: ✅ Active

---

## 1. 核心概念

溯源（Provenance）在 PKGM 中解决三个根本问题：

| 问题 | 说明 | PKGM 解法 |
|------|------|---------|
| **从哪来** | 每条知识的原始出处 | 四级来源分类（original/primary/secondary/tertiary） |
| **怎么变** | 知识被加工、提炼、关联的完整链条 | created_by/updated_by + transformation_chain（Phase 2） |
| **信多少** | 基于来源、验证状态、时间新鲜度的可信度 | 置信度计算（1-5 星） |

---

## 2. 来源类型定义

### 2.1 四级分类

| 类型 | 定义 | 默认置信度 | 示例 |
|------|------|-----------|------|
| **original** | Suhua 的原创思考、设计决策、实验结论 | 5 | 06_Mynotes 下的架构文档 |
| **primary** | 一手资料：官方文档、原始论文、专利、源码 | 4 | NVIDIA 编程指南、arXiv 论文 |
| **secondary** | 对一手资料的解读：技术博客、综述文章、教程 | 3 | 知乎技术文章、CSDN 教程 |
| **tertiary** | 二次以上转述：百科摘要、AI 总结、口头转述 | 2 | Wikipedia、ChatGPT 总结 |

### 2.2 自动映射规则

Agent 在摄取知识时，按文件路径自动判定 `source_type`：

```yaml
source_type_auto_rules:
  "00_Raw_Sources/papers/*.pdf":     primary
  "00_Raw_Sources/articles/*.md":    secondary
  "00_Raw_Sources/patent/*.md":      primary
  "00_Raw_Sources/code-snippets/*":  primary
  "06_Mynotes/**":                   original
  "04_Knowledge/**":                 primary        # 从外部素材提取
  "AI 提取摘要 (未人工确认)":         tertiary
  "人工确认后的 AI 提取":             primary        # 经过人工确认后升级
```

---

## 3. 置信度计算规则

### 3.1 基础分

```
original   → 5
primary    → 4
secondary  → 3
tertiary   → 2
```

### 3.2 修正因子

| 条件 | 修正 | 说明 | 上限/下限 |
|------|------|------|---------|
| `verification.status == "verified"` | +1 | 经过实验/交叉验证 | 上限 5 |
| `verification.status == "refuted"` | -1 | 已被证伪 | - |
| 超过 2 年未更新 | -1 | 可能过时 | - |
| 3+ 个独立来源交叉印证 | +0.5 | 共识度高 | - |
| 存在未解决的 CONTRADICTS 关系 | -0.5 | 有争议 | - |

### 3.3 计算公式

```
confidence = base_score + sum(modifiers)

其中：
- base_score = source_type 对应的基础分
- modifiers = 所有适用的修正因子
- 最终结果四舍五入到整数（1-5）
```

### 3.4 人工覆盖

Suhua 可随时手动修改 `confidence` 值，手动值优先级高于自动计算。

```yaml
# 手动覆盖示例
confidence: 5  # 即使自动计算为 4，人工确认后可改为 5
```

---

## 4. 验证状态机

### 4.1 状态定义

| 状态 | 含义 | 触发条件 |
|------|------|---------|
| `unverified` | 默认状态，未经检验 | Agent 自动提取后 |
| `pending` | 有待验证，已标记可疑 | 冲突检测发现矛盾 |
| `verified` | 已通过实验或交叉验证 | 人工确认/实验支撑 |
| `refuted` | 已被证伪 | 新证据推翻原有结论 |

### 4.2 状态流转

```
unverified ──(实验/审查)──→ verified
     │                          │
     │                          │ (发现错误)
     │                          ↓
     │                       refuted
     │
     └──(冲突检测)──→ pending ──(确认错误)──→ refuted
```

### 4.3 验证方法

| 方法 | 说明 | 适用场景 |
|------|------|---------|
| `experiment` | 通过实验验证 | 性能优化、技术可行性 |
| `peer_review` | 同行评审 | 架构设计、技术选型 |
| `cross_reference` | 交叉引用验证 | 外部知识溯源 |
| `logical_deduction` | 逻辑推导 | 理论分析 |

---

## 5. 生命周期管理

### 5.1 状态定义

| 状态 | 含义 | 关联关系 |
|------|------|---------|
| `active` | 当前有效 | — |
| `superseded` | 被新版本替代 | 自动建立 `OBSOLETES` 边指向新版本 |
| `deprecated` | 不再推荐使用 | 保留页面但标记警告 |
| `refuted` | 结论被推翻 | 自动建立 `CONTRADICTS` 或 `REFUTES` 边 |

### 5.2 状态流转

```
active ──(新版本发布)──→ superseded ──(时间推移)──→ deprecated
   │                                              │
   │ (发现错误)                                   │
   ↓                                              ↓
refuted ←─────────────────────────────────────────┘
```

---

## 6. 知识加工链（Transformation Chain）

### 6.1 Phase 1 简化版

仅记录创建者和更新者：

```yaml
created: 2026-04-14
created_by: "agent/ingest"
updated: 2026-04-14
updated_by: "agent/link"
```

### 6.2 Phase 2 完整版

完整记录知识从原材料到当前状态的每一步转换：

```yaml
provenance:
  transformation_chain:
    - step: 1
      action: "extracted"
      actor: "agent/ingest"
      timestamp: "2026-04-14T10:30:00+08:00"
      input: "00_Raw_Sources/papers/attention.pdf"
      output: "04_Knowledge/01_GPU_Architecture/transformer-draft.md"
    - step: 2
      action: "reviewed"
      actor: "Suhua"
      timestamp: "2026-04-14T14:00:00+08:00"
      changes: "修正了注意力机制的公式描述"
      output: "04_Knowledge/01_GPU_Architecture/transformer-reviewed.md"
    - step: 3
      action: "refined"
      actor: "agent/link"
      timestamp: "2026-04-14T14:05:00+08:00"
      changes: "添加了 DEPENDS_ON -> [[Positional Encoding]] 关系"
      output: "01_Wiki/concepts/transformer.md"
```

---

## 7. 证据链接（Evidence Linking）

### 7.1 关系级证据

对于有属性的关系（如 SURPASSES、VERIFIED_BY），携带证据引用：

```yaml
relations:
  surpasses:
    - target: "[[Mistral-7B]]"
      metric: "MMLU Score"
      value_delta: "+5.2%"
      evidence:
        quote: "LLaMA-3 achieves 79.5% on MMLU, compared to Mistral-7B's 74.3%"
        source: "00_Raw_Sources/papers/llama3.pdf"
        page: 12
        table: "Table 3"
        confidence: 0.95
  
  verified_by:
    - target: "[[PTX-EMU: Warp Divergence 性能测试]]"
      result: "confirmed"
      evidence:
        quote: "测试结果显示 warp divergence 导致性能下降约 40%"
        source: "04_Knowledge/09_Simulators/ptx-emu/benchmarks/warp-div-test.md"
        date: "2026-04-14"
```

### 7.2 Phase 1 简化

Phase 1 仅记录到文件级，Phase 2 支持页码/表格级：

```yaml
# Phase 1
evidence:
  source: "00_Raw_Sources/papers/llama3.pdf"

# Phase 2
evidence:
  source: "00_Raw_Sources/papers/llama3.pdf"
  page: 12
  table: "Table 3"
```

---

## 8. 溯源字段在 Frontmatter 中的位置

```yaml
---
title: "页面标题"
type: concept

# === 溯源核心字段 ===
source_type: primary
source_ref: "NVIDIA CUDA C Programming Guide, Ch.32"
source_url: "https://docs.nvidia.com/cuda/..."
confidence: 4

# === 验证状态 ===
verification:
  status: "unverified"

# === 生命周期 ===
lifecycle:
  status: "active"

# === 创建/更新 ===
created: 2026-04-14
created_by: "agent/ingest"
updated: 2026-04-14
updated_by: "agent/ingest"

# === 其他字段 ===
tags: [cuda, gpu, performance]
relations:
  depends_on:
    - "[[SIMT Execution Model]]"
---
```

---

## 9. 使用示例

### 9.1 外部论文提取

```yaml
---
title: "Attention Is All You Need"
type: paper
source_type: primary
source_ref: "Vaswani et al., NeurIPS 2017"
source_doi: "10.48550/arXiv.1706.03762"
confidence: 4
verification:
  status: "unverified"
lifecycle:
  status: "active"
created: 2026-04-14
created_by: "agent/ingest"
---
```

### 9.2 原创架构设计

```yaml
---
title: "AOS-Universal v3.0"
type: architecture
source_type: original
source_ref: "Suhua 原创设计"
confidence: 5
verification:
  status: "verified"
  method: "peer_review"
  verified_by: "Suhua"
  verified_date: "2026-04-14"
lifecycle:
  status: "active"
created: 2026-04-14
created_by: "Suhua"
updated: 2026-04-14
updated_by: "Suhua"
---
```

### 9.3 实验验证报告

```yaml
---
title: "CUDA 合并访问性能测试"
type: experiment
source_type: original
source_ref: "PTX-EMU 实验记录"
confidence: 5
verification:
  status: "verified"
  method: "experiment"
  verified_by: "Suhua"
  verified_date: "2026-04-14"
lifecycle:
  status: "active"
created: 2026-04-14
created_by: "Suhua"
---
```

---

## 10. 修订历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-04-14 | V1.0 | 初始版本，基于 ADR-002 |

---

`// -- PKGM Provenance Schema V1.0 --`
