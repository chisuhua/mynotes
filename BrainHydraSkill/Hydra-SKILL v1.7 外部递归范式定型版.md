Hydra-SKILL v1.7 完整架构设计文档
代号：Phoenix（外部递归范式定型版）
版本：v1.7（External Recursion Architecture）
状态：✅ 架构冻结（External Recursion范式最终确认）
核心范式：外部递归（CFI结果回流L1）+ 分层认知 + Prefix Cache复用
激活参数：0.46B（L1-21循环），单次推理0.50B（含L24-25终止生成）
总存储参数：0.52B￼1. 架构总览：外部递归范式（External Recursion）1.1 范式定义外部递归（External Recursion）：模型的认知过程不是单次前向传播，而是L1-21层的循环执行。每次循环可以：1. 内部推理：L8-21生成思维，不触发CFI2. 外部交互：L22生成[CFI_CALL]，暂停循环，执行CFI，结果编码为Tokens后回流到L1，开始新一轮循环3. 终止输出：L22生成[THINK_END]，路由到L24-25（仅执行一次）生成最终答案Mermaid￼全屏￼下载￼复制代码预览循环认知层（Recurrent Layers，可执行N次）[CFI_CALL][THINK_END]结果编码Tokens回流￼L1-7 Dense+MLAPrefix Cache复用L8-11 思维模式LoRAL12-15 领域MoE+CFI触发L16-21 验证强化L22 Control Gateway生成控制标记CFI执行外部沙盒/知识库L24-25 TerminationGenerator仅执行一次L23 ObservationEncoder非Transformer层最终答案自然语言1.2 关键架构特征表格￼￼组件类型执行次数功能L1-7Dense+MLA每轮循环（复用Cache）基础编码L8-11Dense+LoRA每轮循环思维模式选择L12-15MoE+LoRA每轮循环领域知识+生成CFI标记L16-21MoE每轮循环验证检查L22Control Gateway每轮循环（决策点）生成[CFI_CALL]/[THINK_END]/[BACKTRACK]L23Observation EncoderCFI返回后（1次/轮）将CFI结果编码为TokensCFIExternal按需（0-N次/问题）工具执行/知识检索L24-25Termination Generator仅1次（最后）生成最终自然语言答案￼2. 详细分层架构（外部递归修正版）2.1 L1-7：感知层（Prefix Cache复用）关键机制：在外部递归中，L1-7的KV Cache可以跨轮次复用（如果输入的Prefix未变），或增量更新（如果输入是CFI结果）。Python￼复制Layer_1_7_Config = {
    "type": "Dense",
    "num_layers": 7,
    "hidden_size": 1152,
    "mla": {"c": 256, "cq": 256},
    
    # 外部递归关键：Prefix Cache管理
    "prefix_cache": {
        "mode": "persistent_across_rounds",  # 跨轮次持久化
        "ttl_seconds": 3600,
        "update_strategy": "append",  # CFI结果作为新Token追加，而非替换
        "reuse_policy": "lazy"        # 仅当输入是CFI新结果时，复用前7层Cache
    }
}回流机制：当CFI结果（L23编码的Tokens）作为新输入时：• 方案A（全量复用）：如果系统提示+用户问题未变，直接复用首轮L1-7 Cache，CFI Tokens从L8开始处理（节省计算）• 方案B（增量编码）：将CFI Tokens与历史拼接，重新走L1-7（确保位置编码连续性）推荐：方案A（Prefix Cache复用）+ RoPE位置编码动态调整（alibi或旋转位置编码的外推）。2.2 L8-11：思维模式层（循环内）每轮循环都重新选择思维模式（根据当前上下文动态调整）。Python￼复制Layer_8_11_Config = {
    "type": "Dense+LoRA",
    "num_layers": 4,
    "lora_modes": 8,  # 8种思维模式
    
    # 外部递归特性：每轮可切换
    "mode_switching": "per_round",  # 每轮循环可切换不同思维LoRA
    "state_carryover": False        # 不携带上轮内部状态（纯外部递归）
}2.3 L12-15：领域知识层（CFI触发点）核心功能：在循环中检测是否需要外部工具。Python￼复制Layer_12_15_Config = {
    "type": "MoE+LoRA",
    "num_experts": 16,
    "top_k": 1,
    
    # CFI触发（循环内决策）
    "cfi_trigger": {
        "marker": "[CFI_CALL]",
        "threshold": 0.8,
        "condition": "expert_confidence < 0.8 or tool_required"
    }
}执行流程：1. L12-15生成[CFI_CALL]标记 → 传递给L22确认2. L22正式输出控制信号 → 暂停循环3. CFI执行 → L23编码 → 回流到L1 → 开始第N+1轮循环2.4 L16-21：验证强化层（循环内）每轮循环都执行验证（检查当前思维的一致性）。Python￼复制Layer_16_21_Config = {
    "type": "MoE",
    "num_experts": 8,
    "expert_assignment": ["logic_check", "consistency", "fact_check", ...],
    
    # 外部递归关键：验证CFI返回结果
    "verify_cfi_results": True,  # 专门验证L23编码的CFI结果是否合理
    "backtrack_trigger": "verification_failed"  # 验证失败可触发Backtrack
}2.5 L22：控制网关层（Control Gateway）定位：循环的决策出口，决定是继续循环（CFI）、终止（Answer）还是回溯。Python￼复制class ControlGatewayLayer(nn.Module):
    """
    L22：控制网关（每轮循环的最后一步）
    决定下一步流向：
    1. [CFI_CALL] -> 执行CFI -> 回流L1（继续循环）
    2. [THINK_END] -> 进入L24-25（终止循环，生成答案）
    3. [BACKTRACK] -> 截断历史 -> 回流L1（回溯后继续）
    """
    def __init__(self):
        self.control_head = nn.Linear(1152, 256)  # Compact控制标记
        
    def forward(self, hidden_state, round_number):
        logits = self.control_head(hidden_state)
        control_token = torch.argmax(logits)
        
        if control_token == CFI_CALL:
            return {
                'action': 'CFI',
                'payload': hidden_state,  # 传递给CFI的参数编码
                'next_layer': None,       # 不进入L23，而是外部执行CFI
                'resume_at': 'L1'         # CFI后回流到L1
            }
        elif control_token == THINK_END:
            return {
                'action': 'TERMINATE',
                'next_layer': 24,         # 进入L24-25（终止层）
                'final_hidden': hidden_state
            }
        elif control_token == BACKTRACK:
            return {
                'action': 'BACKTRACK',
                'truncate_steps': 3,      # 回溯3步
                'resume_at': 'L1'
            }2.6 L23：观察编码层（Observation Encoder）关键修正：不是Transformer层，而是CFI结果到Tokens的编码/预处理模块。Python￼复制class ObservationEncoder:
    """
    L23：将CFI执行结果编码为可回流的Token序列
    位于循环外部（CFI执行后）
    """
    def __init__(self, tokenizer):
        self.tokenizer = tokenizer
        self.vector_projector = nn.Linear(1152, 1152)  # 如果CFI返回向量
        
    def encode(self, cfi_result):
        """
        将CFI结果转为输入Token序列
        """
        if cfi_result.type == 'text':
            # 文本结果：Tokenizer编码 + 特殊标记包裹
            tokens = [OBS_START] + self.tokenizer(cfi_result.text) + [OBS_END]
        elif cfi_result.type == 'vector':
            # 向量结果：投影后通过VQ-VAE或连续嵌入（特殊处理）
            projected = self.vector_projector(cfi_result.embedding)
            tokens = self.vector_to_discrete_tokens(projected)
        elif cfi_result.type == 'structured':
            # 结构化数据（JSON）：压缩编码
            tokens = self.structure_to_tokens(cfi_result.data)
            
        return tokens  # 这些Token将作为新的input_ids进入L1
    
    def vector_to_discrete_tokens(self, vector):
        """
        将连续向量转为离散Token（可选VQ-VAE）
        简化方案：直接作为Embedding输入（如果Tokenizer支持连续输入）
        """
        # 方案：通过一个小型MLP映射到Token分布
        logits = self.token_mapper(vector)  # [1152] -> [vocab_size]
        top_k_tokens = torch.topk(logits, k=10).indices  # 取Top10近似
        return top_k_tokens架构位置：• 物理位置：CFI客户端与模型之间• 逻辑位置：不属于L1-28的Transformer层，而是预处理模块• 参数量：~5M（小MLP），不计入核心0.46B（或计入总0.52B）2.7 L24-25：终止生成层（Termination Generator）关键修正：不参与循环，仅在L22决定终止时执行一次。Python￼复制class TerminationGenerator(nn.Module):
    """
    L24-25：仅在最后执行一次，生成自然语言答案
    输入：L22的final_hidden_state（经过完整思维过程后的状态）
    输出：自然语言文本（<answer>...</answer>）
    """
    def __init__(self):
        super().__init__()
        # 4层Distillation（或5层Fallback）
        self.layers = nn.ModuleList([
            TransformerLayer(1152) for _ in range(4)
        ])
        
        # 纯Semantic Head（无Control Head）
        self.semantic_head = nn.Linear(1152, 50000)
        
    def forward(self, final_hidden):
        """
        一次性前向，生成答案
        注意：不输出控制标记，只输出自然语言
        """
        x = final_hidden
        for layer in self.layers:
            x = layer(x)
        
        # 自回归生成（或单次生成，取决于任务）
        logits = self.semantic_head(x)
        return logits
    
    def generate_answer(self, final_hidden, max_new_tokens=512):
        """
        自回归生成最终答案
        """
        generated = []
        current = final_hidden
        
        for _ in range(max_new_tokens):
            logits = self.forward(current)
            next_token = torch.argmax(logits, dim=-1)
            generated.append(next_token)
            
            if next_token == EOS_TOKEN:
                break
                
            # 准备下一步（简单实现：直接嵌入，不走完整L1-25）
            current = self.embedding(next_token)
            
        return generated参数量说明：• L24-25有90M参数（4层）• 虽然只执行一次，但参数量计入总0.52B• 不影响"激活参数"统计（激活参数指每轮循环实际计算的参数）￼3. 外部递归流程详解（时序图）3.1 单轮CFI交互流程Text￼复制用户输入："计算复利，本金1000，利率5%，10年"

第1轮循环：
  L1-7: 编码"计算复利..." → Cache
  L8-11: 选择"数学归纳"思维模式
  L12-15: 领域专家触发[CFI_CALL:calc]（置信度低，需要计算）
  L16-21: 验证（无需验证，直接通过）
  L22: 输出￼