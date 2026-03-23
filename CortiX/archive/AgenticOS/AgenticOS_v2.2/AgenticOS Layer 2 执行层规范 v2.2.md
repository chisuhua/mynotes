# AgenticOS Layer 2: 执行层规范 v2.2

文档版本：v2.2.0
日期：2026-02-25
范围：brain-domain-agent（领域执行引擎）
状态：基于 AgenticOS 架构 v2.2 正式发布，整合 C++ 核心编排、状态管理工具化、Layer Profile 安全模型与智能化演进特性
依赖：AgenticOS-Architecture-v2.2, AgenticOS-Layer-0-Spec-v2.2, AgenticOS-Security-Spec-v2.2, AgenticOS-Interface-Contract-v2.2, AgenticOS-Intelligence-Evolution-Spec-v1.0.0

---

## 执行摘要

Layer 2 是 AgenticOS 的执行层，第二大脑（Layer 4+5+6 组合）的执行引擎，提供：

*   **C++ 核心编排**：`WorkflowEngine` 基于 C++ 实现，最大化复用 `agentic-dsl-runtime`。
*   **DSL 逻辑驱动**：业务逻辑固化为 `/lib/workflow/**` DSL 子图，Python 仅作胶水层。
*   **状态管理工具化**：通过 `state.read`/`state.write` 工具封装 L4 状态，禁止直接内存访问。
*   **Layer Profile 安全**：实现 Workflow Profile 权限验证，支持编译期 + 运行期双重验证。
*   **智能化演进**：支持智能调度、自适应预算、动态沙箱、风险感知人机协作。

**核心设计**：C++ 引擎 + DSL 逻辑 + 状态工具化 + 安全隔离
**与第二大脑关系**：Layer 2 是第二大脑的执行引擎，通过 Layer 4 (brain-core) 的 `GenericDomainAgent` 接口暴露能力。

---

## 1. 核心定位

Layer 2 是 AgenticOS 的执行层，负责：

*   **工作流执行**：驱动细粒度 DSL 循环（L0/L2），执行领域工作流。
*   **沙箱管理**：通过 `SandboxController` 创建进程级隔离沙箱（cgroups/seccomp/Firecracker）。
*   **状态工具化**：通过 `StateToolAdapter` 封装 L4 状态接口为 DSL `tool_call` 节点。
*   **智能调度**：解析节点 `metadata.priority`，优化执行顺序。
*   **技能扩展**：支持通过 `SKILLS.md` 导入工具和工作流，让 L2 拥有新能力。
*   **交互式沙箱**：支持类似 tmux 的终端会话，用户可在后台查看工作过程。

**关键约束**：
*   ✅ L2 维护 `ExecutionContext`（有状态）
*   ✅ L2 通过 `SandboxController` 创建沙箱
*   ✅ L2 驱动细粒度循环（拓扑排序执行节点链）
*   ✅ L2 在沙箱内调用 L0.execute_node(ast, node_path, context)
*   ✅ L2 注册 `state.read`/`state.write` 到 `ToolRegistry`
*   ❌ 禁止：L2 存储实现细节、直接调用 L0.execute()
*   ❌ 禁止：L2 工具绕过权限验证直接调用 L4 状态接口

---

## 2. 架构设计

### 2.1 模块结构

```
brain-domain-agent/
├── src/
│   ├── core/
│   │   ├── workflow_engine.cpp       # C++ 工作流引擎 (拓扑调度、预算控制)
│   │   ├── execution_context.cpp     # 执行上下文 (快照、合并策略)
│   │   └── smart_scheduler.cpp       # 智能调度 (解析 metadata.priority)
│   ├── state/
│   │   ├── state_tool_adapter.cpp    # 状态工具适配器 (封装 L4 IStateManager)
│   │   └── state_registry.cpp        # 状态工具注册 (state.read/write)
│   ├── sandbox/
│   │   ├── sandbox_controller.cpp    # 沙箱控制器 (进程隔离、cgroups)
│   │   ├── dynamic_subgraph.cpp      # 动态子图沙箱 (独立上下文)
│   │   └── interactive_session.cpp   # 交互式会话 (tmux-like, Stdio 代理)
│   ├── security/
│   │   ├── profile_validator.cpp     # Layer Profile 验证 (编译期 + 运行期)
│   │   └── audit_logger.cpp          # 审计日志 (操作记录)
│   ├── tools/
│   │   ├── tool_registry.cpp         # 工具注册表 (基础设施适配器)
│   │   ├── infrastructure_adapter.cpp # 基础设施适配器 (文件/网络/进程)
│   │   └── skill_importer.cpp        # SKILLS.md 导入器 (工具/工作流注册)
│   └── bindings/
│       └── python.cpp                # Python 绑定 (Thin Wrapper, GIL 释放)
├── lib/
│   └── workflow/                     # 工作流标准库 (/lib/workflow/**)
├── include/
│   └── agentic_l2/
│       ├── workflow_engine.h
│       ├── state_tool_adapter.h
│       └── sandbox_controller.h
├── tests/
├── CMakeLists.txt
└── pyproject.toml
```

### 2.2 L0/L2/L2.5/L3/L4 执行边界契约

| 层级 | 职责 | 禁止行为 | 实现语言 |
| :--- | :--- | :--- | :--- |
| **L4 (Cognitive)** | 逻辑：`/lib/cognitive/**` (DSL)<br>状态：`CognitiveStateManager` (C++)<br>接口：`IStateManager` | 执行领域操作<br>DSL 直接访问 C++ 状态内存 | DSL + C++ |
| **L3 (Reasoning)** | 逻辑：`/lib/thinking/**` (DSL)<br>ReAct 循环 (粗粒度) | 直接系统调用<br>使用 `state.write` 工具 | DSL |
| **L2.5 (Standard Library)** | 提供只读、版本化 DSL 子图 (`/lib/**`) | 运行时修改模板<br>维护会话状态 | DSL |
| **L2 (Execution)** | 引擎：`WorkflowEngine` (C++)<br>逻辑：`/lib/workflow/**` (DSL)<br>工具：`InfrastructureAdapters`<br>状态工具：`StateToolAdapter` | 存储实现细节<br>直接调用 L0.execute() | C++ + DSL |
| **L0 (Resource)** | DSL 编译、节点执行 (细粒度)<br>编译检查：Layer Profile 验证 | 高层业务逻辑<br>维护会话状态<br>反向依赖 L4 服务 | C++ |

**状态管理访问路径：**
*   ✅ DSL → `state.read`/`state.write` 工具 → L2 `StateToolAdapter` → L4 `IStateManager`
*   ❌ 禁止：DSL 直接访问 `CognitiveStateManager` 内存
*   ❌ 禁止：L2 工具绕过权限验证直接调用 L4 状态接口

### 2.3 L2 状态分类表

| 状态类型 | 管理方式 | 存储位置 | 访问方式 | 示例 |
| :--- | :--- | :--- | :--- | :--- |
| **执行上下文** | C++ 原生 | 内存 | `ExecutionContext` | `$.temp.*`, `$.memory.state.*` |
| **沙箱状态** | C++ 原生 | 内存 (隔离) | `SandboxInstance` | `sandbox.local_cache` |
| **工具注册表** | C++ 原生 | 内存 | `ToolRegistry` | `tool.web_search` |
| **状态工具** | C++ 原生 | L4 状态管理器 | `state.read/write` | `memory.profile.*` |
| **执行轨迹** | L1 持久化 | UniDAG-Store | `IDAGStore` | `trace.*` |
| **节点元数据** | DSL 定义 | AST | 只读访问 | `metadata.priority` |
| **交互式会话** | C++ 原生 | 内存 (PTY) | `IOStream` | `session.stdio` |

### 2.4 Layer Profile 与四层防护模型集成

v2.2 引入 Layer Profile 权限模型，与 v2.1.1 四层防护模型深度集成。

| 防护层级 | Layer Profile 集成点 | 安全机制 |
| :--- | :--- | :--- |
| **L1: DSL 层** | 语义分析器验证 `/lib/workflow` 不包含违规节点 | 逻辑标识符、技能白名单、命名空间规则 |
| **L2: 框架层** | 执行器检查 Layer Profile 权限 (TOOL_CALL 拦截) | SandboxController 进程隔离、cgroups/seccomp |
| **L3: 适配器层** | InfrastructureAdapter 验证操作是否符合 Layer Profile | 三重验证（声明/资源/威胁）、审计日志 |
| **L4: 前端层** | 组件沙箱验证渲染内容是否符合 Layer Profile | CSP/数据脱敏、Web Worker + Shadow DOM |

**Layer Profile 定义：**
*   **Cognitive (L4)**: 严格限制，禁止 `tool_call` 和写文件，仅允许读记忆/上下文。**允许 `state.write`**。
*   **Thinking (L3)**: 中等限制，禁止写文件，限制 `tool_call` (仅只读工具)，允许调用 L2。**禁止 `state.write`，仅允许 `state.temp_write`**。
*   **Workflow (L2)**: 沙箱允许，允许 `tool_call`，允许文件写 (沙箱内)，允许网络 (受限)。**受限 `state.write` (沙箱/声明路径)**。

**Profile 继承规则：**
*   **降级原则**：子图调用时权限只能减少（例如 L4 调用 L3，L3 无法获得 L4 未授权的权限）。
*   **显式声明**：DSL 子图必须在 `__meta__` 中声明所需 Profile。
*   **编译期验证**：违反 Profile 约束直接在编译期报错 (`ERR_PROFILE_VIOLATION`)。
*   **运行期验证**：L2 `StateToolAdapter` 再次验证，防止绕过。

#### 2.4.1 Layer Profile 与状态工具权限映射

| 操作类型 | Cognitive Profile (L4) | Thinking Profile (L3) | Workflow Profile (L2) |
| :--- | :--- | :--- | :--- |
| `state.read` | ✅ 允许 | ✅ 允许 | ✅ 允许 |
| `state.write` | ✅ 允许 | ❌ 禁止 | ⚠️ 受限 (沙箱/声明路径) |
| `state.delete` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |
| `state.temp_write` | ✅ 允许 | ✅ 允许 (临时工作区) | ✅ 允许 (临时工作区) |
| `security.*` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |

**编译时验证：**
DSL 编译器必须在语义分析阶段验证 `tool_call` 节点与 `layer_profile` 的兼容性。
违规者 → `ERR_PROFILE_VIOLATION` (编译期错误)。

**双重验证机制：**

| 验证阶段 | 验证内容 | 实现位置 | 错误码 |
| :--- | :--- | :--- | :--- |
| **编译期** | `tool_call` 与 Profile 兼容性 | L0 语义分析器 | `ERR_PROFILE_VIOLATION` |
| **运行期** | 实际调用权限验证 | L2 `StateToolAdapter` | `ERR_PERMISSION_DENIED` |
| **审计期** | 操作日志记录 | L1 Trace 持久化 | N/A |

### 2.5 沙箱职责分层

| 组件 | 职责 | 禁止行为 |
| :--- | :--- | :--- |
| `SandboxController` | 进程级隔离（创建/销毁沙箱） | 业务逻辑验证 |
| `InfrastructureAdapterBase` | 操作级验证（路径/权限/审计） | 创建沙箱 |
| `StateToolAdapter` | 状态工具封装 (调用 L4 状态接口) | 直接访问 C++ 状态内存 |
| `DomainAdapter` | 领域业务逻辑 (工具实现) | 直接系统调用 |
| `ComponentSandbox` | 前端组件隔离（Web Worker + Shadow DOM） | 访问主线程 DOM |
| `InteractiveSession` | 交互式会话管理 (PTY/Stdio 代理) | 绕过沙箱隔离 |

---

## 3. 工作流引擎 (C++ Core)

### 3.1 引擎定义

```cpp
// include/agentic_l2/workflow_engine.h
namespace agentic_l2 {

class WorkflowEngine {
public:
    // 执行 DSL 模板（L2 驱动 L0 细粒度循环）
    virtual ExecutionResult execute_dsl_template(
        const agentic_dsl::AST& ast,
        ExecutionContext& context,
        const agentic_dsl::ExecutionBudget& budget
    ) = 0;
    
    // 注册工具到 ToolRegistry
    template<typename Func>
    virtual void register_tool(const std::string& name, Func&& handler) = 0;
    
    // 创建独立沙箱执行动态子图（v2.2 新增）
    virtual ExecutionResult execute_dynamic_subgraph(
        const agentic_dsl::AST& subgraph_ast,
        const ExecutionContext& parent_context,
        const DynamicSubgraphConfig& config = {}
    ) = 0;
    
    // 创建交互式会话（v2.2 新增，tmux-like）
    virtual std::string create_interactive_session(
        const std::string& session_id,
        const SandboxConfig& config,
        const std::string& shell_cmd = "/bin/bash"
    ) = 0;
    
    // 附加到交互式会话（v2.2 新增）
    virtual std::shared_ptr<IOStream> attach_session(const std::string& session_id) = 0;
    
    // 设置 Layer Profile（v2.2 新增）
    virtual void set_layer_profile(const std::string& profile) = 0;
};

} // namespace agentic_l2
```

### 3.2 智能调度 (Smart Scheduling)

L2 解析节点 `metadata` 中的 `priority` 和 `estimated_cost`，在依赖允许的前提下优化执行顺序。

```cpp
// src/core/smart_scheduler.cpp
namespace agentic_l2 {

struct NodePriority {
    std::string path;
    int priority;              // 从 node.metadata["priority"] 读取
    bool critical_path;        // 是否在关键路径
    
    bool operator<(const NodePriority& other) const {
        // 关键路径优先，其次按优先级排序
        if (critical_path != other.critical_path) {
            return critical_path < other.critical_path;
        }
        return priority < other.priority; // 最大堆，高优先级先执行
    }
};

class SmartScheduler {
public:
    std::vector<std::string> optimize_schedule(
        const std::vector<std::string>& base_order,
        const agentic_dsl::AST& ast) {
        
        // 1. 解析节点元数据
        std::priority_queue<NodePriority> critical_queue;
        std::queue<std::string> normal_queue;
        
        for (const auto& path : base_order) {
            const auto& node = ast.nodes.at(path);
            if (node.metadata.critical_path) {
                critical_queue.push({path, node.metadata.priority, true});
            } else {
                normal_queue.push(path);
            }
        }
        
        // 2. 合并队列 (关键路径优先)
        std::vector<std::string> optimized;
        while (!critical_queue.empty()) {
            optimized.push_back(critical_queue.top().path);
            critical_queue.pop();
        }
        while (!normal_queue.empty()) {
            optimized.push_back(normal_queue.front());
            normal_queue.pop();
        }
        
        return optimized;
    }
};

// 性能目标：智能调度额外开销 <5ms（100 节点 DAG），内存占用 <50MB
} // namespace agentic_l2
```

### 3.3 执行上下文 (ExecutionContext)

支持快照管理 (`snapshot()`/`restore()`)、只读快照继承。

```cpp
// src/core/execution_context.cpp
class ExecutionContext {
public:
    // 创建快照（用于 try_catch 回溯）
    std::string snapshot() const;
    void restore(const std::string& snapshot);
    
    // v2.2 新增：只读快照上下文（用于动态子图沙箱）
    static ExecutionContext create_readonly_snapshot(const ExecutionContext& parent);
    
    // v2.2 新增：会话 ID 与用户 ID 传递
    void set_session_info(const std::string& session_id, const std::string& user_id);
    std::string get_session_id() const;
    std::string get_user_id() const;
    
    // v2.2 新增：Layer Profile 传递（用于运行期验证）
    void set_layer_profile(const std::string& profile);
    std::string get_layer_profile() const;
    
private:
    nlohmann::json data_;
    std::string session_id_;
    std::string user_id_;
    std::string layer_profile_;
    bool readonly_ = false;
};
```

---

## 4. 状态管理工具化 (State Management Toolization)

### 4.1 工具注册流程

1.  L2 初始化时，实例化 `StateToolAdapter` (封装 L4 `IStateManager`)。
2.  L2 调用 L0 `DSLEngine::register_tool("state.read", adapter.read)`。
3.  L0 编译期验证 `state.read/write` 与 Layer Profile 兼容性。

```cpp
// src/state/state_tool_adapter.cpp
class StateToolAdapter {
public:
    std::any read(const std::string& path, const ExecutionContext& ctx) {
        // 1. 获取当前 Layer Profile
        auto profile = ctx.get_layer_profile();
        
        // 2. 运行期双重验证 (防止编译后 AST 篡改)
        if (!validate_profile_compatibility(profile, "state.read")) {
            throw SecurityError("ERR_PERMISSION_DENIED");
        }
        
        // 3. 路径验证 (禁止访问 security.* 等敏感路径)
        if (!validate_path(path, profile)) {
            throw SecurityError("ERR_PATH_VIOLATION");
        }
        
        // 4. 调用 L4 状态管理器
        return state_manager_->read(path);
    }
    
    void write(const std::string& path, const std::any& value, const ExecutionContext& ctx) {
        // 1. 获取当前 Layer Profile
        auto profile = ctx.get_layer_profile();
        
        // 2. Workflow Profile 受限写权限验证
        if (profile == "Workflow") {
            if (!is_sandbox_path(path) && !is_declared_path(path)) {
                throw SecurityError("ERR_PROFILE_VIOLATION: Workflow Profile 受限 state.write");
            }
        }
        
        // 3. 调用 L4 状态管理器 (带版本向量)
        auto version = state_manager_->get_version(path);
        state_manager_->write(path, value, version);
        
        // 4. 审计日志
        audit_logger_.log_state_operation("write", path, profile);
    }
    
private:
    bool validate_profile_compatibility(const std::string& profile, const std::string& tool);
    bool validate_path(const std::string& path, const std::string& profile);
    bool is_sandbox_path(const std::string& path);
    bool is_declared_path(const std::string& path);
};
```

### 4.2 双重验证机制

| 验证阶段 | 验证内容 | 实现位置 | 错误码 |
| :--- | :--- | :--- | :--- |
| **编译期** | `state.read/write` 与 Profile 兼容性 | L0 语义分析器 | `ERR_PROFILE_VIOLATION` |
| **运行期** | 实际调用权限验证 | L2 `StateToolAdapter` | `ERR_PERMISSION_DENIED` |
| **审计期** | 操作日志记录 | L1 Trace 持久化 | N/A |

---

## 5. 沙箱控制器 (Sandbox Controller)

### 5.1 动态子图沙箱

为 `/dynamic/**` 子图创建独立 `SandboxInstance`，防止动态生成的代码污染主流程 Context。

| 配置项 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `isolation_level` | "HIGH" | 独立内存空间 |
| `context_copy` | "SNAPSHOT" | 父 Context 快照只读继承 |
| `merge_explicit_outputs` | true | 仅合并显式输出 |
| `disable_cache` | true | 动态子图强制禁用缓存 |
| `noise_injection` | true | 动态子图强制噪声注入 |

```cpp
// src/sandbox/dynamic_subgraph.cpp
class SandboxController {
public:
    ExecutionResult execute_dynamic_subgraph(
        const agentic_dsl::AST& subgraph_ast,
        const ExecutionContext& parent_context,
        const DynamicSubgraphConfig& config = {}) {
        
        config = config.or_default(DynamicSubgraphConfig{
            .isolation_level = "HIGH",
            .context_copy = "SNAPSHOT",
            .merge_explicit_outputs = true
        });
        
        // 1. 创建独立沙箱配置
        SandboxConfig sandbox_config{
            .isolation_level = config.isolation_level,
            .context_copy = config.context_copy,
            .disable_cache = true,
            .noise_injection = true
        };
        
        // 2. 在独立沙箱中执行
        auto sandbox = create_sandbox(sandbox_config);
        ExecutionContext context;
        if (config.context_copy == "SNAPSHOT") {
            context = ExecutionContext::create_readonly_snapshot(parent_context);
        }
        
        // 3. 执行子图
        auto result = sandbox.execute(subgraph_ast, context);
        
        // 4. 仅合并显式输出 (防止副作用)
        if (config.merge_explicit_outputs) {
            return ExecutionResult{
                .success = result.success,
                .output = result.explicit_outputs
            };
        }
        return result;
    }
};
// 性能目标：动态沙箱创建 <50ms，上下文复制 <10ms
```

### 5.2 交互式沙箱 (Tmux-like Sandbox) ← v2.2 新增

**核心概念：**
*   **SessionMode**: `Batch` (默认) | `Interactive` (tmux-like)
*   **IO Multiplexer**: 沙箱 Stdin/Stdout/Stderr 代理到 Layer 5 WebSocket
*   **Persistence**: 会话状态持久化到 Layer 1 (Session DAG)

**工作流程：**
1.  **创建会话**: L4 请求 L2 创建 `InteractiveSandbox` (指定镜像/环境)
2.  **附加连接**: L5 通过 WebSocket 连接到 L2 Session Manager
3.  **IO 代理**: L2 将沙箱 Stdio 流式转发到 L5 (终端组件)
4.  **detach/attach**: 支持断开连接后后台运行，重新连接恢复上下文
5.  **安全约束**: 
    *   所有输入命令需经过 `InfrastructureAdapter` 验证
    *   禁止直接宿主机系统调用 (仍受 seccomp 限制)
    *   操作日志 100% 审计 (Trace)

```cpp
// src/sandbox/interactive_session.cpp
class SandboxController {
public:
    // 创建交互式会话
    std::string create_interactive_session(
        const std::string& session_id,
        const SandboxConfig& config,
        const std::string& shell_cmd = "/bin/bash"
    );
    
    // 附加到会话 (IO Stream)
    std::shared_ptr<IOStream> attach_session(const std::string& session_id);
    
    // 发送命令 (带权限验证)
    void send_command(const std::string& session_id, const std::string& cmd);
};
```

### 5.3 进程级隔离

*   **cgroups/seccomp**：限制 CPU、内存、系统调用。
*   **Firecracker**：高风险操作使用微虚拟机隔离。
*   **资源配额**：防止资源耗尽。

---

## 6. 技能导入规范 (SKILLS.md) ← v2.2 新增

### 6.1 技能清单格式 (DSL Manifest)

`SKILLS.md` 本质是 **工具注册 + 工作流模板** 的 DSL 清单，符合 `AgenticDSL v4.0` 规范。

```yaml
# SKILLS.md
__meta__:
  name: "python-dev-skill"
  version: "1.0.0"
  signature: "..."  # 必须签名
  layer_profile: "Workflow"

# 定义工具 (绑定脚本或 DSL)
tools:
  - name: "run_python"
    type: "script"  # 或 "dsl"
    runtime: "python3"
    script: "./scripts/run.py"  # 沙箱内路径
    permissions: ["file_read", "network_access"]

  - name: "analyze_code"
    type: "dsl"
    source: "/lib/skills/python/analyze@v1"  # 引用标准库

# 定义工作流 (可被 L3 调用)
workflows:
  - name: "debug_loop"
    entry_point: "/skill/debug/start"
    trigger: "on_error"  # 触发条件
```

**导入流程：**
1.  **验证**: L4 验证签名 & 权限 (Layer Profile)
2.  **编译**: L0 编译 DSL 部分为 AST
3.  **注册**: L2 `ToolRegistry` 动态注册工具
4.  **持久化**: 技能元数据存入 Layer 1 `SkillStore`
5.  **生效**: L3 推理时可发现新工具/工作流

### 6.2 安全约束

*   **沙箱执行**: 技能脚本必须在 `SandboxController` 内运行，禁止宿主机访问。
*   **权限最小化**: `SKILLS.md` 声明的 `permissions` 需用户确认。
*   **命名空间**: 技能工具注册到 `skill.{name}.*` 命名空间，避免冲突。

---

## 7. 安全与权限 (Layer Profile)

### 7.1 Layer Profile 与四层防护集成

| 防护层级 | Layer Profile 集成点 | 安全机制 |
| :--- | :--- | :--- |
| **L1: DSL 层** | 语义分析器验证 `/lib/workflow` 不包含违规节点 | 逻辑标识符、技能白名单、命名空间规则 |
| **L2: 框架层** | 执行器检查 Layer Profile 权限 (TOOL_CALL 拦截) | SandboxController 进程隔离、cgroups/seccomp |
| **L3: 适配器层** | InfrastructureAdapter 验证操作是否符合 Layer Profile | 三重验证（声明/资源/威胁）、审计日志 |
| **L4: 前端层** | 组件沙箱验证渲染内容是否符合 Layer Profile | CSP/数据脱敏、Web Worker + Shadow DOM |

### 7.2 Workflow Profile 权限定义

| 操作类型 | Cognitive Profile (L4) | Thinking Profile (L3) | Workflow Profile (L2) |
| :--- | :--- | :--- | :--- |
| `state.read` | ✅ 允许 | ✅ 允许 | ✅ 允许 |
| `state.write` | ✅ 允许 | ❌ 禁止 | ⚠️ 受限 (沙箱/声明路径) |
| `state.delete` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |
| `state.temp_write` | ✅ 允许 | ✅ 允许 (临时工作区) | ✅ 允许 (临时工作区) |
| `tool_call` | ❌ 禁止 (除 state 工具) | ⚠️ 受限 (只读工具) | ✅ 允许 (沙箱内) |
| `file_write` | ❌ 禁止 | ❌ 禁止 | ⚠️ 受限 (沙箱内) |
| `network_access` | ❌ 禁止 | ❌ 禁止 | ⚠️ 受限 (白名单) |

### 7.3 编译时验证

DSL 编译器必须在语义分析阶段验证 `tool_call` 节点与 `layer_profile` 的兼容性。
*   违规者 → `ERR_PROFILE_VIOLATION` (编译期错误)。
*   例如：Thinking Profile 中出现 `state.write` → 报错。

---

## 8. 接口契约

### 8.1 C++ Core API (唯一真理源)

```cpp
// include/agentic_l2/workflow_engine.h
class GenericDomainAgent {
public:
    // 执行入口 (稳定契约)
    virtual ExecutionResult execute(
        const std::string& directive,
        const ExecutionContext& context,
        float timeout_sec = 120.0f
    ) = 0;
    
    // 注册可视化组件到 Layer 5（v2.2 新增）
    virtual bool register_component(const ComponentSpec& spec) = 0;
};
```

### 8.2 Python 绑定 (Thin Wrapper)

所有 Python 回调函数必须在 `py::gil_scoped_release` 保护下执行。

```python
# interfaces/layer2_bindings.py
class WorkflowEngine(Protocol):
    async def execute_dsl_template(
        self,
        ast: 'AST',
        context: 'ExecutionContext',
        budget: 'ExecutionBudget'
    ) -> 'ExecutionResult':
        pass
    
    def register_tool(
        self,
        name: str,
        handler: Callable[[Dict[str, str]], Any]
    ) -> None:
        pass
    
    async def execute_dynamic_subgraph(
        self,
        subgraph_ast: 'AST',
        parent_context: 'ExecutionContext',
        config: 'DynamicSubgraphConfig' = None
    ) -> 'ExecutionResult':
        pass
    
    async def create_interactive_session(
        self,
        session_id: str,
        config: 'SandboxConfig' = None
    ) -> str:
        pass
    
    async def attach_session(self, session_id: str) -> 'IOStream':
        pass
```

### 8.3 ABI 兼容性承诺

*   **C++ 公开头文件** (`include/agentic_l2/`) 5 年 ABI 稳定。
*   **符号版本控制**：使用 `__attribute__((visibility("default")))` 和版本脚本。
*   **Python 绑定层**：pybind11 接口签名 5 年稳定，实现可迭代。

---

## 9. 性能指标

| 指标 | 目标 | 测试条件 | 备注 |
| :--- | :--- | :--- | :--- |
| 沙箱创建 | <500ms (PC) | 独立上下文 | v2.2 增强 |
| 智能调度开销 | <5ms | 100 节点 DAG | v2.2 新增 |
| 调度器内存占用 | <50MB | 10 万节点 DAG | v2.2 新增 |
| 状态工具调用 | <5ms | state.read/write | v2.2 新增 |
| 动态沙箱创建 | <50ms | 独立 SandboxInstance | v2.2 新增 |
| 上下文复制 | <10ms | 快照继承 | v2.2 新增 |
| Layer Profile 验证 | <1ms | 编译期 + 运行期 | v2.2 新增 |
| DSL 节点执行 | <5ms | assign 节点 | 保持 |
| 拓扑排序 | <10ms | 1000 节点 DAG | 保持 |
| 交互式会话创建 | <100ms | PTY 分配 | v2.2 新增 |
| IO 流式转发延迟 | <50ms | WebSocket | v2.2 新增 |

---

## 10. 测试策略

### 10.1 单元测试

```cpp
// test_layer2_v2.2.cpp
TEST(Layer2Test, StateToolRegistration) {
    // v2.2: 测试 state 工具注册与执行
    WorkflowEngine engine;
    
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

TEST(Layer2Test, LayerProfileRuntimeValidation) {
    // v2.2: 测试 Layer Profile 运行期验证
    WorkflowEngine engine;
    ExecutionContext ctx;
    ctx.set_layer_profile("Workflow");
    
    // 尝试在 Workflow Profile 中执行受限 state.write
    auto node = create_state_write_node("/lib/test", "value");
    
    EXPECT_THROW(engine.execute_node(node, ctx), ProfileViolationError);
}

TEST(Layer2Test, SmartScheduling) {
    // v2.2: 测试智能调度
    WorkflowEngine engine;
    AST ast = load_test_ast();
    
    // 设置节点优先级
    ast.nodes["/main/high_priority"].metadata.priority = 10;
    ast.nodes["/main/low_priority"].metadata.priority = 1;
    
    // 优化调度
    auto optimized = engine.optimize_schedule(base_order, ast);
    
    // 验证高优先级节点在前
    EXPECT_LT(
        std::find(optimized.begin(), optimized.end(), "/main/high_priority"),
        std::find(optimized.begin(), optimized.end(), "/main/low_priority")
    );
}

TEST(Layer2Test, DynamicSubgraphSandbox) {
    // v2.2: 测试动态子图沙箱隔离
    SandboxController controller;
    DynamicSubgraphConfig config{
        .isolation_level = "HIGH",
        .context_copy = "SNAPSHOT",
        .merge_explicit_outputs = true
    };
    
    // 验证独立沙箱创建
    auto result = await controller.execute_dynamic_subgraph(
        subgraph_ast, parent_context, config
    );
    
    // 验证上下文隔离
    EXPECT_TRUE(parent_context.is_unchanged());
}

TEST(Layer2Test, InteractiveSession) {
    // v2.2: 测试交互式会话 (tmux-like)
    SandboxController controller;
    
    // 创建会话
    std::string session_id = controller.create_interactive_session("test_session");
    
    // 附加会话
    auto stream = controller.attach_session(session_id);
    
    // 发送命令
    controller.send_command(session_id, "echo hello");
    
    // 验证输出
    EXPECT_TRUE(stream->read().contains("hello"));
}
```

### 10.2 集成测试

```python
# test_layer2_integration_v2.2.py
import pytest
from layer2.workflow_engine import WorkflowEngine

class TestStateToolIntegration:
    """v2.2: 测试状态工具集成"""
    
    async def test_state_read_write(self):
        """验证 state.read/write 工具可用"""
        engine = WorkflowEngine(...)
        
        # 注册工具
        engine.register_tool("state.read", lambda args: state_manager.read(args["key"]))
        engine.register_tool("state.write", lambda args: state_manager.write(args["key"], args["value"]))
        
        # 执行 DSL
        result = await engine.execute_dsl_template(ast, context, budget)
        
        # 验证状态读写成功
        assert result.success == True

class TestLayerProfileValidation:
    """v2.2: 测试 Layer Profile 验证"""
    
    async def test_compile_time_validation(self):
        """验证编译期 Profile 验证"""
        engine = WorkflowEngine(...)
        
        # 尝试编译违反 Profile 的 DSL
        with pytest.raises(ProfileViolationError):
            engine.compile("AgenticDSL '/lib/workflow/test'\ntype: tool_call\ntool_call:\n  tool: state.write")
    
    async def test_runtime_validation(self):
        """验证运行期 Profile 验证"""
        engine = WorkflowEngine(...)
        context = ExecutionContext()
        context.set_layer_profile("Workflow")
        
        # 尝试执行受限操作
        with pytest.raises(ProfileViolationError):
            await engine.execute_node(state_write_node, context)

class TestSmartScheduling:
    """v2.2: 测试智能调度"""
    
    async def test_priority_scheduling(self):
        """验证优先级调度"""
        engine = WorkflowEngine(...)
        ast = load_test_ast()
        
        # 设置节点优先级
        ast.nodes["/main/high"].metadata.priority = 10
        ast.nodes["/main/low"].metadata.priority = 1
        
        # 执行
        result = await engine.execute_dsl_template(ast, context, budget)
        
        # 验证执行顺序 (通过 Trace 分析)
        trace = result.trace
        high_index = trace.index("/main/high")
        low_index = trace.index("/main/low")
        assert high_index < low_index

class TestInteractiveSession:
    """v2.2: 测试交互式会话"""
    
    async def test_attach_detach(self):
        """验证会话 attach/detach"""
        engine = WorkflowEngine(...)
        
        # 创建会话
        session_id = await engine.create_interactive_session("test")
        
        # 附加会话
        stream = await engine.attach_session(session_id)
        
        # 发送命令
        stream.write("echo hello\n")
        
        # 验证输出
        output = await stream.read()
        assert "hello" in output
```

---

## 11. 实施路线图

### 11.1 Phase 1：核心安全与状态工具 (P0)

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | StateToolAdapter 实现 | `state.read/write` 工具可用，编译时检查生效 | Layer-0-Spec-v2.2 |
| W3-4 | Layer Profile 验证 | 权限隔离验证，编译期拦截率 100% | Security-Spec-v2.2 |
| W5-6 | L2 状态分类表 | 明确 ExecutionContext vs L4 状态边界 | Arch-v2.2 |
| W7-8 | 接口契约对齐 | 与 Interface-Contract-v2.2 完全匹配 | Interface-v2.2 |

### 11.2 Phase 2：智能化演进 (P1)

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | 智能调度实现 | `metadata.priority` 解析与执行顺序优化 | Intelligence-Spec-v1.0 |
| W3-4 | 动态沙箱实现 | `/dynamic/**` 独立上下文隔离 | Intelligence-Spec-v1.0 |
| W5-6 | 性能优化 | 智能调度开销 <5ms，动态沙箱创建 <50ms | - |
| W7-8 | 全链路压测 | SLO 达标，性能回归测试通过 | Observability-Spec-v2.2 |

### 11.3 Phase 3：交互式沙箱与技能导入 (P1)

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | 交互式沙箱原型 | `SandboxController` 支持 PTY/Stdio 流式转发 | Layer-5-Spec-v2.2 |
| W3-4 | L5 终端组件 | `TerminalComponent` 可连接会话 | Layer-5-Spec-v2.2 |
| W5-6 | SKILLS.md 解析器 | SDK 可解析 Manifest 并生成 DSL | Layer-6-Spec-v2.2 |
| W7-8 | 安全审计 | 交互式会话 IO 全量记录到 L1 | Security-Spec-v2.2 |

---

## 12. 风险与缓解

| 风险 | 影响 | 缓解措施 | 责任人 | 对齐依据 |
| :--- | :--- | :--- | :--- | :--- |
| **L4 状态同步复杂** | 状态泄漏风险 | 只读快照 + 事务性更新 + 版本向量 | L4 负责人 | Arch-v2.2#Sec-2.3 |
| **Layer Profile 验证遗漏** | 权限绕过风险 | 编译期 + 运行期双重验证 + 审计日志 | 安全负责人 | Security-v2.2#Sec-3.3 |
| **状态工具性能开销** | 调用延迟增加 | 批量操作 + 本地缓存 (TTL 受 L4 控制) | L2 负责人 | Arch-v2.2#Sec-13 |
| **智能调度内存膨胀** | 内存占用超标 | 混合队列策略，限制 priority_queue 大小 | L0 负责人 | L0-Spec-v2.2#Sec-5.2 |
| **动态沙箱上下文复制慢** | 执行延迟增加 | 优化快照复制机制 (引用计数) | L2 负责人 | Intelligence-Spec-v1.0#Sec-5 |
| **C++ ABI 兼容性破坏** | 第三方集成失败 | 符号版本控制 + ABI 兼容性测试 | L0 负责人 | Interface-v2.2#Sec-21 |
| **状态一致性风险** | 状态覆盖或冲突 | 版本向量 + 事务支持 (compare-and-swap) | L4 负责人 | Arch-v2.2#Sec-13 |
| **交互式沙箱逃逸** | 系统被攻破 | 严格 seccomp 配置，禁止危险系统调用 | 安全负责人 | Security-v2.2#Sec-2.2.2 |
| **技能包恶意代码** | 沙箱内攻击 | 签名验证 + 沙箱隔离 + 权限最小化 | 安全负责人 | Security-v2.2#Sec-3 |

---

## 13. 与 AgenticOS 文档的引用关系

| Layer-2-Spec 章节 | AgenticOS 文档引用 | 说明 |
| :--- | :--- | :--- |
| Section 1 (核心定位) | Architecture-v2.2#Sec-1.1 | 八层架构 |
| Section 2 (架构设计) | Architecture-v2.2#Sec-2.2 | L0/L2/L2.5/L3/L4 执行边界 |
| Section 2.3 (L2 状态分类) | Architecture-v2.2#Sec-2.3 | L4 状态分类表 |
| Section 4 (状态工具化) | State-Tool-Spec-v2.2 | 状态工具规范 |
| Section 5 (沙箱控制器) | Intelligence-Spec-v1.0#Sec-5 | 动态子图沙箱 |
| Section 6 (技能导入) | Layer-6-Spec-v2.2 | SKILLS.md 规范 |
| Section 7 (安全规范) | Security-Spec-v2.2#Sec-3 | Layer Profile 安全模型 |
| Section 8 (接口契约) | Interface-Contract-v2.2#Sec-8 | GenericDomainAgent |
| Section 9 (性能指标) | Observability-Spec-v2.2#Sec-8 | SLO 体系 |
| Section 10 (测试策略) | Security-Spec-v2.2#Sec-12 | 安全测试 |

---

## 14. 附录：错误码

| 错误码 | 含义 | 处理建议 |
| :--- | :--- | :--- |
| `ERR_PROFILE_VIOLATION` | Layer Profile 违规 | 检查 Profile 声明与工具兼容性 |
| `ERR_PERMISSION_DENIED` | 运行期权限拒绝 | 检查 StateToolAdapter 验证 |
| `ERR_PATH_VIOLATION` | 状态路径违规 | 检查 state.read/write 路径限制 |
| `ERR_STATE_TOOL_ERROR` | 状态工具错误 | 检查 L4 状态管理器接口 |
| `ERR_L0_REVERSE_DEPENDENCY` | L0 反向依赖 L4 | 检查 L0 代码无 L4 服务实例化 |
| `ERR_NAMESPACE_VIOLATION` | 命名空间违规 | 禁止写入 `/lib/**` |
| `ERR_BUDGET_EXCEEDED` | 预算超限 | 优化 DAG 或减少操作 |
| `ERR_SANDBOX_ESCAPE` | 沙箱逃逸检测 | 安全审计 + 渗透测试 |
| `ERR_SKILL_SIGNATURE_INVALID` | 技能包签名无效 | 验证 SKILLS.md 签名 |
| `ERR_INTERACTIVE_SESSION_FAILED` | 交互式会话创建失败 | 检查 PTY/资源配额 |

---

## 15. 总结

AgenticOS Layer 2 执行层 v2.2 是**C++ WorkflowEngine 为核心、状态工具化、Layer Profile 安全模型完备**的智能体执行引擎。

**核心变更：**
1.  **C++ 核心编排**：L2 引擎基于 C++ 实现，逻辑 DSL 化。
2.  **状态管理工具化**：通过 `state.read/write` 工具封装 L4 状态。
3.  **Layer Profile 安全**：实现 Workflow Profile 权限验证与双重验证。
4.  **智能化演进**：支持智能调度、动态沙箱、自适应预算。
5.  **交互式沙箱**：支持类似 tmux 的终端会话，用户可在后台查看工作过程。
6.  **技能导入**：支持通过 `SKILLS.md` 导入工具和工作流，让 L2 拥有新能力。

通过严格的接口契约与安全约束，确保 AgenticOS v2.2 的执行层安全性、性能与可演进性，为智能体生态奠定坚实的执行基础。

**核心批准条件：**
1.  **L2 状态分类明确化**: Section 2.3 包含与 Arch v2.2 一致的状态分类表。
2.  **StateToolAdapter 规范完整**: Section 4 详细说明 `state.read/write` 工具注册、权限验证、审计日志流程。
3.  **Layer Profile 双重验证**: Section 7.3 明确编译期 (L0) 与运行期 (L2) 的验证交互。
4.  **智能调度性能达标**: Section 9 明确智能调度开销 <5ms，内存占用 <50MB。
5.  **动态沙箱隔离验证**: Section 5.1 明确 `/dynamic/**` 子图独立上下文，父 Context 未被污染。
6.  **接口契约对齐**: Section 8 与 Interface-Contract-v2.2 完全匹配 (C++ Core API, Python Thin Wrapper)。
7.  **安全关键代码覆盖率**: Section 10 明确安全关键代码单元测试覆盖率 >90%。
8.  **交互式沙箱安全**: Section 5.2 明确 PTY/Stdio 流式转发安全约束，IO 全量审计。
9.  **技能导入安全**: Section 6 明确 `SKILLS.md` 签名验证、沙箱隔离、权限最小化。

---

文档结束
版权：AgenticOS 架构委员会
许可：CC BY-SA 4.0 + 专利授权许可