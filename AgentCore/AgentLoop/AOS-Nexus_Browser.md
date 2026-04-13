基于您提供的知识库（特别是 `浏览器智能体架构.md` 中的 BAFA 架构）以及之前的 AOS-Nexus/HAL-Agent 设计，如果**仅针对浏览器智能体场景**，可以大幅简化架构。浏览器环境是用户态软实时环境，不需要工业网关的硬实时中断、物理 IO 状态管理及复杂的功耗控制。

以下是针对浏览器场景的**简化与移除建议**，以及重构后的轻量级架构设计。

---

### 一、核心简化策略：移除与保留

| 模块/特性 | 原设计 (AOS-Nexus/HAL-Agent) | **浏览器场景简化版 (AOS-Browser)** | **简化理由** |
| :--- | :--- | :--- | :--- |
| **Layer 0: IO 层** | 多总线仲裁 (Modbus/CAN)、设备影子、紧急 ISR | **浏览器适配器 (Playwright/CDP)**、网络 IO | 浏览器无物理寄存器，无需硬件中断处理，CDP 协议即为事件源。 |
| **Layer 1: 中断层** | 顶底分离 (内核顶半部 <10μs)、无锁环形缓冲 | **用户态事件总线**、CDP 事件监听 | 浏览器崩溃/弹窗是用户态事件，无需内核级顶半部，<1ms 响应即可。 |
| **Layer 1: 调度层** | MLFQ-T (Token 预算)、防饥饿算法、多 Agent 并发 | **优先级事件队列** (用户 > 系统 > 背景) | 单任务/少任务场景下，Token 预算过于复杂，优先级队列足够。 |
| **Layer 1: 电源层** | 热/冷休眠、RTC 唤醒、CPU 降频、内存保留 | **进程挂起/退出**、SQLite 持久化 | 服务器/PC 无需极致功耗管理，标准进程管理即可。 |
| **Layer 2: 持久化** | IO 节点状态快照、LLM KV Cache 二进制保存 | **浏览器快照** (Cookie/Storage/URL)、Prompt 历史 | 浏览器状态恢复比 LLM 内部状态恢复更重要；KV Cache 保存开销大且非必要。 |
| **Layer 3: 元认知** | 目标接近度 (基于 IO 传感器)、Token 压缩 | **目标漂移检测** (基于 DOM/URL)、上下文压缩 | 浏览器任务完成度基于页面状态而非物理距离。 |
| **语言边界** | C 内核 + C++ 协程 (跨平台 HAL) | **纯 C++20** (Linux 用户态) | 移除 MCU 兼容包袱，充分利用 C++ 标准库与异步特性。 |

---

### 二、简化后的架构设计：AOS-Browser (BAFA-Lite)

基于 BAFA 三层模型进行裁剪，移除工业网关特性，保留浏览器自动化核心。

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 3: Meta-Cognition (元认知层)                                   │
│ ├─ GoalDriftDetector (目标漂移检测：基于 URL/DOM 变化)               │
│ ├─ ContextCompactor (上下文压缩：Token 优化)                         │
│ └─ TabCoordinator (多标签页协调：可选)                               │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 策略注入
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 2: Cognitive Coroutine (认知协程层)                            │
│ ├─ ReAct Engine (C++20 协程化 ReAct 循环)                            │
│ ├─ Browser Snapshot Manager (页面状态快照：Cookie/Storage/URL)       │
│ ├─ Preemptible LLM (可取消推理：用户暂停支持)                        │
│ └─ Persistent Context (SQLite: 历史 + 浏览器状态)                    │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 事件驱动
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 1: Event & Control (事件与控制层)                              │
│ ├─ Event Bus (优先级队列：用户中断 > CDP 事件 > 背景任务)             │
│ ├─ CDP Listener (Chrome DevTools Protocol 监听)                      │
│ ├─ Interrupt Controller (用户暂停/崩溃信号处理)                      │
│ └─ Recovery Manager (崩溃恢复：重建浏览器实例)                       │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ 系统调用
┌────────────────────────────────▼────────────────────────────────────┐
│ Layer 0: Runtime & Storage (运行时与存储)                            │
│ ├─ Playwright/CDP Adapter (浏览器控制)                               │
│ ├─ LLM Adapter (本地 llama.cpp 或 云端 API)                          │
│ └─ SQLite (WAL 模式：状态存储)                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 三、详细模块简化说明

#### 1. 移除工业级中断架构 (Layer 1)
*   **原设计**：顶半部 (内核 ISR) + 底半部 (Work Queue) + 无锁环。
*   **简化后**：**用户态事件循环**。
*   **理由**：浏览器事件（导航完成、弹窗、崩溃）通过 CDP WebSocket 或 Playwright 事件回调到达，均为用户态。无需内核信号处理。
*   **实现**：
    ```cpp
    // 简化版事件控制器
    class BrowserInterruptController {
    public:
        enum class Priority { USER_PAUSE, CRASH, NAVIGATION, BACKGROUND };
        void PostEvent(Event event); // 直接入队，无需原子环缓冲
        bool CheckPauseSignal();     // 协程检查点调用
    };
    ```

#### 2. 替换持久化内容 (Layer 2)
*   **原设计**：IO 节点状态 (Modbus 寄存器) + LLM KV Cache 二进制。
*   **简化后**：**浏览器快照 (Browser Snapshot)** + Prompt 历史。
*   **理由**：浏览器任务恢复的关键是**页面状态**（URL、Cookie、LocalStorage、表单填写内容），而非 LLM 内部显存状态。恢复时重建浏览器上下文比恢复 LLM 显存更可靠且开销更小。
*   **实现** (基于 BAFA)：
    ```cpp
    struct BrowserSnapshot {
        std::string url;
        std::vector<Cookie> cookies;
        std::string local_storage_json; // 关键：表单/登录状态
        std::vector<FilledForm> forms;  // 已填表单
        // 序列化为 JSON 存入 SQLite
    };
    // 移除 LLM KV Cache 二进制保存，仅保存 prompt 历史
    ```

#### 3. 简化调度策略 (Layer 1)
*   **原设计**：MLFQ-T (Token 预算)、目标接近度冲刺、防饥饿算法。
*   **简化后**：**优先级事件队列**。
*   **理由**：浏览器自动化通常是单任务或少数任务并发。用户暂停指令必须最高优先级，其次是页面加载完成事件。Token 预算主要用于防止 LLM 滥用，可通过 API 限流解决，无需操作系统级调度。
*   **实现**：
    ```cpp
    std::priority_queue<Event, std::vector<Event>, PriorityCompare> event_queue_;
    // 用户暂停事件优先级最高，确保随时可中断 LLM 推理
    ```

#### 4. 移除功耗管理 (Layer 1)
*   **原设计**：热/冷休眠、RTC 唤醒、CPU 降频、内存保留。
*   **简化后**：**标准进程挂起/退出**。
*   **理由**：边缘网关/服务器无需像 MCU 那样管理 RTC 唤醒。长时间任务可持久化后退出进程，由外部调度器 (如 Cron/K8s) 唤醒。
*   **实现**：
    ```cpp
    void Hibernate() {
        SaveStateToSQLite();
        std::exit(0); // 直接退出，释放所有资源
    }
    // 唤醒由外部脚本启动进程并检查 SQLite 未完成任务
    ```

#### 5. 纯 C++ 实现 (移除 C 内核层)
*   **原设计**：C 内核 (Layer 1) + C++ 协程 (Layer 3)，extern "C" 桥接。
*   **简化后**：**纯 C++20**。
*   **理由**：移除 MCU 支持后，无需 C 语言内核来保证确定性。C++20 协程 + RAII 足以管理资源，代码更简洁。
*   **实现**：直接使用 `std::coroutine_handle`, `std::async`, `sqlite_modern_cpp` 等库。

---

### 四、简化后的关键流程示例

#### 1. 可抢占的 ReAct 循环 (简化版)
```cpp
Task<void> BrowserAgent::Run() {
    while (!goal_reached_) {
        // 检查点 1：用户暂停 (简化为检查原子标志位)
        if (interrupt_controller_.IsPaused()) {
            co_await SaveBrowserSnapshot(); // 仅保存浏览器状态
            co_await WaitForResumeSignal(); // 协程挂起，不占线程
            continue;
        }

        // 规划
        auto thought = co_await LLM.Generate(prompt_); // 支持取消 Token
        
        // 执行 (浏览器操作)
        co_await browser_.Click("#submit"); 
        
        // 检查点 2：导航前自动快照 (BAFA 核心)
        if (navigation_detected_) {
            co_await SaveBrowserSnapshot(); 
        }
        
        // 观察
        auto obs = co_await browser_.GetDOM();
        prompt_ = BuildPrompt(thought, obs);
    }
}
```

#### 2. 崩溃恢复流程 (简化版)
```cpp
void RecoveryManager::Recover() {
    // 1. 查询 SQLite 中状态不为 COMPLETED 的任务
    auto tasks = db_.Query("SELECT * FROM tasks WHERE state != 'COMPLETED'");
    
    for (auto& task : tasks) {
        // 2. 启动新浏览器实例
        auto browser = playwright_.Launch();
        
        // 3. 恢复浏览器状态 (关键简化点)
        browser_.RestoreCookies(task.cookies);
        browser_.SetLocalStorage(task.local_storage);
        browser_.Navigate(task.url);
        
        // 4. 重建协程，从 ReAct 历史继续
        agent_.Resume(task.history); 
    }
}
```

---

### 五、简化后的 UR/ADR 调整建议

| 编号 | 原内容 (AOS-Nexus) | **简化后内容 (AOS-Browser)** | 变更理由 |
| :--- | :--- | :--- | :--- |
| **UR-01** | Linux 用户态 + PREEMPT_RT | **Linux 用户态 (标准内核)** | 浏览器事件无需 <100μs 硬实时，标准内核足够。 |
| **UR-06** | 顶底分离中断 (<10μs) | **用户态事件监听 (CDP)** | 移除内核中断依赖，降低开发复杂度。 |
| **UR-07** | 中断响应 <200μs | **用户暂停响应 <1s** | 浏览器加载本身需秒级，暂停响应无需微秒级。 |
| **UR-10** | 冷休眠 + RTC 唤醒 | **持久化 + 进程退出** | 移除 RTC 硬件依赖，由外部调度器管理唤醒。 |
| **ADR-02** | 信号量中断机制 | **事件总线 + 原子标志位** | 简化中断实现，无需信号处理函数。 |
| **ADR-03** | LLM KV Cache 保存 | **仅保存 Prompt 历史** | 降低持久化开销，浏览器状态恢复更关键。 |
| **ADR-05** | 内存池可选 | **直接使用系统分配器** | 移除所有内存池设计，简化内存管理。 |

---

### 六、总结：简化带来的收益

1.  **开发成本降低 50%+**：移除 C 内核层、顶底分离中断、功耗管理、复杂调度器。
2.  **可靠性提升**：浏览器快照恢复比 LLM 显存恢复更成熟可靠；标准内核比 PREEMPT_RT 更易维护。
3.  **聚焦核心痛点**：集中精力解决**浏览器状态持久化**（Cookie/Storage）、**长任务防漂移**、**用户随时干预**这三个浏览器自动化最核心的问题。
4.  **符合 BAFA 最佳实践**：回归 `浏览器智能体架构.md` 中验证过的三层模型，去除工业网关的过度设计。

**建议下一步**：基于此简化版架构，输出 **`AOS-Browser-Detailed-Design.md`**，重点定义 `BrowserSnapshot` 数据结构、CDP 事件映射表、以及 SQLite 状态表结构。