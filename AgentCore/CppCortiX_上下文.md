# CppCortiX 项目上下文报告

> **创建日期**: 2026-03-23  
> **创建者**: CppCortiX 架构师子代理  
> **目的**: 建立 CppCortiX 智能体平台架构的完整上下文，为后续架构决策和对齐做准备

---

## 一、CppCortiX 平台架构设计（v4.0）

### 1.1 五层认知 - 进化体系

CppCortiX 采用完整的五层架构，形成感知 - 决策 - 执行 - 进化闭环：

```
┌─────────────────────────────────────────────────────────────────┐
│ L5: 人机协同层 (Human-in-the-loop)                              │
│ - 意图理解接口 / 策略确认闸门 / 知识注入接口                      │
├─────────────────────────────────────────────────────────────────┤
│ L4: 进化层 (Evolution)                                          │
│ - 轨迹捕获器 / Skill 编译器 (WASM) / Skill 运行时 / 持续优化器      │
├─────────────────────────────────────────────────────────────────┤
│ L3: 元认知层 (Metacognition)                                    │
│ - 目标漂移监测 / 资源管理器 / 世界模型 / 策略选择器 (Skill vs ReAct)│
├─────────────────────────────────────────────────────────────────┤
│ L2: 认知层 (Cognition)                                          │
│ - 分层规划器 / ReAct 引擎 (协程) / 双模态感知 / 状态持久化          │
├─────────────────────────────────────────────────────────────────┤
│ L1: 反射层 (Reflex)                                             │
│ - CDP 直连监听 (<1ms) / Playwright 桥接 / 中断控制器 / 安全策略引擎  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 各层核心设计

| 层级 | 关键组件 | 技术实现 | 性能指标 |
|------|----------|----------|----------|
| **L1** | 混合控制平面 | CDP 直连 + Playwright 桥接 | 崩溃检测<1ms |
| **L2** | 双模态感知 | SoM + A11y Tree 智能切换 | Token 优化 90% |
| **L2** | 分层规划器 | 高层 LLM(准) + 低层 LLM(快) | 任务 DAG 生成 |
| **L3** | 世界模型 | 轻量级 Transition 预测 | 异常检测 |
| **L3** | 策略选择器 | Skill 置信度评估 | 10 倍加速路径 |
| **L4** | Skill 编译器 | 轨迹→Rust→WASM | 20-100x 加速 |
| **L4** | 三级自修正 | L1 适配/L2 重规划/L3 重构 | 减少 90% 维护 |
| **L5** | 安全闸门 | 敏感操作人工确认 | 风险可控 |

### 1.3 核心创新点

1. **从"每次思考"到"肌肉记忆"**: 高频任务编译为 WASM Skill，从分钟级降至秒级
2. **从"脆弱脚本"到"弹性 Skill"**: 三级自修正机制，页面改版自动适应
3. **从"黑盒执行"到"可解释进化"**: Skill 版本化、A/B 测试、人工可干预
4. **完整的认知闭环**: 感知 - 决策 - 执行 - 进化四层联动

---

## 二、AgentCore 内核 + 外壳架构

### 2.1 架构演进路线

```
BAFA v1.0 → AOS-Browser v1.0 → AOS-Browser v2.0 → AOS-Universal v3.0
(融合架构)    (本地 LLM 专用)     (强内核 + 外壳)      (通用操作型智能体)
```

### 2.2 四层架构分层

| 层级 | 模块 | 职责 |
|------|------|------|
| **Layer 3** | WorkflowOrchestrator, PluginManager, HookManager | 元认知与外壳（DAG 编排、插件扩展） |
| **Layer 2** | CognitiveEngine, TaskGroup, UniversalToolAdapter | 认知内核（协程引擎、任务组、工具适配） |
| **Layer 1** | LightweightInterruptQueue, ResourceQuotaManager, SandboxPool | 事件与控制（无锁中断、资源配额） |
| **Layer 0** | SandboxedToolExecutor, WASM/Docker/Process/Browser Sandbox | 运行时与沙箱 |

### 2.3 核心概念

| 概念 | 说明 | 应用场景 |
|------|------|----------|
| **KV Cache 摘要** | 轻量级注意力模式摘要 (<100MB) | 崩溃恢复加速 30%+ |
| **Critical DOM Hash** | 关键 DOM 选择器路径哈希 | 页面状态恢复校验 |
| **强内核 + 灵活外壳** | 内核保证稳定性，外壳支持动态扩展 | 插件化架构基础 |
| **TaskGroup** | 协程任务组，支持 Fork/Join 语义 | 并发任务管理 |
| **WorkflowOrchestrator** | DAG 工作流编排器 | 任务依赖管理 |
| **Tool Manifest** | 工具元数据契约 | 声明式工具定义 |

### 2.4 线程与协程模型

| 线程 | 职责 | 优先级 |
|------|------|--------|
| Main Thread | CognitiveEngine 协程主循环 | SCHED_OTHER |
| IO Thread | 工具执行事件循环，沙箱通信 | SCHED_BATCH |
| Background Thread | 环境快照异步写入，日志轮转 | SCHED_IDLE |
| ThreadPool | 同步工具封装 (8 线程) | SCHED_OTHER |

---

## 三、BrainSkillForge 集成点分析

### 3.1 BrainSkillForge 现状（基于改造方案）

BrainSkillForge 是 AgenticDSL 运行时，当前改造方案将其从脚本执行器演进为生产级 Agent 操作系统：

| v4.0 架构 | BrainSkillForge 现有 | 建议新增/改造 |
|-----------|---------------------|---------------|
| L5 人机协同 | ❌ 无 | HumanDSL 节点 + 确认闸门 |
| L4 进化层 | ❌ 无 | Trajectory→WASM 编译器 |
| L3 元认知 | ⚠️ 部分（max_steps） | MetaDSL 元指令 + 世界模型校验器 |
| L2 认知层 | ✅ DSL 引擎（agent_loop） | 重构为事件驱动协程 |
| L1 反射层 | ⚠️ 部分（工具调用） | 增加 CDP 直连 + 硬实时中断 |

### 3.2 可能的集成方案

#### 方案 A: AgentCore 调用 BrainSkillForge 作为 DSL 执行后端

```
┌─────────────────────────────────────────────────────────┐
│                    CppCortiX 平台                        │
├─────────────────────────────────────────────────────────┤
│  L5/L4/L3 (元认知、进化、人机协同)                        │
├─────────────────────────────────────────────────────────┤
│  L2: CognitiveEngine                                     │
│      └── 调用 ──> BrainSkillForge.DSLEngine             │
│           (AgenticDSL v2.0 执行器)                        │
├─────────────────────────────────────────────────────────┤
│  L1: 中断队列 / 资源管理                                  │
└─────────────────────────────────────────────────────────┘
```

**优点**:
- 复用 BrainSkillForge 现有的 DSL 编译和执行能力
- 职责清晰：AgentCore 负责认知，BrainSkillForge 负责 DSL 执行
- BrainSkillForge 可独立演进

**缺点**:
- 增加依赖复杂度
- 需要定义清晰的接口契约

#### 方案 B: BrainSkillForge 作为 AgentCore 的 Tool 之一

```
┌─────────────────────────────────────────────────────────┐
│                    CppCortiX 平台                        │
├─────────────────────────────────────────────────────────┤
│  L3: WorkflowOrchestrator                                │
│      └── 管理 TaskGroup                                  │
│           └── 调用 UniversalToolAdapter                  │
│                └── BrainSkillForgeTool                   │
│                └── OtherTool (Browser/Terminal/...)      │
└─────────────────────────────────────────────────────────┘
```

**优点**:
- 灵活，AgentCore 可同时支持多种执行后端
- BrainSkillForge 作为可插拔工具

**缺点**:
- 需要定义 Tool Manifest 接口
- 可能损失部分深度集成能力

#### 方案 C: 两者独立，通过 UniDAG-Store 共享状态

```
┌──────────────────┐         ┌──────────────────┐
│   AgentCore      │         │  BrainSkillForge │
│  (认知引擎)       │         │  (DSL 运行时)      │
└────────┬─────────┘         └────────┬─────────┘
         │                            │
         └──────────┬─────────────────┘
                    │
         ┌──────────▼──────────┐
         │   UniDAG-Store      │
         │   (状态共享层)       │
         └─────────────────────┘
```

**优点**:
- 松耦合，可独立演进
- 通过 DAG 存储实现状态同步

**缺点**:
- 状态同步复杂
- 实时性可能受影响

### 3.3 推荐方案：分层集成（方案 A 变体）

基于 CppCortiX 的五层架构和 AgentCore 的四层架构，建议采用**分层集成**：

```
┌─────────────────────────────────────────────────────────────────┐
│ CppCortiX 平台层 (L5/L4)                                         │
│ - 人机协同 / Skill 进化 / 多智能体协调                            │
├─────────────────────────────────────────────────────────────────┤
│ AgentCore 层 (L3/L2)                                             │
│ - WorkflowOrchestrator / CognitiveEngine / TaskGroup            │
│ - 通过 Hook 机制扩展 BrainSkillForge 能力                          │
├─────────────────────────────────────────────────────────────────┤
│ BrainSkillForge 层 (L2/L1)                                       │
│ - AgenticDSL v2.0 执行器 / 事件总线 / 检查点管理                   │
│ - 作为 AgentCore 的"认知执行后端"                                  │
├─────────────────────────────────────────────────────────────────┤
│ 基础设施层 (L1/L0)                                               │
│ - UniDAG-Store (状态持久化) / Hydra-SKILL (推理) / 沙箱运行时      │
└─────────────────────────────────────────────────────────────────┘
```

**集成接口**:
1. **AgentCore → BrainSkillForge**: `DSLEngine.run_async(Context, EventBus)`
2. **BrainSkillForge → AgentCore**: 事件回调（检查点、漂移检测、任务完成）
3. **双向共享**: UniDAG-Store 作为状态后端

---

## 四、待决策事项

### 4.1 架构对齐

| 议题 | 状态 | 相关会话 |
|------|------|----------|
| AgentCore 与 BrainSkillForge 的职责边界 | 待决策 | CppCortiX, BrainSkillForge |
| 集成接口契约定义 | 待决策 | CppCortiX, AgentCore |
| UniDAG-Store 作为共享状态后端 | 待评估 | CppCortiX, UniDAG-Store |
| 与 Hydra-SKILL 的推理集成 | 待评估 | CppCortiX, Hydra-SKILL |
| Synapse-SKILL 多智能体协调协议 | 待评估 | CppCortiX, Synapse-SKILL |

### 4.2 下一步行动

1. **深入理解各子系统**: 
   - BrainSkillForge 会话：TopoScheduler 和 DSLEngine 设计
   - AgentCore 会话：CognitiveEngine 和 TaskGroup 设计
   - UniDAG-Store 会话：DAG 存储接口和版本化机制

2. **跨会话架构对齐**:
   - 联合评审集成方案
   - 定义接口契约
   - 评估性能影响

3. **决策并记录**:
   - 更新 INTEGRATION_TODO.md
   - 创建集成设计文档

---

## 五、关键文档索引

| 文档 | 位置 | 说明 |
|------|------|------|
| CppCortiX 智能体平台架构 v4.0 | `CppCortiX/智能体平台架构 v4.0.md` | 五层认知 - 进化体系 |
| BrainSkillForge 改造方案 | `CppCortiX/智能体平台 v4 改造 brain-dsl-runtime.md` | DSL 运行时演进路线 |
| AgentCore 文档索引 | `AgentCore/README.md` | 架构演进和分层 |
| AgentCore 详细设计 | `AgentCore/AOS-Universal 详细设计.md` | TaskGroup/WorkflowOrchestrator |
| 集成 TODO 列表 | `../INTEGRATION_TODO.md` | 待决策集成点 |

---

## 六、架构决策记录（初步）

| 决策 ID | 决策内容 | 状态 | 日期 |
|---------|----------|------|------|
| ADR-CCX-001 | CppCortiX 采用五层认知 - 进化架构 | 已确认 | 2026-03-23 |
| ADR-CCX-002 | AgentCore 作为 L2/L3 认知内核 | 待评审 | 2026-03-23 |
| ADR-CCX-003 | BrainSkillForge 作为 DSL 执行后端 | 待评审 | 2026-03-23 |
| ADR-CCX-004 | UniDAG-Store 作为共享状态后端 | 待评估 | 2026-03-23 |

---

// -- 🦊 DevMate | CppCortiX 上下文建立完成 --
