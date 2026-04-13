# DOC-03: CommandTranslator 映射表

> **版本**: v1.1-draft  
> **日期**: 2026-04-13  
> **状态**: 待评审  
> **适用范围**: TaskRunner 侧 `TaskCommand` → UsrLinuxEmu 侧 `DeviceCommand` 的完整映射关系

---

## 一、概述

本文档定义 **CommandTranslator** 的完整映射规则。TaskRunner 内部管理丰富的命令类型（20+），提交到 UsrLinuxEmu 时需翻译为精简的设备命令（Phase 1 仅 2 种，Phase 2 扩展至 5-6 种）。

**设计原则**:
- 单向映射：TaskCommand → DeviceCommand，反向不成立
- 有损压缩：多个 TaskCommand 可能映射到同一 DeviceCommand，由 TaskRunner 侧保留完整语义
- 不可映射的命令必须在 TaskRunner 侧消化，不得传到 UsrLinuxEmu

---

## 二、NVIDIA/AMD UserMode 队列与任务调度调研

### 2.1 NVIDIA: GPFIFO 用户态队列模型

NVIDIA 从 **Fermi 架构**开始引入用户态 GPFIFO（General Purpose FIFO）模型：

```
┌─────────────────────────────────────────────────┐
│                    User Space                    │
│                                                   │
│  ┌─────────────┐    ┌──────────────────────────┐ │
│  │  CUDA Driver │───►│  GPFIFO Ring Buffer      │ │  ← mmap 映射的环形缓冲区
│  │  (libcuda)  │    │  (用户态直接写入)         │ │
│  └─────────────┘    └───────────┬──────────────┘ │
│                                 │                  │
│                          Doorbell Write            │  ← 写 MMIO 寄存器通知硬件
│                                 │                  │
├─────────────────────────────────┼──────────────────┤
│                    Kernel Space  │                  │
│                                 ▼                  │
│                     ┌──────────────────────┐       │
│                     │  GPU Hardware        │       │
│                     │  Scheduler (GPFIFO)  │       │
│                     └──────────────────────┘       │
└─────────────────────────────────────────────────┘
```

**关键特征**:
1. **用户态构建命令**: CUDA Driver (libcuda) 在 GPFIFO ring buffer 中直接写入 Method 命令（类似 GPU 的机器码）
2. **Doorbell 机制**: 用户态写一个 MMIO 寄存器（doorbell），GPU 硬件调度器立即看到新任务
3. **零内核拷贝**: 命令数据不经过内核，只在用户态 ring buffer 和 GPU 之间传递
4. **多队列支持**: 一个进程可以创建多个 GPFIFO 通道（对应不同的 GPU engine：graphic、compute、copy）
5. **Push Buffer + IB 混合**: GPFIFO 中可以放直接命令 (push buffer) 或指向间接缓冲区 (IB) 的指针

**ioctl 使用模式**:
```
初始化阶段 (ioctl 密集):
  NV_ESC_ALLOC_OBJECT        → 创建 GPFIFO channel
  NV_ESC_ALLOC_GPFIFO        → 分配 ring buffer
  NV_ESC_MAP_MEMORY          → mmap 映射

提交阶段 (ioctl 稀疏):
  NV_ESC_LAUNCH_DMA          → doorbell 触发（只传 put pointer）
  NV_ESC_EVENT_WAIT          → 等待完成

运行时 (无 ioctl):
  用户态直接写 ring buffer → doorbell → GPU 执行
```

### 2.2 AMD: KFD User-Mode Queue (HSA) 模型

AMD 的 KFD (Kernel Fusion Driver) 是更纯粹的用户态队列模型，基于 **HSA (Heterogeneous System Architecture)** 标准：

```
┌──────────────────────────────────────────────────┐
│                    User Space                     │
│                                                    │
│  ┌──────────────┐    ┌─────────────────────────┐  │
│  │  ROCr Runtime │───►│  User-Mode Queue         │  │  ← 用户态管理的队列
│  │  (libhsa)    │    │  (AQL Packet 队列)       │  │
│  └──────────────┘    └────────┬────────────────┘  │
│                                │                    │
│                         Doorbell Page Write         │  ← 门铃页
│                                │                    │
├────────────────────────────────┼────────────────────┤
│                    Kernel Space │                    │
│                                ▼                    │
│                    ┌───────────────────────┐        │
│                    │  HQD (Hardware Queue   │        │
│                    │  Descriptor)           │        │  ← 硬件队列描述符
│                    │  由 KFD 配置给 GPU     │        │
│                    └───────────────────────┘        │
└──────────────────────────────────────────────────┘
```

**关键特征**:
1. **AQL (Async Queue Language) Packet**: 用户态队列中的命令格式
   - `HSA_PACKET_TYPE_KERNEL_DISPATCH` — 内核分发
   - `HSA_PACKET_TYPE_VENDOR_SPECIFIC` — 厂商特定
   - `HSA_PACKET_TYPE_BARRIER_AND` / `OR` — 硬件屏障
   - `HSA_PACKET_TYPE_SIGNAL` — 信号通知

2. **用户态 Queue 管理**:
   - `KFD_IOC_CREATE_QUEUE` — 创建用户态队列
   - 队列 ring buffer 完全由用户态管理读写指针
   - Doorbell 触发后，GPU 直接从 ring buffer 读取 AQL packet

3. **硬件屏障 (Hardware Barrier)**:
   - 队列中的 `BARRIER_AND` packet 会等待指定的 signal 完成
   - 这是**硬件级**的队列内同步，不需要内核参与
   - 类似 CUDA 的 `__syncthreads()` 但是跨任务级别

4. **Signal 机制**:
   - 用户态可以分配 Signal 对象（类似 fence）
   - Kernel dispatch packet 可以设置"完成时写入 signal"
   - Barrier packet 可以设置"等待 signal 达到某值"

### 2.3 三种架构对比

| 特性 | NVIDIA GPFIFO | AMD KFD/AQL | UsrLinuxEmu (当前) |
|------|--------------|-------------|-------------------|
| **命令构建位置** | 用户态 ring buffer | 用户态 AQL queue | 用户态 packet 数组 |
| **触发方式** | Doorbell MMIO write | Doorbell page write | `GPGPU_SUBMIT_PACKET` ioctl |
| **队列数量** | 多 GPFIFO 通道 | 多 user-mode queue | 单队列（当前） |
| **队列内同步** | Semaphore method | BARRIER_AND packet | ❌ 不支持 |
| **跨队列同步** | Event/Fence ioctl | Signal 对象 | ❌ 不支持 |
| **间接缓冲** | IB (Indirect Buffer) | IB packet | ❌ 不支持 |
| **命令格式** | GPU Method (硬件机器码) | AQL packet (标准化) | 自定义 GpuCommandPacket |

---

## 三、UserMode Queue 能力规划

### 3.1 Phase 1：基础提交（当前）

**能力**:
- 单一命令提交通道（`GPGPU_SUBMIT_PACKET`）
- 两种命令类型：KERNEL, DMA_COPY
- 无队列内同步
- 无多队列支持

**对标**:
- NVIDIA: 单个 GPFIFO channel，只推 push buffer
- AMD: 单个 user-mode queue，只推 dispatch packet

**局限**:
- TaskRunner 必须按顺序提交命令，无法利用 GPU 的并行引擎
- 无法在队列内插入 barrier（必须等前一批完成再提交下一批）

### 3.2 Phase 2：同步屏障（规划中）

**新增能力**:
```cpp
// CommandType 扩展
enum class CommandType : uint32_t {
    KERNEL       = 0,
    DMA_COPY     = 1,
    BARRIER_SYNC = 4,   // ← 新增
};

struct BarrierCommand {
    uint64_t barrier_id;    // 屏障 ID
    uint32_t operation;     // 0=SIGNAL, 1=WAIT
    uint32_t payload;       // 屏障值（用于 timeline fence 语义）
};
```

**对标**:
- AMD AQL: `HSA_PACKET_TYPE_BARRIER_AND`
- NVIDIA: Semaphore acquire/release method

**使用场景**:
```
TaskRunner:
  [KERNEL task_1] → [DMA_COPY task_2] → [BARRIER wait=1] → [KERNEL task_3]
                                                ▲
                                          等待 task_1 和 task_2 完成
```

### 3.3 Phase 3：用户态多队列（远期规划）

**目标架构**（借鉴 AMD KFD）:

```cpp
// ioctl 0x50: 创建用户态队列
struct GpuCreateQueueRequest {
    uint32_t queue_type;      // 0=COMPUTE, 1=COPY, 2=ALL
    uint32_t queue_priority;  // 0=LOW, 1=NORMAL, 2=HIGH
    uint64_t ring_addr;       // 用户态 ring buffer 地址
    uint64_t ring_size;       // ring buffer 大小
    uint64_t doorbell_offset; // 门铃偏移
    uint32_t queue_id;        // OUT: 队列 ID
};

// ioctl 0x52: 门铃触发
struct GpuDoorbellRequest {
    uint32_t queue_id;        // 队列 ID
    uint32_t put_index;       // 新的写指针位置
};
```

**对标**:
- AMD KFD: `KFD_IOC_CREATE_QUEUE` + doorbell page write
- NVIDIA: `NV_ESC_ALLOC_GPFIFO` + doorbell MMIO

**优势**:
- TaskRunner 可以直接写 ring buffer，无需 ioctl 传递数据
- 零拷贝：命令数据不经过内核
- 多引擎并行：COMPUTE queue 和 COPY queue 可以同时工作

---

## 四、命令空间定义

### 4.1 TaskRunner 侧：TaskCommand 枚举

```cpp
namespace async_task {

enum class TaskCommand : uint32_t {
    // === 基础命令 (0-9) ===
    TASK           = 0,
    BARRIER        = 1,
    FENCE          = 2,

    // === CUDA 命令 (10-19) ===
    CUDA_ALLOC         = 10,
    CUDA_FREE          = 11,
    CUDA_COPY_H2D      = 12,
    CUDA_COPY_D2H      = 13,
    CUDA_COPY_D2D      = 14,
    CUDA_LAUNCH_KERNEL = 15,
    CUDA_EVENT_RECORD  = 16,
    CUDA_EVENT_WAIT    = 17,
    CUDA_STREAM_CREATE = 18,
    CUDA_STREAM_SYNC   = 19,

    // === Vulkan 命令 (20-29) ===
    VK_ALLOC_MEMORY    = 20,
    VK_FREE_MEMORY     = 21,
    VK_CREATE_BUFFER   = 22,
    VK_DESTROY_BUFFER  = 23,
    VK_DISPATCH_COMPUTE = 24,
    VK_BIND_PIPELINE   = 25,
    VK_SIGNAL_SEMAPHORE = 26,
    VK_WAIT_SEMAPHORE   = 27,
    VK_CREATE_FENCE    = 28,
    VK_WAIT_FENCE      = 29,

    // === 通用命令 (30-39) ===
    MEMORY_ALLOC   = 30,
    MEMORY_FREE    = 31,
    MEMORY_COPY    = 32,
    BARRIER_SYNC   = 33,
    FENCE_SIGNAL   = 34,
};

} // namespace async_task
```

### 4.2 UsrLinuxEmu 侧：DeviceCommand 枚举

**Phase 1（当前）**:
```cpp
enum class CommandType : uint32_t {
    KERNEL   = 0,   // 计算内核执行
    DMA_COPY = 1,   // 内存拷贝
};
```

**Phase 2（规划）**:
```cpp
enum class DeviceCommand : uint32_t {
    KERNEL       = 0,
    DMA_COPY     = 1,
    MEMORY_ALLOC = 2,
    MEMORY_FREE  = 3,
    BARRIER_SYNC = 4,
    MMIO_ACCESS  = 5,
};
```

---

## 五、完整映射表

### 5.1 Phase 1 映射（当前实现）

| TaskCommand | → | DeviceCommand | 说明 | 对标 |
|-------------|---|---------------|------|------|
| `CUDA_LAUNCH_KERNEL` | → | `KERNEL` | 内核启动 | NVIDIA: method 0x00 |
| `VK_DISPATCH_COMPUTE` | → | `KERNEL` | 计算着色器分发 | AMD: AQL dispatch packet |
| `CUDA_COPY_H2D` | → | `DMA_COPY` | Host→Device 拷贝 | NVIDIA: DMA copy engine |
| `CUDA_COPY_D2H` | → | `DMA_COPY` | Device→Host 拷贝 | NVIDIA: DMA copy engine |
| `CUDA_COPY_D2D` | → | `DMA_COPY` | Device→Device 拷贝 | AMD: SDMA engine |
| `VK_MEMORY_COPY` | → | `DMA_COPY` | Vulkan 内存拷贝 | AMD: SDMA engine |

### 5.2 TaskRunner 内部消化（不传递到 UsrLinuxEmu）

| TaskCommand | 处理方式 | 对标分析 |
|-------------|---------|---------|
| `CUDA_ALLOC` | TaskRunner 内存池管理，耗尽时调用 `GPGPU_ALLOC_MEM` ioctl | NVIDIA: libcuda 内部 pool，不够才调用 UVM alloc |
| `CUDA_FREE` | TaskRunner 内存池回收 | NVIDIA: libcuda 内部 free，不立即释放给 UVM |
| `CUDA_STREAM_CREATE` | TaskRunner 内部创建 Stream 对象 | NVIDIA: libcuda 内部管理 stream，内核无感知 |
| `CUDA_STREAM_SYNC` | TaskRunner 等待 stream 中所有任务完成 | NVIDIA: `cuStreamSynchronize` 内部用 event 等待 |
| `CUDA_EVENT_RECORD` | TaskRunner 记录时间戳 | NVIDIA: event 由 libcuda 管理 |
| `CUDA_EVENT_WAIT` | TaskRunner 依赖图等待 | NVIDIA: event wait 在 driver 层处理 |
| `VK_ALLOC_MEMORY` | TaskRunner 内存池管理 | AMD: ROCr 内部 pool |
| `VK_FREE_MEMORY` | TaskRunner 内存池回收 | AMD: ROCr 内部回收 |
| `VK_CREATE_BUFFER` | TaskRunner buffer 对象管理 | AMD: ROCr 内部管理 |
| `VK_DESTROY_BUFFER` | TaskRunner buffer 对象销毁 | AMD: ROCr 内部销毁 |
| `VK_BIND_PIPELINE` | TaskRunner 流水线绑定 | AMD: 调度层概念 |
| `VK_SIGNAL_SEMAPHORE` | TaskRunner 信号量处理 | AMD: 内部 semaphore |
| `VK_WAIT_SEMAPHORE` | TaskRunner 信号量等待 | AMD: 内部 semaphore |
| `VK_CREATE_FENCE` | TaskRunner fence 对象管理 | AMD: 内部 fence |
| `VK_WAIT_FENCE` | TaskRunner fence 等待 | AMD: `hsa_signal_wait_scacquire` |
| `BARRIER` | TaskRunner 依赖图屏障 | AMD: 内部依赖管理 |
| `FENCE` | TaskRunner fence 管理 | AMD: 内部 fence |
| `TASK` | TaskRunner 通用任务 | N/A |
| `MEMORY_ALLOC` | TaskRunner 通用内存分配 | N/A (纯 CPU) |
| `MEMORY_FREE` | TaskRunner 通用内存释放 | N/A (纯 CPU) |
| `MEMORY_COPY` | TaskRunner 纯 CPU 内存拷贝 | N/A (不涉及 GPU) |
| `BARRIER_SYNC` | TaskRunner 内部同步 | Phase 2 可能传递到设备层 |
| `FENCE_SIGNAL` | TaskRunner fence 信号 | Phase 2 可能传递到设备层 |

---

### 5.3 Phase 2 映射（规划）

**CTO 建议的更新映射**（基于 NVIDIA/AMD 调研）：

| TaskCommand | → | DeviceCommand | 说明 | 对标 |
|-------------|---|---------------|------|------|
| `BARRIER_SYNC` | → | `BARRIER_SYNC` | 队列内硬件屏障 | AMD: `HSA_PACKET_TYPE_BARRIER_AND` |
| `CUDA_STREAM_SYNC` | → | `BARRIER_SYNC` | 转为队列级屏障 | NVIDIA: semaphore between push buffers |
| `FENCE_SIGNAL` | → | `BARRIER_SYNC(SIGNAL)` | 信号写入 | AMD: `HSA_PACKET_TYPE_SIGNAL` |

> ⚠️ Phase 2 的具体映射规则将在协议版本升级到 v2 时另行更新。

---

## 六、CTO 建议与待确认事项

### ⚠️ 待确认 #2A：命令分类边界的理论依据

**CTO 分析**：

借鉴 NVIDIA 和 AMD 的设计，命令应该按**"数据平面 vs 控制平面"**分类：

```
                    ┌─────────────────────────────────────┐
                    │         TaskRunner (控制平面)        │
                    │                                      │
                    │  • Stream/Queue 生命周期管理          │
                    │  • Event/Fence 对象管理              │
                    │  • 依赖图构建                        │
                    │  • 内存池管理 (pool alloc/free)      │
                    │  • Pipeline 绑定                     │
                    │  • Buffer 对象管理                   │
                    │                                      │
                    └───────────────┬─────────────────────┘
                                    │
                  ┌─────────────────┼─────────────────┐
                  │                 │                 │
                  ▼                 ▼                 ▼
            ┌──────────┐    ┌──────────┐     ┌──────────┐
            │  KERNEL  │    │ DMA_COPY │     │ BARRIER  │ ← 数据平面
            │  (type=0)│    │ (type=1) │     │ (type=4) │
            └──────────┘    └──────────┘     └──────────┘
                                    │
                                    ▼
                    ┌─────────────────────────────────────┐
                    │       UsrLinuxEmu (数据平面)         │
                    │                                      │
                    │  • 命令执行 (内核/拷贝/屏障)          │
                    │  • 内存分配 (ioctl)                   │
                    │  • 同步等待 (ioctl, Phase 2)          │
                    │  • 队列管理 (ioctl, Phase 3)          │
                    └─────────────────────────────────────┘
```

**分类原则**（借鉴 NVIDIA libcuda 和 AMD ROCr）：

| 判断标准 | 留在 TaskRunner | 传递到 UsrLinuxEmu |
|---------|----------------|-------------------|
| 是否需要 GPU 硬件执行？ | ❌ | ✅ |
| 是否涉及资源生命周期？ | ❌ | ✅ (但用独立 ioctl，不用 CommandPacket) |
| 是否只影响调度依赖图？ | ✅ | ❌ |
| 是否有跨引擎含义？ | ✅ | ❌ |
| 是否需要零拷贝传递数据？ | ❌ | ✅ |

**结论**：当前 5/22 的分类**基本正确**，但有细微调整：

1. `CUDA_ALLOC` / `CUDA_FREE` 应该分两层：
   - TaskRunner 维护**内存池**（不传递到设备）
   - 内存池耗尽时调用 `GPGPU_ALLOC_MEM` ioctl（独立 ioctl，不通过 CommandPacket）

2. `BARRIER_SYNC` 在 Phase 2 应该传递到设备层：
   - AMD 的 AQL 有 `BARRIER_AND` packet，说明**队列内屏障是设备级操作**
   - NVIDIA 的 GPFIFO 有 semaphore acquire/release method，也是设备级

3. `CUDA_STREAM_SYNC` 可以转为 `BARRIER_SYNC` 传递：
   - 等同"等待队列中所有之前提交的任务完成"
   - AMD 的 `HSA_PACKET_TYPE_BARRIER_AND` 就是这个语义

### ⚠️ 待确认 #2B：UserMode Queue 的 Phase 规划

**CTO 建议的 Phase 3 UserMode Queue 架构**：

```
Phase 1 (现在):
  TaskRunner ──[ioctl: packet数组]──► UsrLinuxEmu

Phase 2 (同步):
  TaskRunner ──[ioctl: packet数组 + barrier]──► UsrLinuxEmu
  TaskRunner ──[ioctl: GPGPU_WAIT_SYNC]──► UsrLinuxEmu

Phase 3 (用户态队列):
  TaskRunner ──[直接写 ring buffer]──► Doorbell ──► UsrLinuxEmu (GPU 模拟器)
  TaskRunner ──[ioctl: 仅用于队列初始化和查询]──► UsrLinuxEmu
```

**对标参考**：
- AMD KFD 的 user-mode queue 是**最接近**我们目标的设计
- AQL packet 格式值得参考（但不用完全兼容，我们定义自己的格式）

**需要确认**：
- [ ] Phase 3 是否需要实现真正的"零拷贝 ring buffer + doorbell"模型？还是继续用 ioctl 传 packet 数组就够了？
- [ ] 如果需要零拷贝模型，UsrLinuxEmu 需要支持 `mmap` 映射 ring buffer，当前的 `FileOperations::mmap` 是否已经可用？

---

## 七、参数转换规则

### 7.1 KERNEL 命令参数映射

```
TaskRunner 输入                          UsrLinuxEmu 接收
─────────────────                       ─────────────────
CUDA_LAUNCH_KERNEL:                     KernelCommand:
  kernel_ptr ──────────────────────────► kernel_addr
  args_ptr   ──────────────────────────► args_addr
  args_size  ──────────────────────────► args_size
  smem       ──────────────────────────► shared_mem
  gridDim    ──────────────────────────► grid[3]
  blockDim   ──────────────────────────► block[3]

VK_DISPATCH_COMPUTE:                    KernelCommand:
  pipeline   ──────────────────────────► kernel_addr (转换后)
  push_const ──────────────────────────► args_addr
  groupCount ──────────────────────────► grid[3]
  (localSize)──────────────────────────► block[3] (从 pipeline 派生)
```

### 7.2 DMA_COPY 命令参数映射

```
TaskRunner 输入                          UsrLinuxEmu 接收
─────────────────                       ─────────────────
CUDA_COPY_H2D:                          DmaCommand:
  src_host   ──────────────────────────► src_phys (已注册的主机地址)
  dst_dev    ──────────────────────────► dst_phys
  bytes      ──────────────────────────► size
  (implicit) ──────────────────────────► direction = H2D

CUDA_COPY_D2H:                          DmaCommand:
  src_dev    ──────────────────────────► src_phys
  dst_host   ──────────────────────────► dst_phys (已注册的主机地址)
  bytes      ──────────────────────────► size
  (implicit) ──────────────────────────► direction = D2H

CUDA_COPY_D2D:                          DmaCommand:
  src_dev    ──────────────────────────► src_phys
  dst_dev    ──────────────────────────► dst_phys
  bytes      ──────────────────────────► size
  (implicit) ──────────────────────────► direction = D2D
```

---

## 八、CommandTranslator 接口定义

```cpp
namespace async_task {

class CommandTranslator {
public:
    /// 翻译单个命令
    static int translate(TaskCommand cmd,
                         const void* params,
                         GpuCommandPacket* out);

    /// 批量翻译
    static int translate_batch(const TaskCommand* commands,
                               const void** params,
                               size_t count,
                               GpuCommandPacket* out);

    /// 检查命令是否可翻译（即是否需要传递到 UsrLinuxEmu）
    static bool needs_device(TaskCommand cmd);
};

} // namespace async_task
```

---

## 九、错误处理

| 场景 | 处理策略 |
|------|---------|
| TaskCommand 无映射 | `needs_device()` 返回 false，TaskRunner 内部处理 |
| 参数转换失败 | 返回 `-EINVAL`，不生成 `GpuCommandPacket` |
| UsrLinuxEmu 不支持的 version | TaskRunner 降级到 v1 或报错 |
| 未知 TaskCommand | 记录日志，返回 `-EOPNOTSUPP` |

---

## 十、测试要求

```cpp
// Phase 1 测试用例
TEST(CommandTranslator, CudaLaunchKernel_TranslatesToKernel)
TEST(CommandTranslator, VkDispatchCompute_TranslatesToKernel)
TEST(CommandTranslator, CudaCopyH2D_TranslatesToDmaH2D)
TEST(CommandTranslator, CudaCopyD2H_TranslatesToDmaD2H)
TEST(CommandTranslator, CudaCopyD2D_TranslatesToDmaD2D)
TEST(CommandTranslator, CudaAlloc_NeedsNoDevice)
TEST(CommandTranslator, VkCreateFence_NeedsNoDevice)
TEST(CommandTranslator, UnknownCommand_ReturnsEOPNOTSUPP)
TEST(CommandTranslator, BatchTranslate_AllKernelCommands)
TEST(CommandTranslator, BatchTranslate_MixedCommands)

// Phase 2 测试用例（预留）
// TEST(CommandTranslator, BarrierSync_TranslatesToBarrier)
// TEST(CommandTranslator, StreamSync_TranslatesToBarrier)
// TEST(CommandTranslator, FenceSignal_TranslatesToBarrierSignal)
```

---

## 十一、各项目简略文档引用

### TaskRunner 侧

在 `docs/interfaces/command-translator.md` 中写：

```markdown
## CommandTranslator 映射

TaskRunner 的 TaskCommand 到 UsrLinuxEmu 的 DeviceCommand 映射关系。

Phase 1 支持：CUDA_LAUNCH_KERNEL → KERNEL, CUDA_COPY_* → DMA_COPY

> 📖 完整映射表（含 NVIDIA/AMD UserMode Queue 调研、参数转换、Phase 3 规划、测试要求）：
> `/workspace/mynotes/TaskRunerUsrLinuxEmu-Interface/DOC-03-command-translator.md`
```

### UsrLinuxEmu 侧

在 `docs/interfaces/command-translator.md` 中写：

```markdown
## CommandTranslator 映射

TaskRunner 向本设备提交的命令翻译规则（参考文档，TaskRunner 侧负责实现）。

> 📖 完整映射表（含 NVIDIA/AMD UserMode Queue 调研、Phase 3 规划）：
> `/workspace/mynotes/TaskRunerUsrLinuxEmu-Interface/DOC-03-command-translator.md`
```

---

**评审记录**:
- [ ] UsrLinuxEmu 维护者确认
- [ ] TaskRunner 维护者确认
- [ ] CTO 批准
