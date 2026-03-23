# AOS-Nexus 智能体架构设计 (Agent OS Nexus Architecture)

| 文档版本 | 1.0 |
| :--- | :--- |
| **状态** | 架构设计 (Architecture Design) |
| **日期** | 2024-05-20 |
| **定位** | 通用智能体运行时框架（浏览器自动化 + 工业网关） |

---

## 一、设计哲学与核心洞察

基于对 BAFA、Pie-Agent、ZeroClaw 及 AOS-Gateway 等架构的深度分析，本设计遵循以下核心原则：

### 1.1 架构演进洞察

| 架构范式 | 解决核心问题 | 局限性 | 本设计采纳 |
| :--- | :--- | :--- | :--- |
| **任务导向递归** | 简单脚本确定性工作流 | 无法中断、无法并发、无法处理外部事件 | ❌ 摒弃 |
| **事件驱动循环** | 并发/异步响应性 | 回调地狱、状态管理复杂 | ✅ 作为底层基础 |
| **BAFA 三层循环** | 崩溃恢复/硬实时安全 | 浏览器专用、复杂度高 | ✅ 分层思想 + 通用化 |
| **Pie-Agent 事件外壳** | 流式输出/Hooks 扩展 | 缺乏调度与持久化 | ✅ Hooks 机制 + 流式处理 |
| **AOS-Gateway 六指标** | 工业级 LLM 抢占与调度 | MCU 耦合、协程栈序列化陷阱 | ✅ 调度策略 + 业务状态持久化 |

### 1.2 核心设计原则

1.  **协程优先 (Coroutine-First)**：使用 C++20 协程编写同步风格的异步代码，避免回调地狱，同时支持挂起/恢复。
2.  **事件驱动底层 (Event-Driven Core)**：所有 IO、中断、用户输入均通过事件总线传递，确保响应性。
3.  **业务状态持久化 (Business State Persistence)**：仅持久化 ReAct 历史、IO 状态、LLM KV Cache 摘要，放弃协程栈镜像序列化。
4.  **分层中断处理 (Layered Interrupt)**：硬实时中断（<10μs）与软实时业务（<100ms）分离，确保安全性。
5.  **Token 预算调度 (Token Budget Scheduling)**：防止单一 Agent 独占 LLM 资源，支持多 Agent 并发。

---

## 二、总体架构：Nexus 四层模型

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 3: Meta-Cognition (元认知层)                                   │
│ ├─ GoalProximityMonitor (目标接近度检测)                             │
│ ├─ ContextCompaction (上下文压缩)                                    │
│ └─ DriftDetection (目标漂移检测)                                     │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 策略注入
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 2: Cognitive Coroutine (认知协程层)                            │
│ ├─ ReAct Engine (协程化 ReAct 循环)                                  │
│ ├─ Event Hooks (Pie-Agent 风格：before/after_tool_call)             │
│ ├─ Stream Handler (流式 Token 输出)                                  │
│ └─ Persistent Context (业务状态序列化)                               │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 协程调度
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 1: Event & Scheduler (事件与调度层)                            │
│ ├─ Event Bus (优先级事件队列：用户 > 系统 > 背景)                     │
│ ├─ MLFQ-T Scheduler (Token 预算 + 多级反馈队列)                      │
│ ├─ Interrupt Bridge (顶底分离：Signal → EventFD → Event Bus)        │
│ └─ Hibernate Manager (热/冷休眠控制)                                 │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 硬件/系统调用
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 0: IO & Runtime (IO 与运行时层)                                 │
│ ├─ LLM Adapter (llama.cpp 封装，支持 KV Cache 保存/恢复)             │
│ ├─ Browser Adapter (Playwright/CDP，支持页面快照)                    │
│ ├─ Device Adapter (Modbus/CAN/GPIO，工业网关场景)                    │
│ └─ SQLite Storage (WAL 模式，异步写入)                               │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 与旧架构的关键差异

| 特性 | AOS-u.md (旧) | AOS-Nexus (新) | 变更理由 |
| :--- | :--- | :--- | :--- |
| **分层模型** | 5 层 (Layer 0-4)，MCU 耦合 | 4 层 (Layer 0-3)，通用化 | 移除 MCU 裸机层，聚焦 Linux 用户态 |
| **持久化** | 协程栈镜像 + 业务状态 | **仅业务状态** (ReAct 历史/IO 状态/KV Cache) | 规避 C++20 协程栈序列化技术陷阱 |
| **调度器** | C 语言内核调度器 | C++ 用户态调度器 (MLFQ-T) | 降低复杂度，利用 Linux 内核调度 |
| **中断处理** | 统一 HAL 封装 | 信号 + eventfd + 事件总线 | 适配 Linux 用户态实时机制 |
| **LLM 集成** | 通用 Connector | llama.cpp 深度集成 (KV Cache 管理) | 支持本地模型抢占与恢复 |
| **适用场景** | MCU + Linux 全谱系 | **浏览器自动化 + 工业网关** | 聚焦高价值场景 |

---

## 三、核心模块设计

### 3.1 Layer 2: 认知协程层 (Cognitive Coroutine)

**设计目标**：提供同步风格的异步编程体验，支持可抢占 ReAct 循环。

```cpp
// nexus_agent.h
class NexusAgent {
public:
    // 主循环：协程化 ReAct
    Task<void> Run(const std::string& goal) {
        auto ctx = co_await CreateContext(goal);
        
        while (ctx.state != TaskState::COMPLETED) {
            // 检查点 1：可被 Layer 1 中断抢占
            if (co_await CheckInterrupt()) {
                co_await SaveCheckpoint(ctx);  // 保存业务状态
                co_await WaitForResumeSignal();
                continue;
            }
            
            // 检查点 2：Token 预算检查（MLFQ-T 调度）
            if (co_await CheckTokenBudgetExhausted()) {
                co_await YieldToNextAgent();  // 让出 CPU
            }
            
            switch (ctx.state) {
                case TaskState::PLANNING: {
                    // 可抢占的 LLM 推理（关键）
                    auto plan = co_await PreemptibleLLMGenerate(
                        BuildPrompt(ctx),
                        // 流式回调（Pie-Agent 风格）
                        [this](const std::string& partial) {
                            EmitEvent("onBlockReply", partial);
                        },
                        cancel_token_
                    );
                    
                    if (plan.was_preempted) {
                        ctx.pending_llm_state = plan.interrupt_state;
                        co_await SaveCheckpoint(ctx);
                        continue;
                    }
                    
                    ctx.plan = plan.result;
                    ctx.state = TaskState::ACTING;
                    break;
                }
                
                case TaskState::ACTING: {
                    // Hooks 机制（Pie-Agent 风格）
                    co_await ExecuteHooksAsync("before_tool_call", ctx.plan.actions);
                    
                    // IO 事务执行（异步，不阻塞）
                    auto exec_result = co_await ExecuteIOTransaction(ctx.plan.actions);
                    
                    co_await ExecuteHooksAsync("after_tool_call", exec_result);
                    
                    ctx.last_observation = exec_result;
                    ctx.state = TaskState::OBSERVING;
                    break;
                }
                
                case TaskState::OBSERVING: {
                    // 事件驱动观察（等待 Layer 0 的 IO 事件）
                    auto obs = co_await WaitForIOEventOrTimeout(100ms);
                    
                    // 元认知层干预（目标接近度检测）
                    float proximity = CalculateGoalProximity(ctx);
                    if (proximity > 0.9f) {
                        co_await scheduler_.BoostPriority(TaskPriority::REALTIME);
                    }
                    
                    ctx.state = TaskState::PLANNING;
                    break;
                }
            }
            
            // 自动保存检查点（每 5 步或关键状态）
            if (ShouldCheckpoint(ctx)) {
                co_await SaveCheckpoint(ctx);
            }
        }
        
        co_await ReportResult(ctx);
    }
    
private:
    // 可抢占 LLM 推理实现
    Task<LLMResult> PreemptibleLLMGenerate(
        const std::string& prompt,
        std::function<void(const std::string&)> on_token,
        CancelToken& cancel
    ) {
        LLMResult result;
        auto stream = llm_.CreateStream(prompt);
        
        // 恢复之前的 KV Cache（如果是中断后恢复）
        if (has_pending_llm_state_) {
            stream.ImportState(pending_llm_state_);
        }
        
        while (auto token_opt = co_await stream.Next()) {
            // 可抢占点 1：外部取消信号（硬件中断触发）
            if (cancel.IsCancelled()) {
                result.was_preempted = true;
                result.interrupt_state = stream.ExportState();  // 保存 KV Cache
                co_return result;
            }
            
            // 可抢占点 2：Token 预算耗尽（时间片轮转）
            if (token_budget_.Consume(1) == 0) {
                result.was_preempted = true;
                result.interrupt_state = stream.ExportState();
                co_return result;
            }
            
            on_token(*token_opt);  // Pie-Agent 风格流式输出
            result.result += *token_opt;
        }
        
        result.was_preempted = false;
        co_return result;
    }
};
```

### 3.2 Layer 1: 事件与调度层 (Event & Scheduler)

**设计目标**：实现优先级事件队列与 Token 预算调度。

```cpp
// nexus_scheduler.h
class MLFQ_T_Scheduler {
public:
    // 队列定义（Token 时间片 + 目标接近度）
    enum QueueLevel {
        Q_REALTIME = 0,      // 紧急 IO/安全：无限 Token，最高优先级
        Q_SPRINT = 1,        // 目标接近度>0.9：4096 Token，防饥饿
        Q_INTERACTIVE = 2,   // 用户交互：2048 Token
        Q_BATCH = 3,         // 常规任务：1024 Token
        Q_BACKGROUND = 4     // 日志/压缩：512 Token
    };
    
    struct TaskControlBlock {
        uint32_t task_id;
        QueueLevel current_queue;
        int32_t token_budget;           // 剩余 Token 预算（时间片）
        float goal_proximity;           // 0.0-1.0，目标接近度
        uint64_t last_cpu_tokens;       // 累计消耗（防饥饿）
        std::coroutine_handle<> handle; // 协程句柄
    };
    
    void Schedule() {
        // O(1) 查找最高非空队列
        for (int q = Q_REALTIME; q <= Q_BACKGROUND; q++) {
            if (!queues_[q].empty()) {
                auto* task = queues_[q].front();
                
                // 执行直到：完成、Token 耗尽、或主动让出
                int consumed = ExecuteTaskWithBudget(task, task->token_budget);
                
                // 动态优先级调整（目标接近度影响）
                UpdateDynamicPriority(task);
                
                // 降级或轮转
                if (task->token_budget <= 0 && q < Q_BACKGROUND) {
                    MoveToQueue(task, static_cast<QueueLevel>(q + 1));
                } else {
                    RotateQueue(q);
                }
                return;
            }
        }
    }
    
    void UpdateDynamicPriority(TaskControlBlock* task) {
        // 目标接近度影响优先级（冲刺机制）
        if (task->goal_proximity > 0.9f && task->current_queue > Q_SPRINT) {
            MoveToQueue(task, Q_SPRINT);
            task->token_budget = 4096;  // 补充 Token
        }
        
        // 防饥饿：长期低优先级任务提升
        if (task->last_cpu_tokens > STARVATION_THRESHOLD) {
            PromoteOneLevel(task);
        }
    }
};

// 事件总线（优先级队列）
class EventBus {
public:
    enum class Priority {
        CRITICAL = 0,  // 系统错误、安全警报
        USER = 1,      // 用户暂停、输入
        SYSTEM = 2,    // 工具完成、观察就绪
        BACKGROUND = 3 // 预加载完成、缓存更新
    };
    
    struct Event {
        Priority priority;
        std::string type;
        json payload;
        std::chrono::steady_clock::time_point timestamp;
    };
    
    void Post(Event event) {
        std::lock_guard lock(mutex_);
        queues_[static_cast<size_t>(event.priority)].push(event);
        cv_.notify_one();
    }
    
    Event Pop() {
        std::unique_lock lock(mutex_);
        cv_.wait(lock, [this] { return !IsEmpty(); });
        
        // 优先级队列：先处理高优先级事件
        for (size_t i = 0; i < queues_.size(); i++) {
            if (!queues_[i].empty()) {
                auto event = queues_[i].front();
                queues_[i].pop();
                return event;
            }
        }
        
        return Event{};  // 不应到达
    }
    
private:
    std::array<std::queue<Event>, 4> queues_;
    std::mutex mutex_;
    std::condition_variable cv_;
};
```

### 3.3 Layer 0: IO 与运行时层 (IO & Runtime)

**设计目标**：封装 LLM、浏览器、设备 IO，支持状态快照。

```cpp
// nexus_io.h
class LLMAdapter {
public:
    struct KVCacheSnapshot {
        std::vector<uint8_t> data;  // llama.cpp 状态序列化
        uint32_t tokens_generated;
        std::string last_prompt;
    };
    
    // 创建流式推理
    Task<Stream> CreateStream(const std::string& prompt);
    
    // 保存 KV Cache 状态（用于中断恢复）
    KVCacheSnapshot ExportState();
    
    // 恢复 KV Cache 状态（从断点继续）
    void ImportState(const KVCacheSnapshot& state);
};

class BrowserAdapter {
public:
    struct PageSnapshot {
        std::string url;
        std::string title;
        std::vector<Cookie> cookies;
        std::string local_storage_json;  // 关键表单数据
        Viewport viewport;
        std::vector<FilledForm> filled_forms;  // 已填写表单状态
    };
    
    // 捕获页面快照（用于崩溃恢复）
    Task<PageSnapshot> CaptureSnapshot();
    
    // 恢复页面状态（从快照重建）
    Task<void> RestoreSnapshot(const PageSnapshot& snapshot);
};

class DeviceAdapter {
public:
    struct NodeState {
        std::string node_id;
        uint64_t last_valid_input;
        uint64_t last_output_cmd;
        std::chrono::steady_clock::time_point last_communication;
        bool is_online;
    };
    
    // 读取 IO 节点状态
    Task<uint64_t> ReadNode(const std::string& node_id);
    
    // 写入 IO 节点（原子事务）
    Task<void> WriteNode(const std::string& node_id, uint64_t value);
    
    // 获取所有节点状态快照（用于持久化）
    std::vector<NodeState> GetAllNodeStates();
};
```

### 3.4 Layer 3: 元认知层 (Meta-Cognition)

**设计目标**：监督 Layer 2，防止目标漂移，优化资源使用。

```cpp
// nexus_metacognition.h
class GoalProximityMonitor {
public:
    // 评估当前距离目标的距离（0.0-1.0，1.0=已完成）
    float CalculateProximity(const AgentContext& ctx) {
        // 方法 1：基于历史步数与预估总步数
        if (ctx.estimated_total_steps > 0) {
            return std::min(1.0f, (float)ctx.history.size() / ctx.estimated_total_steps);
        }
        
        // 方法 2：LLM 评估（周期性执行，不阻塞主循环）
        if (ctx.history.size() % 10 == 0) {
            auto eval = llm_.EvaluateProgress(ctx.history, ctx.goal);
            return eval.completion_rate;
        }
        
        // 方法 3：基于 IO 状态（如距离传感器读数）
        if (auto dist = io_plane_.GetDistanceToTarget()) {
            return 1.0f - (dist / ctx.initial_distance);
        }
        
        return 0.5f;  // 默认中位
    }
};

class ContextCompaction {
public:
    Task<void> CompactHistory(AgentContext& ctx) {
        if (ctx.history.size() < 50) co_return;
        
        // 保留关键步骤（错误、用户干预、里程碑）
        auto critical_steps = FilterCriticalSteps(ctx.history);
        
        // 其余步骤使用 LLM 生成摘要
        auto summary = co_await llm_.SummarizeSteps(
            std::vector<ReActStep>(
                ctx.history.begin() + 10,
                ctx.history.end() - 5
            )
        );
        
        ctx.history = critical_steps;
        ctx.history.push_back({
            .thought = "Summary of previous actions: " + summary,
            .action = Action{ActionType::SUMMARY_MARKER},
            .observation = {}
        });
        
        co_await db_.Write(ctx.task_id, ctx.to_json());
    }
};

class DriftDetection {
public:
    void PeriodicCheck(const std::string& task_id) {
        auto ctx = db_.LoadContext(task_id);
        
        // 提取当前行动轨迹
        auto trajectory = ExtractTrajectory(ctx.history);
        
        // 与原始目标对比（使用 LLM 或规则引擎）
        auto drift_score = CalculateGoalDrift(ctx.goal, trajectory);
        
        if (drift_score > 0.7) {  // 严重漂移
            // 向 Layer 2 发送策略调整信号
            layer2_.InjectReflection(
                "Warning: You seem to be drifting from the original goal. "
                "Consider refocusing or ask user for clarification."
            );
        }
        
        // 检测循环（Repetitive loops）
        if (DetectRepetitivePattern(ctx.history, 3)) {  // 重复 3 次以上
            layer2_.RequestUserIntervention(
                "Stuck in a loop. Please provide guidance."
            );
        }
    }
};
```

---

## 四、持久化与恢复机制

### 4.1 业务状态持久化 (Business State Persistence)

**决策**：仅持久化业务状态，放弃协程栈镜像序列化（ADR-01）。

```cpp
// nexus_persistence.h
struct PersistentContext {
    // 协程与认知状态
    uint32_t checkpoint_magic;           // 校验
    TaskState react_state;               // ReAct 状态机
    std::vector<ReActStep> history;      // 历史（可 JSON 序列化）
    std::string goal;                    // 任务目标
    
    // IO 与设备状态（关键差异：保存所有节点的输出状态）
    std::vector<DeviceAdapter::NodeState> io_states;
    std::optional<BrowserAdapter::PageSnapshot> browser_snapshot;  // 仅浏览器场景
    
    // LLM 推理断点（支持抢占恢复）
    LLMAdapter::KVCacheSnapshot llm_checkpoint;
    
    // 调度器状态
    MLFQ_T_Scheduler::TaskControlBlock sched_state;
    
    // 元认知状态
    float last_goal_proximity;
    uint32_t accumulated_tokens;
    
    // 序列化方法
    nlohmann::json ToJson() const;
    static PersistentContext FromJson(const nlohmann::json& j);
};

class PersistenceManager {
public:
    // 热休眠：保存到内存 + 可选 SQLite（快速恢复）
    Task<void> HibernateHot(NexusAgent& agent) {
        auto snapshot = agent.SerializeContext();
        
        // 1. 保存到内存双缓冲（< 1ms）
        memory_buffer_.Push(snapshot);
        
        // 2. 异步写入 SQLite（后台 Work Queue）
        co_await work_queue_.Enqueue([snapshot] {
            sqlite_.Write(snapshot.task_id, snapshot.ToJson());
        });
        
        // 3. 保持 IO 节点连接（仅降低轮询频率）
        io_plane_.SetPollingMode(PollingMode::LOW_POWER);
    }
    
    // 冷休眠：完整序列化，释放所有资源
    Task<void> HibernateCold(NexusAgent& agent) {
        auto snapshot = agent.SerializeFullContext();
        
        // 1. 命令所有 IO 节点进入安全态
        co_await io_plane_.EmergencyStopAll();
        
        // 2. 完整持久化（包括 LLM KV Cache 摘要）
        co_await sqlite_.WriteFull(snapshot);
        
        // 3. 关闭总线、卸载模型、释放 GPU 内存
        io_plane_.Shutdown();
        llm_engine_.Unload();
        
        // 4. 设置 RTC 唤醒（定时恢复）
        rtc_.SetAlarm(wakeup_time_);
        
        // 5. 进程优雅退出（零内存占用）
        std::exit(EXIT_HIBERNATE);
    }
    
    // 恢复入口
    static Task<NexusAgent> Resume(const std::string& task_id) {
        // 尝试热恢复（内存）
        if (memory_buffer_.HasValidCheckpoint(task_id)) {
            auto ctx = memory_buffer_.Read(task_id);
            co_return NexusAgent(ctx);  // < 10ms 恢复
        }
        
        // 冷恢复（SQLite）
        auto data = co_await sqlite_.Read(task_id);
        auto ctx = PersistentContext::FromJson(data);
        
        // 重建 IO 连接
        for (auto& io_state : ctx.io_states) {
            if (!io_state.is_online) {
                co_await io_plane_.Reconnect(io_state.node_id);
                // 重放最后指令确保状态一致
                co_await io_plane_.ReplayCommand(
                    io_state.node_id,
                    io_state.last_output_cmd
                );
            }
        }
        
        // 恢复 LLM 状态
        if (!ctx.llm_checkpoint.data.empty()) {
            llm_engine_.RestoreKVCache(ctx.llm_checkpoint);
        }
        
        co_return NexusAgent(ctx);  // 1-5s 恢复
    }
};
```

### 4.2 SQLite Schema

```sql
-- 任务主表
CREATE TABLE tasks (
    task_id TEXT PRIMARY KEY,
    goal TEXT NOT NULL,
    current_state TEXT CHECK(current_state IN 
        ('PLANNING', 'ACTING', 'OBSERVING', 'COMPLETED', 'FAILED', 'PAUSED')),
    created_at INTEGER,
    updated_at INTEGER,
    browser_snapshot JSON,  -- Layer 2 的浏览器状态（可选）
    io_states JSON,         -- Layer 0 的 IO 节点状态
    priority INTEGER DEFAULT 1
);

-- 历史步骤表（支持分片加载）
CREATE TABLE react_steps (
    step_id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT,
    step_number INTEGER,
    state TEXT,  -- PLANNING/ACTING/OBSERVING
    thought TEXT,
    action_type TEXT,
    action_params JSON,
    observation_screenshot BLOB,  -- 可选，二进制存储
    observation_text TEXT,
    timestamp INTEGER,
    FOREIGN KEY (task_id) REFERENCES tasks(task_id)
);

-- LLM KV Cache 摘要表
CREATE TABLE llm_checkpoints (
    checkpoint_id INTEGER PRIMARY KEY,
    task_id TEXT,
    tokens_generated INTEGER,
    kv_cache_data BLOB,  -- llama.cpp 状态序列化
    last_prompt TEXT,
    timestamp INTEGER,
    FOREIGN KEY (task_id) REFERENCES tasks(task_id)
);

-- 中断/恢复日志
CREATE TABLE interrupt_log (
    log_id INTEGER PRIMARY KEY,
    task_id TEXT,
    interrupt_type TEXT,
    timestamp INTEGER,
    recovered_at INTEGER,
    context_before JSON,
    context_after JSON
);
```

---

## 五、中断处理架构

### 5.1 顶底分离设计 (Top-Bottom Half Separation)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 0: 顶半部 (Top Half) - 内核空间                               │
│ ├─ 硬件中断 (GPIO/UART/Timer)                                       │
│ ├─ 信号处理函数 (SIGRTMIN)                                          │
│ └─ 无锁环形缓冲区 (Lock-Free Ring Buffer)                           │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ eventfd 通知
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 1: 底半部 (Bottom Half) - 用户态工作线程                       │
│ ├─ eventfd 等待                                                     │
│ ├─ 环形缓冲区读取                                                   │
│ ├─ 协议解析 (Modbus/CAN/CDP)                                        │
│ └─ 事件总线投递 (Event Bus Post)                                    │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 事件队列
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 2: Agent 层 - 协程消费                                         │
│ ├─ co_await WaitForEvent()                                          │
│ ├─ 中断响应 (Cancel LLM, Emergency Stop)                            │
│ └─ 状态恢复 (Resume from Checkpoint)                                │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 时序保证

| 阶段 | 延迟目标 | 实现机制 |
| :--- | :--- | :--- |
| **顶半部** | < 10μs | 内核信号处理，仅写入无锁环形缓冲区 |
| **底半部** | < 1ms | 用户态工作线程，eventfd 唤醒，协议解析 |
| **Agent 响应** | < 100ms | 协程在下一个 `co_await` 检查点响应 |

---

## 六、运行示例：浏览器自动化场景

```cpp
int main() {
    // 初始化 Layer 0-1
    EventBus event_bus;
    MLFQ_T_Scheduler scheduler;
    PersistenceManager persistence;
    
    // 创建 Agent（Layer 2-3）
    NexusAgent agent("task_001", "购买 iPhone 15 Pro");
    
    // 配置：可抢占 LLM（本地 7B 模型）
    agent.ConfigureLLM({
        .model_path = "/models/llama2-7b-q4.gguf",
        .max_tokens_per_slice = 1024,  // Token 时间片
        .enable_preempt = true
    });
    
    // 注册浏览器适配器
    agent.browser().Register({
        .headless = false,
        .timeout_ms = 30000,
        .enable_snapshot = true  // 启用页面快照
    });
    
    // 启动事件处理线程
    std::jthread event_thread([&] {
        while (true) {
            auto event = event_bus.Pop();
            agent.PostEvent(event);
        }
    });
    
    // 启动调度器线程
    std::jthread sched_thread([&] {
        scheduler.Run();
    });
    
    // 主循环：ReAct 协程
    auto main_task = agent.Run();
    
    // 模拟：用户中断（测试可抢占性）
    std::this_thread::sleep_for(5s);
    agent.TriggerUserPause();  // 发送取消信号
    
    // 保存检查点
    auto checkpoint = agent.GetCheckpoint();
    persistence.HibernateCold(agent);
    
    // 恢复后继续
    auto resumed_agent = NexusAgent::Resume("task_001");
    auto resumed_task = resumed_agent.Run();
    
    return 0;
}
```

---

## 七、技术指标验证矩阵

| 指标 | 实现机制 | 验证方法 | 目标性能 |
| :--- | :--- | :--- | :--- |
| **LLM 可抢占** | CancelToken + 流式检查点（每 Token 检查） | 在推理第 50 Token 发送中断信号 | 中断延迟 < 2ms |
| **Token 时间片** | MLFQ-T 队列，1024/2048/4096 Token 预算 | 运行两个 Agent，观察 Token 耗尽让出 | 切换开销 < 50μs |
| **业务状态持久化** | IO 节点快照 + ReAct 历史 + LLM KV Cache | 断电重启，验证状态一致性 | 冷恢复 < 5s，状态 100% 一致 |
| **顶底分离** | Lock-Free Ring（顶）+ WorkQueue（底） | 示波器测量中断到 Agent 响应延迟 | 顶半部 < 10μs，底半部 < 1ms |
| **热/冷休眠** | MemRetention / SQLite + RTC 唤醒 | 测量功耗与唤醒时间 | 热唤醒 < 10ms，冷唤醒 < 5s |
| **目标优先级** | Proximity 计算 + SPRINT 队列提升 | 监控距离目标 10% 时任务队列迁移 | 0.9s 内完成优先级提升 |
| **事件响应** | 优先级事件队列（用户 > 系统 > 背景） | 并发提交多优先级事件，观察处理顺序 | 用户事件优先处理，无饥饿 |

---

## 八、与现有项目对比

| 特性 | BAFA | Pie-Agent | ZeroClaw | AOS-Nexus (本设计) |
| :--- | :--- | :--- | :--- | :--- |
| **核心范式** | 三层硬实时协程 | 事件驱动外壳 | Rust Channel 异步 | 四层协程 + 事件融合 |
| **适用场景** | 浏览器自动化 | 通用 AI 助手 | Rust 生态工具 | **浏览器 + 工业网关** |
| **持久化** | 浏览器快照 + 协程栈 | 内存状态机 | Channel 消息 | **业务状态 (ReAct/IO/KV Cache)** |
| **调度策略** | 每标签页独立协程 | 优先级队列 | tokio 运行时 | **MLFQ-T (Token 预算 + 目标接近度)** |
| **中断处理** | 无锁中断环 + SIGSTOP | 软中断标志 | Channel 取消 | **顶底分离 (信号→eventfd→事件总线)** |
| **LLM 集成** | 通用 API | 流式输出 | 异步调用 | **llama.cpp 深度集成 (KV Cache 管理)** |
| **语言** | C++20 | Python/TS | Rust | **C++20** |

---

## 九、实施路线图

| 阶段 | 时间 | 任务 | 交付物 |
| :--- | :--- | :--- | :--- |
| **Phase 1** | Week 1-2 | 事件总线 + 协程框架 | EventBus, Task<T>, 基础 ReAct 循环 |
| **Phase 2** | Week 3-4 | LLM 适配器 + KV Cache 管理 | LLMAdapter, 流式推理，中断恢复 |
| **Phase 3** | Week 5-6 | 持久化层 + SQLite Schema | PersistenceManager, 冷/热休眠 |
| **Phase 4** | Week 7-8 | MLFQ-T 调度器 + 目标优先级 | Scheduler, GoalProximityMonitor |
| **Phase 5** | Week 9-10 | 浏览器/设备适配器 + 快照 | BrowserAdapter, DeviceAdapter |
| **Phase 6** | Week 11-12 | 元认知层 + 完整集成 | DriftDetection, ContextCompaction, 系统测试 |

---

## 十、结论

AOS-Nexus 架构综合了 BAFA 的硬实时协程安全、Pie-Agent 的事件驱动响应性、ZeroClaw 的异步通信模型、以及 AOS-Gateway 的六项关键指标，形成适用于**浏览器自动化**与**工业网关**的通用智能体运行时框架。

**核心优势**：
1.  **协程优先**：同步风格代码，异步执行效率，避免回调地狱。
2.  **业务状态持久化**：规避协程栈序列化陷阱，保证稳定性与可移植性。
3.  **Token 预算调度**：防止单一 Agent 独占 LLM 资源，支持多 Agent 并发。
4.  **分层中断处理**：硬实时中断与软实时业务分离，确保安全性。
5.  **目标感知优先级**：越接近目标优先级越高，优化任务完成时间。

此架构可作为后续详细设计与开发的正式输入依据。