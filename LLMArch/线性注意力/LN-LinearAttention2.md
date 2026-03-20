# Flash Linear Attention 多种可视化方案

以下是几种更专业的可视化方式，您可以根据使用场景选择：

---

## 方案一：Mermaid 流程图（算法整体流程）

```mermaid
flowchart TD
    subgraph Input["📥 输入张量 [B,H,N,d]"]
        Q[Q: Query]
        K[K: Key]
        V[V: Value]
    end
    
    subgraph Kernel["🔧 核函数映射 φ(·)"]
        phiQ[φ(Q): ELU+1 / ReLU+1]
        phiK[φ(K): 保证正值]
    end
    
    subgraph Block["🧱 分块处理"]
        QBlock["Q_i [BLOCK_Q, d]"]
        KBlock["K_j [BLOCK_KV, d]"]
        VBlock["V_j [BLOCK_KV, d]"]
    end
    
    subgraph State["📊 状态累积 [d,d]"]
        DeltaS["ΔS_ij = φ(K_j)ᵀ @ V_j"]
        Accum["S_i = Σ ΔS_ij"]
    end
    
    subgraph Output["📤 输出计算"]
        OutBlock["O_i = φ(Q_i) @ S_i"]
        Final["O: [B,H,N,d]"]
    end
    
    Input --> Kernel
    Kernel --> Block
    Block --> State
    State --> Output
    
    style Input fill:#e1f5ff
    style Kernel fill:#fff4e1
    style Block fill:#e8f5e9
    style State fill:#fce4ec
    style Output fill:#f3e5f5
```

---

## 方案二：Mermaid 序列图（计算时序）

```mermaid
sequenceDiagram
    participant HBM as 💾 HBM内存
    participant SRAM as ⚡ SRAM共享内存
    participant Core as 🖥️ GPU计算核心
    
    Note over HBM,Core: 外层循环 i (Q块)
    
    HBM->>SRAM: 加载 Q_i [64,128]
    SRAM->>Core: φ(Q_i) 核函数映射
    Core->>SRAM: 存储 φ(Q_i)
    
    Note over HBM,Core: 内层循环 j (K,V块)
    
    loop j = 0 to N/BLOCK_KV
        HBM->>SRAM: 加载 K_j, V_j [64,128]
        SRAM->>Core: φ(K_j) 核函数映射
        Core->>SRAM: ΔS_ij = φ(K_j)ᵀ @ V_j [128,128]
        SRAM->>SRAM: S_i += ΔS_ij 累积
    end
    
    SRAM->>Core: O_i = φ(Q_i) @ S_i [64,128]
    Core->>HBM: 存储 O_i
    
    Note over HBM,Core: 重复直到所有Q块处理完成
```

---

## 方案三：Mermaid 状态图（状态累积过程）

```mermaid
stateDiagram-v2
    [*] --> Init: 初始化 S_i = 0 [d,d]
    
    state 状态累积循环 {
        Init --> LoadKV: 加载 K_j, V_j
        LoadKV --> PhiK: φ(K_j) 核函数
        PhiK --> DeltaS: ΔS = φ(K)ᵀ @ V
        DeltaS --> Accumulate: S += ΔS
        Accumulate --> LoadKV: j++ 下一块
    }
    
    状态累积循环 --> ComputeOut: 所有KV块完成
    ComputeOut --> PhiQ: φ(Q_i) 核函数
    PhiQ --> FinalOut: O_i = φ(Q) @ S
    FinalOut --> [*]
    
    note right of Init
        状态矩阵维度: [d, d]
        例如: [128, 128] = 16,384 元素
        存储在SRAM中
    end note
    
    note right of FinalOut
        输出维度: [BLOCK_Q, d]
        例如: [64, 128] = 8,192 元素
        写回HBM
    end note
```

---

## 方案四：维度变化矩阵图

```mermaid
flowchart LR
    subgraph 输入维度
        A1["Q: [B,H,N,d]<br/>2×8×4096×128"]
    end
    
    subgraph 核函数映射
        A1 --> B1["φ(Q): [B,H,N,d]<br/>维度不变"]
        A1 --> B2["φ(K): [B,H,N,d]<br/>维度不变"]
    end
    
    subgraph 分块加载
        B1 --> C1["Q_i: [64,128]<br/>8,192 元素"]
        B2 --> C2["K_j: [64,128]<br/>8,192 元素"]
        A1 --> C3["V_j: [64,128]<br/>8,192 元素"]
    end
    
    subgraph 状态计算
        C2 --> D1["φ(K_j)ᵀ: [128,64]"]
        C3 --> D1
        D1 --> D2["ΔS: [128,128]<br/>16,384 元素"]
        D2 --> D3["S: [128,128]<br/>累积状态"]
    end
    
    subgraph 输出计算
        C1 --> E1["φ(Q_i): [64,128]"]
        D3 --> E1
        E1 --> E2["O_i: [64,128]<br/>8,192 元素"]
    end
    
    subgraph 最终输出
        E2 --> F1["O: [B,H,N,d]<br/>2×8×4096×128"]
    end
    
    style A1 fill:#bbdefb
    style B1 fill:#e3f2fd
    style B2 fill:#e3f2fd
    style C1 fill:#c8e6c9
    style C2 fill:#c8e6c9
    style C3 fill:#c8e6c9
    style D1 fill:#fff9c4
    style D2 fill:#fff9c4
    style D3 fill:#fff9c4
    style E1 fill:#f3e5f5
    style E2 fill:#f3e5f5
    style F1 fill:#ffe0b2
```

---

## 方案五：循环嵌套结构图

```mermaid
graph TD
    Root["🎯 Flash Linear Attention"]
    
    Root --> Outer["📦 外层循环: Q分块 i=0,64,128..."]
    Outer --> LoadQ["加载 Q_i [64,128]"]
    LoadQ --> PhiQ["φ(Q_i) 核函数映射"]
    
    Outer --> Inner["📦 内层循环: K,V分块 j=0,64,128..."]
    Inner --> LoadKV["加载 K_j, V_j [64,128]"]
    LoadKV --> PhiK["φ(K_j) 核函数映射"]
    PhiK --> DeltaS["ΔS = φ(K_j)ᵀ @ V_j [128,128]"]
    DeltaS --> Accum["S += ΔS 累积"]
    Accum --> Inner
    
    Inner --> Complete["✅ 所有KV块完成"]
    Complete --> ComputeO["O_i = φ(Q_i) @ S [64,128]"]
    ComputeO --> Store["存储 O_i 到HBM"]
    Store --> Outer
    
    Outer --> Done["🎉 所有Q块完成"]
    Done --> Output["输出 O [B,H,N,d]"]
    
    style Root fill:#1976d2,color:#fff
    style Outer fill:#388e3c,color:#fff
    style Inner fill:#f57c00,color:#fff
    style Done fill:#7b1fa2,color:#fff
```

---

## 方案六：内存层次对比图

```mermaid
flowchart TB
    subgraph FlashAttn["Flash Attention"]
        FA1["Q@Kᵀ → S [N,N]"]
        FA2["Softmax → P [N,N]"]
        FA3["P@V → O [N,d]"]
        FA1 --> FA2 --> FA3
        FA_Mem["💾 HBM: O(N²) 中间矩阵"]
    end
    
    subgraph FlashLinAttn["Flash Linear Attention"]
        FL1["φ(Q), φ(K) [N,d]"]
        FL2["φ(K)ᵀ@V → S [d,d]"]
        FL3["φ(Q)@S → O [N,d]"]
        FL1 --> FL2 --> FL3
        FL_Mem["💾 HBM: O(N) 无需中间矩阵"]
    end
    
    FlashAttn --> Compare["⚖️ 对比"]
    FlashLinAttn --> Compare
    
    Compare --> Result["📊 内存节省: N²/d² ≈ 1024倍<br/>(N=4096, d=128)"]
    
    style FlashAttn fill:#ffebee
    style FlashLinAttn fill:#e8f5e9
    style Result fill:#fff3e0
```

---

## 方案七：完整伪代码 + 维度标注

```mermaid
classDiagram
    class FlashLinearAttention {
        +forward(Q, K, V) Output
        -BLOCK_Q: int = 64
        -BLOCK_KV: int = 64
        -kernel_fn: Function
    }
    
    class TensorDimensions {
        +Q: [B, H, N, d]
        +K: [B, H, N, d]
        +V: [B, H, N, d]
        +phi_Q: [B, H, N, d]
        +phi_K: [B, H, N, d]
        +Q_i: [BLOCK_Q, d]
        +K_j: [BLOCK_KV, d]
        +V_j: [BLOCK_KV, d]
        +Delta_S: [d, d]
        +S: [d, d]
        +O_i: [BLOCK_Q, d]
        +O: [B, H, N, d]
    }
    
    class ComputationFlow {
        +load_Q_block()
        +load_KV_block()
        +apply_kernel()
        +accumulate_state()
        +compute_output()
    }
    
    FlashLinearAttention --> TensorDimensions : 使用维度
    FlashLinearAttention --> ComputationFlow : 执行流程
```

---

## 各方案适用场景对比

| 方案 | 类型 | 最佳使用场景 | 优点 |
|------|------|-------------|------|
| **方案一** | 流程图 | 算法整体概览 | 清晰展示数据流向 |
| **方案二** | 序列图 | 计算时序理解 | 展示HBM/SRAM数据移动 |
| **方案三** | 状态图 | 状态累积过程 | 突出状态矩阵变化 |
| **方案四** | 维度图 | 维度变化追踪 | 每个步骤维度一目了然 |
| **方案五** | 循环图 | 嵌套结构理解 | 清晰展示循环层次 |
| **方案六** | 对比图 | 与Flash Attention对比 | 突出内存优势 |
| **方案七** | 类图 | 代码实现参考 | 接近实际代码结构 |

---

## 推荐使用方式

1. **技术文档/论文** → 方案一 + 方案四（流程+维度）
2. **教学演示** → 方案二 + 方案五（时序+循环）
3. **代码实现参考** → 方案七（类图结构）
4. **性能分析** → 方案六（内存对比）

您可以根据具体需求选择合适的可视化方案，或者组合使用多个方案来获得更全面的理解！