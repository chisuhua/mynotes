
# AgenticOS v2.2 DSL 执行控制台规范

---

## 执行摘要

本规范定义 AgenticOS v2.2 的 **DSL 执行控制台（DSL Execution Console）** 架构，支持用户在 xterm.js 终端中：
*   **全链路观察**：实时查看 L4 认知决策、L3 推理步骤、L2 DSL 节点执行流。
*   **实例树管理**：统一展示 L4→L3→L2 执行实例层级，用户可选择 attach 到任意实例。
*   **中断与干预**：在任意 DSL 节点执行前/后暂停，修改 Context/State，注入命令。
*   **安全可控**：所有干预操作经过 Layer Profile 验证与审计日志记录。
*   **生命周期绑定**：控制台会话与 `execution_instance_id` 绑定，实例结束会话关闭（支持历史回放）。

**核心设计**：执行实例化 + 运行时钩子 + 双向 Shell 协议 + 安全沙箱

**关键变更（v2.2）：**
*   **标识符统一**：取消 `debug_session_id`，使用 `session_id` + `execution_instance_id`。
*   **实例树追踪**：明确 L4/L3/L2 父子实例关系，支持跨层 attach。
*   **状态工具化干预**：所有状态修改必须通过 `state.write` 工具，经过 Layer Profile 验证。

---

## 1. 核心定位

### 1.1 控制台定义

DSL 执行控制台是 AgenticOS v2.2 的 **调试与观察界面**，本质是 **Layer 5 终端组件** 与 **Layer 2 执行实例** 的双向交互通道。

| 特性 | 说明 | 实现层级 |
| :--- | :--- | :--- |
| **实例树观察** | 展示 L4→L3→L2 执行实例层级 | Layer 2 ExecutionInstanceManager |
| **实时 IO 流** | 沙箱 Stdio 流式推送到 xterm.js | Layer 5 TerminalComponent |
| **控制命令** | 暂停/恢复/注入/状态修改 | Layer 2 DebugShellAdapter |
| **安全审计** | 100% 操作日志记录到 Layer 1 | Layer 1 AuditLogger |
| **生命周期** | 控制台会话绑定 `execution_instance_id` | Layer 2/4 |

### 1.2 关键约束

✅ **DSL-Centric**：调试对象为 DSL 编排流程（AST 节点执行），而非 Python 脚本。
✅ **状态工具化**：干预操作通过 `state.write` 工具或受控的 Context 注入实现，禁止直接内存修改。
✅ **Layer Profile 安全**：调试会话需声明 `Debug Profile` 或经过 Cognitive Profile 授权。
✅ **沙箱隔离**：交互式会话在独立 `SandboxController` 沙箱中运行，不影响生产环境。
✅ **标识符统一**：使用 `session_id` (用户) + `execution_instance_id` (实例)，无 `debug_session_id`。

❌ **禁止**：直接暴露 OS Shell（违反安全规范，绕过 SandboxController）。
❌ **禁止**：绕过沙箱隔离执行命令。
❌ **禁止**：会话 IO 不记录审计日志。
❌ **禁止**：L0 反向依赖 L4 服务获取会话状态。

---

## 2. 架构设计

### 2.1 控制台架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 5 (Interaction)                                          │
│  ┌─────────────────┐      WebSocket (Execution Stream) ┌────────┐│
│  │ xterm.js        │◄─────────────────────────────────►│ WS     ││
│  │ Terminal        │      (Stdio + Control Commands)   │ Client ││
│  └─────────────────┘                                   └───┬────┘│
└────────────────────────────────────────────────────────────┼─────┘
                                                             │
┌────────────────────────────────────────────────────────────┼─────┐
│  Layer 4 (Cognitive)                                        │     │
│  ┌─────────────────┐      Session Context                  │     │
│  │ SessionManager  │◄─────────────────────────────────────┤     │
│  │ (session_id)    │                                     │     │
│  └────────┬────────┘                                     │     │
│           │                                             │     │
│           │ execution_instance_id                       │     │
│           ▼                                             │     │
└────────────────────────────────────────────────────────────┼─────┘
                                                             │
┌────────────────────────────────────────────────────────────┼─────┐
│  Layer 2 (Execution)                                        │     │
│  ┌─────────────────┐      Execution Instance Tree          │     │
│  │ ExecutionInstanceManager │◄─────────────────────────────┤     │
│  │ (Instance Tree) │                                     │     │
│  │                 │                                     │     │
│  │  L4 Instance    │                                     │     │
│  │    └─ L3 Instance     │                                     │     │
│  │       └─ L2 Instance  │                                     │     │
│  │          └─ PTY Session │                                     │     │
│  └─────────────────┘                                     │     │
└────────────────────────────────────────────────────────────┴─────┘
```

### 2.2 标识符体系

| 标识符 | 用途 | 生命周期 | 范围 | 示例 |
| :--- | :--- | :--- | :--- | :--- |
| `session_id` | 用户会话上下文 | 多轮对话 | 用户级 | `sess_789` |
| `execution_instance_id` | **DSL 执行实例** | 单次 DSL 执行 | 全局唯一 | `exec_l4_001` |
| `trace_id` | 全链路追踪 | 单次请求 | 全局唯一 | `trace_abc123` |
| `pty_session_id` | 终端 IO 会话 | 实例运行期间 | 实例级 | `pty_001` |

**关键区别：**
*   `session_id`：用于鉴权（AuthZ），标识用户。
*   `execution_instance_id`：用于控制（Control），标识具体哪个 DSL 实例在运行。
*   `trace_id`：用于可观测性（Observability），串联日志。
*   **取消 `debug_session_id`**：避免标识符冗余，调试会话即执行实例的视图。

### 2.3 执行实例树结构

```
ExecutionInstanceTree (session_id: sess_789, trace_id: trace_abc123)
│
├── execution_instance_id: "exec_l4_001"
├── layer: "L4"
├── dsl_path: "/lib/cognitive/routing@v1"
├── parent_instance_id: null
├── child_instances: ["exec_l3_001"]
├── status: "running"
├── attachable: true
├── pty_session_id: "pty_001"
└── created_at: "2026-02-25T10:00:00Z"
│
└── execution_instance_id: "exec_l3_001"
    ├── layer: "L3"
    ├── dsl_path: "/lib/thinking/react_loop@v1"
    ├── parent_instance_id: "exec_l4_001"
    ├── child_instances: ["exec_l2_001"]
    ├── status: "running"
    ├── attachable: true
    ├── pty_session_id: "pty_002"
    └── created_at: "2026-02-25T10:00:05Z"
    │
    └── execution_instance_id: "exec_l2_001"
        ├── layer: "L2"
        ├── dsl_path: "/lib/workflow/code_analysis@v1"
        ├── parent_instance_id: "exec_l3_001"
        ├── child_instances: []
        ├── status: "running"
        ├── attachable: true
        ├── pty_session_id: "pty_003"
        └── created_at: "2026-02-25T10:00:10Z"
```

### 2.4 核心组件

| 组件 | 层级 | 职责 | 关键接口 |
| :--- | :--- | :--- | :--- |
| **ExecutionTerminal** | Layer 5 | 渲染 DSL 执行流，接收用户输入 | `render_node_event()`, `send_command()` |
| **ExecutionInstanceManager** | Layer 2 | 管理实例树，追踪父子关系 | `create_instance()`, `get_instance_tree()` |
| **DebugShellAdapter** | Layer 2 | 将终端 IO 映射为控制命令 | `attach_instance()`, `handle_command()` |
| **ControlValidator** | Layer 2/4 | 验证控制命令的 Layer Profile 权限 | `validate_profile()` |

---

## 3. 详细设计

### 3.1 Layer 2: 执行实例管理器

```python
# layer2/execution_instance_manager.py
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum

class InstanceStatus(Enum):
    CREATED = "created"
    RUNNING = "running"
    PAUSED = "paused"       # 调试暂停
    COMPLETED = "completed"
    FAILED = "failed"
    TERMINATED = "terminated"

@dataclass
class ExecutionInstance:
    """DSL 执行实例（5 年稳定）"""
    execution_instance_id: str
    trace_id: str
    session_id: str
    layer: str  # "L4" | "L3" | "L2"
    dsl_path: str
    parent_instance_id: Optional[str]
    child_instance_ids: List[str] = field(default_factory=list)
    status: InstanceStatus = InstanceStatus.CREATED
    pty_session_id: Optional[str] = None  # 关联的 PTY 会话
    attachable: bool = True  # 是否可 attach
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    # 智能化演进字段
    budget_ratio: Optional[float] = None
    confidence_score: Optional[float] = None
    risk_level: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "execution_instance_id": self.execution_instance_id,
            "trace_id": self.trace_id,
            "session_id": self.session_id,
            "layer": self.layer,
            "dsl_path": self.dsl_path,
            "parent_instance_id": self.parent_instance_id,
            "child_instance_ids": self.child_instance_ids,
            "status": self.status.value,
            "pty_session_id": self.pty_session_id,
            "attachable": self.attachable,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "metadata": self.metadata,
            "budget_ratio": self.budget_ratio,
            "confidence_score": self.confidence_score,
            "risk_level": self.risk_level
        }

class ExecutionInstanceManager:
    """
    执行实例管理器
    
    职责：
    - 管理 DSL 执行实例树
    - 追踪父子关系
    - 支持 attach/detach 到任意实例
    - 与 DebugShellAdapter 集成
    """
    
    def __init__(self):
        self.instances: Dict[str, ExecutionInstance] = {}
        self.trace_to_instances: Dict[str, List[str]] = {}  # trace_id → instance_ids
        self.session_to_instances: Dict[str, List[str]] = {}  # session_id → instance_ids
    
    def create_instance(
        self,
        layer: str,
        dsl_path: str,
        trace_id: str,
        session_id: str,
        parent_instance_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> ExecutionInstance:
        """创建执行实例"""
        import uuid
        instance_id = f"exec_{layer.lower()}_{uuid.uuid4().hex[:8]}"
        
        instance = ExecutionInstance(
            execution_instance_id=instance_id,
            trace_id=trace_id,
            session_id=session_id,
            layer=layer,
            dsl_path=dsl_path,
            parent_instance_id=parent_instance_id,
            metadata=metadata or {}
        )
        
        self.instances[instance_id] = instance
        
        # 建立索引
        if trace_id not in self.trace_to_instances:
            self.trace_to_instances[trace_id] = []
        self.trace_to_instances[trace_id].append(instance_id)
        
        if session_id not in self.session_to_instances:
            self.session_to_instances[session_id] = []
        self.session_to_instances[session_id].append(instance_id)
        
        # 更新父实例的子实例列表
        if parent_instance_id and parent_instance_id in self.instances:
            parent = self.instances[parent_instance_id]
            parent.child_instance_ids.append(instance_id)
            parent.updated_at = datetime.utcnow()
        
        return instance
    
    def get_instance_tree(self, trace_id: str) -> Dict[str, Any]:
        """获取执行实例树（用于 xterm.js 展示）"""
        instance_ids = self.trace_to_instances.get(trace_id, [])
        if not instance_ids:
            return {"trace_id": trace_id, "instances": [], "root": None}
        
        # 找到根实例（parent_instance_id 为 null）
        root = None
        for iid in instance_ids:
            inst = self.instances[iid]
            if inst.parent_instance_id is None:
                root = inst.to_dict()
                break
        
        # 构建树形结构
        def build_tree(instance_id: str) -> Dict[str, Any]:
            inst = self.instances[instance_id]
            node = inst.to_dict()
            node["children"] = [
                build_tree(child_id) for child_id in inst.child_instance_ids
            ]
            return node
        
        if root:
            root = build_tree(root["execution_instance_id"])
        
        return {
            "trace_id": trace_id,
            "session_id": self.instances[instance_ids[0]].session_id,
            "root": root,
            "instances": [self.instances[iid].to_dict() for iid in instance_ids]
        }
    
    def get_attachable_instances(self, session_id: str) -> List[ExecutionInstance]:
        """获取可 attach 的实例列表（用于 xterm.js 选择）"""
        instance_ids = self.session_to_instances.get(session_id, [])
        return [
            self.instances[iid] for iid in instance_ids
            if self.instances[iid].attachable and self.instances[iid].status == InstanceStatus.RUNNING
        ]
    
    def update_status(self, instance_id: str, status: InstanceStatus):
        """更新实例状态"""
        if instance_id in self.instances:
            self.instances[instance_id].status = status
            self.instances[instance_id].updated_at = datetime.utcnow()
    
    def link_pty_session(self, instance_id: str, pty_session_id: str):
        """关联 PTY 会话"""
        if instance_id in self.instances:
            self.instances[instance_id].pty_session_id = pty_session_id
```

### 3.2 Layer 2: 调试 Shell 适配器

```python
# layer2/debug_shell_adapter.py
class DebugShellAdapter:
    def __init__(self, instance_manager: ExecutionInstanceManager, ...):
        self.instance_manager = instance_manager
        self.pty_sessions: Dict[str, InteractiveSession] = {}
    
    async def attach_instance(self, instance_id: str, user_id: str) -> Dict[str, Any]:
        """Attach 到执行实例"""
        if instance_id not in self.instance_manager.instances:
            raise ValueError(f"Instance not found: {instance_id}")
        
        instance = self.instance_manager.instances[instance_id]
        
        if not instance.attachable:
            raise ValueError(f"Instance not attachable: {instance_id}")
        
        if instance.status != InstanceStatus.RUNNING:
            raise ValueError(f"Instance not running: {instance.status}")
        
        # 创建或复用 PTY 会话
        if instance.pty_session_id and instance.pty_session_id in self.pty_sessions:
            pty_session = self.pty_sessions[instance.pty_session_id]
        else:
            # 创建新 PTY 会话
            pty_session = await self.create_pty_session(instance)
            instance.pty_session_id = pty_session.session_id
            self.instance_manager.link_pty_session(instance_id, pty_session.session_id)
            self.pty_sessions[pty_session.session_id] = pty_session
        
        return {
            "pty_session_id": pty_session.session_id,
            "instance_id": instance_id,
            "layer": instance.layer,
            "dsl_path": instance.dsl_path,
            "websocket_url": f"ws://l2/debug/pty/{pty_session.session_id}"
        }
    
    async def create_pty_session(self, instance: ExecutionInstance) -> InteractiveSession:
        """为执行实例创建 PTY 会话"""
        config = InteractiveSessionConfig(
            isolation_level="HIGH",
            shell_cmd="/bin/bash",
            audit_enabled=True
        )
        
        session = InteractiveSession(
            session_id=f"pty_{uuid.uuid4().hex[:8]}",
            user_id=instance.metadata.get("user_id"),
            config=config,
            sandbox_controller=self.sandbox_controller,
            audit_logger=self.audit_logger
        )
        
        await session.start()
        
        # 注入执行实例上下文
        await session.send_command(f"export EXECUTION_INSTANCE_ID={instance.execution_instance_id}")
        await session.send_command(f"export TRACE_ID={instance.trace_id}")
        await session.send_command(f"export LAYER={instance.layer}")
        await session.send_command(f"export DSL_PATH={instance.dsl_path}")
        
        return session
    
    async def handle_command(self, session_id: str, command: str, user_profile: str):
        """处理控制命令（pause/resume/inject）"""
        # 1. 解析命令
        cmd_type, args = self._parse_command(command)
        
        # 2. 权限验证 (Layer Profile)
        await self._validate_command_permission(cmd_type, user_profile)
        
        # 3. 执行控制
        if cmd_type == "pause":
            await self._pause_instance(session_id)
        elif cmd_type == "resume":
            await self._resume_instance(session_id)
        elif cmd_type == "inject":
            await self._inject_context(session_id, args)
        elif cmd_type == "state_write":
            await self._state_write(session_id, args)
```

### 3.3 Layer 5: xterm.js 终端增强

```typescript
// layer5/execution_instance_tree.ts
interface ExecutionInstanceNode {
  execution_instance_id: string;
  layer: "L4" | "L3" | "L2";
  dsl_path: string;
  status: "running" | "paused" | "completed" | "failed";
  attachable: boolean;
  pty_session_id?: string;
  children: ExecutionInstanceNode[];
  budget_ratio?: number;
  confidence_score?: number;
  risk_level?: string;
}

class ExecutionInstanceTreeView {
  private term: Terminal;
  private ws: WebSocket;
  private currentInstanceId: string | null = null;
  
  constructor(container: HTMLElement, sessionId: string) {
    this.term = new Terminal();
    this.term.open(container);
    this.ws = new WebSocket(`ws://l2/debug/instances?session_id=${sessionId}`);
    
    this.setupCommandHandlers();
    this.renderInstanceTree();
  }
  
  private setupCommandHandlers(): void {
    this.term.onData((data) => {
      if (data === '\r') {
        // Enter: 选择当前高亮实例 attach
        this.attachToSelectedInstance();
      } else if (data === 'k' || data === '\x1b[A') {
        // Up: 上移选择
        this.moveSelection(-1);
      } else if (data === 'j' || data === '\x1b[B') {
        // Down: 下移选择
        this.moveSelection(1);
      } else if (data === 'd') {
        // d: detach 当前实例
        this.detachFromCurrentInstance();
      } else if (data === 'r') {
        // r: 刷新实例树
        this.renderInstanceTree();
      }
    });
  }
  
  private async renderInstanceTree(): Promise<void> {
    // 获取实例树
    const response = await fetch(`/api/debug/instances?session_id=${this.sessionId}`);
    const tree = await response.json();
    
    this.term.clear();
    this.term.write(`\x1b[2J\x1b[H`);  // 清屏
    this.term.write(`\x1b[1m=== DSL Execution Instances ===\x1b[0m\r\n`);
    this.term.write(`Session ID: ${tree.session_id}\r\n`);
    this.term.write(`\r\n`);
    
    // 递归渲染树
    if (tree.root) {
      this.renderTreeNode(tree.root, 0);
    }
    
    this.term.write(`\r\n`);
    this.term.write(`\x1b[36m[↑/↓] Select  [Enter] Attach  [d] Detach  [r] Refresh\x1b[0m\r\n`);
  }
  
  private renderTreeNode(node: ExecutionInstanceNode, depth: number): void {
    const indent = "  ".repeat(depth);
    const icon = node.status === "running" ? "🟢" : 
                 node.status === "paused" ? "🟡" :
                 node.status === "completed" ? "✅" : "❌";
    
    const isSelected = node.execution_instance_id === this.currentInstanceId;
    const highlight = isSelected ? "\x1b[7m" : "";  // 反色高亮
    const reset = isSelected ? "\x1b[0m" : "";
    
    this.term.write(`${indent}${icon} ${highlight}${node.layer}: ${node.dsl_path}${reset}\r\n`);
    this.term.write(`${indent}   ID: ${node.execution_instance_id}\r\n`);
    this.term.write(`${indent}   Status: ${node.status}\r\n`);
    
    if (node.budget_ratio !== undefined) {
      this.term.write(`${indent}   Budget: ${(node.budget_ratio * 100).toFixed(0)}%\r\n`);
    }
    if (node.confidence_score !== undefined) {
      this.term.write(`${indent}   Confidence: ${(node.confidence_score * 100).toFixed(0)}%\r\n`);
    }
    if (node.risk_level) {
      this.term.write(`${indent}   Risk: ${node.risk_level}\r\n`);
    }
    
    this.term.write(`\r\n`);
    
    // 渲染子节点
    for (const child of node.children) {
      this.renderTreeNode(child, depth + 1);
    }
  }
  
  private async attachToSelectedInstance(): Promise<void> {
    if (!this.currentInstanceId) {
      this.term.write(`\x1b[31mNo instance selected\x1b[0m\r\n`);
      return;
    }
    
    // 创建 PTY 会话
    const response = await fetch(`/api/debug/instances/${this.currentInstanceId}/attach`, {
      method: "POST"
    });
    
    const { pty_session_id } = await response.json();
    
    // 切换到 PTY 终端模式
    this.switchToPtyMode(pty_session_id);
  }
  
  private switchToPtyMode(ptySessionId: string): void {
    // 创建新的 WebSocket 连接到 PTY 会话
    const ptyWs = new WebSocket(`ws://l2/debug/pty/${ptySessionId}`);
    
    ptyWs.onmessage = (event) => {
      // 显示 PTY 输出
      this.term.write(event.data);
    };
    
    this.term.onData((data) => {
      // 发送用户输入到 PTY
      ptyWs.send(JSON.stringify({ type: "input", data }));
    });
    
    this.term.write(`\x1b[32mAttached to instance ${this.currentInstanceId}\x1b[0m\r\n`);
  }
  
  private moveSelection(delta: number): void {
    // 在实例树中移动选择
    // 实现略
  }
  
  private detachFromCurrentInstance(): void {
    // 断开当前 PTY 连接，返回实例树视图
    this.currentInstanceId = null;
    this.renderInstanceTree();
  }
}
```

### 3.4 调试协议 (WebSocket)

| 消息类型 | 方向 | 说明 |  payload 示例 |
| :--- | :--- | :--- | :--- |
| `instance_tree` | S→C | 推送实例树结构 | `{ "root": {...}, "instances": [...] }` |
| `attach_request` | C→S | 请求 attach 实例 | `{ "instance_id": "exec_l2_001" }` |
| `attach_response` | S→C | 返回 PTY 会话 ID | `{ "pty_session_id": "pty_003" }` |
| `pty_io` | 双向 | PTY 输入输出流 | `{ "data": "ls -la\n" }` |
| `control_command` | C→S | 控制命令 (pause/resume) | `{ "cmd": "pause", "instance_id": "..." }` |
| `state_write` | C→S | 状态写入 (通过工具) | `{ "path": "memory.state.x", "value": 1 }` |
| `instance_status` | S→C | 实例状态变更通知 | `{ "instance_id": "...", "status": "paused" }` |

---

## 4. 安全与权限设计

### 4.1 Layer Profile 权限映射

调试是高风险操作，需经过 Layer Profile 验证。

| 操作类型 | Cognitive Profile (L4) | Thinking Profile (L3) | Workflow Profile (L2) |
| :--- | :--- | :--- | :--- |
| `state.read` | ✅ 允许 | ✅ 允许 | ✅ 允许 |
| `state.write` | ✅ 允许 | ❌ 禁止 | ⚠️ 受限 (沙箱/声明路径) |
| `state.delete` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |
| `state.temp_write` | ✅ 允许 | ✅ 允许 (临时工作区) | ✅ 允许 (临时工作区) |
| `security.*` | ✅ 允许 | ❌ 禁止 | ❌ 禁止 |

### 4.2 干预合法性验证

所有用户输入命令必须经过 `ControlValidator` 验证。

```python
# layer2/control_validator.py
class ControlValidator:
    def validate(self, session, command):
        # 1. 检查会话权限
        if session.profile not in ["Cognitive", "Debug"]:
            raise SecurityError("ERR_DEBUG_PERMISSION_DENIED")
        
        # 2. 检查命令白名单
        allowed_cmds = ["continue", "step", "inject", "state_write", "quit"]
        if command.cmd not in allowed_cmds:
            raise SecurityError("ERR_DEBUG_INVALID_COMMAND")
        
        # 3. 检查状态写入路径 (Layer Profile)
        if command.cmd == "state_write":
            if not command.path.startswith("memory.state."):
                raise SecurityError("ERR_DEBUG_STATE_PATH_FORBIDDEN")
            # 验证当前 Profile 是否允许写该路径
            if not self._check_layer_profile(session.profile, command.path):
                raise SecurityError("ERR_DEBUG_PROFILE_VIOLATION")
        
        # 4. 记录审计日志
        self.audit_logger.log_intervention(session.user_id, command)
        
        return True
```

### 4.3 审计日志

所有调试操作必须记录到 Layer 1 Trace，包含 `execution_instance_id`。

```json
{
  "trace_id": "trace_abc",
  "execution_instance_id": "exec_l2_001",
  "event_type": "debug_intervention",
  "user_id": "user_456",
  "session_id": "sess_789",
  "command": "state_write",
  "path": "memory.state.override_flag",
  "value": "true",
  "validation_result": "passed",
  "timestamp": "2026-02-25T10:00:00Z"
}
```

---

## 5. 执行流程示例

1.  **启动调试**：
    *   用户在 Layer 5 打开 xterm.js 终端。
    *   输入 `agentic debug workflow.dsl --session sess_789`。
    *   Layer 5 请求 Layer 2 获取实例树。
2.  **选择实例**：
    *   终端展示 L4→L3→L2 实例树。
    *   用户选择 `exec_l2_001` 并按 Enter。
3.  **Attach 会话**：
    *   Layer 2 创建/复用 PTY 会话 `pty_003`。
    *   Layer 5 切换到 PTY 终端模式，显示 L2 实例输出。
4.  **人工干预**：
    *   用户在终端输入 `pause`。
    *   Layer 2 验证权限，暂停实例。
    *   用户输入 `state_write memory.state.x=1`。
    *   Layer 2 通过 `StateToolAdapter` 写入状态，记录审计日志。
5.  **恢复执行**：
    *   用户输入 `continue`。
    *   实例恢复执行，完成剩余节点。
    *   实例结束，PTY 会话关闭，终端返回实例树视图。

---

## 6. 实施路线图

| 阶段 | 任务 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| **Phase 1** | 执行实例管理器 | 实例创建/查询/树形结构可用 | Layer-2-Spec-v2.2 |
| **Phase 2** | 跨层调用协议扩展 | L4→L3→L2 父子关系追踪正确 | Layer-3/4-Spec-v2.2 |
| **Phase 3** | xterm.js 实例树视图 | 实例树展示/选择/attach 可用 | Layer-5-Spec-v2.2 |
| **Phase 4** | PTY 会话集成 | 每个实例独立 PTY 沙箱 | Layer-2-Spec-v2.2 |
| **Phase 5** | 全链路追踪集成 | trace_id 贯穿所有实例 | Observability-Spec-v2.2 |
| **Phase 6** | 全链路压测 | 实例管理开销 <10ms | All Specs |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
| :--- | :--- | :--- |
| **死锁** | 调试会话阻塞导致资源耗尽 | 会话超时自动终止，最大并发会话限制 |
| **状态篡改** | 用户注入非法状态破坏逻辑 | 严格 Layer Profile 验证，只允许白名单路径 |
| **性能开销** | 调试钩子影响生产性能 | 调试模式编译开关，生产环境默认禁用 |
| **信息泄露** | Trace 流暴露敏感数据 | 敏感字段脱敏，Debug Profile 权限控制 |
| **沙箱逃逸** | 调试命令执行系统指令 | 命令白名单，禁止 `shell_exec` 类命令 |

---

## 8. 性能指标

| 指标 | 目标 | 测试条件 | 备注 |
| :--- | :--- | :--- | :--- |
| 实例创建延迟 | <100ms | PTY 沙箱创建 | Layer 2 |
| 命令执行延迟 | <50ms | 简单命令 | Layer 2 |
| IO 流式延迟 | <100ms | WebSocket 传输 | Layer 5 |
| 实例树查询 | <10ms | 缓存命中 | Layer 2 |
| 审计日志写入 | <10ms | 异步写入 | Layer 1 |
| WebSocket 并发 | 100+ | 同时连接 | Layer 5 |

---

## 9. 测试策略

### 9.1 单元测试

```python
# test_execution_instance.py
import pytest
from layer2.execution_instance_manager import ExecutionInstanceManager

class TestExecutionInstance:
    """测试执行实例管理"""
    
    async def test_create_instance_tree(self):
        """验证实例树创建"""
        manager = ExecutionInstanceManager()
        
        # 创建 L4 实例
        l4_inst = manager.create_instance("L4", "/lib/cognitive/routing", "trace_1", "sess_1")
        
        # 创建 L3 实例 (父实例为 L4)
        l3_inst = manager.create_instance("L3", "/lib/thinking/react", "trace_1", "sess_1", parent_instance_id=l4_inst.execution_instance_id)
        
        # 创建 L2 实例 (父实例为 L3)
        l2_inst = manager.create_instance("L2", "/lib/workflow/code", "trace_1", "sess_1", parent_instance_id=l3_inst.execution_instance_id)
        
        # 验证树形结构
        tree = manager.get_instance_tree("trace_1")
        assert tree["root"]["execution_instance_id"] == l4_inst.execution_instance_id
        assert len(tree["root"]["children"]) == 1
        assert tree["root"]["children"][0]["execution_instance_id"] == l3_inst.execution_instance_id
    
    async def test_attach_instance(self):
        """验证实例 attach"""
        manager = ExecutionInstanceManager()
        adapter = DebugShellAdapter(manager, ...)
        
        inst = manager.create_instance("L2", "/lib/workflow/code", "trace_1", "sess_1")
        manager.update_status(inst.execution_instance_id, InstanceStatus.RUNNING)
        
        result = await adapter.attach_instance(inst.execution_instance_id, "user_1")
        assert "pty_session_id" in result
```

### 9.2 集成测试

```python
# test_integration.py
import pytest
from layer5.execution_instance_tree import ExecutionInstanceTreeView

class TestWebSocketIntegration:
    """测试 WebSocket 集成"""
    
    async def test_instance_tree_via_websocket(self):
        """验证通过 WebSocket 获取实例树"""
        # 模拟客户端连接
        async with websockets.connect("ws://localhost:8765/instances?session_id=sess_1") as ws:
            # 发送获取请求
            await ws.send(json.dumps({
                "message_type": "get_instance_tree",
                "session_id": "sess_1"
            }))
            
            # 接收响应
            response = json.loads(await ws.recv())
            
            assert response["message_type"] == "instance_tree"
            assert "root" in response
```

---

## 10. 版本管理

### 10.1 版本映射

| 对外版本 | 内部版本 | 说明 |
| :--- | :--- | :--- |
| v2.2.0 | Arch v2.2 | 当前（支持实例树/统一标识符） |
| v2.3.0 | Arch v2.3 | 规划中（多用户协作调试） |
| v3.0.0 | Arch v3.0 | 愿景（分布式调试） |

### 10.2 向后兼容

- 接口契约 5 年稳定（`ExecutionInstanceManager`）
- WebSocket 协议保持向后兼容
- 废弃接口提前 1 年通知
- 实例状态格式版本化，支持多版本共存

---

## 11. 与 AgenticOS 文档的引用关系

| DSL-Console-Spec 章节 | AgenticOS 文档引用 | 说明 |
| :--- | :--- | :--- |
| Section 2 (架构设计) | Architecture-v2.2#Sec-1.1 | 八层架构 |
| Section 3 (实例管理) | Layer-2-Spec-v2.2#Sec-2.3 | ExecutionInstanceManager |
| Section 3 (Shell 适配) | Layer-2-Spec-v2.2#Sec-5 | SandboxController |
| Section 3 (终端视图) | Layer-5-Spec-v2.1.1#Sec-3 | TerminalComponent |
| Section 4 (安全约束) | Security-Spec-v2.2#Sec-3 | Layer Profile |
| Section 4 (审计日志) | Layer-1-Spec-v2.1.1#Sec-3 | AuditLogger |
| Section 8 (性能指标) | Observability-Spec-v2.1.1#Sec-8 | SLO 体系 |
| Section 9 (测试策略) | Security-Spec-v2.2#Sec-12 | 安全测试 |

---

## 12. 实施路线图

### 12.1 Phase 1（核心功能）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | 执行实例管理器 | 实例创建/查询/树形结构可用 | Layer-2-Spec-v2.2 |
| W3-4 | 跨层调用协议 | L4→L3→L2 父子关系追踪正确 | Layer-3/4-Spec-v2.2 |
| W5-6 | xterm.js 实例树视图 | 实例树展示/选择/attach 可用 | Layer-5-Spec-v2.2 |
| W7-8 | PTY 会话集成 | 每个实例独立 PTY 沙箱 | Layer-2-Spec-v2.2 |

### 12.2 Phase 2（安全增强）

| 周次 | 里程碑 | 验收标准 | 依赖 |
| :--- | :--- | :--- | :--- |
| W1-2 | 命令过滤 | 危险命令 100% 拦截 | Security-Spec-v2.2 |
| W3-4 | 权限验证 | Layer Profile 验证 100% 生效 | Security-Spec-v2.2 |
| W5-6 | 审计日志 | 100% 操作持久化 | Layer-1-Spec-v2.1.1 |
| W7-8 | 安全渗透测试 | P0 告警路径 100% 通过 | Security-Spec-v2.2 |

---

## 13. 风险与缓解

| 风险 | 影响 | 缓解措施 | 责任人 | 对齐依据 |
| :--- | :--- | :--- | :--- | :--- |
| **沙箱逃逸** | 系统被攻破 | 多层防护 + 渗透测试 | 安全负责人 | Security-v2.2#Sec-2.2.2 |
| **IO 流延迟** | 用户体验下降 | WebSocket 优化 + 本地缓冲 | Layer 5 负责人 | Layer-5-Spec-v2.1.1#Sec-8 |
| **实例状态泄露** | 用户数据曝光 | 端侧加密 + 访问控制 | 安全负责人 | Security-v2.2#Sec-4 |
| **命令注入** | 恶意命令执行 | 命令过滤 + 白名单验证 | Layer 2 负责人 | Layer-2-Spec-v2.2#Sec-6 |
| **审计日志丢失** | 无法追溯 | 异步写入 + 重试机制 | Layer 1 负责人 | Layer-1-Spec-v2.1.1#Sec-3 |
| **WebSocket 断连** | 会话中断 | 自动重连 + 本地缓存 | Layer 5 负责人 | Layer-5-Spec-v2.1.1#Sec-7 |
| **资源耗尽** | 系统不稳定 | 会话配额限制 + 超时终止 | Layer 2 负责人 | Layer-2-Spec-v2.2#Sec-5 |

---

## 14. 附录：错误码

| 错误码 | 含义 | 处理建议 |
| :--- | :--- | :--- |
| `ERR_INSTANCE_NOT_FOUND` | 实例不存在 | 检查 execution_instance_id |
| `ERR_INSTANCE_NOT_ATTACHABLE` | 实例不可 attach | 检查实例状态 |
| `ERR_PERMISSION_DENIED` | 权限不足 | 验证用户归属权 |
| `ERR_COMMAND_INVALID` | 命令无效 | 检查命令白名单 |
| `ERR_COMMAND_FORBIDDEN` | 命令被禁止 | 检查 Layer Profile |
| `ERR_IO_STREAM_ERROR` | IO 流错误 | 检查 WebSocket 连接 |
| `ERR_INSTANCE_TIMEOUT` | 实例超时 | 增加 timeout_sec |
| `ERR_AUDIT_LOG_FAILED` | 审计日志失败 | 检查存储连接 |
| `ERR_LAYER_PROFILE_VIOLATION` | Layer Profile 违规 | 检查 Profile 声明 |
| `ERR_SANDBOX_ESCAPE_DETECTED` | 沙箱逃逸检测 | 安全审计 |

---

## 15. 总结

AgenticOS v2.2 DSL 执行控制台提供：

1.  **全链路可见**：DSL 节点执行流实时推送到终端，延迟 <100ms。
2.  **实例树管理**：统一展示 L4→L3→L2 执行实例，支持 attach 到任意实例。
3.  **安全控制**：`pause`/`inject` 命令经过 Layer Profile 验证，非法操作被拦截。
4.  **工具化干预**：`inject` 命令底层调用 `state.write`，记录审计日志。
5.  **生命周期绑定**：终端会话随 DSL 执行实例结束而关闭，无残留会话。
6.  **架构一致**：符合 v2.2 DSL-Centric、状态工具化、Layer Profile 安全模型。

**核心批准条件：**
1.  **标识符统一**：Section 2.2 明确取消 `debug_session_id`，使用 `session_id` + `execution_instance_id`。
2.  **实例树追踪**：Section 3.1 明确 L4→L3→L2 父子实例关系管理。
3.  **安全验证**：Section 4 明确控制命令的 Layer Profile 验证流程。
4.  **审计完整**：Section 4.3 明确 100% 操作日志记录，包含 `execution_instance_id`。
5.  **性能指标达标**：Section 8 明确实例创建<100ms、IO 流式延迟<100ms 等 SLO。

通过严格的接口契约与安全约束，确保交互式会话的安全性、可用性与可演进性，为用户提供类似 tmux 的终端体验，同时保持 AgenticOS v2.2 架构的安全性和一致性。

---

文档结束
版权：AgenticOS 架构委员会
许可：CC BY-SA 4.0 + 专利授权许可