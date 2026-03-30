# 电商商品数据分析系统 - 架构文档索引

**最后更新**: 2026-03-26  
**版本**: 1.0.0  
**状态**: ✅ 已发布

---

## 文档导航

### 📄 主文档
- [[2026-03-26-ecommerce-analysis-system]] — 系统架构文档（主文档，~750 行）

### 📋 专项文档
- [[ERROR-HANDLING-STRATEGY]] — 错误处理策略（独立文档，约 400 行）
- [[TESTING-STRATEGY]] — 测试策略（613 行，完整指南）
- [[DEPLOYMENT-GUIDE]] — 部署指南（计划中）

### 📋 架构决策记录 (ADR)
- [[ADR-001-pure-openclaw-architecture]] — 选择纯 OpenClaw 驱动架构
- [[ADR-002-multi-agent-collaboration]] — 多 Agent 协作模式（Router + Handoff）
- [[ADR-003-data-storage-strategy]] — 数据存储策略（Workspace + SQLite）
- [[ADR-004-error-handling-and-testing]] — 错误处理与测试策略

### 🔍 评审记录
- [[2026-03-26-ecommerce-analysis-system-review]] — 架构文档评审报告

---

## 快速链接

### 配置示例
- `~/.openclaw/openclaw.json` — OpenClaw 主配置
- `~/.openclaw/skills/ecommerce-daily-analysis.yaml` — 每日分析流水线

### 目录结构
```
~/.openclaw/ecommerce/
├── raw_data/              # 原始爬取数据
├── analysis_results/      # 分析结果
├── reports/               # 生成的报告
├── memory/                # 向量索引
└── config/                # 配置文件
```

---

## 变更记录

| 日期 | 版本 | 变更描述 | 作者 |
|------|------|---------|------|
| 2026-03-26 | 1.2.0 | 主文档精简：移除部署/测试章节，移至专项文档 | OpenClaw Architecture Team |
| 2026-03-26 | 1.1.0 | 添加错误处理策略、测试策略，新增 ADR-004 | OpenClaw Architecture Team |
| 2026-03-26 | 1.0.0 | 初始版本发布 | OpenClaw Architecture Team |

---

## 相关链接

- [OpenClaw 官方文档](https://openclaw.dev/docs)
- [OpenClaw Skills](https://openclaw.dev/skills)
- [Playwright 文档](https://playwright.dev)

---

**维护者**: OpenClaw Architecture Team  
**联系方式**: architecture@openclaw.dev
