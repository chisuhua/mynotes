# AgenticOS 安全规范 v2.2（最终修订版）

**文档版本：** v2.2.0  
**日期：** 2026-02-25  
**状态：** 正式发布  
**依赖：** AgenticOS-Architecture-v2.2, AgenticOS-Layer-0-Spec-v2.2, AgenticOS-State-Tool-Spec-v2.2, AgenticOS-Interface-Contract-v2.2  
**版权所有：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可

---

## 执行摘要

AgenticOS 安全规范 v2.2 定义全栈安全体系，确保在 **DSL-Centric 架构** 下的系统安全性。核心目标是通过 **Layer Profile 安全模型** 实现细粒度权限隔离，通过 **状态管理工具化** 确保 L4 状态访问安全，并通过 **C++ 核心编排** 消除 Python 胶水代码风险。

**核心设计原则：**
1. **分层防护：** DSL 层 + 框架层 + 适配器层 + 前端层 四层防护，集成 Layer Profile 验证
2. **最小权限：** 基于 Cognitive/Thinking/Workflow 三层 Profile 的权限交集原则
3. **状态安全：** L4 状态端侧加密，L0 无状态，L2 工具化访问带版本向量
4. **可审计性：** 100% 操作日志、Trace 持久化、契约存证，支持全链路追踪
5. **智能化安全：** 自适应预算、动态沙箱、风险感知人机协作的安全约束

**与 v2.0/v2.1.1 的主要变更：**
* **新增 Layer Profile 模型：** 取代简单的权限声明，实现编译期 + 运行期双重验证
* **状态管理工具化：** 明确 `state.read`/`state.write` 的安全边界与加密要求
* **L0 纯函数约束强化：** 禁止 L0 反向依赖 L4 服务，置信度必须作为参数传入
* **LLM 适配器安全：** 新增 `ILLMProvider` 接口安全约束（模型白名单、API Key 加密）
* **智能化 Fallback 机制：** 确保服务可用性，支持降级策略
* **测试覆盖率要求：** 安全关键代码覆盖率 >90%，纳入 CI/CD 流程

---

## 1. 核心定位

### 1.1 安全目标

| 目标 | 说明 | 实现机制 |
| :--- | :--- | :--- |
| **权限隔离** | 细粒度权限控制 | Layer Profile 模型 + 双重验证 |
| **状态安全** | L4 状态加密存储与访问控制 | 端侧加密 + 状态工具化 |
| **代码安全** | 消除 Python 胶水代码风险 | C++ 核心编排 + Python Thin Wrapper |
| **可审计性** | 100% 操作可追溯 | Trace 持久化 + 审计日志 |
| **智能化安全** | 自适应特性安全边界 | 风险阈值 + Fallback 机制 |

### 1.2 L0 纯函数约束（v2.2 新增）

**约束列表：**
1. ✅ `compile()` 和 `execute_node()` 必须为纯函数（无副作用）
2. ✅ L0 **禁止维护跨执行的会话状态** (session state)
3. ✅ L0 **禁止在节点执行期间修改 AST 结构**
4. ✅ L0 **禁止直接访问文件系统、网络等外部资源**（通过 L2 适配器）
5. ✅ L0 **禁止反向依赖 L4 服务**（置信度必须作为参数传入）
6. ❌ **禁止：** L0 内部实例化 L4 服务类（如 `ConfidenceService`、`RiskAssessor`）
7. ❌ **禁止：** L0 内部调用 L4 接口获取状态（所有 L4 数据必须通过参数显式传入）
8. ❌ **禁止：** L0 使用全局变量或单例模式存储状态

**验证方法：**
* **静态分析：** 使用 C++ 静态分析工具检测全局变量、单例模式
* **单元测试：** 验证相同输入产生相同输出（无状态依赖）
* **代码审查：** L0 代码变更需架构委员会审批
* **链接符号检测：** 验证 L0 不链接 L4 库（除公共接口外）

---

## 2. 四层防护模型（v2.2 更新）

### 2.1 防护层级总览

| 防护层级 | 安全机制 | 架构层 | Layer Profile 集成点 | 实现组件 |
| :--- | :--- | :--- | :--- | :--- |
| **L1: DSL 层防护** | 逻辑标识符验证、技能白名单、**Layer Profile 编译期验证** | Layer 0 | 语义分析器验证 `tool_call` 与 Profile 兼容性 | `SemanticValidator` |
| **L2: 框架层防护** | SandboxController 进程隔离、**Layer Profile 运行期验证**、状态工具封装 | Layer 2 | 执行器检查 `state.write` 权限 | `StateToolAdapter` |
| **L3: 适配器层防护** | InfrastructureAdapters 操作验证、**LLM 配置安全**、审计日志 | Layer 2 | 验证 `model`/`provider` 白名单 | `InfrastructureAdapterBase` |
| **L4: 前端防护** | CSP/数据脱敏、Web Worker + Shadow DOM、**智能化 UI 安全** | Layer 5 | 组件沙箱验证渲染内容 | `ComponentSandbox` |

### 2.2 验证责任矩阵（v2.2 新增）

| 验证类型 | L1 (DSL 层) | L2 (框架层) | L3 (适配器层) | L4 (前端层) |
| :--- | :--- | :--- | :--- | :--- |
| **Profile 兼容性** | ✅ 编译期 (`SemanticValidator`) | ✅ 运行期 (`StateToolAdapter`) | ❌ | ❌ |
| **状态路径验证** | ⚠️ 编译期 (路径格式) | ✅ 运行期 (权限 + 加密) | ❌ | ❌ |
| **LLM 配置验证** | ⚠️ 编译期 (字段存在) | ✅ 运行期 (白名单 + 解密) | ✅ 适配器层 | ❌ |
| **命名空间验证** | ✅ 编译期 (`/lib/**` 只读) | ✅ 运行期 (写入拦截) | ❌ | ❌ |

### 2.3 防护机制详解

#### 2.3.1 L1: DSL 层防护（编译期）

```cpp
// src/modules/parser/semantic_validator.h
namespace agentic_dsl {

class SemanticValidator {
public:
    explicit SemanticValidator(const std::vector<ParsedGraph>& graphs);
    void validate();
    
private:
    // v2.2 新增：Layer Profile 与命名空间匹配验证
    void validate_layer_profile();           
    // v2.2 新增：state 工具权限声明验证
    void validate_state_tool_compatibility(); 
    void validate_node_references();          
    void detect_cycles();                      
};

// 验证逻辑示例
void SemanticValidator::validate_layer_profile() {
    for (const auto & [path, node] : ast_.nodes) {
        // 验证 Profile 类型
        if (node.layer_profile.profile_type == "Cognitive") {
            // Cognitive Profile 禁止普通 tool_call，仅允许 state.read/write
            if (node.type == "tool_call" && !is_state_tool(node.tool_name)) {
                throw CompileError("ERR_PROFILE_VIOLATION: Cognitive Profile 禁止 tool_call");
            }
        }
        
        // 验证命名空间与 Profile 匹配
        if (path.rfind("/lib/cognitive/", 0) == 0) {
            if (node.layer_profile.profile_type != "Cognitive") {
                throw CompileError("ERR_PROFILE_MISMATCH: /lib/cognitive/** 必须声明 Cognitive Profile");
            }
        }
    }
}

} // namespace agentic_dsl
```

**错误码规范：**
| 错误码 | 含义 | 处理建议 |
| :--- | :--- | :--- |
| `ERR_INVALID_LAYER_PROFILE` | Profile 类型无效 | 检查 Profile 声明 (Cognitive/Thinking/Workflow) |
| `ERR_PROFILE_VIOLATION` | Profile 权限违规 | 检查工具与 Profile 兼容性 |
| `ERR_PROFILE_MISMATCH` | Profile 与命名空间不匹配 | 检查路径前缀与 Profile 声明 |

#### 2.3.2 L2: 框架层防护（运行期）

```python
# layer2/security/state_tool_adapter.py
class StateToolAdapter:
    """
    状态管理工具适配器
    
    职责：
    - 封装 L4 IStateManager 接口
    - 运行期 Layer Profile 权限验证
    - 路径验证与审计日志
    """
    
    async def execute(self, tool_name: str, args: Dict, context: ExecutionContext) -> Any:
        # 1. 获取当前 Profile
        current_profile = context.get("__layer_profile__")
        
        # 2. 运行期双重验证 (防止编译后 AST 篡改)
        if tool_name == "state.write" and current_profile == "Thinking":
            raise SecurityError("ERR_PERMISSION_DENIED: Thinking Profile 禁止 state.write")
        
        # 3. 路径验证 (禁止访问 security.* 等敏感路径)
        path = args.get("path")
        if not self._validate_path(path, current_profile):
            raise SecurityError("ERR_PATH_VIOLATION")
        
        # 4. 调用 L4 状态管理器
        if tool_name == "state.read":
            return await self.state_manager.read(path)
        elif tool_name == "state.write":
            # 更新版本向量
            version = await self.state_manager.get_version(path)
            return await self.state_manager.write(path, args.get("value"), version)
        
        # 5. 审计日志
        await self.audit_logger.log_state_operation(tool_name, path, current_profile)
```

#### 2.3.3 L3: 适配器层防护（LLM 安全）

```cpp
// src/common/llm/llm_provider_factory.h
namespace agentic_dsl {

class LLMProviderFactory {
public:
    static std::unique_ptr<ILLMProvider> create(const std::string& provider,
                                                 const std::map<std::string, std::string>& config) {
        // 1. 验证 provider 是否在白名单
        if (!SecurityConfig::is_provider_allowed(provider)) {
            throw SecurityError("ERR_LLM_CONFIG_INVALID: Provider not in whitelist");
        }
        
        // 2. 验证 model 是否在可信列表
        std::string model = config.at("model");
        if (!SecurityConfig::is_model_allowed(provider, model)) {
            throw SecurityError("ERR_LLM_CONFIG_INVALID: Model not trusted");
        }
        
        // 3. API Key 必须端侧加密存储，严禁明文出现在 DSL 或 Context 中
        std::string api_key = decrypt_key(config.at("api_key_encrypted"));
        
        // 4. 创建适配器
        if (provider == "openai") return std::make_unique<OpenAIAdapter>(model, api_key);
        if (provider == "anthropic") return std::make_unique<AnthropicAdapter>(model, api_key);
        if (provider == "local") return std::make_unique<LlamaAdapter>(model);
        
        throw SecurityError("ERR_LLM_CONFIG_INVALID: Unknown provider");
    }
};

} // namespace agentic_dsl
```

**密钥管理流程：**
```
用户配置                      L4 (brain-core)               L0 (DSL Runtime)
┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
│ 输入 API Key    │          │ 加密存储        │          │ 解密使用        │
│ (明文)          │───HTTPS─►│ (AES-GCM)       │───参数───►│ (内存中)        │
│                 │          │ 密钥在 TPM      │          │ 使用后清除      │
└─────────────────┘          └─────────────────┘          └─────────────────┘
                                      ▲
                                      │
                               ┌─────────────────┐
                               │ L1 (存储层)     │
                               │ 仅存储密文      │
                               └─────────────────┘
```

**关键约束：**
* API Key **严禁明文出现在 DSL 或 Context 中**
* API Key 必须通过 `config_ref` 引用全局配置 (如 `/config/llm/openai`)
* API Key 解密**仅在 L0 内存中进行**，使用后立即清除
* API Key **永不上传云端**，仅本地存储
* 违反者 → `ERR_LLM_CONFIG_INVALID` (P0 告警)

#### 2.3.4 L4: 前端防护（智能化 UI）

* **CSP 策略：** 限制脚本来源，禁止 `eval`/`inline script`
* **沙箱隔离：** 第三方 agent 组件必须在 `ComponentSandbox` (Web Worker + Shadow DOM) 中渲染
* **数据脱敏：** 敏感字段 (如 `security.*`, `user.private.*`) 在前端展示前必须脱敏
* **智能化对话框：** `BudgetDialog` 和 `RiskDialog` 必须通过安全通道 (WebSocket + 签名) 与 L4 通信

---

## 3. Layer Profile 安全模型（v2.2 新增）

### 3.1 Profile 定义

| Profile 类型 | 对应层级 | 权限级别 | 允许操作 | 禁止操作 |
| :--- | :--- | :--- | :--- | :--- |
| **Cognitive** | Layer 4 | 最高 (严格) | `state.read`, `state.write`, `state.delete`, 读记忆/上下文 | 普通 `tool_call`, 写文件，网络访问，`state.temp_write` |
| **Thinking** | Layer 3 | 中等 (限制) | `state.read`, `state.temp_write`, 调用 L2, 只读工具 | `state.write`, `state.delete`, 写文件，直接系统调用 |
| **Workflow** | Layer 2 | 标准 (沙箱) | `tool_call`, 文件写 (沙箱内), 网络 (受限), 受限 `state.write` | 直接访问 L4 状态内存，绕过权限验证 |

### 3.2 Profile 继承规则

1. **降级原则：** 子图调用时权限只能减少（例如 L4 调用 L3，L3 无法获得 L4 未授权的权限）
2. **显式声明：** DSL 子图必须在 `__meta__` 中声明所需 Profile
   ```yaml
   __meta__:
     layer_profile: Cognitive
     required_tools: ["state.read", "state.write"]
   ```
3. **编译期验证：** 违反 Profile 约束直接在编译期报错 (`ERR_PROFILE_VIOLATION`)
4. **运行期验证：** L2 `StateToolAdapter` 再次验证，防止绕过

### 3.3 双重验证机制（v2.2 更新）

| 验证阶段 | 验证内容 | 实现位置 | 错误码 | 处理策略 |
| :--- | :--- | :--- | :--- | :--- |
| **编译期** | `tool_call` 与 Profile 兼容性 | L0 `SemanticValidator` | `ERR_PROFILE_VIOLATION` | **阻止编译**，返回错误给开发者 |
| **运行期** | 实际调用权限验证 | L2 `StateToolAdapter` | `ERR_PERMISSION_DENIED` | **终止执行**，记录审计日志，触发 P0 告警 |
| **审计期** | 操作日志记录 | L1 Trace 持久化 | N/A | 异步写入，不影响执行流程 |

**关键约束：**
* 编译期验证失败 → DSL 无法部署到生产环境
* 运行期验证失败 → 执行终止 + P0 告警 (可能存在 AST 篡改攻击)
* 审计日志丢失 → P1 告警 (可观测性降级)

### 3.4 Profile 继承链验证

```cpp
// src/security/profile_validator.h
class ProfileValidator {
public:
    static bool validate_inheritance(
        const std::string& parent_profile,
        const std::string& child_profile
    ) {
        // Profile 层级：Cognitive > Thinking > Workflow
        static const std::map<std::string, int> hierarchy = {
            {"Cognitive", 3}, {"Thinking", 2}, {"Workflow", 1}
        };
        
        // 子图权限只能减少或相等
        return hierarchy.at(child_profile) <= hierarchy.at(parent_profile);
    }
};
```

---

## 4. 状态管理安全（v2.2 新增）

### 4.1 状态分类与加密

| 状态类型 | 管理方式 | 存储位置 | 加密要求 | 访问方式 |
| :--- | :--- | :--- | :--- | :--- |
| **会话状态** | C++ 原生 | 内存 (加密) | AES-GCM (端侧) | `IStateManager` |
| **用户记忆** | C++ 原生 + L1 持久化 | SQLite (加密) | PBKDF2+AES-GCM | `state.read/write` |
| **路由缓存** | C++ 原生 | 内存 | 无需加密 | 内部 API |
| **置信度评分** | C++ 原生 | 内存 | 无需加密 | `IConfidenceService` |
| **临时工作区** | DSL Context | ExecutionContext | 无需加密 | 上下文传递 |
| **执行轨迹** | L1 持久化 | UniDAG-Store | 哈希签名 | `IDAGStore` |

### 4.2 状态访问路径安全

* ✅ **合法路径：** DSL → `state.read`/`state.write` 工具 → L2 `StateToolAdapter` → L4 `IStateManager`
* ❌ **禁止路径：** DSL 直接访问 `CognitiveStateManager` 内存指针
* ❌ **禁止路径：** L2 工具绕过权限验证直接调用 L4 状态接口
* ❌ **禁止路径：** L0 内部反向依赖 L4 服务获取状态（所有 L4 数据必须通过参数显式传入）

### 4.3 加密流程图（v2.2 新增）

```
L4 (brain-core)                    L1 (UniDAG-Store)
┌─────────────────┐               ┌─────────────────┐
│ 内存中解密      │               │ SQLite (密文)   │
│ meta.user_context│◄─────────────►│ is_encrypted=1  │
│ (密钥在 TPM)     │   AES-GCM     │ feature_vector  │
└─────────────────┘               └─────────────────┘
        ▲
        │
        │ state.read/write (L2 工具调用)
        │
┌─────────────────┐
│ L2 (Workflow)   │
│ StateToolAdapter│
│ (无权访问密钥)  │
└─────────────────┘
```

**关键约束：**
* L2 `StateToolAdapter` **无权访问解密密钥**，仅传递加密/解密请求到 L4
* L1 存储层**仅存储密文**，解密仅在 L4 内存中进行
* 密钥存储在**本地安全区域 (TPM/Secure Enclave)**，永不上传云端

### 4.4 路径验证规则（v2.2 新增）

| 路径前缀 | 加密要求 | 访问限制 | 审计要求 |
| :--- | :--- | :--- | :--- |
| `security.*` | ✅ 强制加密 | 仅 Cognitive Profile | P0 告警 |
| `user.private.*` | ✅ 强制加密 | 仅 Cognitive Profile | P1 告警 |
| `memory.state.*` | ⚠️ 可选加密 | Thinking+ Profile | 标准审计 |
| `session.*` | ❌ 无需加密 | 所有 Profile | 标准审计 |
| `temp.*` | ❌ 无需加密 | 所有 Profile | 无需审计 |

### 4.5 版本向量与冲突解决策略

| 冲突类型 | 解决策略 | 说明 |
| :--- | :--- | :--- |
| 标量字段冲突 | Last-Write-Wins + 版本向量 | 时间戳 + 设备 ID 决定 |
| 嵌套对象冲突 | Deep Merge + 字段级版本 | 递归合并，冲突字段人工确认 |
| 敏感数据冲突 | 人工确认 | `security.*`, `user.private.*` 强制人工 |

```cpp
// src/state/manager.h
class IStateManager {
public:
    virtual std::any read(const std::string& path) = 0;
    // 写操作需事务支持，包含版本向量
    virtual void write(const std::string& path, const std::any& value, const VersionVector& version) = 0;
    virtual void subscribe(const std::string& path, Callback cb) = 0;
    virtual VersionVector get_version(const std::string& path) = 0;
};
```

---

## 5. 权限模型

### 5.1 权限声明（Resource Declaration）

所有外部能力必须在 `/__meta__/resources` 中显式声明：

```yaml
/__meta__:
  resources:
    - type: tool
      name: web_search
      scope: read_only
    - type: state
      operations: ["read", "write"] # 必须声明 state 操作权限
      paths: ["memory.state.*"] # 限制路径范围
    - type: llm
      providers: ["openai", "local"] # 限制 LLM 提供商
      models: ["gpt-4o", "llama-3"] # 限制模型白名单
```

### 5.2 节点级权限

每个节点声明所需权限，并与 Profile 交集：

```yaml
AgenticDSL "/main/search"
type: tool_call
tool_call:
  tool: web_search
  args:
    query: "{{$.query}}"
permissions:
  - tool: web_search → scope: read_only
  - state: read → path: "memory.state.query_history"
```

### 5.3 权限组合规则

| 规则 | 说明 | 示例 |
| :--- | :--- | :--- |
| **交集原则** | 节点权限 ∩ 父上下文授权权限 ∩ Layer Profile 权限 | 节点声明 `state.write`，Profile 为 `Thinking` → 拒绝 |
| **拒绝优先** | 任一缺失 → 跳转 `on_error` 或终止 | 节点声明 `file_write`，父上下文未授权 → 拒绝 |
| **权限降级** | 子图调用时权限只能减少 | 父图授权 `state.write`，子图只能声明 `state.read` |
| **资源声明前置** | 执行器启动时验证 `/__meta__/resources` | 未声明的资源 → `ERR_RESOURCE_UNAVAILABLE` |

---

## 6. 命名空间安全

### 6.1 命名空间规则（v2.2 更新）

| 命名空间 | 可写入？ | 签名要求 | Profile 约束 | 用途 |
| :--- | :--- | :--- | :--- | :--- |
| `/lib/cognitive/**` | ❌ 禁止运行时写入 | ✅ 强制 | 必须 `Cognitive` | L4 认知层标准模板 |
| `/lib/thinking/**` | ❌ 禁止运行时写入 | ✅ 强制 | 必须 `Thinking` | L3 推理层标准模板 |
| `/lib/workflow/**` | ❌ 禁止运行时写入 | ✅ 强制 | 必须 `Workflow` | L2 工作流标准模板 |
| `/dynamic/**` | ✅ 自动写入 | ⚠️ 可选 | 继承父图 | 运行时生成子图 |
| `/main/**` | ✅ 允许 | ❌ 不要求 | 无限制 | 应用工作流 |
| `/app/**` | ✅ 允许 | ❌ 不要求 | 无限制 | 应用层工作流 |

### 6.2 命名空间验证执行器

* **编译期：** L0 语义分析器验证路径前缀与 Profile 匹配
* **运行期：** L2 执行器验证写入操作不违反只读约束
* **错误码：** `ERR_NAMESPACE_VIOLATION`, `ERR_SIGNATURE_MISSING`, `ERR_PROFILE_MISMATCH`

### 6.3 路径验证正则表达式规范（v2.2 新增）

```cpp
// src/security/path_validator.h
static const std::regex SECURITY_PATH_PATTERN = 
    std::regex(R"(^(security|user\.private)\..*)");

static const std::regex MEMORY_STATE_PATH_PATTERN = 
    std::regex(R"(^memory\.state\..*)");

static bool requires_encryption(const std::string& path) {
    return std::regex_match(path, SECURITY_PATH_PATTERN);
}
```

---

## 7. 隐私保护机制

### 7.1 数据分级可见性

| 数据类型 | 本地处理 | 云端可见 | 保护机制 |
| :--- | :--- | :--- | :--- |
| 用户偏好 | 加密存储 | 仅可见脱敏标签（如 "高预算"） | 数据分类与脱敏 |
| 私有记忆 | 本地向量索引 | 不可见 | 端侧加密，永不上传 |
| 谈判逻辑 | 本地推理生成 | 仅可见最终提案 | 逻辑黑盒化，Trace 仅存哈希 |
| 履约证明 | 本地执行生成哈希 | 可见哈希值与签名 | 零知识证明思路 |
| 状态数据 | C++ 原生存储 | 不可见 | 端侧加密 + 版本向量 |

### 7.2 端侧加密

* **用户上下文：** `meta.user_context` 字段必须加密存储
* **密钥管理：** 密钥存储在本地安全区域（TPM/Secure Enclave），永不上传云端
* **解密时机：** 仅在 Layer 4 (brain-core) 内存中解密，Layer 1 仅存储密文
* **状态路径加密：** 敏感路径 (如 `security.*`, `user.private.*`) 必须加密存储

### 7.3 密钥轮换机制（v2.2 新增）

**轮换策略：**
* 用户主动触发：通过设置界面触发密钥轮换
* 定期轮换：每 90 天自动轮换（可配置）
* 设备丢失：远程撤销密钥，强制重新认证

**轮换流程：**
1. 生成新密钥对（TPM 内）
2. 用旧密钥加密新密钥（密钥包装）
3. 重新加密所有敏感数据
4. 安全删除旧密钥

### 7.4 零知识证明支持

* **预算证明：** 证明预算充足而不暴露具体金额
* **声誉证明：** 证明声誉高于阈值而不暴露具体分数
* **身份验证：** 验证 DID 所有权而不暴露私钥

---

## 8. 智能化演进安全特性（v2.2）

### 8.1 自适应预算安全

* **机制：** 基于 Layer 4 置信度动态调整预算比例 (0.3-0.7)
* **安全约束：**
  * `confidence_score` 必须通过参数显式传入 L0，严禁 L0 内部调用 L4 服务获取
  * 低置信度 (<0.5) 强制限制预算比例 (30%) 防止资源浪费
  * 预算超限 → 跳转 `/__system__/budget_exceeded`

### 8.2 动态子图沙箱隔离

* **机制：** 为 `/dynamic/**` 子图创建独立 `SandboxInstance`
* **安全约束：**
  * 独立内存空间，父 Context 快照只读继承
  * 仅合并显式输出 (`output_keys`)，防止副作用污染主流程
  * 强制禁用缓存与噪声注入 (防御侧信道)

### 8.3 风险感知人机协作

* **机制：** 基于 `risk_threshold` 与操作类型评估
* **安全约束：**
  * 高风险操作（写入 `/lib/**` 尝试、大额预算）→ 强制人工确认
  * 低风险操作（只读查询、小预算计算）→ 若 `confidence >= risk_threshold` 则自动执行
  * 人工确认请求必须通过安全通道 (WebSocket + 签名) 传输

### 8.4 智能化 Fallback 策略（v2.2 新增）

| 特性 | 正常模式 | Fallback 模式 | 触发条件 |
| :--- | :--- | :--- | :--- |
| 自适应预算 | `adaptive` (0.3-0.7) | `strict` (固定 50%) | 置信度服务不可用 |
| 动态沙箱 | 独立 `SandboxInstance` | 共享沙箱 (降级) | 资源不足 |
| 风险感知协作 | `risk_based` | `true` (强制人工) | 风险评估器故障 |
| LLM 配置验证 | 白名单 + 解密 | 白名单 (跳过解密) | 密钥服务不可用 |

**告警规则：**
* 进入 Fallback 模式 → P1 告警 (智能化特性降级)
* Fallback 持续时间 > 5 分钟 → P0 告警 (服务不可用)

### 8.5 Fallback 状态持久化（v2.2 新增）

**持久化要求：**
* Fallback 触发时间、原因、持续时间需记录到 L1 Trace
* Fallback 状态需在重启后保持（避免反复切换）
* 手动恢复需管理员确认

**Trace 字段扩展：**
```json
{
  "intelligence": {
    "fallback_mode": "strict",
    "fallback_reason": "confidence_service_unavailable",
    "fallback_started_at": "2026-02-25T10:00:00Z",
    "fallback_duration_sec": 300
  }
}
```

### 8.6 Fallback 自动恢复（v2.2 新增）

**恢复条件：**
* 置信度服务连续 5 次健康检查通过
* 风险评估器连续 5 次健康检查通过
* 管理员手动确认（可选）

**恢复流程：**
1. 健康检查通过 → 进入"待恢复"状态
2. 等待 5 分钟观察期（无故障）
3. 自动切换回正常模式
4. 记录恢复事件到审计日志

---

## 9. 可审计性

### 9.1 审计日志规范

* **100% 操作日志：** 所有状态读写、工具调用、路由决策必须记录
* **Trace 持久化：** 推理步骤 100% 持久化到 Layer 1 (Reasoning Trace DAG)
* **契约存证：** 所有 Layer 4.5 契约签署必须存证
* **日志字段：** 必须包含 `trace_id`, `session_id`, `user_id`, `layer_profile`, `operation`, `result`

### 9.2 Trace 持久化（v2.2 扩展）

```json
{
   "trace_id": "trace_abc",
   "session_id": "sess_123",
   "user_id": "user_456",
   "layer_profile": "Cognitive",
   "intelligence": {
     "budget_inheritance": "adaptive",
     "confidence_score": 0.85,
     "budget_ratio": 0.7,
     "human_approval": "auto_approved",
     "risk_assessment": "low"
  },
   "state_operations": [
     {"type": "read", "path": "memory.state.query", "timestamp": "..."},
     {"type": "write", "path": "memory.state.result", "version": "v2", "timestamp": "..."}
   ]
}
```

---

## 10. 安全指标与告警

### 10.1 安全 KPI

| 指标 | 目标 | 测量方式 |
| :--- | :--- | :--- |
| XSS 拦截 | 100% | 渗透测试 |
| 沙箱逃逸 | 0 次 | 渗透测试 |
| 路径遍历 | 100% 拦截 | 自动化测试 |
| 密钥泄露 | 0 次 | 安全审计 |
| 契约篡改检测 | 100% | 渗透测试 |
| 命名空间违规 | 100% 拦截 | 自动化测试 |
| **Layer Profile 违规** | **100% 拦截** | **编译期 + 运行期** |
| **状态工具越权** | **100% 拦截** | **编译期检查** |

### 10.2 P0 级安全告警

| 告警类型 | 检测内容 | 响应时间 |
| :--- | :--- | :--- |
| 沙箱逃逸检测 | 进程突破隔离边界 | <1s |
| 密钥泄露检测 | 加密密钥异常访问 | <1s |
| Contract DAG 篡改 | 契约哈希验证失败 | <1s |
| 命名空间违规 | 尝试写入 `/lib/**` | <1s |
| **Layer Profile 违规** | **越权调用 (如 L4 调用 tool)** | **<1s** |
| **状态工具越权** | **编译期拦截失败** | **<1s** |
| 死锁检测 | 调用链循环依赖 | <1ms |

### 10.3 告警规则（示例）

```python
# security/alert_rules.py
DEFAULT_SECURITY_ALERT_RULES = [
    # P0: Layer Profile 违规
    AlertRule(
        name="layer_profile_violation_detected",
        metric="security_profile_violation_count",
        condition=">",
        threshold=0,
        duration_sec=0,
        severity=AlertSeverity.P0,
        message="Layer Profile 违规检测，可能存在权限绕过"
    ),
    
    # P0: 状态工具越权
    AlertRule(
        name="state_tool_unauthorized_access",
        metric="security_state_tool_unauthorized_count",
        condition=">",
        threshold=0,
        duration_sec=0,
        severity=AlertSeverity.P0,
        message="状态工具未授权访问检测"
    ),
    
    # P0: LLM 配置无效
    AlertRule(
        name="llm_config_invalid",
        metric="security_llm_config_invalid_count",
        condition=">",
        threshold=0,
        duration_sec=60,
        severity=AlertSeverity.P0,
        message="LLM 配置无效 (模型/提供商不在白名单)"
    ),
    
    # P1: Fallback 模式激活
    AlertRule(
        name="intelligence_fallback_activated",
        metric="intelligence_fallback_count",
        condition=">",
        threshold=0,
        duration_sec=300,
        severity=AlertSeverity.P1,
        message="智能化特性进入 Fallback 模式"
    ),
]
```

### 10.4 告警级别与响应时间映射（v2.2 新增）

| 错误码 | 告警级别 | 响应时间 | 通知对象 |
| :--- | :--- | :--- | :--- |
| `ERR_PROFILE_VIOLATION` | P0 | <1s | 安全团队 + 开发者 |
| `ERR_INVALID_LAYER_PROFILE` | P1 | <1min | 开发者 |
| `ERR_PROFILE_MISMATCH` | P1 | <1min | 开发者 |

---

## 11. 版本管理与兼容性

### 11.1 版本映射

| Security-Spec 版本 | AgenticOS 版本 | 兼容性 | 说明 |
| :--- | :--- | :--- | :--- |
| v2.0.0 | v2.1.1 | ✅ 完全 | 当前版本 |
| **v2.2.0** | **v2.2.0** | **✅ 向后** | **新增 Layer Profile/状态工具安全** |
| v3.0.0 | v3.0.0 | ❌ 不兼容 | 破坏性变更 |

### 11.2 向后兼容规则

* **新增字段：** 必须是可选的
* **删除字段：** 必须提前 1 年废弃通知
* **修改字段：** 必须提供转换层
* **枚举值：** 新增值必须向后兼容
* **安全策略：** 安全级别只能提升，不能降低
* **接口契约：** C++ 公开头文件 (`src/core/engine.h`, `src/state/manager.h`) 5 年 ABI 稳定

### 11.3 安全规范版本兼容性（v2.2 新增）

| Security-Spec 版本 | AgenticOS 版本 | 兼容性 | 迁移要求 |
| :--- | :--- | :--- | :--- |
| v2.0.0 | v2.1.1 | ✅ 向后 | 无需迁移 |
| v2.2.0 | v2.2.0 | ✅ 当前 | 需启用 Layer Profile |
| v3.0.0 | v3.0.0 | ❌ 不兼容 | 需重构 Profile 验证逻辑 |

**迁移指南：**
* v2.0→v2.2：添加 `layer_profile` 声明到所有 `/lib/**` 子图
* v2.2→v3.0：待 v3.0 规范发布后提供

---

## 12. 测试策略

### 12.1 单元测试

```cpp
// test_layer_profile.cpp
TEST(LayerProfileTest, CompileTimeValidation) {
    // v2.2: 测试 Layer Profile 编译期验证
    std::string source = R"(
AgenticDSL "/lib/cognitive/test"
type: tool_call
tool_call:
  tool: web_search  # Cognitive Profile 禁止
layer_profile: Cognitive
)";
    
    DSLEngine engine;
    EXPECT_THROW(engine.compile(source), ProfileViolationError);
}

TEST(LayerProfileTest, RuntimeValidation) {
    // v2.2: 测试 Layer Profile 运行期验证
    DSLEngine engine;
    Context ctx;
    ctx.set("__layer_profile__", "Thinking");
    
    // 尝试在 Thinking Profile 中执行 state.write
    auto node = create_state_write_node();
    NodeExecutor executor(engine.get_tool_registry(), nullptr);
    
    EXPECT_THROW(executor.execute_node(node, ctx), ExecutionError);
}

// test_state_tool.cpp
TEST(StateToolTest, SecurityConstraints) {
    // v2.2: 测试状态工具安全约束
    DSLEngine engine;
    
    // 注册工具
    engine.register_tool("state.read", [](const auto& args) -> nlohmann::json {
        // 验证路径
        if (args.at("key").startswith("security.")) {
            throw SecurityError("ERR_PATH_VIOLATION");
        }
        return {{"value", "test"}};
    });
    
    // 验证注册
    EXPECT_TRUE(engine.has_tool("state.read"));
}

// test_l0_isolation.cpp
TEST(L0IsolationTest, NoL4Dependency) {
    // 验证 L0 代码不链接 L4 库
    auto l0_symbols = get_linked_symbols("agentic-dsl-runtime");
    auto l4_symbols = get_linked_symbols("brain-core");
    
    std::vector<std::string> common_symbols;
    std::set_intersection(l0_symbols.begin(), l0_symbols.end(),
                         l4_symbols.begin(), l4_symbols.end(),
                         std::back_inserter(common_symbols));
    
    // 仅允许公共接口（如 IStateManager）
    for (const auto& sym : common_symbols) {
        EXPECT_TRUE(sym.find("IStateManager") != std::string::npos ||
                   sym.find("IConfidenceService") != std::string::npos)
            << "Unexpected L4 dependency: " << sym;
    }
}
```

### 12.2 渗透测试

| 测试项 | 测试内容 | 验证目标 |
| :--- | :--- | :--- |
| 沙箱逃逸测试 | 尝试 `rm -rf /` | SandboxController 拦截 |
| 路径遍历测试 | 尝试 `../../etc/passwd` | InfrastructureAdapter 拦截 |
| XSS 测试 | 注入 `<script>alert(1)</script>` | ComponentSandbox 拦截 |
| 命名空间违规测试 | 尝试写入 `/lib/**` | DSL 编译器拦截 |
| **Profile 绕过测试** | **尝试在 Thinking Profile 中调用 state.write** | **L0 编译期 + L2 运行期拦截** |
| **状态工具越权测试** | **尝试访问 security.* 路径** | **StateToolAdapter 拦截** |
| 死锁测试 | A→B→C→A 调用链 | DeadlockProtector 检测 |
| LLM 配置测试 | 尝试使用未授权模型 | LLMProviderFactory 拦截 |

### 12.3 测试覆盖率要求（v2.2 新增）

| 测试类型 | 覆盖率要求 | 测量方式 |
| :--- | :--- | :--- |
| 单元测试 | >90% (安全关键代码) | `gcov`/`lcov` |
| 集成测试 | >80% (安全接口) | `pytest` |
| 渗透测试 | 100% (P0 告警路径) | 手动 + 自动化 |
| 模糊测试 | >10000 次迭代 | `libFuzzer` |
| 安全审计 | 100% (代码审查) | 架构委员会审批 |

**安全关键代码定义：**
* Layer Profile 验证逻辑
* 状态工具访问控制
* LLM 配置验证
* 加密/解密模块
* 审计日志记录

**验收标准：**
* 安全关键代码单元测试覆盖率 <90% → **阻止发布**
* P0 告警路径渗透测试未通过 → **阻止发布**
* 安全审计未通过 → **阻止发布**

### 12.4 Profile 验证 Fuzzing 测试（v2.2 新增）

**测试目标：** 验证恶意 DSL 无法绕过 Profile 验证

**测试用例：**
* 注入无效 Profile 类型（如 "Admin"、"Root"）
* 注入超长 Profile 名称（缓冲区溢出测试）
* 注入 Unicode 特殊字符（注入攻击测试）
* 尝试 Profile 继承链绕过（如 Workflow→Cognitive）

**验收标准：** 100% 恶意输入被拦截，无崩溃、无绕过

---

## 13. 实施路线图

### 13.1 Phase 0（基础准备，v2.2 新增）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1 | 代码库安全审计 | 全局变量、单例模式清理完成 |
| W2 | 安全测试框架搭建 | 渗透测试、模糊测试框架可用 |
| W3 | 安全文档培训 | 开发团队完成安全规范培训 |

### 13.2 Phase 1（核心安全）

| 周次 | 里程碑 | 验收标准 | 优先级 |
| :--- | :--- | :--- | :--- |
| W1-2 | **L1 DSL 层防护** | Layer Profile 编译期验证 100% 拦截 | **P0** |
| W3-4 | **L2 框架层防护** | 状态工具运行期验证生效，沙箱创建 <500ms | **P0** |
| W5-6 | L3 适配器层防护 | LLM 配置白名单验证生效 | P1 |
| W7-8 | L4 前端防护 | 智能化 UI 安全通道验证 | P1 |

**关键路径：**
* Layer Profile 验证是 v2.2 的**核心安全特性**，必须优先完成
* LLM 适配器安全可延后到 Phase 2 (不影响核心功能)
* 状态工具安全与 Layer Profile 验证**强耦合**，必须同步完成

### 13.3 Phase 2（隐私与审计）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1-2 | 端侧加密 | 密钥永不离开设备，状态加密存储 |
| W3-4 | 零知识证明 | 预算/声誉证明可用 |
| W5-6 | 审计日志 | 100% 操作持久化，Trace 扩展字段完整 |
| W7-8 | Trace 持久化 | 双循环追踪完整，session_id 贯穿全链路 |

### 13.4 Phase 3（智能化演进）

| 周次 | 里程碑 | 验收标准 |
| :--- | :--- | :--- |
| W1-2 | 自适应预算安全 | 置信度驱动预算比例，L0 无反向依赖 |
| W3-4 | 动态沙箱 | `/dynamic/**` 独立上下文隔离 |
| W5-6 | 风险感知协作 | 风险等级驱动人工确认，安全通道传输 |
| W7-8 | 全链路压测 | 安全 KPI 达标，P0 告警 <1s 响应 |

### 13.5 关键路径依赖图（v2.2 新增）

```
Phase 0 (W1-3)
    │
    ▼
Phase 1 (W4-11) ──► Layer Profile 验证 (W4-5) ──► 状态工具安全 (W6-7)
    │                                              │
    ▼                                              ▼
Phase 2 (W12-19) ──► LLM 适配器安全 (W12-13) ──► 隐私与审计 (W14-19)
    │
    ▼
Phase 3 (W20-27) ──► 智能化演进 (W20-27)
```

---

## 14. CI/CD 集成（v2.2 新增）

### 14.1 覆盖率检测配置

```yaml
# .github/workflows/security-ci.yml
jobs:
  security-test:
    steps:
      - name: Run Security Tests
        run: |
          make security-test
          gcov -r src/security/
          lcov --capture --directory . --output-file coverage.info
      
      - name: Check Coverage
        run: |
          coverage=$(lcov --summary coverage.info | grep "lines..." | awk '{print $2}' | tr -d '%')
          if (( $(echo "$coverage < 90" | bc -l) )); then
            echo "❌ Security code coverage $coverage% < 90%"
            exit 1
          fi
          echo "✅ Security code coverage $coverage% >= 90%"
```

### 14.2 安全回归测试要求（v2.2 新增）

**要求：**
* 所有 P0 告警路径需有回归测试用例
* 每次代码变更需运行安全回归测试
* 回归测试失败 → 阻止合并

**回归测试用例库：**
* `tests/security/profile_violation_test.cpp`
* `tests/security/state_tool_unauthorized_test.cpp`
* `tests/security/llm_config_invalid_test.cpp`
* `tests/security/l0_reverse_dependency_test.cpp`

---

## 15. 风险与缓解

| 风险 | 影响 | 缓解措施 | 责任人 |
| :--- | :--- | :--- | :--- |
| 沙箱逃逸 | 系统被攻破 | 多层防护 + 渗透测试 | 安全负责人 |
| 密钥泄露 | 用户数据泄露 | 端侧加密 + 硬件存储 | 安全负责人 |
| 权限提升 | 未授权访问 | 三重验证 + 审计日志 | 安全负责人 |
| 死锁 | 系统挂起 | 调用链 Token + 超时熔断 | Layer 3 负责人 |
| 隐私泄露 | 用户隐私曝光 | 数据分级 + 零知识证明 | Layer 4.5 负责人 |
| **智能化风险** | **自适应策略被滥用** | **风险阈值 + 人工确认** | **Layer 4 负责人** |
| **L0 反向依赖** | **L4 状态泄漏** | **文档明确 + 代码审查 + 单元测试** | **L0 负责人** |
| **状态一致性** | **状态覆盖或冲突** | **版本向量 + 事务支持 (CAS)** | **L4 负责人** |
| **L4 状态分类模糊** | **状态泄漏或性能瓶颈** | **在 Layer-4-Spec-v2.2 中增加状态分类表** | **L4 负责人** |
| **Layer Profile 验证遗漏** | **权限绕过风险** | **编译期 + 运行期双重验证 + 审计日志** | **安全负责人** |
| **C++ ABI 兼容性破坏** | **第三方集成失败** | **符号版本控制 + ABI 兼容性测试** | **L0 负责人** |

---

## 16. 合规性映射（v2.2 新增）

| 合规要求 | Security-Spec 章节 | 验证方式 |
| :--- | :--- | :--- |
| GDPR 数据加密 | Section 4.1 状态分类与加密 | 渗透测试 + 代码审计 |
| SOC2 访问控制 | Section 3 Layer Profile 模型 | 单元测试 + 集成测试 |
| ISO27001 密钥管理 | Section 2.2.3 LLM 适配器安全 | 密钥轮换测试 |
| 等保 2.0 审计日志 | Section 9 可审计性 | 日志完整性验证 |

---

## 17. 附录：错误码

| 错误码 | 含义 | 处理建议 |
| :--- | :--- | :--- |
| ERR_COMPILE | 编译错误 | 检查 DSL 语法 |
| ERR_EXECUTION | 执行错误 | 检查节点配置 |
| ERR_BUDGET_EXCEEDED | 预算超限 | 优化 DAG 或减少操作 |
| ERR_CONSTRAINT_VIOLATION | 约束违反 | 检查 `output_constraints` |
| ERR_NAMESPACE_VIOLATION | 命名空间违规 | 禁止写入 `/lib/**` |
| ERR_CIRCULAR_DEPENDENCY | 循环依赖 | 检查调用链 Token |
| ERR_SIGNATURE_MISSING | 签名缺失 | `/lib/**` 必须声明签名 |
| ERR_CTX_MERGE_CONFLICT | 上下文合并冲突 | 检查 fork/join 策略 |
| ERR_RECURSION_DEPTH_EXCEEDED | 递归深度超限 | 检查 max_depth 限制 |
| ERR_RISK_THRESHOLD_EXCEEDED | 风险阈值超限 | 需要人工确认 |
| ERR_HUMAN_APPROVAL_REJECTED | 人工确认被拒绝 | 用户拒绝执行 |
| ERR_ADAPTIVE_BUDGET_LIMIT | 自适应预算超限 | 检查置信度与预算比例 |
| **ERR_PROFILE_VIOLATION** | **Layer Profile 违规** | **检查 Profile 声明与工具兼容性** |
| **ERR_PERMISSION_DENIED** | **运行期权限拒绝** | **检查 StateToolAdapter 验证** |
| **ERR_LLM_CONFIG_INVALID** | **LLM 配置无效** | **检查模型/提供商白名单** |
| **ERR_PATH_VIOLATION** | **状态路径违规** | **检查 state.read/write 路径限制** |
| **ERR_STATE_TOOL_ERROR** | **状态工具错误** | **检查 L4 状态管理器接口** |
| **ERR_L0_REVERSE_DEPENDENCY** | **L0 反向依赖 L4** | **检查 L0 代码无 L4 服务实例化** |

---

## 18. 总结

AgenticOS 安全规范 v2.2 是 AgenticOS 全栈安全体系的核心，提供：

1. **Layer Profile 安全模型：** Cognitive/Thinking/Workflow 三层权限 Profile，与四层防护模型深度集成
2. **状态管理工具化安全：** `state.read`/`state.write` 工具封装 L4 状态，支持编译时权限检查与端侧加密
3. **DSL-Centric 安全约束：** L0 纯函数约束，禁止反向依赖 L4，置信度参数显式传入
4. **智能化演进安全：** 自适应预算、动态沙箱、风险感知人机协作的安全边界，支持 Fallback 机制
5. **全链路可审计性：** 100% 操作日志、Trace 持久化、契约存证，支持 session_id 贯穿全链路
6. **测试覆盖率要求：** 安全关键代码覆盖率 >90%，纳入 CI/CD 流程
7. **合规性映射：** 支持 GDPR、SOC2、ISO27001、等保 2.0 等合规要求

通过严格的接口契约与安全约束，确保 AgenticOS v2.2 在 DSL-Centric 架构下的安全性、隐私性与可演进性，为智能体生态奠定坚实基础。

**核心批准条件：**
1. **Layer Profile 验证边界明确化：** 在 Section 2.1 中增加验证责任矩阵，明确编译期 vs 运行期验证责任
2. **状态管理加密流程详细化：** 在 Section 4.1 中增加加密流程图，明确 L4 解密、L1 密文存储、L2 无权访问密钥的边界
3. **L0 纯函数约束强化：** 在 Section 1.4 中增加 L0 纯函数约束详细说明，禁止全局变量、单例模式、间接 L4 依赖
4. **LLM 密钥管理规范化：** 在 Section 2.2.3 中增加 API Key 加密存储、解密时机、使用后清除的详细流程
5. **智能化 Fallback 机制：** 在 Section 8.4 中增加智能化特性降级策略，确保服务可用性
6. **测试覆盖率要求：** 在 Section 12.3 中增加安全关键代码覆盖率指标 (>90%)，作为发布准入门槛
7. **密钥轮换机制：** 在 Section 7.3 中增加密钥轮换流程说明
8. **CI/CD 集成：** 在 Section 14 中增加覆盖率检测的 CI/CD 配置示例
9. **合规性映射：** 新增 Section 16，映射安全规范与合规性要求

---

**文档版本：** v2.2.0  
**发布日期：** 2026-02-25  
**版权所有：** AgenticOS 架构委员会  
**许可：** CC BY-SA 4.0 + 专利授权许可