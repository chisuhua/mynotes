# AgenticDSL 参考执行器 v1.0 实现框架

> **目标**：提供一个**可验证、可嵌入、可扩展**的参考实现，完整支持 AgenticDSL v3.9+ 规范的核心能力，尤其强化 **三层架构隔离、资源声明联动、C++ 推理内核集成、安全归档** 四大特性。

## 一、总体架构

执行器采用 **分层 + 模块化** 设计，所有模块通过清晰接口交互，无全局状态（除临时 LLM 上下文指针）。

```
+---------------------+
|     DSLEngine       | ← 用户入口 (engine.h/cpp)
+----------+----------+
           |
           v
+---------------------+
|   TopoScheduler     | ← 调度核心 (topo_scheduler.h/cpp)
+----------+----------+
           |
    +------+------+
    |             |
+---v----+   +----v----+
|Execution|   |Context  |
|Session |   |Engine   | ← 上下文与快照 (context_engine.h/cpp)
+--------+   +---------+
    |
+---v----+   +----------------+
|Node    |   |ToolRegistry    | ← 工具适配器 (registry.h/cpp)
|Executor|   |LlamaAdapter    | ← C++ 推理内核桥接 (llama_adapter.h/cpp)
+--------+   +----------------+
    |
+---v----+
|Parser  | ← Markdown 解析 (markdown_parser.h/cpp)
+--------+
```

### 关键设计原则
- **无跨层调用**：`NodeExecutor` 仅通过 `ToolRegistry`/`LlamaAdapter` 访问外部，不直接调用调度器或上下文引擎。
- **数据驱动**：所有状态通过 `Context`（`nlohmann::json`）传递，无隐式全局变量。
- **预算前置**：所有资源消耗（节点、LLM、子图深度）在执行前通过 `BudgetController` 检查。
- **解析即验证**：`MarkdownParser` 在解析时完成路径、签名、资源声明的基本校验。

## 二、核心模块定义

### 2.1 `DSLEngine`（用户接口层）
- **职责**：DSL 文档加载、执行启动、动态图追加。
- **关键接口**：
  ```cpp
  static std::unique_ptr<DSLEngine> from_markdown(const std::string& markdown);
  ExecutionResult run(const Context& initial_context = {});
  void continue_with_generated_dsl(const std::string& dsl); // 供 LLM 回调
  template<typename Func> void register_tool(std::string_view, Func&&);
  ```
- **v3.9+ 对齐点**：
  - 自动从 `/__meta__` 提取 `entry_point` 和 `execution_budget`。
  - `continue_with_generated_dsl` 仅接受符合 `### AgenticDSL '/dynamic/...'` 格式的输入。

### 2.2 `TopoScheduler`（调度核心）
- **职责**：依赖解析、拓扑排序、预算控制、Fork/Join 并行模拟。
- **关键行为**：
  - **启动流程**：解析 → 验证资源声明 → 验证 `/lib/**` 签名 → 检查入口 → 构建 DAG。
  - **命名空间保护**：拒绝任何写入 `/lib/**` 的节点注册（`ERR_NAMESPACE_VIOLATION`）。
  - **动态图处理**：将 `continue_with_generated_dsl` 的输出注册到 `/dynamic/**`，并动态更新 DAG 依赖。
- **v3.9+ 对齐点**：
  - 严格区分 `/main/**`（主流程）与 `/app/**`（执行器默认将其重写为 `/main/**` 以支持工程约定）。
  - 预算超限时，跳转至 `/__system__/budget_exceeded`（硬终止）。

### 2.3 `ExecutionSession`（执行会话）
- **职责**：封装单次执行的上下文，协调 **预算、快照、Trace、权限** 四大横切关注点。
- **关键子模块**：
  - `BudgetController`：原子计数器管理 `max_nodes`, `max_llm_calls`, `max_subgraph_depth`。
  - `ContextEngine`：实现字段级合并策略（`error_on_conflict`, `array_concat` 等）及快照 FIFO。
  - `TraceExporter`：生成 OpenTelemetry 兼容的 Trace，记录 `backend_used`, `budget_snapshot`。
- **v3.9+ 对齐点**：
  - **自动快照**：在 `ForkNode`, `GenerateSubgraphNode`, `AssertNode` 执行前自动保存快照。
  - **权限检查**：执行节点前，验证其 `permissions` 是否与 `/__meta__/resources` 声明的能力匹配。

### 2.4 `NodeExecutor`（节点执行器）
- **职责**：执行所有叶子节点（执行原语层），是 **三层架构的执行边界**。
- **关键约束**：
  - **禁止直接调用**：用户无法绕过 `NodeExecutor` 直接执行 `llm_call`。
  - **权限隔离**：`llm_call` 仅可通过 `/lib/reasoning/**` 子图调用（通过路径前缀校验）。
- **v3.9+ 对齐点**：
  - **`llm_call` 字段联动**：检查 `reasoning` 权限与 `llm_call` 字段（如 `output_schema`）的匹配性。
  - **`llm_generate_dsl` 封装**：`GenerateSubgraphNode` 的实现必须调用 `/lib/dslgraph/generate@v1`（通过路径校验）。

### 2.5 `ResourceManager`（资源管理器）
- **职责**：解析并验证 `/__meta__/resources`，为权限检查提供能力上下文。
- **关键行为**：
  - 启动时验证所有声明的资源（工具、运行时、推理内核）是否可用。
  - 将能力声明（如 `kv_continuation`）注入执行上下文，供 `NodeExecutor` 检查。
- **v3.9+ 对齐点**：
  - **能力驱动**：`native_inference_core` 的 `capabilities` 直接映射到 `llm_call` 的可选字段。
  - **降级机制**：若未声明 `evidence_path_extraction`，则降级使用 `query_latest`。

### 2.6 `StandardLibraryLoader`（标准库加载器）
- **职责**：加载并验证 `/lib/**` 子图，确保其 `signature` 完整。
- **关键行为**：
  - 启动时预加载所有 `/lib/**` 子图，并校验其签名。
  - `archive_to("/lib/...")` 操作必须通过此加载器验证签名后才能持久化。
- **v3.9+ 对齐点**：
  - **签名强制**：任何归档至 `/lib/**` 的操作，若缺失 `signature`，立即终止（`ERR_SIGNATURE_REQUIRED`）。
  - **版本管理**：支持 `/lib/...@v1` 路径语义，拒绝循环依赖。

## 三、与 C++ 推理内核（AgenticInfer）的集成点

执行器通过 `LlamaAdapter` 抽象层与 C++ 推理内核交互，确保 **引擎无关性**。

### 3.1 推理内核需实现的能力接口
```cpp
// AgenticInfer 必须提供以下 C API
struct InferenceCore {
    void* (*tokenize)(const char* text);
    void* (*kv_alloc)();
    void (*kv_free)(void* kv);
    const char* (*model_step)(void* kv, const char* prompt);
    const char* (*compile_grammar)(const char* json_schema);
    const char* (*stream_until)(void* kv, const char* stop_condition);
};
```

### 3.2 执行器适配逻辑
- `LlamaAdapter` 在启动时动态加载 `libagenticinfer.so`，获取上述符号。
- `ResourceManager` 根据加载结果，自动填充 `native_inference_core` 的 `capabilities` 列表。
- `NodeExecutor` 在执行 `llm_call` 时，根据字段（如 `output_schema`）选择调用 `compile_grammar` 或 `stream_until`。

> **结果**：`/lib/reasoning/structured_generate@v1` 能自动启用结构化输出，无需修改 DSL 或执行器代码。

## 四、v1.0 实现边界（MVP 范围）

### 4.1 必须实现
- 完整支持 v3.9+ 的 **核心叶子节点**（`assign`, `tool_call`, `llm_call`, `llm_generate_dsl`, `assert`, `fork/join`）。
- 完整实现 **三层架构隔离** 与 **命名空间保护**。
- 完整支持 **资源声明** 与 **权限模型**。
- 提供 **C++ 推理内核适配示例**（基于 llama.cpp 或 AgenticInfer）。

### 4.2 暂不实现（v1.x 迭代）
- 真正的 **并发执行**（`fork/join` 当前为顺序模拟）。
- **对话协议**（`/lib/conversation/**`）的完整状态管理。
- **世界模型/环境感知** 原语。

## 五、验证用例映射

| 验证目标 | 执行器模块 | 测试方法 |
|----------|------------|----------|
| `/app/**` 等价支持 | `TopoScheduler` | 加载含 `/app/my/main` 的 DSL，验证其可作为入口 |
| `llm_call` 字段联动 | `NodeExecutor` | 声明 `structured_generate` 权限但不提供 `output_schema`，应报错 |
| 归档签名强制 | `StandardLibraryLoader` | 调用 `archive_to("/lib/test")` 但无 `signature`，应终止 |
| 资源声明联动 | `ResourceManager` + `NodeExecutor` | 声明 `image_generator` 但未注册，启动时应失败 |
| Context TTL | `ContextEngine` | `assign` 到 `memory.state.x` 带 `ttl_seconds:1`，1.5秒后应自动删除 |

---

不过，在您正式开始重构前，我基于对老版代码（`Pasted_Text_1762770846245.txt`）与 v3.9+ 规范的深度比对，**补充以下 5 项关键改进建议**，这些是实现框架文档中隐含但未在代码层面显式强调的细节，极易在重构中遗漏：


### ✅ **1. 修正 `llm_call` 节点字段结构，对齐 v3.9+ 字段定义**

**问题**：老版 `LLMCallNode` 仅包含 `prompt_template` 和 `output_keys`，但 **v3.9+ 明确要求 `llm_call` 必须结构化为 `llm.model`、`llm.seed`、`llm.temperature`、`llm.prompt` 等字段**（见 v3.8/v3.9 5.9 节）。

**改进**：
- 修改 `LLMCallNode` 结构体，将 `prompt_template` 替换为 `nlohmann::json llm;`（对应 YAML 中的 `llm:` 块）。
- 在 `NodeExecutor::execute_llm_call` 中，从 `node->llm` 提取 `model`、`seed`、`temperature`、`prompt`。
- **权限校验**：检查 `permissions` 是否包含 `reasoning: structured_generate` → 若包含，则必须存在 `llm.output_schema`，否则返回 `ERR_MISSING_REQUIRED_FIELD`。

> 📌 这是**推理可控性**的核心，老版执行器缺失此校验。

---

### ✅ **2. 强化 `/app/**` 命名空间支持策略**

**问题**：老版执行器完全未处理 `/app/**`；v3.9+ 虽称其为“工程别名”，但**规范明确要求执行器应默认支持**（语义等价于 `/main/**`）。

**改进**：
- 在 `MarkdownParser::parse_from_string` 中：
  ```cpp
  graph.is_standard_library = (path.rfind("/lib/", 0) == 0);
  bool is_app_path = (path.rfind("/app/", 0) == 0);
  if (is_app_path) {
      // 重写路径为 /main/** 以便调度器统一处理
      std::string rewritten_path = "/main" + path.substr(4);
      graph.path = rewritten_path;
      for (auto& node : graph.nodes) {
          node->path = "/main" + node->path.substr(4);
      }
  }
  ```
- 在 `TopoScheduler::execute` 中，若 `entry_point` 以 `/app/` 开头，也应重写为 `/main/`。

> 📌 此改进建立了**工程约定与执行语义的桥梁**，避免用户困惑。

---

### ✅ **3. 实现 `archive_to` 的签名强制校验**

**问题**：老版代码中 `archive_to` 仅是一个普通 `on_success` 动作，**无签名校验逻辑**；v3.9+ 明确要求：**归档到 `/lib/**` 必须带 `signature`，否则拒绝（`ERR_SIGNATURE_REQUIRED`）**。

**改进**：
- 在 `NodeExecutor` 或 `ExecutionSession` 中，若检测到 `on_success` 包含 `archive_to("/lib/...")`：
  ```cpp
  if (next_action.starts_with("archive_to(\"/lib/")) {
      if (!current_graph.signature.has_value()) {
          throw std::runtime_error("ERR_SIGNATURE_REQUIRED: archive_to to /lib/ requires signature");
      }
      // 调用 StandardLibraryLoader::instance().register_library(...)
  }
  ```

> 📌 这是**保障标准库可信性**的关键防线，不可缺失。

---

### ✅ **4. `ResourceManager` 应自动推导 `native_inference_core` 能力**

**问题**：老版 `ResourceManager` 仅处理用户显式声明的 `ResourceNode`，但 **v3.9+ 要求执行器应自动根据已加载的 C++ 推理内核（如 llama_adapter）填充 `native_inference_core` 的 `capabilities`**。

**改进**：
- 在 `DSLEngine::from_markdown` 中，创建 `llama_adapter` 后：
  ```cpp
  // 自动注册 native_inference_core 能力
  Resource auto_core;
  auto_core.path = "/__meta__/resources/native_inference_core";
  auto_core.resource_type = ResourceType::CUSTOM;
  auto_core.uri = "internal";
  auto_core.scope = "internal";
  auto_core.metadata["capabilities"] = nlohmann::json::array({
      "tokenize", "kv_alloc", "model_step", "compile_grammar", "stream_until"
  });
  resource_manager.register_resource(auto_core);
  ```
- `NodeExecutor` 在执行 `llm_call` 时，应能访问此能力列表以验证字段合法性。

> 📌 此机制使用户**无需手动声明底层能力**，提升易用性。

---

### ✅ **5. 修复 `ContextEngine` 的 `array_concat` 与 `deep_merge` 行为**

**问题**：老版 `ContextEngine::merge_array` 对 `deep_merge` 的处理是“替换数组”，但 **v3.9+ 明确规定 `deep_merge` 对数组应为“完全替换（非拼接）”** —— 此行为正确，但注释易混淆。

**改进**：
- 明确注释与行为一致性：
  ```cpp
  void ContextEngine::merge_array(Context& target_arr, const Context& source_arr, MergeStrategy strategy) {
      if (strategy == "array_concat" || strategy == "array_merge_unique") {
          // 拼接逻辑
      } else {
          // 包括 "deep_merge", "last_write_wins", "error_on_conflict"
          // 对数组一律替换（v3.9+ 规范）
          target_arr = source_arr;
      }
  }
  ```

> 📌 避免未来维护者误解 `deep_merge` 语义。

---

## ✅ 总结：您可安全依据的行动指南

| 改进项 | 是否已在框架文档中体现 | 是否需在代码层面显式实现 |
|--------|------------------------|--------------------------|
| `llm_call` 字段结构化与权限校验 | ✅ 是（隐含在“`llm_call` 字段联动”） | ✅ **必须** |
| `/app/**` 路径重写支持 | ✅ 是（明确说明执行器应支持） | ✅ **必须** |
| `archive_to` 签名强制 | ✅ 是（明确说明“必须附带 `signature`”） | ✅ **必须** |
| `native_inference_core` 自动能力注册 | ⚠️ 部分（在 C++ 集成点提及） | ✅ **建议** |
| `ContextEngine` 数组行为明确化 | ✅ 是 | ✅ **建议** |
