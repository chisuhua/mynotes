
# Qwen3-0.6B-Hybrid 架构设计规范

## 1. 设计目标与约束

### 1.1 核心目标
- **保持端侧部署能力**：激活参数量严格控制在 **0.6B**（与原模型持平）
- **长序列效率提升**：通过DeltaNet将长文本推理复杂度从 $O(n^2)$ 降至 $O(n)$
- **容量扩展**：通过4层轻量MoE提升模型表达能力，总参数量控制在 **0.85B** 以内
- **训练稳定性**：引入Zero-Centered RMSNorm解决小模型训练震荡问题

### 1.2 硬约束
| 约束项     | 限制值             | 设计影响                                |
| ------- | --------------- | ----------------------------------- |
| 最大激活参数量 | 0.6B            | MoE必须采用Top-1路由，禁止Top-2              |
| 推理显存上限  | 1.5GB (FP16)    | DeltaNet窗口限制2048，避免状态膨胀             |
| 训练显存上限  | 24GB (RTX 4090) | 必须支持Gradient Checkpointing + ZeRO-2 |
| 总训练数据量  | ≤10B tokens     | 0.6B模型容量有限，防止过拟合                    |

---

## 2. 宏观架构设计

### 2.1 分层拓扑结构
```yaml
Layer 0-15 (16层):   Standard GQA + Dense FFN
                     └─ 保持Qwen3原始架构，负责基础语义理解

Layer 16-19 (4层):   Gated DeltaNet + Dense FFN  
                     └─ 线性注意力机制，处理长程依赖，窗口2048

Layer 20-23 (4层):   Standard GQA + Lightweight MoE
                     └─ Expert Choice Routing, 4专家, Top-1激活

Layer 24-27 (4层):   Standard GQA + Dense FFN
                     └─ 输出稳定层，确保生成质量
```

### 2.2 参数分布详表

| 组件 | 层数 | 单层参数量 | 总参数量 | 激活参数量 |
|------|------|------------|----------|------------|
| **Embedding** | 1 | 151,936×1024 | 155.5M | 155.5M |
| **Standard Layers** | 20 | ~11.0M | 220.0M | 220.0M |
| **DeltaNet Layers** | 4 | ~11.8M | 47.2M | 47.2M |
| **MoE Layers** | 4 | ~47.0M (4×11.8M) | 188.0M | **47.0M** (Top-1) |
| **Output Head** | 1 | 1024×151,936 | 155.5M | 155.5M |
| **MTP Module** | 1 | ~2.0M | 2.0M | 2.0M |
| **总计** | - | - | **~825M** | **~627M** |

**注**：MoE层通过Expert Choice机制确保每次仅激活1个专家（11.8M），保持0.6B级别激活量。

---

## 3. 核心模块技术规范

### 3.1 Zero-Centered RMSNorm (ZC-RMSNorm)
**设计原理**：标准RMSNorm仅做尺度归一化，缺乏中心对齐，在小模型中易导致梯度偏移。

**数学定义**：
$$ \text{ZC-RMSNorm}(x) = \frac{x - \mu(x)}{\sqrt{\frac{1}{d}\sum_{i=1}^d (x_i - \mu(x))^2 + \epsilon}} \odot \gamma $$

**实现规范**：
```python
class ZeroCenteredRMSNorm(nn.Module):
    def __init__(self, hidden_size=1024, eps=1e-6, weight_decay=0.01):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(hidden_size))
        self.eps = eps
        self.weight_decay = weight_decay  # 对norm weight施加惩罚
        
    def forward(self, x):
        # 中心对齐
        mean = x.mean(dim=-1, keepdim=True)
        x_centered = x - mean
        
        # RMS计算
        variance = x_centered.pow(2).mean(dim=-1, keepdim=True)
        x_norm = x_centered * torch.rsqrt(variance + self.eps)
        
        # 应用可学习权重
        return self.weight * x_norm
```

**应用位置**：所有28层的Pre-Norm和Post-Norm，QK-Norm前置。

### 3.2 Gated DeltaNet Layer (层16-19)
**架构约束**：
- **窗口大小**：2048 tokens（平衡长程捕获与内存占用）
- **状态维度**：与hidden_size一致（1024），避免额外投影开销
- **门控机制**：引入可学习衰减因子 $\beta_t \in (0,1)$

**核心实现**：
```python
class GatedDeltaNetAttention(nn.Module):
    def __init__(self, hidden_size=1024, num_heads=16, window_size=2048):
        super().__init__()
        self.hidden_size = hidden_size
        self.num_heads = num_heads
        self.head_dim = 64  # 注意：DeltaNet内部可拆分head_dim=64，非官方128
        self.window_size = window_size
        
        # 投影层（复用原Qwen3的Q/K/V投影初始化）
        self.q_proj = nn.Linear(hidden_size, num_heads * self.head_dim)
        self.k_proj = nn.Linear(hidden_size, num_heads * self.head_dim)
        self.v_proj = nn.Linear(hidden_size, num_heads * self.head_dim)
        self.o_proj = nn.Linear(num_heads * self.head_dim, hidden_size)
        
        # DeltaNet特定参数
        self.gate_proj = nn.Linear(self.head_dim, self.head_dim)  # 门控生成
        self.beta_init = -2.0  # 初始化为接近0的门控值（保守策略）
        self.beta = nn.Parameter(torch.full((num_heads, 1, 1), self.beta_init))
        
    def forward(self, x, mask=None):
        batch, seq_len, _ = x.shape
        q = self.q_proj(x).view(batch, seq_len, self.num_heads, self.head_dim).transpose(1, 2)
        k = self.k_proj(x).view(batch, seq_len, self.num_heads, self.head_dim).transpose(1, 2)
        v = self.v_proj(x).view(batch, seq_len, self.num_heads, self.head_dim).transpose(1, 2)
        
        # 局部窗口限制（关键：防止内存随序列长度爆炸）
        if seq_len > self.window_size:
            # 对超过窗口的部分，使用递归状态传递而非全序列计算
            outputs = []
            for i in range(0, seq_len, self.window_size):
                end_i = min(i + self.window_size, seq_len)
                q_chunk = q[:, :, i:end_i]
                k_chunk = k[:, :, i:end_i]
                v_chunk = v[:, :, i:end_i]
                
                # DeltaNet核心：线性注意力 + 门控衰减
                # S_t = β_t * S_{t-1} + (1-β_t) * (k_t^T ⊗ v_t)
                beta = torch.sigmoid(self.beta)  # (num_heads, 1, 1)
                
                # 简化版实现：使用累积和模拟状态更新
                kv_cumsum = torch.cumsum(k_chunk.unsqueeze(-1) * v_chunk.unsqueeze(-2), dim=2)
                state = beta * kv_cumsum[:, :, :-1] + (1-beta) * (k_chunk.unsqueeze(-1) * v_chunk.unsqueeze(-2))
                
                # 线性注意力计算
                attn_output = torch.einsum('bhqd,bhqdk->bhqd', q_chunk, state)
                outputs.append(attn_output)
                
            attn_output = torch.cat(outputs, dim=2)
        else:
            # 全序列线性注意力
            kv = torch.einsum('bhsk,bhsv->bhkv', k, v)
            attn_output = torch.einsum('bhqd,bhkd->bhqv', q, kv)
            
        attn_output = attn_output.transpose(1, 2).contiguous().view(batch, seq_len, self.hidden_size)
        return self.o_proj(attn_output)
```

**关键约束**：DeltaNet层仍保留残差连接和FFN结构，仅替换注意力机制。

### 3.3 Lightweight MoE with Expert Choice (层20-23)
**设计选择**：放弃传统Top-k路由（aux loss难以调优），采用**Expert Choice Routing**（ECR）。

**数学原理**：
- 传统：Token选择专家（Top-k），易导致负载不均
- ECR：专家选择Token，天然负载均衡，公式：
  $$ \text{capacity} = \lceil \frac{\text{num\_tokens} \times \text{capacity\_factor}}{\text{num\_experts}} \rceil $$
  每个专家固定处理capacity个token，通过router logits排序选择。

**架构参数**：
```python
class ExpertChoiceMoELayer(nn.Module):
    def __init__(self, hidden_size=1024, intermediate_size=3072, num_experts=4):
        super().__init__()
        self.num_experts = num_experts
        self.capacity_factor = 1.0
        
        # 4个专家（FFN），独立初始化
        self.experts = nn.ModuleList([
            SwiGLU(hidden_size, intermediate_size) for _ in range(num_experts)
        ])
        
        # 路由器（轻量级）
        self.router = nn.Linear(hidden_size, num_experts, bias=False)
        # 关键初始化：零均值，小方差，初始为均匀分布
        nn.init.normal_(self.router.weight, mean=0.0, std=0.01)
        
    def forward(self, x):
        batch_size, seq_len, hidden_size = x.shape
        num_tokens = batch_size * seq_len
        
        # Router logits: (batch*seq, num_experts)
        router_logits = self.router(x.view(-1, hidden_size))
        
        # Expert Choice: 每个专家选择top-(capacity)个token
        capacity = math.ceil(self.capacity_factor * num_tokens / self.num_experts)
        
        # 对每列（专家）取topk，沿token维度
        topk_vals, topk_indices = torch.topk(router_logits, k=capacity, dim=0)
        
        # 构建输出（稀疏计算）
        output = torch.zeros_like(x.view(-1, hidden_size))
        for i, expert in enumerate(self.experts):
            indices = topk_indices[:, i]  # 该专家处理的token索引
            expert_input = x.view(-1, hidden_size)[indices]
            expert_output = expert(expert_input)
            
            # 加权聚合（可选：使用router权重加权）
            weights = torch.softmax(topk_vals[:, i], dim=0).unsqueeze(-1)
            output[indices] += expert_output * weights
            
        return output.view(batch_size, seq_len, hidden_size)
```

### 3.4 Multi-Token Prediction (MTP)
**设计原则**：必须与主LM Head**共享权重**，否则参数量爆炸（+150M不可接受）。

**架构**：
```python
class SharedMTPModule(nn.Module):
    def __init__(self, hidden_size=1024, num_predictions=2, lm_head=None):
        super().__init__()
        self.num_predictions = num_predictions
        self.lm_head = lm_head  # 共享引用
        
        # 仅添加轻量级投影层（2M参数）
        self.projectors = nn.ModuleList([
            nn.Sequential(
                nn.Linear(hidden_size, hidden_size // 2),
                nn.GELU(),
                nn.Linear(hidden_size // 2, hidden_size)
            ) for _ in range(num_predictions)
        ])
        
    def forward(self, hidden_states):
        # hidden_states: (batch, seq, hidden)
        mtp_logits = []
        current = hidden_states
        
        for i in range(self.num_predictions):
            # 投影并预测
            projected = self.projectors[i](current)
            logits = self.lm_head(projected)  # 共享权重！
            mtp_logits.append(logits)
            
            # 为下一预测准备（简化：仅投影，不递归）
            current = projected
            
        return mtp_logits  # 列表长度=num_predictions
```

---

## 4. 初始化与迁移策略

### 4.1 权重迁移矩阵
| 原Qwen3-0.6B组件 | 目标组件 | 初始化策略 | 冻结策略（阶段1） |
|------------------|----------|------------|------------------|
| Standard Attention | Standard Attention (层0-15,24-27) | 直接复制 | 冻结 |
| Standard Attention | DeltaNet Q/K/V投影 (层16-19) | 复制并 reshape 到 head_dim=64 | 冻结Q/K/V，训练门控 |
| FFN SwiGLU | FFN SwiGLU (所有Dense层) | 直接复制 | 冻结 |
| FFN SwiGLU | MoE Experts (层20-23) | 复制为4个专家副本 + 噪声(σ=0.01) | 冻结专家，训练Router |
| RMSNorm | ZC-RMSNorm | 复制weight，新增center参数 | 训练 |
| LM Head | LM Head | 直接复制 | 冻结 |
| - | MTP Projectors | 正态分布 N(0, 0.02) | 训练 |

### 4.2 噪声注入策略（MoE专家分化）
```python
def initialize_experts_with_noise(base_ffn, num_experts=4, noise_std=0.01):
    """将单个FFN复制为4个专家，注入结构化噪声促进分化"""
    experts = []
    base_state = base_ffn.state_dict()
    
    for i in range(num_experts):
        expert = copy.deepcopy(base_ffn)
        with torch.no_grad():
            for name, param in expert.named_parameters():
                # 不同专家使用不同随机种子
                torch.manual_seed(i * 1000 + hash(name) % 1000)
                noise = torch.randn_like(param) * noise_std
                param.add_(noise)
        experts.append(expert)
    return experts
```

---

## 5. 推理优化设计

### 5.1 动态路由缓存（MoE层）
- 对Expert Choice Routing，在推理时缓存每个专家的capacity分配决策，避免重复计算router logits。

### 5.2 DeltaNet状态复用
- 实现KV Cache的替代方案：状态矩阵 $S_t$ 的增量更新，支持序列延续而不重新计算历史。

### 5.3 量化支持
- 所有改造模块支持INT8/INT4量化：
  - ZC-RMSNorm的center参数需FP16保存，防止量化误差累积
  - DeltaNet状态矩阵禁止量化（保持FP16）

---

