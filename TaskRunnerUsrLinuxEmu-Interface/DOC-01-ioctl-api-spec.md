# DOC-01: ioctl API 规范

> **版本**: v1.1-draft  
> **日期**: 2026-04-13  
> **状态**: 待评审  
> **适用范围**: UsrLinuxEmu ↔ TaskRunner 之间的 ioctl 接口契约

---

## 一、概述

本文档定义 UsrLinuxEmu 对外暴露的全部 ioctl 接口，是 TaskRunner 侧实现 `CommandTranslator` 的唯一权威参考。

**设计原则**:
- 向后兼容：已定义的 ioctl 编号和结构体**永不修改字段**，只能追加
- 错误码标准化：统一使用负值 errno，与 Linux 内核一致
- 线程安全：每个 ioctl 调用必须可重入

---

## 二、NVIDIA/AMD 驱动 ioctl 设计调研

### 2.1 NVIDIA 驱动架构 (`nvidia.ko` + `nvidia-uvm.ko`)

NVIDIA 使用**双设备模型**：

| 设备节点 | 用途 | 典型 ioctl |
|---------|------|-----------|
| `/dev/nvidiaN` | GPU 设备控制 | `NV_ESC_GET_CARD_INFO`, `NV_ESC_ALLOC_MEMORY`, `NV_ESC_RM_CONTROL` |
| `/dev/nvidia-uvm` | 统一虚拟内存管理 | `UVM_INITIALIZE`, `UVM_ALLOC`, `UVM_FREE`, `UVM_MAP_EXTERNAL` |
| `/dev/nvidiactl` | 全局控制 | `NV_ESC_REGISTER_GPU`, `NV_ESC_ATTACH_GPUS_TO_FD` |

**关键设计模式**:

1. **GPFIFO 命令提交**（Fermi+ 架构）:
   - 用户态通过 `NV_ESC_ALLOC_GPFIFO` 获取 GPFIFO 通道
   - 用户态**直接写入 GPFIFO ring buffer**（mmap 映射）
   - 通过 `NV_ESC_LAUNCH_DMA` 触发硬件执行（doorbell 机制）
   - **ioctl 只用于初始化和触发，不传具体命令数据**

2. **RM Control 通道**:
   - `NV_ESC_RM_CONTROL` 是万能 ioctl，通过 `cmd` 参数区分 200+ 子命令
   - 子命令编号是连续的：0x020000~0x020200
   - 这种"一个 ioctl，无数子命令"的设计**减少了 ioctl 编号消耗**

3. **内存管理分离**:
   - UVM 驱动独立管理虚拟内存
   - 物理内存分配通过 `/dev/nvidiaN`
   - 映射关系由 UVM 维护

### 2.2 AMD 驱动架构 (`amdgpu.ko`)

AMD 使用**统一的 DRM 设备模型**：

| ioctl 分类 | 典型 ioctl | 说明 |
|-----------|-----------|------|
| **内存管理** | `DRM_AMDGPU_GEM_CREATE` | 创建 GEM buffer object |
| | `DRM_AMDGPU_GEM_MMAP` | 映射到用户态 |
| | `DRM_AMDGPU_VA` | 虚拟地址空间管理 |
| **命令提交** | `DRM_AMDGPU_CS` | 命令流提交 |
| | `DRM_AMDGPU_WAIT_CS` | 等待命令完成 |
| **上下文** | `DRM_AMDGPU_CTX` | 创建/销毁上下文 |
| **同步** | `DRM_AMDGPU_FENCE` | Fence 操作 |
| | `DRM_AMDGPU_SYNCOBJ` | 同步对象 |

**关键设计模式**:

1. **命令流 (Command Stream)**:
   - 用户态在用户态缓冲区构建完整的命令流 (IB — Indirect Buffer)
   - 通过 `DRM_AMDGPU_CS` 提交一个 IB 列表
   - ioctl 参数是指向 IB 的指针 + 数量，**不是命令数据本身**

2. **同步对象 (Sync Objects)**:
   - `DRM_AMDGPU_SYNCOBJ_CREATE/DESTROY/WAIT/SIGNAL`
   - 独立的 ioctl 编号，与命令提交分离
   - 支持 timeline fence（带单调递增值的 fence）

3. **编号策略**:
   - DRM ioctl 编号从 0x00 开始连续分配
   - 每类功能有连续的编号段
   - 中间**不跳号**，需要新命令时追加到末尾

### 2.3 核心设计模式总结

| 设计要素 | NVIDIA | AMD | 对我们的启示 |
|---------|--------|-----|------------|
| **命令提交方式** | GPFIFO ring buffer (mmap) + doorbell | IB 列表提交 (指针引用) | 我们都用 packet 数组提交，类似 AMD 的 CS |
| **内存管理** | 独立 UVM 设备节点 | GEM + VA ioctl | 我们应该用独立 ioctl 处理内存 |
| **同步原语** | Event ioctl (独立) | SyncObject ioctl (独立) | 同步应该用独立 ioctl，不混在命令提交中 |
| **编号策略** | 按功能分组，组内连续 | 全局连续追加 | **推荐：按功能分组，组内连续，组间预留** |
| **上下文** | RM Control 子命令 | CTX ioctl | 上下文管理用独立 ioctl |
| **用户态队列** | GPFIFO (用户态写 ring) | 用户态构建 IB | 我们当前的 packet 提交已支持 |

---

## 三、ioctl 编号策略建议

### 3.1 借鉴 NVIDIA/AMD 的分组编号法

根据调研，我们采用**按功能分组、组内连续、组间预留**的策略：

| 编号范围 | 功能组 | NVIDIA 对应 | AMD 对应 | 状态 |
|---------|--------|------------|---------|------|
| **0x00-0x0F** | 设备信息查询 | `NV_ESC_GET_CARD_INFO` | `DRM_AMDGPU_INFO` | ✅ 已有 0 |
| **0x10-0x1F** | 内存管理 | `NV_ESC_ALLOC_MEMORY`, UVM ioctls | `GEM_CREATE`, `GEM_MMAP`, `VA` | ✅ 已有 1,2 |
| **0x20-0x2F** | 命令提交 | `NV_ESC_LAUNCH_DMA`, GPFIFO | `DRM_AMDGPU_CS` | ✅ 已有 5 |
| **0x30-0x3F** | 上下文管理 | `NV_ESC_RM_CONTROL` (子命令) | `DRM_AMDGPU_CTX` | 🔜 预留 |
| **0x40-0x4F** | 同步原语 | `NV0005_CTRL_CMD_EVENT` | `SYNCOBJ`, `FENCE` | 🔜 预留 |
| **0x50-0x5F** | 队列管理 | GPFIFO alloc/setup | KFD user-mode queue | 🔜 预留 |
| **0x60-0x6F** | 调试/Profiling | `NV_ESC_PROFILING` | `DRM_AMDGPU_QUERY` | 🔜 远期 |

### 3.2 当前编号重新映射

```
┌─────────────────────────────────────────────────────┐
│ 0x00  GPGPU_GET_DEVICE_INFO   [已有]  设备信息查询   │
│ 0x01  GPGPU_ALLOC_MEM         [已有]  内存管理        │
│ 0x02  GPGPU_FREE_MEM          [已有]  内存管理        │
│ 0x03  ─ 预留 ─                                        │
│ 0x04  ─ 预留 ─                                        │
│ 0x05  GPGPU_SUBMIT_PACKET     [已有]  命令提交        │
│ 0x06  ─ 预留 ─                                        │
│ 0x07  ─ 预留 ─                                        │
│ ...                                                   │
│ 0x0F  ─ 组内预留 ─                                    │
├─────────────────────────────────────────────────────┤
│ 0x10  GPGPU_MAP_MEMORY        [规划]  内存映射         │
│ 0x11  GPGPU_UNMAP_MEMORY      [规划]  内存解映射       │
│ 0x12  ─ 预留 ─                                        │
│ ... 0x1F ─ 组内预留 ─                                 │
├─────────────────────────────────────────────────────┤
│ 0x20  GPGPU_WAIT_SUBMIT       [规划]  等待提交完成     │
│ ... 0x2F ─ 组内预留 ─                                 │
├─────────────────────────────────────────────────────┤
│ 0x30  GPGPU_CREATE_CONTEXT    [规划]  上下文管理       │
│ 0x31  GPGPU_DESTROY_CONTEXT   [规划]  上下文管理       │
│ ... 0x3F ─ 组内预留 ─                                 │
├─────────────────────────────────────────────────────┤
│ 0x40  GPGPU_CREATE_SYNC       [规划]  同步对象创建     │
│ 0x41  GPGPU_DESTROY_SYNC      [规划]  同步对象销毁     │
│ 0x42  GPGPU_WAIT_SYNC         [规划]  同步等待         │
│ 0x43  GPGPU_SIGNAL_SYNC       [规划]  同步信号         │
│ ... 0x4F ─ 组内预留 ─                                 │
├─────────────────────────────────────────────────────┤
│ 0x50  GPGPU_CREATE_QUEUE      [规划]  用户态队列       │
│ 0x51  GPGPU_DESTROY_QUEUE     [规划]  队列销毁         │
│ 0x52  GPGPU_RING_DOORBELL     [规划]  门铃触发         │
│ ... 0x5F ─ 组内预留 ─                                 │
└─────────────────────────────────────────────────────┘
```

### 3.3 CTO 建议

**关于 ioctl vs CommandPacket 的职责划分**：

借鉴 NVIDIA 的 GPFIFO 和 AMD 的 CS 设计，建议：

| 操作 | 应该用 ioctl | 应该用 CommandPacket |
|------|-------------|---------------------|
| 查询设备信息 | ✅ `GPGPU_GET_DEVICE_INFO` | ❌ |
| 分配/释放内存 | ✅ `GPGPU_ALLOC_MEM` / `FREE_MEM` | ❌ |
| 提交计算/拷贝任务 | ❌ | ✅ `GPGPU_SUBMIT_PACKET` |
| 等待任务完成 | ✅ `GPGPU_WAIT_SUBMIT` (Phase 2) | ❌ |
| 同步栅栏操作 | ✅ `GPGPU_WAIT/SIGNAL_SYNC` (Phase 2) | ❌ |
| 用户态队列操作 | ✅ `GPGPU_CREATE/DESTROY_QUEUE` (Phase 3) | ❌ |
| 门铃触发 | ✅ `GPGPU_RING_DOORBELL` (Phase 3) | ❌ |

**核心理念**：
- ioctl 用于**控制平面**（control plane）：创建资源、配置参数、等待状态
- CommandPacket 用于**数据平面**（data plane）：提交工作任务

---

## 四、结构体定义

### 4.1 GpuDeviceInfo（输出）

```cpp
struct GpuDeviceInfo {
    char   name[64];        // 设备名称，如 "GPGPU-Emulator"
    uint64_t memory_size;   // 显存总大小（字节）
    int    max_queues;      // 最大命令队列数
    int    compute_units;   // 计算单元数量
};
```

### 4.2 GpuMemoryRequest（输入/输出）

```cpp
enum class AddressSpaceType : uint32_t {
    FB_PUBLIC = 0,      // 帧缓冲，公开访问
    FB_PRIVATE = 1,     // 帧缓冲，上下文私有
    SYSTEM_CACHED = 2,  // 系统内存，可缓存
    SYSTEM_UNCACHED = 3,// 系统内存，不可缓存
    DEVICE_SVM = 4,     // 设备共享虚拟内存
    MMIO_REMAP = 5      // MMIO 重映射
};

struct GpuMemoryRequest {
    uint64_t size;                  // IN:  请求分配大小（字节）
    AddressSpaceType space_type;    // IN:  地址空间类型
    uint64_t phys_addr;             // OUT: 分配的物理地址（句柄）
    uint64_t cpu_ptr;               // OUT: 用户态 CPU 可访问指针（如可映射）
};
```

### 4.3 GpuCommandRequest（输入）

```cpp
struct GpuCommandRequest {
    const void* packet_ptr;   // IN: GpuCommandPacket 数组指针
    size_t packet_size;       // IN: 数组中命令包的数量（不是字节数！）
};
```

---

## 五、GpuCommandPacket 结构

> ⚠️ 本文档仅列出概要，详细定义见 [DOC-02: DeviceCommand 协议](./DOC-02-device-command-protocol.md)

```cpp
enum class CommandType : uint32_t {
    KERNEL = 0,
    DMA_COPY = 1,
    // Phase 2 扩展:
    // MEMORY_ALLOC = 2,
    // MEMORY_FREE = 3,
    // BARRIER_SYNC = 4,
};

struct GpuCommandPacket {
    CommandType type;
    uint32_t size;  // 包总大小（字节），用于变长包解析
    union {
        KernelCommand kernel;
        DmaCommand    dma;
    };
};
```

---

## 六、错误码规范

| 错误码 | 值 | 含义 | TaskRunner 应对策略 |
|--------|-----|------|-------------------|
| `0` | 0 | 成功 | 继续 |
| `-EINVAL` | -22 | 参数无效 | 检查参数，上报 bug |
| `-EFAULT` | -14 | 用户态地址不可访问 | 检查指针有效性 |
| `-ENOMEM` | -12 | 内存不足 | 释放资源后重试 |
| `-EAGAIN` | -11 | 资源暂不可用 | 指数退避后重试 |
| `-EBUSY` | -16 | 设备忙 | 等待后重试 |
| `-ENODEV` | -19 | 设备不存在 | 检查设备初始化 |
| `-EOPNOTSUPP` | -95 | 命令不支持 | 降级处理或报错 |

---

## 七、线程安全保证

| 操作 | 线程安全 | 说明 |
|------|---------|------|
| `GPGPU_GET_DEVICE_INFO` | ✅ 无锁 | 只读操作 |
| `GPGPU_ALLOC_MEM` | ✅ 内部锁保护 | 内存管理器有锁 |
| `GPGPU_FREE_MEM` | ✅ 内部锁保护 | 与 ALLOC 共享锁 |
| `GPGPU_SUBMIT_PACKET` | ✅ 队列级锁 | 每个队列独立锁 |
| 同一队列的多次 SUBMIT | ⚠️ 顺序保证 | 不保证跨队列顺序 |

---

## 八、向后兼容策略

| 场景 | 策略 |
|------|------|
| 新增 ioctl 命令号 | 追加编号，不影响已有命令 |
| 结构体新增字段 | 只能在**末尾**追加，且需增加 `version` 字段或 size 检查 |
| 废弃命令 | 保留编号，返回 `-EOPNOTSUPP`，**永不重新分配** |
| TaskRunner 使用旧版 UsrLinuxEmu | 通过 `GPGPU_GET_DEVICE_INFO` 查询能力位 |

---

## 九、CTO 建议与待确认事项

### ⚠️ 待确认 #1A：ioctl 编号分组策略

**现状变更**：基于 NVIDIA/AMD 驱动调研，已将编号策略从"连续预留"改为**"按功能分组、组内连续、组间预留"**。

**CTO 建议**：

采用分组策略（见第三节表格）的理由：
1. **NVIDIA** 的 UVM 驱动就是这样设计的：内存管理、GPFIFO、事件各占独立编号段
2. **AMD** 的 DRM ioctl 也是按 GEM/CS/CTX/SYNC 分组
3. 分组让代码维护更清晰——看到编号就知道属于哪个子系统
4. 组间预留空间方便未来扩展，不会"挤压"已有编号

**需要确认**：
- [ ] 是否接受从 0x10 开始的分组编号方案？（当前只用了 0,1,2,5）
- [ ] Phase 2 的同步原语是否独立为 0x40-0x4F 组？还是先用 0x20-0x2F 组？

### ⚠️ 待确认 #1B：Phase 2 扩展方式

**CTO 建议**：

Phase 2 的内存管理和同步**应该用独立 ioctl**，不要扩展 `GPGPU_SUBMIT_PACKET` 的 CommandType：

| 功能 | 推荐方式 | 理由 |
|------|---------|------|
| 内存分配/释放 | ✅ `GPGPU_ALLOC_MEM` / `FREE_MEM`（已有） | 已有，不需要新 ioctl |
| 内存映射/解映射 | ✅ 新增 `GPGPU_MAP_MEMORY` / `UNMAP` (0x10-0x11) | 独立的控制操作 |
| 同步等待 | ✅ 新增 `GPGPU_WAIT_SYNC` (0x42) | NVIDIA 有独立 event ioctl，AMD 有独立的 fence ioctl |
| 任务提交中的 barrier | ✅ 扩展 CommandType (type=4) | 这是数据平面操作，属于 CommandPacket |

**核心区分原则**：
- 如果操作涉及**资源生命周期管理**（创建、销毁、映射）→ 独立 ioctl
- 如果操作涉及**工作任务的执行顺序**（barrier between tasks）→ 扩展 CommandType

**需要确认**：
- [ ] 是否认同"控制平面用 ioctl，数据平面用 CommandPacket"的区分原则？
- [ ] Phase 2 是否先做同步原语的 ioctl（0x40 组），还是先扩展 CommandPacket 的 CommandType？

---

## 十、各项目简略文档引用

### UsrLinuxEmu 侧 (简略说明)

在 `docs/interfaces/ioctl-api.md` 中只需写：

```markdown
## ioctl API

UsrLinuxEmu 通过 `/dev/gpgpu0` 设备节点对外提供 ioctl 接口。

当前支持的命令：
- `GPGPU_GET_DEVICE_INFO` — 查询设备信息
- `GPGPU_ALLOC_MEM` — 分配 GPU 内存
- `GPGPU_FREE_MEM` — 释放 GPU 内存
- `GPGPU_SUBMIT_PACKET` — 提交命令包

> 📖 完整规范（含结构体定义、错误码、兼容性策略、NVIDIA/AMD 设计参考）：
> `/workspace/mynotes/TaskRunerUsrLinuxEmu-Interface/DOC-01-ioctl-api-spec.md`
```

### TaskRunner 侧 (简略说明)

在 `docs/interfaces/usrlinuxemu-ioctl.md` 中只需写：

```markdown
## UsrLinuxEmu ioctl 接口

TaskRunner 通过 ioctl 向 UsrLinuxEmu 提交 GPU 命令。

> 📖 完整规范（含结构体定义、错误码、兼容性策略、NVIDIA/AMD 设计参考）：
> `/workspace/mynotes/TaskRunerUsrLinuxEmu-Interface/DOC-01-ioctl-api-spec.md`
```

---

**评审记录**:
- [ ] UsrLinuxEmu 维护者确认
- [ ] TaskRunner 维护者确认
- [ ] CTO 批准
