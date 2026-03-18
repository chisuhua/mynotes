**Hydra-SKILL v1.7 架构设计文档**  
**代号**：Cognitive OS（认知操作系统）  
**范式**：显式认知架构（Explicit Cognitive Architecture）  
**核心思想**：模型是"认知CPU"，外部框架是"认知外设+内存总线"

---

## 一、范式升级：从隐式到显式认知

### 1.1 v1.6 的局限（隐式认知）
v1.6 的 CLU 循环是**黑盒**：
- 状态 `state_t` 是稠密向量，人类/框架无法解读
- 模型"想"了什么，只能通过最终输出猜测
- 外部框架被动等待，无法主动干预认知过程

### 1.2 v1.7 的突破（显式认知）
**显式化一切认知活动**：
```
模型不再"思考"，而是"写思维日志"
外部框架不再"等待"，而是"读取日志并干预"
```

**架构类比**：
| 组件 | 计算机体系结构 | v1.7 对应 |
|------|---------------|-----------|
| **CLU** | CPU（运算核心） | 生成结构化思维令牌 |
| **外部框架** | 内存+外设+OS | 执行工具、验证逻辑、存储记忆 |
| **思维令牌** | 机器指令 | 可读写的认知原语（<analyze>, <tool>, <verify>） |
| **上下文窗口** | 寄存器+缓存 | 当前工作记忆（Working Memory Buffer） |

---

## 二、v1.7 核心架构：显式认知循环（Explicit Cognitive Loop, ECL）

### 2.1 架构全景图
```
用户输入
    ↓
[感知编码] → 认知向量
    ↓
[ECL Step 1] CLU 生成显式思维令牌（如 "<analyze>合同条款</analyze>"）
    ↓
[外部框架解析] 识别令牌类型 → 执行对应模块
    ├─ <analyze> → 文本分析器 → 返回结构化结果
    ├─ <tool:python> → 代码沙盒 → 返回执行输出
    ├─ <verify> → 逻辑验证器 → 返回一致性报告
    ├─ <retrieve> → 知识图谱 → 返回实体关系
    └─ <imagine> → 世界模型模拟器（v1.8预览）→ 返回预测状态
    ↓
[反馈编码] 框架输出 → 多模态嵌入 → 认知向量
    ↓
[ECL Step 2] CLU 基于反馈生成下一步思维...
    ↓
...
直到生成 <answer>令牌
```

### 2.2 思维令牌词汇表（Thought Token Vocabulary）
**显式认知的关键**：定义标准化的"认知指令集"

```python
THOUGHT_TOKENS = {
    # 元认知控制（Metacognitive Control）
    "<think>":      50000,  # 开始思考（进入ECL）
    "</think>":     50001,  # 结束思考（准备回答）
    "<reflect>":    50002,  # 反思当前状态（触发回溯）
    "<plan>":       50003,  # 制定多步计划
    
    # 核心思维（Core Cognition）
    "<decompose>":  50010,  # 分解问题（参数：子问题列表）
    "<synthesize>": 50011,  # 综合结果
    "<verify>":     50012,  # 请求验证（参数：验证类型）
    
    # 外部工具调用（Tool Use）
    "<tool:code>":  50020,  # 执行Python代码
    "<tool:search>":50021,  # 网络/知识库检索
    "<tool:calc>":  50022,  # 数学计算（调用Wolfram/SymPy）
    "<tool:vision>":50023,  # 图像分析（调用VLM）
    
    # 记忆操作（Memory Ops）- DNC接口
    "<mem:write>":  50030,  # 写入外部记忆（参数：key, value）
    "<mem:read>":   50031,  # 读取外部记忆（参数：query）
    "<mem:forget>": 50032,  # 标记遗忘（用于终身学习）
    
    # 社交认知（Social Cognition）- v1.8预览
    "<user:model>": 50040,  # 模拟用户理解状态
    "<expert:ask>": 50041,  # 请求专家介入（人机协作）
    
    # 输出控制
    "<answer>":     50090,  # 最终答案开始
    "</answer>":    50091,  # 最终答案结束
}
```

**关键设计**：这些不是文本字符串，而是**特殊的token ID**，模型必须通过显式生成这些token来"表达意图"。

### 2.3 CLU 架构重构（显式化版本）

**v1.7 CLU 的核心变化**：输出不再是稠密向量，而是**离散的思维token序列**

```python
class ExplicitCLU(nn.Module):
    def __init__(self, vocab_size=50100, hidden_size=1152):
        # 输入：当前工作记忆（文本+图像+代码结果的嵌入）
        self.encoder = MultimodalEncoder(hidden_size)
        
        # 核心：生成下一个思维token（类似语言模型，但词汇是认知原语）
        self.cognitive_transformer = nn.TransformerDecoder(
            d_model=hidden_size,
            nhead=18,
            num_layers=6,  # 浅层，因为复杂推理在外部框架
            dim_feedforward=hidden_size * 2
        )
        
        # 输出头：预测下一个思维token
        self.thought_head = nn.Linear(hidden_size, vocab_size)
        
        # 内容头：生成token的参数（如<tool:code>的代码内容）
        self.content_head = nn.Linear(hidden_size, vocab_size)  # 共享词汇或单独
        
    def forward_step(self, working_memory):
        """
        单步显式认知
        working_memory: 当前上下文（包含历史思维+外部反馈）
        """
        # 编码多模态输入
        x = self.encoder(working_memory)  # [batch, seq, hidden]
        
        # 生成下一个认知token
        logits = self.thought_head(x[:, -1, :])  # 只看最后位置
        
        # 采样思维token（贪心或采样）
        thought_token_id = torch.argmax(logits, dim=-1)
        thought_token = id_to_token[thought_token_id]
        
        # 如果是带参数的token（如<tool:code>），生成内容
        if thought_token in PARAMETRIC_TOKENS:
            content_logits = self.content_head(x[:, -1, :])
            content = generate_content(content_logits)
        else:
            content = None
            
        return thought_token, content
    
    def generate_thought_chain(self, max_steps=20):
        """生成完整的思维链（显式token序列）"""
        chain = []
        for step in range(max_steps):
            token, content = self.forward_step(working_memory)
            chain.append((token, content))
            
            # 如果是工具调用，暂停生成，等待外部框架
            if token.startswith("<tool:"):
                result = external_framework.execute(token, content)
                working_memory.append(result)  # 反馈注入
            elif token == "<answer>":
                break  # 显式终止
            else:
                working_memory.append(token)  # 自我反馈
                
        return chain
```

---

## 三、外部框架即 DNC（Differentiable Neural Computer）

### 3.1 框架作为显式记忆系统
**v1.7 的关键认识**：外部推理框架就是 v2.0 提到的 DNC 的**读写头（Read/Write Heads）**

```python
class ExternalCognitiveFramework:
    """
    作为模型外部记忆和计算外设的标准化接口
    """
    def __init__(self):
        # 记忆存储（显式数据库，非神经网络参数）
        self.episodic_memory = VectorDB(dimension=1152)  # 情节记忆
        self.semantic_memory = KnowledgeGraph()          # 语义知识
        self.procedural_memory = ToolRegistry()          # 工具注册表
        
        # 处理器（外部认知模块）
        self.processors = {
            "code": CodeSandbox(),
            "math": WolframClient(),
            "vision": VLMBridge(),
            "logic": Z3Solver(),  # 形式化验证
            "world": SimpleWorldModel(),  # v1.8: 轻量级世界模拟
        }
    
    def execute_thought(self, thought_token, content, context):
        """
        执行模型生成的思维指令
        返回：结构化反馈（注入下一步上下文）
        """
        if thought_token == "<tool:code>":
            # 执行代码，返回输出+错误+执行时间
            result = self.processors["code"].run(content)
            return {
                "type": "execution_result",
                "stdout": result.stdout,
                "stderr": result.stderr,
                "status": "success" if result.returncode == 0 else "error",
                "embedding": self.encode(result)  # 编码为认知向量
            }
            
        elif thought_token == "<mem:write>":
            # 写入外部记忆（DNC写操作）
            key = hash(content)  # 或模型提供的key
            self.episodic_memory.insert(
                key=key,
                value=content,
                metadata={"timestamp": now(), "context": context}
            )
            return {"type": "ack", "status": "written"}
            
        elif thought_token == "<mem:read>":
            # 读取外部记忆（DNC读操作）
            results = self.episodic_memory.query(
                query=content,
                top_k=3
            )
            return {
                "type": "retrieval",
                "memories": results,
                "embedding": self.encode(results)
            }
            
        elif thought_token == "<verify>":
            # 形式化验证
            is_valid, counterexample = self.processors["logic"].check(content)
            return {
                "type": "verification",
                "valid": is_valid,
                "counterexample": counterexample,
                "suggestion": "fix_X" if not is_valid else None
            }
        
        # ... 其他处理器
```

### 3.2 认知状态机（Cognitive State Machine）
**显式化认知流程**，确保安全和收敛：

```python
class CognitiveStateMachine:
    """
    监管显式认知循环的状态机
    防止无限循环、非法转换
    """
    VALID_TRANSITIONS = {
        "<think>": ["<decompose>", "<plan>", "<mem:read>"],
        "<decompose>": ["<tool:code>", "<tool:search>", "<verify>"],
        "<tool:code>": ["<verify>", "<reflect>"],
        "<verify>": ["<synthesize>", "<reflect>", "<tool:code>"],  # 验证失败可重试
        "<synthesize>": ["<answer>", "<mem:write>"],
        "<answer>": ["</answer>"],  # 终止
    }
    
    def validate(self, current_token, next_token):
        if next_token not in self.VALID_TRANSITIONS.get(current_token, []):
            raise CognitiveError(f"Illegal transition: {current_token} -> {next_token}")
    
    def enforce_safety(self, thought_chain):
        # 防止无限循环：限制<reflect>次数
        if thought_chain.count("<reflect>") > 3:
            return False, "Too many reflections"
        
        # 防止工具滥用：限制<tool:*>次数
        tool_count = sum(1 for t in thought_chain if t.startswith("<tool:"))
        if tool_count > 10:
            return False, "Tool use limit exceeded"
            
        return True, "OK"
```

---

## 四、多模态与终身学习支持

### 4.1 多模态反馈编码
**v1.7 支持外部框架返回任意模态**，编码后注入 CLU：

```python
class MultimodalFeedbackEncoder:
    def encode(self, framework_result):
        if framework_result["type"] == "text":
            return text_encoder(framework_result["content"])
            
        elif framework_result["type"] == "image":
            # 外部VLM处理图像，返回描述+特征
            return vision_encoder(framework_result["image"])
            
        elif framework_result["type"] == "execution_result":
            # 代码执行：混合文本输出+状态向量
            text_emb = text_encoder(framework_result["stdout"])
            status_emb = status_encoder(framework_result["status"])  # success/failure
            return combine(text_emb, status_emb)
            
        elif framework_result["type"] == "structured_data":
            # 知识图谱返回的图数据
            return graph_encoder(framework_result["triples"])
```

### 4.2 终身学习：动态工具与记忆添加
**无需重训练模型**，通过框架扩展能力：

```python
# 运行时添加新工具（新领域）
framework.register_tool(
    name="bio_seq",  # 生物序列分析
    handler=BioPythonAdapter(),
    description="Analyze DNA/RNA sequences",
    trigger_token="<tool:bio>"  # 模型可立即使用的新token
)

# 模型通过 few-shot 示例学习使用新工具
# 无需修改 CLU 参数，通过上下文学习（ICL）掌握
```

---

## 五、通往 v2.0 的技术路径（Roadmap）

### v1.7（当前）：显式认知基础设施
- **目标**：建立标准化的"模型-框架"接口（思维令牌体系）
- **关键指标**：工具调用准确率>90%，显式认知链可读性100%

### v1.8（世界模型）：内部模拟外部框架
- **升级**：CLU 增加 **World Model Simulator** 模块
- **能力**：生成 `<imagine>` 令牌时，**内部模拟**框架反馈（不实际执行），用于快速评估多方案
- **技术**：基于过去框架反馈训练的条件生成模型（p(结果|动作)）

### v1.9（社会认知）：显式用户建模
- **升级**：增加 `<user:model>` 和 `<expert:ask>` 令牌
- **能力**：模型显式维护"用户信念状态"（用户知道什么？不知道什么？），并决定何时请求人类专家

### v2.0（元认知架构）：自我修改认知架构
- **升级**：模型可以生成 `<arch:modify>` 令牌，请求框架添加新的思维类型或修改状态机
- **能力**：根据任务统计，自动建议"需要新的思维原语 X"

---

## 六、v1.7 实施规范

### 6.1 模型配置（保持 0.5B 规模）

```python
config_v1_7 = {
    "architecture": "ExplicitCognitiveLoop",
    "hidden_size": 1024,  # 略降，因为复杂推理在外部
    "vocab_size": 50100,  # 含思维token
    "cognitive_layers": 6,  # 浅层Transformer（仅生成分类token）
    
    "external_framework": {
        "memory": {"type": "VectorDB", "size": "unlimited"},  # 外存无限
        "tools": ["code", "math", "search", "vision", "logic"],
        "max_tool_calls": 10,  # 安全限制
    },
    
    "training": {
        "paradigm": "supervised+RL",
        "data": "显式思维链标注（含工具调用+反馈）",
        "curriculum": [
            "Step 1: 学习生成合法思维token序列",
            "Step 2: 学习使用外部工具（冻结CLU，仅训练工具使用）",
            "Step 3: 端到端强化学习（工具使用效率）"
        ]
    }
}
```

### 6.2 与 v1.6 的关键差异总结

| 维度 | v1.6 (隐式) | **v1.7 (显式)** |
|------|------------|----------------|
| **认知表示** | 稠密状态向量 | **离散思维token** |
| **外部交互** | 被动等待 | **主动生成指令** |
| **可解释性** | 黑盒 | **白盒（可读思维日志）** |
| **能力扩展** | 需重训练 | **即插即用（新工具token）** |
| **错误恢复** | 梯度反向传播 | **显式<reflect>回溯** |
| **多模态** | 输入侧 | **反馈侧（任意模态）** |

---

## 七、总结：v1.7 的哲学意义

> **"v1.7 完成了从'神经网络黑盒'到'认知操作系统'的跃迁：**
> 
> **模型（CLU）** = CPU，执行基本的模式识别和决策（生成分类token）
> **框架（External）** = 内存+外设+OS，提供存储、计算、I/O
> **思维Token** = 系统调用（syscall），标准化的能力接口
> 
> **这不是一个 bigger 的模型，而是一个可组合、可审计、可终身学习的认知架构。"**

**立即实施 v1.7 的理由**：
1. **安全性**：显式状态机防止无限循环和工具滥用
2. **可扩展性**：新领域无需重训练，注册新工具即可
3. **经济性**：0.5B 参数 + 外部框架 = 3B+ 模型的能力（在工具可用领域）
4. **对齐性**：人类可读的思维链，便于监督和对齐

**建议**：基于 v1.6 的代码，重构输出层为"思维token分类器"，并开发标准化的 `ExternalFramework` 接口。预计迁移时间 2-3 周。