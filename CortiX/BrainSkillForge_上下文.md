# BrainSkillForge 项目上下文报告

**生成日期**: 2026-03-23  
**生成会话**: BrainSkillForge (Subagent)  
**文档状态**: 初始上下文建立

---

## 📌 项目定位

**BrainSkillForge** 是 CortiX 智能体平台的 **底层 DSL 运行时引擎**，基于 C++20 实现，提供 AgenticDSL 的解析、调度、执行能力。

**核心价值**:
- 将智能体工作流编译为可执行 DAG
- 确定性调度 + 预算控制 + 状态合并
- 支持动态子图生成（LLM 生成 DSL）
- 为上层（AgentCore/CortiX）提供统一执行后端

---

## 🏗️ 核心架构

### 1. 三层抽象（AgenticDSL v3.6）

| 层级 | 名称 | 说明 | 扩展性 |
|------|------|------|--------|
| **Layer 1** | 执行原语层 | 内置叶子节点（`assign`, `tool_call`, `llm_call`, `fork/join`, `assert`, `end`, `llm_generate_dsl`） | ❌ 不可扩展 |
| **Layer 2** | 标准原语层 | `/lib/**` 标准库（`/lib/dslgraph/**`, `/lib/reasoning/**`, `/lib/memory/**`, `/lib/conversation/**`） | ✅ 签名契约 |
| **Layer 3** | 知识应用层 | 用户/领域工作流（`/main/**`, `/lib/workflow/**`, `/lib/knowledge/**`） | ✅ 自由组合 |

**关键规则**:
- 所有复杂逻辑必须通过子图组合实现，禁止在叶子节点编码高层语义
- 禁止跨层跳转（知识应用层不得直接调用执行原语层）
- `/lib/**` 必须声明 `signature`（输入/输出契约）

### 2. 执行引擎架构

```text
DSLEngine (主入口)
├── MarkdownParser              ← DSL Markdown → ParsedGraph
├── TopoScheduler               ← Kahn 算法拓扑调度
│   ├── ExecutionSession        ← 单次执行封装
│   │   ├── NodeExecutor        ← 节点类型分发执行
│   │   │   ├── ToolRegistry    ← 工具注册与调用
│   │   │   ├── LlamaAdapter    ← LLM 调用
│   │   │   └── MarkdownParser  ← 动态子图解析
│   │   ├── BudgetController    ← 预算检查与消耗
│   │   ├── ContextEngine       ← 上下文快照与合并
│   │   └── TraceExporter       ← 执行轨迹记录
│   └── ResourceManager         ← 资源注册与访问
└── StandardLibraryLoader       ← 标准库子图加载
```

### 3. 核心组件职责

| 组件 | 文件位置 | 职责 |
|------|----------|------|
| **DSLEngine** | `src/core/engine.h` | 主入口，编译/执行 DSL，工具注册 |
| **TopoScheduler** | `src/modules/scheduler/topo_scheduler.h` | DAG 构建（Kahn 算法）、拓扑调度、Fork/Join 模拟 |
| **NodeExecutor** | `src/modules/executor/node_executor.h` | 节点类型分发执行（assign/tool_call/llm_call 等） |
| **BudgetController** | `src/modules/budget/budget_controller.h` | 预算检查与消耗（max_nodes, max_llm_calls, max_duration_sec） |
| **ContextEngine** | `src/modules/context/context_engine.h` | 上下文快照、合并策略（error_on_conflict, last_write_wins, deep_merge） |
| **ToolRegistry** | `src/common/tools/registry.h` | 工具注册表（C++ 函数/LLM 工具） |
| **LlamaAdapter** | `src/common/llm/llama_adapter.h` | llama.cpp 封装（计划扩展为多后端 ILLMProvider） |
| **TraceExporter** | `src/modules/trace/trace_exporter.h` | 执行轨迹导出（兼容 OpenTelemetry） |

---

## 📐 AgenticOS 层级映射（v2.2）

BrainSkillForge 对应 **AgenticOS Layer 0**（资源层），但通过 DSL 标准库向上延伸：

| AgenticOS Layer | BrainSkillForge 对应 | 说明 |
|-----------------|----------------------|------|
| **Layer 0** (Resource) | `agentic-dsl-runtime` C++ 核心 | 执行原语层、拓扑调度、预算控制 |
| **Layer 2.5** (Standard Library) | `/lib/**` DSL 子图 | 标准原语层（认知/推理/工作流） |
| **Layer 2** (Execution) | `TopoScheduler` + `NodeExecutor` | 工作流执行引擎 |
| **Layer 4** (Cognitive) | `/lib/cognitive/**` + `CognitiveStateManager`（待实现） | 认知逻辑 DSL 化，状态 C++ 管理 |

**关键架构规则**（v2.2）:
1. **唯一真理源**: `agentic-dsl-runtime` C++ 引擎是 L0-L4 执行的唯一核心
2. **逻辑即数据**: L2/L3/L4 业务逻辑固化为 `/lib/**` DSL 子图，禁止 Python 实现核心编排
3. **L4 状态分离**: L4 认知逻辑由 DSL 定义，L4 会话状态由 C++ 原生 `CognitiveStateManager` 维护
4. **状态工具化**: L4 状态通过 `state.read`/`state.write` 工具暴露给 DSL

---

## 🔧 核心节点类型（执行原语层）

| 节点类型 | 语义 | 关键字段 |
|----------|------|----------|
| `assign` | 安全赋值（Inja 表达式） | `assign.expr`, `assign.path` |
| `tool_call` | 调用注册工具 | `tool`, `arguments`, `output_mapping` |
| `llm_call` | LLM 推理调用 | `prompt`, `llm.model`, `llm.temperature`, `llm.seed` |
| `llm_generate_dsl` | LLM 生成动态子图 | `prompt`, `output_constraints`, `permissions.generate_subgraph` |
| `fork` / `join` | 显式并行控制 | `fork.branches`, `join.wait_for`, `join.merge_strategy` |
| `assert` | 条件验证 | `condition`, `on_failure` |
| `end` | 终止子图 | `termination_mode` (hard/soft), `output_keys` |
| `start` | 入口节点 | `next` |

---

## 📚 标准库体系（Layer 2.5）

### 核心标准库清单

| 路径 | 用途 | 稳定性 |
|------|------|--------|
| `/lib/dslgraph/generate@v1` | 安全生成动态子图 | stable |
| `/lib/reasoning/hypothesize_and_verify@v1` | 多假设验证 | stable |
| `/lib/reasoning/try_catch@v1` | 异常回溯 | stable |
| `/lib/reasoning/stepwise_assert@v1` | 分步断言 | stable |
| `/lib/reasoning/graph_guided_hypothesize@v1` | 图引导假设生成 | experimental |
| `/lib/memory/state/**` | Context 状态管理 | stable |
| `/lib/memory/kg/**` | 知识图谱操作 | stable |
| `/lib/memory/vector/**` | 语义记忆检索 | stable |
| `/lib/conversation/start_topic@v1` | 对话话题管理 | stable |

### 标准库分层（重构计划）

```text
lib/
├── cognitive/        # L4 认知层（路由决策、置信度评估）
├── thinking/         # L3 推理层（ReAct 循环）
├── workflow/         # L2 工作流层（领域逻辑）
└── utils/            # 跨层通用工具
```

---

## 🔄 当前进行中的工作

### 1. AgenticOS Layer 0 重构（五阶段计划）

| Phase | 名称 | 关键任务 | 状态 |
|-------|------|----------|------|
| **Phase 1** | 代码整理与接口规范化 | 移除全局指针、去单例化、compile() 接口、结构化错误 | 计划中 |
| **Phase 2** | 多 LLM 后端支持 | ILLMProvider 接口、OpenAI/Anthropic 适配器、工厂 | 计划中 |
| **Phase 3** | 标准库分层重组 | lib/ 目录重组、StandardLibraryLoader 增强 | 计划中 |
| **Phase 4** | Python 绑定 | pybind11 集成、Thin Wrapper 实现 | 计划中 |
| **Phase 5** | 智能化演进（v2.2） | SemanticValidator、智能调度、自适应预算、state 工具、风险感知人机协作 | 计划中 |

### 2. 关键重构任务详情

#### Phase 1: 代码整理与接口规范化
- **移除 `g_current_llm_adapter` 全局指针** → 通过 `TopoScheduler::Config` 传入
- **`StandardLibraryLoader` 去单例化** → 支持非单例构造（测试友好）
- **新增 `DSLEngine::compile()`** → 纯函数解析接口（供 L2 独立调用）
- **统一错误处理** → 引入 `DSLError` 结构化错误类型

#### Phase 5: 智能化演进特性
- **`SemanticValidator`** → Layer Profile 编译时验证（Cognitive/Thinking/Workflow）
- **智能调度** → `metadata.priority` 优先级队列（替换 FIFO）
- **自适应预算** → `AdaptiveBudgetCalculator`（基于置信度分数分配预算）
- **`state.read`/`state.write` 工具路由** → L4 状态管理工具化
- **风险感知人机协作** → `metadata.risk_level` 触发人工审批暂停

---

## 🔗 与 AgentCore 可能的集成点

### 待决策方案（见 INTEGRATION_TODO.md）

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A** | AgentCore 调用 BrainSkillForge 作为 DSL 执行后端 | 复用现有 DSL 运行时，职责清晰 | 增加依赖复杂度 |
| **B** | BrainSkillForge 作为 AgentCore 的 Tool 之一 | 灵活，AgentCore 可同时支持多种执行后端 | 需要定义 Tool 接口 |
| **C** | 两者独立，通过 UniDAG-Store 共享状态 | 松耦合，可独立演进 | 状态同步复杂 |

### 初步分析

**推荐方案 A**（BrainSkillForge 作为执行后端），理由：

1. **架构对齐**: BrainSkillForge 已实现完整的 DSL 运行时（解析→调度→执行），AgentCore 无需重复实现
2. **职责清晰**: 
   - AgentCore: 智能体认知引擎、任务管理、多智能体协调
   - BrainSkillForge: DSL 工作流执行引擎
3. **接口契约明确**:
   - AgentCore → BrainSkillForge: `DSLEngine::from_markdown()` + `run(Context)`
   - BrainSkillForge → AgentCore: 通过 `ToolRegistry` 注册工具（如 `state.read/write`）

### 集成接口设计（初步）

```cpp
// AgentCore 侧
class CognitiveEngine {
    std::unique_ptr<agenticdsl::DSLEngine> dsl_engine_;
    
    void execute_task(const Task& task) {
        // 1. 加载 DSL 工作流
        dsl_engine_ = agenticdsl::DSLEngine::from_file(task.workflow_path);
        
        // 2. 注册状态管理工具（L4 CognitiveStateManager）
        dsl_engine_->register_tool("state.read", [this](const auto& args) {
            return cognitive_state_manager_.read(args.at("key"));
        });
        dsl_engine_->register_tool("state.write", [this](const auto& args) {
            cognitive_state_manager_.write(args.at("key"), args.at("value"));
            return nlohmann::json{{"success", true}};
        });
        
        // 3. 执行 DSL 工作流
        auto result = dsl_engine_->run(task.context);
        
        // 4. 处理结果（暂停/继续/完成）
        if (result.paused_at) {
            // 人工审批或 LLM 暂停
        }
    }
};
```

### 待明确问题

1. **状态管理边界**: AgentCore 的 `CognitiveStateManager` 与 BrainSkillForge 的 `ContextEngine` 如何分工？
   - 建议：`ContextEngine` 管理单次执行上下文，`CognitiveStateManager` 管理跨会话状态

2. **工具注册时机**: AgentCore 何时向 BrainSkillForge 注册工具？
   - 建议：在 `DSLEngine` 创建后、`run()` 执行前批量注册

3. **错误处理协议**: BrainSkillForge 的 `DSLError` 如何映射到 AgentCore 的错误处理？
   - 建议：定义统一错误码映射表（`ErrorCode` → `AgentCore::ErrorType`）

4. **Trace 集成**: BrainSkillForge 的 `TraceExporter` 如何与 AgentCore 的执行轨迹整合？
   - 建议：Trace 通过回调传递给 AgentCore，由 AgentCore 统一存储到 UniDAG-Store

---

## 📋 下一步行动

### 短期（本会话）
- [ ] 深入阅读 `TopoScheduler` 实现（调度逻辑、Fork/Join 模拟）
- [ ] 深入阅读 `NodeExecutor` 实现（节点执行细节）
- [ ] 理解动态子图生成流程（`llm_generate_dsl` → `/dynamic/**`）

### 中期（跨会话）
- [ ] 与 `CppCortiX` 会话对齐 AgentCore 架构
- [ ] 决策集成方案（A/B/C）
- [ ] 定义接口契约文档

### 长期
- [ ] 实施 AgenticOS Layer 0 重构（五阶段）
- [ ] 实现 `CognitiveStateManager`（L4 状态管理）
- [ ] 集成 UniDAG-Store（执行轨迹持久化）

---

## 🔗 相关文档索引

| 文档 | 路径 | 说明 |
|------|------|------|
| AgenticDSL v3.6 规范 | `/workspace/brain-skill-forge/docs/AgenticDSL_v3.6.md` | DSL 语言规范 |
| AgenticOS 架构总览 | `/workspace/brain-skill-forge/docs/AgenticOS_Architecture.md` | 八层架构 |
| Layer 0 重构计划 | `/workspace/brain-skill-forge/docs/AgenticOS_Layer0_RefactoringPlan.md` | 五阶段重构 |
| Layer 0 规范 | `/workspace/brain-skill-forge/docs/AgenticOS_Layer0_Spec.md` | L0 详细设计 |
| 标准库规范 | `/workspace/brain-skill-forge/docs/AgenticDSL_LibSpec_v3.9.md` | `/lib/**` 契约 |
| 集成 TODO | `/workspace/mynotes/CortiX/INTEGRATION_TODO.md` | 待决策集成点 |

---

// -- 🦊 DevMate | BrainSkillForge 上下文建立完成 --
