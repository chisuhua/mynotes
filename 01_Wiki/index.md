# PKGM 知识库索引

**最后更新**: 2026-04-14  
**状态**: 🌱 Phase 1 基础建设完成

---

## 📊 知识健康度仪表板

| 指标 | 数值 | 状态 |
|------|------|------|
| 总条目数 | 0 | 🌱 待填充 |
| 已验证 | 0 (0%) | - |
| 待验证 | 0 (0%) | - |
| 存疑/冲突 | 0 (0%) | - |
| 孤儿页面 | 0 | - |
| 断链数 | 0 | - |
| 溯源完整率 | - | - |

---

## 📁 目录导航

### 00_Raw_Sources（原材料）

外部素材库，只读不修改。

| 子目录 | 说明 | 文件数 |
|--------|------|--------|
| `papers/` | 学术论文 PDF | - |
| `articles/` | 技术博客/文章 | - |
| `code-snippets/` | 代码片段 | - |

---

### 01_Wiki（深度咀嚼）

结构化 Wiki，符合 Schema 规范。

| 子目录 | 说明 | 页面数 |
|--------|------|--------|
| `concepts/` | 概念定义 | - |
| `entities/` | 人物/组织/项目 | - |
| `topics/` | 主题综述 (MOC) | - |
| `sources/` | 素材摘要页 | - |

**模板**:
- [概念页面模板](02_System/templates/01-wiki-concept.md)
- [论文页面模板](02_System/templates/01-wiki-paper.md)

---

### 02_System（系统配置）

| 文件 | 说明 |
|------|------|
| [`schema.yaml`](02_System/schema.yaml) | 知识图谱 Schema 定义 |
| [`provenance-schema.md`](02_System/provenance-schema.md) | 溯源体系规格 |
| `templates/` | 页面模板目录 |
| `prompts/` | Prompt 模板目录（Phase 2） |

---

### 03_Engine（自动化引擎）

Phase 2 实现。

| 模块 | 说明 | 状态 |
|------|------|------|
| `ingest.py` | 素材解析 | 📝 Phase 2 |
| `extract.py` | 实体/关系抽取 | 📝 Phase 2 |
| `graph.py` | 图谱构建 | 📝 Phase 2 |
| `wiki_gen.py` | Wiki 生成 | 📝 Phase 2 |
| `scan.py` | 健康扫描 | 📝 Phase 2 |

---

### 04_Knowledge（初步消化）

LLM 初步消化的知识，按研究领域组织。

| 领域 | 说明 | 页面数 |
|------|------|--------|
| `01_GPU_Architecture/` | GPU 架构 | - |
| `02_CPU_Architecture/` | CPU 架构 | - |
| `03_Memory_System/` | 存储系统 | - |
| `04_Cache_Coherence/` | 缓存一致性 | - |
| `05_Interconnect/` | 互联技术 | - |
| `06_Compiler/` | 编译器 | - |
| `07_AI_Accelerator/` | AI 加速器 | - |
| `08_Distributed_Training/` | 分布式训练 | - |
| `09_Simulators/` | 仿真器 | - |
| `10_Hardware_Design/` | 硬件设计 | - |
| `11_Drivers_OS/` | 驱动/OS | - |
| `12_CUDA_Ecosystem/` | CUDA 生态 | - |

**模板**: [草稿模板](02_System/templates/04-knowledge-draft.md)

---

### 05_Project（项目知识）

按项目组织的专属知识。

| 项目 | 说明 | 页面数 |
|------|------|--------|
| `_template/` | 新项目模板 | - |
| `PTX-EMU/` | PTX 仿真器 | - |
| `CortiX/` | 整合项目 | - |
| `BrainSkillForge/` | AgenticDSL 运行时 | - |
| `UniDAG-Store/` | 智能体存储 | - |
| `Hydra-SKILL/` | MLA 架构外循环 | - |
| `Synapse-SKILL/` | 多智能体架构 | - |
| `CppHDL/` | C++ 硬件描述语言 | - |
| `CppTLM/` | C++ 建模架构 | - |
| `UsrLinuxEmu/` | 用户态 Linux 兼容 | - |

---

### 06_Mynotes（原创思考）

Suhua 的原创思考，不经过 Ingest 流程。

| 子目录 | 说明 | 页面数 |
|--------|------|--------|
| `architecture/` | 架构设计 | - |
| `decisions/` | 设计决策 | - |
| `experiments/` | 实验记录 | - |
| `reflections/` | 思考笔记 | - |

**模板**: [原创模板](02_System/templates/06-mynotes-original.md)

---

## 🔍 快速链接

### 最近创建

（待填充）

### 最近更新

（待填充）

### 待验证知识

（待填充）

### 冲突知识

（待填充）

---

## 📋 使用指南

### 手动创建知识条目

1. **从原材料提取**：
   - 将 PDF/文章放入 `00_Raw_Sources/`
   - 复制 [草稿模板](02_System/templates/04-knowledge-draft.md) 到 `04_Knowledge/` 对应领域
   - 填写内容

2. **提炼到 Wiki**：
   - 复制 [Wiki 模板](02_System/templates/01-wiki-concept.md) 到 `01_Wiki/concepts/`
   - 填写完整 frontmatter 和关系
   - 标注 `extracted_from` 指向 04_Knowledge 草稿

3. **原创思考**：
   - 复制 [原创模板](02_System/templates/06-mynotes-original.md) 到 `06_Mynotes/` 对应子目录
   - 自由格式书写

### Phase 2 自动化

Phase 2 完成后，Agent 将自动：
- 摄取 `00_Raw_Sources/` 新素材
- 生成 `04_Knowledge/` 草稿
- 提炼到 `01_Wiki/`
- 更新本索引页面

---

## 📐 架构文档

| 文档 | 说明 |
|------|------|
| [PRD](05_Project/PKGM/PRD.md) | 产品需求文档 |
| [ADR-001 ~ 006](05_Project/PKGM/ADR/) | 架构决策记录 |
| [ARCHITECTURE.md](05_Project/PKGM/ARCHITECTURE.md) | 架构设计总览 |
| [IMPLEMENTATION_PLAN.md](05_Project/PKGM/IMPLEMENTATION_PLAN.md) | 实施计划 |

---

**版本**: V1.0  
**维护**: PKGM Agent + Suhua
