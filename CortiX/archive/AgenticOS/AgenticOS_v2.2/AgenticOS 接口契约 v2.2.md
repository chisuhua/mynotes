# AgenticOS 接口契约 v2.2

**文档版本：** v2.2.0  
**日期：** 2026-02-25  
**范围：** 5 年稳定接口契约（含 Layer 2.5 标准库层、智能化演进特性、状态管理工具化、Layer Profile 安全模型）  
**状态：** 正式发布  
**依赖：** AgenticOS-Architecture-v2.2, AgenticOS-Layer-0-Spec-v2.2, AgenticOS-Layer-2.5-Spec-v2.2, AgenticOS-Intelligence-Evolution-Spec-v1.0.0, AgenticOS-DSL-Engine-Spec-v4.0  
**版权所有：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可

---

## 执行摘要

AgenticOS 接口契约 v2.2 定义 AgenticOS 的**5 年稳定接口契约**，确保：

- **向后兼容性：** 接口签名 5 年内不破坏性变更
- **生态建设基础：** 第三方开发者基于稳定接口构建应用
- **版本演进可控：** 实现可迭代，接口需冻结
- **第二大脑定位：** 明确 Layer 4+5+6 组合作为官方用户入口的接口边界
- **智能化演进支持：** 支持自适应预算、智能调度、动态沙箱、自适应人机协作
- **状态管理工具化：** 通过 `state.read`/`state.write` 工具封装 L4 状态
- **C++ Core 优先：** C++ Core API 为唯一真理源，Python 仅作 Thin Wrapper

**核心设计：** 接口稳定 + 实现可迭代 + 分层契约 + 智能化扩展 + 状态工具化

**v2.2 核心变更：**
1. **C++ Core API 为唯一真理源**：核心层（L0-L4）接口定义以 C++ 头文件为准
2. **Python 绑定边缘化**：Python 仅作 Thin Wrapper，业务逻辑 DSL 化
3. **状态管理工具化**：L4 状态通过 `state.read`/`state.write` 工具暴露
4. **Layer Profile 安全模型**：Cognitive/Thinking/Workflow 三层权限 Profile
5. **ABI 兼容性承诺**：C++ 公开头文件 5 年 ABI 稳定

---

## 1. 核心定位

本文档定义 AgenticOS v2.2 的接口契约，是所有层间交互的**唯一真理源**。

### 1.1 关键变更（v2.1.1 → v2.2）

| 变更项 | v2.1.1 | v2.2 | 说明 |
| :--- | :--- | :--- | :--- |
| **核心编排** | Python 胶水代码 | C++ DSL Runtime | L2/L3/L4 逻辑 DSL 化 |
| **状态管理** | L4 Python 状态 | C++ CognitiveStateManager | 状态工具化 (`state.read/write`) |
| **安全模型** | 基础权限验证 | Layer Profile 三重验证 | Cognitive/Thinking/Workflow |
| **LLM 适配** | 硬编码 Provider | ILLMProvider 工厂模式 | OpenAI/Anthropic/Local |
| **Python 绑定** | 业务逻辑混合 | Thin Wrapper（GIL 释放） | 消除 GIL 风险 |
| **接口稳定性** | 5 年稳定 | 5 年稳定 + ABI 承诺 | C++ 头文件 ABI 稳定 |
| **版本映射** | Arch v2.1.1 ↔ Lang v4.3 | Arch v2.2 ↔ Lang v4.4 | 同步升级 |

### 1.2 接口分层架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AgenticOS 接口契约 v2.2                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 6 (Application)                                                       │
│  ├─ IDeveloperService (开发者工具)                                           │
│  └─ IAppMarketService (应用市场)                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 5 (Interaction)                                                       │
│  ├─ IComponentRegistry (可视化组件)                                          │
│  └─ WebSocket Protocol (Layer 4/5 通信)                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 4.5 (Social)                                                          │
│  └─ ISocialService (社会协作)                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 4 (Cognitive)                                                         │
│  ├─ IConfidenceService (置信度服务) ← v2.2 增强                               │
│  ├─ IStateManager (状态管理) ← v2.2 新增                                      │
│  └─ ISessionManager (会话管理) ← v2.2 新增                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 3 (Reasoning)                                                         │
│  └─ IReasoningService (推理服务) ← v2.2 增强                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 2.5 (Standard Library)                                                │
│  └─ IStandardLibrary (标准库) ← v2.2 增强                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 2 (Execution)                                                         │
│  └─ GenericDomainAgent.execute() (领域执行)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 1 (Storage)                                                           │
│  └─ IDAGStore (DAG 存储)                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 0 (Resource) ← v2.2 核心                                               │
│  ├─ C++ Core API (唯一真理源)                                                 │
│  └─ Python 绑定 API (Thin Wrapper)                                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 核心设计原则

1. **C++ Core 优先：** C++ Core API 为唯一真理源，Python 绑定基于此封装
2. **状态工具化：** L4 状态通过 `state.read`/`state.write` 工具暴露，禁止直接内存访问
3. **Layer Profile 安全：** 所有接口调用需通过 Cognitive/Thinking/Workflow 权限验证
4. **纯函数约束：** L0 `compile()` 和 `execute_node()` 必须为纯函数，无副作用
5. **依赖注入：** L4 数据（如 `confidence_score`）必须通过参数显式传入，严禁 L0 反向依赖
6. **ABI 稳定：** C++ 公开头文件 5 年 ABI 稳定，符号版本控制
7. **GIL 释放：** Python 回调函数必须在 `py::gil_scoped_release` 保护下执行

---

## 2. 接口清单

### 2.1 完整接口矩阵

| 接口名称 | 调用方向 | 定义位置 | 稳定性 | 版本 | v2.2 变更 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C++ Core API** | L2/L3/L4 → agentic-dsl-runtime | `src/core/engine.h` | 5 年 (ABI) | v2.2 | **新增：唯一真理源** |
| **Python 绑定 API** | Python → C++ Core | `agentic_dsl` 模块 | 5 年 | v2.2 | 增强：GIL 释放策略 |
| **IDAGStore** | 所有层 → UniDAG-Store | `unidag-store` | 5 年 | v2.2 | 增强：优先级同步 |
| **IReasoningService** | brain-core → brain-thinking | `brain-thinking` | 5 年 | v2.2 | 增强：智能化字段 |
| **ISocialService** | brain-core → CiviMind | `brain-core` | 5 年 | v2.2 | 无变更 |
| **GenericDomainAgent.execute()** | brain-core → brain-domain-agent | `brain-domain-agent` | 5 年 | v2.2 | 无变更 |
| **IStandardLibrary** | brain-thinking → agentic-stdlib | `agentic-stdlib` | 5 年 | v2.2 | 增强：签名验证 |
| **IConfidenceService** | Layer 0/2/3 → brain-core | `brain-core` | 5 年 | v2.2 | 增强：风险评估 |
| **IStateManager** | Layer 2 → brain-core | `brain-core` | 5 年 | v2.2 | **新增：状态管理** |
| **ISessionManager** | Layer 4/5 → brain-core | `brain-core` | 5 年 | v2.2 | **新增：会话管理** |
| **ILLMProvider** | Layer 0/2 → LLM 后端 | `agentic-dsl-runtime` | 5 年 | v2.2 | **新增：LLM 工厂** |
| **IAppMarketService** | brain-core → agentic-sdk | `agentic-sdk` | 5 年 | v2.2 | 无变更 |
| **IComponentRegistry** | brain-domain-agent → brain-frontend | `brain-frontend` | 5 年 | v2.2 | 无变更 |
| **IDeveloperService** | 开发者工具 → brain-domain-agent | `brain-domain-agent` | 5 年 | v2.2 | 无变更 |
| **WebSocket 协议** | brain-frontend ↔ brain-core | 协议文档 | 5 年 | v2.2 | 增强：智能化消息 |

### 2.2 接口废弃计划

| 接口 | 废弃版本 | 移除版本 | 替代接口 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `Runtime.execute()` | v2.0 | v3.0 | `Runtime.execute_node()` | 违反纯函数原则 |
| `budget_inheritance: strict` (固定 50%) | v2.1.1 | v3.0 | `budget_inheritance: adaptive` | 智能化演进 |
| `require_human_approval: true` (硬约束) | v2.1.1 | v3.0 | `require_human_approval: risk_based` | 风险感知 |
| `ReasoningRequest.call_chain` (简单列表) | v2.1.1 | v3.0 | `ReasoningRequest.call_chain` (CallChainToken) | 死锁防护增强 |
| Python 业务逻辑接口 | v2.2 | v3.0 | C++ Core API + DSL | DSL-Centric 架构 |

---

## 3. C++ Core API（Layer 0）

### 3.1 接口定义

**v2.2 核心变更：** C++ Core API 为唯一真理源，所有上层接口基于此封装。

```cpp
// include/agentic_dsl/engine.h
#pragma once

#include <string>
#include <memory>
#include <functional>
#include <any>
#include <vector>
#include <map>

namespace agentic_dsl {

// 前向声明
class AST;
class Context;
class ExecutionBudget;
class ExecutionResult;
class CallChainToken;
class RiskAssessment;

/**
 * @brief AgenticDSL C++ 核心运行时接口（5 年 ABI 稳定契约）
 * 
 * Layer 0 核心接口，基于 AgenticDSL 引擎规范 v4.0
 * 
 * 保证：
 * - 纯函数式：compile() 和 execute_node() 无副作用
 * - 无状态：不维护任何会话状态
 * - 安全约束：命名空间验证、预算检查、死锁防护、Layer Profile 验证
 * - ABI 稳定：公开头文件 5 年 ABI 兼容
 * 
 * @since v2.2
 */
class DSLEngine {
public:
    virtual ~DSLEngine() = default;
    
    /**
     * @brief 编译 DSL 源码为 AST（纯函数）
     * 
     * @param source DSL 源码字符串
     * @return AST 抽象语法树
     * @throws CompileError 编译错误
     * @throws NamespaceViolationError 命名空间违规
     * @throws ProfileViolationError Layer Profile 违规（v2.2 新增）
     */
    virtual std::unique_ptr<AST> compile(const std::string& source) = 0;
    
    /**
     * @brief 从文件编译 DSL（纯函数）
     * 
     * @param file_path DSL 文件路径
     * @return AST 抽象语法树
     * @throws CompileError 编译错误
     * @throws FileNotFoundError 文件不存在
     */
    virtual std::unique_ptr<AST> compile_from_file(const std::string& file_path) = 0;
    
    /**
     * @brief 执行单个节点（纯函数，L2 驱动）
     * 
     * @param ast AST
     * @param node_path 节点路径
     * @param context 执行上下文（由 L2 维护）
     * @param budget 执行预算（含 confidence_score）
     * @return ExecutionResult 执行结果
     * @throws ExecutionError 执行错误
     * @throws BudgetExceededError 预算超限
     * @throws ProfileViolationError Layer Profile 违规（v2.2 新增）
     */
    virtual ExecutionResult execute_node(
        const AST& ast,
        const std::string& node_path,
        Context& context,
        const ExecutionBudget& budget
    ) = 0;
    
    /**
     * @brief 验证 AST 有效性
     * 
     * @param ast AST
     * @return bool 是否有效
     */
    virtual bool validate_ast(const AST& ast) = 0;
    
    /**
     * @brief 注册工具到 ToolRegistry
     * 
     * @param name 工具名称
     * @param handler 工具处理函数
     * @throws ToolRegistrationError 注册失败
     */
    template<typename Func>
    virtual void register_tool(const std::string& name, Func&& handler) = 0;
    
    /**
     * @brief 计算自适应预算比例（v2.2 新增）
     * 
     * @param confidence_score 置信度分数 (0.0-1.0)
     * @return float 预算比例 (0.3-0.7)
     */
    virtual float calculate_adaptive_budget_ratio(float confidence_score) = 0;
    
    /**
     * @brief 获取追踪记录
     * 
     * @return std::vector<TraceRecord> 追踪记录列表
     */
    virtual std::vector<TraceRecord> get_last_traces() const = 0;
    
    /**
     * @brief 设置 Layer Profile（v2.2 新增）
     * 
     * @param profile "Cognitive" | "Thinking" | "Workflow"
     */
    virtual void set_layer_profile(const std::string& profile) = 0;
    
    /**
     * @brief 获取当前 Layer Profile（v2.2 新增）
     * 
     * @return std::string 当前 Profile
     */
    virtual std::string get_layer_profile() const = 0;
    
    /**
     * @brief 创建引擎实例（工厂方法）
     * 
     * @return std::unique_ptr<DSLEngine> 引擎实例
     */
    static std::unique_ptr<DSLEngine> create();
};

} // namespace agentic_dsl
```

### 3.2 核心数据结构

```cpp
// include/agentic_dsl/types.h
#pragma once

#include <string>
#include <vector>
#include <map>
#include <any>
#include <memory>
#include <chrono>

namespace agentic_dsl {

/**
 * @brief AST 节点（5 年稳定）
 */
struct Node {
    std::string path;
    std::string type;
    std::map<std::string, std::any> properties;
    std::vector<std::string> next;
    
    // v2.2 新增：智能调度元数据
    struct Metadata {
        int priority = 0;              // 优先级（越高越优先）
        int estimated_cost = 0;        // 预估成本 (ms)
        bool critical_path = false;    // 是否在关键路径
    } metadata;
    
    // v2.2 新增：Layer Profile 声明
    struct LayerProfile {
        std::string profile_type;  // "Cognitive" | "Thinking" | "Workflow"
        std::vector<std::string> required_tools;
        std::vector<std::string> forbidden_tools;
    } layer_profile;
};

/**
 * @brief 抽象语法树（5 年稳定）
 */
class AST {
public:
    std::string version;
    std::string entry_point;
    std::map<std::string, Node> nodes;
    std::map<std::string, std::vector<std::string>> dependencies;
    
    // v2.2 新增：预算与人机协作配置
    struct Config {
        std::string budget_inheritance = "adaptive";      // strict/adaptive/custom
        std::string require_human_approval = "risk_based"; // true/false/risk_based
        float risk_threshold = 0.7f;                       // 风险阈值
        float confidence_score = 0.0f;                     // 置信度分数
        std::string layer_profile = "Workflow";            // v2.2 新增
    } config;
    
    // 序列化为 JSON
    std::string to_json() const;
    
    // 从 JSON 反序列化
    static std::unique_ptr<AST> from_json(const std::string& json_str);
};

/**
 * @brief 执行上下文（5 年稳定）
 * 
 * 由 L2 的 ExecutionContext 维护，L0 不维护会话状态
 */
class Context {
public:
    // 变量操作
    void set(const std::string& path, const std::any& value);
    std::any get(const std::string& path) const;
    bool has(const std::string& path) const;
    
    // 模板渲染
    std::string render_template(const std::string& template_str) const;
    
    // 序列化
    std::string to_json() const;
    void from_json(const std::string& json_str);
    
    // v2.2 增强：上下文快照（用于 try_catch 回溯）
    std::string snapshot() const;
    void restore(const std::string& snapshot);
    
    // v2.2 新增：只读快照上下文（用于动态子图沙箱）
    static Context create_readonly_snapshot(const Context& parent);
    
    // v2.2 新增：会话 ID 与用户 ID 传递
    void set_session_info(const std::string& session_id, const std::string& user_id);
    std::string get_session_id() const;
    std::string get_user_id() const;
    
    // v2.2 新增：Layer Profile 传递（用于运行期验证）
    void set_layer_profile(const std::string& profile);
    std::string get_layer_profile() const;
    
private:
    // 内部实现
};

/**
 * @brief 执行预算（5 年稳定）
 */
struct ExecutionBudget {
    // 原有字段
    int max_nodes = 50;              // 最大节点数
    int max_wall_time_ms = 60000;    // 墙钟时间
    int max_cpu_time_ms = 30000;     // CPU 时间
    int max_subgraph_depth = 3;      // 子图深度
    int max_llm_tokens = 10000;      // LLM Token 数
    int max_memory_mb = 512;         // 内存限制
    
    // 原子计数器（线程安全）
    mutable std::atomic<int> nodes_used{0};
    mutable std::atomic<int> llm_calls_used{0};
    mutable std::atomic<int> subgraph_depth_used{0};
    std::chrono::steady_clock::time_point start_time;
    
    // v2.2 新增：显式传入的置信度分数（通过 L2/L4 传入，非 L0 主动获取）
    float confidence_score = 0.0f;
    
    // v2.2 新增：预算继承策略
    std::string budget_inheritance = "adaptive";  // strict/adaptive/custom
    
    // v2.2 新增：Layer Profile
    std::string layer_profile = "Workflow";
    
    // 预算检查
    bool exceeded() const;
    bool try_consume_node();
    bool try_consume_llm_call();
    bool try_consume_subgraph_depth();
    
    // v2.2 新增：继承子预算
    ExecutionBudget inherit_child(float confidence_score) const;
};

/**
 * @brief 执行结果（5 年稳定）
 */
struct ExecutionResult {
    bool success;
    std::any output;
    std::string trace;
    std::map<std::string, std::any> budget_usage;
    
    // v2.2 新增：智能化演进字段
    struct Intelligence {
        std::string budget_inheritance;
        float confidence_score;
        float budget_ratio;
        std::string human_approval;
        std::string risk_assessment;
    } intelligence;
};

/**
 * @brief 调用链 Token（死锁防护，v2.2 增强）
 */
class CallChainToken {
public:
    CallChainToken(const std::vector<std::string>& path = {}, int max_depth = 3);
    
    // 为子调用创建派生 Token
    CallChainToken fork(const std::string& new_call) const;
    
    // 检查循环依赖
    bool has_circular_dependency() const;
    
    // 检查递归深度
    bool exceeds_max_depth() const;
    
    // 序列化
    std::vector<std::string> to_list() const;
    static CallChainToken from_list(const std::vector<std::string>& list);
    
private:
    std::vector<std::string> path_;
    int max_depth_;
};

/**
 * @brief 风险评估（v2.2 新增）
 */
struct RiskAssessment {
    std::string level;  // "low" | "medium" | "high" | "critical"
    float score;        // 0.0-1.0
    std::vector<std::string> factors;
};

/**
 * @brief 追踪记录（v2.2 增强）
 */
struct TraceRecord {
    std::string trace_id;
    std::string node_path;
    std::string type;
    std::chrono::system_clock::time_point start_time;
    std::chrono::system_clock::time_point end_time;
    std::string status;
    std::optional<std::string> error_code;
    std::map<std::string, std::any> context_delta;
    std::optional<std::string> ctx_snapshot_key;
    std::map<std::string, std::any> budget_snapshot;
    std::map<std::string, std::any> metadata;
    std::optional<std::string> llm_intent;
    std::string mode;
    
    // v2.2 新增：双循环标识
    std::string loop_type;  // "coarse" (L3) | "fine" (L0/L2)
    
    // v2.2 新增：智能化演进字段
    struct Intelligence {
        std::string budget_inheritance;
        float confidence_score;
        float budget_ratio;
        std::string human_approval;
        std::string risk_assessment;
    } intelligence;
    
    // v2.2 新增：Session 标识
    std::string session_id;
    std::string user_id;
    
    // v2.2 新增：Layer Profile
    std::string layer_profile;
};

} // namespace agentic_dsl
```

### 3.3 异常类型

```cpp
// include/agentic_dsl/errors.h
#pragma once

#include <stdexcept>
#include <string>

namespace agentic_dsl {

class CompileError : public std::runtime_error {
public:
    explicit CompileError(const std::string& message)
        : std::runtime_error(message) {}
};

class ExecutionError : public std::runtime_error {
public:
    explicit ExecutionError(const std::string& message)
        : std::runtime_error(message) {}
};

class BudgetExceededError : public std::runtime_error {
public:
    explicit BudgetExceededError(const std::string& message)
        : std::runtime_error(message) {}
};

class NamespaceViolationError : public std::runtime_error {
public:
    explicit NamespaceViolationError(const std::string& message)
        : std::runtime_error(message) {}
};

class CircularDependencyError : public std::runtime_error {
public:
    explicit CircularDependencyError(const std::string& message)
        : std::runtime_error(message) {}
};

class ConstraintViolationError : public std::runtime_error {
public:
    explicit ConstraintViolationError(const std::string& message)
        : std::runtime_error(message) {}
};

// v2.2 新增：Layer Profile 违规
class ProfileViolationError : public std::runtime_error {
public:
    explicit ProfileViolationError(const std::string& message)
        : std::runtime_error(message) {}
};

// v2.2 新增：状态工具错误
class StateToolError : public std::runtime_error {
public:
    explicit StateToolError(const std::string& message)
        : std::runtime_error(message) {}
};

// v2.2 新增：LLM 配置错误
class LLMConfigError : public std::runtime_error {
public:
    explicit LLMConfigError(const std::string& message)
        : std::runtime_error(message) {}
};

} // namespace agentic_dsl
```

---

## 4. Python 绑定 API（Layer 0）

### 4.1 接口定义

**v2.2 核心变更：** Python 仅作 Thin Wrapper，所有 Python 回调函数必须在 `py::gil_scoped_release` 保护下执行。

```python
# interfaces/python_bindings.py
from typing import Protocol, Dict, Any, Optional, List, Callable
from dataclasses import dataclass, field
from enum import Enum
import json

class AgenticDSLRuntime(Protocol):
    """
    AgenticDSL C++ 运行时 Python 绑定接口（5 年稳定契约）
    
    Layer 0 核心接口，基于 AgenticDSL 引擎规范 v4.0
    
    保证：
    - 纯函数式：compile() 和 execute_node() 无副作用
    - 无状态：不维护任何会话状态
    - 安全约束：命名空间验证、预算检查、死锁防护、Layer Profile 验证
    - GIL 释放：Python 回调函数在 py::gil_scoped_release 保护下执行
    
    v2.2 变更：
    - 新增 Layer Profile 支持
    - 新增 state.read/write 工具注册
    - 新增自适应预算计算
    - 新增 ILLMProvider 工厂模式
    """
    
    def compile(self, source: str) -> 'AST':
        """
        编译 DSL 源码为 AST（纯函数）
        
        Args:
            source: DSL 源码字符串
            
        Returns:
            AST: 抽象语法树
            
        Raises:
            CompileError: 编译错误
            NamespaceViolationError: 命名空间违规
            ProfileViolationError: Layer Profile 违规（v2.2 新增）
        """
        pass
    
    def compile_from_file(self, file_path: str) -> 'AST':
        """
        从文件编译 DSL（纯函数）
        
        Args:
            file_path: DSL 文件路径
            
        Returns:
            AST: 抽象语法树
            
        Raises:
            CompileError: 编译错误
            FileNotFoundError: 文件不存在
        """
        pass
    
    def execute_node(self, 
                     ast: 'AST', 
                     node_path: str, 
                     context: 'Context',
                     budget: 'ExecutionBudget') -> 'ExecutionResult':
        """
        执行单个节点（纯函数，L2 驱动）
        
        Args:
            ast: AST
            node_path: 节点路径
            context: 执行上下文（由 L2 维护）
            budget: 执行预算（含 confidence_score）
            
        Returns:
            ExecutionResult: 执行结果
            
        Raises:
            ExecutionError: 执行错误
            BudgetExceededError: 预算超限
            ProfileViolationError: Layer Profile 违规（v2.2 新增）
        """
        pass
    
    def validate_ast(self, ast: 'AST') -> bool:
        """
        验证 AST 有效性
        
        Args:
            ast: AST
            
        Returns:
            bool: 是否有效
        """
        pass
    
    def register_tool(self, name: str, handler: Callable[[Dict[str, str]], Any]) -> None:
        """
        注册工具到 ToolRegistry
        
        Args:
            name: 工具名称
            handler: 工具处理函数（自动 GIL 释放）
            
        Raises:
            ToolRegistrationError: 注册失败
        """
        pass
    
    def calculate_adaptive_budget_ratio(self, confidence_score: float) -> float:
        """
        计算自适应预算比例（v2.2 新增）
        
        Args:
            confidence_score: 置信度分数 (0.0-1.0)
            
        Returns:
            float: 预算比例 (0.3-0.7)
        """
        pass
    
    def set_layer_profile(self, profile: str) -> None:
        """
        设置 Layer Profile（v2.2 新增）
        
        Args:
            profile: "Cognitive" | "Thinking" | "Workflow"
        """
        pass
    
    def get_layer_profile(self) -> str:
        """
        获取当前 Layer Profile（v2.2 新增）
        
        Returns:
            str: 当前 Profile
        """
        pass
    
    def get_last_traces(self) -> List['TraceRecord']:
        """
        获取追踪记录
        
        Returns:
            List[TraceRecord]: 追踪记录列表
        """
        pass


@dataclass(frozen=True)
class AST:
    """抽象语法树（5 年稳定）"""
    version: str
    entry_point: str
    nodes: Dict[str, 'Node']
    dependencies: Dict[str, List[str]]
    
    # v2.2 新增：配置
    config: 'ASTConfig' = field(default_factory=lambda: ASTConfig())
    
    def to_json(self) -> str:
        """序列化为 JSON"""
        pass
    
    @classmethod
    def from_json(cls, json_str: str) -> 'AST':
        """从 JSON 反序列化"""
        pass


@dataclass(frozen=True)
class ASTConfig:
    """AST 配置（v2.2 新增）"""
    budget_inheritance: str = "adaptive"
    require_human_approval: str = "risk_based"
    risk_threshold: float = 0.7
    confidence_score: float = 0.0
    layer_profile: str = "Workflow"


@dataclass(frozen=True)
class Node:
    """AST 节点（5 年稳定）"""
    path: str
    type: str
    properties: Dict[str, Any]
    next: List[str]
    
    # v2.2 新增：智能调度元数据
    metadata: 'NodeMetadata' = field(default_factory=lambda: NodeMetadata())
    
    # v2.2 新增：Layer Profile 声明
    layer_profile: 'LayerProfile' = field(default_factory=lambda: LayerProfile())


@dataclass(frozen=True)
class NodeMetadata:
    """节点元数据（v2.2 新增）"""
    priority: int = 0
    estimated_cost: int = 0
    critical_path: bool = False


@dataclass(frozen=True)
class LayerProfile:
    """Layer Profile 声明（v2.2 新增）"""
    profile_type: str = "Workflow"  # "Cognitive" | "Thinking" | "Workflow"
    required_tools: List[str] = field(default_factory=list)
    forbidden_tools: List[str] = field(default_factory=list)


@dataclass(frozen=True)
class Context:
    """执行上下文（5 年稳定）"""
    data: Dict[str, Any] = field(default_factory=dict)
    
    def set(self, path: str, value: Any) -> None:
        """设置变量"""
        pass
    
    def get(self, path: str) -> Any:
        """获取变量"""
        pass
    
    def has(self, path: str) -> bool:
        """检查变量是否存在"""
        pass
    
    def to_json(self) -> str:
        """序列化为 JSON"""
        pass
    
    @classmethod
    def from_json(cls, json_str: str) -> 'Context':
        """从 JSON 反序列化"""
        pass
    
    # v2.2 增强：上下文快照
    def snapshot(self) -> str:
        """创建快照（用于 try_catch 回溯）"""
        pass
    
    def restore(self, snapshot: str) -> None:
        """恢复快照"""
        pass
    
    # v2.2 新增：只读快照上下文
    @staticmethod
    def create_readonly_snapshot(parent: 'Context') -> 'Context':
        """创建只读快照（用于动态子图沙箱）"""
        pass
    
    # v2.2 新增：会话 ID 与用户 ID 传递
    def set_session_info(self, session_id: str, user_id: str) -> None:
        """设置会话信息"""
        pass
    
    def get_session_id(self) -> str:
        """获取会话 ID"""
        pass
    
    def get_user_id(self) -> str:
        """获取用户 ID"""
        pass
    
    # v2.2 新增：Layer Profile 传递
    def set_layer_profile(self, profile: str) -> None:
        """设置 Layer Profile"""
        pass
    
    def get_layer_profile(self) -> str:
        """获取 Layer Profile"""
        pass


@dataclass(frozen=True)
class ExecutionBudget:
    """执行预算（5 年稳定）"""
    max_nodes: int = 50
    max_wall_time_ms: int = 60000
    max_cpu_time_ms: int = 30000
    max_subgraph_depth: int = 3
    max_llm_tokens: int = 10000
    max_memory_mb: int = 512
    
    # v2.2 新增：置信度分数（显式传入）
    confidence_score: float = 0.0
    
    # v2.2 新增：预算继承策略
    budget_inheritance: str = "adaptive"
    
    # v2.2 新增：Layer Profile
    layer_profile: str = "Workflow"
    
    def inherit_child(self, confidence_score: float) -> 'ExecutionBudget':
        """继承子预算（v2.2 新增）"""
        pass
    
    def exceeded(self) -> bool:
        """检查预算是否超限"""
        pass


@dataclass(frozen=True)
class ExecutionResult:
    """执行结果（5 年稳定）"""
    success: bool
    output: Any
    trace: str
    budget_usage: Dict[str, Any]
    
    # v2.2 新增：智能化演进字段
    intelligence: 'IntelligenceInfo' = field(default_factory=lambda: IntelligenceInfo())


@dataclass(frozen=True)
class IntelligenceInfo:
    """智能化演进信息（v2.2 新增）"""
    budget_inheritance: str = "adaptive"
    confidence_score: float = 0.0
    budget_ratio: float = 0.5
    human_approval: str = "auto_approved"
    risk_assessment: str = "low"


@dataclass(frozen=True)
class TraceRecord:
    """追踪记录（v2.2 增强）"""
    trace_id: str
    node_path: str
    type: str
    start_time: str
    end_time: str
    status: str
    error_code: Optional[str] = None
    context_delta: Dict[str, Any] = field(default_factory=dict)
    budget_snapshot: Dict[str, Any] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    # v2.2 新增：双循环标识
    loop_type: Optional[str] = None  # "coarse" | "fine"
    
    # v2.2 新增：智能化演进字段
    intelligence: Optional[IntelligenceInfo] = None
    
    # v2.2 新增：Session 标识
    session_id: Optional[str] = None
    user_id: Optional[str] = None
    
    # v2.2 新增：Layer Profile
    layer_profile: Optional[str] = None


@dataclass(frozen=True)
class CallChainToken:
    """调用链 Token（死锁防护，v2.2 增强）"""
    path: List[str] = field(default_factory=list)
    max_depth: int = 3
    
    def fork(self, new_call: str) -> 'CallChainToken':
        """为子调用创建派生 Token"""
        pass
    
    def has_circular_dependency(self) -> bool:
        """检查循环依赖"""
        pass
    
    def exceeds_max_depth(self) -> bool:
        """检查递归深度"""
        pass
    
    def to_list(self) -> List[str]:
        """序列化为列表"""
        pass
    
    @classmethod
    def from_list(cls, list_data: List[str]) -> 'CallChainToken':
        """从列表反序列化"""
        pass


@dataclass(frozen=True)
class RiskAssessment:
    """风险评估（v2.2 新增）"""
    level: str  # "low" | "medium" | "high" | "critical"
    score: float  # 0.0-1.0
    factors: List[str] = field(default_factory=list)
```

### 4.2 异常类型

```python
# interfaces/python_bindings.py
class CompileError(Exception):
    """编译错误"""
    pass


class ExecutionError(Exception):
    """执行错误"""
    pass


class BudgetExceededError(Exception):
    """预算超限"""
    pass


class NamespaceViolationError(Exception):
    """命名空间违规（v2.1.1 新增）"""
    pass


class CircularDependencyError(Exception):
    """循环依赖（v2.1.1 新增）"""
    pass


class ConstraintViolationError(Exception):
    """约束违反（v2.1.1 新增）"""
    pass


class ProfileViolationError(Exception):
    """Layer Profile 违规（v2.2 新增）"""
    pass


class StateToolError(Exception):
    """状态工具错误（v2.2 新增）"""
    pass


class LLMConfigError(Exception):
    """LLM 配置错误（v2.2 新增）"""
    pass


class ToolRegistrationError(Exception):
    """工具注册错误"""
    pass
```

### 4.3 Python 使用示例

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

budget = ExecutionBudget(
    max_nodes=50,
    confidence_score=0.85,  # v2.2 新增：显式传入
    budget_inheritance="adaptive",  # v2.2 新增
    layer_profile="Workflow"  # v2.2 新增
)

result = engine.execute_node(ast, "/main/start", context, budget)

# ❌ 禁止：L0 内部维护状态
# engine.execute_loop(ast)  # 违反纯函数原则

# ✅ 正确：L2 驱动细粒度循环
# for node_path in topo_sort(ast):
#     result = engine.execute_node(ast, node_path, context, budget)

# v2.2: 自适应预算计算（confidence_score 显式传入）
budget_ratio = engine.calculate_adaptive_budget_ratio(confidence_score=0.85)
# 返回 0.7 (高置信度 70% 预算)

# v2.2: 注册 state 工具（由 L2 注入，GIL 自动释放）
engine.register_tool("state.read", lambda args: state_manager.read(args["key"]))
engine.register_tool("state.write", lambda args: state_manager.write(args["key"], args["value"]))

# v2.2: 设置 Layer Profile
engine.set_layer_profile("Cognitive")

# v2.2: 获取追踪记录
traces = engine.get_last_traces()
```

---

## 5. IDAGStore（Layer 1）

### 5.1 接口定义

```python
# interfaces/dag_store.py
from typing import Protocol, Dict, Any, Optional, List
from dataclasses import dataclass
from datetime import datetime

class IDAGStore(Protocol):
    """
    DAG 存储接口（5 年稳定契约）
    
    所有层通过此接口与 UniDAG-Store 交互
    
    保证：
    - retrieve() 必须返回不可变快照（Immutable Snapshot）
    - 版本管理：自动递增 version 字段
    - 审计追踪：所有操作记录 audit_log
    - 同步支持：支持向量时钟冲突检测
    - 优先级同步：支持 critical/standard/background 优先级
    
    v2.2 变更：
    - 新增 retrieve_stdlib() 标准库读取
    - 增强 persist() 支持优先级同步
    """
    
    async def persist(self,
                     dag: 'UnifiedDAG',
                     meta: Optional[Dict[str, Any]] = None,
                     user_id: Optional[str] = None,
                     priority: str = "standard") -> str:
        """
        持久化 DAG
        
        Args:
            dag: 要持久化的 DAG
            meta: 元数据
            user_id: 用户 ID
            priority: 同步优先级 ("critical" | "standard" | "background")
            
        Returns:
            str: 快照 ID
        """
        pass
    
    async def retrieve(self, dag_id: str) -> Optional['UnifiedDAG']:
        """
        检索 DAG
        
        保证：返回不可变快照
        
        Args:
            dag_id: DAG ID
            
        Returns:
            Optional[UnifiedDAG]: DAG 或 None
        """
        pass
    
    async def retrieve_stdlib(self, 
                             path: str,  # /lib/**
                             version: str) -> Optional['UnifiedDAG']:
        """
        从 Layer 2.5 标准库读取模板（v2.1.1 新增）
        
        保证：只读、签名验证
        
        Args:
            path: 标准库路径
            version: 版本号
            
        Returns:
             Optional[UnifiedDAG]: 标准库模板
        """
        pass
    
    async def get_version(self, dag_id: str) -> int:
        """
        获取 DAG 版本
        
        Args:
            dag_id: DAG ID
            
        Returns:
            int: 版本号
        """
        pass
    
    async def list_snapshots(self,
                            dag_id: str,
                            limit: int = 10) -> List['SnapshotInfo']:
        """
        列出 DAG 快照
        
        Args:
            dag_id: DAG ID
            limit: 最大数量
            
        Returns:
            List[SnapshotInfo]: 快照列表
        """
        pass
    
    async def vector_search(self,
                           query_vector: List[float],
                           top_k: int = 10,
                           filter: Optional[Dict] = None) -> List['SearchResult']:
        """
        向量搜索
        
        Args:
            query_vector: 查询向量
            top_k: 返回数量
            filter: 过滤条件
            
        Returns:
            List[SearchResult]: 搜索结果
        """
        pass


@dataclass(frozen=True)
class SnapshotInfo:
    """快照信息（5 年稳定）"""
    snapshot_id: str
    dag_id: str
    version: int
    created_at: datetime
    meta: Dict[str, Any]


@dataclass(frozen=True)
class SearchResult:
    """搜索结果（5 年稳定）"""
    node_id: str
    dag_id: str
    score: float
    metadata: Dict[str, Any]
```

---

## 6. IReasoningService（Layer 3）

### 6.1 接口定义

```python
# interfaces/reasoning_service.py
from typing import Protocol, Dict, Any, Optional, List, AsyncIterator
from dataclasses import dataclass

class IReasoningService(Protocol):
    """
    推理服务接口（5 年稳定契约）
    
    brain-core 通过此接口调用 brain-thinking
    
    保证：
    - 离线支持：offline_ok=True 时无网络依赖
    - 轨迹持久化：100% 步骤持久化到 UniDAG-Store
    - 超时熔断：超过 timeout_sec 自动中止
    - 错误封装：异常转换为 ReasoningResponse.error
    - 死锁防护：调用链 Token 检测循环依赖
    - 流式输出：execute_stream() 支持实时 Thought/Action
    - 智能化演进：支持自适应预算、风险感知人机协作
    
    v2.2 变更：
    - 增强 ReasoningRequest 智能化字段
    - 新增 layer_profile 字段
    - 增强 ReasoningStreamChunk loop_type 标识
    """
    
    async def execute(self, request: 'ReasoningRequest') -> 'ReasoningResponse':
        """
        执行推理任务
        
        Args:
            request: 推理请求
            
        Returns:
            ReasoningResponse: 推理响应
        """
        pass
    
    async def execute_stream(self, 
                            request: 'ReasoningRequest') -> AsyncIterator['ReasoningStreamChunk']:
        """
        流式执行推理任务
        
        用于实时返回 Thought 和 Action 到 Layer 5
        
        Yields:
            ReasoningStreamChunk: 流式输出块
        """
        pass


@dataclass(frozen=True)
class ReasoningRequest:
    """推理请求（5 年稳定，v2.2 增强）"""
    user_id: str
    session_id: str
    task: str
    domain_id: str
    context: Dict[str, Any]
    max_steps: int = 10
    timeout_sec: float = 120.0
    offline_ok: bool = True
    multi_view: bool = False
    
    # 死锁防护字段（v2.0 新增）
    call_chain: List[str] = None  # 调用链 Token
    recursion_depth: int = 0      # 当前递归深度
    
    # 智能化演进字段（v2.1.1 新增）
    budget_inheritance: str = "adaptive"  # 预算继承策略 (strict/adaptive/custom)
    require_human_approval: str = "risk_based"  # 人机协作策略 (true/false/risk_based)
    risk_threshold: float = 0.7  # 风险阈值
    confidence_score: Optional[float] = None  # 置信度分数（用于自适应预算）
    
    # v2.2 新增：Layer Profile
    layer_profile: str = "Workflow"  # "Cognitive" | "Thinking" | "Workflow"
    
    def __post_init__(self):
        if self.call_chain is None:
            object.__setattr__(self, 'call_chain', [])
    
    def fork_for_subcall(self, subcall_id: str) -> 'ReasoningRequest':
        """为子调用创建派生请求"""
        # 检查循环依赖
        if subcall_id in self.call_chain:
            raise CircularDependencyError(
                f"Circular dependency detected: {subcall_id} in {self.call_chain}"
            )
        
        # 检查递归深度
        max_recursion = 3
        if self.recursion_depth >= max_recursion:
            raise RecursionDepthExceededError(
                f"Recursion depth exceeded: {self.recursion_depth} >= {max_recursion}"
            )
        
        return ReasoningRequest(
            user_id=self.user_id,
            session_id=self.session_id,
            task=self.task,
            domain_id=self.domain_id,
            context=self.context,
            max_steps=self.max_steps,
            timeout_sec=self.timeout_sec,
            offline_ok=self.offline_ok,
            multi_view=self.multi_view,
            call_chain=self.call_chain + [subcall_id],
            recursion_depth=self.recursion_depth + 1,
            budget_inheritance=self.budget_inheritance,
            require_human_approval=self.require_human_approval,
            risk_threshold=self.risk_threshold,
            confidence_score=self.confidence_score,
            layer_profile=self.layer_profile  # v2.2 新增
        )


@dataclass(frozen=True)
class ReasoningResponse:
    """推理响应（5 年稳定）"""
    trace_id: str
    domain_id: str
    final_answer: Optional[str]
    status: str  # "completed" | "timeout" | "error" | "offline" | "circular_dependency"
    offline_mode: bool
    dag_snapshot_id: Optional[str]
    metadata: Dict[str, Any]


@dataclass(frozen=True)
class ReasoningStreamChunk:
    """推理流式输出块（v2.0 新增）"""
    chunk_type: str  # "thought" | "action" | "observation" | "complete" | "error"
    content: str
    step_number: Optional[int] = None
    timestamp: float = 0.0
    loop_type: Optional[str] = None  # "coarse" | "fine" (v2.1.1 新增)
```

---

## 7. ISocialService（Layer 4.5）

### 7.1 接口定义

```python
# interfaces/social_service.py
from typing import Protocol, Dict, Any, Optional, List
from dataclasses import dataclass
from datetime import datetime

class ISocialService(Protocol):
    """
    社会协作服务接口（5 年稳定契约）
    
    brain-core 通过此接口调用社会协作能力（CiviMind）
    
    保证：
    - 隐私保护：用户数据端侧加密，密钥永不离开设备
    - 契约可追溯：100% 契约 DAG 持久化到 UniDAG-Store
    - 声誉可验证：支持零知识证明验证
    - 应用市场集成：与 DomainRegistry 同步 agent 声誉
    """
    
    async def negotiate(self, request: 'NegotiationRequest') -> 'ContractDAG':
        """
        发起谈判并生成契约 DAG
        
        Args:
            request: 谈判请求，包含意图、约束条件、参与方
            
        Returns:
            ContractDAG: 签署的契约 DAG
            
        Raises: 
            NegotiationTimeoutError: 谈判超时
            ValueConstraintViolation: 价值观约束冲突
        """
        pass
    
    async def notarize(self, contract: 'ContractDAG') -> 'NotaryReceipt':
        """
        契约存证
        
        Args:
            contract: 待存证的契约 DAG
            
        Returns:
            NotaryReceipt: 存证收据，包含时间戳和哈希
        """
        pass
    
    async def query_reputation(self, did: str) -> 'ReputationScore':
        """
        查询声誉分数
        
        Args:
            did: 去中心化身份标识
            
        Returns:
            ReputationScore: 声誉评分详情
        """
        pass
    
    async def broadcast_intent(self, intent: 'SignedIntent') -> List['MatchResult']:
        """
        广播意图并获取匹配结果
        
        Args:
            intent: 签名的意图
            
        Returns:
            List[MatchResult]: 匹配结果列表
        """
        pass
    
    async def sync_agent_reputation(self, agent_id: str) -> bool:
        """
        同步第三方 agent 声誉信息到 DomainRegistry（v2.1.1 新增）
        
        Args:
            agent_id: agent 唯一标识
            
        Returns:
            bool: 同步是否成功
        """
        pass
    
    async def prove_reputation_above(self, 
                                    did: str, 
                                    threshold: float) -> Optional[str]:
        """
        生成零知识证明：证明声誉高于阈值而不暴露具体分数
        
        Args:
            did: DID
            threshold: 阈值 (0-100)
            
        Returns:
            str: ZK proof（可公开验证），或 None（无法证明）
        """
        pass


@dataclass(frozen=True)
class NegotiationRequest:
    """谈判请求（5 年稳定）"""
    initiator_did: str                    # 发起方 DID
    participants: List[str]               # 参与方 DID 列表
    intent: str                           # 协作意图描述
    constraints: Dict[str, Any]           # 约束条件（预算、时间等）
    value_preferences: Dict[str, Any]     # 价值观偏好
    timeout_sec: float = 300.0            # 谈判超时时间
    max_rounds: int = 10                   # 最大谈判轮数


@dataclass(frozen=True)
class ContractDAG:
    """契约 DAG（5 年稳定）"""
    contract_id: str                      # 契约唯一 ID
    dag: 'UnifiedDAG'                     # 执行 DAG
    participants: List[str]               # 参与方 DID 列表
    signatures: Dict[str, str]            # 各方签名
    created_at: datetime
    expires_at: Optional[datetime]
    status: str                           # "draft" | "signed" | "executing" | "completed" | "breached"


@dataclass(frozen=True)
class NotaryReceipt:
    """存证收据（5 年稳定）"""
    receipt_id: str                       # 收据 ID
    contract_hash: str                    # 契约哈希
    timestamp: datetime
    notary_proof: str                     # 存证证明（可用于验证）


@dataclass(frozen=True)
class ReputationScore:
    """声誉评分（5 年稳定）"""
    did: str
    overall_score: float                  # 总体评分 (0-100)
    fulfillment_rate: float               # 履约率
    response_time_score: float            # 响应速度评分
    dispute_loss_rate: float              # 争议败诉率
    total_contracts: int                  # 总契约数
    successful_contracts: int             # 成功履约数
    last_updated: datetime


@dataclass(frozen=True)
class SignedIntent:
    """签名意图（5 年稳定）"""
    intent_id: str
    topic: str                            # 意图主题
    goal: str                             # 目标描述
    constraints: Dict[str, Any]           # 约束条件
    personality_hash: str                 # 人格指纹哈希
    signature: str                        # 数字签名
    timestamp: datetime


@dataclass(frozen=True)
class MatchResult:
    """匹配结果（5 年稳定）"""
    did: str                              # 匹配方 DID
    compatibility_score: float            # 兼容性评分
    reputation_score: float               # 声誉评分
    estimated_cost: Optional[float]       # 预估成本
    response_time_ms: int                 # 响应时间
```

---

## 8. GenericDomainAgent.execute()（Layer 2）

### 8.1 接口定义

```python
# interfaces/domain_agent.py
from typing import Protocol, Dict, Any, Optional
from dataclasses import dataclass

class GenericDomainAgent(Protocol):
    """
    通用领域智能体接口（5 年稳定契约）
    
    brain-core 通过此接口调用领域执行引擎
    
    双重角色：
    1. 执行引擎：被 brain-core 调用
    2. 可开发应用：被开发者工具扩展
    
    稳定接口：
        execute(directive, context, timeout_sec) -> ExecutionResult
    """
    
    async def execute(self,
                     directive: str,
                     context: Dict[str, Any],
                     timeout_sec: Optional[float] = None) -> 'ExecutionResult':
        """
        执行入口
        
        稳定契约：
        - 输入：自然语言指令 + 上下文
        - 输出：ExecutionResult（结构化结果）
        - 保证：超时熔断、异常封装、状态清理、死锁检测
        """
        pass
    
    async def register_component(self, 
                                component_spec: 'ComponentSpec') -> bool:
        """
        注册可视化组件到 Layer 5（v2.1.1 新增）
        
        Args:
            component_spec: 组件规范
            
        Returns:
            bool: 注册是否成功
        """
        pass


@dataclass(frozen=True)
class ExecutionResult:
    """执行结果（5 年稳定）"""
    status: str  # "completed" | "timeout" | "error" | "circular_dependency"
    summary: str
    artifacts: Dict[str, Any]
    dag_snapshot_id: Optional[str]
    execution_metadata: Dict[str, Any]


@dataclass(frozen=True)
class ComponentSpec:
    """组件规范（5 年稳定，v2.1.1 新增）"""
    component_id: str
    render_type: str  # "markdown" | "code_diff" | "dag_view" | "custom"
    data_schema: Dict[str, Any]  # 数据契约
    render_logic: str  # 渲染逻辑（DSL 或 JavaScript）
    domain_id: str  # 所属领域
```

---

## 9. IStandardLibrary（Layer 2.5）

### 9.1 接口定义

```python
# interfaces/standard_library.py
from typing import Protocol, Dict, Any, Optional, List
from dataclasses import dataclass
from datetime import datetime

class IStandardLibrary(Protocol):
    """
    标准库服务接口（5 年稳定契约，v2.1.1 新增）
    
    brain-thinking 通过此接口加载 Layer 2.5 标准库模板
    
    保证：
    - 只读访问：/lib/** 禁止运行时修改
    - 签名验证：所有标准库子图必须通过签名验证
    - 版本管理：支持@v1, @v2 等版本标识
    - 预算继承：strict 模式默认 50%，adaptive 模式基于置信度
    
    v2.2 变更：
    - 增强 load_template() 签名验证
    - 新增缓存策略
    - 新增分层加载（/lib/cognitive/**, /lib/thinking/**, /lib/workflow/**）
    """
    
    async def load_template(self, 
                           path: str,  # 如 "/lib/reasoning/react"
                           version: str = "v1.0") -> Optional['UnifiedDAG']:
        """
        加载标准 DSL 模板（只读）
        
        Args:
            path: 标准库路径（/lib/**）
            version: 版本号（@v1, @v2 等）
            
        Returns:
            Optional[UnifiedDAG]: 标准库子图（只读快照）
            
        Raises:
            NamespaceViolationError: 尝试访问非/lib/**路径
            SignatureVerificationError: 签名验证失败
        """
        pass
    
    async def list_templates(self, 
                            category: str) -> List['TemplateInfo']:
        """
        列出可用模板
        
        Args:
            category: 分类（cognitive/thinking/workflow/reasoning/memory/conversation）
            
        Returns:
            List[TemplateInfo]: 模板信息列表
        """
        pass
    
    async def verify_signature(self, 
                              dag: 'UnifiedDAG', 
                              expected_signature: str) -> bool:
        """
        验证标准库签名
        
        Args:
            dag: 待验证的 DAG
            expected_signature: 期望的签名
            
        Returns:
            bool: 验证是否通过
        """
        pass
    
    # v2.2 新增：缓存管理
    async def clear_cache(self, path: Optional[str] = None) -> None:
        """
        清除缓存
        
        Args:
            path: 可选，清除指定路径缓存，None 则清除全部
        """
        pass
    
    # v2.2 新增：分层加载
    async def load_layer_templates(self, 
                                   layer: str) -> List['UnifiedDAG']:
        """
        加载指定层的所有模板
        
        Args:
            layer: "cognitive" | "thinking" | "workflow"
            
        Returns:
            List[UnifiedDAG]: 模板列表
        """
        pass


@dataclass(frozen=True)
class TemplateInfo:
    """模板信息（5 年稳定）"""
    path: str
    version: str
    description: str
    signature: str
    created_at: datetime
    updated_at: datetime
    stability: str  # "stable" | "experimental" | "deprecated"
    inputs: Dict[str, Any]  # 输入参数 schema
    outputs: Dict[str, Any]  # 输出参数 schema
    layer_profile: str  # v2.2 新增："Cognitive" | "Thinking" | "Workflow"
```

---

## 10. IConfidenceService（Layer 4）

### 10.1 接口定义

```python
# interfaces/confidence_service.py
from typing import Protocol, Dict, Any, Optional
from dataclasses import dataclass

class IConfidenceService(Protocol):
    """
    置信度服务接口（5 年稳定契约，v2.1.1 新增）
    
    为全系统提供置信度评估，支持智能化演进特性
    
    保证：
    - 自适应预算：基于置信度动态调整预算比例
    - 风险感知：评估操作风险等级
    - 人机协作：动态决定人工确认需求
    
    v2.2 变更：
    - 增强 calculate_budget_ratio() 支持 custom 模式
    - 新增 assess_risk() 风险评估
    """
    
    def calculate_budget_ratio(self, confidence_score: float) -> float:
        """
        计算预算比例
        
        Args:
            confidence_score: 置信度分数 (0.0-1.0)
            
        Returns:
            float: 预算比例 (0.3-0.7)
        """
        pass
    
    def requires_human_approval(self, 
                               operation_risk: float, 
                               confidence_score: float) -> bool:
        """
        判断是否需要人工确认
        
        Args:
            operation_risk: 操作风险 (0.0-1.0)
            confidence_score: 置信度分数 (0.0-1.0)
            
        Returns:
            bool: 是否需要人工确认
        """
        pass
    
    def assess_risk(self, operation: Dict[str, Any]) -> 'RiskAssessment':
        """
        评估操作风险（v2.2 新增）
        
        Args:
            operation: 操作描述
            
        Returns:
            RiskAssessment: 风险评估结果
        """
        pass
    
    def get_confidence_level(self) -> str:
        """
        获取置信度等级（v2.2 新增）
        
        Returns:
            str: "HIGH" | "MEDIUM" | "LOW"
        """
        pass
    
    def get_confidence_score(self) -> float:
        """
        获取当前置信度分数（v2.2 新增）
        
        Returns:
            float: 置信度分数 (0.0-1.0)
        """
        pass


@dataclass(frozen=True)
class RiskAssessment:
    """风险评估（5 年稳定）"""
    level: str  # "low" | "medium" | "high" | "critical"
    score: float  # 0.0-1.0
    factors: List[str]
```

---

## 11. IStateManager（Layer 4）

### 11.1 接口定义

**v2.2 新增：** L4 状态管理接口，通过 `state.read`/`state.write` 工具暴露给 DSL。

```python
# interfaces/state_manager.py
from typing import Protocol, Dict, Any, Optional, Callable
from dataclasses import dataclass
from datetime import datetime

class IStateManager(Protocol):
    """
    状态管理接口（5 年稳定契约，v2.2 新增）
    
    Layer 4 C++ 原生状态管理接口，通过 L2 StateToolAdapter 暴露给 DSL
    
    保证：
    - 端侧加密：用户上下文、记忆数据必须端侧加密
    - 版本向量：支持多端同步冲突检测
    - 会话隔离：不同 session_id 的状态严格隔离
    - 工具化访问：通过 state.read/write 工具访问，禁止直接内存访问
    
    安全约束：
    - ✅ DSL → state.read/write 工具 → L2 StateToolAdapter → L4 IStateManager
    - ❌ 禁止：DSL 直接访问 CognitiveStateManager 内存
    - ❌ 禁止：L2 工具绕过权限验证直接调用 L4 状态接口
    """
    
    def read(self, path: str) -> Any:
        """
        读取状态
        
        Args:
            path: 状态路径（如 "memory.profile.*", "session.user_id"）
            
        Returns:
            Any: 状态值
            
        Raises:
            StateToolError: 读取失败
            PermissionDeniedError: 权限不足
        """
        pass
    
    def write(self, path: str, value: Any) -> None:
        """
        写入状态（需事务支持）
        
        Args:
            path: 状态路径
            value: 状态值
            
        Raises:
            StateToolError: 写入失败
            PermissionDeniedError: 权限不足
            ProfileViolationError: Layer Profile 违规
        """
        pass
    
    def subscribe(self, path: str, callback: Callable[[Any], None]) -> None:
        """
        订阅状态变更
        
        Args:
            path: 状态路径
            callback: 回调函数
            
        Raises:
            StateToolError: 订阅失败
        """
        pass
    
    def get_version(self, path: str) -> 'VersionVector':
        """
        获取版本向量（用于冲突检测）
        
        Args:
            path: 状态路径
            
        Returns:
            VersionVector: 版本向量
        """
        pass
    
    def delete(self, path: str) -> None:
        """
        删除状态（v2.2 新增）
        
        Args:
            path: 状态路径
            
        Raises:
            StateToolError: 删除失败
            PermissionDeniedError: 权限不足
        """
        pass


@dataclass(frozen=True)
class VersionVector:
    """版本向量（5 年稳定）"""
    counters: Dict[str, int]  # 设备 ID -> 计数器
    timestamp: datetime
    device_id: str
```

### 11.2 状态分类表

| 状态类型 | 管理方式 | 存储位置 | 访问方式 | 示例 |
| :--- | :--- | :--- | :--- | :--- |
| **会话状态** | C++ 原生 | 内存 (加密) | `IStateManager` | `session.user_id`, `session.context` |
| **用户记忆** | C++ 原生 + L1 持久化 | SQLite (加密) | `state.read/write` | `memory.profile.*`, `memory.private.*` |
| **路由缓存** | C++ 原生 | 内存 | 内部 API | `routing.l1_cache` |
| **置信度评分** | C++ 原生 | 内存 | `IConfidenceService` | `confidence.current_score` |
| **临时工作区** | DSL Context | ExecutionContext | 上下文传递 | `$.temp.working_data` |
| **执行轨迹** | L1 持久化 | UniDAG-Store | `IDAGStore` | `trace.*` |

### 11.3 状态访问路径

```
✅ DSL → state.read/write 工具 → L2 StateToolAdapter → L4 IStateManager
❌ 禁止：DSL 直接访问 CognitiveStateManager 内存
❌ 禁止：L2 工具绕过权限验证直接调用 L4 状态接口
```

---

## 12. ISessionManager（Layer 4）

### 12.1 接口定义

**v2.2 新增：** L4 会话管理接口，管理多轮对话状态。

```python
# interfaces/session_manager.py
from typing import Protocol, Dict, Any, Optional, List
from dataclasses import dataclass
from datetime import datetime

class ISessionManager(Protocol):
    """
    会话管理接口（5 年稳定契约，v2.2 新增）
    
    Layer 4 会话状态管理接口，管理多轮对话上下文
    
    保证：
    - 端侧加密：会话数据必须端侧加密
    - 会话隔离：不同 session_id 的状态严格隔离
    - 版本向量：支持多端同步冲突检测
    """
    
    def get_session(self, session_id: str) -> Optional['SessionInfo']:
        """
        获取会话信息
        
        Args:
            session_id: 会话 ID
            
        Returns:
            Optional[SessionInfo]: 会话信息
        """
        pass
    
    def create_session(self, 
                      user_id: str, 
                      initial_context: Optional[Dict[str, Any]] = None) -> 'SessionInfo':
        """
        创建新会话
        
        Args:
            user_id: 用户 ID
            initial_context: 初始上下文
            
        Returns:
            SessionInfo: 会话信息
        """
        pass
    
    def update_session(self, 
                      session_id: str, 
                      context: Dict[str, Any]) -> None:
        """
        更新会话上下文
        
        Args:
            session_id: 会话 ID
            context: 新上下文
        """
        pass
    
    def delete_session(self, session_id: str) -> None:
        """
        删除会话
        
        Args:
            session_id: 会话 ID
        """
        pass
    
    def list_sessions(self, user_id: str, limit: int = 10) -> List['SessionInfo']:
        """
        列出用户会话
        
        Args:
            user_id: 用户 ID
            limit: 最大数量
            
        Returns:
            List[SessionInfo]: 会话列表
        """
        pass


@dataclass(frozen=True)
class SessionInfo:
    """会话信息（5 年稳定）"""
    session_id: str
    user_id: str
    context: Dict[str, Any]
    created_at: datetime
    updated_at: datetime
    message_count: int
```

---

## 13. ILLMProvider（Layer 0）

### 13.1 接口定义

**v2.2 新增：** LLM 适配器工厂接口，支持多提供商。

```python
# interfaces/llm_provider.py
from typing import Protocol, Dict, Any, Optional, List
from dataclasses import dataclass
from enum import Enum

class LLMProviderType(Enum):
    """LLM 提供商类型"""
    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    LOCAL = "local"  # llama.cpp
    VLLM = "vllm"


class ILLMProvider(Protocol):
    """
    LLM 适配器接口（5 年稳定契约，v2.2 新增）
    
    支持多后端 LLM 适配器
    
    保证：
    - API Key 端侧加密存储
    - 模型白名单验证
    - 超时熔断
    """
    
    def generate(self, 
                prompt: str, 
                config: Optional['LLMConfig'] = None) -> str:
        """
        生成文本
        
        Args:
            prompt: 提示词
            config: LLM 配置
            
        Returns:
            str: 生成结果
            
        Raises:
            LLMConfigError: 配置错误
            LLMTimeoutError: 超时
        """
        pass
    
    def validate_config(self, config: 'LLMConfig') -> bool:
        """
        验证配置
        
        Args:
            config: LLM 配置
            
        Returns:
            bool: 是否有效
        """
        pass
    
    def get_provider_name(self) -> str:
        """
        获取提供商名称
        
        Returns:
            str: 提供商名称
        """
        pass
    
    def is_loaded(self) -> bool:
        """
        检查模型是否已加载
        
        Returns:
            bool: 是否已加载
        """
        pass


@dataclass(frozen=True)
class LLMConfig:
    """LLM 配置（5 年稳定）"""
    provider: LLMProviderType
    model: str
    temperature: float = 0.7
    max_tokens: int = 1000
    timeout_sec: float = 120.0
    api_key_encrypted: str = ""  # 加密的 API Key


class LLMProviderFactory(Protocol):
    """
    LLM 提供商工厂（5 年稳定契约，v2.2 新增）
    """
    
    def create(self, 
              provider_type: LLMProviderType, 
              config: Dict[str, Any]) -> ILLMProvider:
        """
        创建 LLM 提供商实例
        
        Args:
            provider_type: 提供商类型
            config: 配置字典
            
        Returns:
            ILLMProvider: LLM 提供商实例
        """
        pass
```

---

## 14. IComponentRegistry（Layer 5）

### 14.1 接口定义

```python
# interfaces/component_registry.py
from typing import Protocol, Dict, Any, Optional, List

class IComponentRegistry(Protocol):
    """
    可视化组件注册接口（5 年稳定契约，v2.1.1 增强）
    
    brain-domain-agent 通过此接口向 brain-frontend 注册自定义组件
    
    保证：
    - 组件隔离：Shadow DOM + CSP 隔离
    - 安全渲染：Web Worker 渲染，防止 XSS
    - 动态注册：支持运行时注册/注销
    """
    
    async def register_component(self, 
                                 component_id: str,
                                 component_spec: 'ComponentSpec',
                                 domain_id: str) -> bool:
        """
        注册可视化组件
        
        Args:
            component_id: 组件唯一标识
            component_spec: 组件规范
            domain_id: 所属领域
            
        Returns:
            bool: 注册是否成功
        """
        pass
    
    async def unregister_component(self, component_id: str) -> bool:
        """注销组件"""
        pass
    
    async def list_components(self, domain_id: Optional[str] = None) -> List['ComponentSpec']:
        """列出已注册组件"""
        pass
```

---

## 15. IDeveloperService（Layer 6）

### 15.1 接口定义

```python
# interfaces/developer_service.py
from typing import Protocol, Dict, Any, Optional, List

class IDeveloperService(Protocol):
    """
    开发者服务接口（5 年稳定契约，v2.1.1 增强）
    
    开发者工具通过此接口直接调用 brain-domain-agent
    
    保证：
    - 调试支持：支持断点、追踪
    - 组件注册：支持可视化组件注册到 Layer 5
    - 应用市场：支持 agent 发布/安装
    """
    
    async def invoke_domain(self,
                           domain_id: str,
                           directive: str,
                           context: Dict[str, Any]) -> 'ExecutionResult':
        """
        直接调用领域智能体
        
        Args:
            domain_id: 领域标识
            directive: 自然语言指令
            context: 执行上下文
            
        Returns:
            ExecutionResult: 执行结果
        """
        pass
    
    async def list_domains(self) -> List['DomainInfo']:
        """
        列出已注册的领域
        
        Returns:
            List[DomainInfo]: 领域信息列表
        """
        pass
    
    async def register_component(self,
                                domain_id: str,
                                component_spec: 'ComponentSpec') -> bool:
        """
        注册可视化组件
        
        Args:
            domain_id: 所属领域
            component_spec: 组件规范
            
        Returns:
            bool: 注册是否成功
        """
        pass


@dataclass(frozen=True)
class DomainInfo:
    """领域信息（5 年稳定）"""
    domain_id: str
    domain_name: str
    description: str
    skills: List[str]
    components: List[str]
    version: str
    author: str
```

---

## 16. IAppMarketService（Layer 6）

### 16.1 接口定义

```python
# interfaces/app_market_service.py
from typing import Protocol, Dict, Any, Optional, List

class IAppMarketService(Protocol):
    """
    应用市场服务接口（5 年稳定契约）
    
    brain-core 通过此接口与应用市场交互
    """
    
    async def search_agents(self, 
                           query: str,
                           domain_filter: Optional[str] = None) -> List['AgentSearchResult']:
        """搜索领域 agent"""
        pass
    
    async def get_agent_info(self, agent_id: str) -> 'AgentInfo':
        """获取 agent 详情"""
        pass
    
    async def download(self, agent_id: str) -> 'AgentPackage':
        """下载 agent"""
        pass
    
    async def submit_review(self, 
                           agent_id: str, 
                           rating: float, 
                           review: str) -> bool:
        """提交评价"""
        pass
    
    async def sync_agent_reputation(self, agent_id: str) -> bool:
        """同步 agent 声誉到 Layer 4.5"""
        pass


@dataclass(frozen=True)
class AgentSearchResult:
    """agent 搜索结果（5 年稳定）"""
    agent_id: str
    agent_name: str
    domain_id: str
    description: str
    author: str
    rating: float
    download_count: int
    reputation_score: float
```

---

## 17. WebSocket 协议（Layer 4/5）

### 17.1 消息格式

```json
{
   "message_type": "view_requested",
   "session_id": "sess_abc123",
   "payload": {
     "view_type": "markdown",
     "content": "..."
  },
   "timestamp": 1704067200,
   "trace_id": "trace_xyz",
   "span_id": "span_123"
}
```

### 17.2 消息类型

| 消息类型 | 方向 | 说明 | 版本 |
| :--- | :--- | :--- | :--- |
| `user_message` | Client → Server | 用户消息 | v2.0 |
| `view_requested` | Server → Client | 请求渲染视图 | v2.0 |
| `view_ack` | Client → Server | 视图确认 | v2.0 |
| `error` | Server → Client | 错误通知 | v2.0 |
| `ping` | 双向 | 心跳 | v2.0 |
| `conflict_resolution` | Client → Server | 冲突解决选择 (Sync Protocol) | v2.1 |
| `marketplace_install` | Client → Server | 应用市场安装请求 (Layer 6) | v2.1 |
| `trace_event` | Server → Client | 双循环追踪事件 (Coarse/Fine) | v2.1.1 |
| `component_registered` | Server → Client | 组件注册通知 (Layer 2→5) | v2.1.1 |
| `intelligence_update` | Server → Client | 智能化演进状态更新 | v2.1.1 |
| `budget_approval_request` | Server → Client | 自适应预算确认请求 | v2.1.1 |
| `risk_approval_request` | Server → Client | 风险感知人工确认请求 | v2.1.1 |
| `state_change_notification` | Server → Client | 状态变更通知 (v2.2 新增) | v2.2 |

---

## 18. 版本兼容性

### 18.1 兼容性矩阵

| 提供方版本 | 消费方版本 | 兼容性 | 说明 |
| :--- | :--- | :--- | :--- |
| v2.2 | v2.2 | ✅ 完全 | 同版本 |
| v2.2 | v2.1.1 | ✅ 向后 | 新增可选字段 |
| v3.0 | v2.2 | ❌ 不兼容 | 破坏性变更 |
| v2.1.1 | v2.2 | ⚠️ 部分 | 消费方需处理缺失字段 |

### 18.2 向后兼容规则

1. **新增字段：** 必须是可选的（带默认值）
2. **删除字段：** 必须提前 1 年废弃通知
3. **修改字段：** 必须提供转换层
4. **枚举值：** 新增值必须向后兼容
5. **接口方法：** 新增方法可选实现，删除方法需废弃期
6. **安全策略：** 安全级别只能提升，不能降低
7. **ABI 兼容：** C++ 公开头文件 5 年 ABI 稳定

### 18.3 废弃接口管理

| 接口 | 废弃版本 | 移除版本 | 替代接口 |
| :--- | :--- | :--- | :--- |
| `Runtime.execute()` | v2.0 | v3.0 | `Runtime.execute_node()` |
| `ReasoningRequest.call_chain` (简单列表) | v2.1.1 | v3.0 | `ReasoningRequest.call_chain` (CallChainToken) |
| `budget_inheritance: strict` (固定 50%) | v2.1.1 | v3.0 | `budget_inheritance: adaptive` |
| `require_human_approval: true` (硬约束) | v2.1.1 | v3.0 | `require_human_approval: risk_based` |
| Python 业务逻辑接口 | v2.2 | v3.0 | C++ Core API + DSL |

---

## 19. 安全约束

### 19.1 接口安全

| 约束类型 | 检查点 | 错误代码 |
| :--- | :--- | :--- |
| 签名验证 | 所有外部调用 | `ERR_SIGNATURE_INVALID` |
| 权限声明 | 基础设施操作 | `ERR_PERMISSION_MISSING` |
| 命名空间违规 | 标准库访问 | `ERR_NAMESPACE_VIOLATION` |
| 死锁检测 | 递归调用 | `ERR_CIRCULAR_DEPENDENCY` |
| 预算超限 | 资源使用 | `ERR_BUDGET_EXCEEDED` |
| Layer Profile 违规 | 工具调用 | `ERR_PROFILE_VIOLATION` |
| 状态工具越权 | 状态访问 | `ERR_STATE_TOOL_UNAUTHORIZED` |

### 19.2 数据隐私

1. **端侧加密：** 用户上下文、记忆数据必须端侧加密。
2. **最小化原则：** 云端仅接收完成协作所需的最小数据集。
3. **密钥管理：** 密钥存储在本地安全区域，永不上传云端。
4. **状态隔离：** 不同 `session_id` 的状态必须严格隔离。

### 19.3 Layer Profile 安全

| Profile 类型 | 允许操作 | 禁止操作 |
| :--- | :--- | :--- |
| **Cognitive (L4)** | `state.read`, `state.write`, `state.delete` | `tool_call` (除 state 工具), 写文件 |
| **Thinking (L3)** | `state.read`, `state.temp_write` | `state.write`, `state.delete`, 写文件 |
| **Workflow (L2)** | `tool_call`, `state.read`, 受限 `state.write` | 直接访问 C++ 状态内存 |

---

## 20. 测试策略

### 20.1 接口兼容性测试

```python
# test_interface_compatibility.py
import pytest
from interfaces.reasoning_service import IReasoningService, ReasoningRequest

class TestInterfaceCompatibility:
    """测试接口兼容性"""
    
    def test_reasoning_request_backward_compatible(self):
        """验证 ReasoningRequest 向后兼容"""
        # v2.0 请求（无智能化字段）
        request_v2 = ReasoningRequest(
            user_id="u1",
            session_id="s1",
            task="test",
            domain_id="d1",
            context={}
        )
        
        # v2.2 请求（有智能化字段）
        request_v22 = ReasoningRequest(
            user_id="u1",
            session_id="s1",
            task="test",
            domain_id="d1",
            context={},
            budget_inheritance="adaptive",
            require_human_approval="risk_based",
            layer_profile="Workflow"  # v2.2 新增
        )
        
        # 验证 v2.0 字段仍然存在
        assert request_v2.user_id == "u1"
        assert request_v22.user_id == "u1"
        
        # 验证 v2.2 字段有默认值
        assert request_v2.budget_inheritance == "adaptive"
        assert request_v2.layer_profile == "Workflow"
    
    def test_new_interface_optional(self):
        """验证新增接口为可选"""
        # IStateManager 为 v2.2 新增
        # 旧版本实现不应报错
        pass
```

### 20.2 接口契约测试

```python
# test_interface_contract.py
import pytest
from interfaces.standard_library import IStandardLibrary

class TestInterfaceContract:
    """测试接口契约"""
    
    async def test_standard_library_readonly(self):
        """验证标准库只读约束"""
        stdlib = IStandardLibrary()
        
        # 尝试加载/lib/** 模板
        template = await stdlib.load_template("/lib/reasoning/react", "v1")
        
        # 验证返回只读快照
        assert template.readonly == True
        
        # 尝试写入应失败
        with pytest.raises(NamespaceViolationError):
            await stdlib.write_template("/lib/reasoning/react", template)
    
    async def test_layer_profile_validation(self):
        """v2.2: 验证 Layer Profile 验证"""
        stdlib = IStandardLibrary()
        
        # 尝试加载 Cognitive 层模板
        template = await stdlib.load_template("/lib/cognitive/routing", "v1")
        
        # 验证 Profile 类型
        assert template.layer_profile == "Cognitive"
```

---

## 21. ABI 兼容性承诺

### 21.1 C++ ABI 稳定

1. **公开头文件：** `include/agentic_dsl/` 下所有头文件 5 年 ABI 稳定
2. **符号版本控制：** 使用 `__attribute__((visibility("default")))` 和版本脚本
3. **版本脚本路径：** `version_script.map`
4. **示例：** `agentic_dsl_v2.2 { global: DSLEngine::*; local: *; };`

### 21.2 Python 绑定稳定

1. **接口签名：** pybind11 接口签名 5 年稳定
2. **实现可迭代：** 实现可优化，但签名不变
3. **GIL 释放：** Python 回调函数必须在 `py::gil_scoped_release` 保护下执行

## 22. 与 AgenticOS 文档的引用关系

| Interface-Contract 章节 | AgenticOS 文档引用 | 说明 |
| :--- | :--- | :--- |
| Section 3 (C++ Core API) | Layer-0-Spec-v2.2 Section 3 | C++ 核心接口 |
| Section 4 (Python 绑定) | Layer-0-Spec-v2.2 Section 8 | pybind11 绑定 |
| Section 5 (IDAGStore) | Layer-1-Spec-v2.1 Section 3 | 存储接口 |
| Section 6 (IReasoningService) | Layer-3-Spec-v2.1 Section 5 | 推理服务 |
| Section 7 (ISocialService) | Layer-4.5-Spec-v2.1 Section 3 | 社会协作 |
| Section 8 (GenericDomainAgent) | Layer-2-Spec-v2.1 Section 4 | 执行接口 |
| Section 9 (IStandardLibrary) | Layer-2.5-Spec-v2.2 Section 3 | 标准库接口 |
| Section 10 (IConfidenceService) | Intelligence-Evolution-Spec-v1.0 Section 3 | 置信度服务 |
| Section 11 (IStateManager) | Layer-4-Spec-v2.2 Section 9 | 状态管理接口（v2.2 新增） |
| Section 12 (ISessionManager) | Layer-4-Spec-v2.2 Section 8 | 会话管理接口（v2.2 新增） |
| Section 13 (ILLMProvider) | Layer-0-Spec-v2.2 Section 10 | LLM 适配器接口（v2.2 新增） |
| Section 14 (IComponentRegistry) | Layer-5-Spec-v2.1 Section 3 | 组件注册 |
| Section 15 (IDeveloperService) | Layer-6-Spec-v2.1 Section 3 | 开发者服务 |
| Section 16 (IAppMarketService) | Layer-6-Spec-v2.1 Section 4 | 应用市场服务 |
| Section 17 (WebSocket) | Layer-5-Spec-v2.1 Section 7 | WebSocket 协议 |
| Section 19 (安全约束) | Security-Spec-v2.2 Section 2 | 四层防护模型 |

---

## 23. 总结

AgenticOS 接口契约 v2.2 提供：

1. **C++ Core 优先：** C++ Core API 为唯一真理源，Python 仅作 Thin Wrapper
2. **状态管理工具化：** 通过 `state.read`/`state.write` 工具封装 L4 状态
3. **Layer Profile 安全：** Cognitive/Thinking/Workflow 三层权限 Profile
4. **智能化演进：** 自适应预算、智能调度、动态沙箱、风险感知人机协作
5. **LLM 适配器工厂：** `ILLMProvider` 支持多提供商（OpenAI/Anthropic/Local）
6. **会话管理：** `ISessionManager` 管理多轮对话状态
7. **ABI 兼容承诺：** C++ 公开头文件 5 年 ABI 稳定
8. **GIL 释放策略：** Python 回调函数在 `py::gil_scoped_release` 保护下执行

通过严格的接口契约与安全约束，确保 AgenticOS v2.2 的**接口稳定性**、**生态建设基础**与**智能化演进能力**，为未来 5 年的技术发展奠定坚实基础。

---

**文档结束**  
**版权：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可