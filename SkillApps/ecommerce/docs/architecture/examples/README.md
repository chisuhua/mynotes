# 电商商品数据分析系统 - 执行脚本说明

本目录包含 3 个执行脚本/配置文件，用于不同场景：

---

## 文件列表

| 文件 | 用途 | 使用场景 |
|------|------|---------|
| `openclaw.json` | OpenClaw 主配置文件 | 首次安装时复制到 `~/.openclaw/` |
| `run-pipeline.sh` | Shell 执行脚本 | 调试、测试、自定义流程 |
| `crawler.py` | Python 爬虫脚本 | 单独测试爬取功能 |

---

## 快速开始

### 1. 复制配置文件

```bash
# 复制 OpenClaw 配置
cp openclaw.json ~/.openclaw/openclaw.json

# 创建工作区
mkdir -p ~/.openclaw/ecommerce/{raw_data,analysis_results,reports,memory,config}
```

### 2. 创建商品 URL 配置

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

### 3. 执行分析

**推荐方式**（使用 OpenClaw 编排 Agent）：
```bash
openclaw chat --agent ecommerce-orchestrator "执行每日商品分析流程"
```

**调试方式**（使用 Shell 脚本）：
```bash
# 干运行（验证流程）
bash run-pipeline.sh --dry-run

# 实际运行
bash run-pipeline.sh
```

**测试爬取**（单独测试爬虫）：
```bash
python3 crawler.py \
  ~/.openclaw/ecommerce/config/product_urls.json \
  ~/.openclaw/ecommerce/raw_data/20260326
```

---

## 各脚本详细说明

### openclaw.json

OpenClaw 主配置文件，定义了 8 个 Agent：

| Agent 名 | 职责 |
|---------|------|
| `ecommerce-orchestrator` | 编排 Agent，协调其他 Agent |
| `crawler-agent` | 爬取淘宝/京东数据 |
| `price-analyst` | 价格趋势分析 |
| `sentiment-analyst` | 评价情感分析 |
| `classifier-agent` | 商品分类标注 |
| `competitor-analyst` | 竞品对比分析 |
| `anomaly-detector` | 异常检测 |
| `report-generator` | 报告生成 |

**修改建议**：
- 如需更换 LLM 模型，修改 `model` 字段
- 如需调整 Prompt，修改 `system_prompt` 字段
- 如需添加工具，修改 `tools` 数组

### run-pipeline.sh

Shell 执行脚本，包含 4 个阶段：

1. **crawl** - 爬取数据
2. **deduplicate** - 数据去重
3. **analyze** - AI 分析（5 个专业 Agent）
4. **report** - 生成报告

**参数**：
- `--dry-run` - 干运行，不实际执行，仅打印流程

**自定义**：
- 如需修改输出路径，编辑 `WORKSPACE` 变量
- 如需修改阶段，编辑各阶段命令

### crawler.py

Python 爬虫脚本，使用 Playwright 爬取淘宝/京东数据。

**依赖**：
```bash
pip install playwright
playwright install chromium
```

**参数**：
```bash
python3 crawler.py <config_file> <output_dir>
```

**自定义**：
- 如需添加新平台，添加新的 `crawl_<platform>()` 函数
- 如需修改解析逻辑，编辑对应的选择器

---

## 故障排查

### 问题 1: 配置文件找不到
```
错误：商品 URL 配置文件不存在
```
**解决**：确保 `~/.openclaw/ecommerce/config/product_urls.json` 存在

### 问题 2: Playwright 未安装
```
错误：请先安装 playwright
```
**解决**：
```bash
pip install playwright
playwright install chromium
```

### 问题 3: 爬取失败
```
爬取失败：Timeout 30000ms exceeded
```
**解决**：
- 检查网络连接
- 增加 timeout 参数（编辑 `crawler.py`）
- 使用代理（编辑 `USER_AGENTS` 池）

---

## 查看报告

执行完成后，报告生成在：
```bash
~/.openclaw/ecommerce/reports/daily_YYYYMMDD.md
```

查看最新报告：
```bash
cat ~/.openclaw/ecommerce/reports/daily_$(date +%Y%m%d).md
```

---

**文档版本**: 1.0.0  
**最后更新**: 2026-03-26
