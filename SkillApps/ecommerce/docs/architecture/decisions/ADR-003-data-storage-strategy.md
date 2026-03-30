# ADR-003: 数据存储策略（OpenClaw Workspace + SQLite）

**日期**: 2026-03-26  
**状态**: ✅ 已采纳  
**相关文档**: [[2026-03-26-ecommerce-analysis-system]]

---

## 背景

需要存储以下数据：
1. 原始爬取数据（商品详情、评价）
2. 分析结果（价格趋势、情感评分、分类标签）
3. 生成的报告
4. 向量索引（用于 RAG 和历史对比）

选项：
- A: 纯文件系统（Markdown + JSON）
- B: 关系数据库（PostgreSQL/MySQL）
- C: 混合（文件系统 + SQLite 向量索引）

## 决策

采用**选项 C：混合存储策略**。

**存储分层**：
1. **原始数据** — Markdown + JSON 文件存储于 Workspace 目录
2. **分析结果** — Markdown 文件存储于 Workspace 目录
3. **向量索引** — 使用 OpenClaw Memory-Core（SQLite 后端）
4. **缓存** — Redis（可选，用于去重和速率限制）

## 目录结构

```
~/.openclaw/ecommerce/
├── raw_data/              # 原始爬取数据
│   ├── taobao/
│   │   └── YYYY-MM-DD/
│   └── jd/
│       └── YYYY-MM-DD/
├── analysis_results/      # 分析结果
│   ├── price_trends/
│   ├── sentiment/
│   ├── classifications/
│   └── competitor/
├── reports/               # 生成的报告
│   ├── daily/
│   └── weekly/
├── memory/                # 向量索引（Memory-Core 自动管理）
└── config/                # 配置文件
    ├── product_urls.json  # 商品 URL 列表
    └── categories.yaml    # 分类体系
```

## 决策理由

### 1. OpenClaw 原生
- Workspace 是 OpenClaw 一等公民
- Agent 天然支持文件读写
- 无需额外数据库驱动

### 2. 可追溯
- 所有数据以文件形式存在
- 便于审计和版本控制
- 支持 Git 管理

### 3. 简单
- 无需额外数据库部署（前期）
- 零运维成本
- 开箱即用

### 4. 可扩展
- 大规模时可迁移至 PostgreSQL
- 文件结构保持不变
- 只需修改数据访问层

## 权衡

### 正面后果 ✅
- 零部署成本
- 文件即数据库
- 支持 Git 版本控制
- 便于调试（直接查看文件）

### 负面后果 ⚠️
- 大规模（>100 万商品）性能下降
- 不支持复杂查询（需要 Python 脚本）
- 并发写入需要文件锁

## 扩展路径

### 第一阶段（当前）
- 日爬取 1-10 万商品
- 纯文件系统 + SQLite 向量索引
- 零运维

### 第二阶段（>50 万商品/日）
- 原始数据迁移至 PostgreSQL
- 保持文件结构作为缓存层
- 增加 Redis 缓存

### 第三阶段（>100 万商品/日）
- 考虑微服务拆分
- 每个服务独立数据库
- 事件驱动数据同步

## 数据 Schema

### 商品数据（JSON）
```json
{
  "id": "taobao_123456789",
  "platform": "taobao",
  "url": "https://item.taobao.com/item.htm?id=123456789",
  "title": "商品标题",
  "price": 99.99,
  "original_price": 199.99,
  "description": "商品描述...",
  "category": "electronics/mobile",
  "reviews": [
    {
      "content": "评价内容",
      "rating": 5,
      "date": "2026-03-25"
    }
  ],
  "crawl_time": "2026-03-26T06:00:00Z"
}
```

### 分析结果（Markdown Frontmatter）
```markdown
---
product_id: taobao_123456789
analysis_date: 2026-03-26
analysis_type: price_trend
price_trend_7d: -5.2%
price_trend_30d: -12.8%
anomaly_detected: false
---

# 价格趋势分析

## 7 天走势
...
```

## 相关链接
- [系统架构文档](2026-03-26-ecommerce-analysis-system.md)
- ADR-001: 纯 OpenClaw 架构
- ADR-002: 多 Agent 协作模式
