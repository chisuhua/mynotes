# 存储模块详细设计

**创建时间**: 2026-03-29  
**版本**: v1.0 草案  
**状态**: 待评审

---

## 1. 模块概述

### 1.1 职责

存储层负责持久化处理后的数据：
- **SQLite 数据库** - 结构化存储
- **Markdown 文件** - 报告输出
- **JSON 缓存** - 原始数据备份

### 1.2 设计原则

- **多格式存储** - 支持数据库/文件/缓存
- **事务支持** - 数据库操作支持事务
- **版本控制** - Markdown 报告支持 Git 版本控制

---

## 2. 数据库设计

### 2.1 Schema

```sql
-- 讯息表
CREATE TABLE news_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    url TEXT UNIQUE NOT NULL,
    source TEXT NOT NULL,
    domain TEXT,
    summary TEXT,
    category TEXT,
    fingerprint TEXT UNIQUE NOT NULL,
    content TEXT,
    published_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 索引
CREATE INDEX idx_category ON news_items(category);
CREATE INDEX idx_domain ON news_items(domain);
CREATE INDEX idx_published_at ON news_items(published_at);
CREATE INDEX idx_fingerprint ON news_items(fingerprint);

-- 去重历史表
CREATE TABLE dedup_history (
    fingerprint TEXT PRIMARY KEY,
    title TEXT,
    url TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 索引
CREATE INDEX idx_dedup_created ON dedup_history(created_at);
```

---

## 3. 存储实现

### 3.1 数据库存储

```python
# src/storage/database.py

import sqlite3
from typing import List, Optional
from datetime import datetime
from crawlers.base_crawler import NewsItem

class NewsDatabase:
    """新闻数据库"""
    
    def __init__(self, db_path: str = "agent_news.db"):
        self.db_path = db_path
        self._init_schema()
    
    def _init_schema(self):
        """初始化数据库 Schema"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 创建表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS news_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                url TEXT UNIQUE NOT NULL,
                source TEXT NOT NULL,
                domain TEXT,
                summary TEXT,
                category TEXT,
                fingerprint TEXT UNIQUE NOT NULL,
                content TEXT,
                published_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # 创建索引
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_category ON news_items(category)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_fingerprint ON news_items(fingerprint)")
        
        conn.commit()
        conn.close()
    
    def insert(self, item: NewsItem) -> bool:
        """插入单条数据"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        try:
            cursor.execute("""
                INSERT OR IGNORE INTO news_items 
                (title, url, source, domain, summary, category, fingerprint, content, published_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                item.title, item.url, item.source, item.domain,
                item.summary, item.category, item.fingerprint,
                item.content, item.published_at
            ))
            conn.commit()
            return cursor.rowcount > 0
        except sqlite3.IntegrityError:
            return False
        finally:
            conn.close()
    
    def insert_batch(self, items: List[NewsItem]) -> int:
        """批量插入"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        count = 0
        for item in items:
            try:
                cursor.execute("""
                    INSERT OR IGNORE INTO news_items 
                    (title, url, source, domain, summary, category, fingerprint, content, published_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    item.title, item.url, item.source, item.domain,
                    item.summary, item.category, item.fingerprint,
                    item.content, item.published_at
                ))
                count += cursor.rowcount
            except sqlite3.IntegrityError:
                continue
        
        conn.commit()
        conn.close()
        return count
    
    def query_by_date(self, date: str) -> List[dict]:
        """按日期查询"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM news_items 
            WHERE DATE(published_at) = ?
            ORDER BY published_at DESC
        """, (date,))
        
        results = [dict(row) for row in cursor.fetchall()]
        conn.close()
        return results
    
    def get_recent_fingerprints(self, days: int = 30) -> List[str]:
        """获取最近 N 天的指纹"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT fingerprint FROM news_items 
            WHERE created_at >= datetime('now', ?)
        """, (f'-{days} days',))
        
        fingerprints = [row[0] for row in cursor.fetchall()]
        conn.close()
        return fingerprints
```

---

### 3.2 Markdown 报告存储

```python
# src/storage/markdown_report.py

from typing import List
from datetime import datetime
from pathlib import Path

class MarkdownReporter:
    """Markdown 报告生成器"""
    
    def __init__(self, output_dir: str = ".acf/status/daily"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def generate_daily_report(self, items: List[dict], date: str = None):
        """生成每日报告"""
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")
        
        report_path = self.output_dir / f"report_{date}.md"
        
        content = f"""# Agent News 每日简报

**日期**: {date}  
**生成时间**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}  
**总数**: {len(items)} 条

---

## 📊 分类统计

{self._generate_category_stats(items)}

## 🔗 原始链接汇总

{self._generate_links(items)}

## 📝 摘要汇总

{self._generate_summaries(items)}

## 📈 趋势分析

{self._generate_trends(items)}

---

**报告生成**: Agent News System
"""
        
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        return report_path
    
    def _generate_category_stats(self, items: List[dict]) -> str:
        """生成分类统计"""
        from collections import Counter
        categories = Counter(item.get('category', 'uncategorized') for item in items)
        
        lines = ["| 分类 | 数量 |", "|------|------|"]
        for cat, count in categories.most_common():
            lines.append(f"| {cat} | {count} |")
        
        return "\n".join(lines)
    
    def _generate_links(self, items: List[dict]) -> str:
        """生成链接汇总"""
        lines = []
        for item in items:
            lines.append(f"- [{item['title']}]({item['url']}) - {item['source']}")
        return "\n".join(lines)
    
    def _generate_summaries(self, items: List[dict]) -> str:
        """生成摘要汇总"""
        lines = []
        for item in items:
            lines.append(f"### {item['title']}\n\n{item.get('summary', '无摘要')}\n")
        return "\n".join(lines)
    
    def _generate_trends(self, items: List[dict]) -> str:
        """生成趋势分析"""
        # TODO: 实现趋势分析
        return "趋势分析功能开发中..."
```

---

### 3.3 JSON 缓存

```python
# src/storage/json_cache.py

import json
from pathlib import Path
from datetime import datetime

class JsonCache:
    """JSON 原始数据缓存"""
    
    def __init__(self, cache_dir: str = ".acf/cache"):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
    
    def save_raw_data(self, source: str, data: list):
        """保存原始数据"""
        date = datetime.now().strftime("%Y%m%d")
        cache_path = self.cache_dir / f"{source}_{date}.json"
        
        with open(cache_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    
    def load_raw_data(self, source: str, date: str) -> list:
        """加载原始数据"""
        cache_path = self.cache_dir / f"{source}_{date}.json"
        
        if cache_path.exists():
            with open(cache_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        
        return []
```

---

## 4. 存储管理器

### 4.1 统一接口

```python
# src/storage/manager.py

from typing import List
from crawlers.base_crawler import NewsItem
from .database import NewsDatabase
from .markdown_report import MarkdownReporter
from .json_cache import JsonCache

class StorageManager:
    """存储管理器"""
    
    def __init__(self, config: dict):
        self.db = NewsDatabase(config.get('db_path', 'agent_news.db'))
        self.reporter = MarkdownReporter(config.get('output_dir', '.acf/status/daily'))
        self.cache = JsonCache(config.get('cache_dir', '.acf/cache'))
    
    def store(self, items: List[NewsItem], date: str = None):
        """存储数据"""
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")
        
        # 1. 存储到数据库
        count = self.db.insert_batch(items)
        
        # 2. 生成 Markdown 报告
        items_dict = [self._item_to_dict(item) for item in items]
        report_path = self.reporter.generate_daily_report(items_dict, date)
        
        # 3. 缓存原始数据
        by_source = self._group_by_source(items)
        for source, source_items in by_source.items():
            self.cache.save_raw_data(source, [self._item_to_dict(i) for i in source_items])
        
        return {
            'db_count': count,
            'report_path': report_path
        }
    
    def _item_to_dict(self, item: NewsItem) -> dict:
        """转换 NewsItem 为字典"""
        return {
            'title': item.title,
            'url': item.url,
            'source': item.source,
            'domain': item.domain,
            'summary': item.summary,
            'category': item.category,
            'content': item.content,
            'published_at': item.published_at
        }
    
    def _group_by_source(self, items: List[NewsItem]) -> dict:
        """按数据源分组"""
        from collections import defaultdict
        grouped = defaultdict(list)
        for item in items:
            grouped[item.source].append(item)
        return grouped
```

---

## 5. 错误处理

### 5.1 事务回滚

```python
def insert_batch(self, items: List[NewsItem]) -> int:
    """批量插入（带事务）"""
    conn = sqlite3.connect(self.db_path)
    cursor = conn.cursor()
    
    try:
        for item in items:
            cursor.execute("INSERT ...", (...))
        conn.commit()
    except Exception as e:
        conn.rollback()  # 回滚
        raise
    finally:
        conn.close()
```

---

## 6. 测试策略

### 6.1 单元测试

```python
# tests/storage/test_database.py

def test_database_insert():
    """测试数据库插入"""
    db = NewsDatabase(":memory:")  # 内存数据库
    item = NewsItem(...)
    result = db.insert(item)
    assert result == True

def test_database_duplicate():
    """测试重复数据"""
    db = NewsDatabase(":memory:")
    item1 = NewsItem(fingerprint="abc")
    item2 = NewsItem(fingerprint="abc")  # 重复
    db.insert(item1)
    result = db.insert(item2)
    assert result == False
```

---

## 7. 验收标准

### 7.1 功能验收

- [ ] 数据库正常存储
- [ ] Markdown 报告生成
- [ ] JSON 缓存正常
- [ ] 事务回滚正常

### 7.2 性能验收

- [ ] 批量插入 100 条 <1 秒
- [ ] 报告生成 <5 秒

---

## 8. 依赖关系

```
存储层
├── 依赖：处理层（处理后的 NewsItem）
├── 被依赖：输出层
└── 外部依赖：sqlite3
```

---

**评审状态**: 待评审  
**同步状态**: 未同步

---

**创建人**: DevMate  
**创建时间**: 2026-03-29  
**下次更新**: 评审通过后
