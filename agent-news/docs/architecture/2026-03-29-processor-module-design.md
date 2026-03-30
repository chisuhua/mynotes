# 处理模块详细设计

**创建时间**: 2026-03-29  
**版本**: v1.0 草案  
**状态**: 待评审

---

## 1. 模块概述

### 1.1 职责

处理层负责对爬虫抓取的原始数据进行处理：
- **去重** - 指纹去重 + 标题/URL 去重
- **摘要** - 自动生成内容摘要
- **分类** - 自动分类到领域标签

### 1.2 设计原则

- **流水线处理** - 数据按顺序流经各处理器
- **可插拔** - 处理器可独立替换
- **高性能** - 支持批量处理

---

## 2. 接口定义

### 2.1 基础处理器类

```python
# src/processors/base_processor.py

from abc import ABC, abstractmethod
from typing import List
from crawlers.base_crawler import NewsItem

class BaseProcessor(ABC):
    """处理器基类"""
    
    @abstractmethod
    def process(self, items: List[NewsItem]) -> List[NewsItem]:
        """处理数据"""
        pass
```

---

## 3. 处理器实现

### 3.1 去重处理器

```python
# src/processors/deduplicator.py

from .base_processor import BaseProcessor
from typing import List, Set
from crawlers.base_crawler import NewsItem

class Deduplicator(BaseProcessor):
    """去重处理器"""
    
    def __init__(self, retention_days: int = 30):
        self.retention_days = retention_days
        self.seen_fingerprints: Set[str] = set()
        self.seen_titles: Set[str] = set()
        self.seen_urls: Set[str] = set()
    
    def process(self, items: List[NewsItem]) -> List[NewsItem]:
        """去重处理"""
        unique_items = []
        
        for item in items:
            # 指纹去重
            if item.fingerprint in self.seen_fingerprints:
                continue
            
            # 标题去重
            if item.title in self.seen_titles:
                continue
            
            # URL 去重
            if item.url in self.seen_urls:
                continue
            
            # 添加到已见集合
            self.seen_fingerprints.add(item.fingerprint)
            self.seen_titles.add(item.title)
            self.seen_urls.add(item.url)
            
            unique_items.append(item)
        
        return unique_items
    
    def load_history(self, db_connection):
        """加载历史去重记录"""
        # 从数据库加载最近 30 天的记录
        pass
    
    def cleanup(self):
        """清理过期记录"""
        # 清理超过 retention_days 的记录
        pass
```

---

### 3.2 摘要生成器

```python
# src/processors/summarizer.py

from .base_processor import BaseProcessor
from typing import List
from crawlers.base_crawler import NewsItem

class Summarizer(BaseProcessor):
    """摘要生成器"""
    
    def __init__(self, max_length: int = 200, model: str = "default"):
        self.max_length = max_length
        self.model = model
    
    def process(self, items: List[NewsItem]) -> List[NewsItem]:
        """生成摘要"""
        for item in items:
            if not item.content:
                item.summary = "无摘要"
                continue
            
            # 调用 OpenClaw 内置模型生成摘要
            summary = self._generate_summary(item.content)
            item.summary = summary
        
        return items
    
    def _generate_summary(self, text: str) -> str:
        """生成摘要（调用 OpenClaw Skill）"""
        # TODO: 实现 OpenClaw Skill 调用
        # 临时实现：截取前 max_length 字
        return text[:self.max_length] + "..." if len(text) > self.max_length else text
```

---

### 3.3 分类器

```python
# src/processors/classifier.py

from .base_processor import BaseProcessor
from typing import List, Dict
from crawlers.base_crawler import NewsItem

class Classifier(BaseProcessor):
    """自动分类器"""
    
    def __init__(self, domain_config: Dict):
        self.domain_config = domain_config
        self.keyword_map = self._build_keyword_map()
    
    def process(self, items: List[NewsItem]) -> List[NewsItem]:
        """自动分类"""
        for item in items:
            category = self._classify(item)
            item.category = category
        
        return items
    
    def _classify(self, item: NewsItem) -> str:
        """分类逻辑"""
        text = f"{item.title} {item.content}".lower()
        
        # 关键词匹配
        for domain_id, config in self.domain_config['domains'].items():
            if not config.get('enabled', False):
                continue
            
            keywords = config.get('keywords', [])
            if any(kw.lower() in text for kw in keywords):
                return domain_id
        
        return 'uncategorized'
    
    def _build_keyword_map(self) -> Dict:
        """构建关键词映射"""
        keyword_map = {}
        for domain_id, config in self.domain_config['domains'].items():
            for keyword in config.get('keywords', []):
                keyword_map[keyword.lower()] = domain_id
        return keyword_map
```

---

## 4. 处理流水线

### 4.1 流水线实现

```python
# src/processors/pipeline.py

from typing import List
from crawlers.base_crawler import NewsItem
from .deduplicator import Deduplicator
from .summarizer import Summarizer
from .classifier import Classifier

class ProcessingPipeline:
    """处理流水线"""
    
    def __init__(self, config: Dict):
        self.deduplicator = Deduplicator(retention_days=30)
        self.summarizer = Summarizer(max_length=200)
        self.classifier = Classifier(config)
    
    def process(self, items: List[NewsItem]) -> List[NewsItem]:
        """完整处理流程"""
        # 1. 去重
        items = self.deduplicator.process(items)
        
        # 2. 生成摘要
        items = self.summarizer.process(items)
        
        # 3. 分类
        items = self.classifier.process(items)
        
        return items
```

---

## 5. 数据流

```
爬虫层 (List[NewsItem])
    ↓
去重处理器 (Deduplicator)
    ↓
摘要生成器 (Summarizer)
    ↓
分类器 (Classifier)
    ↓
存储层
```

---

## 6. 错误处理

### 6.1 降级策略

```python
# 摘要生成失败 → 使用原文前 200 字
try:
    summary = generate_summary(content)
except Exception:
    summary = content[:200] + "..."

# 分类失败 → 标记为"未分类"
category = classify(item) or "uncategorized"
```

---

## 7. 测试策略

### 7.1 单元测试

```python
# tests/processors/test_deduplicator.py

def test_deduplicator_removes_duplicates():
    """测试去重功能"""
    dedup = Deduplicator()
    items = [
        NewsItem(title="Test", url="http://a.com", fingerprint="abc"),
        NewsItem(title="Test", url="http://a.com", fingerprint="abc"),  # 重复
    ]
    result = dedup.process(items)
    assert len(result) == 1

def test_summarizer_generates_summary():
    """测试摘要生成"""
    summ = Summarizer(max_length=50)
    items = [NewsItem(content="A" * 100)]
    result = summ.process(items)
    assert len(result[0].summary) <= 53  # 50 + "..."
```

---

## 8. 验收标准

### 8.1 功能验收

- [ ] 去重准确率 >95%
- [ ] 摘要生成正常
- [ ] 分类准确
- [ ] 流水线正常工作

### 8.2 性能验收

- [ ] 处理 100 条数据 <1 分钟
- [ ] 内存使用 <100MB

---

## 9. 依赖关系

```
处理层
├── 依赖：爬虫层（NewsItem）
├── 被依赖：存储层
└── 内部依赖：无（各处理器独立）
```

---

**评审状态**: 待评审  
**同步状态**: 未同步

---

**创建人**: DevMate  
**创建时间**: 2026-03-29  
**下次更新**: 评审通过后
