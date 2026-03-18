

**安全 · 可终止 · 可调试 · 可复用 · 可契约 · 可验证**

## 引言
AgenticDSL 是一套 AI-Native 的声明式动态 DAG 语言，专为单智能体及未来多智能体系统设计。通过构建由DAG驱动AgenticDSL应用，构建被LLM可理解学习的DAG标准库，最终实现一切应用都可以由LLM来驱动和优化, 让LLM成为计算机的主人。

## 一、核心理念与定位

### 1.1 定位

AgenticDSL支持：
- **LLM 可生成**：大模型能输出结构化、可执行的子图
- **引擎可执行**：确定性调度、状态合并、预算控制
- **DAG 可动态生长**：运行时生成新子图，支持思维流与行动流
- **标准库可契约复用**：`/lib/**` 带签名，最小权限沙箱
- **推理可验证进化**：通过 `assert`、Trace、`archive_to` 实现闭环优化

### 1.2 根本范式
| 角色 | 职责 |
|------|------|
| LLM | 程序员：基于真实状态生成可验证子图 |
| 执行器 | 运行时：确定性调度、状态合并、预算控制 |
| 上下文 | 内存：结构可契约、合并可策略、冲突可诊断 |
| DAG | 程序：图可增量演化，支持行动流与思维流 |
| 标准库 | SDK：`/lib/**` 必须带 `signature`，最小权限沙箱 |

### 1.3 设计原则
- **确定性优先**：所有节点必须在有限时间内完成；禁止异步回调；LLM 调用必须声明 `seed` 与 `temperature`；输出需经结构化验证（如 JSON Schema）
- **契约驱动**：接口必须声明，调用必须验证
- **最小权限**：节点/子图需显式声明所需权限；权限组合遵循交集原则
- **可终止性**：全局预算控制，防止无限循环或生成
- **可观测性**：每个节点生成结构化 Trace，支持调试与训练
- **可验证性**：所有推理行为必须可通过 `assert`、Trace 或归档机制进行事后验证

## 二、节点抽象层级（三层架构 + 交互边界）

### 2.1 三层架构
| 层级 | 说明 | 约束 |
|------|------|------|
| 1. 执行原语层（叶子节点） | 规范内置、不可扩展的最小操作单元 | 禁止用户自定义新类型 |
| 2. 标准原语层 | 规范提供的稳定接口实现 | 路径：`/lib/dslgraph/**`, `/lib/memory/**`, `/lib/reasoning/**`, `/lib/conversation/**`，版本稳定 |
| 3. 知识应用层 | 用户/社区扩展的领域逻辑 | 路径：`/lib/workflow/**`, `/lib/knowledge/**` |

✅ 所有复杂逻辑必须通过子图组合实现，禁止在叶子节点中编码高层语义。

注：`/app/**` 不属于上述三层架构，仅为工程组织约定（见附录 A）。

### 2.2 层间契约规则
- **执行 → 标准原语**：仅通过上下文传递数据，禁止直接 API 调用
- **标准原语 → 知识应用**：必须通过 `signature` 暴露能力
- **禁止跨层跳转**：知识应用层不得直接调用执行原语层（必须通过 `/lib/**` 封装）
- **动态子图生成能力**：通过 `/lib/dslgraph/**` 实现，`llm_generate_dsl` 仅用于内部封装
- **强制沙箱隔离**：所有非标准原语层的操作必须通过标准库接口访问外部系统

### 2.3 适配器模式显式化
所有外部系统交互必须通过规范定义的工具接口：
- **工具注册表**：执行器维护 `tool_schema`，声明输入/输出契约
- **适配器隔离**：DAG 仅通过 `tool_call` 与工具交互，不依赖实现细节
- **安全边界**：禁止启动线程、注册回调、直接读写上下文、访问未声明资源

## 三、术语表
| 术语 | 定义 |
|------|------|
| 子图（Subgraph） | 以 `### AgenticDSL '/path'` 开头的逻辑单元 |
| 动态生长 | 通过子图生成在运行时注册新子图至 `/dynamic/**` |
| 契约（Contract） | 由 `signature` 定义的输入/输出接口规范 |
| 软终止 | 子图结束时返回调用者上下文，而非终止整个 DAG |
| 核心标准库 | 强制实现的 `/lib/**` 子图集合（见附录 C） |
| 执行原语层 | 内置叶子节点（如 `assign`, `assert`），不可扩展 |
| 语义能力（Capability） | 执行器可提供的一组原子功能，如 `structured_generate`、`kv_continuation` |

## 四、公共契约

### 4.1 上下文模型（Context）
全局可变字典，支持嵌套路径（如 `user.name`）
**合并策略（字段级、可继承）**：

| 策略 | 行为说明 |
|------|----------|
| `error_on_conflict`（默认） | 任一字段在多个分支中被写入 → 报错终止 |
| `last_write_wins` | 以最后完成的节点写入值为准（仅用于幂等操作，禁用于 `prod` 模式） |
| `deep_merge` | 递归合并对象；数组完全替换（非拼接）；标量覆盖（严格遵循 RFC 7396） |
| `array_concat` | 数组拼接（保留顺序，允许重复） |
| `array_merge_unique` | 数组拼接 + 去重（基于 JSON 序列化值） |

✅ **字段级策略继承**：支持通配路径（如 `results.*`），子图策略优先于父图  
✅ **结构化冲突错误**：必须包含字段路径、各分支值、来源节点、错误码 `ERR_CTX_MERGE_CONFLICT`

### 4.2 Inja 模板引擎（安全模式）
✅ **允许**：变量（如 `{{ $.path }}`）、条件、循环、表达式  
❌ **禁止**：`include`/`extends`、环境变量、任意代码执行  
🔁 **性能优化**：缓存相同模板+上下文的渲染结果  

**时间上下文**：可通过 `$.now` 访问（ISO 8601 字符串），非模板函数，由执行器注入。

### 4.3 节点通用字段
| 字段 | 说明 |
|------|------|
| `type` | 节点类型（必需） |
| `next` | 路径或路径列表（支持 `@v1`） |
| `permissions` | 权限声明（见 7.2） |
| `context_merge_policy` | 字段级合并策略 |
| `on_success` | 成功后动作（如 `archive_to(...)`） |
| `on_error` | 错误跳转路径（若未定义，则终止当前子图） |
| `expected_output` | 期望输出（用于验证/训练） |
| `curriculum_level` | 课程难度标签（如 `beginner`） |

❌ **移除 `dev_comment`**：使用标准 Markdown 注释（如 `<!-- debug: ... -->`）

**说明**：`expected_output` 用于单次执行验证，而 `signature.outputs` 用于子图接口契约。前者记录具体期望值用于 Trace 验证，后者定义调用契约。

## 五、核心叶子节点定义（执行原语层）

### 5.1 `assign`
**语义**：安全赋值到上下文（Inja 表达式）
```yaml
type: assign
assign:
  expr: "coffee"
  path: "memory.state.preferred_drink"
meta:
  ttl_seconds: 600
  persistence: ephemeral
```

**字段表**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| assign.expr | string | ✅ | Inja 表达式 |
| assign.path | string | ✅ | 目标上下文路径 |
| meta.ttl_seconds | integer | ❌ | 字段存活时间（秒），超时后自动删除 |
| meta.persistence | string | ❌ | `ephemeral`（默认）或 `durable` |

**执行器行为**：
- 仅 `memory.state.*` 路径支持 TTL；其他路径忽略 `meta`
- `durable` 字段永不自动清理（用于长期状态）
- 每次调度前清理已过期字段（不计入 `max_nodes`）

### 5.2 `tool_call`
**语义**：调用注册工具（带权限检查）  
**关键字段**：`tool`, `arguments`, `output_mapping`  
**权限要求**：必须声明 `permissions`（如 `tool: web_search`）

### 5.3 `codelet_call`
**语义**：执行沙箱代码（带安全策略）  
**关键字段**：`runtime`, `code`, `security`  
**权限要求**：必须声明 `permissions`（如 `runtime: python3`）

### 5.4 `assert`
**语义**：验证条件，失败则跳转  
**关键字段**：`condition`（Inja 布尔表达式）, `on_failure`
```yaml
type: assert
condition: "{{ len($.roots) == 1 }}"
on_failure: "/self/repair"
```

### 5.5 `fork` / `join`
**语义**：显式并行控制  
- `fork.branches`: 路径列表
- `join.wait_for`: 依赖列表, `merge_strategy`

**依赖解析时机**：执行器必须在节点入调度队列前解析 `wait_for` 表达式  
**禁止**：在执行中动态变更依赖拓扑

### 5.6 `end`
**语义**：终止当前子图  
**关键字段**：
- `termination_mode`: `hard`（默认）或 `soft`
- `output_keys`: 仅合并指定字段到父上下文（`soft` 模式）

### 5.7 `llm_generate_dsl`
**语义**：委托 LLM 生成结构化子图（仅用于 `/lib/dslgraph/generate@v1` 内部封装）  
**输出**：必须为 `### AgenticDSL '/dynamic/...'` 块  
**权限**：`generate_subgraph: { max_depth: N }`  
**namespace_prefix** 强制为 `/dynamic/`，禁止 `/lib/` 或 `/main/`

**字段表**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| prompt | string | ✅ | 完整提示（已渲染 Inja 模板） |
| llm | object | ✅ | `model`, `seed`（整数）, `temperature`（≤1.0） |
| output_constraints | object | ✅ | 见下表 |
| next | string or list | ✅ | 成功后跳转路径 |

**output_constraints 子字段**：
| 字段 | 默认值 | 说明 |
|------|--------|------|
| must_be_agenticdsl_blocks | true | LLM 输出必须为 `### AgenticDSL '/dynamic/...'` 块 |
| namespace_prefix | "/dynamic/" | 强制生成路径前缀，禁止 `/lib/` 或 `/main/` |
| max_blocks | 3 | 最多生成子图数量 |
| validate_json_schema | true | 对每个 block 内容做 JSON Schema 验证 |

**Trace 输出**：
```json
{
  "llm_generate_dsl": {
    "prompt_tokens": 120,
    "completion_tokens": 300,
    "generated_paths": ["/dynamic/plan_1", "/dynamic/plan_2"],
    "validation_passed": true
  }
}
```

### 5.8 `start`
无操作，跳转到 `next`

### 5.9 `llm_call`
**语义**：调用推理引擎内置 LLM 推理内核  
**约束**：仅可通过 `/lib/reasoning/**` 子图调用，禁止用户在知识应用层或主 DAG 中直接使用  

**必需字段**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| llm.model | string | ✅ | 模型标识（如 `gpt-4o`, `llama-3-8b`） |
| llm.seed | integer | ✅ | 确定性种子 |
| llm.temperature | number | ✅ | 温度（0.0–1.0） |
| llm.prompt | string | ✅ | 提示词（Inja 渲染后） |

**标准可选字段**（执行器必须识别，未声明则忽略）：
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| llm.max_tokens | integer | 256 | 最大生成长度 |
| llm.output_schema | object | — | JSON Schema，用于结构化输出约束 |
| llm.kv_handle | string | — | KV 缓存句柄，用于续写 |
| llm.stop_condition | string | — | 流式终止条件（如特殊 token 或字符串） |
| llm.draft_model | string | "phi-3-mini" | 推测解码头模型 |
| llm.max_speculative_tokens | integer | 5 | 推测最大 token 数 |

**行为规则**：
- 所有字段必须通过 `Inja` 安全渲染（禁止任意代码）
- 若字段未定义（如 `output_schema`），执行器应忽略而非报错
- 返回值必须包含 `text` 字段；若支持 KV 复用，可附加 `kv_handle`
- **Trace 必须记录**：
```json
{
  "llm_call": {
    "model": "gpt-4o",
    "prompt_tokens": 120,
    "completion_tokens": 80,
    "used_features": ["output_schema", "kv_handle"],
    "backend_used": "AgenticInfer-v1.4"
  }
}
```

**权限要求**：必须声明对应推理权限（如 `reasoning: llm_generate`）

## 六、统一文档结构

### 6.1 路径命名空间（关键强化）
| 命名空间 | 用途 | 可写入？ | 可复用？ | 签名要求 |
|----------|------|----------|----------|----------|
| `/lib/**` | 标准库（只读） 包含推理、记忆、图操作等契约化组件 | ❌ 禁止运行时写入或覆盖 | ✅ 全局可用 | ✅ 强制 |
| `/dynamic/**` | 运行时生成子图 | ✅ 自动写入 | ⚠️ 会话内有效 | ⚠️ 可选（验证后） |
| `/main/**` | 主流程入口 | ✅ 允许 | ❌ | ❌ |
| `/app/**` | 工程别名，语义等价于 `/main/**` | ✅ 允许 | ❌ | ❌ |
| `/__meta__` | 元信息（版本、入口、资源声明） | ✅（仅解析阶段） | N/A | N/A |

**执行器行为**：
- 违反命名空间写规则（如尝试写入 `/lib/**`）→ `ERR_NAMESPACE_VIOLATION`
- 执行器应默认支持 `/app/**` 作为 `/main/**` 的语义等价命名空间。在沙箱或高安全环境中，可通过配置显式禁用，此时归档或引用 /app/** 路径应返回 ERR_NAMESPACE_DISABLED

### 6.2 子图签名（Subgraph Signature）
所有 `/lib/**` 必须声明：
```yaml
signature:
  inputs:
    - name: expr
      type: string
      required: true
  outputs:
    - name: roots
      type: array
      schema: { type: array, items: { type: number }, minItems: 1 }
  version: "1.0"
  stability: stable  # stable / experimental / deprecated
```

### 6.3 显式执行入口
```yaml
AgenticDSL `/__meta__`
version: "3.9"
mode: dev
entry_point: "/main/start"  # ✅ 必需：DAG 执行入口路径
execution_budget:
  max_nodes: 20
  max_subgraph_depth: 2
```

**规则**：
- 唯一性：每个 `.agent.md` 仅允许一个 `entry_point`
- 必需字段；若缺失 → `ERR_MISSING_ENTRY_POINT`
- 必须指向文档中已定义的子图
- 推荐将入口设为 `/main/start`（类型为 `start` 或 `assign`）

### 6.4 资源声明（Resource Declaration）
```yaml
AgenticDSL `/__meta__/resources`
type: resource_declare
resources:
  - type: tool
    name: web_search
    scope: read_only
  - type: runtime
    name: python3
    allow_imports: [json, sympy]
  - type: network
    outbound:
      domains: ["api.mathsolver.com"]
  - type: memory
    backends: [kg, vector]
  - type: knowledge_graph
    capabilities:
      - multi_hop_query
      - evidence_path_extraction
      - subgraph_write
  - type: generate_subgraph
    max_depth: 2
  - type: tool
    name: image_generator
    scope: write
    capabilities: [text_to_image, high_res]
    rate_limit: "5/min"
  - type: reasoning
    capabilities:
      - text_generation
      - structured_generate
      - kv_continuation
      - stream_output
      - speculative_decode
  - type: tool
    name: native_inference_core
    scope: internal
    capabilities: [tokenize, kv_alloc, model_step, compile_grammar, stream_until]
```

**路径固定**：必须为 `/__meta__/resources`  
**非执行性**：不参与 DAG 执行流，不计 `max_nodes`，无 `next` 字段  
**启动时验证**：执行器在 DAG 启动前一次性验证所有声明资源  
**验证失败**：立即终止，返回错误码 `ERR_RESOURCE_UNAVAILABLE`  
**与权限联动**：声明的资源自动成为后续节点权限检查的上下文依据  

**资源类型定义**：
| 类型 | 字段 | 示例 |
|------|------|------|
| tool | name, scope, capabilities, rate_limit | image_generator, ["text_to_image"], "5/min", web_search, read_only |
| runtime | name, allow_imports | python3, [json, re] |
| network | outbound.domains | ["api.example.com"] |
| memory | backends | [kg, vector, profile] |
| knowledge_graph | capabilities | [multi_hop_query, evidence_path_extraction] |
| generate_subgraph | max_depth | 2 |
| reasoning | capabilities | [text_generation, structured_generate, kv_continuation] |
| native_inference_core | capabilities | [tokenize, kv_alloc, model_step] |

**语义规则**：
- **能力声明**：声明所需能力（如 `evidence_path_extraction`），而非具体实现
- **非强制绑定**：`backend_hint` 仅作为优化提示，执行器可选择任意满足能力的后端
- **权限映射**：`reasoning` 能力声明必须与 `llm_call` 字段支持明确对应：
  - `structured_generate` → `output_schema`
  - `kv_continuation` → `kv_handle`
  - `stream_output` → `stop_condition`
  - `speculative_decode` → `draft_model`, `max_speculative_tokens`
- **降级机制**：若未声明所需能力，执行器应尝试使用基础三元组查询（`query_latest`），若完全不支持，返回 `ERR_UNSUPPORTED_CAPABILITY`

## 七、安全与工程保障

### 7.1 标准库契约强制
- 启动时预加载并校验所有 `/lib/**`
- LLM 生成时 `available_subgraphs` 必须含 `signature`
- 任何尝试写入 `/lib/**` 的行为立即终止（`ERR_NAMESPACE_VIOLATION`）

### 7.2 权限与沙箱
**权限格式**为结构化对象：
```yaml
permissions:
  - tool: web_search → scope: read_only
  - runtime: python3 → allow_imports: [json, re]
  - network: outbound → domains: ["api.example.com"]
  - generate_subgraph: { max_depth: 2 }
```

**权限组合规则**：
- **交集原则**：节点权限 ∩ 父上下文授权权限
- **拒绝优先**：任一缺失 → 跳转 `on_error`
- **权限降级**：子图调用时权限只能减少
- **资源声明是权限的前置契约**：执行器在启动时验证 `/__meta__/resources` 中声明的资源可用性后，才允许执行声明了对应 `permissions` 的节点

**推理权限类型**：
| 权限 | 说明 | 最小权限范围 |
|------|------|------------|
| reasoning: llm_generate | 基础文本生成 | 仅限 `llm_call` 调用 |
| reasoning: structured_generate | 结构化输出（需 `output_schema`） | 同上 |
| reasoning: stream_output | 流式终止（需 `stop_condition`） | 同上 |
| reasoning: speculative_decode | 推测解码 | 同上 |

### 7.3 可观测性（Trace Schema）
兼容 OpenTelemetry，记录：执行状态、上下文变更、输出匹配、LLM 意图、预算快照

**通用 Trace 结构**：
```json
{
  "node_id": "node-123",
  "node_type": "llm_call",
  "timestamp": "2025-11-10T08:30:00Z",
  "status": "success",
  "latency_ms": 450,
  "context_snapshot": { /* 变更前后对比 */ },
  "budget_snapshot": {
    "nodes_left": 15,
    "depth_left": 1
  }
}
```

**推理证据 Trace 扩展**：
```json
{
  "reasoning_evidence": {
    "type": "graph_based",
    "evidence_type": "path_based",
    "paths": [
      [
        { "head": "Beijing", "relation": "capital_of", "tail": "China" },
        { "head": "China", "relation": "located_in", "tail": "Asia" }
      ]
    ],
    "confidence_scores": [0.94, 0.87],
    "backend_used": "gfm-retriever-v1",
    "subgraph_id": "sg-20251103-abc"
  }
}
```

**记忆操作 Trace 扩展**：
```json
{
  "memory_op_type": "state_set | kg_write | vector_store | profile_update",
  "memory_key": "travel.departure_date",
  "backend_used": "context | graphiti | qdrant | mem0",
  "latency_ms": 12,
  "user_id": "user_123"
}
```

**对话节点 Trace**：
```json
{
  "conversation": {
    "topic_id": "booking",
    "role_id": "agent",
    "turn": 3
  }
}
```

**记录规则**：
- 仅当调用图原生接口时记录
- 所有字段均为可选，执行器按能力填充
- `backend_used` 必须记录实际使用的后端标识，便于调试

### 7.4 标准库版本与依赖管理
- **路径支持语义化版本**：`/lib/...@v1`
- **子图可声明依赖**：`requires: - lib: "/lib/reasoning/...@^1.0"`
- **执行器启动时解析依赖图**，拒绝循环或缺失依赖
- **签名变更策略**：
  - `stable` 子图仅可增加字段，不可删除/修改类型
  - 签名变更需提升主版本号
- **小版本升级**（3.x → 3.y）保证向后兼容

### 7.5 归档与签名强制
- `archive_to("/lib/...")` 必须附带有效 `signature`，否则拒绝归档（`ERR_SIGNATURE_REQUIRED`）
- 归档目标路径必须符合命名空间规则
- 归档操作需记录完整 Trace，包括源子图ID、操作者、时间戳

## 八、核心能力规范

### 8.1 动态 DAG 执行 + 全局预算
**DAG 启动流程**：解析 → 验证资源 → 验证签名 → 检查入口 → 启动调度器

**`execution_budget`**：`max_nodes`, `max_subgraph_depth`, `max_duration_sec`  
**超限** → 跳转 `/__system__/budget_exceeded`  
**终止条件**：队列空 + 无活跃生成 + 无待合并子图 + 预算未超

### 8.2 动态子图生成
- LLM 必须输出 `### AgenticDSL '/dynamic/...'` 块
- 新子图可被后续节点通过 `next: "/dynamic/plan_123"` 调用
- **禁止行为**：LLM 生成的子图不得包含 `/lib/**` 写入或调用未声明工具
- 动态子图必须通过运行时权限检查

### 8.3 并发与依赖表达
- `wait_for` 支持 `any_of` / `all_of`
- 支持动态依赖：`wait_for: "{{ dynamic_branches }}"`
- **依赖解析时机**：节点入调度队列前
- **禁止**：在执行中动态变更依赖拓扑

### 8.4 自进化控制
```yaml
on_success: archive_to("/lib/solved/{{ problem_type }}@v1")
```
- 成功 DAG 自动存入图库
- **归档目标可为任意路径，但仅 `/lib/**` 被视为标准库**
- 归档必须提供有效签名

### 8.5 开发模式
```yaml
mode: dev | prod
```

- **`dev`**：`signature_validation: warn`，允许 `last_write_wins`，含上下文快照
- **`prod`**（默认）：强制 `strict`，禁用 `last_write_wins`，最小权限沙箱启用
- **Trace 增强**：`dev` 模式下包含快照信息（若 budget 允许）

### 8.6 性能边界指南
- **上下文大小**：<1MB（>512KB 启用快照压缩）
- **单子图节点数**：<50
- **预算建议**：`max_nodes: 10 × [预期分支数]`，`max_subgraph_depth: 3`
- **记忆操作**：单次查询响应时间 <100ms

### 8.7 Context 快照机制
```yaml
type: assign
assign:
  expr: "{{ $.ctx_snapshots['/main/step3'] }}"  # ✅ 静态键
  path: ""
```

⚠️ **安全限制**：`$.ctx_snapshots` 的访问键必须为静态字符串，禁止动态计算（如 `{{ $.key }}`）

## 九、LLM 生成指令
> 你是一个推理与行动架构师，你的任务是生成可执行、可验证的动态 DAG，包含：
> - 行动流：调用工具、与人协作
> - 思维流：假设 → 计算 → 验证
> 
> 你必须：
> 1. 输出一个或多个 `### AgenticDSL '/path'` 块
> 2. 遵守预算：递归深度 ≤ `{{ budget.subgraph_depth_left }}`
> 3. 优先调用标准库（清单含 `signature`）
> 4. 所有 LLM 调用必须包含 `seed` 与 `temperature`
> 5. 优先调用 `/lib/dslgraph/generate@v1` 生成新子图
> 
> 可用库清单（含契约）：
> {% for lib in available_subgraphs %}
> - {{ lib.path }} (v{{ lib.version }}): {{ lib.description }}
>   Inputs: {{ lib.signature.inputs | map(attr='name') | join(', ') }}
>   Outputs: {{ lib.signature.outputs | map(attr='name') | join(', ') }}
> {% endfor %}
> 
> 当前上下文：
> - 已执行节点：`{{ execution_context.executed_nodes }}`
> - 任务目标：`{{ execution_context.task_goal }}`
> - 执行预算剩余：`nodes: {{ budget.nodes_left }}, depth: {{ budget.subgraph_depth_left }}`
> - （训练模式）期望输出：`{{ expected_output }}`
> - 可用资源声明：`{{ available_resources }}`

## 十、标准原语层

### 10.1 子图管理（`/lib/dslgraph/**`）
- `/lib/dslgraph/generate@v1`（stable）

### 10.2 推理原语（`/lib/reasoning/**`）
- `/lib/reasoning/hypothesize_and_verify@v1`
- `/lib/reasoning/stepwise_assert@v1`
- `/lib/reasoning/counterfactual_compare@v1`（experimental）
- `/lib/reasoning/try_catch@v1`
- `/lib/reasoning/induce_and_archive@v1`
- `/lib/reasoning/graph_guided_hypothesize@v1`（experimental）
- `/lib/reasoning/iper_loop@v1`
- `/lib/reasoning/generate_text@v1`
- `/lib/reasoning/structured_generate@v1`
- `/lib/reasoning/continue_from_kv@v1`
- `/lib/reasoning/stream_until@v1`
- `/lib/reasoning/speculative_decode@v1`（experimental）
- `/lib/reasoning/fallback_text@v1`
- `/lib/reasoning/fallback_structured@v1`

### 10.3 内存记忆原语（`/lib/memory/**`）
- `/lib/memory/state/set@v1`
- `/lib/memory/state/get_latest@v1`
- `/lib/memory/kg/query_subgraph@v1`
- `/lib/memory/kg/write_subgraph@v1`
- `/lib/memory/vector/store@v1`
- `/lib/memory/vector/recall@v1`
- `/lib/memory/profile/update@v1`
- `/lib/memory/profile/get@v1`

**权限模型**：
- `/lib/memory/state/set@v1`：`memory: state_write`
- `/lib/memory/kg/query_subgraph@v1`：`kg: subgraph_query`
- `/lib/memory/kg/write_subgraph@v1`：`kg: subgraph_write`
- `/lib/memory/vector/store@v1`：`vector: store`
- `/lib/memory/vector/recall@v1`：`vector: recall`
- `/lib/memory/profile/update@v1`：`profile: update`

**工具注册要求**：
| 工具名 | 输入 | 输出 | 参考实现 |
|--------|------|------|----------|
| vector_store | text, metadata | success | Pinecone/Qdrant |
| vector_recall | query, top_k, filter | memories | Pinecone/Qdrant |
| profile_update | user_id, attributes | success | Redis/MongoDB |

### 10.4 对话协议（`/lib/conversation/**`）
- `/lib/conversation/start_topic@v1`（stable）
- `/lib/conversation/switch_role@v1`（stable）
- `/lib/conversation/meeting@v1`（stable）

**对话上下文模型**（10.4.1）：
- 每个话题拥有独立上下文路径：`/topics/{topic_id}/context`
- 角色切换更新 `conversation.current_role`
- 会议协调器管理多角色状态同步
- 预算控制：`max_conversation_turns`、`max_topics`、`max_roles`

### 10.5 工作流原语（`/lib/workflow/**`）
- `/lib/workflow/parallel_map@v1`（experimental）

### 10.6 世界模型及环境感知原语
*待定义：AgenticDSL 感知物理世界的原语*

### 10.7 资源工具
- `/lib/tool/list_available@v1`：动态查询当前可用工具及其能力标签，供 LLM 规划使用

## 附录 A：应用组织模型（工程推荐）

### A.1 应用目录结构推荐
```
my_project/
├── app/
│   └── my_robot/
│       ├── main.agent.md        # entry_point: "/app/my_robot/main"
│       └── private_utils.agent.md
├── lib/
│   └── workflow/
│       └── navigation/
│           └── path_planner@v1.agent.md
└── README.md
```

### A.2 演进路径：从私有到共享
1. **开发阶段**：逻辑置于 `/app/<AppName>/xxx`
2. **验证成功**：通过 `iper_loop` 或人工确认效果
3. **归档发布**：调用 `archive_to("/lib/workflow/...@v1")`
4. **复用阶段**：其他应用通过 `next: "/lib/workflow/...@v1"` 调用

**注意**：`/app/**` 在 DSL 层面与 `/main/**` 语义等价，规范强制要求执行器支持该路径。

## 附录 B：错误码
| 错误码 | 含义 |
|--------|------|
| ERR_MISSING_ENTRY_POINT | 未声明 entry_point |
| ERR_NAMESPACE_VIOLATION | 违反命名空间写规则 |
| ERR_CTX_MERGE_CONFLICT | 上下文合并冲突 |
| ERR_RESOURCE_UNAVAILABLE | 资源声明验证失败 |
| ERR_UNSUPPORTED_CAPABILITY | 请求的能力未被支持 |
| ERR_SIGNATURE_VIOLATION | 子图签名验证失败 |
| ERR_BUDGET_EXCEEDED | 超出执行预算（节点数、深度或时间） |
| ERR_SIGNATURE_REQUIRED | 归档至 `/lib/**` 时缺少签名 |

## 附录 C：核心标准库清单
以下子图为强制实现的核心标准库（执行器必须内置）：

### C.1 子图管理
- `/lib/dslgraph/generate@v1`

### C.2 推理原语
- `/lib/reasoning/generate_text@v1`
- `/lib/reasoning/structured_generate@v1`
- `/lib/reasoning/try_catch@v1`
- `/lib/reasoning/hypothesize_and_verify@v1`

### C.3 内存记忆原语
- `/lib/memory/state/set@v1`
- `/lib/memory/state/get_latest@v1`
- `/lib/memory/kg/query_subgraph@v1`
- `/lib/memory/vector/recall@v1`

### C.4 对话协议
- `/lib/conversation/start_topic@v1`
- `/lib/conversation/switch_role@v1`

## 附录 E：最佳实践与约定

### E.1 时间上下文约定（非强制）
- `$.now`: ISO8601 当前时间（由执行器注入）
- `$.time_anchor`: 任务参考时间点
- `$.timeline[]`: `{ts: "...", event: "...", source: "..."}`

### E.2 禁止行为清单
- 在 DAG 内实现异步回调
- 在叶子节点中编码高层推理逻辑
- 使用 `generate_subgraph` 调用已有子图
- 输出非 `### AgenticDSL` 块的 LLM 内容
- 在生产模式下使用 `last_write_wins` 合并策略
- 在知识应用层直接使用 `llm_generate_dsl`
- 在 `/lib/dslgraph/**` 之外实现子图生成逻辑

### E.3 推荐开发工作流
1. `agentic validate example.agent.md`
2. `agentic simulate --mode=dev`
3. 从 Trace 提取失败案例，更新 `expected_output`
4. 通过 `archive_to` 沉淀验证通过模块
5. 生产部署必须显式设置 `mode: prod`

### E.4 资源声明最佳实践
- 所有对外部能力的依赖（工具、运行时、网络）应在 `/__meta__/resources` 中显式声明
- 避免在 `generate_subgraph` 生成的子图中使用未声明资源
- 生产环境必须完整声明资源，开发环境可适当放宽（但不推荐）

## 附录 F：记忆原语演进路线
- **6 个核心子图**（`set`, `get_latest`, `store`, `recall`, `update`, `get`）
- **实验性**：
  - `/lib/memory/orchestrator/hybrid_recall@v1`（融合结构化+语义）
  - 支持记忆 TTL（`assign` + `$.now` + 过期策略）
  - 多模态记忆存储（图像、音频、视频）

## 附录 G：适配层参考实现指南
*本附录仅提供参考实现模式，不强制要求。执行器可自由选择实现细节，只要符合接口契约。*

### G.1 工具适配器示例
```python
# 参考伪代码
class ToolAdapter:
    def __init__(self, tool_name, schema):
        self.tool_name = tool_name
        self.schema = schema  # 符合 tool_schema 规范
        
    def validate_input(self, args):
        # 使用 JSON Schema 验证
        pass
        
    def execute(self, args, permissions):
        # 权限检查
        if not self.check_permissions(permissions):
            raise PermissionError(f"Missing permissions for {self.tool_name}")
            
        # 执行工具
        result = self._tool_impl(args)
        
        # 生成 Trace
        trace = {
            "tool_name": self.tool_name,
            "latency_ms": time.time() - start_time,
            "backend_used": self.backend_id
        }
        
        return result, trace
```

### G.2 C++ 推理核心集成点
- **KV 缓存管理**：通过 `native_inference_core.kv_alloc` 与 `llm_call.kv_handle`
- **语法约束**：通过 `native_inference_core.compile_grammar` 与 `llm_call.output_schema`
- **流式处理**：通过 `native_inference_core.stream_until` 与 `llm_call.stop_condition`
- **执行器必须提供 C API**，允许推理核心注册能力（如 `register_capability("kv_continuation")`）

---

**AgenticDSL v3.9+ 是 AI-操作系统和推理能力标准化的关键一步**。  
通过 **三层抽象 + 对话协议标准化 + Core SDK 契约化**，  
**契约化推理原语 + 安全 `llm_call` + 资源声明联动**，  
为构建 **可靠、可协作、可进化的智能体生态** 提供工业级工程基石。

**发布计划**：2025 Q4 开源参考执行器 + 对话子图参考实现