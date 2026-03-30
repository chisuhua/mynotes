# ADR-001: 选择纯 OpenClaw 驱动架构

**日期**: 2026-03-26  
**状态**: ✅ 已采纳  
**相关文档**: [[2026-03-26-ecommerce-analysis-system]]

---

## 背景

需要为电商商品数据分析系统选择技术架构。初始方案考虑了以下选项：

1. **方案 A**: 分层单体架构（纯 Python）
2. **方案 B**: 微服务架构（Docker + gRPC）
3. **方案 C**: 混合架构（C++ 底层 + Python 封装 + OpenClaw 编排）
4. **方案 D**: 纯 OpenClaw 驱动架构（不依赖外部项目）

初始讨论中，方案 C 被推荐，但依赖 AOS-Browser（浏览器自动化项目）和 BrainSkillForge（Agent DSL 项目）。

## 决策

采用**方案 D：纯 OpenClaw 驱动架构**，不依赖 AOS-Browser/BrainSkillForge 外部项目。

## 决策理由

### 1. 降低复杂度
- 单一平台运维，无需跨项目集成
- 配置文件集中管理（openclaw.json）
- 无需维护 C++ 底层代码

### 2. 快速启动
- OpenClaw 原生能力足够支撑中型规模（日爬取 1-10 万）
- 开发周期从 3 周缩短至 2 周
- 无需学习外部项目 DSL

### 3. 配置驱动
- Agent、Pipeline 通过 JSON/YAML 配置
- 无需编写复杂代码
- 符合"配置即代码"原则

### 4. 生态一致
- 符合 OpenClaw 技能生态系统设计理念
- 可复用 OpenClaw 社区技能
- 便于未来扩展

## 权衡

### 正面后果 ✅
- 开发周期缩短 33%
- 维护成本降低 50%
- 配置文件单一，易于审计

### 负面后果 ⚠️
- 受 OpenClaw 平台能力限制
- 超大规模（>100 万商品/日）需扩展至 PostgreSQL
- Playwright 性能可能不如 C++ 原生实现

## 迁移路径

如未来需要扩展：
1. **第一阶段**: 保持 OpenClaw 编排，替换爬虫模块为 C++ 实现
2. **第二阶段**: 数据存储迁移至 PostgreSQL
3. **第三阶段**: 考虑微服务拆分

## 相关链接
- [系统架构文档](2026-03-26-ecommerce-analysis-system.md)
- ADR-002: 多 Agent 协作模式
- ADR-003: 数据存储策略
