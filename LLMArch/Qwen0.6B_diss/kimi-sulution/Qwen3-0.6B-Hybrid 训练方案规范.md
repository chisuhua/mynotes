
# Qwen3-0.6B-Hybrid 训练方案规范

## 1. 训练阶段总览

| 阶段      | 目标                | 数据量       | 核心策略               | 预计时间(A100) | 预计时间(4090) |
| ------- | ----------------- | --------- | ------------------ | ---------- | ---------- |
| **阶段1** | Router预热 & Norm适应 | 1B tokens | 冻结骨干，训练Router+Norm | 2.5天       | 3天         |
| **阶段2** | 专家分化 & DeltaNet适应 | 4B tokens | 全量微调，分层学习率         | 12天        | 18天        |
| **阶段3** | MTP精炼 & 对齐        | 1B tokens | 低学习率精修，激活MTP       | 3天         | 4.5天       |
| **总计**  | -                 | 6B tokens | -                  | **17.5天**  | **25.5天**  |

---

## 2. 阶段1：基础迁移（Warmup）

### 2.1 训练配置
```yaml
# stage1_config.yaml
model_path: "Qwen/Qwen3-0.6B"
output_dir: "./output/stage1_warmup"

# 数据配置
data:
  total_tokens: 1_000_000_000  # 1B
  sources:
    - name: "general_corpus"
      weight: 0.6
      path: "path/to/general"
    - name: "long_context"
      weight: 0.2
      path: "path/to/longcontext"  # 用于预热DeltaNet层
    - name: "code"
      weight: 0.2
      path: "path/to/code"

# 优化器配置
optimizer:
  type: "adamw"
  lr: 5.0e-5
  betas: [0.9, 0.95]
  eps: 1.0e-8
  weight_decay: 0.01  # 对Norm weight施加

# 学习率调度
lr_scheduler:
  type: "warmup_stable_decay"
  warmup_steps: 1000  # 约0.5%的步数
  decay_steps: 10000

# 训练超参
training:
  per_device_batch_size: 4
  gradient_accumulation_steps: 64  # 总batch=256
  max_seq_length: 2048
  gradient_checkpointing: true

# 冻结策略（关键）
frozen_components:
  - "layers.0-15.attention"        # 前16层注意力
  - "layers.0-15.mlp"             # 前16层FFN
  - "layers.16-19.attention.q_proj"  # DeltaNet Q/K/V冻结，仅训练gate
  - "layers.16-19.attention.k_proj"
  - "layers.16-19.attention.v_proj"
  - "layers.16-19.attention.o_proj"
  - "layers.20-23.mlp.experts"    # MoE专家冻结
  - "layers.24-27.*"              # 最后4层全部冻结
  - "lm_head"
  - "embed_tokens"

trainable_components:
  - "layers.16-19.attention.gate_proj"  # DeltaNet门控
  - "layers.16-19.attention.beta"       # DeltaNet衰减系数
  - "layers.20-23.mlp.router"          # MoE路由器
  - "norm"                             # 所有ZC-RMSNorm
```

### 2.2 关键监控指标
- **Router Entropy**：应维持在 $\ln(4) \approx 1.386$ 附近，允许范围 [1.0, 1.5]
- **Expert Usage Variance**：4个专家的使用率方差应 < 0.05
- **Gradient Norm**：DeltaNet门控参数梯度范数应 < 0.1（防止门控极端化）

**早停条件**：
- 若1000步后Entropy < 0.5：重启并降低LR至 2e-5
- 若出现NAN：检查ZC-RMSNorm的center计算，考虑暂时回退到标准RMSNorm

---

## 3. 阶段2：核心训练（Specialization）

### 3.1 训练配置
```yaml
# stage2_config.yaml
input_model: "./output/stage1_warmup"
output_dir: "./output/stage2_core"

data:
  total_tokens: 4_000_000_000  # 4B
  mix:
    - general: 0.4      # 维持通用能力
    - code: 0.3         # 专家分化关键数据
    - math_reasoning: 0.2
    - multilingual: 0.1

optimizer:
  type: "adamw"
  lr: 2.0e-5  # 较阶段1降低
  weight_decay: 0.01

# 分层学习率（关键技巧）
layer_lr_decay: 0.9  # 每深一层，LR衰减10%
special_lr:
  "layers.20-23.mlp.experts": 1.0e-5  # MoE专家使用更低LR，防止破坏预训练知识
  "layers.16-19.attention.*": 3.0e-5  # DeltaNet使用较高LR加速适应

training:
  per_device_batch_size: 2  # 减小以支持全量训练
  gradient_accumulation_steps: 128  # 维持总batch=256
  max_seq_length: 4096  # 延长至4K，训练长序列能力
  
  # 序列长度Warmup（防止早期长序列震荡）
  seq_length_warmup:
    start: 1024
    target: 4096
    steps: 5000

# 正则化
dropout: 0.0  # 小模型不使用dropout，依赖early stopping
gradient_clipping: 1.0

# MoE特定配置
moe_aux_loss_coef: 0.0  # 使用Expert Choice，无需aux loss
```

### 3.2 稳定性技巧
1. **DeltaNet β参数约束**：在训练过程中对 $\beta = \text{sigmoid}(\text{beta\_param})$ 施加约束，确保 $\beta \in [0.1, 0.9]$，防止门控饱和。
2. **专家Dropout**：以10%概率随机屏蔽某个专家输出，强制冗余学习（仅阶段2使用）。
3. **动态容量调整**：每1000步检查专家负载，若某专家使用率<15%，临时提高其router bias 0.1。

### 3.3 验证检查点
- **每2B tokens评估**：
  - 在 LongBench（长文本）上评估，应比原模型提升 >10%
  - 在 HumanEval（代码）上评估，MoE层应展现专业化倾向（通过分析专家激活模式）

---

## 4. 阶段3：精炼与MTP（Refinement）

### 4.1 训练配置
```yaml
# stage3_config.yaml
input_model: "./output/stage2_core"
output_dir: "./output/stage3_final"

data:
  total_tokens: 1_000_000_000
  quality_filter: "high"  # 仅使用高质量数据（如指令微调数据）
  sources:
    - instruct_data: 0.7
    - general: 0.3

optimizer:
  lr: 5.0e-6  # 极低学习率精修
  
training:
  per_device_batch_size: 4
  gradient_accumulation_steps: 64
  
  # MTP激活
  mtp_enabled: true
  mtp_loss_weight: 0.3  # MTP loss占30%
  mtp_num_predictions: 2

# 早停
early_stopping:
  patience: 2000  # 2000步无提升则停
  metric: "eval_perplexity"
```

### 4.2 MTP训练细节
- **主任务保护**：确保主LM Head的perplexity不上升，若上升超过2%，降低MTP权重至0.1
- **共享权重冻结**：阶段3冻结LM Head权重，仅训练MTP投影层（防止破坏主任务）

---

## 5. 资源估算与硬件方案

### 5.1 显存占用详解（阶段2，最耗资源阶段）

| 组件 | 内存占用 | 优化后（4090方案） |
|------|----------|-------------------|
| 模型参数 (BF16) | 1.65B × 2B = **3.3GB** | 3.3GB |
| 梯度 | 1.65B × 2B = **3.3GB** | 3.3GB |
| 优化器状态 (Adam) | 1.65B × 4B × 2 = **13.2GB** | **0GB** (Offload到CPU) |
| 激活值 (Batch=2, Seq=4096) | ~**6GB** | **3GB** (Gradient Checkpointing) |
| 临时缓存 | ~**1GB** | 1GB |
| **总计** | **~27GB** | **~10.6GB** ✅ |

### 5.2 硬件选择决策树
- **单卡 A100 40GB**：标准方案，无需特殊优化，阶段2 batch可提升至4
- **单卡 RTX 4090 24GB**：必须开启Optimizer Offload和Gradient Checkpointing，阶段2 batch只能为2
- **2× RTX 4090**：使用DeepSpeed Expert Parallelism（将4个MoE层分摊到2卡），可实现batch=4

### 5.3 时间成本估算（基于6B tokens）
| 硬件 | 有效吞吐 | 总时间 | 云成本估算（AutoDL） |
|------|----------|--------|---------------------|
| A100 40G | ~2800 tok/s | **17.5天** | ~¥2,100 |
| RTX 4090 | ~2200 tok/s (offload损耗) | **25.5天** | ~¥1,800 |
| 2×A100 | ~5500 tok/s | **7天** | ~¥1,680 |

---

## 6. 评估与验收标准

### 6.1 必须通过的基线测试
| 测试项 | 原Qwen3-0.6B | 改造后目标 | 测试方法 |
|--------|--------------|------------|----------|
| **PPL (WikiText-2)** | 基准 | < 基准 × 1.02 | 语言建模 |
| **LongBench (Avg)** | 基准 | > 基准 × 1.10 | 长文本理解（关键提升项） |
| **HumanEval** | 基准 | > 基准 × 1.05 | 代码生成 |
| **GSM8K** | 基准 | ≥ 基准 | 数学推理（保持） |
| **推理速度 (32K)** | 1× | **> 2.5×** | 关键验收指标 |

### 6.2 架构验证测试
- **专家专业化测试**：在代码数据上推理，MoE层应主要激活专家0或1；在中文数据上，应主要激活专家2或3。通过计算专家激活与数据类型的互信息验证。
- **DeltaNet稳定性**：在32K长度输入上，loss无异常峰值，梯度范数 < 1.0

---

## 7. 风险预案

| 风险 | 检测方法 | 应对措施 |
|------|----------|----------|
| **MoE路由崩溃** | Entropy < 0.5 | 立即回退到阶段1检查点，降低LR至1e-5，增加capacity_factor至1.2 |
| **DeltaNet梯度爆炸** | Loss = NaN 或 >10 | 对该层实施Gradient Clipping (max_norm=0.5)，或暂时回退为标准注意力 |
| **MTP导致退化** | 主PPL上升 >5% | 冻结MTP，仅保留阶段2产出；或降低MTP权重至0.05 |
| **显存OOM（阶段2）** | CUDA OOM Error | 减少MoE层数至2层（仅20-21层），或缩短max_seq_length至2048 |

---

## 8. 部署与推理规范

### 8.1 模型导出
```python
# 导出为HuggingFace格式
from transformers import AutoModelForCausalLM, AutoTokenizer

model = AutoModelForCausalLM.from_pretrained("./output/stage3_final")
# 移除训练专用参数（如MTP的额外输出，推理时可选禁用）
model.save_pretrained("./deploy/qwen3-0.6b-hybrid")
```

### 8.2 推理配置建议
```python
# generation_config.json
{
  "max_new_tokens": 2048,
  "do_sample": true,
  "temperature": 0.7,
  "top_p": 0.9,
  # 长序列优化
  "cache_implementation": "hybrid",  # 标准层用KV Cache，DeltaNet层用状态Cache
  "moe_top_k": 1,  # 严格Top-1保持速度
}
```

---

**文档版本**：v1.0  
**适用基座模型**：Qwen3-0.6B (hidden_size=1024, intermediate_size=3072, 28 layers)  
**总激活参数**：~0.63B  
**总参数量**：~0.83B  
**预计训练成本**：17-26天（单卡）或 7天（双卡A100）