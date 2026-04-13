# DOC-02: DeviceCommand 协议

> **版本**: v1.0-draft  
> **日期**: 2026-04-13  
> **状态**: 待评审  
> **适用范围**: `GpuCommandPacket` 的完整结构定义、序列化格式、扩展规范

---

## 一、概述

本文档定义 UsrLinuxEmu 侧的 **DeviceCommand** 协议——即通过 ioctl `GPGPU_SUBMIT_PACKET` 传递的命令包的完整格式。

**设计原则**:
- 协议版本化：包头包含 version 字段，支持未来扩展
- 自描述：每个命令包包含自身大小，支持变长数据
- 零拷贝优先：大数据块通过共享内存传递，包内只传地址

---

## 二、协议版本

```cpp
// 当前协议版本（写入每个 GpuCommandPacket 头部）
#define DEVICE_COMMAND_PROTOCOL_VERSION 1u
```

| 版本 | 说明 |
|------|------|
| v1 | 基础版本：KERNEL + DMA_COPY |
| v2 (规划) | 扩展：MEMORY_ALLOC / FREE / BARRIER_SYNC |

---

## 三、命令包头部

```cpp
struct CommandHeader {
    uint32_t version;       // 协议版本号，当前为 1
    uint32_t type;          // CommandType 枚举值
    uint32_t size;          // 整个包的总大小（含 header + payload）
    uint32_t flags;         // 标志位（见下表）
    uint64_t sequence_id;   // 命令序列号（用于调试和排序）
};
```

**flags 位定义**:

| 位 | 名称 | 说明 |
|----|------|------|
| 0 | `CMD_FENCE` | 此命令完成后触发 fence |
| 1 | `CMD_SYNC` | 同步执行（阻塞直到完成） |
| 2 | `CMD_PRIORITY_HIGH` | 高优先级 |
| 3 | `CMD_NO_CALLBACK` | 不触发完成回调 |
| 4-31 | 保留 | 必须为 0 |

---

## 四、CommandType 枚举

### Phase 1 (当前)

```cpp
enum class CommandType : uint32_t {
    KERNEL   = 0,   // 内核函数执行
    DMA_COPY = 1,   // DMA 内存拷贝
};
```

### Phase 2 (规划，预留编号)

```cpp
    MEMORY_ALLOC   = 2,   // 设备内存分配
    MEMORY_FREE    = 3,   // 设备内存释放
    BARRIER_SYNC   = 4,   // 同步屏障
    MMIO_ACCESS    = 5,   // MMIO 寄存器访问
```

> ⚠️ 新增命令必须在**两端同时实现**后才能启用。TaskRunner 在 v1 协议下不得发送 type >= 2 的命令。

---

## 五、命令 Payload 定义

### 5.1 KernelCommand (type=0)

```cpp
struct KernelCommand {
    uint64_t kernel_addr;       // 内核函数入口地址（设备物理地址）
    uint64_t args_addr;         // 参数缓冲区地址（设备物理地址）
    uint32_t args_size;         // 参数缓冲区大小（字节）
    uint32_t shared_mem;        // 共享内存大小（字节）
    uint32_t grid[3];           // Grid 维度 (x, y, z)
    uint32_t block[3];          // Block 维度 (x, y, z)
    uint32_t padding;           // 对齐填充
};
```

**字段说明**:
| 字段 | 说明 |
|------|------|
| kernel_addr | PTX/固件编译后的入口点地址 |
| args_addr | 内核参数的物理地址，通过 `GPGPU_ALLOC_MEM` 分配 |
| args_size | 参数总大小，用于边界检查 |
| shared_mem | 动态 shared memory 大小（类似 CUDA 的 `dynamic_smem`） |
| grid/block | 线程层级配置，0 表示该维度为 1 |

**执行流程**:
```
TaskRunner                    UsrLinuxEmu
    │                             │
    ├─ GPGPU_ALLOC_MEM(args) ────►│
    │◄─ phys_addr ────────────────┤
    │                             │
    ├─ 写入参数到 phys_addr ──────►│ (用户态直接写共享内存)
    │                             │
    ├─ GPGPU_SUBMIT_PACKET ──────►│
    │  (KernelCommand)            │
    │                             ├─ 仿真执行内核
    │◄─ callback / 完成事件 ──────┤
```

---

### 5.2 DmaCommand (type=1)

```cpp
enum class DmaDirection : uint32_t {
    H2D = 0,    // Host → Device
    D2H = 1,    // Device → Host
    D2D = 2,    // Device → Device
};

struct DmaCommand {
    uint64_t src_phys;      // 源物理地址
    uint64_t dst_phys;      // 目的物理地址
    uint64_t size;          // 拷贝大小（字节）
    uint32_t direction;     // DmaDirection 枚举值
    uint32_t stride;        // 步幅（0 表示连续拷贝）
    uint64_t callback_id;   // 完成回调 ID（0 表示无回调）
};
```

**字段说明**:
| 字段 | 说明 |
|------|------|
| src_phys / dst_phys | 必须是有效的设备物理地址（由 `GPGPU_ALLOC_MEM` 分配或用户态注册） |
| size | 拷贝字节数，必须 > 0 |
| direction | 决定 src/dst 哪边是 host 哪边是 device |
| stride | 2D/3D 拷贝时的行步幅，0 表示线性连续拷贝 |
| callback_id | 异步完成通知 ID，0 表示不通知 |

**地址空间约束**:

| direction | src 地址空间 | dst 地址空间 |
|-----------|-------------|-------------|
| H2D | CPU 虚拟地址（已注册） | 设备物理地址 |
| D2H | 设备物理地址 | CPU 虚拟地址（已注册） |
| D2D | 设备物理地址 | 设备物理地址 |

> CPU 虚拟地址必须通过 `GPGPU_ALLOC_MEM(SYSTEM_CACHED/SYSTEM_UNCACHED)` 预先注册。

---

### 5.3 MemoryAllocCommand (type=2，Phase 2 规划)

```cpp
struct MemoryAllocCommand {
    uint64_t size;                  // 请求大小
    uint32_t space_type;            // AddressSpaceType
    uint32_t alignment;             // 对齐要求（0 表示默认）
    uint64_t result_phys;           // OUT: 分配的设备物理地址
    uint64_t result_cpu_ptr;        // OUT: 映射的 CPU 指针
};
```

### 5.4 MemoryFreeCommand (type=3，Phase 2 规划)

```cpp
struct MemoryFreeCommand {
    uint64_t phys_addr;     // 要释放的物理地址（句柄）
};
```

### 5.5 BarrierCommand (type=4，Phase 2 规划)

```cpp
enum class BarrierOp : uint32_t {
    SIGNAL = 0,
    WAIT = 1,
};

struct BarrierCommand {
    uint64_t barrier_id;    // 屏障 ID
    uint32_t operation;     // BarrierOp
    uint32_t padding;
};
```

---

## 六、完整 GpuCommandPacket 结构

```cpp
// Phase 1 实际使用的结构
struct GpuCommandPacket {
    // 头部
    uint32_t version;       // = 1
    uint32_t type;          // CommandType
    uint32_t size;          // 包总字节数
    uint32_t flags;         // 标志位
    uint64_t sequence_id;   // 序列号

    // Payload (union)
    union {
        struct {
            uint64_t kernel_addr;
            uint64_t args_addr;
            uint32_t args_size;
            uint32_t shared_mem;
            uint32_t grid[3];
            uint32_t block[3];
            uint32_t padding;
        } kernel;

        struct {
            uint64_t src_phys;
            uint64_t dst_phys;
            uint64_t size;
            uint32_t direction;
            uint32_t stride;
            uint64_t callback_id;
        } dma;
    };
};
```

---

## 七、序列化与对齐

### 7.1 内存布局

- 所有结构体按 **8 字节对齐**
- `CommandHeader` 固定 24 字节
- 各 Payload 大小:
  - KernelCommand: 56 字节
  - DmaCommand: 48 字节
  - 完整包大小 (Phase 1):
    - KERNEL: 24 + 56 = **80 字节**
    - DMA_COPY: 24 + 48 = **72 字节**

### 7.2 批量提交

```cpp
// GpuCommandRequest 可以提交多个连续的命令包
struct GpuCommandRequest {
    const void* packet_ptr;   // 指向 GpuCommandPacket 数组
    size_t packet_size;       // 数组中的包数量（不是字节数）
};
```

**内存布局示例**:
```
packet_ptr → [Header+Payload][Header+Payload][Header+Payload] ...
              ← size=N1    → ← size=N2    → ← size=N3    →
```

UsrLinuxEmu 按顺序解析每个包，通过 `Header::size` 定位下一个包的起始位置。

### 7.3 字节序

- 所有字段使用 **主机字节序**（x86_64 = little-endian）
- 跨平台场景由 TaskRunner 侧负责转换

---

## 八、错误处理

### 8.1 包级错误

| 错误 | 行为 |
|------|------|
| `version != 1` | 返回 `-EOPNOTSUPP`，拒绝整个批次 |
| `type` 超出范围 | 返回 `-EINVAL`，拒绝整个批次 |
| `size` 与实际不符 | 返回 `-EINVAL`，拒绝整个批次 |
| 物理地址无效 | 返回 `-EFAULT`，拒绝整个批次 |

### 8.2 批量提交的原子性

- **Phase 1**: 非原子——部分命令可能已执行，遇到错误后停止后续命令
- **Phase 2**: 可选原子模式（通过 `flags` 控制）

---

## 九、各项目简略文档引用

### UsrLinuxEmu 侧

在 `docs/interfaces/device-command.md` 中写：

```markdown
## DeviceCommand 协议

定义通过 `GPGPU_SUBMIT_PACKET` 传递的命令包格式。

当前支持: KERNEL, DMA_COPY

> 📖 完整协议（含序列化、扩展规划、错误处理）：
> `/workspace/mynotes/TaskRunerUsrLinuxEmu-Interface/DOC-02-device-command-protocol.md`
```

### TaskRunner 侧

在 `docs/interfaces/device-command.md` 中写：

```markdown
## DeviceCommand 协议

TaskRunner 向 UsrLinuxEmu 提交的命令包格式。

> 📖 完整协议（含序列化、扩展规划、错误处理）：
> `/workspace/mynotes/TaskRunerUsrLinuxEmu-Interface/DOC-02-device-command-protocol.md`
```

---

**评审记录**:
- [ ] UsrLinuxEmu 维护者确认
- [ ] TaskRunner 维护者确认
- [ ] CTO 批准
