# ADR-002: 多 Agent 协作模式（Router + Handoff）

**日期**: 2026-03-26  
**状态**: ✅ 已采纳  
**相关文档**: [[2026-03-26-ecommerce-analysis-system]]

---

## 背景

系统需要 5 种 AI 分析能力：
1. 价格趋势分析
2. 情感分析（评价）
3. 商品分类标注
4. 竞品对比分析
5. 异常价格检测

需要决定如何组织这些能力：
- 选项 A: 单一 Agent 处理所有分析
- 选项 B: 多 Agent 协作（Router + Handoff）
- 选项 C: 每个分析独立 Script

## 决策

采用**选项 B：多 Agent 协作模式**。

**架构**：
- 1 个编排 Agent（ecommerce-orchestrator）负责任务分派
- 5 个专业 Agent 分别负责专业分析
- 1 个报告 Agent 负责输出

**协作机制**：
- **Router Pattern**: 编排 Agent 使用 `agent:invoke` 工具调用专业 Agent
- **Handoff**: 使用 `transfer_to_<agent>` 实现上下文继承切换

## 决策理由

### 1. 职责分离
- 每个 Agent 专注单一领域
- Prompt 更精准，分析质量更高
- 便于独立测试和优化

### 2. 可复用
- 专业 Agent 可被多个 Pipeline 复用
- 例如：sentiment-analyst 可被"每日分析"和"竞品分析"复用

### 3. 可观测
- 每个 Agent 的输出独立记录
- 便于调试和审计
- 可追溯分析过程

### 4. 可扩展
- 新增分析类型只需添加新 Agent
- 不影响现有 Agent
- 支持并行执行

## 权衡

### 正面后果 ✅
- Agent 可独立优化和测试
- 支持并行执行（多个 Agent 同时分析）
- 分析质量提升（专业化 Prompt）

### 负面后果 ⚠️
- 需要维护多个 Agent 配置
- Agent 间通信有开销（约 10-20% 延迟）
- 需要编排逻辑（增加复杂度）

## Agent 列表

| Agent 名 | 职责 | 模型 |
|---------|------|------|
| ecommerce-orchestrator | 任务编排 | qwen3.5-plus |
| crawler-agent | 数据爬取 | qwen3-max |
| price-analyst | 价格趋势 + 异常检测 | qwen3.5-plus |
| sentiment-analyst | 评价情感分析 | qwen3.5-plus |
| classifier-agent | 商品分类标注 | qwen3-max |
| competitor-analyst | 竞品对比 | qwen3.5-plus |
| anomaly-detector | 异常模式识别 | qwen3.5-plus |
| report-generator | 报告生成 | qwen3-max |

## 相关链接
- [系统架构文档](2026-03-26-ecommerce-analysis-system.md)
- ADR-001: 纯 OpenClaw 架构
- ADR-003: 数据存储策略
