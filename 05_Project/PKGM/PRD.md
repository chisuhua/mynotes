# PRD — PKGM (Personal Knowledge Graph Management)

**版本**: V1.1 (已评审)  
**日期**: 2026-04-13  
**作者**: CTO (Suhua 技术顾问)  
**状态**: ✅ PRD 已确认，进入 ADR 阶段  

---

## 1. 产品概述

### 1.1 一句话定义

> PKGM 是一个 **Agent 驱动的个人知识图谱管理系统**，它读取外部素材和你的原创思考，自动生成结构化、可溯源、可检索的 Wiki 知识库。

### 1.2 核心定位

| 维度 | 定义 |
|------|------|
| **不是什么** | 又一个笔记应用 / 又一个 Obsidian 替代品 |
| **是什么** | 一个构建和维护个人知识库的 **自动化引擎** |
| **核心理念** | 知识不应该孤立存在，而应该通过图谱关系相互连接、可追溯来源、可验证真伪 |
| **目标用户** | Suhua（首席架构师）—— 需要管理多个技术项目的架构思考和外部研究 |
| **技术栈** | Markdown + YAML + 知识图谱 Schema + LLM Agent + OpenClaw |

### 1.3 与现有系统的关系

```
mynotes/ (现有知识库)
├── 00_Raw_Sources/     ← PKGM 的输入 A（外部素材）
├── 04_Knowledge/       ← PKGM 的输入 B（你的原创）
├── 02_System/          ← PKGM 的配置（Schema / Prompts / Agent 指令）
├── 03_Engine/          ← PKGM 的代码实现
└── 01_Wiki/            ← PKGM 的输出（生成的 Wiki）
```

**PKGM 的工作流**：

```
[00_Raw_Sources] ──┐
                    ├──→ [03_Engine: 抽取 + 关联 + 溯源] ──→ [01_Wiki]
[04_Knowledge]  ────┘                                          ↑
                                                               │
[02_System: Schema + Prompts] ─────────────────────────────────┘
```

---

## 2. 问题陈述

### 2.1 当前痛点

| # | 痛点 | 影响 |
|---|------|------|
| P1 | 大量项目架构文档分散在 mynotes 根目录下，没有统一索引 | 知识孤岛，难以发现关联 |
| P2 | 外部论文/文章与原创思考混在一起，无法区分来源 | 知识可信度无法评估 |
| P3 | 知识之间缺少显式关联 | 无法回答"这个设计参考了哪些论文" |
| P4 | 新知识需要手动整理和链接 | 维护成本高，容易遗漏 |
| P5 | 矛盾/过时的知识无法自动发现 | 可能基于错误知识做决策 |

### 2.2 解决目标

| 目标 | 衡量指标 |
|------|---------|
| 知识可溯源 | 100% Wiki 条目标注来源类型 |
| 知识可关联 | > 80% 的概念有至少 2 个图谱关系 |
| 知识可检索 | 支持语义搜索 + 图谱查询 + 混合检索 |
| 知识可验证 | 冲突知识自动标记，实验记录可追溯 |
| 维护低成本 | 新素材入库后，Wiki 自动生成初稿 |

---

## 3. 用户画像

### 3.1 主要用户：Suhua（架构师）

| 属性 | 描述 |
|------|------|
| **角色** | 首席架构师 / 技术负责人 |
| **技术栈** | C++/CUDA/PTX、Python、Agent 系统 |
| **当前项目** | CortiX, PTX-EMU, BrainSkillForge, UniDAG-Store 等 10+ 项目 |
| **知识需求** | 需要管理技术选型思考、架构设计决策、论文研究成果、代码最佳实践 |
| **痛点** | 时间宝贵，不想手动维护 Wiki 链接和索引 |
| **偏好** | Git-based、Markdown 原生、Agent 自动生成、自己审核确认 |

### 3.2 用户场景

| 场景编号 | 场景描述 | 频率 | 优先级 |
|---------|---------|------|--------|
| UC-01 | 读了一篇论文，希望自动提取核心概念并关联到已有知识 | 每周 2-3 次 | P0 |
| UC-02 | 做了一个架构设计，希望记录并关联到参考论文和实验数据 | 每周 1-2 次 | P0 |
| UC-03 | 问"我的 XX 设计参考了哪些论文"，希望直接得到答案 | 每天 | P0 |
| UC-04 | 发现某个技术知识可能过时了，希望自动检测并提醒 | 每月 | P1 |
| UC-05 | 新加入一个技术方向，希望快速生成该方向的知识地图 | 每月 1-2 次 | P1 |
| UC-06 | 发现两个知识条目说法矛盾，希望系统自动发现并标记 | 偶尔 | P1 |
| UC-07 | 浏览知识库，发现概念之间的隐含关联 | 每天 | P2 |

---

## 4. 功能需求

### 4.1 功能全景图

```
PKGM 功能全景
├── F1. 知识摄取 (Ingest)
│   ├── F1.1 外部素材解析
│   ├── F1.2 原创知识录入
│   └── F1.3 多模态支持
├── F2. 知识图谱构建 (Graph Build)
│   ├── F2.1 实体识别
│   ├── F2.2 关系抽取
│   └── F2.3 溯源标注
├── F3. Wiki 生成 (Wiki Gen)
│   ├── F3.1 概念页面生成
│   ├── F3.2 索引页面维护
│   └── F3.3 冲突标记
├── F4. 知识检索 (Search)
│   ├── F4.1 语义检索
│   ├── F4.2 图谱检索
│   └── F4.3 混合检索
├── F5. 知识维护 (Maintain)
│   ├── F5.1 冲突检测
│   ├── F5.2 过期检测
│   ├── F5.3 链接健康检查
│   └── F5.4 孤儿页面检测
└── F6. 知识展示 (Display)
    ├── F6.1 Wiki 导航
    ├── F6.2 图谱可视化
    └── F6.3 知识健康度仪表板
```

### 4.2 详细功能定义

#### F1. 知识摄取 (Ingest)

| 子功能 | 描述 | 输入 | 输出 | 优先级 |
|--------|------|------|------|--------|
| F1.1 外部素材解析 | 解析 `00_Raw_Sources/` 中的文件（PDF、Markdown、网页） | PDF/MD/URL | 结构化文本 + 元数据 JSON | P0 |
| F1.2 原创知识录入 | 扫描 `04_Knowledge/` 中的设计文档和讨论记录 | Markdown 文档 | 结构化知识条目 | P0 |
| F1.3 多模态支持 | 处理代码片段、图表、视频转录 | 代码文件/图片/文本 | 带描述的 Markdown | P2 |

**F1.1 素材解析规则**：

```yaml
source_type_mapping:
  papers/*.pdf:      source_type: primary,   confidence: 4
  articles/*.md:     source_type: secondary, confidence: 3
  patent/*.md:       source_type: primary,   confidence: 4
  code-snippets/*:   source_type: primary,   confidence: 4
```

**F1.2 原创知识规则**：

```yaml
# 04_Knowledge/ 下所有内容默认为原创
default_source_type: original
default_confidence: 5
default_author: "Suhua"
```

---

#### F2. 知识图谱构建 (Graph Build)

| 子功能 | 描述 | 优先级 |
|--------|------|--------|
| F2.1 实体识别 | 从文本中识别概念、实体、项目、人物等 | P0 |
| F2.2 关系抽取 | 识别实体之间的依赖、启发、实现、验证等关系 | P0 |
| F2.3 溯源标注 | 自动标注每条知识的来源类型和置信度 | P0 |

**实体类型定义**（详见后续 ADR 中的 Schema 决策）：

| 实体 | 来源 | 示例 |
|------|------|------|
| `Concept` | 通用技术概念 | Transformer, CUDA Warp Divergence |
| `Architecture` | 04_Knowledge 原创 | AOS-Universal v3.0, PTX-EMU 架构 |
| `Decision` | 04_Knowledge 原创 | ADR-001: 存储层用 UniDAG |
| `Experiment` | 04_Knowledge 原创 | CUDA 性能测试报告 |
| `Paper` | 00_Raw_Sources | Attention Is All You Need |
| `Method` | 两者皆可 | FlashAttention, MoE |
| `Person` | 两者皆可 | Karpathy, Suhua |
| `Organization` | 两者皆可 | NVIDIA, OpenAI |
| `Project` | 04_Knowledge | CortiX, PTX-EMU |
| `CodePattern` | 两者皆可 | CUDA 合并访问模式 |

**关系类型定义**：

| 关系 | 方向 | 描述 | 示例 |
|------|------|------|------|
| `DEPENDS_ON` | Concept → Concept | 概念依赖 | CUDA Warp Divergence → SIMT Model |
| `INSPIRED_BY` | Architecture → Paper/Concept | 架构灵感来源 | AOS-Universal → Transformer |
| `IMPLEMENTS` | CodePattern → Concept | 代码实现概念 | CUDA Kernel → 并行计算 |
| `VERIFIED_BY` | Concept → Experiment | 概念被实验验证 | 合并访问 → 性能测试报告 |
| `OBSOLETES` | Concept → Concept | 新版本淘汰旧版 | Hopper Memory → Ampere Memory |
| `REFINES` | Concept → Concept | 细化/深化 | Attention → Multi-Query Attention |
| `CONTRADICTS` | Concept → Concept | 矛盾/冲突 | 128-byte vs 64-byte 对齐 |
| `CITES` | Paper → Paper | 引用关系 | 论文 A 引用论文 B |
| `SURPASSES` | Paper → Paper | 超越关系 | 论文 A 超越论文 B |
| `REFUTES` | Paper → Paper | 反驳关系 | 论文 A 反驳论文 B |
| `BELONGS_TO` | Concept → Topic/Project | 归类 | CUDA 概念 → PTX-EMU 项目 |
| `CREATED_BY` | Architecture/Decision → Person | 谁创建的 | AOS-Universal → Suhua |
| `USED_IN` | Concept/Method → Project | 用在哪里 | Transformer → CortiX |

---

#### F3. Wiki 生成 (Wiki Gen)

| 子功能 | 描述 | 输出位置 | 优先级 |
|--------|------|---------|--------|
| F3.1 概念页面 | 为每个识别到的概念生成 Markdown 页面 | `01_Wiki/concepts/` | P0 |
| F3.2 实体页面 | 为人物/组织/项目生成页面 | `01_Wiki/entities/` | P0 |
| F3.3 主题页面 | 为主题生成 MOC (Map of Content) | `01_Wiki/topics/` | P1 |
| F3.4 索引页面 | 维护全局索引 | `01_Wiki/index.md` | P0 |
| F3.5 溯源页面 | 素材摘要页 | `01_Wiki/sources/` | P1 |
| F3.6 冲突标记 | 在页面中标注矛盾知识 | 页面内嵌 | P1 |

**Wiki 页面模板**（概念页面）：

```yaml
---
title: "CUDA Warp Divergence"
created: 2026-04-13
updated: 2026-04-13
source_type: primary              # knowledge provenance
source_ref: "NVIDIA CUDA C Programming Guide, Ch.32"
source_url: "https://docs.nvidia.com/cuda/..."
confidence: 4                     # 1-5 星置信度
verified_by: "experiment"         # 验证方式
verification_date: 2026-04-13
tags: [cuda, gpu, performance]
relations:
  depends_on: "[[SIMT Execution Model]]"
  verified_by: "[[CUDA 性能测试-Warp 发散]]"
  contradicts:                    # 如有矛盾
    - target: "[[旧版 CUDA 对齐策略]]"
      reason: "Hopper 架构行为已改变"
---

## 定义

...

## 我的理解 🧠

...

## 来源 📖

> 来源: [[primary]] NVIDIA CUDA C Programming Guide

## 关联

- [[SIMT Execution Model]] (DEPENDS_ON)
- [[CUDA 性能测试-Warp 发散]] (VERIFIED_BY)
```

---

#### F4. 知识检索 (Search)

| 子功能 | 描述 | 检索策略 | 优先级 |
|--------|------|---------|--------|
| F4.1 语义检索 | 自然语言查询，返回语义相关页面 | 向量搜索 | P1 |
| F4.2 图谱检索 | 基于关系遍历查询 | 图谱遍历 | P0 |
| F4.3 混合检索 | 语义 + 图谱 + 元数据过滤 | 多路召回 | P1 |

**检索场景示例**：

| 用户查询 | 检索策略 | 返回内容 |
|---------|---------|---------|
| "什么是 CUDA Warp Divergence？" | 语义 + 关键词 | 概念定义页面 |
| "AOS-Universal 参考了哪些论文？" | 图谱遍历 INSPIRED_BY | 关联的 Paper 列表 |
| "哪些知识还没有验证过？" | 元数据过滤 confidence < 4 | 待验证条目列表 |
| "有没有互相矛盾的知识？" | 图谱遍历 CONTRADICTS | 冲突知识对 |
| "PTX-EMU 项目用到了哪些技术？" | 图谱遍历 USED_IN 反向 | 概念/方法列表 |

---

#### F5. 知识维护 (Maintain)

| 子功能 | 描述 | 触发方式 | 优先级 |
|--------|------|---------|--------|
| F5.1 冲突检测 | 检测互相矛盾的知识条目 | 入库时自动 + 定期扫描 | P1 |
| F5.2 过期检测 | 检测可能被推翻/过时的知识 | 定期扫描（每周） | P1 |
| F5.3 链接健康 | 检查断链和孤儿页面 | 定期扫描（每周） | P1 |
| F5.4 溯源完整性 | 检查缺少来源标注的条目 | 定期扫描（每周） | P1 |

**维护报告模板**：

```markdown
## 🔍 知识健康度报告 (2026-04-13)

| 指标 | 数值 | 状态 |
|------|------|------|
| 总条目数 | 156 | - |
| 已验证 | 89 (57%) | ✅ |
| 待验证 | 45 (29%) | ⚠️ |
| 存疑/冲突 | 3 (2%) | ❌ |
| 孤儿页面 | 2 (1%) | ⚠️ |
| 断链数 | 5 | ⚠️ |
| 溯源完整率 | 94% | ✅ |
```

---

#### F6. 知识展示 (Display)

| 子功能 | 描述 | 优先级 |
|--------|------|--------|
| F6.1 Wiki 导航 | index.md + MOC 页面导航 | P0 |
| F6.2 图谱可视化 | 可选：MkDocs + Mermaid 或 Obsidian 图谱 | P2 |
| F6.3 健康度仪表板 | index.md 顶部的知识健康度概览 | P1 |

---

## 5. 非功能需求

| 需求 | 描述 |
|------|------|
| **Git-based** | 所有内容用 Git 版本控制，不引入外部数据库 |
| **Markdown 原生** | 输出为标准 Markdown，可在任何编辑器中打开 |
| **Agent 驱动** | 核心能力是 AI Agent 自动处理，非手动操作 |
| **人机协同** | Agent 生成初稿，人工审核确认后才定稿 |
| **增量更新** | 新素材入库不重建全量 Wiki，只更新受影响部分 |
| **可扩展** | Schema 支持扩展新实体类型和关系类型 |
| **可追溯** | 所有自动生成的内容标注来源和置信度 |

---

## 6. 目录结构（已确认版）

```
mynotes/
│
├── 00_Raw_Sources/          # 📥 外部素材（只读，不修改）
│   ├── articles/            #   文章/博客
│   ├── papers/              #   学术论文 PDF
│   ├── patent/              #   专利文档
│   └── code-snippets/       #   有参考价值的代码片段
│
├── 01_Wiki/                 # 📚 PKGM 输出（Agent 自动生成）
│   ├── index.md             #   全局索引 + 健康度仪表板
│   ├── concepts/            #   概念定义
│   ├── entities/            #   人物/组织/项目
│   ├── topics/              #   主题综述 (MOC)
│   └── sources/             #   素材摘要页
│
├── 02_System/               # ⚙️ 系统配置
│   ├── schema.yaml          #   知识图谱 Schema
│   ├── provenance-schema.md #   溯源体系定义
│   ├── CLAUDE.md            #   Agent 角色指令
│   └── prompts/             #   Prompt 模板
│       ├── ingest.md
│       ├── extract.md
│       ├── link.md
│       ├── verify.md
│       └── evolve.md
│
├── 03_Engine/               # 🔧 自动化引擎（代码，Phase 2+）
│   ├── ingest.py            #   素材解析
│   ├── extract.py           #   实体/关系抽取
│   ├── graph.py             #   图谱构建
│   ├── wiki_gen.py          #   Wiki 生成
│   └── scan.py              #   健康扫描
│
├── 04_Knowledge/            # 🧠 原创知识（按知识领域划分，Suhua 创作）
│   ├── 01_GPU_Architecture/
│   │   ├── generations/         # GPU 代际演进
│   │   ├── microarchitecture/   # 微架构组件
│   │   ├── processors/          # 具体 GPU 型号
│   │   └── programming-models/  # 编程模型
│   ├── 02_CPU_Architecture/
│   │   ├── isa/                 # 指令集架构
│   │   ├── microarchitecture/   # 微架构
│   │   └── processors/          # 具体 CPU 型号
│   ├── 03_Memory_System/
│   │   ├── types/               # 存储类型
│   │   ├── concepts/            # 核心概念
│   │   └── optimization/        # 优化技术
│   ├── 04_Cache_Coherence/
│   │   ├── protocols/           # 一致性协议
│   │   ├── gpu-cache/           # GPU 缓存
│   │   └── challenges/          # 挑战与方案
│   ├── 05_Interconnect/
│   │   ├── protocols/           # 互联协议
│   │   ├── topologies/          # 拓扑结构
│   │   └── optimization/        # 优化
│   ├── 06_Compiler/
│   │   ├── frontend/            # 前端
│   │   ├── optimization/        # 优化
│   │   ├── gpu-compilers/       # GPU 编译
│   │   └── backends/            # 后端
│   ├── 07_AI_Accelerator/
│   │   ├── architectures/       # 加速器架构
│   │   ├── design/              # 设计原理
│   │   └── comparison/          # 对比分析
│   ├── 08_Distributed_Training/
│   │   ├── parallelism/         # 并行策略
│   │   ├── collectives/         # 集合通信
│   │   └── frameworks/          # 框架
│   ├── 09_Simulators/
│   │   ├── cpu-simulators/      # CPU 仿真
│   │   ├── gpu-simulators/      # GPU 仿真
│   │   ├── methodology/         # 仿真方法
│   │   └── ptx-emu/             # PTX 仿真
│   ├── 10_Hardware_Design/
│   │   ├── rtl/                 # RTL 设计
│   │   ├── verification/        # 验证
│   │   └── fpga/                # FPGA
│   ├── 11_Drivers_OS/
│   │   ├── linux-kernel/        # Linux 内核
│   │   ├── device-drivers/      # 设备驱动
│   │   └── cuda-driver/         # CUDA 驱动
│   └── 12_CUDA_Ecosystem/
│       ├── libraries/           # CUDA 库
│       ├── frameworks/          # 框架集成
│       └── tools/               # 工具
│
├── 05_Project/              # 📦 项目知识（Suhua 逐步添加）
│   # 占位，内容后续添加
│
├── CortiX/                  # 📦 各项目（现有，不迁移、不创建符号链接）
├── PTX-EMU/
├── BrainSkillForge/
└── ...
```

**目录设计原则**：
- `04_Knowledge` 按**知识领域**（而非项目）组织，便于跨项目复用
- `05_Project` 按**具体项目**组织，记录项目专属知识
- 根目录下的现有项目文档**保持不变**，不迁移，不创建符号链接
- `04_Knowledge` 和 `05_Project` 的内容由 Suhua 逐步添加

---

## 7. 阶段规划

### Phase 1: 基础建设（1-2 周）

| 任务 | 交付物 | 优先级 |
|------|--------|--------|
| 创建目录结构 | 01_Wiki, 04_Knowledge, 03_Engine | P0 |
| 定义 Schema | `02_System/schema.yaml` | P0 |
| 定义溯源体系 | `02_System/provenance-schema.md` | P0 |
| 生成 Wiki 骨架 | index.md + 空目录 | P0 |
| 扫描现有项目 | 将 mynotes 根目录项目文档归类到 04_Knowledge | P1 |

### Phase 2: Agent 管线（2-3 周）

| 任务 | 交付物 | 优先级 |
|------|--------|--------|
| 素材解析 Pipeline | ingest.py | P0 |
| 实体/关系抽取 | extract.py + Prompts | P0 |
| Wiki 自动生成 | wiki_gen.py | P0 |
| 索引自动维护 | index.md 自动生成 | P0 |
| 冲突检测 | scan.py (冲突部分) | P1 |

### Phase 3: 检索与展示（2-3 周）

| 任务 | 交付物 | 优先级 |
|------|--------|--------|
| 语义检索 | search.py (向量部分) | P1 |
| 图谱检索 | search.py (图谱部分) | P1 |
| 健康扫描全功能 | scan.py (全功能) | P1 |
| MkDocs 展示 | 可选静态站点 | P2 |

---

## 8. 决策记录（已确认）

以下决策已由老板确认，将写入后续 ADR 文档：

| # | 决策点 | 决策结果 | 状态 |
|---|--------|---------|------|
| D-01 | 04_Knowledge 目录组织 | **按知识领域划分**，12 个一级目录，二级/三级由 CTO 推荐 | ✅ 已确认 |
| D-02 | 图谱存储方式 | **Phase 1 纯 Markdown**，YAML frontmatter 存储关系 | ✅ 已确认 |
| D-03 | Agent 触发方式 | **两者结合**：文件监听处理新素材 + Cron 定期扫描 | ✅ 已确认 |
| D-04 | 语义检索 | **Phase 1 不做**，先用纯图谱关系满足核心需求 | ✅ 已确认 |
| D-05 | 现有项目文档 | **不迁移，不创建符号链接**，保持原样 | ✅ 已确认 |
| D-06 | Wiki 页面格式 | **YAML frontmatter + Obsidian 兼容格式**（[[wikilink]]） | ✅ 已确认 |

### 新增决策

| # | 决策点 | 决策结果 | 状态 |
|---|--------|---------|------|
| D-07 | 新增 05_Project 目录 | **创建占位**，内容后续由 Suhua 添加 | ✅ 已确认 |

---

## 9. 术语表

| 术语 | 定义 |
|------|------|
| **PKGM** | Personal Knowledge Graph Management，个人知识图谱管理 |
| **Provenance** | 知识溯源，记录知识从哪里来、经过谁的加工 |
| **Confidence** | 置信度，1-5 星，表示知识的可信程度 |
| **MOC** | Map of Content，主题地图/索引页 |
| **ADR** | Architecture Decision Record，架构决策记录 |
| **Ingest** | 知识摄取，将原始素材转化为结构化知识 |
| **Entity** | 实体，知识图谱中的节点（概念/人物/项目等） |
| **Relation** | 关系，知识图谱中的边（依赖/启发/验证等） |
| **孤儿页面** | 没有任何入链的 Wiki 页面 |

---

## 10. 修订历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-04-13 | V1.0 Draft | 初始版本，基于 Karpathy 理念 + KnowledgeGraph 架构 + 溯源体系 |

---

`// -- CTO 输出，待老板评审 --`