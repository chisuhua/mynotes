# AOS-Universal 架构扩展评审：从浏览器自动化到通用操作型智能体

**结论：** 当前的 **AOS-Browser v2.0 (强内核 + 灵活外壳)** 架构 **完全支持** 扩展为通用操作型应用（General Operational Agent），但需要对 **Layer 0 (工具执行)** 和 **Layer 3 (任务编排)** 进行针对性增强。核心内核（中断、协程、持久化）无需改动，可直接复用。

以下是针对您提出的需求（工具调用、同步/异步、沙箱、多任务、依赖树）的详细架构演进方案。

---

## 一、架构演进映射表

| 需求 | 当前 AOS-Browser v2.0 状态 | **AOS-Universal v3.0 扩展方案** | 涉及层级 |
| :--- | :--- | :--- | :--- |
| **通用工具调用** | 仅支持 Browser Actions (Click/Type) | **统一 Tool Interface** (File, Shell, API, Browser) | Layer 0 & 2 |
| **执行方式** | 异步 (Playwright) | **同步/异步自适应** (线程池封装同步工具) | Layer 0 & 2 |
| **沙箱安全** | 仅浏览器隔离 | **多模式沙箱** (WASM / Docker / Process) | Layer 0 |
| **多任务并行** | 多标签页 (TabCoordinator) | **任务组 (TaskGroup)** + 资源配额 | Layer 1 & 3 |
| **依赖关系** | 无 (线性 ReAct) | **DAG 工作流** (Fork/Join 语义) | Layer 3 |
| **状态持久化** | BrowserSnapshot | **EnvironmentSnapshot** (文件树/进程态/变量) | Layer 2 |

---

## 二、核心模块增强设计

### 2.1 Layer 0: 沙箱化通用工具执行器 (Sandboxed Tool Executor)

将浏览器操作降级为一种普通工具，引入统一执行接口，支持同步/异步透明化。

```cpp
// layer0/tool_executor.h
enum class ToolType { BROWSER, SHELL, FILESYSTEM, API, CUSTOM };
enum class ExecutionMode { SYNC, ASYNC };

struct ToolRequest {
    std::string tool_id;
    ToolType type;
    std::string command;      // 如 "read_file", "click_button"
    nlohmann::json parameters;
    ExecutionMode mode;       // 用户声明或自动推断
    uint32_t timeout_ms;
};

struct ToolResult {
    int exit_code;
    std::string output;
    std::string error;
    bool is_async_complete;   // 异步任务是否完成
};

// 核心执行器：支持沙箱隔离
class SandboxedToolExecutor {
public:
    // 统一入口：协程友好，同步工具内部自动转异步
    Task<ToolResult> Execute(const ToolRequest& req) {
        // 1. 安全校验 (Layer 2 SecurityManager 前置检查)
        if (!security_mgr_.VerifyToolPermission(req.tool_id)) {
            co_return ToolResult{.exit_code = -1, .error = "Permission Denied"};
        }

        // 2. 选择沙箱环境
        auto sandbox = SelectSandbox(req.type); // WASM / Docker / Process
        
        // 3. 执行 (同步工具在线程池运行，避免阻塞协程)
        if (req.mode == ExecutionMode::SYNC) {
            co_return co_await ThreadPool::Run([sandbox, req]() {
                return sandbox->RunSync(req); // 阻塞调用
            });
        } else {
            co_return co_await sandbox->RunAsync(req); // 事件回调
        }
    }

private:
    std::unique_ptr<Sandbox> SelectSandbox(ToolType type) {
        switch (type) {
            case SHELL: return std::make_unique<DockerSandbox>(); // 高风险
            case FILESYSTEM: return std::make_unique<ChrootSandbox>(); // 中风险
            case BROWSER: return std::make_unique<BrowserSandbox>(); // 低风险
            default: return std::make_unique<WasmSandbox>(); // 高性能
        }
    }
};
```

**关键设计点**：
1.  **透明异步**：上层协程无需关心工具是同步还是异步，`Execute` 统一返回 `Task<ToolResult>`。
2.  **沙箱隔离**：高风险操作（脚本执行）使用 Docker/Process 隔离，低风险（文件读写）使用 Chroot 或权限控制。
3.  **超时控制**：每个工具调用自带超时，防止死锁。

---

### 2.2 Layer 2: 支持 Fork/Join 的协程任务组

在 `CognitiveEngine` 之上增加 `TaskGroup` 抽象，支持并行任务与依赖管理。

```cpp
// layer2/task_group.h
class TaskGroup {
public:
    // Fork: 启动子任务 (不阻塞)
    TaskHandle Fork(std::string task_id, std::string goal) {
        auto engine = std::make_unique<CognitiveEngine>(task_id, goal);
        auto handle = engine->Start(); // 返回协程句柄
        children_.push_back(std::move(engine));
        return handle;
    }

    // Join: 等待所有子任务完成 (阻塞当前协程)
    Task<std::vector<ToolResult>> Join() {
        std::vector<Task<ToolResult>> tasks;
        for (auto& child : children_) {
            tasks.push_back(child->GetResult());
        }
        // std::when_all 等待所有子协程完成
        co_return co_await std::when_all(tasks.begin(), tasks.end());
    }

    // Dependency: 等待特定任务完成
    Task<void> WaitFor(const TaskHandle& handle) {
        co_await handle.GetResult();
    }

private:
    std::vector<std::unique_ptr<CognitiveEngine>> children_;
};
```

**ReAct 循环中的使用示例**：
```cpp
Task<void> UniversalAgent::RunComplexWorkflow() {
    TaskGroup group;

    // 1. Fork: 并行收集信息 (无依赖)
    auto h1 = group.Fork("task_1", "Read config.yaml");
    auto h2 = group.Fork("task_2", "Check network status");
    
    // 2. Join: 等待收集完成
    auto results = co_await group.Join();

    // 3. 基于结果决策
    if (results[0].exit_code == 0) {
        // 4. 串行执行 (有依赖)
        co_await tool_executor_.Execute({.command = "deploy_script.sh"});
    }
}
```

---

### 2.3 Layer 3: 工作流编排器 (Workflow Orchestrator)

针对有依赖关系的任务树，引入轻量级 DAG 管理器。

```cpp
// layer3/workflow_orchestrator.h
struct TaskNode {
    std::string id;
    std::vector<std::string> dependencies; // 前置任务 ID
    std::string goal;
    TaskState state = PENDING;
};

class WorkflowOrchestrator {
public:
    // 加载任务树
    void LoadDAG(const std::vector<TaskNode>& nodes);

    // 调度：返回当前可执行的任务列表 (依赖已满足)
    std::vector<std::string> GetReadyTasks() {
        std::vector<std::string> ready;
        for (auto& node : nodes_) {
            if (node.state == PENDING && AllDepsCompleted(node)) {
                ready.push_back(node.id);
            }
        }
        return ready;
    }

    // 通知任务完成，触发后续任务
    void OnTaskCompleted(const std::string& task_id) {
        nodes_[task_id].state = COMPLETED;
        // 通知 Layer 1 调度器有新任务可运行
        event_bus_.Publish({type: TASK_READY});
    }

private:
    bool AllDepsCompleted(const TaskNode& node) {
        for (const auto& dep : node.dependencies) {
            if (nodes_[dep].state != COMPLETED) return false;
        }
        return true;
    }
    std::unordered_map<std::string, TaskNode> nodes_;
};
```

---

### 2.4 Layer 2: 通用环境快照 (Environment Snapshot)

将 `BrowserSnapshot` 泛化为 `EnvironmentSnapshot`，支持文件系统和进程状态。

```cpp
// layer2/environment_snapshot.h
struct EnvironmentSnapshot {
    // 1. 浏览器状态 (兼容旧版)
    std::optional<BrowserSnapshot> browser;

    // 2. 文件系统状态 (新增)
    struct FileSystemState {
        std::string working_directory;
        std::vector<std::string> modified_files; // 记录变更文件路径
        std::unordered_map<std::string, std::string> file_hashes; // 关键文件哈希
    } filesystem;

    // 3. 进程/变量状态 (新增)
    struct ExecutionContext {
        std::unordered_map<std::string, std::string> environment_vars;
        std::vector<int> spawned_process_ids; // 跟踪子进程
    } execution;

    // 序列化用于持久化
    nlohmann::json ToJson() const;
};
```

**恢复策略**：
*   **文件恢复**：若任务失败，可根据 `modified_files` 列表从备份恢复文件内容。
*   **进程清理**：恢复时检查 `spawned_process_ids`，清理遗留僵尸进程。

---

## 三、更新后的顶层架构图 (AOS-Universal v3.0)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 3: Meta-Cognition & Orchestration (元认知与编排层)             │
│ ├─ WorkflowOrchestrator   │ DAG 管理 / Fork/Join 依赖解析            │
│ ├─ GoalDriftDetector      │ 目标漂移检测 (通用任务)                  │
│ ├─ TaskGroupCoordinator   │ 多任务资源配额 / 优先级协调              │
│ └─ LocalMetricsCollector  │ 指标收集                                 │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ 策略注入 / 任务调度
┌───────────────────────────▼─────────────────────────────────────────┐
│ Layer 2: Cognitive Kernel (认知内核层)                               │
│ ├─ PreemptibleReActEngine  │ 协程化 ReAct (支持 TaskGroup)           │
│ ├─ UniversalToolAdapter    │ 【新增】统一工具接口 (Browser/Shell/FS) │
│ ├─ EnvironmentSnapshotMgr  │ 【增强】文件/进程/浏览器状态快照        │
│ ├─ PersistentContext       │ SQLite 状态存储                         │
│ └─ SecurityManager         │ 权限校验 / 敏感操作审计                 │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ 事件驱动 / 协程调度
┌───────────────────────────▼─────────────────────────────────────────┐
│ Layer 1: Event & Control (事件与控制层)                              │
│ ├─ LightweightInterruptQueue │ 原子信号中断                         │
│ ├─ EventBus                │ 内部事件总线 (ToolComplete/TaskReady)  │
│ ├─ MLFQ_T_Scheduler        │ 【新增】多任务 Token 预算调度           │
│ └─ RecoveryManager         │ 崩溃恢复 (清理进程/恢复文件)            │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ 系统调用 / 资源管理
┌───────────────────────────▼─────────────────────────────────────────┐
│ Layer 0: Runtime & Sandbox (运行时与沙箱层)                          │
│ ├─ SandboxedToolExecutor   │ 【新增】Docker/WASM/Process 沙箱        │
│ ├─ PlaywrightAdapter       │ 浏览器工具实现                          │
│ ├─ ShellExecutor           │ 脚本执行实现                            │
│ ├─ FileSystemWatcher       │ 文件变更监听                            │
│ └─ SQLiteStorage           │ 状态存储                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 四、关键问题解决方案

### 4.1 同步工具如何不阻塞协程？
*   **方案**：在 `SandboxedToolExecutor` 内部维护一个 **专用线程池**。
*   **实现**：当检测到工具是同步阻塞 IO（如大文件读写）时，将其提交到线程池，协程 `co_await` 线程池的 `Future`。
*   **代码**：
    ```cpp
    // 内部实现
    Task<ToolResult> RunSyncInThread(std::function<ToolResult()> blocking_call) {
        co_return co_await thread_pool_.Submit(blocking_call); // 挂起协程，线程池执行
    }
    ```

### 4.2 多任务并行如何资源隔离？
*   **方案**：复用 AOS-Gateway 的 **MLFQ-T 调度器**。
*   **实现**：每个用户任务是一个 `TaskControlBlock`，分配独立的 Token 预算和内存配额。
*   **限制**：`TaskGroupCoordinator` 监控总资源，若某任务组占用过高，降低其优先级或暂停非关键子任务。

### 4.3 沙箱执行的安全性如何保障？
*   **方案**：分层沙箱策略。
    *   **高风险 (Shell/Script)**: Docker 容器 (网络隔离，文件系统只读挂载)。
    *   **中风险 (File IO)**: Chroot  jail + 白名单路径。
    *   **低风险 (API/Calc)**: WASM 沙箱 (确定性执行，无系统调用)。
*   **审计**：所有工具调用通过 `SecurityManager` 记录审计日志（Layer 2）。

### 4.4 任务依赖树 (DAG) 如何持久化？
*   **方案**：在 SQLite 中增加 `task_dependencies` 表。
*   **恢复**：崩溃恢复时，`RecoveryManager` 重建 DAG 状态，仅重跑 `PENDING` 且依赖已满足的节点，`COMPLETED` 节点直接跳过。

---

## 五、实施路线图建议

| 阶段 | 目标 | 关键任务 | 预计周期 |
| :--- | :--- | :--- | :--- |
| **Phase 1** | **工具抽象化** | 定义 `UniversalToolAdapter` 接口，将 Browser 操作 refactor 为工具之一 | 1 周 |
| **Phase 2** | **沙箱执行器** | 实现 `SandboxedToolExecutor` (先支持 Process/Docker)，集成线程池 | 2 周 |
| **Phase 3** | **任务组支持** | 实现 `TaskGroup` (Fork/Join)，支持多任务并行 | 1 周 |
| **Phase 4** | **工作流编排** | 实现 `WorkflowOrchestrator` (DAG 管理)，支持依赖恢复 | 2 周 |
| **Phase 5** | **通用快照** | 扩展 `EnvironmentSnapshot` 支持文件/进程状态 | 1 周 |

---

## 六、结论

**当前架构具备极高的扩展性**，只需将 "浏览器" 视为一种 "工具"，将 "标签页" 视为一种 "任务组"，即可平滑演进为通用操作型智能体架构。

**核心优势保留**：
1.  **强内核稳定性**：中断、持久化、协程调度机制无需改动，直接复用。
2.  **安全沙箱**：新增 Layer 0 沙箱层，弥补通用操作的安全风险。
3.  **灵活编排**：Layer 3 增加 DAG 编排，支持复杂依赖任务树。

**建议下一步**：
基于此 v3.0 通用架构，输出 **`AOS-Universal-Tool-Interface.md`**，定义标准工具协议（输入/输出/沙箱配置），并实现第一个非浏览器工具（如 `FileSystemTool`）作为验证。