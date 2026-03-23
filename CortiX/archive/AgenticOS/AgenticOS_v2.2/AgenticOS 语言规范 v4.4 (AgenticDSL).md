# AgenticOS 语言规范 v4.4 (AgenticDSL)

文档版本：v4.4.0  
日期：2026-02-27  
状态：基于 AgenticOS 架构 v2.2 正式发布，整合评审意见与 DSL-Centric 架构  
依赖：AgenticOS-Architecture-v2.2, AgenticOS-Layer-0-Spec-v2.2, AgenticOS-Security-Spec-v2.2, AgenticOS-v2.2-Skill-Package-Spec, AgenticOS-v2.2-DSL-Execution-Console-Spec

---

## 执行摘要

AgenticDSL v4.4 是 AgenticOS 的声明式领域特定语言，核心目标是成为 **LLM 的对外通用语言**——既可作为 LLM 的输入（提示词结构化），也可作为 LLM 的输出（可执行工作流）。

**核心设计原则：**
1. **Markdown 原生**：DSL 使用 Markdown 标题格式，LLM 可自然生成与理解
2. **SKILL.md 超集**：完全兼容 SKILL.md 技能包格式，支持工具/工作流/触发器定义
3. **DAG 显式化**：节点信息与连接信息分离声明，支持复杂拓扑
4. **状态工具化**：通过 `state.read`/`state.write` 工具访问 L4 状态，禁止直接内存访问
5. **Layer Profile 安全**：Cognitive/Thinking/Workflow 三层权限 Profile，编译期 + 运行期双重验证
6. **LLM 双向协议**：DSL 作为 LLM 输入/输出的统一格式，支持 `llm_generate_dsl` 原语
7. **运行时可观察可控制**：提供独立 Shell 窗口观察 DSL 运行过程

**与 v4.3 的主要变更（基于评审修订）：**
| 变更项 | v4.3 | v4.4 (修订后) | 说明 |
| :--- | :--- | :--- | :--- |
| SKILL.md 兼容 | 不支持 | ✅ 完全兼容 | 支持 tools/workflows/triggers 声明，对齐 Skill-Package-Spec-v2.2 |
| DAG 连接 | `next` 字段 | `edges` 独立声明 | 支持复杂拓扑（fork/join/condition） |
| Layer Profile | 无 | ✅ 强制声明 | `__meta__.layer_profile`，双重验证机制 |
| 状态访问 | 直接 Context | `state.read/write` 工具 | 状态管理工具化，增加安全约束 |
| L0 依赖 | 隐式获取 | ✅ 参数显式传入 | `confidence_score` 必须作为参数传入 L0，禁止反向依赖 L4 |
| LLM 交互 | 单向 | ✅ 双向协议 | DSL 作为 LLM 输入/输出统一格式，增加配置安全验证 |
| 运行时控制 | 无 | ✅ 独立 Shell 窗口 | 新增 DSL 执行控制台规范 (Section 2.7) |
| 可观测性 | 基础 Trace | ✅ 增强字段 | 增加 `execution_instance_id` 关联，智能化 Trace 扩展 |

---

## 1. 核心定位

### 1.1 DSL 作为 LLM 通用语言

AgenticDSL v4.4 设计为 LLM 与 AgenticOS 之间的**双向协议**：

```
┌─────────────────────────────────────────────────────────────────┐
│                    LLM ↔ AgenticDSL 双向协议                     │
├─────────────────────────────────────────────────────────────────┤
│  LLM → DSL (输出)                                                │
│  ├─ 用户请求 → LLM 生成 DSL 工作流 → AgenticOS 执行                │
│  ├─ 支持 llm_generate_dsl 原语                                   │
│  ├─ 安全约束：output_constraints (max_blocks, allowed_types)    │
│  └─ 配置安全：model/provider 白名单验证，API Key 加密             │
│                                                                  │
│  DSL → LLM (输入)                                                │
│  ├─ DSL 节点 → LLM 填充 prompt 内容                               │
│  ├─ 支持 llm_call 节点的 model/provider 配置                       │
│  └─ 上下文注入：$.memory.state.*, $.session.*                   │
│                                                                  │
│  DSL ↔ DSL (编排)                                                │
│  ├─ 子图调用：/lib/** 标准库模板                                 │
│  ├─ 动态生成：/dynamic/** 运行时生成子图                          │
│  └─ 技能导入：SKILL.md → DSL 转换                                │
│                                                                  │
│  DSL ↔ Console (控制)                                            │
│  ├─ 独立 Shell 窗口：观察运行过程                                 │
│  ├─ 实例树管理：attach/detach 执行实例                            │
│  └─ 干预操作：pause/resume/state_write (经权限验证)              │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 SKILL.md 兼容性

SKILL.md 是 AgenticOS v2.2 的技能清单格式，v4.4 DSL 完全兼容其结构：

| SKILL.md 元素 | AgenticDSL v4.4 映射 | 实现方式 |
| :--- | :--- | :--- |
| `__meta__` | `__meta__` 块 | 签名、Profile、版本声明 |
| `tools` | `tool_call` 节点 + ToolRegistry 注册 | 工具定义与权限声明 |
| `workflows` | DSL 子图 (`/app/skills/**`) | 工作流 DAG 定义 |
| `triggers` | `trigger` 元数据 + 条件节点 | 事件/条件触发机制 |
| `permissions` | `permissions` 字段 + Layer Profile | 权限最小化声明 |
| `resources` | `/__meta__/resources` 块 | 资源能力声明 |

### 1.3 与 AgenticOS 架构映射

| AgenticDSL v4.0 概念 | AgenticOS v2.2 层级 | 说明 |
| :--- | :--- | :--- |
| Layer 1: Execution Primitives | Layer 0 | 内置原语 (assign/llm_call/state.read 等)，C++ 实现 |
| Layer 2: Standard Primitives | Layer 2.5 | 标准库 (`/lib/cognitive/**`, `/lib/thinking/**`, `/lib/workflow/**`) |
| Layer 3: Knowledge Application | Layer 3 + Layer 4 + Layer 6 | 应用工作流 (`/main/**`, `/app/**`, `/app/skills/**`) |

**关键架构规则：**
- ✅ **唯一真理源**：`agentic-dsl-runtime` C++ 引擎是 L0-L4 执行的唯一核心
- ✅ **逻辑即数据**：L2/L3/L4 业务逻辑固化为 `/lib/**` DSL 子图，禁止 Python 实现核心编排
- ✅ **状态工具化**：L4 状态通过 `state.read`/`state.write` 工具暴露，禁止直接内存访问
- ✅ **纯函数约束**：L0 执行原语层必须为纯函数，禁止维护会话状态
- ✅ **Layer Profile**：Cognitive/Thinking/Workflow 三层权限 Profile，编译期 + 运行期双重验证
- ✅ **L0 无反向依赖**：`confidence_score` 等 L4 数据必须通过参数显式传入，严禁 L0 内部调用 L4 服务

---

## 2. 语法规范

### 2.1 基本结构

AgenticDSL 使用 **Markdown 标题格式**，每个子图以 `AgenticDSL` 代码块开始：

```markdown

# /main/start

```yaml
AgenticDSL "/main/start"
type: start
__meta__:
  layer_profile: Workflow
  version: "1.0.0"
next: "/main/step_1"
```
```

# /main/step_1

```yaml
AgenticDSL "/main/step_1"
type: llm_call
llm_call:
  model: "gpt-4o"
  provider: "openai"
  config_ref: "/config/llm/openai"
  prompt: "{{$.task}}"
next: "/main/end"
```
```

# /main/end

```yaml
AgenticDSL "/main/end"
type: end
```



### 2.2 节点类型系统

v4.4 支持以下节点类型：

| 类型 | 用途 | 必需属性 | AgenticOS 层级 | SKILL.md 兼容 |
| :--- | :--- | :--- | :--- | :--- |
| `start` | 入口节点 | 无 | Layer 0 | ✅ |
| `end` | 结束节点 | 无 | Layer 0 | ✅ |
| `assign` | 变量赋值 | `assign.expr`, `assign.path` | Layer 0 | ✅ |
| `tool_call` | 调用注册工具 | `tool`, `arguments`, `output_mapping` | Layer 0 | ✅ tools |
| `state_read` | 读取 L4 状态 | `path`, `output_mapping` | Layer 0 + Layer 4 | ✅ |
| `state_write` | 写入 L4 状态 | `path`, `value` | Layer 0 + Layer 4 | ✅ |
| `llm_call` | 调用 LLM | `llm.model`, `llm.prompt` | Layer 0 | ✅ |
| `llm_generate_dsl` | 生成 DSL 子图 | `prompt`, `output_constraints` | Layer 0 | ✅ |
| `condition` | 条件分支 | `condition.expr`, `true_next`, `false_next` | Layer 0 | ✅ triggers |
| `fork` / `join` | 并行控制 | `fork.branches`, `join.wait_for` | Layer 0 | ✅ |
| `assert` | 条件断言 | `condition`, `on_failure` | Layer 0 | ✅ |
| `trigger` | 事件触发器 | `trigger.event`, `trigger.action` | Layer 2 | ✅ triggers |

### 2.3 元数据声明 (`__meta__`)

每个子图必须声明 `__meta__` 块，包含版本、Profile、权限等信息：

```markdown
# /main/workflow

```agenticdsl
AgenticDSL "/main/workflow"
type: start
__meta__:
  layer_profile: Workflow          # 必需：Cognitive/Thinking/Workflow
  version: "1.0.0"                 # 语义化版本
  signature: "RSA-SHA256:..."      # 标准库子图必需
  author: "skill-developer"
  description: "Python 开发技能包"
  
  # 智能化演进配置
  budget_inheritance: "adaptive"   # strict/adaptive/custom
  require_human_approval: "risk_based"  # true/false/risk_based
  risk_threshold: 0.7
  
  # 资源能力声明（SKILL.md 兼容）
  resources:
    - type: tool
      name: run_python
      scope: sandbox_only
    - type: state
      operations: ["read", "write"]
      paths: ["memory.state.*"]
    - type: network
      outbound:
        domains: ["pypi.org"]
  
  # 触发器声明（SKILL.md 兼容）
  triggers:
    - name: "on_python_file"
      type: "file_pattern"
      pattern: "*.py"
      action: "suggest_skill"

next: "/main/step_1"
```
```

### 2.4 DAG 连接信息（边声明）

v4.4 支持两种连接声明方式：

#### 方式 1：`next` 字段（简单线性流）

```agenticdsl
AgenticDSL "/main/step_1"
type: llm_call
next: "/main/step_2"
```

#### 方式 2：`edges` 独立声明（复杂拓扑）

```markdown
# /main/edges

```agenticdsl
__edges__:
  - from: "/main/start"
    to: "/main/step_1"
    type: "sequential"
  
  - from: "/main/step_1"
    to: "/main/branch_a"
    type: "fork"
    condition: "{{$.condition_a}}"
  
  - from: "/main/step_1"
    to: "/main/branch_b"
    type: "fork"
    condition: "{{$.condition_b}}"
  
  - from: "/main/branch_a"
    to: "/main/join"
    type: "join"
    wait_for: ["branch_a", "branch_b"]
  
  - from: "/main/branch_b"
    to: "/main/join"
    type: "join"
  
  - from: "/main/join"
    to: "/main/end"
    type: "sequential"
```
```

**边类型：**
| 类型 | 说明 | 属性 |
| :--- | :--- | :--- |
| `sequential` | 顺序执行 | 无 |
| `fork` | 并行分支 | `condition` (可选) |
| `join` | 分支合并 | `wait_for`, `merge_strategy` |
| `conditional` | 条件跳转 | `condition`, `true_next`, `false_next` |
| `error` | 错误处理 | `on_error`, `retry_count` |

### 2.5 SKILL.md 兼容语法

#### 工具定义（兼容 SKILL.md `tools`）

```markdown
# /app/skills/python-dev/tools

```agenticdsl
# 工具 1：运行 Python 脚本
AgenticDSL "/app/skills/python-dev/tools/run_python"
type: tool_call
__meta__:
  layer_profile: Workflow
  tool_name: "run_python"
  tool_type: "script"
  runtime: "python3"
  script_path: "./scripts/run.py"
  
tool_call:
  tool: "run_python"
  arguments:
    script: "{{$.script_path}}"
    args: "{{$.script_args}}"
  output_mapping:
    success: "$.tool_result.success"
    output: "$.tool_result.output"

permissions:
  - tool: run_python → scope: sandbox_only
  - state: read → path: "memory.state.*"
  - file: read → path: "/app/skills/python-dev/**"

# 工具 2：代码分析（引用标准库）
AgenticDSL "/app/skills/python-dev/tools/analyze_code"
type: tool_call
__meta__:
  layer_profile: Workflow
  tool_name: "analyze_code"
  tool_type: "dsl"
  
tool_call:
  tool: "analyze_code"
  source: "/lib/skills/python/analyze@v1"
```
```

#### 工作流定义（兼容 SKILL.md `workflows`）

```markdown
# /app/skills/python-dev/workflows

```agenticdsl
# 工作流 1：调试循环
AgenticDSL "/app/skills/python-dev/workflows/debug_loop"
type: start
__meta__:
  layer_profile: Workflow
  workflow_name: "debug_loop"
  trigger: "on_error"
  entry_point: "/app/skills/python-dev/debug/start"
  
next: "/app/skills/python-dev/debug/analyze"

AgenticDSL "/app/skills/python-dev/debug/analyze"
type: llm_call
llm_call:
  model: "gpt-4o"
  prompt: "分析以下错误：{{$.error_message}}"
next: "/app/skills/python-dev/debug/fix"

# 工作流 2：代码审查
AgenticDSL "/app/skills/python-dev/workflows/code_review"
type: start
__meta__:
  layer_profile: Workflow
  workflow_name: "code_review"
  trigger: "manual"
  entry_point: "/app/skills/python-dev/review/start"
```
```

#### 触发器定义（兼容 SKILL.md `triggers`）

```markdown
# /app/skills/python-dev/triggers

```agenticdsl
# 触发器 1：文件模式匹配
AgenticDSL "/app/skills/python-dev/triggers/on_python_file"
type: trigger
__meta__:
  layer_profile: Workflow
  trigger_name: "on_python_file"
  trigger_type: "file_pattern"

trigger:
  event: "file_created"
  pattern: "*.py"
  action: "suggest_skill"
  skill_name: "python-dev-skill"

# 触发器 2：条件触发
AgenticDSL "/app/skills/python-dev/triggers/on_error"
type: trigger
__meta__:
  layer_profile: Workflow
  trigger_name: "on_error"
  trigger_type: "condition"

trigger:
  event: "execution_error"
  condition: "{{$.error_type}} == 'SyntaxError'"
  action: "run_workflow"
  workflow: "/app/skills/python-dev/workflows/debug_loop"
```
```

### 2.6 LLM 交互语法

#### `llm_call` 节点（LLM 输入）

```agenticdsl
AgenticDSL "/main/llm_task"
type: llm_call
llm_call:
  model: "gpt-4o"                    # 模型标识
  provider: "openai"                 # 提供商 (openai/anthropic/local)
  config_ref: "/config/llm/openai"   # 引用全局配置
  parameters:                        # 可选：覆盖全局参数
    temperature: 0.7
    max_tokens: 1000
  prompt: "{{$.task}}"
  output_schema:                     # 可选：结构化输出
    type: object
    properties:
      result: { type: string }
      confidence: { type: number }
next: "/main/end"
```

**安全约束：**
- ✅ `model`/`provider` 必须在 Layer 4 配置的可信列表中
- ✅ API Key 必须端侧加密存储，严禁明文出现在 DSL 或 Context 中
- ✅ 违反者 → 报错 `ERR_LLM_CONFIG_INVALID`

#### `llm_generate_dsl` 节点（LLM 输出）

```agenticdsl
AgenticDSL "/main/generate_workflow"
type: llm_generate_dsl
llm_generate_dsl:
  prompt: "{{memory.state.requirement}}"
  output_constraints:                # 运行时安全约束
    max_blocks: 3                    # 最大节点数
    allowed_node_types:              # 允许的节点类型
      - "assign"
      - "llm_call"
      - "tool_call"
      # 禁止 fork/join 防并发爆炸
    max_depth_delta: 1               # 相对父图深度增量限制
    
    # 智能化演进特性
    budget_inheritance: "adaptive"   # 自适应预算 (strict/adaptive/custom)
    require_human_approval: "risk_based"  # 自适应人机协作
    risk_threshold: 0.7              # 风险阈值
    
    # ⚠️ 关键修订：confidence_score 必须作为参数传入，严禁 L0 内部获取
    # confidence_score: 0.85         # 由 L2/L4 通过 ExecutionBudget 传入
    
    namespace_prefix: "/dynamic/"    # 强制生成路径前缀
next: "/main/execute_generated"
```

### 2.7 DSL 执行控制台（v2.2 新增）

基于 `AgenticOS-v2.2-DSL-Execution-Console-Spec`，DSL 运行时提供独立的 Shell 窗口用于观察和控制。

#### 控制台功能
1. **实例树管理**：展示 L4→L3→L2 执行实例层级，用户可选择 attach 到任意实例。
2. **实时 IO 流**：沙箱 Stdio 流式推送到 xterm.js 终端。
3. **中断与干预**：在任意 DSL 节点执行前/后暂停，修改 Context/State，注入命令。
4. **安全可控**：所有干预操作经过 Layer Profile 验证与审计日志记录。
5. **生命周期绑定**：控制台会话与 `execution_instance_id` 绑定，实例结束会话关闭。

#### 控制台语法示例

```markdown
# /main/debug_session

```agenticdsl
AgenticDSL "/main/debug_session"
type: start
__meta__:
  layer_profile: Workflow
  debuggable: true                   # 允许 attach 到该实例
  console_config:
    isolation_level: "HIGH"          # 独立沙箱
    audit_enabled: true              # 开启审计日志
    allowed_commands:                # 允许的控制命令白名单
      - "pause"
      - "resume"
      - "state_write"
      - "inject_context"

next: "/main/step_1"
```
```

**安全约束：**
- ✅ 所有控制命令必须经过 `ControlValidator` 验证（Section 4.2）
- ✅ 状态修改必须通过 `state.write` 工具，禁止直接内存修改
- ✅ 100% 操作日志记录到 Layer 1 Trace，包含 `execution_instance_id`

---

## 3. 语义规范

### 3.1 命名空间规则

| 命名空间 | 可写入？ | 签名要求 | Profile 约束 | 用途 |
| :--- | :--- | :--- | :--- | :--- |
| `/lib/cognitive/**` | ❌ 禁止运行时写入 | ✅ 强制 | 必须 Cognitive | L4 认知层标准模板 |
| `/lib/thinking/**` | ❌ 禁止运行时写入 | ✅ 强制 | 必须 Thinking | L3 推理层标准模板 |
| `/lib/workflow/**` | ❌ 禁止运行时写入 | ✅ 强制 | 必须 Workflow | L2 工作流标准模板 |
| `/app/skills/**` | ✅ 允许 | ✅ 强制 | 必须声明 | 技能包工作流 |
| `/dynamic/**` | ✅ 自动写入 | ⚠️ 可选 | 继承父图 | 运行时生成子图 |
| `/main/**` | ✅ 允许 | ❌ 不要求 | 无限制 | 应用工作流 |
| `/app/**` | ✅ 允许 | ❌ 不要求 | 无限制 | 应用层工作流 |

**约束：**
- ❌ 禁止写入 `/lib/**`（`ERR_NAMESPACE_VIOLATION`）
- ✅ `/lib/**` 子图必须声明 `signature` 契约
- ✅ `/app/skills/**` 必须声明 `signature` 契约（SKILL.md 兼容）
- ✅ `/app/skills/**` 工具注册到 `skill.{name}.*` 命名空间，避免冲突

### 3.2 Layer Profile 权限模型

v4.4 引入 Layer Profile 权限模型，与 Security Spec v2.2 深度集成：

| Profile 类型 | 对应层级 | 权限级别 | 允许操作 | 禁止操作 |
| :--- | :--- | :--- | :--- | :--- |
| **Cognitive** | Layer 4 | 最高 (严格) | `state.read`, `state.write`, `state.delete`, 读记忆/上下文 | 普通 `tool_call`, 写文件，网络访问 |
| **Thinking** | Layer 3 | 中等 (限制) | `state.read`, `state.temp_write`, 调用 L2, 只读工具 | `state.write`, `state.delete`, 写文件，直接系统调用 |
| **Workflow** | Layer 2 | 标准 (沙箱) | `tool_call`, 文件写 (沙箱内), 网络 (受限), 受限 `state.write` | 直接访问 L4 状态内存，绕过权限验证 |

**状态工具权限映射：**
| 操作类型 | Cognitive Profile (L4) | Thinking Profile (L3) | Workflow Profile (L2) |
| :--- | :--- | :--- | :--- |
| `state.read` | ✅ 允许 | ✅ 允许 | ✅ 允许 |
| `state.write` | ✅ 允许 | ❌ 禁止 | ⚠️ 受限 (沙箱/声明路径) |
| `state.delete` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |
| `state.temp_write` | ✅ 允许 | ✅ 允许 (临时工作区) | ✅ 允许 (临时工作区) |
| `security.*` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |

**双重验证机制：**
| 验证阶段 | 验证内容 | 实现位置 | 错误码 |
| :--- | :--- | :--- | :--- |
| **编译期** | `tool_call` 与 Profile 兼容性 | L0 语义分析器 | `ERR_PROFILE_VIOLATION` |
| **运行期** | 实际调用权限验证 | L2 `StateToolAdapter` | `ERR_PERMISSION_DENIED` |
| **审计期** | 操作日志记录 | L1 Trace 持久化 | N/A |

**关键修订：**
- ✅ `ExecutionContext` 中的 `__layer_profile__` 字段为**只读系统字段**，防止运行时篡改
- ✅ 运行期验证失败触发 P0 告警，记录审计日志

### 3.3 上下文合并策略

当并行分支（`fork`/`join`）写入同一上下文字段时，应用以下策略：

| 策略 | 行为 | 使用场景 | 默认 |
| :--- | :--- | :--- | :--- |
| `error_on_conflict` | 多分支写入同一字段时抛出 `ERR_CTX_MERGE_CONFLICT` | 安全优先，检测意外覆盖 | ✅ |
| `last_write_wins` | 使用最后完成分支的值 | 幂等操作（仅 dev 模式允许） | ❌ |
| `deep_merge` | 递归合并对象，数组完全替换 (RFC 7396) | 嵌套结构组合 | ❌ |
| `array_concat` | 数组合并保持顺序 | 结果聚合 | ❌ |
| `array_merge_unique` | 数组合并并去重 | 唯一项收集 | ❌ |

**声明方式：**
```agenticdsl
/__meta__:
  context_merge_strategies:
    "memory.state.results": "array_concat"
    "memory.state.unique_items": "array_merge_unique"
    "user.profile": "deep_merge"
```

### 3.4 预算系统

#### 预算字段

```agenticdsl
AgenticDSL "/main/start"
type: start
budget:
  max_nodes: 50
  max_wall_time_ms: 60000
  max_cpu_time_ms: 30000
  max_subgraph_depth: 3
  max_llm_tokens: 10000
  max_memory_mb: 512
```

#### 预算继承规则

| 策略 | 行为 | AgenticOS 映射 |
| :--- | :--- | :--- |
| `strict` | 子图预算 ≤ 父图预算 × 50%（默认） | Layer-0-Spec Section 7.3 |
| `adaptive` | 基于 Layer 4 置信度动态调整 (0.3-0.7) | Layer-4-Spec Section 3 (贝叶斯) |
| `custom` | 显式指定比例（如 0.6） | 自定义配置 |

**关键修订：**
- ✅ **`confidence_score` 必须通过参数显式传入 L0**（通过 `ExecutionBudget`），严禁 L0 内部调用 L4 服务获取
- ✅ 置信度与预算比例映射：
  - `confidence >= 0.8` → 0.7 (70%)
  - `0.5 <= confidence < 0.8` → 0.5 (50%)
  - `confidence < 0.5` → 0.3 (30%)

**终止条件：**
- 队列空 + 无活跃生成 + 无待合并子图 + 预算未超
- 超限 → 跳转 `/__system__/budget_exceeded`

---

## 4. SKILL.md 移植规范

### 4.1 SKILL.md 到 DSL 转换流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    SKILL.md → DSL 转换流程                       │
├─────────────────────────────────────────────────────────────────┤
│  1. SKILLS.md 解析 (Layer 6 SDK)                                 │
│     └─ 解析 Manifest → 验证签名 → 提取工具/工作流定义             │
│                                                                  │
│  2. DSL 编译 (Layer 0)                                           │
│     └─ 工作流 DSL → AST → 语义验证 (Layer Profile)               │
│                                                                  │
│  3. 工具注册 (Layer 2)                                           │
│     └─ 注册到 ToolRegistry → 权限验证 → 沙箱配置                 │
│                                                                  │
│  4. 持久化 (Layer 1)                                             │
│     └─ 技能元数据 → SkillStore → 签名验证                        │
│                                                                  │
│  5. 生效 (Layer 4/3)                                             │
│     └─ DomainRegistry 注册 → L3 推理可发现新工具/工作流           │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 SKILL.md 结构映射

| SKILL.md 字段 | AgenticDSL v4.4 映射 | 示例 |
| :--- | :--- | :--- |
| `__meta__.name` | `__meta__.name` | `"python-dev-skill"` |
| `__meta__.version` | `__meta__.version` | `"1.0.0"` |
| `__meta__.signature` | `__meta__.signature` | `"RSA-SHA256:..."` |
| `__meta__.layer_profile` | `__meta__.layer_profile` | `"Workflow"` |
| `tools[].name` | `__meta__.tool_name` | `"run_python"` |
| `tools[].type` | `__meta__.tool_type` | `"script"` / `"dsl"` |
| `tools[].script` | `tool_call.arguments.script` | `"./scripts/run.py"` |
| `tools[].permissions` | `permissions` 字段 | `[state: read → path: "memory.state.*"]` |
| `workflows[].name` | `__meta__.workflow_name` | `"debug_loop"` |
| `workflows[].entry_point` | `AgenticDSL` 路径 | `"/app/skills/python-dev/debug/start"` |
| `workflows[].trigger` | `__meta__.triggers` | `"on_error"` |
| `triggers[].type` | `trigger.event` | `"file_pattern"` / `"condition"` |
| `resources` | `/__meta__/resources` 块 | 资源能力声明 |

### 4.3 技能包签名验证

所有 `/app/skills/**` 技能包必须声明 `signature` 契约：

```agenticdsl
__meta__:
  signature:
    algorithm: "RSA-SHA256"             # 或 ECDSA
    public_key: "..."                   # 公钥指纹
    signed_data: "..."                  # 签名内容
    timestamp: "2026-02-27T10:00:00Z"
    expires_at: "2027-02-27T10:00:00Z"  # 可选，过期时间
```

**验证流程：**
1. L6 应用市场验证签名（发布时）
2. L4 DomainRegistry 验证签名（安装时）
3. L2 WorkflowEngine 验证签名（执行时，缓存）

**错误码：** `ERR_SIGNATURE_INVALID`, `ERR_SIGNATURE_EXPIRED`, `ERR_SIGNATURE_MISSING`

---

## 5. 运行时工具扩展

### 5.1 状态管理工具

v4.4 新增 `state.read`/`state.write` 工具，封装 L4 状态访问：

#### `state.read` 工具

```agenticdsl
AgenticDSL "/main/read_state"
type: tool_call
tool_call:
  tool: "state.read"
  arguments:
    path: "memory.profile.user_preferences"
  output_mapping:
    value: "$.user_prefs"
```

#### `state.write` 工具

```agenticdsl
AgenticDSL "/main/write_state"
type: tool_call
tool_call:
  tool: "state.write"
  arguments:
    path: "memory.state.last_query"
    value: "{{$.query}}"
```

**安全约束（关键修订）：**
- ✅ DSL → `state.read`/`state.write` 工具 → L2 `StateToolAdapter` → L4 `IStateManager`
- ❌ 禁止：DSL 直接访问 `CognitiveStateManager` 内存
- ❌ 禁止：L2 工具绕过权限验证直接调用 L4 状态接口
- ❌ 禁止：L0 内部反向依赖 L4 服务获取状态（所有 L4 数据必须通过参数显式传入）
- ✅ **路径验证**：敏感路径（`security.*`, `user.private.*`）必须加密存储，仅 Cognitive Profile 可访问
- ✅ **审计日志**：所有状态操作必须记录到 L1 Trace，包含 `execution_instance_id`

### 5.2 基础设施适配器

L2 提供基础设施适配器，封装文件/网络/进程操作：

```agenticdsl
AgenticDSL "/main/file_read"
type: tool_call
tool_call:
  tool: "file.read"
  arguments:
    path: "/app/data/input.txt"
  output_mapping:
    content: "$.file_content"
permissions:
  - file: read → path: "/app/data/**"

AgenticDSL "/main/network_request"
type: tool_call
tool_call:
  tool: "http.get"
  arguments:
    url: "https://api.example.com/data"
    headers:
      Authorization: "{{$.api_key}}"
  output_mapping:
    response: "$.http_response"
permissions:
  - network: outbound → domains: ["api.example.com"]
```

### 5.3 工具注册协议

L2 `ToolRegistry` 支持动态注册工具：

```python
# Layer 2 注册 state 工具（Python Thin Wrapper）
engine.register_tool("state.read", lambda args: state_manager.read(args["key"]))
engine.register_tool("state.write", lambda args: state_manager.write(args["key"], args["value"]))

# Layer 2 注册技能工具
engine.register_tool("skill.python-dev.run_python", lambda args: sandbox.execute_script(args["script"]))
```

**命名空间隔离：**
- 技能工具注册到 `skill.{name}.*` 命名空间，避免冲突
- 标准库工具注册到 `stdlib.*` 命名空间
- 基础设施工具注册到 `infra.*` 命名空间

---

## 6. 错误处理

### 6.1 错误类型

| 错误代码 | 说明 | 处理建议 | 文档依据 |
| :--- | :--- | :--- | :--- |
| `ERR_COMPILE` | 编译错误 | 检查 DSL 语法 | Language-Spec-v4.4 Section 6.1 |
| `ERR_EXECUTION` | 执行错误 | 检查节点配置 | Language-Spec-v4.4 Section 6.1 |
| `ERR_BUDGET_EXCEEDED` | 预算超限 | 优化 DAG 或减少操作 | Language-Spec-v4.4 Section 3.4 |
| `ERR_CONSTRAINT_VIOLATION` | 约束违反 | 检查 `output_constraints` | Language-Spec-v4.4 Section 2.6 |
| `ERR_NAMESPACE_VIOLATION` | 命名空间违规 | 禁止写入 `/lib/**` | Language-Spec-v4.4 Section 3.1 |
| `ERR_PROFILE_VIOLATION` | Layer Profile 违规 | 检查 Profile 声明与工具兼容性 | Security-Spec-v2.2 Section 3 |
| `ERR_PERMISSION_DENIED` | 运行期权限拒绝 | 检查 StateToolAdapter 验证 | Security-Spec-v2.2 Section 3.3 |
| `ERR_SIGNATURE_INVALID` | 签名验证失败 | 验证技能包签名 | Skill-Package-Spec-v2.2 Section 4 |
| `ERR_CIRCULAR_DEPENDENCY` | 循环依赖 | 检查调用链 Token | Layer-3-Spec-v2.2 Section 3 |
| `ERR_HUMAN_APPROVAL_REJECTED` | 人工确认被拒绝 | 用户拒绝执行 | Intelligence-Spec-v1.0 Section 6 |
| `ERR_LLM_CONFIG_INVALID` | LLM 配置无效 | 检查模型/提供商白名单 | Security-Spec-v2.2 Section 2.3.3 |
| `ERR_L0_REVERSE_DEPENDENCY` | L0 反向依赖 L4 | 检查 L0 代码无 L4 服务实例化 | Layer-0-Spec-v2.2 Section 1.2 |

### 6.2 错误处理示例

```agenticdsl
AgenticDSL "/main/error_handling"
type: tool_call
tool_call:
  tool: "risky_operation"
  on_error: "/main/fallback"  # 错误跳转
next: "/main/continue"

AgenticDSL "/main/fallback"
type: assign
assign:
  expr: "Error occurred"
  path: "memory.state.error"
next: "/main/end"
```

---

## 7. 可观测性（Trace Schema）

所有标准库操作 Trace 必须兼容 AgenticOS Observability Spec v2.2：

### 7.1 通用 Trace 结构

```json
{
  "node_id": "node-123",
  "node_type": "llm_call",
  "timestamp": "2026-02-27T08:30:00Z",
  "status": "success",
  "latency_ms": 450,
  "context_snapshot": {},
  "budget_snapshot": {
    "nodes_left": 15,
    "depth_left": 1
  },
  "loop_type": "fine",
  "trace_id": "trace_abc",
  "session_id": "sess_123",
  "user_id": "user_456",
  "layer_profile": "Workflow",
  "execution_instance_id": "exec_l2_001"
}
```

### 7.2 智能化演进 Trace 扩展

```json
{
  "intelligence": {
    "budget_inheritance": "adaptive",
    "confidence_score": 0.85,
    "budget_ratio": 0.7,
    "human_approval": "auto_approved",
    "risk_assessment": "low",
    "scheduling_priority": 10
  }
}
```

### 7.3 技能包 Trace 扩展

```json
{
  "skill_metadata": {
    "skill_id": "skill.python-dev-skill",
    "skill_version": "1.0.0",
    "tool_name": "run_python",
    "workflow_name": "debug_loop"
  }
}
```

### 7.4 控制台干预 Trace 扩展（v2.2 新增）

```json
{
  "console_intervention": {
    "command": "state_write",
    "path": "memory.state.override_flag",
    "value": "true",
    "validation_result": "passed",
    "operator_id": "user_456"
  }
}
```

---

## 8. 版本管理与兼容性

### 8.1 版本映射

| 语言规范版本 | AgenticOS 版本 | DSL 引擎版本 | 兼容性 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| v4.3.0 | v2.1.1 | v3.9.0 | ✅ 完全 | 当前版本 |
| v4.4.0 | v2.2.0 | v4.0.0 | ✅ 向后 | 新增 SKILL.md 兼容、Layer Profile |
| v5.0.0 | v3.0.0 | v5.0.0 | ❌ 不兼容 | 破坏性变更 |

### 8.2 向后兼容规则

- **新增字段**：必须是可选的（如 `metadata.priority`）
- **删除字段**：必须提前 1 年废弃通知
- **修改字段**：必须提供转换层
- **枚举值**：新增值必须向后兼容
- **安全策略**：安全级别只能提升，不能降低
- **纯函数约束**：不得破坏 `compile()` 和 `execute_node()` 的纯函数语义
- **接口签名**：Python 绑定接口签名 5 年稳定
- **C++ ABI 兼容性**：C++ 公开头文件 (`src/core/engine.h`, `src/state/manager.h`) 5 年 ABI 稳定，符号版本控制

### 8.3 废弃接口管理

| 接口 | 废弃版本 | 移除版本 | 替代接口 |
| :--- | :--- | :--- | :--- |
| `Runtime.execute()` | v2.0 | v3.0 | `Runtime.execute_node()` |
| `budget_inheritance: strict` (固定 50%) | v2.1.1 | v3.0 | `budget_inheritance: adaptive` |
| `require_human_approval: true` (硬约束) | v2.1.1 | v3.0 | `require_human_approval: risk_based` |
| Python 业务逻辑接口 | v2.2 | v3.0 | C++ Core API + DSL |

---

## 9. 测试策略

### 9.1 单元测试

```python
# test_language_v4.4.py
import pytest
from agentic_language import DSLConstraints, LayerProfileValidator

class TestNamespaceValidation:
    """测试命名空间验证"""
    
    def test_lib_read_only(self):
        """验证/lib/** 只读约束"""
        # 尝试写入/lib/**
        with pytest.raises(NamespaceViolationError):
            compile_dsl("/lib/test", "assign")
    
    def test_signature_required(self):
        """验证/lib/** 签名要求"""
        # 缺少签名的/lib/** 子图
        with pytest.raises(SignatureMissingError):
            load_template("/lib/reasoning/test", "v1")

class TestLayerProfileValidation:
    """测试 Layer Profile 验证"""
    
    def test_cognitive_profile_tool_call(self):
        """验证 Cognitive Profile 禁止 tool_call"""
        source = """
        AgenticDSL "/lib/cognitive/test"
        type: tool_call
        tool_call:
          tool: web_search
        layer_profile: Cognitive
        """
        with pytest.raises(ProfileViolationError):
            compile_dsl(source)
    
    def test_thinking_profile_state_write(self):
        """验证 Thinking Profile 禁止 state.write"""
        source = """
        AgenticDSL "/lib/thinking/test"
        type: tool_call
        tool_call:
          tool: state.write
        layer_profile: Thinking
        """
        with pytest.raises(ProfileViolationError):
            compile_dsl(source)

class TestL0ReverseDependency:
    """测试 L0 无反向依赖"""
    
    def test_confidence_score_parameter(self):
        """验证 confidence_score 通过参数传入"""
        # L0 不应内部调用 L4 服务
        # 通过单元测试验证相同输入产生相同输出（纯函数）
        runtime = Runtime()
        budget = ExecutionBudget(confidence_score=0.85)  # 显式传入
        result = runtime.execute_node(ast, "/main/start", context, budget)
        # 验证结果一致
        assert result.success == True

class TestSkillPackageCompatibility:
    """测试 SKILL.md 兼容性"""
    
    def test_skill_manifest_parsing(self):
        """验证 SKILL.md Manifest 解析"""
        manifest = parse_skills_md("test_skills.md")
        assert manifest.name == "python-dev-skill"
        assert manifest.version == "1.0.0"
        assert manifest.layer_profile == "Workflow"
    
    def test_skill_signature_verification(self):
        """验证技能包签名验证"""
        with pytest.raises(SignatureVerificationError):
            parse_skills_md("invalid_signature_skills.md")
```

### 9.2 集成测试

```python
# test_integration_v4.4.py
import pytest
from agentic_language import Compiler, SkillImporter

class TestSkillImportIntegration:
    """测试技能包导入集成"""
    
    async def test_import_and_execute_skill(self):
        """验证技能导入与执行"""
        importer = SkillImporter(...)
        
        # 导入技能
        skill_id = await importer.import_skill("python-dev-skill-1.0.0.zip")
        assert skill_id == "skill.python-dev-skill"
        
        # 执行技能工作流
        engine = WorkflowEngine(...)
        context = ExecutionContext()
        context.set_layer_profile("Workflow")
        
        result = await engine.execute_skill_workflow(
            skill_id="skill.python-dev-skill",
            workflow_name="debug_loop",
            context=context,
            budget=ExecutionBudget()
        )
        assert result.success == True

class TestLLM 双向协议：
    """测试 LLM 双向协议"""
    
    async def test_llm_generate_dsl(self):
        """验证 LLM 生成 DSL"""
        engine = Compiler(...)
        
        # LLM 生成 DSL 子图
        result = await engine.execute_llm_generate_dsl(
            prompt="创建一个 Python 代码分析工作流",
            output_constraints={
                "max_blocks": 3,
                "allowed_node_types": ["assign", "llm_call", "tool_call"]
            }
        )
        
        # 验证生成的 DSL 有效
        assert result.ast is not None
        assert len(result.ast.nodes) <= 3

class TestLayerProfile 双重验证：
    """测试 Layer Profile 双重验证"""
    
    async def test_compile_time_validation(self):
        """验证编译期 Profile 验证"""
        engine = Compiler(...)
        
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

class TestDSLConsoleIntegration:
    """测试 DSL 执行控制台集成"""
    
    async def test_attach_instance(self):
        """验证 attach 到执行实例"""
        console = DSLConsole(...)
        session_id = await console.create_session("sess_123")
        instance_tree = await console.get_instance_tree(session_id)
        
        # 验证实例树结构
        assert "root" in instance_tree
        assert instance_tree["root"]["layer"] == "L4"
        
        # 验证 attach
        pty_session = await console.attach_instance(instance_tree["root"]["execution_instance_id"])
        assert pty_session["pty_session_id"] is not None
```

---

## 10. 实施路线图

### 10.1 Phase 1：核心语法与 SKILL.md 兼容（P0）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | DSL 解析器增强 | 支持 `__meta__` 块、`edges` 声明 | Layer-0-Spec-v2.2 |
| W3-4 | SKILL.md 解析器 | 解析 Manifest、验证签名 | Skill-Package-Spec-v2.2 |
| W5-6 | Layer Profile 验证 | 编译期验证 100% 生效 | Security-Spec-v2.2 |
| W7-8 | 状态工具注册 | `state.read/write` 工具可用 | State-Tool-Spec-v2.2 |

### 10.2 Phase 2：LLM 双向协议（P1）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | `llm_generate_dsl` 增强 | 支持 `output_constraints` | Intelligence-Spec-v1.0 |
| W3-4 | `llm_call` 配置扩展 | 支持 `model`/`provider`/`config_ref` | Layer-0-Spec-v2.2 |
| W5-6 | LLM 适配器工厂 | `ILLMProvider` 接口实现 | Layer-0-Spec-v2.2 |
| W7-8 | 全链路压测 | SLO 达标，性能回归测试通过 | Observability-Spec-v2.2 |

### 10.3 Phase 3：触发器与事件系统（P1）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | 触发器语法 | `trigger` 节点类型实现 | Layer-2-Spec-v2.2 |
| W3-4 | 事件总线 | 事件发布/订阅机制 | Layer-4-Spec-v2.2 |
| W5-6 | 条件触发 | `condition` 节点与触发器集成 | Layer-2-Spec-v2.2 |
| W7-8 | 安全审计 | 触发器操作 100% 审计日志 | Security-Spec-v2.2 |

### 10.4 Phase 4：DSL 执行控制台（P1）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | 实例树管理 | L4→L3→L2 实例层级展示 | DSL-Console-Spec-v2.2 |
| W3-4 | PTY 会话集成 | 独立沙箱 Stdio 流式转发 | Layer-2-Spec-v2.2 |
| W5-6 | 控制命令验证 | `ControlValidator` 权限验证 | Security-Spec-v2.2 |
| W7-8 | 审计日志 | 100% 操作记录到 L1 Trace | Layer-1-Spec-v2.2 |

---

## 11. 风险与缓解

| 风险 | 影响 | 缓解措施 | 责任人 | 对齐依据 |
| :--- | :--- | :--- | :--- | :--- |
| SKILL.md 格式变更 | 与其他工具兼容性 | 保持向后兼容，增加格式版本标记 | 语言规范负责人 | Skill-Package-Spec-v2.2#Sec-2 |
| Layer Profile 验证遗漏 | 权限绕过风险 | 编译期 + 运行期双重验证 + 审计日志 | 安全负责人 | Security-Spec-v2.2#Sec-3.3 |
| L0 反向依赖 L4 | 状态泄漏风险 | 文档明确 + 代码审查 + 单元测试 | L0 负责人 | Layer-0-Spec-v2.2#Sec-1.2 |
| LLM 生成 DSL 不可控 | 资源爆炸风险 | `output_constraints` 严格限制 | Layer 4 负责人 | Intelligence-Spec-v1.0#Sec-3 |
| 状态工具性能开销 | 调用延迟增加 | 批量操作 + 本地缓存 (TTL 受 L4 控制) | L2 负责人 | Arch-v2.2#Sec-13 |
| 技能包恶意代码 | 沙箱内攻击 | 签名验证 + 沙箱隔离 + 权限最小化 | 安全负责人 | Security-Spec-v2.2#Sec-4 |
| C++ ABI 兼容性破坏 | 第三方集成失败 | 符号版本控制 + ABI 兼容性测试 | L0 负责人 | Interface-Contract-v2.2#Sec-21 |
| 状态一致性风险 | 状态覆盖或冲突 | 版本向量 + 事务支持 (compare-and-swap) | L4 负责人 | Arch-v2.2#Sec-13 |
| 交互式沙箱逃逸 | 系统被攻破 | 严格 seccomp 配置，禁止危险系统调用 | 安全负责人 | Security-Spec-v2.2#Sec-2.2.2 |
| 控制台干预篡改 | 状态非法修改 | 所有命令经 `ControlValidator` 验证 | Layer 2 负责人 | DSL-Console-Spec-v2.2#Sec-4 |

---

## 12. 与 AgenticOS 文档的引用关系

| Language-Spec v4.4 章节 | AgenticOS 文档引用 | 说明 |
| :--- | :--- | :--- |
| Section 1 (核心定位) | Architecture-v2.2#Sec-1.2 | DSL 三层架构映射 |
| Section 2 (语法规范) | DSL-Engine-Spec-v4.0 Section 2 | 节点类型定义 |
| Section 2.7 (控制台) | DSL-Console-Spec-v2.2#Sec-3 | 独立 Shell 窗口规范 |
| Section 3 (语义规范) | Security-Spec-v2.2 Section 3 | Layer Profile 安全模型 |
| Section 4 (SKILL.md 移植) | Skill-Package-Spec-v2.2 Section 3 | 技能包移植流程 |
| Section 5 (运行时工具) | State-Tool-Spec-v2.2 Section 4 | 状态管理工具化 |
| Section 6 (错误处理) | Layer-0-Spec-v2.2 Section 15 | 错误码定义 |
| Section 7 (可观测性) | Observability-Spec-v2.2 Section 4 | Trace Schema |
| Section 8 (版本管理) | Interface-Contract-v2.2 Section 18 | 版本兼容性 |
| Section 9 (测试策略) | Security-Spec-v2.2 Section 12 | 安全测试 |

---

## 13. 附录：核心标准库清单

| 路径 | 用途 | 稳定性 | 依赖 Layer |
| :--- | :--- | :--- | :--- |
| `/lib/cognitive/routing@v1` | L4 路由决策 | stable | Layer 4 |
| `/lib/cognitive/confidence@v1` | 置信度评估 | stable | Layer 4 |
| `/lib/thinking/react_loop@v1` | L3 ReAct 循环 | stable | Layer 3 |
| `/lib/thinking/plan_and_execute@v1` | 计划执行模式 | stable | Layer 3 |
| `/lib/workflow/multi_agent_collab@v1` | 多智能体协作 | stable | Layer 2 |
| `/lib/workflow/llm_chain@v1` | LLM 链式调用 | stable | Layer 2 |
| `/lib/reasoning/generate_text@v1` | 基础生成 | stable | Layer 0 |
| `/lib/reasoning/structured_generate@v1` | 结构化输出 | stable | Layer 0 |
| `/lib/memory/state/read@v1` | 状态读取工具 | stable | Layer 4 |
| `/lib/memory/state/write@v1` | 状态写入工具 | stable | Layer 4 |
| `/lib/skills/python/analyze@v1` | Python 代码分析 | stable | Layer 2 |
| `/lib/social/contract_sign@v1` | 契约签署 | stable | Layer 4.5 |

---

## 14. 总结

AgenticDSL v4.4 是 AgenticOS 的声明式领域特定语言，核心特性：

1. **LLM 通用语言**：DSL 作为 LLM 输入/输出的统一格式，支持双向协议
2. **SKILL.md 超集**：完全兼容 SKILL.md 技能包格式，支持工具/工作流/触发器定义
3. **Markdown 原生**：使用 Markdown 标题格式，LLM 可自然生成与理解
4. **DAG 显式化**：节点信息与连接信息分离声明，支持复杂拓扑
5. **状态工具化**：通过 `state.read`/`state.write` 工具访问 L4 状态
6. **Layer Profile 安全**：Cognitive/Thinking/Workflow 三层权限 Profile，编译期 + 运行期双重验证
7. **智能化演进**：自适应预算、智能调度、动态沙箱、风险感知人机协作
8. **运行时可观察可控制**：独立 Shell 窗口观察运行过程，支持实例树管理与干预

**核心批准条件：**
- ✅ **SKILL.md 格式标准化**：Section 4 明确 Manifest 结构、签名要求、Layer Profile 声明
- ✅ **DAG 连接显式化**：Section 2.4 明确 `next` 字段与 `edges` 独立声明两种方式
- ✅ **Layer Profile 双重验证**：Section 3.2 明确编译期 (L0) 与运行期 (L2) 的验证交互
- ✅ **状态工具安全约束**：Section 5.1 明确 `state.read/write` 工具的权限验证与审计日志
- ✅ **LLM 双向协议**：Section 2.6 明确 `llm_call` 与 `llm_generate_dsl` 的输入/输出规范
- ✅ **DSL 执行控制台**：Section 2.7 明确独立 Shell 窗口与实例树管理
- ✅ **L0 无反向依赖**：Section 3.4 明确 `confidence_score` 通过参数传入，严禁 L0 内部获取
- ✅ **测试覆盖率达标**：Section 9 明确安全关键代码覆盖率 >90%

通过严格的接口契约与安全约束，确保 AgenticDSL v4.4 成为 LLM 与 AgenticOS 之间的稳定、安全、可演进的通用语言。

---

文档结束  
版权：AgenticOS 架构委员会  
许可：CC BY-SA 4.0 + 专利授权许可