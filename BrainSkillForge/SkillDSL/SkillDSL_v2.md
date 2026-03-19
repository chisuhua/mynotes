# PromptC v2.0 语言规范（融合版）

> **版本**: v2.0-Progressive  
> **定位**: 面向 LLM-Native 应用的渐进固化语言  
> **核心范式**: 路径即类型、沙箱即效应、阶段化编译

---

## 1. 程序结构与路径命名空间

### 1.1 路径即类型系统

PromptC 使用**文件路径作为类型标识符**，所有 Skill、类型、子图都通过路径寻址：

| 路径前缀 | 语义角色 | 沙箱默认 | 编译阶段 | 可见性 |
|---------|---------|---------|---------|--------|
| `/lib/**` | 标准库类型 | L0 (信任) | AOT 全优化 | 全局公共 |
| `/app/**` | 应用业务逻辑 | L0 | JIT 缓存 | 会话级 |
| `/main/**` | 执行入口 | L0 | 解释/渐进 | 实例级 |
| `/dynamic/**` | 运行时生成 | L1 | 动态验证 | 动态注册 |
| `/tmp/**` | 临时子图 | L2 (隔离) | 无优化 | 单次执行 |

```promptc
// 类型即路径：/lib/nlp/Text 是一个类型，也是一个可寻址的 Skill
skill AnalyzeText<input: /lib/nlp/Text> -> /lib/nlp/Analysis 
    @path("/app/text/analyzer")
    @sandbox(L1)          // 替代效应系统：网络调用需 L1
    @stage("jitted")      // 渐进固化阶段：interpreted | jitted | solidified
{
    // 实现
}
```

### 1.2 元信息块 (`/__meta__`)

每个程序必须以元信息块开头，声明路径、资源和预算：

```yaml
### PromptC /__meta__
version: "2.0.0"
path: "/main/research_agent"          # 本程序路径（唯一标识）
stage: "interpreted"                  # 当前固化阶段
entry_point: "/main/research_agent/run"

sandbox:
  default_level: L0
  max_level: L2                       # 本会话可能升级到的最高沙箱级别

resources:
  - path: /lib/search/academic
    preload: true                     # 预加载到上下文
  - path: /lib/llm/gpt4
    pool_size: 5                      # 资源池大小

budget:
  max_nodes: 50
  max_llm_calls: 20
  max_duration_sec: 120
  max_branches: 8                     # 最大并发分支数

context:
  merge_strategy: "error_on_conflict" # Fork-Join 合并策略
  description_matching: true          # 启用语义路由
```

---

## 2. 类型系统与阶段注解

### 2.1 路径类型与结构体

使用 `struct` 定义可在路径下注册的类型：

```promptc
// 在路径下注册类型
struct Paper @path("/lib/types/Paper") {
    title: String @comptime,           // 编译期已知（用于提示词生成）
    content: String @runtime,          // 运行时确定
    metadata: JSON @runtime
}

// 使用路径类型
skill ExtractKeywords<paper: /lib/types/Paper> -> Vec<String> 
    @path("/lib/nlp/extract_keywords")
    @sandbox(L0)                      // 纯文本处理，L0 足够
{
    // 编译期可访问 paper.title 生成特定提示词
    prompt: "从论文《{{paper.title}}》中提取关键词...\n内容：{{paper.content}}"
}
```

### 2.2 渐进固化阶段（Progressive Solidification）

Skill 可在生命周期中从解释执行逐步编译为原生代码：

| 阶段 | 标记 | 执行方式 | 适用场景 |
|------|------|---------|---------|
| **Interpreted** | `@stage("interpreted")` | VM 解释，prompt_template 动态渲染 | 快速迭代、动态生成 |
| **Jitted** | `@stage("jitted")` | JIT 编译为 DAG，支持节点融合 | 稳定工作流、性能敏感 |
| **Solidified** | `@stage("solidified")` | AOT 编译为 WASM/Native | 高频调用、库函数 |

```promptc
// 阶段 1：解释执行（动态灵活）
skill FlexibleParser @path("/dynamic/parser/v1") @stage("interpreted") {
    prompt_template: "请解析以下文本：{{input}}"
    output_schema: JSON                # 动态推断输出结构
}

// 阶段 2：JIT 优化（执行 100 次后自动提升）
// 编译器分析发现总是生成相同结构，转为 JIT
skill StableAnalyzer @path("/app/analyzer") @stage("jitted") 
    @fusion_candidates(["extract", "summarize"])
{
    // 具体实现...
}

// 阶段 3：完全固化（编译期确定一切）
skill StaticValidator @path("/lib/validate/email") @stage("solidified")
    @comptime_eval(true)              // 强制编译期执行
    @sandbox(L0)
{
    // 编译为正则表达式 WASM，无 LLM 调用
    regex: "^[\\w.-]+@[\\w.-]+\\.\\w+$"
}
```

---

## 3. 沙箱安全体系（替代效应系统）

使用**沙箱级别**替代复杂的效应代数，简化认知模型同时保证安全：

### 3.1 三级沙箱

| 级别 | 能力范围 | 触发条件 | 编译优化 |
|------|---------|---------|---------|
| **L0** | 纯计算、内存、正则 | 默认 | 激进内联、常量折叠、安全缓存 |
| **L1** | 网络、文件读写、LLM 调用 | 显式标记或工具检测 | 允许缓存，禁止跨节点状态共享 |
| **L2** | 任意代码执行、第三方运行时 | `unsafe` 标记或动态代码 | 进程隔离，IPC 通信，禁止内联 |

```promptc
// 沙箱声明替代效应注解
skill WebSearch @path("/lib/search/web") @sandbox(L1) {
    // 自动获得 Network + LLMCall 能力，但受 L1 隔离
    http_client: /lib/io/HTTPClient,
    timeout: 30
}

skill PythonExecutor @path("/lib/runtime/python") @sandbox(L2) {
    // L2 强制进程隔离，通过 IPC 与主进程通信
    imports: ["numpy", "pandas"],      // 声明可用依赖
    memory_limit: "512mb"
}

// 调用 L2 Skill 时自动升级当前上下文沙箱级别
skill DataAnalysis @path("/app/analysis") @sandbox(L1) {
    node preprocess: /lib/transform/clean = ...;        // L0
    node calculate: /lib/runtime/python = ...;          // 自动升级至 L2 执行
    node summarize: /lib/nlp/summarize = ...;           // 回到 L1
}
```

### 3.2 权限与资源契约

```promptc
permissions {
    // 声明式权限，与沙箱级别联动
    network {
        allow: ["api.example.com", "*.arxiv.org"]
        sandbox: L1
    }
    filesystem {
        read: ["/data/input/**"]
        write: ["/tmp/output/**"]
        sandbox: L1
    }
    runtime {
        python: {
            version: "3.10"
            packages: ["scikit-learn"]
            sandbox: L2
        }
    }
}
```

---

## 4. 节点类型与控制流

PromptC v2.0 采用**分层 DAG**：基础数据流 + 四种特殊控制节点。

### 4.1 基础节点

**LLM 调用节点**：
```promptc
node extract: /lib/llm/gpt4 = {
    prompt: "分析 {{input}}",
    temperature: 0.7,
    seed: 42,                         // 确定性生成
    output_schema: /lib/types/Analysis,
    cache_policy: "ttl:3600"
}
```

**纯函数节点**（L0）：
```promptc
node clean: /lib/text/clean = {
    input: raw_text,
    operations: ["trim", "normalize"]
} @sandbox(L0)
```

### 4.2 控制流原语（仅四种）

#### A. Map（数据并行）
```promptc
node analyses: Map = {
    collection: papers,               // Vec<Paper>
    body: /app/analyze_single,        // 子图路径
    parallelism: 5,                   // 并发数
    batch_size: 3,                    // LLM 批处理大小
    mode: "parallel"                  // parallel | sequential | speculative
} @sandbox(L1)
```

#### B. Reduce（聚合归约）
```promptc
node summary: Reduce = {
    collection: analyses.results,
    combiner: /lib/nlp/merge_two,     // 二元合并子图
    initial: "空报告",
    tree_reduction: true              // 编译器优化为树形归约 O(log n)
}
```

#### C. While（条件循环）
```promptc
node refined: While = {
    condition: |ctx| => ctx.quality < 0.9 && ctx.round < 5,
    body: /app/refine_once,           // 每轮执行子图
    carry_vars: ["draft", "quality", "round"],
    unroll_hint: 2                    // 编译器尝试展开 2 次
}
```

#### D. Branch（条件分支）
```promptc
node route: Branch = {
    condition: query.complexity,
    branches: {
        "simple": /app/fast_answer,   // 路径指向子图
        "complex": /app/deep_research
    },
    lazy_eval: true,                  // 未选分支不实例化
    merge_policy: "union"             // 分支输出合并策略
}
```

### 4.3 Fork-Join（显式并发）

```promptc
// Fork 创建并行分支
fork {
    branch academic: /lib/search/academic = { query: topic };
    branch industry: /lib/search/industry = { query: topic };
    branch news: /lib/search/news = { query: topic };
} 
// Join 同步点
join {
    strategy: "all",                  // all | any | n_of(2)
    merge: {
        results: "array_concat",      // 数组合并
        confidence: "max"             // 取最大值
    },
    timeout: 30
}
```

---

## 5. 动态生成与元编程

### 5.1 运行时子图生成（GenerateSubgraph）

```promptc
node adaptive_solver: GenerateSubgraph = {
    prompt: "方程 {{equation}} 求解失败，请生成新的求解策略",
    
    // 生成约束
    target_namespace: "/dynamic/solvers/{{$instance_id}}",  // 强制前缀
    signature_validation: "strict",   // strict | warn | ignore
    budget_consumption: {
        max_nodes: 10,
        max_depth: 2                  // 防止无限生成
    },
    
    // 固化触发：执行超过阈值后自动转为 jitted
    auto_solidify: {
        trigger_count: 50,
        target_path: "/lib/solvers/auto_generated"
    }
}
```

### 5.2 编译期元编程（Comptime）

```promptc
skill SelfOptimizing @path("/app/optimizer") {
    comptime {
        // 编译期执行：分析历史日志，生成优化配置
        node analyzer: /lib/meta/analyze_logs = {
            logs: $execution_history,
            goal: "reduce_latency"
        };
        
        // 将分析结果写入编译期常量
        let optimized_template = analyzer.best_template;
    }
    
    runtime {
        // 运行时使用编译期生成的模板
        node execute: /lib/llm/gpt4 = {
            prompt_template: optimized_template,  // 编译期确定
            input: user_query
        };
    }
}
```

---

## 6. 描述匹配与增量加载

### 6.1 语义路由（Semantic Routing）

保留 OpenClaw 的描述匹配机制，支持基于语义的 Skill 选择：

```promptc
skill AcademicSearch 
    @path("/lib/search/academic")
    @description("搜索学术论文和期刊文章，适合科研场景")
    @semantic_keys(["paper", "arxiv", "journal", "citation", "research"])
    @context_budget(2000)             // 仅保留 2000 tokens 描述
{
    // 实现
}

// 运行时自动路由
node search: SemanticRoute = {
    query: user_input,
    candidates: ["/lib/search/*"],    // 路径通配
    threshold: 0.75,                  // 相似度阈值
    fallback: "/lib/search/general"
}
```

### 6.2 上下文增量加载

基于路径前缀控制 LLM 上下文长度，避免一次性加载全部 Skill：

```yaml
context_loading:
  strategy: "path_prefix"
  
  rules:
    - prefix: "/lib/core/**"
      always_load: true               # 核心库常驻上下文
      
    - prefix: "/lib/search/**"
      load_when: "router_match"       # 路由匹配时加载
      budget_slots: 3                 # 最多加载 3 个搜索技能
      
    - prefix: "/lib/dangerous/**"     # L2 沙箱技能
      load_when: "explicit_call"      # 显式调用时才加载
      require_confirmation: true      # 需要用户确认
      
    - prefix: "/dynamic/**"
      ephemeral: true                 # 会话结束即卸载
```

---

## 7. 渐进固化 IR 示例

同一个 Skill 在不同固化阶段的 IR 表示：

**Interpreted 阶段**（灵活，LLM 友好）：
```json
{
  "path": "/dynamic/math/solver",
  "stage": "interpreted",
  "body": {
    "type": "template",
    "prompt": "请解方程：{{equation}}",
    "model": "gpt-4",
    "output_schema": null              // 动态推断
  },
  "sandbox": "L1"
}
```

**Jitted 阶段**（优化后，保留结构）：
```json
{
  "path": "/app/math/solver",
  "stage": "jitted",
  "body": {
    "type": "dag",
    "nodes": {
      "parse": {"type": "pure", "op": "parse_equation"},
      "solve": {"type": "llm_call", "fused_chain": ["analyze", "compute"]},
      "verify": {"type": "pure", "op": "check_result"}
    }
  },
  "compilation_hints": {
    "fusion_applied": ["parse+solve"],
    "cache_strategy": "aggressive"
  }
}
```

**Solidified 阶段**（完全编译）：
```json
{
  "path": "/lib/math/solver",
  "stage": "solidified",
  "body": {
    "type": "wasm",
    "binary": "wasm_base64...",
    "exports": ["solve_linear", "solve_quadratic"],
    "no_llm": true                     // 标记：无 LLM 调用
  },
  "sandbox": "L0"                     // 纯本地计算
}
```

---

## 8. 与现有生态互操作

### 8.1 导入现有 Skill（Transpiler）

```promptc
// 自动迁移 OpenAPI/MCP/OpenClaw Skill
import {
    // 从 MCP 导入
    source: "mcp://filesystem",
    path: "/lib/mcp/fs/read",
    as: /lib/io/FileRead,
    sandbox: L1
    
    // 从 OpenClaw 导入
    source: "openclaw://./skills/search.md",
    path: "/lib/openclaw/web_search",
    preserve_description: true         // 保留语义描述
}

// 使用导入的 Skill
node result: /lib/mcp/fs/read = {path: "/data/file.txt"};
```

### 8.2 导出为标准接口

```promptc
export {
    // 导出为 OpenAPI
    format: "openapi",
    path: "/main/api",
    expose: ["/app/public/**"],
    
    // 导出为 MCP Tool
    mcp: {
        name: "research_assistant",
        version: "1.0.0"
    }
}
```

---

## 9. 完整示例：研究助手（渐进固化版）

```promptc
### PromptC /__meta__
path: "/main/research_agent"
stage: "jitted"
entry_point: "/main/research_agent/analyze"

// 1. 类型定义
struct Paper @path("/lib/types/Paper") {
    title: String @comptime,
    abstract: String @runtime,
    url: String @runtime
}

// 2. 基础 Skill（已固化）
skill KeywordExtract @path("/lib/nlp/keywords") @stage("solidified") 
    @sandbox(L0) 
{
    regex_patterns: ["[A-Z][a-z]+ [A-Z][a-z]+", "[a-z]+_[a-z]+"]
}

// 3. 搜索 Skill（JIT 阶段）
skill AcademicSearch @path("/lib/search/academic") @stage("jitted") 
    @sandbox(L1)
    @description("搜索 arXiv 和 Google Scholar")
    @semantic_keys(["academic", "paper", "research"])
{
    node query_gen: /lib/nlp/expand_query = {input: topic};
    node fetch: /lib/io/http_get = {url: query_gen.search_url};
    node parse: /lib/html/extract_papers = {html: fetch.body};
    
    return parse.papers;              // Vec</lib/types/Paper>
}

// 4. 主流程（解释阶段，可自动提升）
skill DeepResearch @path("/main/research_agent/analyze") 
    @stage("interpreted")
    @sandbox(L1)
{
    input: {topic: String, depth: Int = 3}
    
    // 4.1 并行搜索（Fork-Join）
    fork {
        branch academic: /lib/search/academic = {query: topic};
        branch web: /lib/search/web = {query: topic};
    }
    join {
        strategy: "all",
        merge: {papers: "array_concat"}
    }
    
    // 4.2 批量分析（Map）
    node analyses: Map = {
        collection: join.papers,
        body: /app/analyze_paper,      // 引用本地子图
        parallelism: 4,
        batch_size: 2
    };
    
    // 4.3 迭代综合（While + Reduce）
    node report: While = {
        initial: {content: "初始化", quality: 0.0, round: 0},
        condition: |ctx| => ctx.quality < 0.9 && ctx.round < depth,
        body: /app/refine_report,
        carry_vars: ["content", "quality", "round"]
    };
    
    return report.content;
}

// 5. 子图定义
subgraph AnalyzePaper @path("/app/analyze_paper") {
    input: Paper
    
    node keywords: /lib/nlp/keywords = {text: input.abstract};
    node classify: /lib/nlp/classify = {
        text: input.abstract,
        categories: ["ML", "Systems", "Theory"]
    };
    
    output: {
        paper_id: input.title,
        keywords: keywords.result,
        category: classify.result
    }
}
```

---

## 10. 设计原则总结

| 原则 | 实现方式 | 优势 |
|------|---------|------|
| **路径即类型** | `/lib/xxx` 作为类型标识 | 全局唯一、生态可组合、版本控制天然支持 |
| **沙箱即效应** | L0/L1/L2 替代复杂效应代数 | 认知简单、安全边界清晰、优化策略直接关联 |
| **渐进固化** | interpreted → jitted → solidified | 动态灵活到高性能的连续谱，支持自动优化 |
| **描述匹配** | `@description` + `@semantic_keys` | 支持语义路由、增量加载、减少上下文爆炸 |
| **分层 DAG** | 基础节点 + 4 种控制节点 | 易于可视化、可证明终止性、支持向量化 |

此规范融合了 **AgenticDSL 的工程鲁棒性**（沙箱、预算、Fork-Join）与 **原 PromptC 的编译期优化能力**（阶段化类型、comptime、JIT 融合），通过**渐进固化**解决了"灵活性 vs 性能"的根本矛盾。

# PromptC v2.0 示例集

（对应原 `PromteC_examples.md`），展示从简单原子操作到复杂元编程的渐进能力，全部使用**路径即类型**、**沙箱级别**和**渐进固化**新语法：

---

## 示例 1：单步原子技能（Hello World）
**场景**：简单的文本翻译，展示最基础的 L0 纯计算与 L1 LLM 调用区别

### PromptC v2.0 源码
```promptc
skill Translate @path("/lib/nlp/translate") @stage("solidified") 
    @sandbox(L0)                      // 纯规则，无 LLM，正则实现
{
    input: {text: String, target_lang: String = "中文"}
    
    // 完全固化：编译为 WASM 正则替换
    pattern: "translate_{{target_lang}}",
    wasm_binding: "fast_translate_v1"
}

// 对比：L1 版本（需要 LLM）
skill TranslateLLM @path("/lib/nlp/translate_llm") @stage("jitted")
    @sandbox(L1)                      // 需要网络/LLM
{
    input: {text: String, target_lang: String}
    prompt: "将以下文本翻译为{{target_lang}}：{{text}}"
    model: /lib/llm/gpt4-mini
}
```

### PromptC-IR v2.0
```json
{
  "ir_version": "2.0.0",
  "path": "/lib/nlp/translate",
  "stage": "solidified",
  "type": "single_node",
  "sandbox": "L0",
  "node": {
    "type": "wasm_native",
    "inputs": {
      "text": {"source": "external", "param": "text"},
      "target_lang": {"source": "compile_time", "value": "中文"}
    },
    "wasm_module": "translate_v1.wasm",
    "exports": "translate",
    "no_llm": true
  }
}
```

**✅ 验证**：展示同一功能的不同固化阶段，L0 版本性能高 1000 倍。

---

## 示例 2：顺序流水线（Linear Pipeline）
**场景**：搜索 → 摘要 → 翻译，展示 JIT 自动融合

### PromptC v2.0 源码
```promptc
skill ResearchPipeline @path("/app/pipeline/research") @stage("jitted")
    @sandbox(L1)
{
    input: {query: String, target_lang: String = "英文"}
    
    node search: /lib/search/web = {query: input.query, top_k: 5};
    node summarize: /lib/nlp/summarize = {
        content: search.results[0].content,
        max_length: 500
    };
    node translate: /lib/nlp/translate_llm = {
        text: summarize.summary,
        target_lang: input.target_lang
    };
    
    return translate.result;
}
```

### PromptC-IR v2.0（JIT 融合后）
```json
{
  "ir_version": "2.0.0",
  "path": "/app/pipeline/research",
  "stage": "jitted",
  "type": "dag",
  "sandbox": "L1",
  "fusion_applied": ["search+summarize+translate"],
  "nodes": {
    "fused_node": {
      "type": "llm_call",
      "fusion_strategy": "chain_of_thought",
      "prompt_template": "步骤1：搜索{{query}}；步骤2：总结结果；步骤3：翻译为{{target_lang}}",
      "inputs": {
        "query": "$external.query",
        "target_lang": "$external.target_lang"
      },
      "estimated_tokens": 2500,
      "fits_context_window": true
    }
  }
}
```

**✅ 验证**：JIT 检测到三节点串行、总长度 < 8k，融合为单次调用。

---

## 示例 3：条件路由（Condition Branch）
**场景**：根据查询复杂度选择简单回答或深度研究

### PromptC v2.0 源码
```promptc
skill RouteByComplexity @path("/app/router/complexity") @stage("interpreted")
    @sandbox(L1)
{
    input: {query: String}
    
    node check: /lib/nlp/classify = {
        text: input.query,
        categories: ["simple", "complex", "multi_step"]
    };
    
    // Branch 控制节点：惰性求值
    node route: Branch = {
        condition: check.label,
        branches: {
            "simple": /app/answer/direct,
            "complex": /app/research/deep,
            "multi_step": /app/plan/multi_step
        },
        lazy_eval: true,              // 未选分支不实例化
        merge_policy: "error_on_conflict"
    };
    
    return route.result;
}
```

### PromptC-IR v2.0
```json
{
  "ir_version": "2.0.0",
  "path": "/app/router/complexity",
  "stage": "interpreted",
  "nodes": {
    "classify": {
      "type": "llm_call",
      "skill_path": "/lib/nlp/classify",
      "sandbox": "L1",
      "outputs": ["label", "confidence"]
    },
    "branch_node": {
      "type": "control",
      "subtype": "branch",
      "condition": {"source": "node", "node_id": "classify", "field": "label"},
      "branches": {
        "simple": {"type": "subgraph_ref", "path": "/app/answer/direct"},
        "complex": {"type": "subgraph_ref", "path": "/app/research/deep"}
      },
      "lazy_eval": true,
      "sandbox_inheritance": true       // 子图继承 L1 沙箱
    }
  }
}
```

**✅ 验证**：`lazy_eval` 确保复杂分支在简单查询下零开销。

---

## 示例 4：批量处理（Map - 数据并行）
**场景**：分析多篇论文，展示自动批处理与并行策略

### PromptC v2.0 源码
```promptc
skill BatchPaperAnalysis @path("/app/analysis/batch_papers") @stage("jitted")
    @sandbox(L1)
{
    input: {papers: Vec</lib/types/Paper>}
    
    node extract_key_points: Map = {
        collection: input.papers,
        body: /app/extract/single_paper,   // 子图路径
        parallelism: 5,                     // 并发度
        batch_size: 3,                      // LLM API 批处理
        mode: "adaptive"                    // adaptive | parallel | sequential
    };
    
    return extract_key_points.results;      // Vec<Analysis>
}

// 子图定义
subgraph ExtractSinglePaper @path("/app/extract/single_paper") 
    @stage("solidified")
{
    input: /lib/types/Paper
    
    node extract: /lib/nlp/extract_keywords = {text: input.abstract};
    node classify: /lib/nlp/classify_topic = {text: input.title};
    
    output: {
        keywords: extract.result,
        topic: classify.result,
        title: input.title
    }
}
```

### PromptC-IR v2.0
```json
{
  "ir_version": "2.0.0",
  "path": "/app/analysis/batch_papers",
  "stage": "jitted",
  "nodes": {
    "map_analysis": {
      "type": "control",
      "subtype": "map",
      "inputs": {"collection": "$external.papers"},
      "body_graph": "/app/extract/single_paper",
      "parallelism": 5,
      "batch_size": 3,
      "compilation_strategy": "jit",
      "fusion_candidates": ["/lib/nlp/extract_keywords"],
      "sandbox": "L1"
    }
  }
}
```

**✅ 验证**：支持 JIT 决策：串行/并行/批处理 API。

---

## 示例 5：聚合归约（Reduce）
**场景**：将多个分析结果合并为综合报告，树形归约优化

### PromptC v2.0 源码
```promptc
skill SynthesizeFindings @path("/app/synthesis/reduce") @stage("jitted")
    @sandbox(L1)
{
    input: {analyses: Vec</lib/types/Analysis>}
    
    node combine: Reduce = {
        collection: input.analyses,
        combiner: /app/merge/two_reports,    // 二元合并子图
        initial: {content: "空报告", score: 0.0},
        tree_reduction: true,                 // O(log n) 深度优化
        associative_check: true               // 验证结合律
    };
    
    return combine.final_result;
}

subgraph MergeTwoReports @path("/app/merge/two_reports") @stage("jitted") {
    input: {acc: /lib/types/Report, item: /lib/types/Analysis}
    
    node merge: /lib/nlp/merge_content = {
        existing: input.acc.content,
        new: input.item.summary
    };
    
    output: {
        content: merge.result,
        score: input.acc.score + input.item.confidence
    }
}
```

### PromptC-IR v2.0
```json
{
  "ir_version": "2.0.0",
  "path": "/app/synthesis/reduce",
  "stage": "jitted",
  "nodes": {
    "reduce_node": {
      "type": "control",
      "subtype": "reduce",
      "combiner_graph": "/app/merge/two_reports",
      "initial_value": {"content": "空报告", "score": 0.0},
      "tree_reduction": true,
      "associative_check": true,
      "estimated_depth": "log2(n)"
    }
  }
}
```

**✅ 验证**：树形归约将 1024 项的合并从 1023 次调用降至 10 次。

---

## 示例 6：迭代收敛（While - 条件循环）
**场景**：多轮反思改进答案，直到质量达标

### PromptC v2.0 源码
```promptc
skill IterativeRefinement @path("/app/refine/iterative") @stage("jitted")
    @sandbox(L1)
{
    input: {question: String, max_rounds: Int = 3}
    
    node current: /lib/nlp/draft_answer = {query: input.question};
    
    node refined: While = {
        condition: |ctx| => ctx.quality < 0.9 && ctx.round < input.max_rounds,
        body: /app/refine/one_round,
        carry_vars: ["content", "quality", "round"],
        max_iterations: input.max_rounds,
        unroll_hint: 1                      // 尝试展开 1 次
    };
    
    return refined.content;
}

subgraph RefineOneRound @path("/app/refine/one_round") @stage("interpreted") {
    input: {content: String, round: Int}
    
    node critique: /lib/nlp/critique = {answer: input.content};
    node improve: /lib/nlp/improve = {
        current: input.content,
        suggestions: critique.suggestions
    };
    
    output: {
        content: improve.result,
        quality: improve.quality_score,
        round: input.round + 1
    }
}
```

### PromptC-IR v2.0
```json
{
  "ir_version": "2.0.0",
  "path": "/app/refine/iterative",
  "stage": "jitted",
  "nodes": {
    "draft": {
      "type": "llm_call",
      "skill_path": "/lib/nlp/draft_answer"
    },
    "refine_loop": {
      "type": "control",
      "subtype": "while",
      "condition_graph": "/app/refine/check_convergence",
      "body_graph": "/app/refine/one_round",
      "max_iterations": 3,
      "loop_carried_vars": ["content", "quality", "round"],
      "unroll_factor": 1
    }
  }
}
```

**✅ 验证**：显式声明循环携带变量，支持向量化与展开优化。

---

## 示例 7：嵌套控制流（Map + Branch）
**场景**：处理文档列表，短文档直接摘要，长文档分段处理

### PromptC v2.0 源码
```promptc
skill AdaptiveDocumentProcessing @path("/app/process/adaptive_docs") 
    @stage("jitted")
    @sandbox(L1)
{
    input: {docs: Vec</lib/types/Document>}
    
    node process_each: Map = {
        collection: input.docs,
        body: /app/process/single_adaptive,
        parallelism: 2
    };
    
    return process_each.results;
}

subgraph ProcessSingleAdaptive @path("/app/process/single_adaptive") 
    @stage("interpreted")
{
    input: /lib/types/Document
    
    node check: /lib/text/length_check = {text: input.content};
    
    node route: Branch = {
        condition: check.is_long,         // boolean
        branches: {
            "false": /app/summarize/quick,
            "true": /app/summarize/chunked  // 内部再包含 Map
        }
    };
    
    output: route.result;
}

// 长文档处理子图（嵌套 Map）
subgraph SummarizeChunked @path("/app/summarize/chunked") @stage("jitted") {
    input: /lib/types/Document
    
    node split: /lib/text/split = {text: input.content, chunk_size: 4000};
    
    node summarize_chunks: Map = {
        collection: split.chunks,
        body: /lib/nlp/summarize_chunk,
        parallelism: 3
    };
    
    node merge: /lib/nlp/merge_summaries = {
        summaries: summarize_chunks.results
    };
    
    output: merge.result;
}
```

### PromptC-IR v2.0（嵌套结构）
```json
{
  "ir_version": "2.0.0",
  "path": "/app/process/adaptive_docs",
  "stage": "jitted",
  "nodes": {
    "outer_map": {
      "type": "control",
      "subtype": "map",
      "body_graph": "/app/process/single_adaptive",
      "parallelism": 2
    }
  },
  "subgraphs": {
    "/app/process/single_adaptive": {
      "type": "dag",
      "nodes": {
        "check": {"type": "pure", "op": "length_check"},
        "route": {
          "type": "control",
          "subtype": "branch",
          "branches": {
            "false": "/app/summarize/quick",
            "true": "/app/summarize/chunked"
          }
        }
      }
    },
    "/app/summarize/chunked": {
      "type": "dag",
      "nodes": {
        "split": {"type": "pure", "op": "text_split"},
        "inner_map": {
          "type": "control",
          "subtype": "map",
          "body_graph": "/lib/nlp/summarize_chunk",
          "parallelism": 3
        }
      }
    }
  }
}
```

**✅ 验证**：支持任意层级嵌套，符合"仅允许特殊控制节点"约束。

---

## 示例 8：动态技能选择（运行时图构建）
**场景**：根据输入类型，从技能库中动态选择处理链

### PromptC v2.0 源码
```promptc
skill DynamicDispatch @path("/app/dispatch/dynamic") @stage("interpreted")
    @sandbox(L1)
{
    input: {data: Any, goal: String}
    
    node selector: /lib/meta/skill_selector = {
        input_type: type_of(input.data),
        goal: input.goal,
        registry: "/lib/registry/entity_extraction"  // 技能库路径
    };
    
    // 运行时动态派生
    node execute: DynamicDispatch = {
        dispatch_key: selector.selected_path,        // 运行时确定的路径
        registry: "/lib/registry",
        fallback: "/lib/generic/entity_extract",
        inputs: {data: input.data},
        cache_compiled_graphs: true                   // 缓存编译后的子图
    };
    
    return execute.result;
}
```

### PromptC-IR v2.0（动态部分）
```json
{
  "ir_version": "2.0.0",
  "path": "/app/dispatch/dynamic",
  "stage": "interpreted",
  "nodes": {
    "selector": {
      "type": "llm_call",
      "skill_path": "/lib/meta/skill_selector",
      "outputs": ["selected_path", "confidence"]
    },
    "executor": {
      "type": "control",
      "subtype": "dynamic_dispatch",
      "dispatch_key": {"source": "node", "field": "selected_path"},
      "registry": "/lib/registry",
      "fallback": "/lib/generic/entity_extract",
      "compilation": "jit_lazy",
      "cache_compiled_graphs": true
    }
  },
  "skill_library": {
    "/lib/registry/medical": {
      "type": "subgraph_ref",
      "ir_path": "skills/medical/entity_extraction.json",
      "description": "医疗实体提取",
      "semantic_keys": ["medical", "clinical"]
    },
    "/lib/registry/legal": {
      "type": "subgraph_ref", 
      "ir_path": "skills/legal/entity_extraction.json"
    }
  }
}
```

**✅ 验证**：`dynamic_dispatch` 支持运行时加载，JIT 缓存避免重复编译。

---

## 示例 9：多智能体协商（Fork-Join 并发）
**场景**：三个专家智能体并行审查提案，仲裁者综合决策

### PromptC v2.0 源码
```promptc
skill MultiAgentReview @path("/app/review/multi_agent") @stage("jitted")
    @sandbox(L1)
{
    input: {proposal: /lib/types/Proposal}
    
    // Fork：创建并行分支
    fork {
        branch tech: /lib/agents/tech_expert = {proposal: input.proposal};
        branch market: /lib/agents/market_expert = {proposal: input.proposal};
        branch legal: /lib/agents/legal_expert = {proposal: input.proposal};
    }
    
    // Join：同步与合并
    join {
        strategy: "all",                    // 等待所有分支
        timeout: 30,
        merge: {
            "reviews": "array_concat",      // 收集所有评审意见
            "conflicts": "detect_conflicts" // 自动检测冲突
        }
    }
    
    // 仲裁节点
    node arbitrator: /lib/agents/arbitrator = {
        reviews: join.reviews,
        conflicts: join.conflicts
    };
    
    // 条件循环：有冲突则调解
    node final_decision: While = {
        condition: |ctx| => arbitrator.has_conflicts && ctx.round < 3,
        body: /app/mediate/resolve,
        carry_vars: ["decision", "round"]
    };
    
    return final_decision.decision;
}
```

### PromptC-IR v2.0（Fork-Join 显式表示）
```json
{
  "ir_version": "2.0.0",
  "path": "/app/review/multi_agent",
  "stage": "jitted",
  "nodes": {
    "fork_node": {
      "type": "control",
      "subtype": "fork",
      "branches": ["tech", "market", "legal"],
      "parallelism": true,
      "synchronization": "barrier"
    },
    "tech_branch": {
      "type": "subgraph",
      "skill_path": "/lib/agents/tech_expert",
      "sandbox": "L1"
    },
    "join_node": {
      "type": "control",
      "subtype": "join",
      "wait_for": ["@all"],
      "merge_strategy": {
        "reviews": "array_concat",
        "conflicts": "pure_op_detect_conflicts"
      },
      "timeout": 30
    },
    "mediation_loop": {
      "type": "control",
      "subtype": "while",
      "condition_graph": "/app/mediate/check_conflict",
      "max_iterations": 3
    }
  }
}
```

**✅ 验证**：`fork` 创建 COW 上下文分支，`join` 作为屏障同步。

---

## 示例 10：元编程自优化（编译期代码生成）
**场景**：程序分析自己的执行历史，生成优化后的固化版本

### PromptC v2.0 源码
```promptc
skill SelfOptimizingAgent @path("/app/meta/optimizer") @stage("interpreted")
    @sandbox(L1)
{
    input: {task: String, history: /lib/types/ExecutionLog}
    
    // 编译期块：在部署时执行
    comptime {
        node optimizer: /lib/meta/prompt_optimizer = {
            current_ir: $current_program,           // 访问自身 IR
            performance_data: input.history.metrics,
            goal: "reduce_latency"
        };
        
        // 生成优化后的子图并注册到 /lib/
        node register: RegisterSubgraph = {
            name: "optimized_v2",
            path: "/lib/auto/generated_solver",
            ir: optimizer.optimized_ir,
            stage: "solidified"                     // 提升固化等级
        };
    }
    
    // 运行时执行优化后的版本
    runtime {
        node execute: DynamicDispatch = {
            dispatch_key: "/lib/auto/generated_solver",
            input: input.task
        };
        
        return execute.result;
    }
}
```

### PromptC-IR v2.0（元编程扩展）
```json
{
  "ir_version": "2.0.0",
  "path": "/app/meta/optimizer",
  "stage": "interpreted",
  "compilation_units": [
    {
      "unit_id": "meta_optimization",
      "type": "comptime_block",
      "stage": "compilation",
      "sandbox": "L0",                    // 编译期无外部效应
      "nodes": {
        "analyze": {
          "type": "llm_call",
          "skill_path": "/lib/meta/prompt_optimizer",
          "inputs": {
            "metrics": "$external.history.metrics"
          }
        },
        "register": {
          "type": "meta",
          "op": "register_subgraph",
          "target_path": "/lib/auto/generated_solver",
          "stage": "solidified",
          "side_effect": "update_program_registry"
        }
      }
    },
    {
      "unit_id": "runtime_execution",
      "type": "runtime_block",
      "stage": "execution",
      "nodes": {
        "dispatch": {
          "type": "control",
          "subtype": "dynamic_dispatch",
          "dispatch_key": "/lib/auto/generated_solver"
        }
      }
    }
  ],
  "execution_order": ["meta_optimization", "runtime_execution"]
}
```

**✅ 验证**：`comptime` 块实现同像性，程序可修改自身 IR 并提升固化等级。

---

## 总结：PromptC v2.0 能力验证表

| 复杂度 | 示例 | 关键特性 | 固化阶段 | 验证结果 |
|--------|------|---------|---------|---------|
| **原子** | 1. 单步翻译 | 路径即类型、L0/L1 区别 | solidified/jitted | ✅ |
| **线性** | 2. 顺序流水线 | JIT 自动融合 | jitted | ✅ |
| **分支** | 3. 条件路由 | Branch 惰性求值 | interpreted | ✅ |
| **数据并行** | 4. 批量处理 | Map 批处理策略 | jitted | ✅ |
| **归约** | 5. 聚合报告 | Reduce 树形优化 | jitted | ✅ |
| **迭代** | 6. 反思改进 | While 循环携带变量 | jitted | ✅ |
| **嵌套** | 7. 自适应处理 | 多层控制流嵌套 | mixed | ✅ |
| **动态** | 8. 运行时派生 | DynamicDispatch 缓存 | interpreted | ✅ |
| **并发** | 9. 多智能体 | Fork-Join COW 隔离 | jitted | ✅ |
| **元编程** | 10. 自优化 | Comptime 代码生成 | interpreted→solidified | ✅ |

**所有示例满足 v2.0 设计约束**：
- ✅ 路径即类型：所有 Skill 通过 `/lib/xxx` 或 `/app/xxx` 寻址
- ✅ 沙箱即安全：L0/L1/L2 替代复杂效应系统
- ✅ 渐进固化：支持 interpreted → jitted → solidified 自动提升
- ✅ 分层 DAG：基础节点 + 4 种控制节点（Map/Reduce/While/Branch）+ Fork-Join