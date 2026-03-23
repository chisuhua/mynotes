# 集成方案 TODO 列表

> **创建日期**: 2026-03-23  
> **状态**: 待定 - 需要充分理解各项目后再决策

---

## 📋 待决策集成点

### 1. AgentCore ↔ brain-skill-forge 集成

**背景**：
- **AgentCore** (mynotes/CortiX/AgentCore): 智能体内核 + 灵活外壳架构（C++）
- **brain-skill-forge** (/workspace/brain-skill-forge): AgenticDSL 运行时（C++）

**待考虑方案**：

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A** | AgentCore 调用 brain-skill-forge 作为 DSL 执行后端 | 复用现有 DSL 运行时，职责清晰 | 增加依赖复杂度 |
| **B** | brain-skill-forge 作为 AgentCore 的 Tool 之一 | 灵活，AgentCore 可同时支持多种执行后端 | 需要定义 Tool 接口 |
| **C** | 两者独立，通过 UniDAG-Store 共享状态 | 松耦合，可独立演进 | 状态同步复杂 |

**决策条件**：
- [ ] 充分理解 AgentCore 的 `CognitiveEngine` 和 `TaskGroup` 设计
- [ ] 充分理解 brain-skill-forge 的 `TopoScheduler` 和 `DSLEngine` 设计
- [ ] 明确两者在智能体执行流程中的职责边界
- [ ] 评估性能影响（延迟、内存占用）

**相关会话**：
- `BrainSkillForge` - 深入讨论 brain-skill-forge 架构
- `CppCortiX` - 深入讨论 AgentCore 架构

---

### 2. CppCortiX ↔ CortiX 子系统集成

**背景**：
- **CppCortiX**: 顶层智能体平台架构
- **CortiX 子系统**: UniDAG-Store, Hydra-SKILL, Synapse-SKILL, BrainSkillForge

**待考虑议题**：
- [ ] 多智能体如何共享 AgentCore 实例
- [ ] 智能体间通信协议（基于 UniDAG-Store）
- [ ] 与 Hydra-SKILL 的推理集成
- [ ] 与 Synapse-SKILL 的多智能体协调

**决策条件**：
- [ ] 明确 CppCortiX 的平台级职责
- [ ] 明确各子系统的接口契约
- [ ] 评估资源协调机制（显存、DAG 存储、技能缓存）

---

### 3. AgentCore ↔ UniDAG-Store 集成

**背景**：
- **AgentCore**: 需要持久化任务状态和执行轨迹
- **UniDAG-Store**: 智能体存储（DAG 版本化）

**待考虑方案**：
- [ ] AgentCore 的 `EnvironmentSnapshot` 是否使用 UniDAG-Store 作为后端
- [ ] 执行轨迹如何映射到 DAG 节点
- [ ] 崩溃恢复时如何从 UniDAG-Store 重建状态

---

## 📅 决策流程

1. **阶段 1**: 各会话独立深入讨论（BrainSkillForge, CppCortiX, AgentCore）
2. **阶段 2**: 跨会话架构对齐（联合评审）
3. **阶段 3**: 决策并记录到本文档
4. **阶段 4**: 实施集成方案

---

## 🔗 相关文档

- [AgentCore README](./AgentCore/README.md)
- [brain-skill-forge docs](../../brain-skill-forge/docs/)
- [CppCortiX 智能体平台架构](./CppCortiX/)

---

// -- 🦊 DevMate | 集成方案待决策 --
