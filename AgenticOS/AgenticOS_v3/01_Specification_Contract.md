# 01_Specification_&_Contract.md

> **文档版本**: v1.0  
> **对应 DSL 规范**: AgenticDSL v3.10-PE (Parallel Edition)  
> **对应协议版本**: WebSocket v2.1  
> **对应引擎版本**: LocalAI Core v2.1-P0+  
> **文档状态**: Phase 1.1 基线冻结（冻结后代码可迭代，契约不可变）  
> **目标读者**: DSL 作者、前端开发者、系统集成商  
> **关键约束**: 本文档定义外部稳定契约，实现细节请参考 `02_Architecture_&_Runtime.md`

---

## 文档摘要

| 项目 | 内容 |
|------|------|
| **核心定位** | 定义 LocalAI × AgenticDSL 系统的对外稳定契约，确保 DSL 作者、前端开发者与引擎实现者的共识 |
| **关键演进** | 引入 Branch 并行执行模型、L0-L2 沙箱分级体系、ExecutionInstance 全局标识 |
| **兼容性承诺** | 协议 v2.1 保证向后兼容至引擎 v2.0；DSL v3.10-PE 完全兼容 v3.9 语法，新增特性为可选扩展 |
| **安全边界** | 明确 L0-L2 沙箱能力边界，L3 作为预留扩展点（当前未实现） |
| **P0 红线** | 协议握手强制、线程安全约束、Agent 单实例单会话 |

---

## 1. AgenticDSL 语言规范（v3.10-PE）

### 1.1 核心概念与术语

#### 1.1.1 执行实体层级

| 术语 | 英文标识 | 定义 | 作用域 | 生命周期 |
|------|----------|------|--------|----------|
| **会话** | `session_id` | 用户级对话上下文，持久化存储，支持多轮对话 | 用户级 | TTL 管理（默认 30min） |
| **执行实例** | `execution_instance_id` | 单次 DSL 执行的完整运行时上下文，全局唯一标识（格式 `exec_{layer}_{uuid}`） | 全局 | `run()` 开始 → 结果返回 |
| **分支** | `branch_id` | DAG 内的轻量级并行执行单元，拥有独立 COW 上下文与沙箱级别 | Session 内 | Fork 创建 → Join 合并 |
| **资源实例** | `resource_id` | AgentPool 中的推理资源实例（LLM/SD/Whisper），受单实例单会话约束 | AgentPool 内 | 获取 → 释放 |

**层级关系**:
```
Session (1)
├── ExecutionInstance N (1:N)
│   ├── Branch M (1:N，Fork/Join 创建)
│   └── BudgetController (实例级预算)
└── Persistent State (SQLite WAL)

AgentPool (全局)
└── LLMResource (1:1 绑定 ExecutionInstance，通过 occupied_ 标记)
```

#### 1.1.2 命名空间规范

| 路径前缀 | 用途 | 可写入 | 签名要求 | 默认沙箱级别 | 持久化 |
|----------|------|--------|----------|--------------|--------|
| `/lib/**` | 标准库（只读） | ❌ | ✅ 强制 | L0 | 引擎内置 |
| `/dynamic/**` | 运行时生成子图 | ✅ | ⚠️ 可选 | L1 | 会话级 |
| `/main/**` | 主流程入口 | ✅ | ❌ | L0 | 可选 |
| `/app/**` | 工程别名（语义等价 `/main/**`） | ✅ | ❌ | L0 | 可选 |
| `/__meta__` | 元信息声明 | ✅（解析阶段） | N/A | N/A | N/A |

**约束**:
- 尝试写入 `/lib/**` → 错误码 `0x2004` (DSL_NAMESPACE_VIOLATION)
- `/dynamic/**` 路径自动生成，禁止手动指定为 `/lib` 或 `/main` 子路径

### 1.2 程序结构规范

#### 1.2.1 元信息块（`/__meta__`）

```yaml
### AgenticDSL `/__meta__`
version: "3.10-PE"
mode: dev  # dev | prod
entry_point: "/main/start"  # 必需，指向 DAG 入口节点
execution_budget:
  max_nodes: 20              # 本实例最大节点执行数
  max_llm_calls: 10          # LLM 调用次数上限
  max_subgraph_depth: 2      # 动态生成深度上限
  max_duration_sec: 60       # 执行时间上限（秒）
  max_branches: 10           # 最大并发 Branch 数（v3.10-PE 新增）
context_merge_policy: "error_on_conflict"  # 默认合并策略
```

**字段约束**:
- `entry_point` 必须指向文档中已定义的子图路径
- `mode: prod` 时强制禁用 `last_write_wins` 合并策略
- `max_branches` 限制单个 ExecutionInstance 内的并发 Branch 数

#### 1.2.2 资源声明块（`/__meta__/resources`）

```yaml
### AgenticDSL `/__meta__/resources`
type: resource_declare
resources:
  - type: reasoning
    capabilities: [structured_generate, kv_continuation]
  - type: tool
    name: web_search
    scope: read_only
  - type: sandbox
    max_level: L2           # 本会话可能使用的最高沙箱级别
    l2_pool_size: 10        # 可选：L2 进程池预热提示
permissions:
  - reasoning: llm_generate
  - tool: web_search
```

**语义**:
- 声明的资源在执行前验证可用性，失败返回 `0x4001` (SYS_POOL_EXHAUSTED) 或 `0x3001` (AUTH_PERMISSION_DENIED)
- `sandbox.max_level` 限制本会话可使用的最高沙箱级别（L0/L1/L2），防止未预期的 L2 开销

### 1.3 节点类型规范

#### 1.3.1 通用字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `type` | string | ✅ | 节点类型 |
| `next` | string \| list | ❌ | 后继节点路径（支持 `@v1` 版本语法） |
| `permissions` | list | ❌ | 权限声明列表（与 `/__meta__/resources` 交集检查） |
| `sandbox_level` | enum | ❌ | 覆盖默认沙箱级别（L0/L1/L2） |
| `context_merge_policy` | object | ❌ | 字段级合并策略覆盖 |
| `on_success` | string | ❌ | 成功后动作（如 `archive_to("/lib/...")`） |
| `on_error` | string | ❌ | 错误跳转路径（未定义则终止当前子图） |
| `expected_output` | object | ❌ | 期望输出（用于验证/训练） |

#### 1.3.2 执行原语节点

**`assign`** - 安全赋值
```yaml
type: assign
assign:
  key1: "literal_value"
  key2: "{{ $.input | upper }}"  # Inja 模板
  nested.key: "{{ length(items) }}"
next: "/main/next"
```
- 多字段并发赋值，冲突遵循 `context_merge_policy`
- 支持嵌套路径（`.` 分隔）

**`dsl_call`**（v3.10-PE）- 统一推理调用（支持多模态）

```yaml
type: dsl_call
# 模态声明：text | image | audio | video | structured_data
# 默认为 text，向后兼容 v3.9 纯文本调用
modality: text

# 多模态输入内容（modality != text 时必需）
content_parts:
  - type: text
	text: "分析 {{ $.data }} 并总结"
  - type: image_url
    image_url:
      path: "{{ $.input_image }}"      # 支持 Inja 模板引用上下文变量
      detail: high | low | auto        # 图像质量提示（ vision 模型用）
  - type: audio
    audio:
      path: "{{ $.input_audio }}"
      format: wav | mp3 | webm

# 输出配置
output_modality: text                 # 期望输出模态
output_keys: ["analysis_result"]      # 输出存储的上下文键

# 工具链（跨模态转换时使用，如 "图→文→图" 复杂流水线）
# 单模态推理可省略，直接使用默认工具
tool_chain: ["vision_encode", "reasoning", "decode"]

# 标准 LLM 参数（复用现有）
llm_tool_name: "multimodal-7b"        # AgentPool 注册的多模态工具名
llm_params:
  temperature: 0.7
  max_tokens: 512
  seed: 42

sandbox_level: L0                     # 多模态推理强制 L0（需 GPU 访问）
next: "/main/process_result"
```

**执行语义**：
- 单模态（text）：等效于原 `prompt_template` 模式
- 多模态：引擎根据 `content_parts` 组装输入，通过 `AgentPool` 获取对应模态资源
- 跨模态：若声明 `tool_chain`，引擎按序调用工具链完成模态转换
- **关键约束**：多模态推理禁止在 L2 沙箱执行（GPU 资源必须在 L0/L1 访问）
- **关键约束**: `dsl_call` 禁止在 L2 沙箱内执行（L2 用于用户代码隔离，LLM 推理必须在 L0/L1）
- 执行时通过 `AgentPool` 获取 `LLMResource`，受 `occupied_` 单实例单会话约束

**`multimodal_call`** - 显式跨模态调用
当需要原子性跨模态转换（如"根据音频生成配图"）且逻辑复杂时，使用此节点替代 `dsl_call`：

```yaml
type: multimodal_call
# 定义输入模态组合
input_modality: [audio, text]         # 支持多输入模态
input_context_keys: 
  audio: "$.user_voice"
  text: "$.generation_prompt"

# 定义输出模态组合  
output_modality: [image, text]
output_mapping:
  image: "$.generated_illustration"   # 映射到上下文路径
  text: "$.image_caption"

# 工具链声明（强制）
tool_chain: ["whisper_transcribe", "sd_generate", "caption_generate"]

sandbox_level: L0
next: "/main/display"
```

**与 `dsl_call` 的区别**：
- `dsl_call`：**单模态为主**，支持内容混合（content_parts），适合大多数场景
- `multimodal_call`：**多进多出**，强制工具链声明，适合复杂 AIGC 流水线

**`tool_call`** - 工具调用
```yaml
type: tool_call
tool: python_executor
arguments:
  code: "{{ $.generated_code }}"
sandbox_level: L2              # 高风险工具强制 L2
output_keys: ["result"]
```
- 工具可声明默认沙箱级别，高风险操作自动升级 L2
- L2 沙箱内执行通过 IPC 回传结果，禁止直接访问 AgentPool

**`generate_subgraph`** - 动态子图生成
```yaml
type: generate_subgraph
prompt_template: "生成求解方程 {{ $.expr }} 的 DAG"
output_keys: ["new_graph_path"]
signature_validation: warn     # strict | warn | ignore
namespace_prefix: "/dynamic/solution_{{ $.instance_id }}"
next: "/dynamic/solution_{{ $.instance_id }}/start"
```
- 生成路径必须位于 `/dynamic/**`，前缀自动附加
- 新子图通过当前 ExecutionInstance 的动态图注入机制注册
- 遵守 `execution_budget.max_subgraph_depth`

**`fork` / `join`** - 并行控制

*Fork 节点*:
```yaml
type: fork
branches:
  - "/main/strategy_a"
  - "/main/strategy_b"
mode: parallel                 # parallel | speculative | ensemble
options:
  speculative_validator: "{{ $.confidence > 0.9 }}"
  ensemble_aggregator: "majority_vote"
  fail_fast: false             # 任一分支失败是否立即终止
```

*Join 节点*:
```yaml
type: join
wait_for: ["@all"]             # @all | @any | [id1, id2]
merge_strategy: "error_on_conflict"
field_policies:
  "results": "array_concat"
  "best_score": "last_write_wins"
timeout_sec: 30
```

**执行语义**:
- **Fork**: 创建 N 个 Branch，每个拥有独立 COW 上下文（写时复制）
- **并行模式**: 所有 Branch 提交到 `BranchExecutor` 并发执行
- **推测模式**: 多 Branch 执行同一任务，首个满足 `validator` 的结果立即返回，取消其他
- **集成模式**: 多 Branch 执行不同策略，结果按 `aggregator` 合并
- **Join**: 等待条件满足后，按策略合并各 Branch 上下文

**`assert`** - 条件验证
```yaml
type: assert
condition: "{{ len($.roots) == 1 }}"
on_failure: "/main/recovery"
```

**`end`** - 子图终止
```yaml
type: end
metadata:
  termination_mode: hard       # hard: 终止 DAG；soft: 返回父上下文
output_keys: ["result"]        # soft 模式下合并到父上下文的字段
```

### 1.4 上下文与合并策略

#### 1.4.1 上下文模型
全局可变字典，支持嵌套路径。特殊变量：
- `$.now`: ISO 8601 当前时间
- `$.instance_id`: 当前 ExecutionInstance ID
- `$.branch_id`: 当前 Branch ID（Fork 后有效）
- `$.ctx_snapshots['/path']`: 访问指定节点快照（静态键，禁止动态计算）

#### 1.4.2 合并策略（v3.10-PE 标准）

| 策略 | 行为 | 适用场景 |
|------|------|----------|
| `error_on_conflict`（默认） | 字段在多个 Branch 中被写入 → 报错 | 严格一致性 |
| `last_write_wins` | 以最后完成 Branch 的值为准 | 幂等操作（仅 dev 模式） |
| `deep_merge` | 递归合并对象；数组完全替换；标量覆盖 | 对象属性合并 |
| `array_concat` | 数组拼接（保留顺序） | 收集多 Branch 结果 |
| `array_merge_unique` | 数组拼接 + 去重 | 去重收集 |

**策略继承链**: 节点级 `field_policies` > 子图级 `context_merge_policy` > 全局默认


#### 1.4.3 多模态内容格式（v3.10-PE）

当 `dsl_call` 或 `multimodal_call` 处理非文本内容时，上下文中的数据格式遵循以下规范：

```yaml
# 标准 content_parts 存储格式（兼容 OpenAI / Anthropic API 规范）
$.content_parts:
  - type: text
    text: "用户查询文本"
  - type: image
    image:
      # 方案 A：base64 内联（小图 < 100KB）
      data: "iVBORw0KGgoAAAANSUhEUgAA..."
      mime_type: "image/png"
      # 方案 B：文件路径引用（大图，推荐）
      path: "/tmp/agentic_os/img_123.png"
      # 元数据
      detail: high
      size: [1024, 768]
  - type: audio
    audio:
      path: "/tmp/agentic_os/audio_456.wav"
      format: wav
      duration_sec: 15.5
      sample_rate: 16000
```  

### 1.5 预算控制

```yaml
execution_budget:
  max_nodes: 20
  max_llm_calls: 10
  max_subgraph_depth: 2
  max_duration_sec: 60
  max_branches: 10
```

**预算层级**: Session Budget ≥ Instance Budget ≥ Branch Budget  
**超限行为**: 跳转至 `/__system__/budget_exceeded` 节点，返回错误码 `0x2003`

---

## 2. 通信协议规范（WebSocket v2.1）

### 2.1 连接与路径

**强制绑定**: 引擎强制绑定 `127.0.0.1`，远程访问必须通过 SSH 隧道  
**路径定义**:

| 路径 | 功能 | 消息方向 | 沙箱关联 |
|------|------|----------|----------|
| `/stream` | DSL 驱动推理流（主通道） | 双向 | L0/L1（LLM 推理） |
| `/pty` | 终端代理（跨平台 PTY） | 双向 | L2（用户终端） |
| `/debug` | 执行控制（pause/resume/inject） | 双向 | L0（调试接口） |
| `/config` | 布局与配置管理 | 双向 | L0 |
| `/trace` | Trace 事件订阅（Server-Sent 风格） | 服务端推送 | L0 |

### 2.2 协议握手（P0 强制）

**握手流程**:
1. 客户端连接后立即发送 `handshake` 消息
2. 服务端验证 `version` 兼容性
3. 协商背压参数与能力集
4. 握手失败立即断开（code 1008）

**握手消息**:
```json
// 客户端 → 服务端
{
  "type": "handshake",
  "version": "2.1",
  "capabilities": [
    "backpressure:configurable",
    "multimodal",
    "branch:parallel",
    "sandbox:l2"
  ],
  "backpressure": {
    "ack_batch_size": 20,
    "transport_high_water": 2097152,
    "app_high_water": 100
  }
}

// 服务端 → 客户端（成功）
{
  "type": "handshake_ack",
  "version": "2.1",
  "negotiated": {
    "ack_batch_size": 20,
    "sandbox_max_level": "L2",
    "branch_concurrency": 10
  }
}

// 服务端 → 客户端（失败）
{
  "type": "error",
  "error": {
    "code": "0x0002",
    "message": "Protocol version mismatch: expected 2.1, got 2.0"
  }
}
```

**P0 红线**: 未收到 `handshake_ack` 前发送业务消息 → 服务端立即断开（code 1008）

### 2.3 应用层消息格式

**推理请求**:
```json
{
  "type": "completion",
  "session_id": "sess_abc123",
  "execution_context": {
    "instance_id": "exec_l2_uuid789",
    "branch_id": "branch_001"
  },
  "dsl_entry": "/main/start",
  "prompt": "用户输入",
  "parameters": {
    "temperature": 0.7,
    "max_tokens": 512
  },
  "backpressure": {
    "ack_batch_size": 20
  }
}
```

**Token 流响应**:
```json
{
  "type": "chunk",
  "instance_id": "exec_l2_uuid789",
  "branch_id": "branch_001",
  "delta": "生成的 token",
  "object": "chat.completion.chunk",
  "budget": {
    "nodes_left": 15,
    "branches_active": 3
  }
}
```

**ACK 确认（应用层背压）**:
```json
{
  "type": "ack",
  "count": 20,
  "instance_id": "exec_l2_uuid789"
}
```

**错误响应**:
```json
{
  "type": "error",
  "error": {
    "code": "0x5001",
    "message": "Agent pool exhausted",
    "actionable": true,
    "suggestion": "Reduce concurrent branches or increase --max-llm-agents"
  }
}
```

### 2.4 双层背压机制

**传输层背压**（uWebSockets 原生）:
- 监测 `ws->getBufferedAmount()`
- 高水位（默认 1MB）时暂停发送，低水位恢复

**应用层背压**（ACK 驱动）:
- 服务端维护 `pending_tokens` 计数
- 客户端按 `ack_batch_size`（默认 10）批量确认
- 达到 `app_high_water`（默认 50）时挂起生成

**线程安全**: 所有 `ws->send()` 必须通过 `uWS::Loop::defer()` 抛回主线程执行（P0 强制）

---

## 3. 安全与隔离契约

### 3.1 三级沙箱体系（L0-L2）

| 级别 | 技术实现 | 启动延迟 | 适用场景 | 资源访问 | LLM 推理 |
|------|---------|---------|---------|----------|----------|
| **L0** | 直接函数调用（同进程） | ~0μs | 标准库 `/lib/**`、内部工具 | 直接访问 | ✅ 允许 |
| **L1** | Seccomp-BPF + Cgroups | ~1ms | API 调用、文件操作 | 过滤系统调用 | ✅ 允许 |
| **L2** | Clone Namespace + OverlayFS | ~50ms（预热 ~5ms） | 用户代码、第三方工具 | 完全隔离（IPC 通信） | ❌ 禁止 |

**L3 预留**: 作为未来 VM 级隔离扩展点，当前规范保留枚举值但不实现

### 3.2 沙箱级别选择规则

**默认映射**:
- `/lib/**`: 强制 L0
- `/main/**`, `/app/**`: 默认 L0，可通过节点级 `sandbox_level` 显式升级
- `/dynamic/**`: 默认 L1，高风险操作自动升级 L2

**动态升级**:
- Branch 执行中可升级 `SandboxLevel`（L0→L1→L2）
- **禁止降级**（安全边界不可逆）
- 升级时保存执行状态，迁移到新的沙箱环境，恢复执行

**关键约束**:
- **L2 沙箱禁止直接访问 AgentPool**: LLM 推理必须在 L0/L1 执行
- **L2 通信机制**: 通过 Unix Domain Socket 与主进程通信，请求 LLM 调用或持久化数据

### 3.3 权限与沙箱联动

**权限声明格式**:
```yaml
permissions:
  - tool: web_search
    scope: read_only
    sandbox_level: L1
  - runtime: python3
    allow_imports: [json, re]
    sandbox_level: L2
  - generate_subgraph:
      max_depth: 2
```

**校验规则**:
- 节点 `permissions` 必须与 `/__meta__/resources` 声明交集非空
- 节点要求的 `sandbox_level` 必须 ≤ 会话声明的 `sandbox.max_level`
- 权限组合遵循**交集原则**（节点 ∩ 子图 ∩ 用户授权）

### 3.4 命名空间与安全边界

**写入约束**:
- 尝试写入 `/lib/**` → `0x2004` (DSL_NAMESPACE_VIOLATION)
- 尝试在 L2 直接访问 SQLite → 被拒绝，必须通过 IPC 调用主进程接口

**路径安全**:
- 文件操作必须通过 `safe_join()` 校验，防止目录遍历（`../` 逃逸）
- 允许路径白名单：`~/.localai`, `~/Documents`（可配置）

---

## 4. 错误码与版本契约

### 4.1 标准错误码空间

| 错误码 | 名称 | 含义 | 前端映射 | 是否可重试 |
|--------|------|------|----------|------------|
| **通用错误** |
| `0x0000` | `UNKNOWN` | 未知错误 | "系统错误，请重试" | ✅ |
| `0x0001` | `BACKPRESSURE_TIMEOUT` | 背压超时 | "网络响应缓慢" | ✅ |
| `0x0002` | `PROTOCOL_VERSION_MISMATCH` | 协议版本不匹配 | "请升级客户端" | ❌ |
| **AI 资源错误** |
| `0x1001` | `AI_OOM` | 显存不足 | "内存不足，请关闭其他应用" | ⚠️（换小模型） |
| `0x1002` | `AI_MODEL_LOAD_FAILED` | 模型加载失败 | "模型文件损坏" | ❌ |
| `0x1003` | `AI_TOOL_UNAVAILABLE` | LLM 工具未注册 | "服务未就绪" | ✅ |
| **DSL 执行错误** |
| `0x2001` | `DSL_PARSE_ERROR` | DSL 解析错误 | "脚本语法错误" | ❌ |
| `0x2002` | `DSL_NODE_EXEC_FAILED` | 节点执行失败 | "执行失败" | ⚠️ |
| `0x2003` | `DSL_BUDGET_EXCEEDED` | 预算超限 | "任务过于复杂，请简化" | ❌ |
| `0x2004` | `DSL_NAMESPACE_VIOLATION` | 命名空间违规 | "权限不足" | ❌ |
| **权限安全错误** |
| `0x3001` | `AUTH_PERMISSION_DENIED` | 权限不足 | "操作被拒绝" | ❌ |
| `0x3002` | `AUTH_PROFILE_VIOLATION` | 用户配置违规 | "超出用户权限" | ❌ |
| **系统资源错误** |
| `0x4001` | `SYS_POOL_EXHAUSTED` | AgentPool 耗尽 | "服务繁忙，请稍后" | ✅ |
| `0x4002` | `SYS_SQLITE_BUSY` | 数据库锁冲突 | "数据保存中，请重试" | ✅ |
| `0x4003` | `SYS_PTY_SPAWN_FAILED` | 终端启动失败 | "终端不支持" | ❌ |
| `0x4004` | `SYS_SANDBOX_ESCAPE` | 沙箱逃逸尝试 | "安全警告" | ❌ |

### 4.2 版本映射与兼容性

**版本矩阵**:

| 文档版本 | DSL 规范 | LocalAI 引擎 | 协议版本 | 沙箱支持 | Branch 并发 | 状态 |
|----------|----------|--------------|----------|----------|-------------|------|
| v1.0 | v3.10-PE | v2.1-P0 | v2.1 | L0-L2 | 顺序模拟（v1.0）/ 真并发（v1.1） | **当前基线** |
| v1.1 | v3.11 | v2.2 | v2.2 | L0-L2（优化） | 真并发 + Speculative | 规划中 |
| v2.0 | v4.0 | v3.0 | v3.0 | L0-L3（VM） | 分布式 | 远期规划 |

**兼容性承诺**:
- 协议 v2.1 保证向后兼容至引擎 v2.0（降级功能）
- DSL v3.10-PE 完全兼容 v3.9 语法（`llm_call` 作为 `dsl_call` 别名保留）
- L2 沙箱接口稳定，v1.0 为基础进程隔离，v1.1 增加 Cgroups v2 支持

---

## 5. 附录

### 5.1 标识符格式规范
| 标识符 | 格式 | 示例 | 生成规则 |
|--------|------|------|----------|
| session_id | `sess_{uuid4}` | `sess_a1b2c3d4` | 客户端首次连接时生成，TTL 30min |
| instance_id | `exec_{layer}_{uuid4}` | `exec_l2_f5e6d7c8` | 层级标识（L1-L4）+ 随机 |
| branch_id | `branch_{parent}_{seq}` | `branch_f5e6_001` | 父 Instance ID 前缀 + 序列号 |
| trace_id | `trace_{timestamp}_{uuid}` | `trace_1709...` | 用于全链路追踪 |

### 5.2 Inja 模板安全子集

**允许**: 变量 (`{{ $.path }}`)、过滤器 (`upper`, `length`, `default`)、条件 (`{% if %}`)、循环 (`{% for %}`)  
**禁止**: `include`, `extends`, 环境变量访问 (`env.`), 任意函数调用

**时间上下文**: `$.now` 由执行器注入，格式 ISO 8601

### 5.3 保留关键字

`session_id`, `instance_id`, `branch_id`, `trace_id`, `execution_context`, `ctx_snapshots`, `now`, `budget`, `permissions`, `sandbox_level`

### 5.4 参考文档索引

- 架构实现: `02_Architecture_&_Runtime.md`
- 工程部署: `03_Engineering_&_Deployment.md`
- 技术速查: `04_Technical_Reference.md`
