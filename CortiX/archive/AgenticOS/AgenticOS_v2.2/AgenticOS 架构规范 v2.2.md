# AgenticOS 架构规范 v2.2

**文档版本：** v2.2.0  
**日期：** 2026-02-22  
**状态：** 正式发布  
**依赖：** AgenticDSL v4.0, AgenticOS-Layer-0-Spec-v2.2, AgenticOS-Security-Spec-v2.2, AgenticOS-State-Tool-Spec-v2.2  
**版权所有：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可

---

## 执行摘要

AgenticOS v2.2 是 AgenticOS 架构的重大演进版本，核心目标是确立 **"DSL-Centric"（以 DSL 为中心）** 的架构地位，最大化复用 `agentic-dsl-runtime` C++ 核心实现，将 LLM 生态扩展从 Python 库迁移至 DSL 标准库子图，并通过稳定的 C++/Python 混合接口暴露能力。

**核心变更：**
1. **纯 C++ DSL 核心编排**：L2/L3/L4 的业务逻辑不再由 Python 胶水代码实现，而是完全由 **DSL 子图（`/lib/**`）** 定义，并由 **`agentic-dsl-runtime` C++ 引擎** 直接调度执行。
2. **L4 状态与逻辑分离**：Layer 4 认知层分为 **DSL 逻辑**（`/lib/cognitive/**`）与 **C++ 状态管理**（`CognitiveStateManager`），确保状态管理的性能与安全性。
3. **状态管理工具化**：通过 `state.read`/`state.write` 工具将 L4 C++ 状态封装为 DSL `tool_call` 节点，支持编译时权限检查。
4. **Layer Profile 安全模型**：引入 **Cognitive/Thinking/Workflow** 三层权限 Profile，与四层防护模型深度集成，实现细粒度权限隔离。
5. **Python 绑定边缘化**：Python 仅作为 **Thin Wrapper**（薄封装），不再包含业务逻辑，消除 GIL 和胶水代码风险。
6. **智能化演进特性**：原生支持自适应预算、智能调度、动态沙箱、风险感知人机协作。

**官方表述：** "AgenticOS v2.2 采用八层基础设施（Layers 0-5 + Layer 4.5 + Layer 2.5）+ 第二大脑（Layer 4+5+6 组合），核心引擎基于 C++ DSL Runtime 实现全栈编排。"

---

## 1. 架构全景

### 1.1 八层架构总览 (v2.2 更新)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AgenticOS 八层架构 v2.2                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 6: Application Layer (应用层)                                         │
│  ├─ agentic-sdk: 开发者工具链（VS Code Extension、CLI）                       │
│  ├─ AgenticOS App Market: 第三方 brain-domain-agent 发布与分发               │
│  └─ 通过 AgenticSDK 与下层交互                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 5: Interaction Layer (交互层) ←  第二大脑界面层                         │
│  ├─ brain-frontend: 三层安全沙箱、跨端布局抽象、全链路追踪                      │
│  └─ 可视化组件库、开发者调试工具                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 4.5: Social Orchestration Layer (社会协作层)                           │
│  ├─ Persona Core: 数字分身身份与价值观管理（DID+ 人格指纹）                      │
│  ├─ Contract System: 智能契约 DAG（谈判→签署→存证→履约）                       │
│  └─ Reputation Ledger: 基于零知识证明的信用积累系统                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 4: Cognitive Layer (认知层) ← 第二大脑认知中枢                          │
│  ├─ 逻辑：/lib/cognitive/** (DSL 子图，路由决策、置信度评估)                    │
│  ├─ 状态：CognitiveStateManager (C++ 原生，用户会话、记忆缓存)                 │
│  ├─ IStateManager: 状态接口 (Read/Write/Subscribe)                           │
│  ├─ DomainRegistry: 已安装 domain-agent 管理与动态加载                         │
│  └─ 端侧加密、离线检测、轨迹验证                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 3: Reasoning Layer (推理层)                                           │
│  ├─ 逻辑：/lib/thinking/** (DSL 子图，粗粒度 ReAct 循环)                        │
│  ├─ 生成：llm_generate_dsl 原语 (生成/dynamic/** 子图)                         │
│  └─ 轨迹生成、离线降级、多视角推理                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 2.5: Standard Library Layer (标准库层)                                │
│  ├─ /lib/cognitive/**: 认知层标准模板 (L4 专用)                                │
│  ├─ /lib/thinking/**: 推理层标准模板 (L3 专用)                                 │
│  ├─ /lib/workflow/**: 工作流标准模板 (L2 专用)                                 │
│  └─ /lib/dslgraph/**, /lib/reasoning/**, /lib/memory/**                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 2: Execution Layer (执行层) ← 双重角色                                 │
│  ├─ 引擎：C++ WorkflowEngine (拓扑调度、预算控制)                              │
│  ├─ 逻辑：/lib/workflow/** (DSL 子图，领域工作流)                              │
│  ├─ 工具：InfrastructureAdapters (Python/C++/HTTP 工具实现)                    │
│  ├─ StateToolAdapter: 状态管理工具封装 (state.read/write)                     │
│  └─ SandboxController: 进程级隔离（cgroups/seccomp/Firecracker）               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 1: Storage Layer  (存储层)                                             │
│  ├─ UniDAG-Store: 统一 DAG 存储、拓扑排序、版本管理                               │
│  ├─ Execution DAG: 执行控制流（内存）                                           │
│  ├─ Domain DAG: 领域知识表示（持久化 + 向量）                                    │
│  └─ Reasoning Trace: 推理轨迹（审计，100% 可追溯）                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 0: Resource Layer (资源层)                                             │
│  ├─ agentic-dsl-runtime: AgenticDSL C++ 核心运行时（唯一真理源）                │
│  ├─ 编译器：语义分析 (Layer Profile 检查)                                     │
│  ├─ LLM 适配器：OpenAI/Anthropic/本地 vLLM (最小化，仅 HTTP/Protocol)             │
│  └─ 基础设施：文件系统、网络、进程                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**官方表述：** "AgenticOS 采用八层基础设施（Layers 0-5 + Layer 4.5 + Layer 2.5）+ 第二大脑（Layer 4+5+6 组合）"

### 1.2 AgenticDSL 三层架构映射 (v2.2 更新)

| AgenticDSL v4.0 | AgenticOS v2.2 | 说明 |
| :--- | :--- | :--- |
| **Layer 1: Execution Primitives** | **Layer 0** | 内置原语 (assign/llm_call/tool_call 等)，C++ 实现 |
| **Layer 2: Standard Primitives** | **Layer 2.5** | 标准库 (`/lib/cognitive/**`, `/lib/thinking/**`, `/lib/workflow/**`) |
| **Layer 3: Knowledge Application** | **Layer 3 + Layer 4 + Layer 6** | 应用工作流 (`/main/**`, `/app/**`)，DSL 编排 |

**关键架构规则：**
1. **唯一真理源**：`agentic-dsl-runtime` C++ 引擎是 L0-L4 执行的唯一核心，Python 仅作绑定。
2. **逻辑即数据**：L2/L3/L4 业务逻辑固化为 `/lib/**` DSL 子图，禁止 Python 实现核心编排逻辑。
3. **L4 状态分离**：L4 认知逻辑由 DSL 定义，L4 会话状态由 C++ 原生 `CognitiveStateManager` 维护。
4. **状态工具化**：L4 状态通过 `state.read`/`state.write` 工具暴露给 DSL，禁止直接内存访问。
5. **纯函数约束**：L0 执行原语层必须为纯函数，禁止维护会话状态（session state）。
6. **安全分层**：Layer Profile 权限模型贯穿全栈（Cognitive/Thinking/Workflow）。

### 1.3 核心数据流（双循环模型 v2.2）

```text
用户请求
    │
    ▼
┌─────────────┐    WebSocket     ┌─────────────────────────┐
│  Frontend   │◄────────────────►│  CognitiveStateManager  │
│  (Layer 5)  │   view_requested │  (L4 C++ State)         │
└─────────────┘                  └──────┬──────────────────┘
                                        │ 只读 Context 快照
                                        ▼
                               ┌─────────────────────────┐
                               │  /lib/cognitive/**      │
                               │  (L4 DSL Logic)         │
                               │ 路由决策、置信度评估      │
                               └──────┬──────────────────┘
                                      │ 延伸调用 (Extended Call)
                                      │ 传递 domain_id
                                      ▼
                               ┌─────────────────────────┐
                               │  /lib/thinking/**       │
                               │  (L3 DSL Logic)         │
                               │ 粗粒度 ReAct 循环         │
                               └──────┬──────────────────┘
                                      │ 沙箱调用 (Sandbox Call)
                                      │ 独立 SandboxInstance
                                      ▼
                               ┌─────────────────────────┐
                               │  /lib/workflow/**       │
                               │  (L2 DSL Logic)         │
                               │ 细粒度 DSL 节点执行       │
                               └──────┬──────────────────┘
                                      │
                                      ▼
                               ┌─────────────────────────┐
                               │ agentic-dsl-runtime     │
                               │  (Layer 0 C++ Core)     │
                               │ 唯一执行引擎             │
                               │ 编译时 Profile 检查        │
                               └──────┬──────────────────┘
                                      │ tool_call (state.read/write)
                                      ▼
                               ┌─────────────────────────┐
                               │ StateToolAdapter        │
                               │  (Layer 2)              │
                               │ 权限验证 + Schema 检查     │
                               └──────┬──────────────────┘
                                      │ C++ API
                                      ▼
                               ┌─────────────────────────┐
                               │ CognitiveStateManager   │
                               │  (Layer 4)              │
                               │ IStateManager 接口        │
                               └──────┬──────────────────┘
                                      │
                                      ▼
                               ┌─────────────────────────┐
                               │ UniDAG-Store            │
                               │  (Layer 1)              │
                               └─────────────────────────┘
```

**调用协议：**
1. **L4→L3 (延伸调用)**：L4 Context 只读快照传递给 L3，L3 不可修改 L4 状态，权限自动降级。
2. **L3→L2 (沙箱调用)**：L2 创建独立 `SandboxInstance`，与 L3 上下文隔离，仅合并显式输出 (`output_keys`)。
3. **状态工具调用**：DSL `tool_call` 节点 → L2 `StateToolAdapter` → L4 `IStateManager`。
4. **调用链 Token**：跨层调用追加 `call_chain`，防止循环依赖。

### 1.4 四类 DAG 协同

| DAG 类型 | 存储位置 | 用途 | 向量支持 | 生命周期 |
| :--- | :--- | :--- | :--- | :--- |
| **Execution DAG** | 内存（TopoScheduler） | 执行控制流 | ❌ 无 | 单次执行 |
| **Domain DAG** | UniDAG-Store | 领域知识表示 | ✅ feature_vector | 长期持久化 |
| **Reasoning Trace** | UniDAG-Store | 审计/学习/调试 | ❌ 无 | 长期持久化 |
| **Contract DAG** | UniDAG-Store | 智能契约 | ❌ 无 | 契约生命周期 |

协同机制：
* 向量检索从 Domain DAG 获取 → 注入 Execution DAG 的 `memory.state`
* `reasoning_trace_id` 贯穿 Execution DAG 与 Reasoning Trace
* Domain DAG 仅通过标准库契约访问（Layer 2.5）
* Contract DAG 通过 Layer 4.5 社会协作层管理

---

## 2. 核心设计原则

### 2.1 分层职责原则 (v2.2 更新)

| 层级 | 核心职责 | 禁止行为 | 实现语言 |
| :--- | :--- | :--- | :--- |
| **Layer 6 (应用)** | 业务逻辑、用户体验、应用市场 | 直接访问存储层 | Python/TS (SDK) |
| **Layer 5 (交互)** | 渲染、交互、安全沙箱、组件注册 | 包含业务逻辑 | TypeScript |
| **Layer 4.5 (社会)** | 多智能体协作、契约管理 | 执行领域操作 | Python/C++ |
| **Layer 4 (认知)** | **逻辑：** `/lib/cognitive/**` (DSL)<br>**状态：** `CognitiveStateManager` (C++)<br>**接口：** `IStateManager` | 执行领域操作 | **DSL + C++** |
| **Layer 3 (推理)** | **逻辑：** `/lib/thinking/**` (DSL)<br>ReAct 循环 (粗粒度)、DSL 调用 | 直接系统调用、维护执行状态 | **DSL** |
| **Layer 2.5 (标准库)** | 提供声明式 DSL 模板 (`/lib/**`) | 运行时修改模板、维护会话状态 | DSL |
| **Layer 2 (执行)** | **引擎：** C++ WorkflowEngine<br>**逻辑：** `/lib/workflow/**` (DSL)<br>**工具：** InfrastructureAdapters<br>**状态工具：** StateToolAdapter | 存储实现细节、直接调用 L0.execute() | **C++ + DSL** |
| **Layer 1 (存储)** | DAG 持久化、拓扑排序、版本管理、CDC 同步 | 业务语义验证 | C++/Rust |
| **Layer 0 (资源)** | DSL 编译、节点执行 (细粒度)<br>**编译检查：** Layer Profile 验证 | 高层业务逻辑、维护会话状态 | **C++** |

### 2.2 L0/L2/L2.5/L3/L4 执行边界契约 (v2.2 更新)

**明确契约：**
* **L4 (Cognitive)**:
    * ✅ 调用 L0 进行 DSL 编译（AST 生成）→ 纯函数，无状态
    * ✅ 加载 L2.5 标准库模板 (`/lib/cognitive/**`)
    * ✅ 维护 C++ 原生状态 (`CognitiveStateManager`)
    * ✅ 提供 `IStateManager` 接口 (Read/Write/Subscribe)
    * ❌ 禁止：DSL 逻辑直接访问 C++ 状态内存
    * ❌ 禁止：直接调用 L0.execute()，必须经过 L2 调度器
* **L3 (Reasoning)**:
    * ✅ 通过 `llm_generate_dsl` 原语生成 `/dynamic/**` 子图
    * ✅ 调用 L2.5 模板 (`/lib/thinking/**`)
    * ✅ 使用 `state.read` 工具读取状态 (只读)
    * ❌ 禁止：使用 `state.write` 工具 (Thinking Profile 限制)
    * ❌ 禁止：直接调用 L0.execute()，必须经过 L2 调度器
* **L2.5 (Standard Library)**:
    * ✅ 提供只读、版本化的 DSL 子图 (`/lib/**`)
    * ❌ 禁止：运行时修改，必须通过签名验证
    * ✅ 分类：`/lib/reasoning/**` (基础推理), `/lib/workflow/**` (业务流)
* **L2 (WorkflowEngine)**:
    * ✅ 维护 `ExecutionContext`（有状态）
    * ✅ 通过 `SandboxController` 创建沙箱
    * ✅ 驱动细粒度循环（拓扑排序执行节点链）
    * ✅ 在沙箱内调用 L0.execute_node(ast, node_path, context)
    * ✅ 智能化：解析节点 metadata 中的 priority/estimated_cost，优化执行顺序
    * ✅ 状态工具：注册 `state.read`/`state.write` 到 `ToolRegistry`
* **L0 (agentic-dsl-runtime)**:
    * ✅ 纯函数式运行时 (`compile`, `execute_node`)
    * ✅ 支持自适应预算约束、风险感知人机协作
    * ✅ 编译时检查：`tool_call` 与 `Layer Profile` 兼容性
    * ❌ 禁止：维护任何会话状态 (session state)
    * ❌ 禁止：直接访问文件系统、网络等外部资源（通过 L2 适配器）
    * ❌ 禁止：硬编码 LLM Provider 逻辑（仅负责 HTTP 协议）

**状态管理访问路径：**
* **L4 (CognitiveStateManager)**: 
    * ✅ 维护 C++ 原生状态 (用户会话、记忆缓存)
    * ✅ 提供 `IStateManager` 接口 (Read/Write/Subscribe)
    * ❌ 禁止：DSL 逻辑直接访问 C++ 状态内存
* **L2 (InfrastructureAdapters)**: 
    * ✅ 注册状态管理工具 (`state.read`, `state.write`) 到 `ToolRegistry`
    * ✅ 封装 L4 状态接口为 DSL `tool_call` 节点
    * ✅ 执行权限验证 (Layer Profile + Permissions)
* **L0 (agentic-dsl-runtime)**: 
    * ✅ 解析 `tool_call` 节点
    * ✅ 编译时检查 `state.write` 与 `Layer Profile` 兼容性
    * ❌ 禁止：L0 核心维护任何会话状态 (状态仍在 L4)

### 2.3 L4 状态分类表 (v2.2 新增)

| 状态类型 | 管理方式 | 存储位置 | 访问方式 | 示例 |
| :--- | :--- | :--- | :--- | :--- |
| **会话状态** | C++ 原生 | 内存 (加密) | `IStateManager` | `session.user_id`, `session.context` |
| **用户记忆** | C++ 原生 + L1 持久化 | SQLite (加密) | `state.read/write` | `memory.profile.*`, `memory.private.*` |
| **路由缓存** | C++ 原生 | 内存 | 内部 API | `routing.l1_cache` |
| **置信度评分** | C++ 原生 | 内存 | `IConfidenceService` | `confidence.current_score` |
| **临时工作区** | DSL Context | ExecutionContext | 上下文传递 | `$.temp.working_data` |
| **执行轨迹** | L1 持久化 | UniDAG-Store | `IDAGStore` | `trace.*` |

**状态访问路径：**
* ✅ DSL → `state.read`/`state.write` 工具 → L2 `StateToolAdapter` → L4 `IStateManager`
* ❌ 禁止：DSL 直接访问 `CognitiveStateManager` 内存
* ❌ 禁止：L2 工具绕过权限验证直接调用 L4 状态接口

### 2.4 Layer Profile 与四层防护模型集成

v2.2 引入 **Layer Profile** 权限模型，与 v2.1.1 四层防护模型深度集成。

| 防护层级 | Layer Profile 集成点 | 安全机制 |
| :--- | :--- | :--- |
| **L1: DSL 层** | 语义分析器验证 `/lib/cognitive` 不包含违规节点 | 逻辑标识符、技能白名单、命名空间规则 |
| **L2: 框架层** | 执行器检查 Layer Profile 权限 (TOOL_CALL 拦截) | SandboxController 进程隔离、cgroups/seccomp |
| **L3: 适配器层** | InfrastructureAdapter 验证操作是否符合 Layer Profile | 三重验证（声明/资源/威胁）、审计日志 |
| **L4: 前端层** | 组件沙箱验证渲染内容是否符合 Layer Profile | CSP/数据脱敏、Web Worker + Shadow DOM |

**Layer Profile 定义：**
* **Cognitive (L4)**: 严格限制，禁止 `tool_call` 和写文件，仅允许读记忆/上下文。**允许 `state.write`**。
* **Thinking (L3)**: 中等限制，禁止写文件，限制 `tool_call` (仅只读工具)，允许调用 L2。**禁止 `state.write`，仅允许 `state.temp_write`**。
* **Workflow (L2)**: 沙箱允许，允许 `tool_call`，允许文件写 (沙箱内)，允许网络 (受限)。**受限 `state.write` (沙箱/声明路径)**。

**Profile 继承规则：**
* **降级原则**：子图调用时权限只能减少（例如 L4 调用 L3，L3 无法获得 L4 未授权的权限）。
* **显式声明**：DSL 子图必须在 `__meta__` 中声明所需 Profile。
* **编译期验证**：违反 Profile 约束直接在编译期报错 (`ERR_PROFILE_VIOLATION`)。
* **运行期验证**：L2 `StateToolAdapter` 再次验证，防止绕过。

### 2.4.1 Layer Profile 与状态工具权限映射

| 操作类型 | Cognitive Profile (L4) | Thinking Profile (L3) | Workflow Profile (L2) |
| :--- | :--- | :--- | :--- |
| `state.read` | ✅ 允许 | ✅ 允许 | ✅ 允许 |
| `state.write` | ✅ 允许 | ❌ 禁止 | ⚠️ 受限 (沙箱/声明路径) |
| `state.delete` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |
| `state.temp_write` | ✅ 允许 | ✅ 允许 (临时工作区) | ✅ 允许 (临时工作区) |
| `security.*` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |

**编译时验证：**
* DSL 编译器必须在语义分析阶段验证 `tool_call` 节点与 `layer_profile` 的兼容性。
* 违规者 → `ERR_PROFILE_VIOLATION` (编译期错误)。

**双重验证机制：**
| 验证阶段 | 验证内容 | 实现位置 | 错误码 |
| :--- | :--- | :--- | :--- |
| **编译期** | `tool_call` 与 Profile 兼容性 | L0 语义分析器 | `ERR_PROFILE_VIOLATION` |
| **运行期** | 实际调用权限验证 | L2 `StateToolAdapter` | `ERR_PERMISSION_DENIED` |
| **审计期** | 操作日志记录 | L1 Trace 持久化 | N/A |

### 2.5 沙箱职责分层

| 组件 | 职责 | 禁止行为 |
| :--- | :--- | :--- |
| **SandboxController** | 进程级隔离（创建/销毁沙箱） | 业务逻辑验证 |
| **InfrastructureAdapterBase** | 操作级验证（路径/权限/审计） | 创建沙箱 |
| **StateToolAdapter** | 状态工具封装 (调用 L4 状态接口) | 直接访问 C++ 状态内存 |
| **DomainAdapter** | 领域业务逻辑 (工具实现) | 直接系统调用 |
| **ComponentSandbox** | 前端组件隔离（Web Worker + Shadow DOM） | 访问主线程 DOM |

### 2.6 离线优先设计

| 能力级别 | 领域示例 | 可用性 | 实现机制 |
| :--- | :--- | :--- | :--- |
| ✅ **完全离线** | C++/论文/文件 | 100% 功能 | 规则引擎 + 本地 LLM |
| ⚠️ **降级可用** | 社交/购物 | 基础功能 | 规则引擎 + 缓存 |
| ❌ **不可用** | 生物/数据科学 | 明确提示 | 联网检测 + 用户提示 |

### 2.7 双循环执行模型 (v2.2 更新)

* **粗粒度循环 (Layer 3/4)**:
    * 单位：ReAct Step (Thought → Action → Observation) / Cognitive Decision
    * 职责：策略决策、目标分解、异常处理、路由决策
    * 粒度：100-500ms 每步
    * 驱动：DSL 子图 (`/lib/thinking/**`, `/lib/cognitive/**`) + C++ 引擎
* **细粒度循环 (Layer 0 + Layer 2)**:
    * 单位：DSL 节点执行链 (assign → llm_call → tool_call)
    * 职责：原子操作执行、拓扑排序、预算控制
    * 粒度：5-50ms 每节点
    * 驱动：L2 WorkflowEngine (C++) 驱动 L0 Runtime (C++) 执行

### 2.8 标准库层规范 (Layer 2.5)

**命名空间：**
* `/lib/cognitive/**`: 认知层标准模板 (L4 专用)，只读，签名强制。
* `/lib/thinking/**`: 推理层标准模板 (L3 专用)，只读，签名强制。
* `/lib/workflow/**`: 工作流标准模板 (L2 专用)，只读，签名强制。
* `/lib/reasoning/**`: 基础推理原语 (L0/L2 共用)，只读，签名强制。
* `/lib/**`: 通用标准库（只读，签名强制，Layer 2.5）。
* `/dynamic/**`: 运行时生成（session-scoped，llm_generate_dsl 输出）。
* `/main/**`: 主 DAG（应用工作流）。

**约束：**
* 禁止写入 `/lib/**`（`ERR_NAMESPACE_VIOLATION`）。
* `/lib/**` 子图必须声明 `signature` 契约。
* `/lib/**` 子图执行时继承父图预算（strict 模式默认 50%，adaptive 模式基于置信度）。
* **分类治理**：基础推理模式 (`react`, `plan_and_execute`) 归入 `/lib/reasoning/**`，特定业务流归入 `/lib/workflow/**`。

### 2.9 应用市场与生态规范 (Layer 6 + Layer 4)

* **应用市场 (Layer 6)**: 第三方 brain-domain-agent 发布、分发、评价平台，集成 Layer 4.5 声誉账本。
* **DomainRegistry (Layer 4)**: 管理已安装的 domain-agent，验证签名与完整性，动态加载/卸载 Agent。
* **安全约束**: 安装包签名校验，沙箱隔离执行，资源权限显式声明，组件命名空间隔离。

### 2.10 智能化演进特性 (v2.2 原生支持)

| 特性 | 说明 | 实现层级 | 性能 KPI |
| :--- | :--- | :--- | :--- |
| **自适应预算** | 基于 Layer 4 置信度动态调整预算比例 (0.3-0.7) | Layer 4 + Layer 0 (C++) | 计算 <1ms |
| **智能调度** | L2 解析节点 metadata.priority，优化执行顺序 | Layer 2 (C++) | 开销 <5ms |
| **动态沙箱** | 为 `/dynamic/**` 子图创建独立 SandboxInstance | Layer 2 (C++) | 创建 <50ms |
| **自适应人机协作** | 基于风险等级与置信度动态决定人工确认需求 | Layer 0 + Layer 4 (C++) | 评估 <2ms |
| **状态管理工具化** | `state.read`/`state.write` 工具封装 L4 状态 | Layer 2 + Layer 4 | 调用 <5ms |

---

## 3. 核心接口契约（5 年稳定）

### 3.1 子项目间接口矩阵

| 接口名称 | 调用方向 | 定义位置 | 稳定性 | 版本 |
| :--- | :--- | :--- | :--- | :--- |
| **C++ Core API** | L2/L3/L4 → agentic-dsl-runtime | `src/core/engine.h` | **5 年 (ABI)** | **v2.2** |
| **Python 绑定 API** | Python → C++ Core | `agentic_dsl` 模块 | 5 年 | v2.2 |
| **IDAGStore** | 所有层 → UniDAG-Store | unidag-store | 5 年 | v2.2 |
| **IReasoningService** | brain-core → brain-thinking | brain-thinking | 5 年 | v2.2 |
| **ISocialService** | brain-core → CiviMind | brain-core | 5 年 | v2.2 |
| **GenericDomainAgent.execute()** | brain-core → brain-domain-agent | brain-domain-agent | 5 年 | v2.2 |
| **IStandardLibrary** | brain-thinking → agentic-stdlib | agentic-stdlib | 5 年 | v2.2 |
| **IConfidenceService** | Layer 0/2/3 → brain-core | brain-core | 5 年 | v2.2 |
| **IStateManager** | Layer 2 → brain-core | brain-core | 5 年 | v2.2 |
| **IAppMarketService** | brain-core → agentic-sdk | agentic-sdk | 5 年 | v2.2 |
| **IComponentRegistry** | brain-domain-agent → brain-frontend | brain-frontend | 5 年 | v2.2 |
| **IDeveloperService** | 开发者工具 → brain-domain-agent | brain-domain-agent | 5 年 | v2.2 |
| **WebSocket 协议** | brain-frontend ↔ brain-core | 协议文档 | 5 年 | v2.2 |

**v2.2 重点：**
* **C++ Core API** 为唯一真理源，Python 绑定 API 基于此封装。
* **废弃接口管理**：v2.1.1 Python 接口将在 v2.2 中废弃，迁移至 C++ Core。
* **接口松弛**：目前无第三方开发者基于现有 Python 接口构建的应用，可打破老版接口要求，修订为和新架构对应的接口。原则是 DSL 可以读取所有信息，最大化 LLM 通过 DAG 看到全部信息。
* **新增接口**：`ILLMProvider` (LLM 适配器工厂), `ISessionManager` (L4 会话管理), **`IStateManager` (状态管理接口)**。

### 3.2 数据契约

```protobuf
// UnifiedDAG v2.2 (UniDAG-Store)
message UnifiedDAG {
  string dag_id = 1;
  string name = 2;
  repeated DAGNode nodes = 6;
  repeated DAGEdge edges = 7;
  repeated string root_node_ids = 8;
  repeated int32 topo_ranks = 11;
  string domain = 12;
  int32 version = 13;  // DAG 内容版本
  string layer_profile = 14;  // v2.2 新增：Cognitive/Thinking/Workflow
}

// ReasoningRequest (brain-thinking)
message ReasoningRequest {
  string user_id = 1;
  string session_id = 2;
  string task = 3;
  string domain_id = 4;
  int32 max_steps = 5;
  float timeout_sec = 6;
  bool offline_ok = 7;
  repeated string call_chain  = 8;      // 调用链 Token（死锁检测）
  int32 recursion_depth = 9;           // 递归深度
  
  // 智能化演进字段 (v2.2)
  string budget_inheritance = 10;      //  "strict " |  "adaptive " |  "custom "
  string require_human_approval = 11;  //  "true " |  "false " |  "risk_based "
  float risk_threshold = 12;           // 风险阈值
  float confidence_score = 13;         // 置信度分数
  string layer_profile = 14;           // v2.2 新增：权限 Profile
}

// ContractDAG (Layer 4.5)
message ContractDAG {
  string contract_id = 1;
  UnifiedDAG dag = 2;
  repeated string participants = 3;
  map <string, string > signatures = 4;
  string status = 5;  //  "draft " |  "signed " |  "executing " |  "completed " |  "breached "
}

// StateOperation (Layer 2 → Layer 4)
message StateOperation {
  string operation_type = 1;  // "read" | "write" | "delete" | "subscribe"
  string path = 2;
  bytes value = 3;  // 序列化后的值
  string session_id = 4;
  VersionVector version = 5;  // 用于冲突检测
}
```

---

## 4. 子项目划分

### 4.1 子项目清单

```text
AgenticOS/
│
├── agentic-dsl-runtime/        # Layer 0 - C++ 核心运行时 (唯一真理源)
├── unidag-store/               # Layer 1 - 统一 DAG 存储
├── brain-domain-agent/         # Layer 2 - 领域执行引擎 (C++ 引擎 + DSL 逻辑)
├── agentic-stdlib/             # Layer 2.5 - 标准库层 (DSL 模板)
├── brain-thinking/             # Layer 3 - 推理运行时 (DSL 编排)
├── brain-core/                 # Layer 4 - 认知增强层 (C++ 状态 + DSL 逻辑)
│   └── state_manager/          # C++ 原生状态管理 (IStateManager)
├── civimind/                   # Layer 4.5 - 社会协作层
├── brain-frontend/             # Layer 5 - 用户交互层
└── agentic-sdk/                # Layer 6 - 应用开发 SDK + 应用市场
```

### 4.2 子项目依赖图

```mermaid
flowchart TB
    subgraph Layer0[Layer 0: Resource]
        R0[agentic-dsl-runtime (C++ Core)]
    end
    
    subgraph Layer1[Layer 1: Storage]
        R1[unidag-store]
    end
    
    subgraph Layer2[Layer 2: Execution]
        R2[brain-domain-agent (C++ Engine + DSL)]
        R2_State[StateToolAdapter]
    end

    subgraph Layer2_5[Layer 2.5: Standard Library]
        R2_5[agentic-stdlib (DSL Templates)]
    end
    
    subgraph Layer3[Layer 3: Reasoning]
        R3[brain-thinking (DSL Orchestration)]
    end
    
    subgraph Layer4[Layer 4: Cognitive]
        R4[brain-core (C++ State + DSL Logic)]
        R4_State[CognitiveStateManager]
    end
    
    subgraph Layer4_5[Layer 4.5: Social]
        R4_5[civimind]
    end
    
    subgraph Layer5[Layer 5: Interaction]
        R5[brain-frontend]
    end
    
    subgraph Layer6[Layer 6: Application]
        R6[agentic-sdk]
    end
    
    R0 -->|C++ API | R3
    R0 -->|C++ API | R2
    R0 -->|C++ API | R4
    R1   <-->|IDAGStore| R2
    R1   <-->|IDAGStore| R3
    R1   <-->|IDAGStore| R4
    R2_5 -->|IStandardLibrary| R3
    R2_5 -->|IStandardLibrary| R2
    R2_5 -->|IStandardLibrary| R4
    R3 -->|IReasoningService| R2
    R2 -->|GenericDomainAgent| R4
    R2_State -->|IStateManager| R4_State
    R4   <-->|ISocialService| R4_5
    R4   <-->|WebSocket| R5
    R4 -->|API| R6
    R6 -->|IAppMarketService| R4
    R4 -->|IConfidenceService| R0
    R4 -->|IConfidenceService| R2
    R4 -->|IConfidenceService| R3
    
    classDef l0 fill:#e8f5e8,stroke:#2e7d32
    classDef l1 fill:#e3f2fd,stroke:#1976d2
    classDef l2 fill:#fff3e0,stroke:#e65100
    classDef l2_5  fill:#fff8e1,stroke:#ff8f00
    classDef l3 fill:#f3e5f5,stroke:#4a148c
    classDef l4 fill:#ffebee,stroke:#c62828
    classDef l4_5 fill:#fce4ec,stroke:#ad1457
    classDef l5 fill:#c8e6c9,stroke:#388e3c
    classDef l6 fill:#e1f5fe,stroke:#0277bd
    
    class R0 l0
    class R1 l1
    class R2 l2
    class R2_State l2
    class R2_5 l2_5
    class R3 l3
    class R4 l4
    class R4_State l4
    class R4_5 l4_5
    class R5 l5
    class R6 l6
```

---

## 5. 部署架构

### 5.1 三端部署模式

| 部署场景 | 组件组合 | 存储实现 | 网络依赖 |
| :--- | :--- | :--- | :--- |
| **PC 本地** | Layers 0-5 + 4.5 + 2.5 | EmbeddedUniDAGStore (SQLite+Zarr) | ❌ 无 |
| **移动 APP** | Layers 0-5 + 4.5 + 2.5 | EmbeddedUniDAGStore (SQLite+Zarr) | ❌ 无 |
| **浏览器** | Layers 5-6 + 云端 0-4.5+2.5 | CloudUniDAGStore (PostgreSQL+S3) | ✅ 必需 |
| **混合模式** | Layers 0-5 + 4.5 + 2.5 + 云端同步 | 双存储适配器 | ⚠️ 可选 |

### 5.2 数据流部署

**本地部署（PC/移动）:**
```text
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Frontend  │────►│  brain-core │────►│   UniDAG    │
│   (Layer 5) │◄────│  (Layer 4)  │◄────│   -Store    │
└─────────────┘     └──────┬──────┘     │  (Layer 1)  │
                           │            └─────────────┘
                    ┌──────┴──────┐
                    │ brain-thinking│
                    │  (Layer 3)   │
                    └──────┬──────┘
                    ┌──────┴──────┐
                    │ agentic-stdlib│
                    │  (Layer 2.5) │
                    └──────┬──────┘
                    ┌──────┴──────┐
                    │brain-domain  │
                    │   -agent     │
                    │  (Layer 2)   │
                    └──────┬──────┘
                    ┌──────┴──────┐
                    │agentic-dsl   │
                    │   -runtime   │
                    │  (Layer 0)   │
                    └─────────────┘
                    ┌─────────────┐
                    │   CiviMind   │
                    │ (Layer 4.5)  │
                    └─────────────┘
                    ┌─────────────┐
                    │State Manager│
                    │  (Layer 4)  │
                    └─────────────┘
```

---

## 6. 演进路线图

### 6.1 各子项目演进

| 子项目 | MVP | v1.0 | v2.0 (Current) | v2.2 (Target) | v3.0（愿景） |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **agentic-dsl-runtime** | 基础 DSL+ 调度 | +GPU+ 标准库 | + 分布式 | **+ C++ Core 全编排** | + 形式化验证 |
| **unidag-store** | SQLite+Zarr | +S3+PostgreSQL | + 分布式 | + 全局图网络 | + 全局图网络 |
| **brain-domain-agent** | cgroups 沙箱 | Firecracker | + 多领域 | **+ DSL 编排** | + 自进化技能 |
| **agentic-stdlib** | /lib/reasoning | +/lib/memory | +/lib/dslgraph | **+ /lib/cognitive/thinking** | + 生态贡献 |
| **brain-thinking** | ReAct 基础 | + 多视角 | + 元学习 | **+ DSL 编排** | + 认知架构 |
| **brain-core** | L1 路由 + 加密 | + 多端同步 | + 认知图谱 | **+ C++ 状态管理** | + 数字孪生 |
| **civimind** | 两人契约 A↔B | + 多方谈判 | + 经济系统 | +DAO 治理 | +DAO 治理 |
| **brain-frontend** | Web 基础 | + 移动端 | +AR/VR | + 脑机接口 | + 脑机接口 |
| **agentic-sdk** | CLI 基础 | +VS Code | + 应用市场 | + 低代码平台 | + 低代码平台 |

### 6.2 技术债务管理

* **原则**：接口契约 5 年稳定，实现可迭代。
* **兼容**：每版本保留向后兼容层。
* **通知**：废弃接口提前 1 年通知。
* **迁移**：多版本共存支持平滑迁移。
* **v2.2 特别策略**：由于目前还在架构文档阶段，没有任何第三方开发者基于现有 Python 接口构建的应用，可以不必遵循老版的接口要求，同时修订为和新架构对应的接口。

---

## 7. 版本管理

### 7.1 版本映射表

| 对外版本 | 架构版本 | 语言规范 | 接口契约 | 状态 |
| :--- | :--- | :--- | :--- | :--- |
| AgenticOS v2.1.1 | Arch v2.1.1 | Lang v4.3.0 | Interface v2.1.1 | 当前 |
| **AgenticOS v2.2** | **Arch v2.2** | **Lang v4.4** | **Interface v2.2** | **目标** |
| AgenticOS v3.0 | Arch v3.0 | Lang v5.0 | Interface v3.0 | 愿景 |

**对外统一使用：** AgenticOS v2.2  
**内部通过映射表管理子版本：** Arch v2.2 ↔ Lang v4.4 ↔ Interface v2.2

### 7.2 版本兼容性

| 提供方版本 | 消费方版本 | 兼容性 | 说明 |
| :--- | :--- | :--- | :--- |
| v2.2 | v2.2 | ✅ 完全 | 同版本 |
| v2.2 | v2.1.1 | ✅ 向后 | 新增可选字段 |
| v3.0 | v2.2 | ❌ 不兼容 | 破坏性变更 |
| v2.1.1 | v2.2 | ⚠️ 部分 | 消费方需处理缺失字段 |

---

## 8. 关键指标

### 8.1 性能 KPI

| 指标 | 目标 | 测量方式 |
| :--- | :--- | :--- |
| **DSL 编译** | <100ms | benchmark |
| **沙箱创建** | <500ms (PC) | benchmark |
| **L1 路由** | <10ms | benchmark |
| **向量检索** | <100ms | benchmark |
| **拓扑排序** | <100ms (100 万节点) | benchmark |
| **契约生成** | <100ms | benchmark |
| **细粒度节点执行** | **<5ms** | benchmark |
| **粗粒度 ReAct 步** | <500ms | benchmark |
| **标准库模板加载** | <50ms | benchmark |
| **智能调度开销** | <5ms | benchmark |
| **自适应预算计算** | <1ms | benchmark |
| **动态沙箱创建** | <50ms | benchmark |
| **C++/Python 调用开销** | **<0.1ms** | benchmark |
| **L4→L3 延伸调用** | <10ms | benchmark |
| **L3→L2 沙箱调用** | <50ms | benchmark |
| **状态工具调用** | **<5ms** | benchmark |

### 8.2 安全 KPI

| 指标 | 目标 | 测量方式 |
| :--- | :--- | :--- |
| XSS 拦截 | 100% | 渗透测试 |
| 沙箱逃逸 | 0 次 | 渗透测试 |
| 路径遍历 | 100% 拦截 | 自动化测试 |
| 密钥泄露 | 0 次 | 安全审计 |
| 契约篡改检测 | 100% | 渗透测试 |
| 命名空间违规 | 100% 拦截 | 自动化测试 |
| 第三方 Agent 签名 | 100% 验证 | 自动化测试 |
| 权限违规 | 100% 拦截 | 自动化测试 |
| **Layer Profile 违规** | **100% 拦截** | **自动化测试** |
| **状态工具越权** | **100% 拦截** | **编译时检查** |

### 8.3 可靠性 KPI

| 指标 | 目标 | 测量方式 |
| :--- | :--- | :--- |
| 轨迹持久化 | 100% | 自动化验证 |
| 离线可用性 | 100% 核心功能 | 功能测试 |
| 测试覆盖率 | >70% | pytest --cov |
| 同步成功率 | >99% | 监控指标 |
| 应用市场安装成功率 | >99% | 监控指标 |

---

## 9. 与第二大脑的关系

第二大脑是 AgenticOS 的官方用户界面入口和全能助手，而非普通应用：

### 9.1 定位对比

| 方面 | 第二大脑 | AgenticOS |
| :--- | :--- | :--- |
| 定位 | 用户界面入口 + 全能助手 | 通用智能体操作系统 |
| 用户 | 个人用户 | 开发者 + 企业 + 个人用户 |
| 范围 | 跨领域通用助手 | 多领域通用框架 |
| 层级 | Layer 4 + Layer 5 + Layer 6 组合 | Layers 0-5 + Layer 4.5 + Layer 2.5 + Layer 6 |
| 接口 | 使用 AgenticOS 5 年稳定契约 | 提供 5 年稳定契约 |
| 部署 | 端云协同（与 AgenticOS 一致） | 端云协同 |
| 协作 | 多智能体社会网络（通过 Layer 4.5） | 多智能体社会网络 |

### 9.2 核心功能

第二大脑通过 AgenticOS 各层能力提供以下服务：

| 功能 | 实现层级 | 说明 |
| :--- | :--- | :--- |
| 意图理解 | Layer 4 (brain-core) | RoutingEngine 自适应路由 |
| 多领域 Agent 调用 | Layer 2 (brain-domain-agent) | Python/Paper/Code 等领域 |
| 界面个性化 | Layer 5 (brain-frontend) | ViewManager 动态适配 |
| 网络搜索代理 | Layer 2 (InfrastructureAdapters) | NetworkAdapter 代理操作 |
| AI 编程辅助 | Layer 3 + Layer 2 | ReAct 引擎 + 代码 Domain |
| 社交协作 | Layer 4.5 (CiviMind) | 契约系统 + 声誉账本 |
| 应用市场 | Layer 6 (agentic-sdk) | 第三方 Agent 分发与管理 |
| 置信度服务 | Layer 4 (ConfidenceService) | 自适应预算与人机协作 |
| **状态管理** | **Layer 4 + Layer 2** | **C++ 原生状态 + DSL 工具封装** |

---

## 10. 安全与隐私

### 10.1 数据分级可见性

| 数据类型 | 本地处理 | 云端可见 | 保护机制 |
| :--- | :--- | :--- | :--- |
| 用户偏好 | 加密存储 | 仅可见脱敏标签（如 "高预算 "） | 数据分类与脱敏 |
| 私有记忆 | 本地向量索引 | 不可见 | 端侧加密，永不上传 |
| 谈判逻辑 | 本地推理生成 | 仅可见最终提案 | 逻辑黑盒化，Trace 仅存哈希 |
| 履约证明 | 本地执行生成哈希 | 可见哈希值与签名 | 零知识证明思路 |
| Agent 评价 | 本地提交 | 可见评价内容（匿名） | DID 匿名化 |
| **状态数据** | **C++ 原生存储** | **不可见** | **端侧加密 + 版本向量** |

### 10.2 端侧加密

* 用户上下文：`meta.user_context` 字段必须加密存储。
* 密钥管理：密钥存储在本地安全区域（TPM/Secure Enclave），永不上传云端。
* 解密时机：仅在 Layer 4 (brain-core) 内存中解密，Layer 1 仅存储密文。
* **状态路径加密**：敏感路径 (如 `security.*`, `user.private.*`) 必须加密存储。

### 10.3 零知识证明支持

* 预算证明：证明预算充足而不暴露具体金额。
* 声誉证明：证明声誉高于阈值而不暴露具体分数。
* 身份验证：验证 DID 所有权而不暴露私钥。

---

## 11. 可观测性

### 11.1 分层 SLO 体系

| 层级 | 关键指标 | 目标值 | 告警级别 |
| :--- | :--- | :--- | :--- |
| L0 | DSL 编译延迟 P99 | <100ms | P1 |
| L1 | DAG 持久化延迟 P99 | <50ms | P1 |
| L2 | 沙箱创建成功率 | >99.9% | P0 |
| L2.5 | 标准库加载延迟 P99 | <50ms | P2 |
| L3 | 推理步骤成功率 | >95% | P1 |
| L4 | 路由决策延迟 P99 | <10ms | P2 |
| L4.5 | 契约签署延迟 P99 | <100ms | P1 |
| L5 | 前端渲染延迟 P99 | <16ms | P2 |
| L6 | 应用市场安装成功率 | >99% | P2 |
| 端到端 | 用户请求响应 P99 | <2s | P1 |
| **状态工具** | **调用延迟 P99** | **<5ms** | **P2** |

### 11.2 P0 级安全告警

| 告警类型 | 检测内容 | 响应时间 |
| :--- | :--- | :--- |
| 沙箱逃逸检测 | 进程突破隔离边界 | <1s |
| 密钥泄露检测 | 加密密钥异常访问 | <1s |
| Contract DAG 篡改 | 契约哈希验证失败 | <1s |
| 命名空间违规 | 尝试写入  /lib/** | <1s |
| 死锁检测 | 调用链循环依赖 | <1ms |
| **Layer Profile 违规** | **越权调用 (如 L4 调用 tool)** | **<1s** |
| **状态工具越权** | **编译期拦截失败** | **<1s** |

### 11.3 全链路追踪

* **Trace ID**：贯穿所有层级，支持端到端追踪。
* **Span ID**：每层操作生成独立 Span。
* **双循环标识**：`loop_type` 字段区分 Coarse (L3/L4) / Fine (L0/L2)。
* **智能化扩展**：`intelligence` 字段记录自适应预算、置信度、风险等级。
* **Layer Profile**：记录当前执行的权限 Profile。
* **状态操作**：记录 `state.read`/`state.write` 操作路径与结果。

---

## 12. 实施路线图

### 12.1 Phase 1：核心闭环（3 个月）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1-2 | Layer 0 编译器 | DSL 编译 <100ms |
| W3-4 | Layer 1 存储 | SQLite 持久化 <50ms |
| W5-6 | Layer 2 沙箱 | cgroups 隔离 <500ms |
| W6-7 | Layer 2.5 标准库 | /lib/workflow/** 模板可用 |
| W7-8 | Layer 3 推理 | /lib/thinking/** 模板可用 |
| W9-10 | Layer 4 路由 | L1 规则路由 <10ms |
| W11-12 | 端到端集成 | Python 代码分析场景验证 |

### 12.2 Phase 2：安全与存储（2 个月）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1-2 | Zarr 集成 | 特征存储 |
| W3-4 | FAISS 向量检索 | <100ms 检索 |
| W5-6 | 端侧加密 | PBKDF2+AES-GCM |
| W7-8 | 向量时钟 | 冲突检测 |

### 12.3 Phase 3：生态与社会层（3 个月）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1-2 | Persona Core | DID 管理 |
| W3-4 | Intent Broadcast | 意图匹配 |
| W5-6 | Contract System | 契约签署 |
| W7-8 | SDK | agenticos CLI |
| W9-10 | Firecracker | 沙箱 <500ms |
| W11-12 | 端到端集成 | A↔B 契约 |

### 12.4 Phase 4：性能与扩展（2 个月）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1-2 | GPU 加速 | 推理调度优化 |
| W3-4 | DuckDB | 分析查询 |
| W5-6 | MCTS | 搜索算法 |
| W7-8 | 全链路压测 | SLO 达标 |

### 12.5 Phase 5：智能化演进（v2.2 核心）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | C++ 核心编排 | L2/L3/L4 逻辑 DSL 化，Python 逻辑移除率 50% | Layer-0-Spec-v2.2 |
| W3-4 | **状态管理工具化** | **`state.read/write` 工具可用，编译时检查生效** | **Layer-2/4-Spec-v2.2** |
| W5-6 | Layer Profile 安全 | 权限隔离验证，编译期拦截率 100% | Security-Spec-v2.2 |
| W7-8 | 智能化特性 | 自适应预算/调度可用，Fallback 机制验证 | Intelligence-Spec-v1.0 |
| W9-10 | **DSL 逻辑迁移** | **Python 逻辑移除率 100%**，性能回归测试通过 | All Specs |

---

## 13. 风险与缓解

| 风险 | 影响 | 缓解措施 | 责任人 |
| :--- | :--- | :--- | :--- |
| AgenticDSL 代码不兼容 | L0 重构延期 | 提前评估代码差异，建立适配层 | 架构委员会 |
| 纯函数约束难以保证 | 状态泄漏风险 | 单元测试 + 静态分析工具 | L0 负责人 |
| 标准库签名验证复杂 | Layer 2.5 延期 | Phase 1 简化为 Warn only | Layer 2.5 负责人 |
| 自适应预算逻辑复杂 | 预算超限风险 | 默认 fallback 到 strict 模式 | Layer 4 负责人 |
| 动态沙箱性能开销 | 执行延迟增加 | 优化快照复制机制 | Layer 2 负责人 |
| submodule 管理复杂 | 版本同步困难 | 建立版本映射表 | 配置管理 |
| MVP 范围过大 | Phase 1 延期 | 聚焦单一场景（Python 分析） | 项目经理 |
| **DSL 表达能力不足** | **复杂逻辑难以 DSL 化** | **增强 fork/join 和 llm_generate_dsl 原语** | **语言规范负责人** |
| **C++ 逻辑复杂度高** | **开发维护困难** | **严格模块化，增加单元测试覆盖率** | **L0 负责人** |
| **迁移成本高** | **现有 Python 逻辑废弃** | **提供 Python-to-DSL 迁移工具** | **Layer 2.5 负责人** |
| **L4 状态同步复杂** | **状态泄漏风险** | **只读快照 + 事务性更新 + 版本向量** | **L4 负责人** |
| **Layer Profile 验证遗漏** | **权限绕过风险** | **编译期 + 运行期双重验证 + 审计日志** | **安全负责人** |
| **C++ ABI 兼容性破坏** | **第三方集成失败** | **符号版本控制 + ABI 兼容性测试** | **L0 负责人** |
| **状态一致性风险** | **状态覆盖或冲突** | **版本向量 + 事务支持 (compare-and-swap)** | **L4 负责人** |
| **状态工具性能开销** | **调用延迟增加** | **批量操作 + 本地缓存 (TTL 受 L4 控制)** | **L2 负责人** |
| **安全绕过风险** | **未授权状态写入** | **编译时检查 + 运行时验证 + 审计日志** | **安全负责人** |

---

## 14. 文档清单

| 文档 | 路径 | 版本 | 状态 |
| :--- | :--- | :--- | :--- |
| 架构总纲 | AgenticOS-Architecture-v2.2.md | v2.2 | **当前** |
| Layer 0 规范 | AgenticOS-Layer-0-Resource-Spec.md | v2.2 | 规划中 |
| Layer 1 规范 | AgenticOS-Layer-1-Storage-Spec.md | v2.1.1 | 当前 |
| Layer 2 规范 | AgenticOS-Layer-2-Execution-Spec.md | v2.2 | 规划中 |
| Layer 2.5 规范 | AgenticOS-Layer-2.5-Spec.md | v2.2 | 规划中 |
| Layer 3 规范 | AgenticOS-Layer-3-Reasoning-Spec.md | v2.2 | 规划中 |
| Layer 4 规范 | AgenticOS-Layer-4-Cognitive-Spec.md | v2.2 | 规划中 |
| Layer 4.5 规范 | AgenticOS-Layer-4.5-Social-Spec.md | v2.1.1 | 当前 |
| Layer 5 规范 | AgenticOS-Layer-5-Interaction-Spec.md | v2.1.1 | 当前 |
| Layer 6 规范 | AgenticOS-Layer-6-Application-Spec.md | v2.1.1 | 当前 |
| 接口契约 | AgenticOS-Interface-Contract-v2.2.md | v2.2 | 规划中 |
| 同步协议 | AgenticOS-Sync-Protocol-v2.1.1.md | v2.1.1 | 当前 |
| 语言规范 | AgenticOS-Language-Spec-v4.4.md | v4.4 | 规划中 |
| DSL 引擎规范 | AgenticOS-DSL-Engine-Spec-v4.0.md | v4.0 | 规划中 |
| 智能化演进规范 | AgenticOS-Intelligence-Evolution-Spec-v1.0.0.md | v1.0.0 | 当前 |
| 安全规范 | AgenticOS-Security-Spec-v2.2.md | v2.2 | 规划中 |
| 实施路线图 | AgenticOS-Implementation-Roadmap-v2.2.md | v2.2 | 规划中 |
| 可观测性规范 | AgenticOS-Observability-Spec-v2.1.1.md | v2.1.1 | 当前 |
| 术语规范 | AgenticOS-Glossary-v2.1.1.md | v2.1.1 | 当前 |
| **状态管理工具规范** | **AgenticOS-State-Tool-Spec-v2.2.md** | **v2.2** | **规划中** |
| **Layer 4 状态接口** | **AgenticOS-Layer-4-State-Interface-v2.2.md** | **v2.2** | **规划中** |

---

## 15. 附录：核心术语

| 术语 | 英文 | 定义 |
| :--- | :--- | :--- |
| AgenticOS | AgenticOS | 智能体操作系统 |
| 八层架构 | Eight-Layer Architecture | Layers 0-5 + Layer 4.5 + Layer 2.5 |
| 第二大脑 | Second Brain | AgenticOS 的官方用户界面入口和全能助手（Layer 4+5+6 组合） |
| 双循环模型 | Dual Loop Model | L3/L4 粗粒度 ReAct 循环 + L0/L2 细粒度 DSL 循环 |
| DSL 核心引擎 | DSL Core Engine | AgenticOS Layer 0 运行时规范（v3.9/v4.0） |
| 标准库层 | Standard Library Layer | Layer 2.5，声明式标准原语（/lib/**） |
| 执行原语层 | Execution Primitives | DSL 三层架构 Layer 1，对应 AgenticOS Layer 0 |
| 标准原语层 | Standard Primitives | DSL 三层架构 Layer 2，对应 AgenticOS Layer 2.5 |
| 知识应用层 | Knowledge Application | DSL 三层架构 Layer 3，对应 AgenticOS Layer 3 + Layer 6 |
| 调用链 Token | Call Chain Token | 死锁检测用的调用路径记录 |
| 向量时钟 | Vector Clock | 多端同步并发修改检测机制 |
| 自适应预算 | Adaptive Budget | 基于置信度动态调整预算比例 (0.3-0.7) |
| 智能调度 | Smart Scheduling | L2 解析节点 metadata.priority，优化执行顺序 |
| 动态沙箱 | Dynamic Sandbox | 为  /dynamic/**  子图创建独立 SandboxInstance |
| 自适应人机协作 | Adaptive Human-in-the-Loop | 基于风险等级与置信度动态决定人工确认需求 |
| **Layer Profile** | **Layer Profile** | **Cognitive/Thinking/Workflow 权限模型** |
| **C++ Core** | **C++ Core** | **agentic-dsl-runtime 唯一真理源** |
| **状态管理工具化** | **State Management Toolization** | **通过 `state.read`/`state.write` 工具封装 L4 状态** |
| **IStateManager** | **IStateManager** | **L4 C++ 状态管理接口 (Read/Write/Subscribe)** |

---

**文档结束**  
**版权：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可