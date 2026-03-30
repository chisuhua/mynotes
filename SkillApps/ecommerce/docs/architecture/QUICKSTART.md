# 电商商品数据分析系统 - 快速开始指南

## 前置条件

- Python 3.10+
- Node.js 18+
- OpenClaw 平台（v2026.2+）
- Playwright

## 安装步骤

### 1. 安装 OpenClaw

```bash
pip install openclaw
```

### 2. 启用所需技能

```bash
openclaw skills enable doc-skills
```

### 3. 初始化工作区

```bash
mkdir -p ~/.openclaw/ecommerce/{raw_data,analysis_results,reports,memory,config}
```

### 4. 复制配置文件

```bash
# 复制 openclaw.json
cp docs/architecture/examples/openclaw.json ~/.openclaw/openclaw.json

# 复制 Skill Pipeline
cp docs/architecture/examples/ecommerce-daily-analysis.yaml ~/.openclaw/skills/
```

### 5. 安装 Playwright

```bash
playwright install chromium
playwright install-deps chromium
```

### 6. 创建商品 URL 配置

```bash
cat > ~/.openclaw/ecommerce/config/product_urls.json << 'EOF'
{
  "taobao": [
    "https://item.taobao.com/item.htm?id=YOUR_PRODUCT_ID"
  ],
  "jd": [
    "https://item.jd.com/YOUR_PRODUCT_ID.html"
  ]
}
EOF
```

### 7. 测试运行

**方式一：通过编排 Agent 执行（⭐ 推荐）**

这是最简单、最推荐的方式。OpenClaw 编排 Agent 会自动协调各专业 Agent 完成整个流程。

```bash
# 执行完整分析流程
openclaw chat --agent ecommerce-orchestrator "
  从配置文件读取商品 URL 列表，执行完整分析流程：
  1. 爬取淘宝/京东最新数据
  2. 数据去重
  3. 协调各专业 Agent 进行分析（价格趋势、情感分析、分类标注、竞品对比、异常检测）
  4. 生成每日分析报告
"

# 或者使用简化命令
openclaw chat --agent ecommerce-orchestrator "执行每日商品分析流程"
```

**方式二：通过 Shell 脚本执行（调试/测试用）**

适用于调试特定阶段或测试爬取功能。

```bash
# 干运行（不实际爬取，仅验证流程）
bash docs/architecture/examples/run-pipeline.sh --dry-run

# 实际运行（执行完整流程）
bash docs/architecture/examples/run-pipeline.sh

# 查看生成的报告
cat ~/.openclaw/ecommerce/reports/daily_$(date +%Y%m%d).md
```

**方式三：分步执行（调试/自定义用）**

适用于单独测试某个 Agent 或自定义分析流程。

```bash
# 步骤 1: 爬取数据
python3 docs/architecture/examples/crawler.py \
  ~/.openclaw/ecommerce/config/product_urls.json \
  ~/.openclaw/ecommerce/raw_data/20260326

# 步骤 2: 单独测试各 Agent
openclaw chat --agent price-analyst "分析 ~/.openclaw/ecommerce/raw_data/20260326 中的价格数据"
openclaw chat --agent sentiment-analyst "分析评价情感"
openclaw chat --agent classifier-agent "对商品进行分类标注"
openclaw chat --agent competitor-analyst "对比淘宝和京东的竞品"
openclaw chat --agent anomaly-detector "检测价格异常"

# 步骤 3: 生成报告
openclaw chat --agent report-generator "生成每日分析报告"
```

## 查看报告

运行完成后，报告将生成在：

```bash
~/.openclaw/ecommerce/reports/daily_YYYYMMDD.md
```

查看最新报告：

```bash
cat ~/.openclaw/ecommerce/reports/daily_$(date +%Y%m%d).md
```

## 定时任务配置

### Cron 配置

```bash
# 编辑 crontab
crontab -e

# 添加每日早上 6 点执行
0 6 * * * openclaw run-skill ecommerce-daily-analysis >> ~/.openclaw/ecommerce/logs/cron.log 2>&1
```

### 验证 Cron

```bash
# 查看 Cron 日志
tail -f ~/.openclaw/ecommerce/logs/cron.log
```

## 常见问题

### Q: 爬取失败怎么办？

A: 检查以下几点：
1. 网络连接是否正常
2. 商品 URL 是否正确
3. 是否触发反爬虫（降低爬取频率）
4. 查看日志：`~/.openclaw/ecommerce/logs/crawler.log`

### Q: 分析结果不准确？

A: 调整 Agent Prompt：
1. 编辑 `~/.openclaw/openclaw.json`
2. 修改对应 Agent 的 `system_prompt`
3. 重启 OpenClaw Gateway：`openclaw gateway restart`

### Q: 如何添加新的分析维度？

A: 添加新的专业 Agent：
1. 在 `openclaw.json` 中添加新 Agent 配置
2. 在 `ecommerce-daily-analysis.yaml` 中添加分析阶段
3. 重新运行 Pipeline

## 下一步

- 查看完整架构文档：[[2026-03-26-ecommerce-analysis-system]]
- 查看 ADR：[[ADR-001-pure-openclaw-architecture]]
- 查看评审报告：[[2026-03-26-ecommerce-analysis-system-review]]

---

**文档版本**: 1.0.0  
**最后更新**: 2026-03-26
