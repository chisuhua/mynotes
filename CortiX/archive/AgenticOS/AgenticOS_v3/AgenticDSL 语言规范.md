# AgenticDSL 语言规范 v3.10-PE（Parallel Edition）

> **版本**：v3.10-PE（Parallel Edition）  
> **状态**：LocalAI × AgenticDSL 统一架构基线规范  
> **定位**：定义对外稳定契约，独立于具体实现版本  
> **关键演进**：引入 Branch 并行执行模型、L0-L2 沙箱体系、ExecutionInstance 标识体系

---

## 目录

1. [引言与核心理念](#1-引言与核心理念)
2. [术语与概念体系](#2-术语与概念体系)
3. [程序结构](#3-程序结构)
4. [节点类型规范](#4-节点类型规范)
5. [上下文与数据流](#5-上下文与数据流)
6. [并发与并行](#6-并发与并行)
7. [安全与沙箱](#7-安全与沙箱)
8. [标准库契约](#8-标准库契约)
9. [附录](#9-附录)

---

## 1. 引言与核心理念

### 1.1 定位

AgenticDSL 是面向 AI-Native 应用的声明式动态 DAG 语言，支持：

- **确定性执行**：拓扑排序驱动，预算约束保障可终止性
- **并行推理**：Branch 级并行（Fork/Join）、推测执行（Speculative）、结果集成（Ensemble）
- **动态生长**：运行时生成子图（`generate_subgraph`），支持思维流与行动流统一
- **资源契约**：AgentPool 资源池化、单实例单会话约束、显存水位保护
- **分级安全**：L0-L2 沙箱体系，代码与数据隔离边界清晰

### 1.2 根本范式

| 角色 | 职责 |
|------|------|
| **LLM** | 基于上下文生成结构化子图（`/dynamic/**`），遵循预算与签名约束 |
| **执行器** | 调度 Branch 并行执行，管理 ExecutionInstance 生命周期，强制执行资源契约 |
| **Branch** | DAG 内的轻量级执行单元，拥有独立 COW 上下文与沙箱级别 |
| **AgentPool** | 推理资源（LLM/SD/Whisper）的池化管理，确保单实例单会话隔离 |
| **上下文** | 结构可契约、合并可策略、冲突可诊断的不可变数据流 |

### 1.3 设计原则

- **确定性优先**：所有节点在有限时间内完成；禁止异步回调；LLM 调用必须声明 `seed` 与 `temperature`
- **并行安全**：Branch 间通过 COW（写时复制）隔离，Join 时按策略合并，禁止执行期跨 Branch 写操作
- **预算层级**：Session Budget ≥ Instance Budget ≥ Branch Budget，防止级联资源耗尽
- **沙箱分级**：L0（直接调用）、L1（Seccomp）、L2（进程隔离），动态升级不可逆
- **契约驱动**：`/lib/**` 必须声明 `signature`，`/dynamic/**` 可选签名校验

---

## 2. 术语与概念体系

### 2.1 核心术语表（规范级定义）

| 术语 | 英文 | 定义 | 作用域 | 生命周期 |
|------|------|------|--------|---------|
| **分支** | Branch | DAG 中的轻量级并行执行单元，拥有独立调度队列、COW 上下文覆盖层和沙箱级别 | Session 内 | Fork 创建 → Join 合并 |
| **执行实例** | ExecutionInstance | 单次 DSL 执行的完整运行时上下文，全局唯一标识（`exec_{layer}_{uuid}`），与 `session_id` 解耦 | 全局 | `run()` 开始 → 结果返回 |
| **会话** | Session | 用户级对话上下文，持久化存储于 SQLite，可包含多个 ExecutionInstance | 用户级 | 多轮对话周期（TTL 管理） |
| **资源池** | AgentPool | 推理资源（LLM/SD/Whisper）的池化管理器，实现资源复用与**单实例单会话约束** | 全局 | 引擎启动 → 关闭 |
| **推理资源** | LLMResource | AgentPool 中的单个推理实例包装器，封装模型上下文与占用状态 | AgentPool 内 | 创建 → 显式释放 |
| **并行原语** | Fork/Join | DSL 声明的并行控制节点，创建/合并多个 Branch，支持字段级上下文合并策略 | DAG 内 | 节点执行周期 |
| **沙箱级别** | SandboxLevel | 执行隔离等级：L0（直接）、L1（Seccomp-BPF）、L2（Namespace+OverlayFS） | Branch 级 | Branch 生命周期，支持动态升级 |
| **写时复制** | COW Context | Copy-On-Write 上下文机制，Fork 时共享父引用，写入时触发深拷贝 | Branch 内 | Branch 生命周期 |

> **术语使用规范**：文档与代码中统一使用上述英文术语作为标识符，中文术语用于文档叙述。

### 2.2 层级关系

```
Session (用户级对话)
├── ExecutionInstance_1 (单次 DSL 执行，如 "/main/analyze")
│   ├── Branch_A (Fork 创建，并行路径 A)
│   ├── Branch_B (Fork 创建，并行路径 B)
│   └── Branch_C (Fork 创建，并行路径 C)
├── ExecutionInstance_2 (子任务，如代码生成)
│   └── Branch_D
└── ExecutionInstance_3 (原子操作)

AgentPool (全局资源)
├── LLMResource_1 (occupied by Instance_1)
├── LLMResource_2 (occupied by Instance_2)
└── LLMResource_3 (available)
```

**关键约束**：
- **Branch 不可跨 Session**：Branch 的 Context/Sandbox 状态依附于创建它的 Session
- **Instance 单线程调度**：单个 ExecutionInstance 的调度器在单线程内运行，Branch 并行通过 ThreadPool 实现
- **Resource 占用原子性**：`occupied_` 标记必须使用原子操作，防止并发获取竞态

---

## 3. 程序结构

### 3.1 路径命名空间

| 命名空间 | 用途 | 可写入 | 可复用 | 签名要求 | 沙箱默认级别 |
|----------|------|--------|--------|----------|--------------|
| `/lib/**` | 标准库（只读） | ❌ 禁止 | ✅ 全局 | ✅ 强制 | L0 |
| `/dynamic/**` | 运行时生成子图 | ✅ 自动 | ⚠️ 会话内 | ⚠️ 可选 | L1 |
| `/main/**` | 主流程入口 | ✅ 允许 | ❌ | ❌ | L0 |
| `/app/**` | 工程别名（等价于 `/main/**`） | ✅ 允许 | ❌ | ❌ | L0 |
| `/__meta__` | 元信息（版本、入口、资源声明） | ✅（仅解析阶段） | N/A | N/A | N/A |

**沙箱级别覆盖规则**：
- 标准库 `/lib/**` 强制 L0（信任执行）
- `/main/**` 和 `/app/**` 默认 L0，可通过节点级 `sandbox_level` 字段升级
- `/dynamic/**` 默认 L1，高风险操作自动升级到 L2

### 3.2 统一文档结构

#### 3.2.1 元信息块（`/__meta__`）

```yaml
### AgenticDSL `/__meta__`
version: "3.10-PE"
mode: dev  # dev | prod
entry_point: "/main/start"  # 必需
execution_budget:
  max_nodes: 20
  max_subgraph_depth: 2
  max_duration_sec: 60
  max_snapshots: 10
context_merge_policy: "error_on_conflict"  # 默认合并策略
```

#### 3.2.2 资源声明块（`/__meta__/resources`）

```yaml
### AgenticDSL `/__meta__/resources`
type: resource_declare
resources:
  - type: tool
    name: web_search
    scope: read_only
  - type: runtime
    name: python3
    allow_imports: [json, re]
  - type: generate_subgraph
    max_depth: 2
  - type: reasoning
    capabilities: [structured_generate, kv_continuation]
  - type: sandbox
    max_level: L2  # 声明本会话可能使用的最高沙箱级别
    l2_pool_size: 10  # L2 进程池预热大小
```

**资源声明规则**：
- 启动时验证所有声明资源的可用性，失败返回 `ERR_RESOURCE_UNAVAILABLE`
- `sandbox.max_level` 限制本会话可使用的最高沙箱级别，防止逃逸

---

## 4. 节点类型规范

### 4.1 节点通用字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `type` | string | ✅ | 节点类型 |
| `next` | string / list | ❌ | 后继节点路径（支持 `@v1` 版本语法） |
| `permissions` | list | ❌ | 权限声明列表 |
| `sandbox_level` | enum | ❌ | 覆盖默认沙箱级别（L0/L1/L2） |
| `context_merge_policy` | object | ❌ | 字段级合并策略覆盖 |
| `on_success` | string | ❌ | 成功后动作（如 `archive_to`） |
| `on_error` | string | ❌ | 错误跳转路径 |
| `expected_output` | object | ❌ | 期望输出（用于验证/训练） |
| `curriculum_level` | string | ❌ | 课程难度标签 |

### 4.2 执行原语层（叶子节点）

#### 4.2.1 `start`
无操作，跳转到 `next`。

#### 4.2.2 `end`
终止当前子图。

```yaml
type: end
metadata:
  termination_mode: hard  # hard: 终止整个 DAG；soft: 返回调用者上下文
output_keys: ["result"]  # soft 模式下合并到父上下文的字段（可选）
```

#### 4.2.3 `assign`
安全赋值到上下文（Inja 模板渲染）。

```yaml
type: assign
assign:
  preferred_drink: "coffee"                    # 直接值
  welcome_msg: "Hello, {{ user.name }}!"       # Inja 模板
  item_count: "{{ length(items) }}"            # 表达式
next: "/main/next_step"
```

**执行语义**：
- 按 Inja 模板渲染后写入上下文，失败抛出异常
- 多个键并发写入，冲突遵循当前合并策略
- 支持嵌套路径（如 `user.profile.name`）

#### 4.2.4 `dsl_call`（v3.10，旧名 `llm_call`）
通过已注册的 LLM 工具生成文本。

```yaml
type: dsl_call
prompt_template: "请分析 {{ $.input }} 并给出结论"
llm_tool_name: "llama-7b"  # 对应 AgentPool 中注册的工具名
llm_params:
  temperature: 0.7
  max_tokens: 512
  seed: 42  # 确定性生成
output_keys: ["analysis"]
next: "/main/verify"
```

**约束**：
- `llm_tool_name` 必须在 `/__meta__/resources` 中声明或通过 `AgentPool` 注册
- 执行时从 `AgentPool` 获取 `LLMResource`，检查 `occupied_` 标记
- **禁止在 L2 沙箱内直接执行**（L2 用于用户代码，LLM 推理必须在 L0/L1）

#### 4.2.5 `tool_call`
调用注册工具。

```yaml
type: tool_call
tool: calculate
arguments:
  a: "{{ $.num1 }}"
  b: "{{ $.num2 }}"
  op: "+"
output_keys: ["sum_result"]
permissions:
  - tool: calculate
```

**沙箱执行**：
- 若工具标记为高风险（如 `python3` 运行时），自动升级到 L2 沙箱
- L2 沙箱内执行通过 IPC 回传结果，禁止直接访问 `AgentPool`

#### 4.2.6 `generate_subgraph`
委托 LLM 生成结构化子图并动态注入。

```yaml
type: generate_subgraph
prompt_template: "方程 {{ $.expr }} 求解失败。请重写为标准形式并生成新 DAG。"
output_keys: ["generated_graph_path"]
signature_validation: warn  # strict | warn | ignore
namespace_prefix: "/dynamic/repair_{{ $.instance_id }}"  # 强制前缀
next: "/dynamic/repair_123/start"
```

**约束**：
- 生成路径必须位于 `/dynamic/**`，禁止写入 `/lib/**`（`ERR_NAMESPACE_VIOLATION`）
- 新子图通过 `ExecutionInstance` 的动态图注入机制注册
- 遵守 `execution_budget.max_subgraph_depth`

#### 4.2.7 `assert`
验证条件，失败跳转。

```yaml
type: assert
condition: "{{ len($.roots) == 1 and $.roots[0] == -1 }}"
on_failure: "/self/repair"
```

#### 4.2.8 `fork` / `join`
显式并行控制。

**Fork 节点**：
```yaml
type: fork
branches:
  - "/main/hypothesis_a"
  - "/main/hypothesis_b"
  - "/main/hypothesis_c"
mode: parallel  # parallel | speculative | ensemble
options:
  speculative_validator: "{{ $.confidence > 0.9 }}"  # Speculative 模式用
  ensemble_aggregator: "majority_vote"  # Ensemble 模式用
```

**Join 节点**：
```yaml
type: join
wait_for: ["@all"]  # @all | @any | ["branch_id_1", "branch_id_2"]
merge_strategy: "error_on_conflict"  # 全局策略
field_policies:
  "confidence_scores": "array_concat"
  "final_result": "last_write_wins"
timeout_sec: 30  # 等待超时，超时报错
```

**执行语义**：
- **Fork**：创建 N 个 Branch，每个 Branch 拥有独立的 COW 上下文和调度队列
- **并行模式**：所有 Branch 同时提交到 `BranchExecutor`，利用 ThreadPool 并发执行
- **推测模式**：多 Branch 执行同一任务，首个满足 `validator` 的结果立即返回，取消其他 Branch
- **集成模式**：多 Branch 执行不同策略，结果按 `aggregator` 合并（投票/加权/元评判）
- **Join**：等待指定 Branch 完成，按 `merge_strategy` 和 `field_policies` 合并上下文

**Branch 生命周期**：
1. Fork 时创建 Branch，初始化 COW 上下文（共享父引用）
2. Branch 内节点执行时，写入操作触发深拷贝（Copy-On-Write）
3. Join 时合并各 Branch 的上下文，冲突检测遵循策略
4. 合并完成后销毁 Branch，释放资源

---

## 5. 上下文与数据流

### 5.1 上下文模型（Context）
全局可变字典，支持嵌套路径（如 `user.name`）。

**特殊变量**：
- `$.now`：ISO 8601 当前时间（执行器注入）
- `$.instance_id`：当前 ExecutionInstance ID
- `$.branch_id`：当前 Branch ID（Fork 后有效）
- `$.ctx_snapshots['/main/step3']`：访问指定节点的上下文快照（静态键）

### 5.2 合并策略（字段级、可继承）

| 策略 | 行为说明 | 适用场景 |
|------|----------|----------|
| `error_on_conflict`（默认） | 任一字段在多个 Branch 中被写入 → 报错终止 | 严格一致性要求 |
| `last_write_wins` | 以最后完成的 Branch 写入值为准 | 幂等操作（仅用于 `dev` 模式） |
| `deep_merge` | 递归合并对象；数组完全替换（非拼接）；标量覆盖 | 对象属性合并 |
| `array_concat` | 数组拼接（保留顺序，允许重复） | 收集多 Branch 结果 |
| `array_merge_unique` | 数组拼接 + 去重（基于 JSON 序列化值） | 去重收集 |

**策略继承**：
- 子图策略优先于父图
- 字段级 `field_policies` 优先于全局 `merge_strategy`
- 支持通配路径（如 `results.*`）

### 5.3 快照机制
在 `ForkNode`、`GenerateSubgraphNode`、`AssertNode` 执行前自动保存上下文快照。

```yaml
# 访问快照（静态键）
type: assign
assign:
  prev_state: "{{ $.ctx_snapshots['/main/step3'] }}"
```

**安全限制**：`$.ctx_snapshots` 的访问键必须为**静态字符串**，禁止动态计算（如 `{{ $.key }}`）。

---

## 6. 并发与并行

### 6.1 并行层级矩阵

| 并行维度 | 控制主体 | 功能边界 | 隔离边界 | 适用场景 |
|---------|---------|---------|---------|---------|
| **Branch 级** | `TopoScheduler` + `BranchExecutor` | DAG 内多路径并行推理 | COW 上下文 + 沙箱 + 预算 | 多假设验证、Ensemble |
| **Instance 级** | `SessionManager` | 多用户/多任务并发执行 | DSLEngine + Budget | 多租户服务、批处理 |
| **Resource 级** | `AgentPool` | 多模型实例并发推理 | 模型实例 + KV Cache | 高并发请求、资源复用 |
| **System 级** | `ThreadPool` | 底层任务调度 | 线程/进程边界 | 计算/IO 分离 |

### 6.2 并发约束

1. **Branch 不可跨 Session**：Branch 状态依附于创建它的 Session
2. **Instance 单线程调度**：单个 ExecutionInstance 的调度器在单线程内运行，Branch 并行通过 ThreadPool 实现
3. **Resource 单实例单会话**：`LLMResource` 通过 `occupied_` 原子标记确保同一时刻只服务一个 Instance
4. **预算层级**：`Session Budget` ≥ `Instance Budget` ≥ `Branch Budget`
5. **沙箱升级不可逆**：Branch 执行中可升级 `SandboxLevel`（L0→L1→L2），禁止降级

### 6.3 预算控制

```yaml
execution_budget:
  max_nodes: 20           # 本实例最大节点数
  max_llm_calls: 10       # LLM 调用次数上限
  max_subgraph_depth: 2   # 动态生成深度上限
  max_duration_sec: 60    # 执行时间上限
  max_branches: 10        # 最大并发 Branch 数（新增）
```

**预算消耗**：
- 每个节点执行前检查 `BudgetController`
- Fork 创建 Branch 时预检查 `max_branches`
- LLM 调用时检查 `max_llm_calls` 和 AgentPool 可用性
- 超限时跳转至 `/__system__/budget_exceeded`

---

## 7. 安全与沙箱

### 7.1 三级沙箱体系（L0-L2）

| 级别 | 技术实现 | 启动延迟 | 适用场景 | 防御能力 |
|------|---------|---------|---------|---------|
| **L0** | 直接函数调用（同进程） | ~0μs | 标准库 `/lib/**`、内部工具 | 依赖代码审计 |
| **L1** | Seccomp-BPF + Cgroups | ~1ms | API 调用、文件操作、网络请求 | 系统调用过滤 |
| **L2** | Clone Namespace + OverlayFS | ~50ms（预热后 ~5ms） | 用户上传代码、第三方工具、Python 运行时 | 文件系统/网络/进程隔离 |

**L3 预留**：作为未来扩展点（如 VM 级隔离），v3.10-PE 规范中保留枚举值但不实现。

### 7.2 沙箱级别选择策略

**默认规则**：
- `/lib/**`：强制 L0
- `/main/**`、`/app/**`：默认 L0，可通过节点级 `sandbox_level` 显式升级
- `/dynamic/**`：默认 L1，执行高风险操作（如 `codelet_call`）时自动升级到 L2

**动态升级**：
```cpp
// 伪代码示例
if (node.type == "tool_call" && tool.risk_level == "high") {
    branch.sandbox_level = SandboxLevel::L2;  // 自动升级
    // 保存状态，迁移到 L2 进程，恢复执行
}
```

**关键约束**：
- **LLM 推理禁止在 L2 执行**：`dsl_call` 节点必须在 L0/L1 执行，通过 `AgentPool` 获取资源
- **L2 进程禁止直接访问 AgentPool**：必须通过 IPC（Unix Domain Socket）向主进程请求 LLM 调用

### 7.3 权限与沙箱联动

```yaml
permissions:
  - tool: python3
    sandbox_level: L2  # 声明需要 L2 沙箱
  - network:
      outbound:
        domains: ["api.example.com"]
```

**权限校验时机**：
1. **解析时**：验证权限声明格式
2. **执行前**：检查当前 Branch 的 `sandbox_level` 是否满足节点要求
3. **运行时**：L2 沙箱内通过 Seccomp 阻止未声明的系统调用

---

## 8. 标准库契约

### 8.1 标准库路径（`/lib/**`）

| 类别 | 路径 | 功能 | 沙箱级别 |
|------|------|------|----------|
| 子图管理 | `/lib/dslgraph/generate@v1` | 动态 DSL 生成 | L0 |
| 推理原语 | `/lib/reasoning/generate_text@v1` | 文本生成 | L0 |
| | `/lib/reasoning/structured_generate@v1` | 结构化输出 | L0 |
| | `/lib/reasoning/hypothesize_and_verify@v1` | 假设验证 | L0（内部 Fork）|
| 内存记忆 | `/lib/memory/state/set@v1` | 状态存储 | L0 |
| | `/lib/memory/kg/query_subgraph@v1` | 知识图谱查询 | L0 |
| 对话协议 | `/lib/conversation/start_topic@v1` | 话题管理 | L0 |

**契约要求**：
- 必须声明 `signature`（输入/输出/版本）
- 必须指定 `stability`（stable/experimental/deprecated）
- 强制 L0 执行（标准库受信任）

### 8.2 子图签名规范

```yaml
### AgenticDSL '/lib/reasoning/analyze@v1'
signature:
  inputs:
    - name: query
      type: string
      required: true
  outputs:
    - name: result
      type: object
      schema: { type: object, properties: { ... } }
  version: "1.0"
  stability: stable
permissions:
  - reasoning: llm_generate
```

---

## 9. 附录

### 9.1 错误码字典

| 错误码 | 名称 | 含义 | HTTP 映射 |
|--------|------|------|-----------|
| `0x0000` | `UNKNOWN` | 未知错误 | 500 |
| `0x0001` | `BACKPRESSURE_TIMEOUT` | 背压超时 | 503 |
| `0x0002` | `PROTOCOL_VERSION_MISMATCH` | 协议版本不匹配 | 400 |
| `0x1001` | `AI_OOM` | 显存不足 | 503 |
| `0x1002` | `AI_MODEL_LOAD_FAILED` | 模型加载失败 | 500 |
| `0x2001` | `DSL_PARSE_ERROR` | DSL 解析错误 | 400 |
| `0x2002` | `DSL_NODE_EXEC_FAILED` | 节点执行失败 | 500 |
| `0x2003` | `DSL_BUDGET_EXCEEDED` | 预算超限 | 429 |
| `0x2004` | `DSL_NAMESPACE_VIOLATION` | 命名空间违规（如写入 `/lib/**`） | 403 |
| `0x3001` | `AUTH_PERMISSION_DENIED` | 权限不足 | 403 |
| `0x4001` | `SYS_POOL_EXHAUSTED` | AgentPool 耗尽 | 503 |
| `0x4002` | `SYS_SANDBOX_ESCAPE` | 沙箱逃逸尝试 | 500 |

### 9.2 版本映射表

| 文档版本 | DSL 规范 | LocalAI 引擎 | 协议版本 | 沙箱支持 | 状态 |
|----------|----------|--------------|----------|----------|------|
| v1.0 | v3.10-PE | v2.1-P0 | v2.1 | L0-L2 | 当前基线 |
| v1.1 | v3.11 | v2.2 | v2.2 | L0-L2 (优化) | 规划中 |

### 9.3 Inja 模板安全模式

**允许**：变量（`{{ $.path }}`）、条件（`{% if %}`）、循环（`{% for %}`）、过滤器（`upper`、`length`）  
**禁止**：`include`、`extends`、环境变量访问、任意代码执行

### 9.4 保留关键字

`session_id`、`instance_id`、`branch_id`、`trace_id`、`ctx_snapshots`、`now`、`budget`、`permissions`、`sandbox_level`

---

**AgenticDSL v3.10-PE** 通过 **Branch 并行模型**、**L0-L2 沙箱体系** 与 **AgentPool 资源契约**，为构建可靠、可协作、可进化的 AI 应用提供了工业级语言基石。
