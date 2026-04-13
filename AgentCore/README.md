# AgentCore 文档索引

> **项目**: CortiX / AgentCore  
> **最后更新**: 2026-03-23  
> **架构版本**: AOS-Universal v3.0

---

## 📚 文档导航

### 架构演进路线
```
BAFA v1.0 → AOS-Browser v1.0 → AOS-Browser v2.0 → AOS-Universal v3.0
(融合架构)    (本地 LLM 专用)     (强内核 + 外壳)      (通用操作型智能体)
```

---

## 📋 文档清单

| 文档 | 版本 | 类型 | 说明 |
|---|---|---|---|
| [README.md](./README.md) | - | 索引 | 本文档 |
| [浏览器智能体架构.md](./浏览器智能体架构.md) | BAFA v1.0 | 架构基线 | 三层架构 (反射层/认知层/元认知层) |
| [AOS-Browser 顶层设计 v1.0.md](./AOS-Browser 顶层设计 v1.0.md) | v1.0 | 顶层设计 | 10 项 UR 需求 + 13 项 ADR 决策 |
| [AOS-Browser 顶层设计 v2.0.md](./AOS-Browser 顶层设计 v2.0.md) | v2.0 | 顶层设计 | 插件化 Hook 机制 + 事件总线 |
| [AOS-Universal 顶层设计 v3.0.md](./AOS-Universal 顶层设计 v3.0.md) | v3.0 | 顶层设计 | 通用工具接口 + DAG 工作流 |
| [AOS-Browser 详细设计.md](./AOS-Browser 详细设计.md) | v1.0 | 详细设计 | 浏览器专用模块设计 |
| [AOS-Universal 详细设计.md](./AOS-Universal 详细设计.md) | v1.0 | 详细设计 | 通用智能体模块设计 (TaskGroup/WorkflowOrchestrator) |
| [AOS-Browser 工具接口 v1.0.md](./AOS-Browser 工具接口 v1.0.md) | v1.0 | 协议规范 | Tool Manifest + 沙箱协议 |
| [AOS-Browser 工具接口 v1.1.md](./AOS-Browser 工具接口 v1.1.md) | v1.1 | 协议规范 | 评审增强版 (CompiledSchema/预热池) |
| [CDP 浏览器内核.md](./CDP 浏览器内核.md) | v1.0 | 内核设计 | CyberWeasel 架构 (Layer0 浏览器沙箱实现) |

---

## 🏗️ 架构分层

| 层级 | 模块 | 文档 |
|---|---|---|
| **Layer 3** | WorkflowOrchestrator, PluginManager, HookManager | AOS-Universal 顶层设计 v3.0, AOS-Universal 详细设计 |
| **Layer 2** | CognitiveEngine, TaskGroup, UniversalToolAdapter | AOS-Browser 详细设计, AOS-Universal 详细设计 |
| **Layer 1** | LightweightInterruptQueue, ResourceQuotaManager, SandboxPool | 浏览器智能体架构 |
| **Layer 0** | SandboxedToolExecutor, WASM/Docker/Process/Browser Sandbox | AOS-Browser 工具接口 v1.1, CDP 浏览器内核 |

---

## 🔑 核心概念

| 概念 | 说明 | 参考文档 |
|---|---|---|
| **KV Cache 摘要** | 轻量级注意力模式摘要 (<100MB)，加速崩溃恢复 30%+ | AOS-Browser 顶层设计 v1.0 (ADR-11) |
| **Critical DOM Hash** | 关键 DOM 选择器路径哈希，页面状态恢复校验 | AOS-Browser 顶层设计 v1.0 (ADR-12) |
| **强内核 + 灵活外壳** | 内核保证稳定性，外壳支持动态扩展 | AOS-Browser 顶层设计 v2.0 |
| **Tool Manifest** | 工具元数据契约，声明式定义能力/资源/安全策略 | AOS-Browser 工具接口 v1.1 |
| **TaskGroup** | 协程任务组，支持 Fork/Join 语义 | AOS-Universal 详细设计 |
| **WorkflowOrchestrator** | DAG 工作流编排器，管理任务依赖 | AOS-Universal 详细设计 |

---

## 📝 版本规范

### 命名规则
- 所有版本采用 `vX.Y.Z` 语义化版本格式
- 文档文件名与版本号一致 (如 `AOS-Browser 顶层设计 v2.0.md`)

### 基线依赖
- 每篇文档开头必须标注 **基线架构** 版本
- 详细设计文档必须引用对应的顶层设计版本

### 变更流程
1. 顶层设计变更 → 更新 ADR → 同步详细设计
2. 协议变更 → 更新工具接口文档 → 版本号递增
3. 所有变更需在本文档更新记录中登记

---

## 🔗 外部依赖

| 项目 | 说明 |
|---|---|
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | 本地 LLM 推理引擎 (定制 KV Cache 摘要分支) |
| [Playwright](https://playwright.dev/) | 浏览器自动化 (BrowserSandbox 实现) |
| [nlohmann/json](https://github.com/nlohmann/json) | C++ JSON 库 |
| [libseccomp](https://github.com/seccomp/libseccomp) | 系统调用过滤 (沙箱安全) |

---

## 📅 更新记录

| 日期 | 变更 | 作者 |
|---|---|---|
| 2026-03-23 | 初始版本，统一文档命名规范，新增 AOS-Universal 详细设计 | DevMate |
| 2026-03-22 | 工具接口 v1.1 评审增强 | 池工 |
| 2026-03-20 | CDP 浏览器内核/CyberWeasel 架构 | 池工 |

---

// -- 🦊 DevMate | AgentCore 文档索引 --
