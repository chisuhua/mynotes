# 电商商品数据分析系统 — 测试策略

| 属性 | 值 |
|------|-----|
| **版本** | 1.1.0 |
| **创建日期** | 2026-03-26 |
| **最后更新** | 2026-03-26 |
| **状态** | 已发布 |
| **作者** | OpenClaw Architecture Team |
| **相关文档** | [[2026-03-26-ecommerce-analysis-system]] |

---

## 变更记录

| 版本 | 日期 | 作者 | 变更描述 |
|------|------|------|---------|
| 1.1.0 | 2026-03-26 | OpenClaw Architecture Team | 初始版本 |

---

## 1. 测试金字塔

系统采用三层测试金字塔模型：

```
        ╱▔▔▔▔╲         E2E 测试（10%）
       ╱      ╲        — 完整 Pipeline 验证
      ╱────────╲       集成测试（30%）
     ╱          ╲      — Agent 协作、数据流
    ╱────────────╲     单元测试（60%）
   ╱______________╲    — 函数、工具类
```

### 1.1 测试覆盖率要求

| 测试层级 | 覆盖率要求 | 说明 |
|---------|-----------|------|
| **单元测试** | 行覆盖率 ≥ 60% | 核心模块（爬虫、分析）≥ 80% |
| **集成测试** | 关键路径 100% | 所有 Agent 协作流程必须覆盖 |
| **E2E 测试** | 主流程 100% | 每日 Pipeline 必须可运行 |

### 1.2 测试工具链

```txt
# requirements-test.txt
pytest>=7.4.0
pytest-cov>=4.1.0      # 覆盖率
pytest-mock>=3.11.0    # Mock
responses>=0.23.0      # HTTP Mock
freezegun>=1.2.0       # 时间 Mock
```

### 1.3 目录结构

```
tests/
├── unit/
│   ├── test_crawler.py        # 爬虫模块测试
│   ├── test_price_analysis.py # 价格分析测试
│   ├── test_sentiment.py      # 情感分析测试
│   ├── test_classifier.py     # 分类模块测试
│   └── test_retry.py          # 重试机制测试
├── integration/
│   ├── test_agent_collaboration.py  # Agent 协作测试
│   └── test_data_flow.py            # 数据流测试
├── e2e/
│   └── test_full_pipeline.py        # 完整 Pipeline 测试
├── fixtures/
│   ├── sample_product.html          # 示例 HTML
│   ├── sample_reviews.json          # 示例评价数据
│   └── expected_report.md           # 预期报告模板
└── conftest.py                      # pytest 配置
```

---

## 2. 单元测试

**测试框架**：pytest + pytest-cov

### 2.1 爬虫解析测试

```python
# tests/unit/test_crawler.py
import pytest
from src.crawler.parser import parse_product_info, parse_price

class TestProductParser:
    """商品解析器测试"""
    
    def test_parse_price_yuan(self):
        """测试价格解析 - 元格式"""
        html = "<div class='price'>¥99.00</div>"
        result = parse_price(html)
        assert result == 99.00
    
    def test_parse_price_with_text(self):
        """测试价格解析 - 含文字"""
        html = "<span>价格：￥199 元</span>"
        result = parse_price(html)
        assert result == 199.0
    
    def test_parse_price_invalid(self):
        """测试无效价格处理"""
        html = "<div>价格面议</div>"
        with pytest.raises(ValueError):
            parse_price(html)
    
    def test_parse_product_info_complete(self):
        """测试完整商品信息解析"""
        html = """
        <div class="product">
            <h1 class="title">测试商品</h1>
            <div class="price">¥299.00</div>
            <p class="description">商品描述</p>
        </div>
        """
        result = parse_product_info(html)
        assert result["title"] == "测试商品"
        assert result["price"] == 299.00
        assert result["description"] == "商品描述"
```

### 2.2 重试机制测试

```python
# tests/unit/test_retry.py
import pytest
from unittest.mock import Mock
from src.utils.retry import retry_with_exponential_backoff, MaxRetriesExceeded

class TestRetryMechanism:
    """重试机制测试"""
    
    def test_retry_success_on_first_try(self):
        """测试首次尝试成功"""
        mock_func = Mock(return_value="success")
        result = retry_with_exponential_backoff(mock_func)
        assert result == "success"
        mock_func.assert_called_once()
    
    def test_retry_success_after_failures(self):
        """测试失败后重试成功"""
        mock_func = Mock(side_effect=[
            ConnectionError("失败 1"),
            ConnectionError("失败 2"),
            "success"
        ])
        result = retry_with_exponential_backoff(
            mock_func,
            max_retries=3,
            exceptions=(ConnectionError,)
        )
        assert result == "success"
        assert mock_func.call_count == 3
    
    def test_retry_exceeds_max(self):
        """测试超过最大重试次数"""
        mock_func = Mock(side_effect=ConnectionError("始终失败"))
        
        with pytest.raises(MaxRetriesExceeded) as exc_info:
            retry_with_exponential_backoff(
                mock_func,
                max_retries=3,
                exceptions=(ConnectionError,)
            )
        
        assert "超过最大重试次数" in str(exc_info.value)
        assert mock_func.call_count == 4  # 初始 + 3 次重试
```

### 2.3 运行单元测试

```bash
# 运行所有单元测试
pytest tests/unit/ -v

# 运行并生成覆盖率报告
pytest tests/unit/ --cov=src --cov-report=html --cov-report=term

# 运行特定测试文件
pytest tests/unit/test_crawler.py -v

# 运行特定测试函数
pytest tests/unit/test_crawler.py::TestProductParser::test_parse_price_yuan -v
```

---

## 3. 集成测试

**测试范围**：Agent 协作、数据流、存储层

### 3.1 Agent 协作测试

```python
# tests/integration/test_agent_collaboration.py
import pytest
from src.agents.orchestrator import OrchestratorAgent
from src.agents.crawler import CrawlerAgent
from src.agents.price_analyst import PriceAnalystAgent

class TestAgentCollaboration:
    """Agent 协作测试"""
    
    @pytest.fixture
    def orchestrator(self):
        """创建编排 Agent 实例"""
        return OrchestratorAgent(
            workspace="~/.openclaw/ecommerce",
            test_mode=True  # 测试模式，不实际调用 API
        )
    
    def test_orchestrator_crawl_and_analyze(self, orchestrator):
        """测试编排 Agent 执行爬取和分析"""
        urls = [
            "https://item.taobao.com/item.htm?id=test1",
            "https://item.taobao.com/item.htm?id=test2"
        ]
        
        # 使用 mock 数据执行
        result = orchestrator.run_analysis(urls, mock_data=True)
        
        assert result["status"] == "success"
        assert len(result["crawled_items"]) == 2
        assert "price_analysis" in result["analysis"]
        assert "sentiment_analysis" in result["analysis"]
    
    def test_agent_handoff(self, orchestrator):
        """测试 Agent 间 Handoff 机制"""
        # 验证编排 Agent 可以正确调用专业 Agent
        handoff_result = orchestrator.handoff_to(
            agent_name="price_analyst",
            context={"product_data": {"price": 99.00}}
        )
        
        assert handoff_result["agent"] == "price_analyst"
        assert "analysis" in handoff_result
```

### 3.2 数据流测试

```python
# tests/integration/test_data_flow.py
import pytest
import json
from pathlib import Path
from src.data.flow import DataFlowManager

class TestDataFlow:
    """数据流测试"""
    
    @pytest.fixture
    def data_flow(self, tmp_path):
        """创建临时数据流管理器"""
        return DataFlowManager(workspace=str(tmp_path))
    
    def test_full_data_flow(self, data_flow):
        """测试完整数据流"""
        # 1. 写入原始数据
        raw_data = {"title": "测试商品", "price": 99.00}
        raw_path = data_flow.write_raw_data("taobao", raw_data)
        assert raw_path.exists()
        
        # 2. 读取并处理
        loaded = data_flow.read_raw_data(raw_path)
        assert loaded["title"] == "测试商品"
        
        # 3. 写入分析结果
        analysis = {"price_trend": "rising", "sentiment": 0.8}
        analysis_path = data_flow.write_analysis_result("price", analysis)
        assert analysis_path.exists()
        
        # 4. 验证数据完整性
        all_results = data_flow.get_all_analysis()
        assert len(all_results) == 1
```

### 3.3 运行集成测试

```bash
# 运行所有集成测试
pytest tests/integration/ -v

# 运行集成测试（带标记）
pytest -m integration -v
```

---

## 4. 端到端测试

**测试范围**：完整 Pipeline 执行

### 4.1 E2E 测试脚本

```bash
#!/bin/bash
# tests/e2e/run_pipeline_test.sh

set -e

echo "=== E2E Pipeline 测试 ==="

# 1. 准备测试环境
export OPENCLAW_WORKSPACE="/tmp/ecommerce_test_$$"
export OPENCLAW_TEST_MODE="true"
mkdir -p "$OPENCLAW_WORKSPACE"/{raw_data,analysis_results,reports,config}

# 2. 准备测试数据
cat > "$OPENCLAW_WORKSPACE/config/product_urls.json" <<EOF
{
  "taobao": [
    "https://item.taobao.com/item.htm?id=test1"
  ],
  "jd": [
    "https://item.jd.com/test1.html"
  ]
}
EOF

# 3. 执行 Pipeline（使用 mock）
echo "执行每日分析 Pipeline..."
openclaw chat --agent ecommerce-orchestrator \
  "执行每日商品分析流程（测试模式）" \
  --test-mode

# 4. 验证输出
echo "验证输出报告..."
REPORT_COUNT=$(find "$OPENCLAW_WORKSPACE/reports" -name "*.md" | wc -l)
if [ "$REPORT_COUNT" -gt 0 ]; then
    echo "✅ 报告生成成功：$REPORT_COUNT 个文件"
    
    # 验证报告内容
    if grep -q "价格趋势" "$OPENCLAW_WORKSPACE/reports"/*.md; then
        echo "✅ 报告包含价格分析"
    else
        echo "❌ 报告缺少价格分析"
        exit 1
    fi
else
    echo "❌ 未生成报告"
    exit 1
fi

# 5. 清理
rm -rf "$OPENCLAW_WORKSPACE"

echo "=== E2E 测试通过 ==="
```

### 4.2 运行 E2E 测试

```bash
# 运行 E2E 测试
bash tests/e2e/run_pipeline_test.sh

# 或使用 pytest 运行器
pytest tests/e2e/ -v
```

---

## 5. 测试数据管理

### 5.1 Fixture 示例

**商品 HTML**：
```html
<!-- tests/fixtures/sample_product.html -->
<!DOCTYPE html>
<html>
<head><title>测试商品页面</title></head>
<body>
    <div class="product">
        <h1 class="title">iPhone 15 Pro Max</h1>
        <div class="price">¥9999.00</div>
        <div class="description">Apple iPhone 15 Pro Max 256GB</div>
        <div class="reviews">
            <div class="review-item">
                <span class="text">非常好用，值得购买！</span>
                <span class="rating" data-value="5">5 星</span>
            </div>
            <div class="review-item">
                <span class="text">价格有点贵</span>
                <span class="rating" data-value="4">4 星</span>
            </div>
        </div>
    </div>
</body>
</html>
```

**评价数据**：
```json
// tests/fixtures/sample_reviews.json
[
  {
    "content": "非常好用，值得购买！",
    "rating": 5,
    "date": "2026-03-20"
  },
  {
    "content": "价格有点贵",
    "rating": 4,
    "date": "2026-03-18"
  }
]
```

### 5.2 Pytest 配置

```python
# tests/conftest.py
import pytest
import json
from pathlib import Path

@pytest.fixture
def sample_product_html():
    """加载示例商品 HTML"""
    fixture_path = Path(__file__).parent / "fixtures" / "sample_product.html"
    return fixture_path.read_text(encoding="utf-8")

@pytest.fixture
def sample_reviews_json():
    """加载示例评价数据"""
    fixture_path = Path(__file__).parent / "fixtures" / "sample_reviews.json"
    return json.loads(fixture_path.read_text(encoding="utf-8"))

@pytest.fixture
def mock_llm_response():
    """Mock LLM API 响应"""
    return {
        "sentiment_score": 0.85,
        "keywords": ["好用", "值得购买"],
        "classification": "电子产品/手机"
    }
```

---

## 6. CI/CD 集成

### 6.1 GitHub Actions 配置

```yaml
# .github/workflows/test.yml
name: Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov
      
      - name: Run unit tests
        run: |
          pytest tests/unit/ --cov=src --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./coverage.xml
  
  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run integration tests
        run: |
          pytest tests/integration/ -v
  
  e2e-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run E2E tests
        run: |
          bash tests/e2e/run_pipeline_test.sh
```

### 6.2 覆盖率检查

```bash
# 检查覆盖率是否达标
pytest tests/ --cov=src --cov-fail-under=60
```

### 6.3 测试报告

生成 HTML 覆盖率报告：

```bash
# 生成 HTML 报告
pytest tests/ --cov=src --cov-report=html

# 在浏览器中打开
open htmlcov/index.html  # macOS
xdg-open htmlcov/index.html  # Linux
```

---

## 7. 测试最佳实践

### 7.1 测试命名规范

```python
# 函数命名：test_<function>_<scenario>_<expected>
def test_parse_price_yuan():  # ✅ 清晰
def test_price():  # ❌ 不清晰

# 类命名：Test<Module/Feature>
class TestProductParser:  # ✅ 清晰
class TestCrawler:  # ✅ 清晰
```

### 7.2 测试独立性

```python
# ✅ 每个测试独立，不依赖其他测试状态
def test_parse_price(self):
    # 独立设置
    html = "<div>¥99</div>"
    # ...

def test_parse_title(self):
    # 独立设置
    html = "<h1>商品</h1>"
    # ...
```

### 7.3 测试数据隔离

```python
# ✅ 使用临时目录，测试后自动清理
@pytest.fixture
def temp_workspace(tmp_path):
    workspace = tmp_path / "ecommerce"
    workspace.mkdir()
    yield workspace
    # 自动清理
```

### 7.4 Mock 外部依赖

```python
# ✅ Mock LLM API，避免实际调用
@pytest.fixture
def mock_llm(mocker):
    return mocker.patch(
        'src.agents.llm.call_llm_api',
        return_value={"sentiment": 0.8}
    )
```

---

## 8. 常见问题

### Q: 覆盖率达不到 60% 怎么办？

**A**: 按优先级补充测试：
1. **P0** — 核心业务逻辑（爬虫解析、分析函数）
2. **P1** — 工具函数（重试、熔断器）
3. **P2** — 配置类代码、简单 getter/setter

### Q: 集成测试运行太慢？

**A**: 
- 使用 `pytest-xdist` 并行执行：`pytest -n auto`
- Mock 外部依赖（LLM API、Redis）
- 使用内存数据库（SQLite :memory:）

### Q: E2E 测试不稳定？

**A**:
- 增加重试机制（flaky 装饰器）
- 使用固定测试数据（避免依赖外部状态）
- 设置合理超时（避免网络波动）

---

## 相关链接

- [主架构文档](../2026-03-26-ecommerce-analysis-system.md)
- [ADR-004：错误处理与测试策略](decisions/ADR-004-error-handling-and-testing.md)
- [pytest 官方文档](https://docs.pytest.org)
- [pytest-cov 文档](https://pytest-cov.readthedocs.io)

---

**文档结束**
