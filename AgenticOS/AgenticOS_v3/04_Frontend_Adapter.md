# 04_Frontend_Adapter.md

> **文档版本**: v1.0  
> **对应协议**: WebSocket v2.1  
> **对应引擎**: AgenticOS v3.10-PE / LocalAI Core v2.1-P0+  
> **目标读者**: 前端开发者、UX设计师、系统集成商  
> **设计原则**: 用户仅感知 Session 与消息流；Instance/Branch/Budget 仅调试可见

---

## 文档摘要

| 项目 | 内容 |
|------|------|
| **用户视角** | 对话式交互（Session → Message），无执行实例概念 |
| **调试视角** | DAG 可视化（Instance → Branch → Node），完整执行拓扑 |
| **多模态策略** | 用户看到"内容"（图片/音频），看不到"文件路径"或"资源ID" |
| **部署双模** | 本地模式与远程 SSH 模式对用户无差异感知 |
| **安全边界** | 前端零特权；临时资源自动清理；用户不可访问引擎内部路径 |

---

## 1. 用户通信契约

用户与引擎的交互基于 **Session**（对话上下文）和 **Message**（消息气泡）。后台的 ExecutionInstance、Branch、预算控制等技术概念**对用户完全透明**。

### 1.1 WebSocket 连接与路径

| 路径 | 用户场景 | 说明 |
|------|----------|------|
| `/stream` | 对话与内容生成 | 收发消息流，支持文本/图像/音频 |
| `/fs` | 大文件获取 | 获取生成的图片、音频文件（用户无感知路径） |
| `/config` | 用户偏好设置 | 主题、布局、快捷键等持久化配置 |

> **约束**：引擎始终绑定 `127.0.0.1`，远程访问通过 SSH 隧道（端口映射到本地）。

### 1.2 消息格式（用户模式）

用户可见的消息仅包含 `session_id`（会话标识）和 `message_id`（消息标识，用于前端排序与去重）。

**文本内容流**：
```json
{
  "type": "content_chunk",
  "session_id": "sess_abc123",
  "message_id": "msg_789",
  "content_part": {
    "type": "text",
    "text": "生成的文本内容..."
  }
}
```

**图像生成完成**：
```json
{
  "type": "content_complete",
  "session_id": "sess_abc123",
  "message_id": "msg_790",
  "content_part": {
    "type": "image",
    "image": {
      "url": "blob://internal-ref-001",  // 前端通过 /fs 获取的实际访问令牌
      "mime_type": "image/png",
      "size": [1024, 1024]
    }
  }
}
```

**音频转录结果**：
```json
{
  "type": "content_complete",
  "session_id": "sess_abc123", 
  "message_id": "msg_791",
  "content_part": {
    "type": "audio",
    "audio": {
      "url": "blob://internal-ref-002",
      "duration_sec": 15.5
    },
    "text": "转录的文本内容..."
  }
}
```

**UX 规范**：
- **加载状态**：当内容未生成完成时，前端显示占位符（如灰色脉冲框），不暴露任何技术 ID
- **自动清理**：`blob://` 引用的临时文件在 Session 终止后自动失效，前端无需管理生命周期

### 1.3 用户任务状态

用户发起的每个"提问"或"指令"对应一个**用户任务**，引擎后台可能映射为多个 ExecutionInstance（如自动触发的子任务），但前端始终呈现为单一消息流。

**任务状态通知**：
```json
{
  "type": "task_status",
  "session_id": "sess_abc123",
  "message_id": "msg_790",
  "status": "generating",  // thinking | generating | completed | failed
  "progress": 75           // 可选，0-100，用于进度条（仅多模态生成时提供）
}
```

---

## 2. 部署与连接

用户通过统一界面访问引擎，无需感知本地或远程差异。

### 2.1 本地桌面模式（Tauri）

引擎作为 Tauri Sidecar 进程启动，前端通过本地 WebSocket 连接。

**启动流程**：
1. Tauri 启动 Sidecar（`agentic_os_core` 二进制）
2. 引擎报告端口（stdout: `SYSTEM_READY:PORT=xxxx`）
3. 前端注入端口配置，建立 WebSocket 连接
4. 协议握手（v2.1）后进入就绪状态

**用户感知**：双击应用图标，直接开始对话。

### 2.2 远程 SSH 模式

通过 Tauri 层建立 SSH 隧道，前端连接本地映射端口。

**用户操作**：
- 选择"远程连接"，输入主机地址与用户名
- Tauri 自动建立隧道（`ssh -L 9001:127.0.0.1:9001 user@host`）
- 前端连接 `ws://127.0.0.1:9001/stream`

**用户感知**：与本地模式完全一致，延迟可能略高但界面无差异。

### 2.3 连接状态管理

前端通过以下状态提示用户：

| 状态 | 界面提示 | 说明 |
|------|----------|------|
| `connecting` | "正在连接..." | 初始握手阶段 |
| `ready` | 输入框可用 | 正常对话状态 |
| `backpressure` | "服务器繁忙，请稍候..." | 应用层背压触发（Token 堆积） |
| `reconnecting` | "连接中断，正在重连..." | 网络波动，自动重试 |

---

## 3. 错误处理（面向用户）

错误以 **Session 级广播** 形式推送，关联到具体的用户消息（`message_id`），避免暴露内部 Instance 失败细节。

### 3.1 Session 错误通知

当后台执行失败时，引擎向该 Session 的所有前端连接推送：

```json
{
  "type": "session_error",
  "session_id": "sess_abc123",
  "error_context": {
    "message_id": "msg_790",           // 关联到用户可见的消息气泡
    "user_facing_code": "TASK_TOO_COMPLEX",
    "title": "任务过于复杂",
    "message": "当前请求处理复杂度超出限制，建议拆分执行",
    "suggestion": "尝试将需求拆分为多个简单步骤",
    "actionable": true                 // 是否显示"重试"按钮
  }
}
```

### 3.2 用户友好错误码映射

| 用户错误码 | 场景 | 用户提示 | 建议操作 |
|------------|------|----------|----------|
| `TASK_TOO_COMPLEX` | 预算超限 | "任务太复杂，请简化后重试" | 拆分需求，减少生成步骤 |
| `RESOURCE_BUSY` | 资源池耗尽 | "AI 助手正忙，请稍后再试" | 等待后重试 |
| `GENERATION_FAILED` | 生成失败 | "内容生成失败" | 点击重试按钮 |
| `UNSUPPORTED_CONTENT` | 不支持的输入 | "无法处理此类型的内容" | 更换输入格式 |
| `VERSION_MISMATCH` | 协议版本不匹配 | "客户端版本过旧" | 升级应用 |

> **注意**：`user_facing_code` 由引擎根据原始错误码（如 `0x2003` DSL_BUDGET_EXCEEDED）映射而来，前端仅处理展示逻辑。

### 3.3 重试与恢复

对于 `actionable: true` 的错误，前端提供：
- **重试按钮**：重新发送相同请求（引擎将创建新的后台 Instance）
- **简化建议**：根据错误类型提示用户如何修改输入（如"请缩短描述"）

---

## 4. 文件与资源管理

用户与多模态内容的交互通过**抽象 URL**（如 `blob://internal-ref-001`）进行，实际文件路径对用户完全不可见。

### 4.1 大文件获取协议

前端通过 `/fs` 路径获取生成的媒体文件：

```json
// 前端请求（用户点击"查看原图"时触发）
{
  "type": "fetch_content",
  "ref": "blob://internal-ref-001",
  "format": "base64"  // 或 "blob"（二进制帧）
}

// 引擎响应
{
  "type": "content_data",
  "ref": "blob://internal-ref-001",
  "data": "iVBORw0KGgoAAAANSUhEUgAA...",
  "mime_type": "image/png"
}
```

**约束**：
- `ref` 为临时令牌，仅在 Session 生命周期内有效
- 禁止前端构造或猜测 `ref` 值（由引擎在 `content_complete` 中分配）
- 文件实际存储路径（如 `/tmp/agentic_os/...`）**绝不暴露**给前端

### 4.2 临时资源生命周期

- **自动创建**：多模态生成时自动创建临时文件
- **自动清理**：Session 终止（超时或用户关闭）后，引擎自动清理相关临时文件
- **用户无感知**：前端无需实现删除逻辑，也不提供"删除文件"按钮

---

## 5. 调试与开发附录（可选实现）

以下协议仅在**调试模式**下启用，普通用户界面不应暴露相关功能。

### 5.1 调试模式开关

通过 `/config` 路径启用调试视图：

```json
// 前端请求（开发者模式下显示"开启调试"开关）
{
  "type": "set_mode",
  "mode": "debug"  // 或 "normal"
}
```

### 5.2 执行拓扑可视化（/trace）

订阅后台 ExecutionInstance 与 Branch 的详细执行事件，用于 DAG 调试面板。

```json
// 订阅请求
{
  "type": "subscribe_trace",
  "session_id": "sess_abc123"  // 获取该 Session 下的所有 Instance
}

// Instance 创建事件
{
  "type": "trace_event",
  "event": "instance_created",
  "instance_id": "exec_l0_uuid123",
  "parent_instance_id": null,
  "trigger_message_id": "msg_790",
  "timestamp": "2026-03-09T10:00:00Z"
}

// Branch 启动事件（Fork 节点触发）
{
  "type": "trace_event",
  "event": "branch_started",
  "instance_id": "exec_l0_uuid123",
  "branch_id": "branch_001",
  "node_path": "/main/hypothesis_a",
  "sandbox_level": "L0"
}

// 节点完成事件
{
  "type": "trace_event",
  "event": "node_completed",
  "instance_id": "exec_l0_uuid123",
  "branch_id": "branch_001",
  "node_path": "/main/dsl_call",
  "duration_ms": 1523
}
```

### 5.3 预算与性能监控

调试模式下展示资源消耗细节：

```json
{
  "type": "budget_update",
  "instance_id": "exec_l0_uuid123",
  "budget": {
    "nodes_used": 12,
    "nodes_total": 20,
    "llm_calls_used": 3,
    "llm_calls_total": 10,
    "branches_active": 2
  }
}
```

### 5.4 调试控制接口

通过 `/debug` 路径实现断点调试：

```json
// 暂停特定 Instance
{
  "type": "debug_command",
  "command": "pause",
  "instance_id": "exec_l0_uuid123"
}

// 获取当前上下文快照（查看 Branch 内部状态）
{
  "type": "debug_command",
  "command": "inspect",
  "instance_id": "exec_l0_uuid123",
  "branch_id": "branch_001"
}
```

---

## 附录 A：与 LocalAI 的映射对照表

| LocalAI 概念 | AgenticOS 对应概念 | 前端适配说明 |
|--------------|-------------------|--------------|
| Chat Session | Session | 完全对应，复用现有 UI 组件 |
| Message | Message (`message_id`) | 增加 `message_id` 用于关联后台任务 |
| AI Response | `content_chunk` + `content_complete` | 流式接口一致，复用现有渲染逻辑 |
| Error Code | `session_error` | 增加 `user_facing_code` 层，映射逻辑不变 |
| Image URL (base64) | `blob://` 引用 + `/fs` 获取 | 小图可协商内联（兼容性模式），大图走 `/fs` |
| Settings | `/config` 路径 | 配置项扩展（增加 DSL 相关用户偏好） |
| Terminal (PTY) | `/pty` 路径 | 完全一致，复用 xterm.js 组件 |

**迁移检查清单**：
- [ ] 将轮询 API 改为 WebSocket 订阅（`content_chunk`）
- [ ] 将直接图片 URL 改为 `blob://` 引用 + `fetch_content` 获取
- [ ] 错误处理增加 `session_error` 消息类型监听
- [ ] 可选：增加"开发者模式"开关，集成 5. 章节的调试功能
