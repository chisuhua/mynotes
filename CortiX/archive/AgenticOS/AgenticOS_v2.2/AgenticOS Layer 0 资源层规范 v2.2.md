# AgenticOS Layer 0: 资源层规范 v2.2

**文档版本：** v2.2.0  
**日期：** 2026-02-25  
**范围：** agentic-dsl-runtime（C++ 核心运行时）  
**状态：** 基于 AgenticDSL v4.0 重构，适配 AgenticOS v2.2 架构，支持 DSL-Centric 编排与状态管理工具化  
**依赖：** AgenticOS-Architecture-v2.2, AgenticDSL v4.0, AgenticOS-Security-Spec-v2.2, AgenticOS-State-Tool-Spec-v2.2, AgenticOS-Interface-Contract-v2.2  
**基础代码：** `chisuhua/AgenticDSL`（`src/` 目录）

---

## 1. 核心定位

Layer 0（`agentic-dsl-runtime`）是 AgenticOS 的底层执行引擎，基于现有 `AgenticDSL` C++ 代码库重构而来，为 AgenticOS v2.2 提供 **DSL-Centric** 的核心编排能力。

### 1.1 现有能力与重构目标

| 能力 | 现有实现 | 重构目标 (v2.2) |
| :--- | :--- | :--- |
| **DSL 解析** | `MarkdownParser`（Markdown 格式解析） | 保留，增加 Layer Profile 编译时验证 |
| **拓扑调度** | `TopoScheduler`（Kahn 算法） | 保留，增强智能调度（`metadata.priority`） |
| **节点执行** | `NodeExecutor`（纯函数式分发） | 保留，增加 `state.read`/`state.write` 工具支持 |
| **预算控制** | `BudgetController` + `ExecutionBudget`（原子计数器） | 保留，增加自适应预算继承 |
| **上下文管理** | `ContextEngine`（快照 + 合并策略） | 保留，增强只读快照继承 |
| **工具注册** | `ToolRegistry` | 保留，增加 state 工具注册 |
| **LLM 适配** | `LlamaAdapter`（本地 llama.cpp） | 扩展为多后端适配器接口 (`ILLMProvider`) |
| **追踪导出** | `TraceExporter` | 保留，增强双循环标识 |
| **标准库加载** | `StandardLibraryLoader` | 扩展为 `/lib/cognitive/`, `/lib/thinking/`, `/lib/workflow/` 分层 |

### 1.2 关键约束（继承自 AgenticOS Architecture v2.2）

* ✅ **L0 是纯函数式运行时**：节点执行不修改传入 AST/Context，通过返回值传递变更
* ✅ **L0 禁止维护跨执行的会话状态**（session state）
* ✅ **L0 禁止在节点执行期间修改 AST 结构**
* ✅ **L3 禁止直接调用 `DSLEngine::run()`**，必须经过 L2 调度器
* ✅ **Python 仅作 Thin Wrapper**（pybind11），业务逻辑必须 DSL 化
* ✅ **L0 内部禁止反向依赖 L4 服务**（置信度必须作为参数传入）
* ❌ **禁止：L0 内部直接实例化 L4 服务类**（如 ConfidenceService、RiskAssessor）
* ❌ **禁止：L0 内部调用 L4 接口获取状态**（所有 L4 数据必须通过参数显式传入）

### 1.3 技术栈

* **语言标准：** C++20（当前 `CMakeLists.txt` 使用 `CMAKE_CXX_STANDARD 20`）
* **构建系统：** CMake 3.20+
* **Python 绑定：** pybind11（带 GIL 释放策略）
* **外部依赖：** llama.cpp, nlohmann/json, inja（模板渲染）
* **DSL 规范版本：** **AgenticDSL v4.0**（对应 Lang v4.4）

---

## 2. 架构设计

### 2.1 L0/L2/L2.5/L3/L4 执行边界契约

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    L0/L2/L2.5/L3/L4 执行边界契约 v2.2                    │
├─────────────────────────────────────────────────────────────────────────┤
│  L4 (Cognitive)                                                         │
│  ├─ ✅ 调用 L0.compile(source) → 返回 AST（纯函数，无状态）               │
│  ├─ ✅ 加载 L2.5 标准库模板（/lib/cognitive/**）                           │
│  ├─ ✅ 维护 C++ 原生状态 (CognitiveStateManager)                          │
│  ├─ ✅ 提供 IStateManager 接口 (Read/Write/Subscribe)                     │
│  ├─ ✅ 显式传入 confidence_score 给 L0（通过参数，非 L0 主动获取）         │
│  └─ ❌ 禁止：DSL 逻辑直接访问 C++ 状态内存                                │
│  └─ ❌ 禁止：直接调用 L0.execute()，必须经过 L2 调度器                     │
├─────────────────────────────────────────────────────────────────────────┤
│  L3 (Reasoning)                                                         │
│  ├─ ✅ 通过 llm_generate_dsl 原语生成 /dynamic/** 子图                     │
│  ├─ ✅ 调用 L2.5 模板（/lib/thinking/**）                                  │
│  ├─ ✅ 使用 state.read 工具读取状态 (只读)                                │
│  └─ ❌ 禁止：使用 state.write 工具 (Thinking Profile 限制)                │
│  └─ ❌ 禁止：直接调用 L0.execute()，必须经过 L2 调度器                     │
├─────────────────────────────────────────────────────────────────────────┤
│  L2.5 (Standard Library)                                                │
│  ├─ ✅ 提供只读、版本化的 DSL 子图（/lib/**）                               │
│  ├─ ✅ 签名强制验证                                                      │
│  ├─ ✅ 分类：/lib/cognitive/**, /lib/thinking/**, /lib/workflow/**       │
│  └─ ❌ 禁止：运行时修改                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  L2 (WorkflowEngine)                                                    │
│  ├─ ✅ 维护 ExecutionContext（有状态）                                    │
│  ├─ ✅ 通过 SandboxController 创建沙箱                                     │
│  ├─ ✅ 驱动细粒度循环（拓扑排序执行节点链）                                │
│  ├─ ✅ 智能调度（解析 metadata.priority）                                 │
│  ├─ ✅ 在沙箱内调用 L0.execute_node(ast, node_path, context)             │
│  ├─ ✅ 状态工具：注册 state.read/write 到 ToolRegistry                    │
│  ├─ ✅ 显式传入 confidence_score 给 L0（通过 ExecutionBudget 参数）        │
│  └─ ❌ 禁止：存储实现细节、直接调用 L0.execute()                          │
├─────────────────────────────────────────────────────────────────────────┤
│  L0 (agentic-dsl-runtime)                                               │
│  ├─ ✅ compile(source) → AST（纯函数）                                    │
│  ├─ ✅ execute_node(ast, node_path, context) → Result（纯函数）          │
│  ├─ ✅ 支持自适应预算约束（budget_inheritance: adaptive）                │
│  ├─ ✅ 支持风险感知人机协作（require_human_approval: risk_based）        │
│  ├─ ✅ 编译时检查：tool_call 与 Layer Profile 兼容性                      │
│  ├─ ✅ 运行时再次验证：Layer Profile 权限（防止 AST 篡改）                │
│  ├─ ✅ 状态工具注册：state.read/write 工具验证                           │
│  ├─ ✅ confidence_score 通过参数显式传入（非 L0 主动获取）                │
│  └─ ❌ 禁止：维护会话状态、直接系统调用、修改 AST、反向依赖 L4 服务        │
│  └─ ❌ 禁止：L0 内部实例化 L4 服务类（如 ConfidenceService）              │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块结构（重构后）

```text
agentic-dsl-runtime/
├── src/
│   ├── core/
│   │   ├── engine.h / engine.cpp          # DSLEngine（主入口，新增 compile() 接口）
│   │   └── types/
│   │       ├── node.h                     # 节点类型（新增 STATE_READ/STATE_WRITE）
│   │       ├── budget.h                   # ExecutionBudget（新增 adaptive 模式）
│   │       ├── context.h                  # Context（nlohmann::json）
│   │       ├── resource.h                 # Resource, ResourceType
│   │       └── errors.h                   # 结构化错误类型
│   ├── common/
│   │   ├── llm/
│   │   │   ├── illm_provider.h            # ILLMProvider 接口
│   │   │   ├── llama_adapter.h/cpp        # 实现 ILLMProvider
│   │   │   ├── openai_adapter.h/cpp       # OpenAI HTTP 适配
│   │   │   ├── anthropic_adapter.h/cpp    # Anthropic 适配
│   │   │   └── llm_provider_factory.h/cpp # 工厂方法
│   │   └── tools/
│   │       ├── registry.h/cpp             # ToolRegistry
│   │       └── state_tool_registry.h/cpp  # state 工具注册与验证
│   └── modules/
│       ├── parser/
│       │   ├── markdown_parser.h/cpp      # MarkdownParser
│       │   └── semantic_validator.h/cpp   # 语义分析（Layer Profile 验证）
│       ├── scheduler/
│       │   ├── topo_scheduler.h/cpp       # 拓扑排序（混合队列策略）
│       │   ├── execution_session.h/cpp    # ExecutionSession
│       │   └── resource_manager.h/cpp     # ResourceManager
│       ├── executor/
│       │   ├── node_executor.h/cpp        # 节点执行（双重验证）
│       │   └── node.cpp                   # 各节点类型执行实现
│       ├── budget/
│       │   ├── budget_controller.h/cpp    # BudgetController
│       │   └── adaptive_budget.h/cpp      # 自适应预算计算
│       ├── context/
│       │   └── context_engine.h/cpp       # ContextEngine
│       ├── trace/
│       │   └── trace_exporter.h/cpp       # TraceExporter（异步批量）
│       ├── library/
│       │   ├── library_loader.h/cpp       # 分层加载（带缓存失效）
│       │   └── schema.h                   # LibraryEntry
│       ├── system/
│       │   └── system_nodes.h/cpp         # 系统节点
│       └── bindings/
│           └── python.cpp                 # pybind11 Thin Wrapper（GIL 释放）
├── lib/
│   ├── cognitive/                         # L4 认知层标准库
│   ├── thinking/                          # L3 推理层标准库
│   ├── workflow/                          # 工作流标准库
│   └── utils/                             # 通用工具
├── include/
│   └── agentic_dsl/                       # 公共头文件（对外暴露）
│       ├── engine.h
│       ├── types.h
│       └── llm_provider.h
├── tests/
│   ├── test_compiler.cpp
│   ├── test_executor.cpp
│   ├── test_layer_profile.cpp             # Layer Profile 验证
│   ├── test_state_tool.cpp                # state 工具注册
│   ├── test_adaptive_budget.cpp           # 自适应预算
│   └── test_bindings.py                   # Python 绑定
├── CMakeLists.txt                         # 增加 pybind11 支持
├── pyproject.toml                         # Python 包配置
├── version_script.map                     # 符号版本控制脚本
└── README.md
```

### 2.3 核心类关系

```text
DSLEngine
├── MarkdownParser              ← DSL Markdown 文档解析，输出 ParsedGraph
├── SemanticValidator           ← 编译时语义验证（Layer Profile）
├── TopoScheduler               ← Kahn 算法拓扑调度（混合队列）
│   ├── ExecutionSession        ← 单次执行封装
│   │   ├── NodeExecutor        ← 节点类型分发执行（双重验证）
│   │   │   ├── ToolRegistry    ← 工具注册与调用
│   │   │   ├── StateToolRegistry ← state 工具路由
│   │   │   ├── ILLMProvider    ← LLM 调用
│   │   │   └── MarkdownParser  ← 动态子图解析
│   │   ├── BudgetController    ← 预算检查与消耗
│   │   ├── AdaptiveBudgetCalculator ← 自适应预算计算（参数传入 confidence）
│   │   ├── ContextEngine       ← 上下文快照与合并
│   │   └── TraceExporter       ← 执行轨迹记录（异步批量）
│   └── ResourceManager         ← 资源注册与访问
└── StandardLibraryLoader       ← 标准库子图加载（分层 + 缓存失效）
```

---

## 3. 节点类型系统

### 3.1 现有节点类型（`src/core/types/node.h`）

```cpp
enum class NodeType : uint8_t {
    START,              // 入口节点
    END,                // 出口节点
    ASSIGN,             // 变量赋值（支持 Inja 模板）
    LLM_CALL,           // LLM 推理调用
    TOOL_CALL,          // 工具调用（ToolRegistry）
    RESOURCE,           // 资源声明（文件/DB/API）
    FORK,               // 并行分支（v3.1）
    JOIN,               // 分支合并（v3.1）
    GENERATE_SUBGRAPH,  // 动态子图生成（llm_generate_dsl）
    ASSERT,             // 条件断言
    // v2.2 新增（Phase 1）
    STATE_READ,         // state.read 工具调用（L4 状态读取）
    STATE_WRITE         // state.write 工具调用（L4 状态写入）
};
```

### 3.2 ParsedGraph 结构

```cpp
struct ParsedGraph {
    std::vector<std::unique_ptr<Node>> nodes;
    NodePath path;                           // e.g., /main
    nlohmann::json metadata;                 // 图级 metadata
    std::optional<ExecutionBudget> budget;   // 从 /__meta__ 解析
    std::optional<std::string> signature;    // 子图签名
    std::vector<std::string> permissions;    // 子图权限声明
    bool is_standard_library = false;        // 路径以 /lib/ 开头
    std::optional<nlohmann::json> output_schema; // 输出 JSON Schema
    
    // v2.2 新增：Layer Profile 声明
    struct LayerProfile {
        std::string profile_type;  // "Cognitive" | "Thinking" | "Workflow"
        std::vector<std::string> required_tools;
        std::vector<std::string> forbidden_tools;
    } layer_profile;
};
```

### 3.3 L0 重构：计划新增节点类型

| 节点类型 | 说明 | 优先级 | 实施阶段 |
| :--- | :--- | :--- | :--- |
| `CONDITION` | 条件分支（替代 ASSERT 中的跳转逻辑） | P1 | Phase 2 |
| `STATE_READ` | `state.read` 工具调用（L4 状态读取） | **P0** | **Phase 1** |
| `STATE_WRITE` | `state.write` 工具调用（L4 状态写入） | **P0** | **Phase 1** |

---

## 4. 解析器模块

### 4.1 现有实现（`MarkdownParser`）

现有解析器以 **Markdown 格式**解析 DSL 文档，输出 `ParsedGraph` 列表。

```cpp
class MarkdownParser {
public:
    // 从字符串解析，返回多个 ParsedGraph（支持多图）
    std::vector<ParsedGraph> parse_from_string(const std::string& markdown_content);
    
    // 从文件路径解析
    std::vector<ParsedGraph> parse_from_file(const std::string& file_path);
    
    // 从 JSON 对象创建单个节点
    std::unique_ptr<Node> create_node_from_json(const NodePath& path, const nlohmann::json& node_json);
    
private:
    void validate_nodes(const std::vector<std::unique_ptr<Node>>& nodes);
    std::optional<nlohmann::json> parse_output_schema_from_signature(const std::string& signature_str);
};
```

### 4.2 重构计划：增加编译时验证

在 `MarkdownParser` 或独立的 `SemanticValidator` 中增加：

```cpp
// 计划新增（Phase 1：核心安全）
class SemanticValidator {
public:
    explicit SemanticValidator(const std::vector<ParsedGraph>& graphs);
    void validate();
    
private:
    void validate_layer_profile();           // Layer Profile 与命名空间匹配
    void validate_state_tool_compatibility(); // state.read/write 权限声明
    void validate_node_references();          // 节点引用有效性
    void detect_cycles();                      // 环检测
};
```

**Layer Profile 规则（v2.2 计划）：**

| 命名空间前缀 | 要求 Profile | 约束 |
| :--- | :--- | :--- |
| `/lib/cognitive/**` | `Cognitive` | 仅允许 `state.read`/`state.write` 工具调用 |
| `/lib/thinking/**` | `Thinking` | 禁止 `state.write` |
| `/lib/workflow/**` | `Workflow` | 无额外约束 |
| `/dynamic/**` | 继承父图 | 运行时动态生成 |

### 4.3 语义验证实现（编译期 + 运行期双重验证）

```cpp
// 计划实现（Phase 1）
void SemanticValidator::validate_layer_profile() {
    for (const auto& [path, node] : ast_.nodes) {
        // 验证 layer_profile 声明
        if (node.layer_profile.profile_type.empty()) {
            // 默认继承父图 Profile
            continue;
        }
        
        // 验证 Profile 类型
        if (node.layer_profile.profile_type != "Cognitive" &&
            node.layer_profile.profile_type != "Thinking" &&
            node.layer_profile.profile_type != "Workflow") {
            throw CompileError(
                "ERR_INVALID_LAYER_PROFILE: " + node.layer_profile.profile_type
            );
        }
        
        // 验证 tool_call 与 Profile 兼容性
        if (node.type == "tool_call" || node.type == "state_read" || node.type == "state_write") {
            auto tool_name = get_tool_name(node);
            
            // Cognitive Profile: 禁止 tool_call（除 state.read/write）
            if (node.layer_profile.profile_type == "Cognitive") {
                if (tool_name != "state.read" && tool_name != "state.write") {
                    throw CompileError(
                        "ERR_PROFILE_VIOLATION: Cognitive Profile 禁止 tool_call: " + tool_name
                    );
                }
            }
            
            // Thinking Profile: 禁止 state.write
            if (node.layer_profile.profile_type == "Thinking") {
                if (tool_name == "state.write") {
                    throw CompileError(
                        "ERR_PROFILE_VIOLATION: Thinking Profile 禁止 state.write"
                    );
                }
            }
        }
        
        // 验证命名空间与 Profile 匹配
        if (path.rfind("/lib/cognitive/", 0) == 0) {
            if (node.layer_profile.profile_type != "Cognitive") {
                throw CompileError(
                    "ERR_PROFILE_MISMATCH: /lib/cognitive/** 必须声明 Cognitive Profile"
                );
            }
        }
        // ... 其他命名空间验证
    }
}

// 运行期双重验证（NodeExecutor 中）
bool NodeExecutor::verify_layer_profile_runtime(const Node& node, const Context& ctx) {
    // 防止编译后 AST 被篡改或上下文动态变更导致权限提升
    auto current_profile = ctx.get("__layer_profile__").get<std::string>();
    
    if (node.type == "state_write" && current_profile == "Thinking") {
        log_security_warning("Runtime Profile violation detected: state.write in Thinking Profile");
        return false;
    }
    
    // ... 其他运行期验证
    return true;
}
```

---

## 5. 调度器模块

### 5.1 现有实现（`TopoScheduler`）

```cpp
class TopoScheduler {
public:
    struct Config {
        std::optional<ExecutionBudget> initial_budget;
    };

    TopoScheduler(Config config, ToolRegistry& tool_registry, 
                  ILLMProvider* llm_provider, 
                  const std::vector<ParsedGraph>* full_graphs = nullptr);

    void register_node(std::unique_ptr<Node> node);
    void build_dag();           // 构建 DAG（计算入度 + 反向边）
    ExecutionResult execute(Context initial_context);  // Kahn 算法执行

    // 动态子图追加（generate_subgraph 回调）
    void append_dynamic_graphs(std::vector<ParsedGraph> new_graphs);
    
    std::vector<TraceRecord> get_last_traces() const;
};
```

**现有 Fork/Join 支持：**

`TopoScheduler` 已实现 Fork/Join 模拟执行：
- `start_fork_simulation()` / `finish_fork_simulation()`
- `execute_single_branch()` 按分支顺序串行执行（当前为模拟并行）
- `start_join_simulation()` / `finish_join_simulation()` 处理合并策略

### 5.2 重构计划：智能调度增强（混合队列策略）

在 `TopoScheduler::execute()` 中增加 `metadata.priority` 解析，采用混合队列策略以控制内存开销：

```cpp
// 计划增强（Phase 2）
// 关键路径节点使用 priority_queue，普通节点使用普通 queue
struct NodePriority {
    NodePath path;
    int priority;  // 从 node.metadata["priority"] 读取，默认 0
    bool critical_path;  // 是否在关键路径
    
    bool operator<(const NodePriority& other) const {
        // 关键路径优先，其次按优先级排序
        if (critical_path != other.critical_path) {
            return critical_path < other.critical_path;
        }
        return priority < other.priority; // 最大堆，高优先级先执行
    }
};

class TopoScheduler {
private:
    // 混合队列：关键路径用 priority_queue，普通节点用 queue
    std::priority_queue<NodePriority> critical_queue_;
    std::queue<NodePath> normal_queue_;
    
    // 内存控制：限制 priority_queue 大小
    static constexpr size_t MAX_CRITICAL_QUEUE_SIZE = 1000;
};

// 性能目标：智能调度额外开销 <5ms（100 节点 DAG），内存占用 <50MB
```

### 5.3 执行计划

```cpp
// scheduler/execution_plan.h
namespace agentic_dsl {

struct ExecutionStep {
    std::string node_path;
    std::string node_type;
    std::vector<std::string> dependencies;
    std::chrono::milliseconds estimated_time;
    
    // v2.2 新增：智能化字段
    int priority = 0;
    bool critical_path = false;
};

class ExecutionPlan {
public:
    void add_step(const ExecutionStep& step);
    std::vector<ExecutionStep> get_parallel_batch();
    bool has_more_steps() const;
    
private:
    // 混合队列策略
    std::priority_queue<ExecutionStep> critical_steps_;
    std::queue<ExecutionStep> normal_steps_;
    std::set<std::string> completed_;
};

} // namespace agentic_dsl
```

---

## 6. 执行器模块

### 6.1 现有实现（`NodeExecutor`）

```cpp
class NodeExecutor {
public:
    NodeExecutor(ToolRegistry& tool_registry, ILLMProvider* llm_provider = nullptr);

    // 纯函数式执行：接受 Context，返回新 Context（不修改原始 Context）
    Context execute_node(Node* node, const Context& ctx);
    
    // 动态子图回调
    void set_append_graphs_callback(AppendGraphsCallback cb);
    
private:
    ToolRegistry& tool_registry_;
    ILLMProvider* llm_provider_;
    AppendGraphsCallback append_graphs_callback_;
    MarkdownParser markdown_parser_;  // 用于 generate_subgraph 解析

    // 权限检查
    void check_permissions(const std::vector<std::string>& perms, const NodePath& node_path);
    
    // v2.2 新增：运行期 Layer Profile 验证
    bool verify_layer_profile_runtime(const Node& node, const Context& ctx);

    // 按节点类型分发
    Context execute_start(const StartNode* node, const Context& ctx);
    Context execute_end(const EndNode* node, const Context& ctx);
    Context execute_assign(const AssignNode* node, const Context& ctx);
    Context execute_llm_call(const LLMCallNode* node, const Context& ctx);
    Context execute_tool_call(const ToolCallNode* node, const Context& ctx);
    Context execute_state_read(const StateReadNode* node, const Context& ctx);  // v2.2 新增
    Context execute_state_write(const StateWriteNode* node, const Context& ctx); // v2.2 新增
    Context execute_resource(const ResourceNode* node, const Context& ctx);
    Context execute_generate_subgraph(const GenerateSubgraphNode* node, const Context& ctx);
    Context execute_join(const JoinNode* node, const Context& ctx);
    Context execute_fork(const ForkNode* node, const Context& ctx);
    Context execute_assert(const AssertNode* node, const Context& ctx);
};
```

### 6.2 重构计划：state 工具支持（Phase 1）

在 `execute_tool_call` 中增加 `state.read` / `state.write` 路由，并增加运行期双重验证：

```cpp
// 计划增强（Phase 1）
Context NodeExecutor::execute_tool_call(const ToolCallNode* node, const Context& ctx) {
    const auto& tool_name = node->tool_name;
    
    // 运行期 Layer Profile 双重验证
    if (!verify_layer_profile_runtime(*node, ctx)) {
        throw ExecutionError("ERR_PROFILE_VIOLATION: Runtime Profile check failed");
    }
    
    // state 工具路由到 StateToolRegistry
    if (tool_name == "state.read" || tool_name == "state.write") {
        return execute_state_tool(node, ctx);
    }
    
    // 普通工具调用
    check_permissions(node->permissions, node->path);
    auto result = tool_registry_.call_tool(tool_name, node->arguments);
    // ...
}

// 新增：state 工具执行
Context NodeExecutor::execute_state_tool(const ToolCallNode* node, const Context& ctx) {
    const auto& tool_name = node->tool_name;
    const auto& args = node->arguments;
    
    // 验证 Layer Profile 兼容性（运行期再次验证）
    if (tool_name == "state.write") {
        auto current_profile = ctx.get("__layer_profile__").get<std::string>();
        if (current_profile == "Thinking") {
            throw ExecutionError("ERR_PROFILE_VIOLATION: Thinking Profile 禁止 state.write");
        }
    }
    
    // 调用 StateToolRegistry（由 L2 注入）
    auto result = state_tool_registry_.call_tool(tool_name, args);
    
    // 处理 output_mapping
    // ...
    
    return new_context;
}
```

### 6.3 运行时安全约束检查

```cpp
// 计划新增（Phase 1）
bool NodeExecutor::check_output_constraints(const Node& node) {
    if (node.type != "llm_generate_dsl") return true;
    
    auto constraints = node.properties.find("output_constraints");
    if (constraints == node.properties.end()) return true;
    
    // 检查 max_blocks（防止 DSL 爆炸）
    auto max_blocks = constraints->second.find("max_blocks");
    if (max_blocks != constraints->second.end()) {
        int max_val = std::any_cast<int>(max_blocks->second);
        if (max_val > 3) {
            throw ExecutionError(
                "ERR_CONSTRAINT_VIOLATION: max_blocks exceeds limit"
            );
        }
    }
    
    // v2.2: 检查预算继承策略
    auto budget_inheritance = constraints->second.find("budget_inheritance");
    if (budget_inheritance != constraints->second.end()) {
        std::string strategy = 
            std::any_cast<std::string>(budget_inheritance->second);
        if (strategy == "adaptive") {
            // confidence_score 必须通过 Context 或 ExecutionBudget 参数显式传入
            // 严禁 L0 内部调用 L4 ConfidenceService 获取
        }
    }
    
    // v2.2: 检查人机协作策略
    auto human_approval = constraints->second.find("require_human_approval");
    if (human_approval != constraints->second.end()) {
        std::string mode = 
            std::any_cast<std::string>(human_approval->second);
        if (mode == "risk_based") {
            // 需要风险评估支持（通过参数传入）
        }
    }
    
    return true;
}
```

---

## 7. 预算控制模块

### 7.1 现有实现

**`ExecutionBudget`（`src/core/types/budget.h`）：** 使用 `std::atomic<int>` 实现线程安全的预算计数。

```cpp
struct ExecutionBudget {
    int max_nodes = -1;           // -1 表示无限制
    int max_llm_calls = -1;
    int max_duration_sec = -1;
    int max_subgraph_depth = -1;
    int max_snapshots = -1;
    size_t snapshot_max_size_kb = 512;

    // 原子计数器（线程安全）
    mutable std::atomic<int> nodes_used{0};
    mutable std::atomic<int> llm_calls_used{0};
    mutable std::atomic<int> subgraph_depth_used{0};
    std::chrono::steady_clock::time_point start_time;
    
    // v2.2 新增：显式传入的置信度分数（通过 L2/L4 传入，非 L0 主动获取）
    float confidence_score = 0.0f;

    bool exceeded() const;
    bool try_consume_node();
    bool try_consume_llm_call();
    bool try_consume_subgraph_depth();
};
```

**`BudgetController`（`src/modules/budget/budget_controller.h`）：** 封装预算管理逻辑，支持预算超限跳转（默认跳转至 `/__system__/budget_exceeded`）。

### 7.2 重构计划：自适应预算（参数显式传入）

增加 `budget_inheritance: adaptive` 支持，**confidence_score 必须通过参数显式传入**：

```cpp
// 计划新增（Phase 1）
class AdaptiveBudgetCalculator {
public:
    // 基于置信度分数（confidence_score）动态调整子图预算比例
    // ratio = 0.3 + 0.4 * confidence_score  (range: [0.3, 0.7])
    // 注意：confidence_score 必须通过参数显式传入，严禁内部调用 L4 服务
    static ExecutionBudget compute_subgraph_budget(
        const ExecutionBudget& parent_budget,
        float confidence_score  // 显式参数，来自 L2/L4
    );
    
    // 性能要求：<1ms
    static float estimate_confidence(const Context& ctx);
};

// 实现示例
ExecutionBudget AdaptiveBudgetCalculator::compute_subgraph_budget(
    const ExecutionBudget& parent_budget,
    float confidence_score) {  // 显式参数
    
    float ratio = 0.3f + 0.4f * confidence_score;  // [0.3, 0.7]
    if (ratio > 0.7f) ratio = 0.7f;
    if (ratio < 0.3f) ratio = 0.3f;
    
    ExecutionBudget child_budget;
    child_budget.max_nodes = static_cast<int>(parent_budget.max_nodes * ratio);
    child_budget.max_llm_calls = static_cast<int>(parent_budget.max_llm_calls * ratio);
    child_budget.max_duration_sec = static_cast<int>(parent_budget.max_duration_sec * ratio);
    child_budget.max_subgraph_depth = parent_budget.max_subgraph_depth - 1;
    child_budget.confidence_score = confidence_score;  // 传递给子预算
    
    return child_budget;
}
```

### 7.3 预算继承规则

| 策略 | 行为 | AgenticOS 映射 |
| :--- | :--- | :--- |
| `strict` | 子图预算 ≤ 父图预算 × 50%（默认） | Layer-0-Spec Section 7.3 |
| `adaptive` | 基于 Layer 4 置信度动态调整 (0.3-0.7) | Layer-4-Spec Section 3 (贝叶斯) |
| `custom` | 显式指定比例（如 0.6） | 自定义配置 |

**终止条件：**
- 队列空 + 无活跃生成 + 无待合并子图 + 预算未超
- 超限 → 跳转 `/__system__/budget_exceeded`

---

## 8. 上下文管理模块

### 8.1 现有实现（`ContextEngine`）

```cpp
// Context = nlohmann::json（别名，定义于 src/core/types/context.h）
using Value = nlohmann::json;
using Context = nlohmann::json;

class ContextEngine {
public:
    // 执行节点并处理快照
    Result execute_with_snapshot(
        std::function<Context(const Context&)> execute_func,
        const Context& ctx,
        bool need_snapshot,
        const NodePath& snapshot_node_path
    );

    // 静态合并（Fork/Join 分支结果合并）
    static void merge(Context& target, const Context& source, 
                      const ContextMergePolicy& policy = {});

    // 快照管理
    void save_snapshot(const NodePath& key, const Context& ctx);
    const Context* get_snapshot(const NodePath& key) const;
    void enforce_snapshot_budget();
    void set_snapshot_limits(size_t max_count, size_t max_size_kb);
};

// 合并策略（字符串枚举）
// "error_on_conflict" | "last_write_wins" | "deep_merge" | "array_concat" | "array_merge_unique"
using MergeStrategy = std::string;
```

**Fork/Join 合并策略：** `JoinNode::merge_strategy` 字段控制分支结果合并行为，当前支持 `error_on_conflict`（默认）、`last_write_wins`、`deep_merge`、`array_concat`、`array_merge_unique`。

### 8.2 重构计划：只读快照上下文（引用计数策略）

为动态子图沙箱增加只读快照支持，采用引用计数策略管理生命周期：

```cpp
// 计划新增（Phase 1）
class Context {
public:
    // ... 现有方法
    
    // v2.2 新增：只读快照上下文（用于动态子图沙箱）
    // 采用引用计数策略，确保父 Context 生命周期管理得当
    static Context create_readonly_snapshot(const Context& parent);
    
    // v2.2 新增：会话 ID 与用户 ID 传递
    void set_session_info(const std::string& session_id, const std::string& user_id);
    std::string get_session_id() const;
    std::string get_user_id() const;
    
    // v2.2 新增：Layer Profile 传递（用于运行期验证）
    void set_layer_profile(const std::string& profile);
    std::string get_layer_profile() const;
    
private:
    nlohmann::json data_;
    std::string session_id_;  // v2.2 新增
    std::string user_id_;     // v2.2 新增
    std::string layer_profile_;  // v2.2 新增
    bool readonly_ = false;   // v2.2 新增
    
    // 引用计数管理（防止悬空指针）
    std::shared_ptr<nlohmann::json> shared_data_;
};
```

---

## 9. 工具注册系统

### 9.1 现有实现（`ToolRegistry`）

```cpp
class ToolRegistry {
public:
    ToolRegistry();  // 构造时注册默认工具

    template<typename Func>
    void register_tool(std::string name, Func&& func);

    bool has_tool(const std::string& name) const;
    
    // 调用工具，传入 key-value 参数，返回 JSON 结果
    nlohmann::json call_tool(const std::string& name, 
                              const std::unordered_map<std::string, std::string>& args);
    
    std::vector<std::string> list_tools() const;
};
```

`DSLEngine` 通过 `register_tool<Func>()` 模板方法允许宿主程序注册自定义工具：

```cpp
engine->register_tool("my_tool", [](const auto& args) -> nlohmann::json {
    return { {"result", args.at("input")} };
});
```

### 9.2 重构计划：state 工具注册（Phase 1）

```cpp
// 计划新增（Phase 1）
// 在 L2（WorkflowEngine）中注册 state 工具到 ToolRegistry
engine->register_tool("state.read", [&state_manager](const auto& args) -> nlohmann::json {
    return state_manager.read(args.at("key"));
});

engine->register_tool("state.write", [&state_manager](const auto& args) -> nlohmann::json {
    state_manager.write(args.at("key"), args.at("value"));
    return { {"success", true} };
});

// StateToolRegistry 增强验证
class StateToolRegistry {
public:
    void register_tool(const std::string& name, std::function<std::any(const Context&)> handler);
    bool is_registered(const std::string& name) const;
    std::any execute(const std::string& name, const Context& context) const;
    ValidationResult validate_permission(const std::string& name, const std::string& layer_profile) const;
};
```

---

## 10. LLM 适配器

### 10.1 现有实现（`LlamaAdapter`）

当前 L0 仅支持本地 llama.cpp 后端：

```cpp
class LlamaAdapter {
public:
    struct Config {
        std::string model_path;
        int n_ctx = 2048;
        int n_threads = 4;
        float temperature = 0.7f;
        float min_p = 0.05f;
        int n_predict = 512;
    };

    explicit LlamaAdapter(const Config& config);
    std::string generate(const std::string& prompt);
    bool is_loaded() const;
};

// 注意：当前存在全局指针（计划重构为依赖注入）
extern LlamaAdapter* g_current_llm_adapter;
```

### 10.2 重构计划：多后端适配器接口

将 `LlamaAdapter` 重构为实现 `ILLMProvider` 接口，支持多后端：

```cpp
// 计划新增（Phase 2）
class ILLMProvider {
public:
    virtual ~ILLMProvider() = default;
    virtual std::string generate(const std::string& prompt) = 0;
    virtual bool is_loaded() const = 0;
    virtual std::string get_provider_name() const = 0;
    virtual ValidationResult validate_config(const LLMConfig& config) const = 0;
};

class LlamaAdapter : public ILLMProvider { /* 现有实现 */ };
class OpenAIAdapter : public ILLMProvider { /* 新增：OpenAI HTTP 适配 */ };
class AnthropicAdapter : public ILLMProvider { /* 新增：Anthropic HTTP 适配 */ };

// 工厂模式
class LLMProviderFactory {
public:
    static std::unique_ptr<ILLMProvider> create(const std::string& provider,
                                                 const std::map<std::string, std::string>& config);
};

// 同时移除全局指针 g_current_llm_adapter，改为依赖注入
```

### 10.3 安全约束

* **API Key 端侧加密存储**：严禁明文出现在 DSL 或 Context 中
* **模型白名单验证**：`model`/`provider` 必须在 Layer 4 配置的可信列表中
* **违反者** → 报错 `ERR_LLM_CONFIG_INVALID`

---

## 11. 标准库层（对应 AgenticOS L2.5）

### 11.1 现有实现

```cpp
class StandardLibraryLoader {
public:
    static StandardLibraryLoader& instance();  // 单例
    const std::vector<LibraryEntry>& get_available_libraries() const;
    void load_from_directory(const std::string& lib_dir);
    void load_builtin_libraries();
};
```

当前 `lib/` 目录结构：
```text
lib/
├── auth/       # 认证相关工具
├── human/      # 人机交互工具
├── math/       # 数学计算工具
└── utils/      # 通用工具
```

### 11.2 重构计划：分层标准库（v2.2）

按 AgenticOS v2.2 架构，将标准库重组为三层，**增加缓存失效机制**：

```text
lib/
├── cognitive/   # L4 认知层专用（Cognitive Profile，仅允许 state.read/write）
├── thinking/    # L3 推理层专用（Thinking Profile，禁止 state.write）
├── workflow/    # L2 工作流专用（Workflow Profile，无额外约束）
└── utils/       # 通用工具（跨层使用）
```

**分类治理：**
* 基础推理模式 (`react`, `plan_and_execute`) 归入 `/lib/reasoning/**`
* 特定业务流归入 `/lib/workflow/**`
* `/lib/**` 在 v2.2 中强制要求签名验证，而在 DSL v3.9 中为可选

### 11.3 标准库加载器增强（带缓存失效）

```cpp
// 计划增强（Phase 1）
class StandardLibraryLoader {
public:
    // 去单例化，支持多实例
    StandardLibraryLoader();
    
    // 分层加载
    void load_layer(const std::string& layer_name, const std::string& lib_dir);
    
    // 加载模板（只读快照）
    std::optional<ParsedGraph> load_template(const std::string& path, const std::string& version);
    
    // 签名验证
    bool verify_signature(const ParsedGraph& graph, const std::string& expected_signature);
    
    // 缓存策略
    void set_cache_enabled(bool enabled);
    void clear_cache();
    
    // v2.2 新增：缓存失效机制（开发模式）
    void invalidate_cache(const std::string& path);  // 单个路径失效
    void invalidate_all_cache();  // 全部失效（开发模式）
    
    // 生产模式：严格只读，缓存永久有效
    void set_production_mode(bool production);
};
```

---

## 12. 追踪导出模块

### 12.1 现有实现（`TraceExporter`）

```cpp
struct TraceRecord {
    std::string trace_id;
    NodePath node_path;
    std::string type;       // NodeType 字符串
    std::chrono::system_clock::time_point start_time;
    std::chrono::system_clock::time_point end_time;
    std::string status;     // "success" | "failed" | "skipped"
    std::optional<std::string> error_code;
    nlohmann::json context_delta;      // 执行前后上下文差量
    std::optional<NodePath> ctx_snapshot_key;
    nlohmann::json budget_snapshot;   // 执行时预算状态
    nlohmann::json metadata;          // 节点原始 metadata
    std::optional<std::string> llm_intent;
    std::string mode;       // "dev" | "prod"
};

class TraceExporter {
public:
    void on_node_start(const NodePath& path, NodeType type,
                       const nlohmann::json& initial_context,
                       const std::optional<ExecutionBudget>& budget);
    
    void on_node_end(const NodePath& path, const std::string& status,
                     const std::optional<std::string>& error_code,
                     const nlohmann::json& initial_context,
                     const nlohmann::json& final_context,
                     const std::optional<NodePath>& snapshot_key,
                     const std::optional<ExecutionBudget>& budget);
    
    std::vector<TraceRecord> get_traces() const;
    void clear_traces();
};
```

### 12.2 重构计划：双循环标识与智能化扩展（异步批量写入）

```cpp
// 计划增强（Phase 1）
struct TraceRecord {
    // ... 现有字段
    
    // v2.2 新增：双循环标识
    std::string loop_type;  // "coarse" (L3) | "fine" (L0/L2)
    
    // v2.2 新增：智能化演进字段
    struct Intelligence {
        std::string budget_inheritance;  // "strict" | "adaptive" | "custom"
        float confidence_score;
        float budget_ratio;
        std::string human_approval;  // "auto_approved" | "manual_approved" | "rejected"
        std::string risk_assessment;  // "low" | "medium" | "high" | "critical"
    } intelligence;
    
    // v2.2 新增：Session 标识
    std::string session_id;
    std::string user_id;
    
    // v2.2 新增：Layer Profile
    std::string layer_profile;
};

// TraceExporter 支持异步批量写入（性能目标：<1% 开销）
class TraceExporter {
public:
    // ... 现有方法
    
    // v2.2 新增：异步批量写入
    void enable_async_batch_write(size_t batch_size = 100, std::chrono::milliseconds interval = 100);
    
private:
    // 异步写入队列
    std::queue<TraceRecord> async_queue_;
    std::mutex queue_mutex_;
    std::thread async_writer_thread_;
    bool running_ = false;
};
```

---

## 13. Python 绑定计划（pybind11）

### 13.1 重构目标

当前代码库没有 Python 绑定。重构后，通过 pybind11 暴露最小化接口（Thin Wrapper），**所有 Python 回调函数必须在 `py::gil_scoped_release` 保护下执行**：

```cpp
// 计划新增：src/bindings/python.cpp
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <pybind11/json.h>
#include <pybind11/gil.h>  // 用于 GIL 释放
#include "core/engine.h"

namespace py = pybind11;

PYBIND11_MODULE(agentic_dsl_runtime, m) {
    m.doc() = "AgenticDSL C++ Runtime for AgenticOS v2.2";
    
    // AST 绑定
    py::class_<ParsedGraph>(m, "ParsedGraph")
        .def_property_readonly("path", &ParsedGraph::path)
        .def_property_readonly("nodes", &ParsedGraph::nodes)
        .def("to_json", &ParsedGraph::to_json);
    
    // Node 绑定
    py::class_<Node>(m, "Node")
        .def_property_readonly("path", &Node::path)
        .def_property_readonly("type", &Node::type)
        .def_property_readonly("properties", &Node::properties)
        .def_property_readonly("layer_profile", &Node::layer_profile);  // v2.2 新增
    
    // Node::Metadata 绑定（v2.2 新增）
    py::class_<Node::Metadata>(m, "NodeMetadata")
        .def_readonly("priority", &Node::Metadata::priority)
        .def_readonly("estimated_cost", &Node::Metadata::estimated_cost)
        .def_readonly("critical_path", &Node::Metadata::critical_path);
    
    // Context 绑定
    py::class_<Context>(m, "Context")
        .def(py::init<>())
        .def("set", &Context::set)
        .def("get", &Context::get)
        .def("has", &Context::has)
        .def("to_json", &Context::to_json)
        .def("from_json", &Context::from_json)
        .def("snapshot", &Context::snapshot)        // v2.2 增强
        .def("restore", &Context::restore)          // v2.2 增强
        .def_static("create_readonly_snapshot",     // v2.2 新增
                    &Context::create_readonly_snapshot)
        .def("set_session_info", &Context::set_session_info)  // v2.2 新增
        .def("get_session_id", &Context::get_session_id)      // v2.2 新增
        .def("get_user_id", &Context::get_user_id)            // v2.2 新增
        .def("set_layer_profile", &Context::set_layer_profile);  // v2.2 新增
    
    // Budget 绑定
    py::class_<ExecutionBudget>(m, "ExecutionBudget")
        .def(py::init<>())
        .def_readwrite("max_nodes", &ExecutionBudget::max_nodes)
        .def_readwrite("max_llm_calls", &ExecutionBudget::max_llm_calls)
        .def_readwrite("max_subgraph_depth", &ExecutionBudget::max_subgraph_depth)
        .def_readwrite("confidence_score", &ExecutionBudget::confidence_score)  // v2.2 新增
        .def("inherit_child", &ExecutionBudget::inherit_child);  // v2.2 新增
    
    // ExecutionResult 绑定
    py::class_<ExecutionResult>(m, "ExecutionResult")
        .def_property_readonly("success", &ExecutionResult::success)
        .def_property_readonly("output", &ExecutionResult::output)
        .def_property_readonly("trace", &ExecutionResult::trace)
        .def_property_readonly("budget_usage", &ExecutionResult::budget_usage);
    
    // Runtime 绑定（纯函数接口）
    py::class_<DSLEngine>(m, "DSLEngine")
        .def(py::init<>())
        .def_static("from_markdown", &DSLEngine::from_markdown,
                    "DSL 源码→AST（纯函数）",
                    py::arg("source"))
        .def_static("from_file", &DSLEngine::from_file,
                    "DSL 文件→AST（纯函数）",
                    py::arg("file_path"))
        .def("run", &DSLEngine::run,
             "执行 DAG（L2 驱动）",
             py::arg("context") = Context{})
        .def("register_tool", [](DSLEngine& self, const std::string& name, py::function fn) {
            // GIL 释放策略：Python 回调函数必须在 py::gil_scoped_release 保护下执行
            self.register_tool(name, [fn](const std::unordered_map<std::string, std::string>& args) 
                               -> nlohmann::json {
                py::gil_scoped_release release;  // 释放 GIL，防止阻塞 C++ 调度器
                py::gil_scoped_acquire acquire;  // 获取 GIL 调用 Python 函数
                return py::cast<nlohmann::json>(fn(args));
            });
        }, "注册工具", py::arg("name"), py::arg("fn"))
        .def("get_last_traces", &DSLEngine::get_last_traces,
             "获取追踪记录")
        .def("calculate_adaptive_budget_ratio",
             &DSLEngine::calculate_adaptive_budget_ratio,  // v2.2 新增
             "计算自适应预算比例",
             py::arg("confidence_score"));
    
    // CallChainToken 绑定（v2.2 新增）
    py::class_<CallChainToken>(m, "CallChainToken")
        .def(py::init<>())
        .def("fork", &CallChainToken::fork)
        .def("has_circular_dependency", &CallChainToken::has_circular_dependency)
        .def("exceeds_max_depth", &CallChainToken::exceeds_max_depth);
    
    // RiskAssessment 绑定（v2.2 新增）
    py::class_<RiskAssessment>(m, "RiskAssessment")
        .def_readonly("level", &RiskAssessment::level)
        .def_readonly("score", &RiskAssessment::score)
        .def_readonly("factors", &RiskAssessment::factors);
    
    // 异常绑定
    py::register_exception<CompileError>(m, "CompileError");
    py::register_exception<ExecutionError>(m, "ExecutionError");
    py::register_exception<BudgetExceededError>(m, "BudgetExceededError");
    py::register_exception<NamespaceViolationError>(m, "NamespaceViolationError");
    py::register_exception<CircularDependencyError>(m, "CircularDependencyError");
    py::register_exception<ConstraintViolationError>(m, "ConstraintViolationError");
    py::register_exception<ProfileViolationError>(m, "ProfileViolationError");  // v2.2 新增
    py::register_exception<StateToolError>(m, "StateToolError");                 // v2.2 新增
}
```

**约束：** Python 层不包含任何业务逻辑，所有逻辑通过 DSL 子图实现。

### 13.2 Python 使用示例

```python
# Python 使用示例（保持纯函数语义）
from agentic_dsl_runtime import DSLEngine, Context, ExecutionBudget

# L0 是纯函数式运行时，状态由 L2 管理
engine = DSLEngine.from_file("workflow.md")

# compile() 是纯函数：输入 source → 输出 AST，无副作用
# ast = engine.compile(dsl_source)

# execute_node() 是纯函数：输入 node+context → 输出 result
# Context 由 L2 的 ExecutionContext 维护，L0 不维护会话状态
context = Context()
context.set_session_info("sess_123", "user_456")  # v2.2 新增
context.set_layer_profile("Workflow")  # v2.2 新增
result = engine.run(context)

# ❌ 禁止：L0 内部维护状态
# engine.execute_loop(ast)  # 违反纯函数原则

# ✅ 正确：L2 驱动细粒度循环
# for node_path in topo_sort(ast):
#     result = engine.execute_node(ast, node_path, context)

# v2.2: 自适应预算计算（confidence_score 显式传入）
budget_ratio = engine.calculate_adaptive_budget_ratio(confidence_score=0.85)
# 返回 0.7 (高置信度 70% 预算)

# v2.2: 注册 state 工具（由 L2 注入，GIL 自动释放）
engine.register_tool("state.read", lambda args: state_manager.read(args["key"]))
engine.register_tool("state.write", lambda args: state_manager.write(args["key"], args["value"]))

# v2.2: 获取追踪记录
traces = engine.get_last_traces()
```

---

## 14. 重构实施计划

> **完整实施细节已提取为独立文档：**
> 📄 [AgenticOS_Layer0_RefactoringPlan.md](AgenticOS_Layer0_RefactoringPlan.md)
>
> 包含五个重构阶段的逐行代码差异、新增文件列表、接口修改说明和测试用例。

### Phase 总览（**关键特性优先级提升**）

| Phase | 名称 | 关键任务 | 新增文件 | 预估工作量 |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | 核心安全与状态工具 | 移除全局指针、**state.read/write 支持**、**Layer Profile 编译期 + 运行期验证**、结构化错误类型 | `src/core/types/errors.h`, `src/common/tools/state_tool_registry.h/cpp` | **2-3 周** |
| **Phase 2** | 多 LLM 后端支持 | `ILLMProvider` 接口抽象、`LlamaAdapter` 重构、新增 `OpenAIAdapter`/`AnthropicAdapter`、`LLMProviderFactory` | `illm_provider.h`, `openai_adapter.h/cpp`, `anthropic_adapter.h/cpp`, `llm_provider_factory.h/cpp` | 2-3 周 |
| **Phase 3** | 标准库分层重组 | `lib/` 目录按层重组、`StandardLibraryLoader::load_layer()` 增强、缓存失效机制 | `lib/cognitive/`, `lib/thinking/`, `lib/workflow/` | 1-2 周 |
| **Phase 4** | Python 绑定（pybind11） | pybind11 集成、Thin Wrapper `python.cpp`、`pyproject.toml`、**GIL 释放策略** | `src/modules/bindings/python.cpp`, `pyproject.toml` | 1-2 周 |
| **Phase 5** | 智能化演进优化 | 智能调度混合队列、自适应预算参数优化、动态沙箱性能优化 | `scheduler/execution_plan.h` 优化 | 2-3 周 |

---

## 15. 性能指标

| 指标 | 目标值 | 测试条件 | 备注 |
| :--- | :--- | :--- | :--- |
| **DSL 解析** | <50ms | 1000 行 Markdown | `MarkdownParser` |
| **拓扑排序** | <10ms | 1000 节点 DAG | `TopoScheduler::build_dag()` |
| **智能调度开销** | <5ms | 100 节点 DAG | 混合队列策略 |
| **调度器内存占用** | **<50MB** | 10 万节点 DAG | **v2.2 新增** |
| **节点执行（assign/condition）** | <1ms | 纯 CPU | `NodeExecutor` |
| **自适应预算计算** | <1ms | 贝叶斯估计 | `AdaptiveBudgetCalculator` |
| **LLM 调用延迟** | <10ms | 不含 LLM 响应时间 | 适配器开销 |
| **状态工具调用** | <5ms | state.read/write | L2 注入实现 |
| **Layer Profile 验证** | <1ms | 编译期 + 运行期 | `SemanticValidator` + `NodeExecutor` |
| **C++/Python 调用开销** | <0.1ms | 单次调用 | pybind11 绑定（GIL 释放） |
| **Trace 异步写入开销** | <1% | 全量采集 | `TraceExporter` |
| **内存占用** | <100MB | 运行时 | Layer 0 |

---

## 16. 接口契约

### 16.1 L0/L2 边界（核心约束）

```
L2（WorkflowEngine）             L0（agentic-dsl-runtime）
         │                               │
         │  compile(markdown_source)     │
         │──────────────────────────────▶│
         │  ◀────── ParsedGraph[] ───────│
         │                               │
         │  execute(graphs, ctx, budget) │
         │  budget.confidence_score=0.85 │  ← confidence_score 显式传入
         │──────────────────────────────▶│
         │  ◀──── ExecutionResult ───────│
         │                               │
         │  register_tool("state.read")  │
         │──────────────────────────────▶│
         │                               │
```

**约束：**
* L2 不直接访问 `NodeExecutor`、`TopoScheduler` 内部状态
* L2 通过 `DSLEngine::register_tool()` 注入 `state.read`/`state.write` 实现
* L0 不维护跨调用的持久状态（每次 `run()` 是独立执行）
* **L2 必须显式传入 `confidence_score` 给 L0（通过 `ExecutionBudget` 参数）**
* **L0 禁止主动调用 L4 接口获取 `confidence_score`**

### 16.2 Python Thin Wrapper 接口

```python
import agentic_dsl_runtime as runtime

# 编译 DSL
engine = runtime.DSLEngine.from_file("workflow.md")

# 注册工具（从 L2 传入，GIL 自动释放）
engine.register_tool("state.read", lambda args: state_manager.read(args["key"]))
engine.register_tool("state.write", lambda args: state_manager.write(args["key"], args["value"]))

# 执行（显式传入 confidence_score）
context = Context()
context.set("__layer_profile__", "Workflow")
result = engine.run(context)

# 获取追踪记录
traces = engine.get_last_traces()
```

### 16.3 ABI 兼容性承诺

* **C++ 公开头文件**（`include/agentic_dsl/`）5 年 ABI 稳定
* **符号版本控制**：使用 `__attribute__((visibility("default")))` 和版本脚本
  * 版本脚本路径：`version_script.map`
  * 示例：`agentic_dsl_v2.2 { global: DSLEngine::*; local: *; };`
* **Python 绑定层**：pybind11 接口签名 5 年稳定，实现可迭代

---

## 17. 风险与缓解

| 风险 | 影响 | 缓解措施 | 责任人 |
| :--- | :--- | :--- | :--- |
| `g_current_llm_adapter` 全局状态 | 多实例冲突 | Phase 1 优先移除，改为依赖注入 | L0 负责人 |
| `StandardLibraryLoader` 单例 | 测试隔离困难 | Phase 1 去单例化 | L0 负责人 |
| Fork/Join 当前为串行模拟 | 无真正并行 | 评估线程池方案（Phase 3） | L2 负责人 |
| Markdown 解析格式变更 | 与其他工具兼容性 | 保持向后兼容，增加格式版本标记 | 语言规范负责人 |
| pybind11 GIL 开销 | Python 调用性能 | **通过 `py::gil_scoped_release` 释放 GIL** | L0 负责人 |
| Layer Profile 验证遗漏 | 权限绕过风险 | **编译期 + 运行期双重验证** | 安全负责人 |
| ABI 兼容性破坏 | 第三方集成失败 | 符号版本控制，`include/agentic_dsl/` 稳定接口 | L0 负责人 |
| 状态一致性风险 | 状态覆盖或冲突 | 版本向量 + 事务支持 (compare-and-swap) | L4 负责人 |
| 状态工具性能开销 | 调用延迟增加 | 批量操作 + 本地缓存 (TTL 受 L4 控制) | L2 负责人 |
| 安全绕过风险 | 未授权状态写入 | 编译时检查 + 运行时验证 + 审计日志 | 安全负责人 |
| **智能调度内存膨胀** | **内存占用超标** | **混合队列策略，限制 priority_queue 大小** | **L0 负责人** |
| **confidence_score 获取方式错误** | **L0 反向依赖 L4** | **文档明确 + 代码审查 + 单元测试** | **L0 负责人** |

---

## 18. 与 AgenticOS 架构层对应关系

| AgenticOS 层 | 对应组件 | 实现位置 |
| :--- | :--- | :--- |
| **L0** | `DSLEngine`, `MarkdownParser`, `TopoScheduler`, `NodeExecutor` | `src/core/`, `src/modules/` |
| **L0** | `BudgetController`, `ContextEngine`, `TraceExporter` | `src/modules/budget/`, `context/`, `trace/` |
| **L0** | `LlamaAdapter`（重构为 `ILLMProvider`） | `src/common/llm/` |
| **L0** | `ToolRegistry`（含 state 工具） | `src/common/tools/` |
| **L2.5** | `/lib/cognitive/`, `/lib/thinking/`, `/lib/workflow/` | `lib/` |
| **L2** | `WorkflowEngine`（注册 state 工具，调用 `DSLEngine`） | 独立项目（AgenticOS L2） |
| **L4** | `CognitiveStateManager`（提供 `state.read`/`state.write` 实现） | 独立项目（AgenticOS L4） |

---

## 19. 测试策略

### 19.1 单元测试

```cpp
// test_layer_profile.cpp
TEST(LayerProfileTest, CompileTimeValidation) {
    // v2.2: 测试 Layer Profile 编译期验证
    std::string source = R"(
AgenticDSL "/lib/cognitive/test"
type: tool_call
tool_call:
  tool: web_search  # Cognitive Profile 禁止
layer_profile: Cognitive
)";
    
    DSLEngine engine;
    EXPECT_THROW(engine.compile(source), ProfileViolationError);
}

TEST(LayerProfileTest, RuntimeValidation) {
    // v2.2: 测试 Layer Profile 运行期验证
    DSLEngine engine;
    Context ctx;
    ctx.set("__layer_profile__", "Thinking");
    
    // 尝试在 Thinking Profile 中执行 state.write
    auto node = create_state_write_node();
    NodeExecutor executor(engine.get_tool_registry(), nullptr);
    
    EXPECT_THROW(executor.execute_node(node, ctx), ExecutionError);
}

// test_state_tool.cpp
TEST(StateToolTest, RegistrationAndExecution) {
    // v2.2: 测试 state 工具注册与执行（Phase 1）
    DSLEngine engine;
    
    // 注册工具
    engine.register_tool("state.read", [](const auto& args) -> nlohmann::json {
        return {{"value", "test"}};
    });
    
    // 验证注册
    EXPECT_TRUE(engine.has_tool("state.read"));
    
    // 执行工具
    auto result = engine.call_tool("state.read", {{"key", "test"}});
    EXPECT_EQ(result["value"], "test");
}

// test_adaptive_budget.cpp
TEST(AdaptiveBudgetTest, BudgetRatioCalculation) {
    // v2.2: 测试自适应预算计算（confidence_score 显式传入）
    ExecutionBudget parent_budget;
    parent_budget.max_nodes = 100;
    
    // confidence_score 必须通过参数显式传入
    ExecutionBudget child_budget = AdaptiveBudgetCalculator::compute_subgraph_budget(
        parent_budget, 0.85f  // 显式参数，非 L0 内部获取
    );
    
    EXPECT_EQ(child_budget.max_nodes, 70);  // 70% 继承
}

// test_gil_release.cpp
TEST(PythonBindingTest, GILRelease) {
    // v2.2: 测试 Python 回调 GIL 释放
    DSLEngine engine;
    
    // 注册 Python 工具（应自动释放 GIL）
    engine.register_tool("test_tool", py::function(...));
    
    // 验证 C++ 调度器不被 Python 阻塞
    // ...
}
```

### 19.2 集成测试

```python
# test_bindings.py
import pytest
from agentic_dsl_runtime import DSLEngine, Context

def test_l0_pure_function():
    """验证 L0 纯函数语义"""
    engine = DSLEngine()
    context1 = Context()
    context2 = Context()
    
    # 相同输入应产生相同输出
    ast = engine.compile("AgenticDSL '/main/start'\ntype: start")
    
    # 多次编译结果一致
    ast2 = engine.compile("AgenticDSL '/main/start'\ntype: start")
    assert ast.to_json() == ast2.to_json()

def test_adaptive_budget_inheritance():
    """v2.2: 验证自适应预算继承（confidence_score 显式传入）"""
    engine = DSLEngine()
    
    # 高置信度 (0.85) → 70% 预算
    ratio = engine.calculate_adaptive_budget_ratio(confidence_score=0.85)
    assert ratio == 0.7
    
    # 中置信度 (0.6) → 50% 预算
    ratio = engine.calculate_adaptive_budget_ratio(confidence_score=0.6)
    assert ratio == 0.5
    
    # 低置信度 (0.4) → 30% 预算
    ratio = engine.calculate_adaptive_budget_ratio(confidence_score=0.4)
    assert ratio == 0.3

def test_state_tool_registration():
    """v2.2: 测试 state 工具注册（Phase 1）"""
    engine = DSLEngine()
    
    # 注册工具
    engine.register_tool("state.read", lambda args: {"value": "test"})
    
    # 验证注册
    assert engine.has_tool("state.read")

def test_layer_profile_runtime_validation():
    """v2.2: 测试 Layer Profile 运行期验证"""
    engine = DSLEngine()
    context = Context()
    context.set("__layer_profile__", "Thinking")
    
    # 尝试在 Thinking Profile 中执行 state.write
    # 应抛出 ProfileViolationError
    with pytest.raises(ProfileViolationError):
        engine.execute_state_write(...)
```

---

## 20. 文档清单

| 文档 | 路径 | 版本 | 状态 |
| :--- | :--- | :--- | :--- |
| AgenticOS 架构总纲 | `docs/AgenticOS_Architecture.md` | v2.2 | 已发布 |
| **Layer 0 重构规范**（本文档） | `docs/AgenticOS_Layer0_Spec.md` | **v2.2** | **当前** |
| **Layer 0 重构实施计划（五阶段详细）** | `docs/AgenticOS_Layer0_RefactoringPlan.md` | v2.2 | 已更新 |
| DSL 标准库规范 | `docs/AgenticDSL_LibSpec_v4.0.md` | v4.0 | 已发布 |
| DSL 语言规范 | `docs/AgenticDSL_v4.0.md` | v4.0 | 已发布 |
| 运行时开发指南 | `docs/AgenticDSL_RTGuide.md` | v3.9 | 已发布 |
| 应用开发指南（C++） | `docs/AgenticDSL_AppDevGuide_C++_part.md` | v3.9 | 已发布 |
| 接口契约 | `docs/AgenticOS_Interface_Contract_v2.2.md` | v2.2 | 规划中 |
| 安全规范 | `docs/AgenticOS_Security_Spec_v2.2.md` | v2.2 | 规划中 |
| 状态工具规范 | `docs/AgenticOS_State_Tool_Spec_v2.2.md` | v2.2 | 规划中 |

---

## 21. 总结

Layer 0 资源层是 AgenticOS 的核心执行引擎，基于 **AgenticDSL v4.0** 重构，提供：

1. **纯函数式运行时**：`compile()` 和 `execute_node()` 无副作用，状态由 L2 管理
2. **双循环支持**：L3 粗粒度 ReAct 循环 + L0/L2 细粒度 DSL 循环
3. **安全约束**：命名空间验证、预算控制、死锁防护、权限检查、**Layer Profile 编译期 + 运行期双重验证**
4. **智能化演进**：自适应预算、智能调度、动态沙箱、风险感知人机协作
5. **状态管理工具化**：`state.read`/`state.write` 工具注册与验证（**Phase 1**）
6. **LLM 适配器标准化**：`ILLMProvider` 工厂模式，支持多提供商
7. **Python 绑定边缘化**：Thin Wrapper，业务逻辑 DSL 化，**GIL 释放策略**
8. **高性能**：DSL 编译<50ms，节点执行<1ms，自适应预算计算<1ms，**调度器内存<50MB**

**关键修订：**
* ✅ **版本依赖修正**：所有 `AgenticDSL-v3.9` 引用更新为 **`AgenticDSL v4.0`**
* ✅ **核心特性优先级调整**：`state.read/write` 工具支持、Layer Profile 验证从 Phase 5 提升至 **Phase 1**
* ✅ **安全双重验证**：明确 **编译期 + 运行期** 的 Layer Profile 双重验证机制
* ✅ **依赖注入明确化**：`confidence_score` 等 L4 数据必须通过参数传入，严禁 L0 反向依赖
* ✅ **GIL 风险缓解**：Python 回调函数必须在 `py::gil_scoped_release` 保护下执行
* ✅ **性能约束增强**：增加调度器内存占用 <50MB 约束

通过严格的 L0/L2 边界契约，确保系统安全性与可维护性，同时为未来 LLM 能力演进预留扩展空间。

**下一步：** 按 Phase 1 开始代码重构，移除全局状态，规范化接口

---

**文档结束**  
**基于代码库：** `chisuhua/AgenticDSL`（`src/` 目录，2026-02-25）  
**版权：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可