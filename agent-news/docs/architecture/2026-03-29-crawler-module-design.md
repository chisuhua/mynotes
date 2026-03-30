# 爬虫模块详细设计

**创建时间**: 2026-03-29  
**版本**: v1.0 草案  
**状态**: 待评审

---

## 1. 模块概述

### 1.1 职责

爬虫层负责从 4 个数据源抓取智能体领域讯息：
- arXiv（学术论文）
- GitHub（代码仓库）
- Blogs（技术博客）
- Social（社交媒体）

### 1.2 设计原则

- **统一接口** - 所有爬虫实现相同接口
- **独立实现** - 每个爬虫独立，互不影响
- **速率限制** - 遵守各平台速率限制
- **错误重试** - 支持自动重试机制

---

## 2. 接口定义

### 2.1 基础爬虫类

```python
# src/crawlers/base_crawler.py

from abc import ABC, abstractmethod
from typing import List, Dict, Optional
from dataclasses import dataclass

@dataclass
class NewsItem:
    """讯息项数据结构"""
    title: str
    url: str
    source: str
    domain: str
    content: str
    published_at: str
    fingerprint: str
    raw_data: Dict

class BaseCrawler(ABC):
    """爬虫基类"""
    
    def __init__(self, rate_limit: int = 60):
        self.rate_limit = rate_limit  # 请求数/小时
        self.last_request_time = 0
    
    @abstractmethod
    def fetch(self, keywords: List[str]) -> List[NewsItem]:
        """抓取数据"""
        pass
    
    @abstractmethod
    def parse(self, raw_data: Dict) -> NewsItem:
        """解析数据"""
        pass
    
    def _respect_rate_limit(self):
        """遵守速率限制"""
        # 实现速率限制逻辑
        pass
```

---

## 3. 爬虫实现

### 3.1 arXiv 爬虫

```python
# src/crawlers/arxiv_crawler.py

from .base_crawler import BaseCrawler, NewsItem
import requests
from datetime import datetime

class ArxivCrawler(BaseCrawler):
    """arXiv 论文爬虫"""
    
    def __init__(self):
        super().__init__(rate_limit=100)
        self.api_url = "https://export.arxiv.org/api/query"
    
    def fetch(self, keywords: List[str]) -> List[NewsItem]:
        """抓取 arXiv 论文"""
        # 构建查询
        query = " OR ".join([f'all:{kw}' for kw in keywords])
        params = {
            'search_query': query,
            'start': 0,
            'max_results': 50,
            'sortBy': 'submittedDate',
            'sortOrder': 'descending'
        }
        
        # 发送请求
        response = requests.get(self.api_url, params=params)
        response.raise_for_status()
        
        # 解析结果
        items = []
        for entry in self._parse_feed(response.text):
            items.append(self.parse(entry))
        
        return items
    
    def parse(self, raw_data: Dict) -> NewsItem:
        """解析论文数据"""
        return NewsItem(
            title=raw_data.get('title'),
            url=raw_data.get('pdf_url'),
            source='arxiv',
            domain='cs.AI',
            content=raw_data.get('summary'),
            published_at=raw_data.get('published'),
            fingerprint=self._generate_fingerprint(raw_data),
            raw_data=raw_data
        )
```

---

### 3.2 GitHub 爬虫

```python
# src/crawlers/github_crawler.py

from .base_crawler import BaseCrawler, NewsItem
import requests

class GithubCrawler(BaseCrawler):
    """GitHub Trending 爬虫"""
    
    def __init__(self):
        super().__init__(rate_limit=60)
        self.trending_url = "https://github.com/trending"
    
    def fetch(self, keywords: List[str]) -> List[NewsItem]:
        """抓取 GitHub Trending"""
        # 获取 Trending 页面
        response = requests.get(self.trending_url)
        response.raise_for_status()
        
        # 解析 HTML
        items = []
        for repo in self._parse_html(response.text):
            # 过滤相关仓库
            if self._match_keywords(repo, keywords):
                items.append(self.parse(repo))
        
        return items
    
    def parse(self, raw_data: Dict) -> NewsItem:
        """解析仓库数据"""
        return NewsItem(
            title=raw_data.get('name'),
            url=raw_data.get('url'),
            source='github',
            domain='agent',
            content=raw_data.get('description'),
            published_at=raw_data.get('updated_at'),
            fingerprint=self._generate_fingerprint(raw_data),
            raw_data=raw_data
        )
```

---

### 3.3 Blogs 爬虫

```python
# src/crawlers/blog_crawler.py

from .base_crawler import BaseCrawler, NewsItem
import feedparser

class BlogCrawler(BaseCrawler):
    """技术博客爬虫（RSS）"""
    
    def __init__(self):
        super().__init__(rate_limit=30)
        self.feeds = [
            "https://openai.com/blog/feed",
            "https://www.anthropic.com/news/feed",
            "https://clawhub.ai/feed"
        ]
    
    def fetch(self, keywords: List[str]) -> List[NewsItem]:
        """抓取博客文章"""
        items = []
        for feed_url in self.feeds:
            feed = feedparser.parse(feed_url)
            for entry in feed.entries:
                if self._match_keywords(entry, keywords):
                    items.append(self.parse(entry))
        
        return items
    
    def parse(self, raw_data: Dict) -> NewsItem:
        """解析博客文章"""
        return NewsItem(
            title=raw_data.get('title'),
            url=raw_data.get('link'),
            source='blog',
            domain='ai-news',
            content=raw_data.get('summary'),
            published_at=raw_data.get('published'),
            fingerprint=self._generate_fingerprint(raw_data),
            raw_data=raw_data
        )
```

---

### 3.4 Social 爬虫

```python
# src/crawlers/social_crawler.py

from .base_crawler import BaseCrawler, NewsItem

class SocialCrawler(BaseCrawler):
    """社交媒体爬虫"""
    
    def __init__(self):
        super().__init__(rate_limit=50)
        # TODO: 实现 Twitter/Reddit API 集成
    
    def fetch(self, keywords: List[str]) -> List[NewsItem]:
        """抓取社交媒体"""
        # TODO: 实现
        return []
    
    def parse(self, raw_data: Dict) -> NewsItem:
        """解析社交媒体数据"""
        # TODO: 实现
        pass
```

---

## 4. 工具函数

### 4.1 指纹生成

```python
# src/crawlers/utils.py

import hashlib

def generate_fingerprint(title: str, url: str, date: str) -> str:
    """生成讯息指纹（用于去重）"""
    content = f"{title}|{url}|{date}"
    return hashlib.md5(content.encode()).hexdigest()
```

### 4.2 关键词匹配

```python
def match_keywords(item: Dict, keywords: List[str]) -> bool:
    """检查是否匹配关键词"""
    text = f"{item.get('title', '')} {item.get('description', '')}".lower()
    return any(kw.lower() in text for kw in keywords)
```

---

## 5. 错误处理

### 5.1 异常类型

```python
# src/crawlers/exceptions.py

class CrawlerError(Exception):
    """爬虫通用异常"""
    pass

class RateLimitError(CrawlerError):
    """速率限制错误"""
    pass

class ParseError(CrawlerError):
    """解析错误"""
    pass
```

### 5.2 重试策略

```python
# src/crawlers/retry.py

from functools import wraps
import time

def retry_with_backoff(max_retries=3, base_delay=1.0):
    """指数退避重试装饰器"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for i in range(max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if i == max_retries:
                        raise
                    delay = base_delay * (2 ** i)
                    time.sleep(delay)
        return wrapper
    return decorator
```

---

## 6. 测试策略

### 6.1 单元测试

```python
# tests/crawlers/test_arxiv_crawler.py

def test_arxiv_fetch():
    """测试 arXiv 抓取"""
    crawler = ArxivCrawler()
    items = crawler.fetch(["AI Agent"])
    assert len(items) > 0
    assert all(isinstance(item, NewsItem) for item in items)

def test_arxiv_parse():
    """测试 arXiv 解析"""
    crawler = ArxivCrawler()
    raw_data = {...}  # Mock 数据
    item = crawler.parse(raw_data)
    assert item.source == 'arxiv'
```

### 6.2 Mock 策略

```python
# tests/crawlers/conftest.py

import pytest

@pytest.fixture
def mock_arxiv_response():
    """Mock arXiv API 响应"""
    return """<?xml version="1.0"?>
    <feed>...</feed>"""
```

---

## 7. 验收标准

### 7.1 功能验收

- [ ] 4 个爬虫都能正常抓取数据
- [ ] 速率限制正常工作
- [ ] 错误重试机制有效
- [ ] 指纹生成一致

### 7.2 质量验收

- [ ] 单元测试覆盖率 >80%
- [ ] 无循环依赖
- [ ] 接口设计合理

---

## 8. 依赖关系

```
爬虫层
├── 依赖：requests, feedparser
├── 被依赖：处理层（Deduplicator）
└── 无内部依赖（各爬虫独立）
```

---

**评审状态**: 待评审  
**同步状态**: 未同步

---

**创建人**: DevMate  
**创建时间**: 2026-03-29  
**下次更新**: 评审通过后
