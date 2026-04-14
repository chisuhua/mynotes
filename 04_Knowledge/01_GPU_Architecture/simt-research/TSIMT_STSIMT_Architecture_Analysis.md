# TSIMT/STSIMT 架构深度解析

> **文档版本**: v1.0  
> **创建日期**: 2026-04-14  
> **基于论文**: Lucas et al., "Spatiotemporal SIMT and Scalarization for Improving GPU Efficiency", ACM TACO 2015  
> **作者机构**: Technische Universität Berlin (柏林工业大学)

---

## 📋 目录

- [1. 研究背景与动机](#1-研究背景与动机)
- [2. TSIMT架构详解](#2-tsimt架构详解)
- [3. STSIMT混合架构](#3-stsimt混合架构)
- [4. 标量化优化技术](#4-标量化优化技术)
- [5. 性能评估与分析](#5-性能评估与分析)
- [6. 实现细节与挑战](#6-实现细节与挑战)
- [7. 与HPST架构的对比](#7-与hpst架构的对比)
- [8. 总结与启示](#8-总结与启示)

---

## 1. 研究背景与动机

### 1.1 传统SIMT的局限性

#### **空间SIMT执行模型**

传统GPU采用**空间并行**的SIMT（Single Instruction Multiple Threads）模型：

```
传统SIMT执行示例 (Warp Size = 32):

Cycle 1: [T0  T1  T2  ... T31]  ← 所有32个线程同时执行
Cycle 2: [T0  T1  T2  ... T31]
Cycle 3: [T0  T1  T2  ... T31]
...

遇到分支发散时:
if (threadIdx.x < 16) {
    // Branch A
} else {
    // Branch B
}

Cycle 1-10: Execute Branch A with mask [1,1,...,1,0,0,...,0]
            Threads 16-31 are IDLE but still occupy execution units
            
Cycle 11-20: Execute Branch B with inverted mask
             Threads 0-15 are IDLE

总周期: 20 cycles
资源利用率: 50% (严重浪费!)
```

**核心问题**：
- ❌ **分支发散导致执行单元闲置**
- ❌ **固定warp分组无法适应不规则工作负载**
- ❌ **Masked execution浪费能量和时间**

#### **性能瓶颈量化**

论文通过实验发现：
- 在实际应用中，**SIMD效率**（活跃线程比例）平均仅为**60-70%**
- 高度发散的内核（如图算法）效率可降至**30%以下**
- 这意味着**30-70%的计算资源被浪费**

### 1.2 研究目标

提出一种新的执行模型，能够：
1. ✅ **消除分支发散带来的资源浪费**
2. ✅ **提高硬件利用率**
3. ✅ **保持或提升整体性能**
4. ✅ **降低能耗延迟积（EDP）**

---

## 2. TSIMT架构详解

### 2.1 核心设计理念

**TSIMT (Temporal SIMT)** 的核心思想是：**将线程从空间维度转移到时间维度执行**。

```
传统SIMT (Spatial):
Lane 0: [T0 T1 T2 ... T31]  ← 空间并行，32个ALU
Lane 1: [T0 T1 T2 ... T31]
...

TSIMT (Temporal):
Lane 0: T0 → T1 → T2 → ... → T31  ← 时间串行，1个ALU
Lane 1: T0 → T1 → T2 → ... → T31
Lane 2: T0 → T1 → T2 → ... → T31
...
Lane 31: T0 → T1 → T2 → ... → T31

关键差异:
• 每个lane只处理一个warp
• 线程逐个周期顺序执行
• 类似单通道向量处理器
```

### 2.2 微架构设计

#### **2.2.1 整体架构**

```
┌──────────────────────────────────────────────────────┐
│                  TSIMT GPU Architecture               │
├──────────────────────────────────────────────────────┤
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │           Global Warp Scheduler                 │  │
│  │  • Warp分配器                                  │  │
│  │  • 负载均衡器                                  │  │
│  └──────────────────┬─────────────────────────────┘  │
│                     │                                 │
│  ┌──────────────────▼─────────────────────────────┐  │
│  │        Streaming Multiprocessor (SM)            │  │
│  │                                                  │  │
│  │  ┌──────┐ ┌──────┐ ┌──────┐     ┌──────┐      │  │
│  │  │Lane 0│ │Lane 1│ │Lane 2│ ... │Lane31│      │  │
│  │  │      │ │      │ │      │     │      │      │  │
│  │  │ ALU  │ │ ALU  │ │ ALU  │     │ ALU  │      │  │
│  │  └──┬───┘ └──┬───┘ └──┬───┘     └──┬───┘      │  │
│  │     │        │        │            │           │  │
│  │  ┌──▼────────▼────────▼────────────▼───┐      │  │
│  │  │   Register File (32 independent     │      │  │
│  │  │    narrow banks, one per lane)      │      │  │
│  │  └─────────────────────────────────────┘      │  │
│  └──────────────────────────────────────────────┘  │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │              Memory Subsystem                   │  │
│  │  • L1 Cache                                    │  │
│  │  • Shared Memory                               │  │
│  │  • Load/Store Units                            │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

#### **2.2.2 Lane结构**

每个TSIMT lane包含：
- **1个ALU**: 执行算术/逻辑运算
- **独立寄存器文件**: 窄而深的RF bank
- **PC计数器**: 跟踪当前执行的线程
- **Active Mask**: 标记哪些线程是活跃的

```cpp
struct TSIMT_Lane {
    ALU alu;                      // 单个执行单元
    RegisterFile rf;              // 独立的寄存器文件
    uint32_t current_thread_id;   // 当前执行的线程ID (0-31)
    uint32_t active_mask;         // 32-bit活跃线程掩码
    uint32_t pc;                  // 程序计数器
    Warp* assigned_warp;          // 分配给此lane的warp
    
    // 执行状态
    enum State {
        IDLE,           // 空闲
        EXECUTING,      // 正在执行
        WAITING_MEMORY, // 等待内存访问
        COMPLETED       // warp执行完成
    } state;
};
```

#### **2.2.3 执行流程**

```
TSIMT执行一个warp的完整流程:

初始化:
  Lane 0 分配 Warp W0
  current_thread_id = 0
  
执行循环:
  while (current_thread_id < 32) {
    
    1. FETCH阶段:
       - 从W0的PC取指
       - 检查Thread[current_thread_id]是否活跃
       
    2. DECODE阶段:
       - 解码指令
       - 准备操作数
       
    3. EXECUTE阶段:
       if (active_mask[current_thread_id]) {
           alu.execute(instruction, operands);
       } else {
           // 跳过非活跃线程，无浪费!
       }
       
    4. WRITEBACK阶段:
       - 写回结果到寄存器
       
    5. UPDATE阶段:
       current_thread_id++;
       
       // 如果是分支指令
       if (is_branch(instruction)) {
           update_pc_based_on_condition();
       }
  }
  
  // Warp执行完成，释放资源
  release_warp(W0);
  assign_new_warp();
```

### 2.3 关键优势：指令压缩（Instruction Compaction）

#### **原理**

TSIMT的最大优势是**只对活跃线程执行指令**，天然避免了masked execution的浪费。

```
示例：高度发散的分支

代码:
if (threadIdx.x % 4 == 0) {  // 只有8个threads满足条件
    result = complex_computation();
}

传统SIMT执行:
  Cycle 1-100: Fetch & Execute with mask [1,0,0,0,1,0,0,0,...]
               32 threads fetched, but only 8 execute
               24 execution units IDLE → 75% waste!
               
TSIMT执行:
  Lane 0: 
    Thread 0: active → execute (Cycle 1-100)
    Thread 1: inactive → skip (0 cycles)
    Thread 2: inactive → skip (0 cycles)
    Thread 3: inactive → skip (0 cycles)
    Thread 4: active → execute (Cycle 101-200)
    ...
    
  总周期: 8 × 100 = 800 cycles (仅活跃线程)
  但分布在8个lanes并发: 800 / 8 = 100 cycles
  
  资源利用率: 100% (无浪费!)
  加速比: 与传统SIMT相同，但能效更高
```

#### **理论加速比**

对于发散率为 `d` 的warp（`d` = 活跃线程比例）：

```
Speedup_TSIMIT = 1 / d

示例:
• d = 0.25 (8/32活跃): Speedup = 4×
• d = 0.5 (16/32活跃): Speedup = 2×
• d = 1.0 (32/32活跃): Speedup = 1× (无加速)
```

### 2.4 TSIMT的问题与挑战

#### **问题1：负载均衡困难**

**现象**：
```
假设8个lanes，分配了8个warps:

Lane 0: Warp 0 (1000 instructions)
Lane 1: Warp 1 (1000 instructions)
...
Lane 7: Warp 7 (1000 instructions)

如果Warp 0-3很快完成，而Warp 4-7还在执行:
  Lane 0-3: IDLE (浪费!)
  Lane 4-7: BUSY
  
负载不均衡导致性能下降
```

**根本原因**：
- Warps静态分配到lanes
- 不同warps的执行时间差异大
- 缺乏动态负载均衡机制

#### **问题2：Occupancy要求高**

**定义**：Occupancy = 活跃warps数 / 最大支持warps数

```
低Occupancy场景:

只有4个warps可用，但有8个lanes:
  Lane 0-3: 执行warps
  Lane 4-7: IDLE
  
性能损失: 50%

论文实验发现:
• 当warps < 8时，性能急剧下降
• 某些基准测试出现50%的性能退化
```

#### **问题3：延迟隐藏能力减弱**

**传统SIMT的优势**：
```
当一个warp等待内存时，立即切换到另一个warp:

Warp 0: [Execute] → [Memory Wait] → [Switch to Warp 1]
Warp 1: [Execute] → [Memory Wait] → [Switch to Warp 0]

通过上下文切换隐藏内存延迟
```

**TSIMT的劣势**：
```
每个lane只有一个warp:

Lane 0: Warp 0 [Execute] → [Memory Wait] → [STALL]
         无法切换，必须等待

需要更多lanes或更长的指令级并行来补偿
```

#### **问题4：指令发布带宽需求高**

```
传统SIMT:
  每周期发布1条指令，32个lanes并行执行
  指令带宽: 1 instruction/cycle
  
TSIMT:
  每个lane每周期都需要新指令
  32个lanes需要: 32 instructions/cycle
  
挑战:
  前端需要4×的指令发布带宽
  指令缓存压力增大
```

### 2.5 实验结果

#### **微基准测试**

论文使用自定义微基准测试验证TSIMT理论性能：

| 测试场景 | 活跃线程数 | TSIMT加速比 |
|---------|-----------|------------|
| 极度发散 | 2/32 | **16×** |
| 高度发散 | 8/32 | **4×** |
| 中等发散 | 16/32 | **2×** |
| 无发散 | 32/32 | 1× |

#### **实际基准测试**

使用Rodinia等真实应用测试：

```
总体结果:
• 平均性能: -7.3% (相比传统SIMT)
• 最佳案例: GAU_1 (+15%)
• 最差案例: LUD_1 (-35%)

分析:
✓ 高发散内核受益
✗ 低发散内核受损
✗ 负载均衡问题严重
```

**关键发现**：
> 纯TSIMT在实际应用中表现不佳，主要原因是**负载均衡问题**和**occupancy不足**。

---

## 3. STSIMT混合架构

### 3.1 设计动机

为了解决纯TSIMT的问题，论文提出**时空混合SIMT**（Spatio-Temporal SIMT, STSIMT）：

```
设计目标:
1. 保留TSIMT的指令压缩优势
2. 改善负载均衡
3. 增强延迟隐藏能力
4. 降低指令带宽需求

核心思路:
在每个lane内引入适度的空间并行度
```

### 3.2 STSIMT架构设计

#### **3.2.1 基本概念**

```
STSIMT-N: 每个lane有N个ALU (N-wide)

STSIMT-4示例:
┌─────────────────────────────────────┐
│         SM with 8 Lanes             │
│                                     │
│  Lane 0: [ALU0 ALU1 ALU2 ALU3]     │  ← 4-wide
│  Lane 1: [ALU0 ALU1 ALU2 ALU3]     │
│  Lane 2: [ALU0 ALU1 ALU2 ALU3]     │
│  ...                                │
│  Lane 7: [ALU0 ALU1 ALU2 ALU3]     │
│                                     │
│  Total ALUs: 8 × 4 = 32            │
└─────────────────────────────────────┘

执行模式:
• Lane内: 空间并行 (4 threads同时)
• Lane间: 时间并行 (不同warps/paths)
• 混合: Spatio-temporal flexibility
```

#### **3.2.2 Thread映射策略**

```
Warp到STSIMT-4 Lanes的映射:

Warp (32 threads) 分配到 8 lanes:

Lane 0: Threads [0, 1, 2, 3]    ← 4 threads
Lane 1: Threads [4, 5, 6, 7]
Lane 2: Threads [8, 9, 10, 11]
Lane 3: Threads [12, 13, 14, 15]
Lane 4: Threads [16, 17, 18, 19]
Lane 5: Threads [20, 21, 22, 23]
Lane 6: Threads [24, 25, 26, 27]
Lane 7: Threads [28, 29, 30, 31]

执行:
Cycle 1: All 8 lanes execute their 4 threads in parallel
         Total: 32 threads executed in 1 cycle (if uniform)

遇到分支发散:
if (threadIdx.x < 16) {
    // Branch A: Threads 0-15
} else {
    // Branch B: Threads 16-31
}

Lane 0-3: Execute Branch A (Threads 0-15)
Lane 4-7: Execute Branch B (Threads 16-31)

两组合并发，无需序列化!
```

#### **3.2.3 微架构细节**

```cpp
struct STSIMT_Lane {
    ALU alus[4];                // 4个ALU (4-wide)
    RegisterFile rf;            // 共享寄存器文件
    uint32_t thread_ids[4];     // 当前分配的4个线程ID
    uint32_t active_mask_4bit;  // 4-bit活跃掩码
    
    // 执行状态机
    enum State {
        FETCH,
        DISPATCH,   // 分发到4个ALU
        EXECUTE,    // 4个ALU并行执行
        WRITEBACK,
        NEXT_THREAD_GROUP  // 移动到下一组4个线程
    } state;
    
    Warp* assigned_warp;
    int current_thread_group;  // 当前处理的thread group (0-7)
};

// SM级别
struct STSIMT_SM {
    STSIMT_Lane lanes[8];       // 8个4-wide lanes
    WarpScheduler scheduler;
    RegisterFile scalar_rf;     // 标量寄存器 (per warp)
    RegisterFile vector_rf;     // 向量寄存器 (per lane)
};
```

### 3.3 STSIMT的优势

#### **优势1：改善负载均衡**

```
传统TSIMT问题:
  Lane 0-3: 完成早，IDLE
  Lane 4-7: 仍在执行
  
STSIMT-4改进:
  每个lane处理4个threads
  即使某些threads慢，其他3个可以继续
  粒度更细，负载均衡更好
  
效果:
  Lane利用率从~50%提升到~75%
```

#### **优势2：保持部分指令压缩**

```
示例：16个活跃threads (50%发散)

传统SIMT:
  Cycle 1-100: Execute with 50% mask
  Waste: 50%
  
TSIMT:
  16 active threads × 100 cycles = 1600 thread-cycles
  Distributed across 8 lanes: 200 cycles
  Compression: 2×
  
STSIMT-4:
  16 threads / 4 (width) = 4 thread-groups
  4 groups × 100 cycles = 400 cycles
  Distributed across 8 lanes: 50 cycles
  Compression: 2× (same as TSIMT for this case)
  
关键: STSIMT-4在适度发散时接近TSIMT性能
```

#### **优势3：降低指令带宽需求**

```
指令带宽需求:

Pure TSIMT (32 lanes):
  32 instructions/cycle
  
STSIMT-4 (8 lanes):
  8 instructions/cycle
  
Reduction: 4× lower bandwidth requirement
  
好处:
• 前端设计更简单
• 指令缓存压力减小
• 功耗降低
```

#### **优势4：更好的延迟隐藏**

```
内存访问延迟隐藏:

传统SIMT:
  Warp-level context switching
  Need many warps to hide latency
  
STSIMT-4:
  Within a lane: 4 threads can overlap
  Across lanes: 8 lanes can interleave
  
Effective concurrency: 8 × 4 = 32 threads
Similar to traditional SIMT but more flexible
```

### 3.4 STSIMT配置对比

论文评估了多种STSIMT配置：

| 配置 | Lanes | Width | Total ALUs | 特点 |
|------|-------|-------|-----------|------|
| **Pure TSIMT** | 32 | 1 | 32 | 最大压缩，负载不均 |
| **STSIMT-2** | 16 | 2 | 32 | 平衡点 |
| **STSIMT-4** | 8 | 4 | 32 | **最佳平衡** ⭐ |
| **STSIMT-8** | 4 | 8 | 32 | 接近传统SIMT |
| **Traditional** | 1 | 32 | 32 | 无压缩，均匀负载 |

### 3.5 STSIMT-4性能评估

#### **实验设置**

```
基准测试集:
• Rodinia Suite (图算法、生物信息学等)
• GPGPU-Sim benchmarks
• 共37个kernels

分类:
• High divergence (SIMD efficiency < 85%): 15 kernels
• Low divergence (SIMD efficiency ≥ 85%): 22 kernels

模拟器: Extended GPGPU-Sim
工艺: 40nm technology node
```

#### **性能结果**

```
Overall Performance (Geometric Mean):

Configuration          Performance vs Traditional SIMT
------------------------------------------------------
Pure TSIMT             -7.3%
STSIMT-2               +3.2%
STSIMT-4               +5.6%  ← Best overall
STSIMT-8               +2.1%

High Divergence Kernels:
STSIMT-4               +8.0%  ← Significant improvement

Low Divergence Kernels:
STSIMT-4               +4.2%  ← Modest improvement
```

**关键洞察**：
> STSIMT-4在所有类别中都优于传统SIMT，特别是在高发散应用中表现出色。

#### **案例分析**

**最佳案例：GAU_1 (高斯消元)**
```
特性:
• 高度不规则的控制流
• 大量条件分支
• SIMD效率: ~40%

结果:
• Traditional SIMT: Baseline
• STSIMT-4: +25% speedup
• 原因: 指令压缩充分发挥作用
```

**最差案例：LUD_1 (LU分解)**
```
特性:
• 规则的控制流
• 少量分支
• SIMD效率: ~95%

结果:
• Traditional SIMT: Baseline
• STSIMT-4: -5% slowdown
• 原因: 负载均衡开销超过压缩收益
```

---

## 4. 标量化优化技术

### 4.1 标量化的基本概念

#### **什么是标量化？**

```
标量化 (Scalarization): 
识别warp中所有线程使用相同操作数的指令，
只需执行一次，而非每线程一次。

示例:

__global__ void kernel(float scale, float* data) {
    int tid = threadIdx.x;
    
    // scale对所有threads相同 → 可标量化
    data[tid] = data[tid] * scale;
}

传统SIMT执行:
  Thread 0: data[0] * scale
  Thread 1: data[1] * scale  ← scale重复加载32次!
  Thread 2: data[2] * scale
  ...
  Thread 31: data[31] * scale
  
标量化执行:
  Step 1: Load scale once to scalar register
  Step 2: Broadcast to all threads
  Step 3: Each thread multiplies with its own data
  
节省:
• 31次冗余内存读取
• 31次冗余寄存器读取
• 减少寄存器压力
```

#### **标量化的层次**

```
1. 编译器标量化 (Compiler Scalarization):
   • 静态分析检测uniform值
   • 生成标量指令
   
2. 硬件标量化 (Hardware Scalarization):
   • 运行时检测uniformity
   • 动态选择标量/向量路径
   
3. 混合标量化 (Hybrid):
   • 编译器提示 + 硬件验证
   • 最灵活的方案
```

### 4.2 论文1的标量化创新

#### **4.2.1 前人工作的局限**

**Lee et al. 2013的方法**：
```cpp
// 传统标量化条件 (过于保守)
if (control_flow_is_convergent) {
    scalarize(register);
}

问题:
• 只在收敛控制流中标量化
• 错过大量标量化机会
• 标量化率: ~13.5%
```

#### **4.2.2 改进的标量化算法**

**核心创新**：放宽标量化条件

```cpp
// 论文1的新方法
if (register_dies_before_reconvergence_point) {
    scalarize(register);  // 即使控制流发散也可标量
}

原理:
• 只要寄存器在重汇聚点之前"死亡"（不再使用）
• 就可以安全地标量化
• 不需要保证控制流收敛

效果:
• 标量化率: 13.5% → 30.3% (2.25×提升!)
• 寄存器压力减少: 26.1%
```

#### **4.2.3 算法实现**

```cpp
/**
 * 检测寄存器是否可标量化
 * 
 * @param reg: 待分析的寄存器
 * @param cfg: 控制流图
 * @param reconvergence_points: 重汇聚点集合
 * @return: 是否可标量化
 */
bool canScalarize(Register reg, CFG& cfg, 
                  set<BasicBlock*> reconvergence_points) {
    
    // 1. 找到寄存器的所有定义点
    vector<Instruction*> defs = findAllDefinitions(reg);
    
    // 2. 找到寄存器的所有使用点
    vector<Instruction*> uses = findAllUses(reg);
    
    // 3. 检查是否存在发散的使用
    for (auto use : uses) {
        BasicBlock* bb = use->getParent();
        
        // 如果使用点在重汇聚点之后
        if (isAfterReconvergence(bb, reconvergence_points)) {
            return false;  // 不能标量化
        }
    }
    
    // 4. 检查所有定义是否产生相同值
    if (!allDefsProduceSameValue(defs)) {
        return false;
    }
    
    // 5. 检查寄存器是否在重汇聚点前死亡
    if (registerDiesBeforeReconvergence(reg, reconvergence_points)) {
        return true;  // 可以标量化!
    }
    
    return false;
}

/**
 * 检查寄存器是否在重汇聚点前死亡
 */
bool registerDiesBeforeReconvergence(Register reg, 
                                     set<BasicBlock*> reconvergence_pts) {
    
    // 找到最后使用点
    Instruction* last_use = findLastUse(reg);
    BasicBlock* last_use_bb = last_use->getParent();
    
    // 检查所有重汇聚点
    for (auto reconvergence_bb : reconvergence_pts) {
        // 如果最后使用点在重汇聚点之前
        if (dominates(last_use_bb, reconvergence_bb)) {
            return true;  // 寄存器在重汇聚前死亡
        }
    }
    
    return false;
}
```

### 4.3 TSIMT中的标量化优势

#### **硬件成本极低**

```
传统SIMT的标量化硬件:

需要:
• 独立的标量执行单元
• 广播网络 (broadcast network)
• 额外的寄存器文件
• 复杂的调度逻辑

面积开销: ~15-20% of SM
```

```
TSIMT/STSIMT的标量化硬件:

利用现有资源:
• 复用相同的ALU (本来就是串行的)
• 复用相同的寄存器文件
• 无需额外广播网络
• 简单的uniformity检测器

面积开销: ~2-3% of SM

优势:
✓ 几乎零额外成本
✓ 自然支持标量执行
✓ 易于实现
```

#### **Uniformity检测器**

```cpp
// 硬件模块: 快速检测4个操作数是否相同
module UniformityDetector_4wide (
    input  [31:0] operand_values[4],
    input  [3:0]  active_mask,
    output reg    is_uniform,
    output reg [31:0] uniform_value
);
    always @(*) begin
        is_uniform = 1;
        uniform_value = 0;
        int first_active_idx = -1;
        
        for (int i = 0; i < 4; i++) begin
            if (active_mask[i]) begin
                if (first_active_idx == -1) begin
                    // 第一个活跃thread
                    uniform_value = operand_values[i];
                    first_active_idx = i;
                end else begin
                    // 比较后续threads
                    if (operand_values[i] != uniform_value) begin
                        is_uniform = 0;
                    end
                end
            end
        end
        
        // 如果没有活跃threads，默认uniform
        if (first_active_idx == -1) begin
            is_uniform = 1;
        end
    end
endmodule

// 面积: ~500 gates (极小)
// 延迟: 1 cycle
```

### 4.4 STSIMT-4 + 标量化的综合效果

#### **性能提升**

```
配置对比 (Geometric Mean):

Configuration          Performance    EDP Improvement
----------------------------------------------------------
Traditional SIMT       1.0×           Baseline
TSIMT                  0.94×          N/A
STSIMT-4               1.056×         -9.5%
STSIMT-4 + Scalar      1.196×         -26.2%  ← Best!

提升分解:
• STSIMT-4基础提升: +5.6%
• 标量化额外提升: +13.3%
• 总计: +19.6%
```

#### **寄存器压力减少**

```
每Warp所需寄存器数:

Without Scalarization:
  Average: 48 registers/warp
  
With Scalarization:
  Average: 35.5 registers/warp
  
Reduction: 26.1%

好处:
✓ 更高的occupancy
✓ 更好的延迟隐藏
✓ 减少寄存器溢出到内存
```

#### **能效改善**

```
Energy-Delay Product (EDP):

EDP = Energy × Delay²

Traditional SIMT: EDP = 1.0
STSIMT-4 + Scalar: EDP = 0.738

Improvement: 26.2%

分解:
• Delay减少: 1/1.196 = 0.836
• Energy增加: 1.056 (略增，因控制逻辑)
• EDP = 1.056 × 0.836² = 0.738
```

---

## 5. 性能评估与分析

### 5.1 实验方法论

#### **基准测试集**

```
来源:
• Rodinia Benchmark Suite
• GPGPU-Sim standard benchmarks
• Parboil
• SHOC

总数: 37 kernels

分类标准 (SIMD Efficiency):
• High Divergence (< 85%): 15 kernels
  - BFS, SSSP (图算法)
  - Hotspot (热传导模拟)
  - Gauassian (高斯消元)
  
• Low Divergence (≥ 85%): 22 kernels
  - SRAD (图像去噪)
  - LUD (LU分解)
  - NN (神经网络)
```

#### **评估指标**

```
1. 性能 (Performance):
   • Execution time
   • Speedup vs baseline
   
2. 能效 (Energy Efficiency):
   • Energy consumption
   • Power draw
   • EDP (Energy-Delay Product)
   • EDP² (Energy-Delay² Product)
   
3. 资源利用 (Resource Utilization):
   • SIMD efficiency
   • Occupancy
   • Register pressure
   • Lane utilization
   
4. 可扩展性 (Scalability):
   • Performance vs warp count
   • Performance vs divergence rate
```

### 5.2 详细性能结果

#### **5.2.1 整体性能**

```
Geometric Mean Speedup:

┌─────────────────────┬──────────┬──────────┬───────────┐
│ Configuration       │ All      │ High Div │ Low Div   │
├─────────────────────┼──────────┼──────────┼───────────┤
│ Traditional SIMT    │ 1.00×    │ 1.00×    │ 1.00×     │
│ Pure TSIMT          │ 0.927×   │ 1.15×    │ 0.82×     │
│ STSIMT-2            │ 1.032×   │ 1.12×    │ 0.98×     │
│ STSIMT-4            │ 1.056×   │ 1.08×    │ 1.04×     │
│ STSIMT-8            │ 1.021×   │ 1.05×    │ 1.01×     │
│ STSIMT-4 + Scalar   │ 1.196×   │ 1.28×    │ 1.14×     │
└─────────────────────┴──────────┴──────────┴───────────┘

关键观察:
✓ STSIMT-4在所有类别中最平衡
✓ 标量化带来显著额外收益
✓ 纯TSIMT在低发散时表现差
```

#### **5.2.2 按应用分类**

**图算法 (高发散)**:
```
BFS (Breadth-First Search):
  Traditional: 1.0×
  STSIMT-4: 1.22×
  STSIMT-4+Scalar: 1.35×
  
  原因:
  • 不规则内存访问
  • 大量条件分支
  • SIMD效率: ~45%
  
SSSP (Single-Source Shortest Path):
  Traditional: 1.0×
  STSIMT-4: 1.18×
  STSIMT-4+Scalar: 1.31×
```

**线性代数 (低发散)**:
```
SGEMM (矩阵乘法):
  Traditional: 1.0×
  STSIMT-4: 1.02×
  STSIMT-4+Scalar: 1.08×
  
  原因:
  • 规则的控制流
  • 高度并行
  • SIMD效率: ~98%
  
LUD (LU分解):
  Traditional: 1.0×
  STSIMT-4: 0.95×
  STSIMT-4+Scalar: 1.03×
  
  注意: 轻微下降，因负载均衡开销
```

**图像处理**:
```
SRAD (Speckle Reducing Anisotropic Diffusion):
  Traditional: 1.0×
  STSIMT-4: 1.06×
  STSIMT-4+Scalar: 1.15×
  
Hotspot (热传导):
  Traditional: 1.0×
  STSIMT-4: 1.11×
  STSIMT-4+Scalar: 1.24×
```

### 5.3 负载均衡分析

#### **Lane利用率分布**

```
测量指标: Lane Utilization = Busy Cycles / Total Cycles

Pure TSIMT:
  Average: 62%
  Std Dev: 18%  ← 高方差，负载不均
  
STSIMT-2:
  Average: 71%
  Std Dev: 12%
  
STSIMT-4:
  Average: 78%  ← 最佳平衡
  Std Dev: 8%
  
STSIMT-8:
  Average: 82%
  Std Dev: 5%
  
Traditional SIMT:
  Average: 85%
  Std Dev: 3%  ← 最均匀，但无压缩
```

**可视化**:
```
Lane Utilization Distribution:

Pure TSIMT:     [====||||||........] 62% ±18%
STSIMT-2:       [=====|||||.......] 71% ±12%
STSIMT-4:       [======||||......] 78% ±8%   ← Sweet spot
STSIMT-8:       [=======|||.....] 82% ±5%
Traditional:    [========||....] 85% ±3%

理想: 高平均值 + 低方差
STSIMT-4达到最佳权衡
```

#### **Warp分配策略的影响**

```
实验: 不同warp数量的影响

Warps Available    TSIMT Perf    STSIMT-4 Perf
------------------------------------------------
4                  0.50×         0.85×
8                  0.75×         0.95×
16                 0.92×         1.04×
32                 1.00×         1.06×
64                 1.02×         1.07×

观察:
• TSIMT对warp数量极其敏感
• STSIMT-4更加鲁棒
• 32+ warps后趋于稳定
```

### 5.4 功耗与能效分析

#### **功耗组成**

```
Power Breakdown (STSIMT-4 vs Traditional):

Component          Traditional    STSIMT-4    Change
-------------------------------------------------------
ALUs               45%            42%         -3%
Register File      20%            18%         -2%
Control Logic      10%            15%         +5%  ← Overhead
Memory Subsystem   15%            14%         -1%
Clock Distribution 10%            11%         +1%
-------------------------------------------------------
Total              100%           100%        

Absolute Power:
  Traditional: 5.2W
  STSIMT-4: 5.5W (+5.6%)
  
原因:
• ALU活动减少 (少执行masked指令)
• 但控制逻辑增加 (path management)
• 净效应: 小幅增加
```

#### **能效指标**

```
Energy-Delay Product (EDP):

Formula: EDP = Energy × Delay²

Normalized EDP:
  Traditional SIMT: 1.00
  Pure TSIMT: 0.95
  STSIMT-4: 0.905
  STSIMT-4 + Scalar: 0.738  ← 26.2% improvement
  
Interpretation:
• Lower EDP = Better energy efficiency
• STSIMT-4+Scalar delivers best EDP
• Worth the slight power increase
```

```
Energy-Delay² Product (EDP²):

Emphasizes performance more heavily:

  Traditional SIMT: 1.00
  STSIMT-4 + Scalar: 0.615  ← 38.5% improvement
  
Use case:
• EDP: Balanced metric
• EDP²: Performance-critical applications
```

### 5.5 敏感性分析

#### **Warp Size的影响**

```
实验: 改变warp size

Warp Size    STSIMT-4 Perf    Notes
------------------------------------------
16           1.08×           Better load balance
32           1.056×          Default (NVIDIA)
64           1.03×           Worse compression

结论:
• 较小warp (16) 改善负载均衡
• 但减少指令级并行
• 32是合理折中
```

#### **Lane数量的影响**

```
固定32 ALUs，不同配置:

Config       Lanes    Width    Perf
------------------------------------
TSIMT        32       1        0.927×
STSIMT-2     16       2        1.032×
STSIMT-4     8        4        1.056×  ← Optimal
STSIMT-8     4        8        1.021×
SIMT         1        32       1.00×

Sweet spot: 8 lanes × 4-wide
```

---

## 6. 实现细节与挑战

### 6.1 寄存器文件设计

#### **分层寄存器架构**

```
Traditional SIMT RF:
┌─────────────────────────────┐
│  Single Wide RF Bank        │
│  256 registers × 32 threads │
│  × 32 bits = 256 KB         │
│                             │
│  Pros: Simple               │
│  Cons: Large area, high     │
│        access latency       │
└─────────────────────────────┘
  Area: 2.27 mm² @ 40nm
```

```
TSIMT/STSIMT RF:
┌─────────────────────────────┐
│  Scalar RF (Per Warp)       │
│  32 regs × 32 bits = 128 B  │
│  For uniform values         │
└──────────┬──────────────────┘
           │
┌──────────▼──────────────────┐
│  Vector RF Banks            │
│  Lane 0: 64 regs × 4 thr    │
│  Lane 1: 64 regs × 4 thr    │
│  ...                        │
│  Lane 7: 64 regs × 4 thr    │
│  Total: 8 KB                │
└─────────────────────────────┘
  Area: 0.49 mm² @ 40nm
  
Advantage:
• 5.6× smaller area
• Lower access latency
• Better scalability
```

#### **寄存器访问逻辑**

```cpp
// 智能寄存器访问：自动选择scalar或vector
uint32_t readRegister(uint8_t reg_id, uint8_t thread_id, uint8_t lane_id) {
    
    if (reg_metadata[reg_id].is_scalar) {
        // 从Scalar RF读取，广播
        return scalar_rf.read(reg_id);
    } else {
        // 从Vector RF读取
        uint8_t pos = thread_id % 4;  // Position in lane
        return vector_rf[lane_id].read(reg_id, pos);
    }
}

void writeRegister(uint8_t reg_id, uint8_t thread_id, uint8_t lane_id, 
                   uint32_t value) {
    
    if (reg_metadata[reg_id].is_scalar) {
        scalar_rf.write(reg_id, value);
    } else {
        uint8_t pos = thread_id % 4;
        vector_rf[lane_id].write(reg_id, pos, value);
    }
}
```

### 6.2 内存访问合并

#### **全局内存合并**

```
STSIMT-4的内存访问模式:

Scenario: Coalesced access
  Lane 0: Threads [0,1,2,3] access addresses [A, A+4, A+8, A+12]
  → Can be coalesced into single 128-byte transaction
  
Scenario: Uncoalesced access
  Lane 0: Threads [0,1,2,3] access addresses [A, B, C, D] (random)
  → 4 separate transactions
  
Challenge:
• Within-lane coalescing similar to traditional SIMT
• But cross-lane patterns may differ
```

#### **共享内存Bank冲突**

```
Traditional SIMT:
  Warp accesses shared memory
  Bank conflicts within warp possible
  
STSIMT-4:
  No intra-warp bank conflicts!
  (Threads in same lane access sequentially)
  
But:
  Inter-warp bank conflicts possible
  (Different warps in different lanes)
  
Mitigation:
  • Padding
  • Bank conflict detection hardware
```

### 6.3 指令发布带宽

#### **带宽需求分析**

```
Traditional SIMT:
  Issue 1 instruction/cycle
  32 lanes execute in parallel
  
Pure TSIMT:
  Issue 32 instructions/cycle (one per lane)
  Challenge: 32× higher bandwidth
  
STSIMT-4:
  Issue 8 instructions/cycle (one per lane)
  Manageable: 8× higher than traditional
  
Solution:
  • Wider issue width
  • Multiple issue ports
  • Instruction cache banking
```

#### **指令缓存设计**

```
I-Cache Requirements:

Traditional:
  1 fetch/cycle × 4 bytes = 4 bytes/cycle
  
STSIMT-4:
  8 fetches/cycle × 4 bytes = 32 bytes/cycle
  
Design:
  • 8-banked I-Cache
  • Each bank serves one lane
  • Parallel fetch capability
  
Area overhead: ~10% larger I-Cache
```

### 6.4 死锁避免

#### **潜在死锁场景**

```cuda
__shared__ int flag = 0;

// Threads 0-15 (if branch)
if (threadIdx.x < 16) {
    flag = 1;
    while (flag == 0);  // Wait for threads 16-31
}
// Threads 16-31 (else branch)
else {
    while (flag == 0);  // Wait for threads 0-15
    flag = 1;
}

Problem:
• In traditional SIMT: Both branches execute sequentially
• In TSIMT/STSIMT: Different lanes may execute different branches
• Potential deadlock if synchronization crosses lanes
```

#### **解决方案**

```
1. Compiler Analysis:
   • Detect potential deadlocks at compile time
   • Insert warnings or restructure code
   
2. Hardware Detection:
   • Monitor lane progress
   • Detect stalls
   • Force context switch
   
3. Programming Guidelines:
   • Avoid cross-lane synchronization
   • Use atomic operations instead
   • Explicit barriers
```

### 6.5 编译器支持

#### **LLVM Pass集成**

```cpp
class STSIMTOptimizer : public ModulePass {
public:
    bool runOnModule(Module &M) override {
        for (auto &F : M.functions()) {
            if (isGPUKernel(F)) {
                optimizeForSTSIMT(F);
            }
        }
        return true;
    }
    
private:
    void optimizeForSTSIMT(Function &F) {
        // 1. Detect scalarizable operations
        detectAndMarkScalars(F);
        
        // 2. Optimize register allocation
        optimizeRegAllocation(F);
        
        // 3. Insert convergence hints
        insertConvergenceHints(F);
        
        // 4. Optimize memory access patterns
        optimizeMemoryAccess(F);
    }
    
    void detectAndMarkScalars(Function &F) {
        // Data flow analysis to find uniform values
        for (auto &BB : F) {
            for (auto &I : BB) {
                if (isUniformAcrossWarp(&I)) {
                    I.setMetadata("stsimt.scalar", 
                        MDNode::get(I.getContext(), {}));
                }
            }
        }
    }
};
```

#### **PTX扩展**

```ptx
// Hints for STSIMT optimizer

// Mark uniform value
mov.uniform.f32 %scalar_val, %input;

// Convergence point hint
@converge bar.sync 0;

// Scalar operation hint
@scalar mul.f32 %result, %a, %uniform_b;
```

---

## 7. 与HPST架构的对比

### 7.1 设计理念对比

| 维度 | STSIMT-4 (论文1) | HPST (我们的设计) |
|------|-----------------|------------------|
| **基本思想** | 固定4-wide lanes | Path-based + 4-wide lanes |
| **调度单位** | Warp | Path |
| **分支处理** | Masked execution within lane | Path splitting/fusion |
| **灵活性** | 中等 | 高 |
| **复杂度** | 中 | 中高 |

### 7.2 技术特性对比

```
Branch Divergence Handling:

STSIMT-4:
  if (condition) {
      // Branch A
  } else {
      // Branch B
  }
  
  Execution:
  Lane 0: Threads [0,1,2,3]
    - Check condition for each thread
    - Execute A or B based on mask
    - Some threads may be idle
    
HPST:
  Same code
  
  Execution:
  Path 1: Threads where condition=true
  Path 2: Threads where condition=false
  
  - Two paths scheduled independently
  - No idle threads within a path
  - More flexible scheduling
```

### 7.3 性能预期对比

| 指标 | STSIMT-4 | HPST (预期) |
|------|---------|------------|
| 高发散性能 | +8% | **+25-35%** |
| 负载均衡 | Good | **Better** |
| 死锁避免 | Manual care | **Guaranteed (BFS)** |
| 非结构化CF | Limited | **Full support** |
| 硬件复杂度 | Medium | Medium-High |

### 7.4 HPST的改进

```
HPST builds upon STSIMT-4:

1. Path-based Flexibility:
   • Dynamic path splitting (like paper 3)
   • Better handling of irregular control flow
   
2. Adaptive Scheduling:
   • DFS/BFS policy selection
   • Avoid livelocks automatically
   
3. Enhanced Scalarization:
   • Combine paper 1's algorithm
   • With path-aware optimization
   
4. Better Convergence:
   • Explicit path fusion
   • No reconvergence stack needed
```

---

## 8. 总结与启示

### 8.1 主要贡献总结

#### **论文1的核心贡献**

1. ✅ **首个完整的TSIMT微架构设计与实现**
   - 详细的硬件设计
   - GPGPU-Sim扩展
   - 全面的评估

2. ✅ **揭示TSIMT的实际问题**
   - 负载均衡困难
   - Occupancy敏感性
   - 指令带宽需求

3. ✅ **提出STSIMT混合架构**
   - 平衡压缩与负载均衡
   - STSIMT-4为最佳配置
   - 平均性能+5.6%

4. ✅ **改进的标量化算法**
   - 放宽标量化条件
   - 标量化率2.25×提升
   - 寄存器压力-26.1%

5. ✅ **综合优化效果显著**
   - STSIMT-4 + 标量化: +19.6%性能
   - EDP改善: -26.2%

### 8.2 关键洞察

#### **洞察1：纯理论最优 ≠ 实际最优**

```
TSIMT理论:
  • Perfect compaction
  • Zero waste
  
TSIMT实际:
  • Load imbalance
  • Low occupancy sensitivity
  • Net performance: -7.3%
  
Lesson:
  理论分析必须结合实际约束
  Hybrid approaches often win
```

#### **洞察2：适度并行是关键**

```
Pure Serial (TSIMT): Too rigid
Pure Parallel (SIMT): Wasteful
Hybrid (STSIMT-4): Just right!

8 lanes × 4-wide = Sweet spot
  • Enough parallelism for load balance
  • Enough seriality for compaction
```

#### **洞察3：标量化成本低收益高**

```
TSIMT/STSIMT天然适合标量化:
  • No extra hardware needed
  • Reuse existing ALUs
  • 2.25× more scalarized instructions
  • 26.1% less register pressure
  
Recommendation:
  Always enable scalarization in TSIMT-like architectures
```

### 8.3 对未来架构的启示

#### **启示1：灵活性至关重要**

```
Fixed warp grouping (Traditional/SIMT): Rigid
Fixed lane assignment (TSIMT): Too rigid
Dynamic path management (HPST): Flexible

Future GPUs need:
  • Dynamic thread grouping
  • Adaptive execution models
  • Context-aware scheduling
```

#### **启示2：软硬件协同设计**

```
Hardware alone (TSIMT): Limited
Software alone (MoS methods): Overhead
Co-design (STSIMT + Compiler): Effective

Best practice:
  • Hardware provides primitives
  • Compiler exploits opportunities
  • Runtime adapts to workload
```

#### **启示3：能效与性能并重**

```
Performance-focused: Higher power
Energy-focused: Lower performance
Balanced (EDP optimization): Best value

STSIMT-4 + Scalar achieves:
  • +19.6% performance
  • -26.2% EDP
  
This is the right metric for modern GPUs
```

### 8.4 开放问题与未来方向

#### **未解决的问题**

1. **动态Lane宽度调整**
   ```
   Current: Fixed 4-wide
   Future: Adaptive width based on divergence?
   Challenge: Hardware complexity
   ```

2. **跨SM的路径迁移**
   ```
   Current: Paths stay within SM
   Future: Migrate paths between SMs for load balance?
   Challenge: State transfer overhead
   ```

3. **机器学习驱动的调度**
   ```
   Current: Heuristic policies
   Future: RL-based adaptive scheduling?
   Challenge: Training overhead, generalization
   ```

#### **研究方向**

1. **异构计算集成**
   - CPU-GPU协同的路径管理
   - 多加速器间的工作负载平衡

2. **量子启发执行模型**
   - 概率性路径执行
   - 叠加态类比的路径并行

3. **面向AI的专用优化**
   - Transformer模型的稀疏注意力
   - GNN的不规则图遍历
   - 推荐系统的嵌入查找

### 8.5 实践建议

#### **对于GPU架构师**

```
✅ Do:
• Consider hybrid spatio-temporal designs
• Enable scalarization by default
• Balance flexibility and complexity
• Measure EDP, not just performance

❌ Don't:
• Pursue pure theoretical optima
• Ignore load balancing
• Underestimate software support needs
• Forget backward compatibility
```

#### **对于编译器开发者**

```
✅ Do:
• Implement advanced scalarization
• Provide path/convergence hints
• Optimize for register pressure
• Support adaptive execution

❌ Don't:
• Assume uniform control flow
• Ignore hardware capabilities
• Over-complicate IR
• Neglect debugging support
```

#### **对于应用开发者**

```
✅ Do:
• Profile divergence patterns
• Use uniform variables when possible
• Minimize cross-thread synchronization
• Test on target architecture

❌ Don't:
• Assume all branches are equal
• Ignore memory access patterns
• Over-use dynamic parallelism
• Skip performance validation
```

---

## 📚 参考文献

[1] Jan Lucas, Michael Andersch, Mauricio Alvarez-Mesa, Ben Juurlink. "Spatiotemporal SIMT and Scalarization for Improving GPU Efficiency". ACM Transactions on Architecture and Code Optimization, Vol. 12, No. 3, Article 32, September 2015. DOI: 10.1145/2806888

[2] Caroline Collange. "GPU architecture: Revisiting the SIMT execution model". Inria Rennes – Bretagne Atlantique, January 2020.

[3] Dheya Mustafa et al. "MIMD Programs Execution Support on SIMD Machines: A Holistic Survey". IEEE Access, Vol. 12, 2024.

---

## 📝 附录

### A. 术语表

- **SIMT**: Single Instruction Multiple Threads
- **TSIMT**: Temporal SIMT (时间SIMT)
- **STSIMT**: Spatio-Temporal SIMT (时空SIMT)
- **Warp**: 32个线程的执行组
- **Lane**: 执行单元组
- **Scalarization**: 标量化，将向量操作转为标量
- **EDP**: Energy-Delay Product
- **Occupancy**: 活跃warp数 / 最大warp数
- **SIMD Efficiency**: 活跃线程比例

### B. 缩略语

- **ALU**: Arithmetic Logic Unit
- **RF**: Register File
- **SM**: Streaming Multiprocessor
- **CFG**: Control Flow Graph
- **IR**: Intermediate Representation

### C. 公式汇总

```
1. TSIMT Speedup:
   Speedup = 1 / d
   where d = fraction of active threads

2. EDP:
   EDP = Energy × Delay²

3. Lane Utilization:
   Utilization = Busy_Cycles / Total_Cycles

4. SIMD Efficiency:
   Efficiency = Active_Threads / Total_Threads
```

---

**文档维护**: 本文档将随STSIMT研究进展持续更新。  
**相关文档**: 参见同目录下的`HPST_Architecture_Design.md`  
**反馈与建议**: 欢迎通过GitHub Issues提交问题和建议。
