# 电商商品数据分析系统 — 错误处理策略

| 属性 | 值 |
|------|-----|
| **版本** | 1.0.0 |
| **创建日期** | 2026-03-26 |
| **最后更新** | 2026-03-26 |
| **状态** | 已发布 |
| **作者** | OpenClaw Architecture Team |
| **相关文档** | [[2026-03-26-ecommerce-analysis-system]] |

---

## 变更记录

| 版本 | 日期 | 作者 | 变更描述 |
|------|------|------|---------|
| 1.0.0 | 2026-03-26 | OpenClaw Architecture Team | 初始版本（从主架构文档分离） |

---

## 1. 概述

### 1.1 目标

本文档定义电商商品数据分析系统的错误处理框架，确保系统在面临各种故障时能够：

1. **自动恢复** — 瞬时错误自动重试恢复
2. **优雅降级** — 系统性故障时保持核心功能
3. **可追溯** — 所有错误有完整日志记录
4. **可告警** — 关键错误及时通知相关人员

### 1.2 适用范围

本文档适用于所有模块的错误处理设计与实现：
- 爬虫模块（Playwright 爬取）
- AI Agent 模块（LLM 调用、Agent 协作）
- 数据存储模块（文件系统、Redis、Memory-Core）

---

## 2. 错误分类框架

系统错误分为四类，每类对应不同处理策略：

| 错误类型 | 定义 | 示例 | 处理策略 |
|---------|------|------|---------|
| **Transient（瞬时错误）** | 临时性、可自动恢复的错误 | 网络抖动、临时 HTTP 429 限流、DNS 解析失败 | 指数退避重试（最多 3 次） |
| **Permanent（永久错误）** | 不可恢复的错误 | URL 无效（404）、HTML 结构变化导致解析失败、API 认证失败 | 记录错误日志，跳过继续处理 |
| **Systematic（系统性错误）** | 影响整体服务的错误 | API 配额耗尽、LLM 服务不可用、Redis 连接失败 | 熔断器模式（15 分钟），降级至缓存 |
| **Timeout（超时错误）** | 操作超过阈值时间 | 爬取超时（>30s）、LLM 响应超时（>60s）、数据库查询超时 | 重试（2 次），回退至部分结果 |

### 2.1 错误识别指南

**判断流程图**：

```
错误发生
    │
    ▼
┌─────────────────┐
│ 是否可自动恢复？ │
└─────────────────┘
    │
    ├─ 是 → Transient（重试）
    │
    └─ 否 → 是否影响整体服务？
              │
              ├─ 是 → Systematic（熔断 + 降级）
              │
              └─ 否 → Permanent（记录 + 跳过）

超时单独处理 → Timeout（重试 + 回退）
```

---

## 3. 重试机制（指数退避）

### 3.1 重试策略

| 参数 | 值 | 说明 |
|------|------|------|
| **适用场景** | Transient 错误、Timeout 错误 | — |
| **最大重试次数** | 3 次 | 避免无限重试 |
| **退避公式** | `delay = base_delay * (2 ^ attempt) + random(0, 1)` | 指数增长 + 随机抖动 |
| **基础延迟** | 1 秒 | 首次重试延迟 |
| **最大延迟** | 60 秒 | 防止延迟过长 |

### 3.2 重试时序

```
第 1 次失败 → 等待 1-2 秒 → 第 2 次尝试
第 2 次失败 → 等待 2-3 秒 → 第 3 次尝试
第 3 次失败 → 等待 4-5 秒 → 第 4 次尝试
第 4 次失败 → 标记为永久失败，记录日志
```

### 3.3 完整实现代码

```python
import time
import random
import logging
from typing import Callable, Any, Optional, Tuple

logger = logging.getLogger(__name__)

class MaxRetriesExceeded(Exception):
    """超过最大重试次数异常"""
    pass

def retry_with_exponential_backoff(
    func: Callable,
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exceptions: Tuple[type, ...] = (Exception,),
    logger: Optional[logging.Logger] = None
) -> Any:
    """
    指数退避重试装饰器
    
    Args:
        func: 要执行的函数
        max_retries: 最大重试次数（默认 3 次）
        base_delay: 基础延迟（秒，默认 1 秒）
        max_delay: 最大延迟（秒，默认 60 秒）
        exceptions: 需要重试的异常类型（默认捕获所有异常）
        logger: 日志记录器（可选）
        
    Returns:
        函数执行结果
        
    Raises:
        MaxRetriesExceeded: 超过最大重试次数
        
    示例:
        >>> @retry_with_exponential_backoff(max_retries=3)
        ... def crawl_product(url: str) -> dict:
        ...     # 爬取逻辑
        ...     pass
        
        >>> # 或使用装饰器
        >>> result = retry_with_exponential_backoff(
        ...     crawl_product,
        ...     max_retries=3,
        ...     exceptions=(ConnectionError, TimeoutError)
        ... )
    """
    logger = logger or logging.getLogger(__name__)
    last_exception = None
    
    for attempt in range(max_retries + 1):
        try:
            return func()
        except exceptions as e:
            last_exception = e
            
            if attempt == max_retries:
                break
                
            # 计算延迟：指数退避 + 随机抖动
            delay = min(base_delay * (2 ** attempt) + random.uniform(0, 1), max_delay)
            logger.warning(
                f"第{attempt + 1}次失败，{delay:.2f}秒后重试：{type(e).__name__}: {e}"
            )
            time.sleep(delay)
    
    raise MaxRetriesExceeded(
        f"超过最大重试次数{max_retries}, 最后错误：{type(last_exception).__name__}: {last_exception}"
    )
```

### 3.4 使用示例

**爬虫模块**：
```python
from src.utils.retry import retry_with_exponential_backoff

@retry_with_exponential_backoff(
    max_retries=3,
    base_delay=1.0,
    exceptions=(ConnectionError, TimeoutError, HTTPError)
)
def crawl_product(url: str) -> dict:
    """
    爬取商品数据（带重试）
    
    自动处理：
    - 网络连接失败
    - 请求超时
    - HTTP 错误（502, 503, 504）
    """
    # 爬取逻辑
    pass
```

**LLM 调用**：
```python
@retry_with_exponential_backoff(
    max_retries=2,
    base_delay=2.0,
    exceptions=(TimeoutError, RateLimitError)
)
def call_llm_api(prompt: str) -> dict:
    """
    调用 LLM API（带重试）
    
    自动处理：
    - API 超时
    - 速率限制（429）
    """
    # LLM 调用逻辑
    pass
```

---

## 4. 熔断器模式

### 4.1 熔断器状态机

```
                    失败次数 > 阈值
    ┌─────────────────────────────────┐
    │                                 ▼
┌─────────┐    超时      ┌─────────┐  探测请求
│ CLOSED  │ ───────────▶ │  OPEN   │ ─────────┐
│ (正常)  │              │ (熔断)  │          │
└─────────┘              └─────────┘          │
    ▲                                         │
    │      探测成功                           ▼
    │          ┌─────────┐              ┌─────────────┐
    └─────────│ HALF_   │◀─────────────│  等待恢复   │
              │  OPEN   │              │  (15 分钟)   │
              │ (试探)  │              └─────────────┘
              └─────────┘
```

### 4.2 状态说明

| 状态 | 说明 | 行为 | 转换条件 |
|------|------|------|---------|
| **CLOSED（正常）** | 系统正常运行 | 所有请求正常处理，失败计数累加 | 失败次数 > 阈值 → OPEN |
| **OPEN（熔断）** | 系统已熔断 | 拒绝所有请求，直接返回降级响应 | 超时 → HALF_OPEN |
| **HALF_OPEN（试探）** | 试探性恢复 | 允许 1 个探测请求 | 成功 → CLOSED / 失败 → OPEN |

### 4.3 配置参数

**推荐配置**：
```yaml
# 熔断器配置
circuit_breaker:
  failure_threshold: 5        # 失败次数阈值（触发熔断）
  recovery_timeout: 900       # 恢复超时（15 分钟）
  half_open_max_calls: 1      # 试探模式最大请求数
  success_threshold: 2        # 试探成功次数（恢复条件）
```

**参数调优指南**：
| 参数 | 调大效果 | 调小效果 | 默认值 |
|------|---------|---------|--------|
| `failure_threshold` | 更难点熔断 | 更易熔断 | 5 |
| `recovery_timeout` | 熔断时间更长 | 更快尝试恢复 | 900s |
| `success_threshold` | 更难恢复正常 | 更快恢复正常 | 2 |

### 4.4 完整实现代码

```python
from enum import Enum
from datetime import datetime, timedelta
from threading import Lock
from typing import Callable, Any

class CircuitState(Enum):
    """熔断器状态"""
    CLOSED = "closed"      # 正常
    OPEN = "open"          # 熔断
    HALF_OPEN = "half_open" # 试探

class CircuitOpenError(Exception):
    """熔断器已打开异常"""
    pass

class CircuitBreaker:
    """
    熔断器实现
    
    使用示例:
        >>> breaker = CircuitBreaker(failure_threshold=5)
        >>> 
        >>> @breaker.call
        >>> def call_llm_api(prompt: str) -> dict:
        ...     # LLM 调用逻辑
        ...     pass
    """
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: int = 900,
        success_threshold: int = 2,
        half_open_max_calls: int = 1,
        name: str = "default"
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout  # 秒
        self.success_threshold = success_threshold
        self.half_open_max_calls = half_open_max_calls
        self.name = name
        
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time = None
        self._half_open_calls = 0
        self._lock = Lock()
    
    def call(self, func: Callable, *args, **kwargs) -> Any:
        """
        执行受保护的函数调用
        
        Args:
            func: 要执行的函数
            *args: 函数参数
            **kwargs: 函数关键字参数
            
        Returns:
            函数执行结果
            
        Raises:
            CircuitOpenError: 熔断器已打开
        """
        with self._lock:
            if self._state == CircuitState.OPEN:
                if self._should_attempt_reset():
                    self._state = CircuitState.HALF_OPEN
                    self._half_open_calls = 0
                    self._success_count = 0
                else:
                    raise CircuitOpenError(
                        f"熔断器已打开 [{self.name}]，将在 {self._get_remaining_timeout():.0f} 秒后重试"
                    )
            
            if self._state == CircuitState.HALF_OPEN:
                if self._half_open_calls >= self.half_open_max_calls:
                    raise CircuitOpenError(
                        f"熔断器试探中 [{self.name}]，请稍后重试"
                    )
                self._half_open_calls += 1
        
        try:
            result = func(*args, **kwargs)
            self._on_success()
            return result
        except Exception as e:
            self._on_failure()
            raise
    
    def _on_success(self):
        """成功回调"""
        with self._lock:
            if self._state == CircuitState.HALF_OPEN:
                self._success_count += 1
                if self._success_count >= self.success_threshold:
                    self._reset()
            else:
                self._failure_count = 0
    
    def _on_failure(self):
        """失败回调"""
        with self._lock:
            self._failure_count += 1
            self._last_failure_time = datetime.now()
            
            if self._state == CircuitState.HALF_OPEN:
                self._state = CircuitState.OPEN
            elif self._failure_count >= self.failure_threshold:
                self._state = CircuitState.OPEN
                logging.warning(f"熔断器已打开 [{self.name}]")
    
    def _should_attempt_reset(self) -> bool:
        """判断是否可以尝试重置"""
        if self._last_failure_time is None:
            return True
        elapsed = (datetime.now() - self._last_failure_time).total_seconds()
        return elapsed >= self.recovery_timeout
    
    def _get_remaining_timeout(self) -> float:
        """获取剩余熔断时间（秒）"""
        if self._last_failure_time is None:
            return 0
        elapsed = (datetime.now() - self._last_failure_time).total_seconds()
        return max(0, self.recovery_timeout - elapsed)
    
    def _reset(self):
        """重置熔断器"""
        with self._lock:
            self._state = CircuitState.CLOSED
            self._failure_count = 0
            self._success_count = 0
            self._half_open_calls = 0
            logging.info(f"熔断器已恢复 [{self.name}]")
    
    @property
    def state(self) -> CircuitState:
        """获取当前状态"""
        return self._state
```

### 4.5 使用示例

**LLM API 熔断**：
```python
from src.utils.circuit_breaker import CircuitBreaker, CircuitOpenError

# 创建熔断器实例
llm_circuit_breaker = CircuitBreaker(
    failure_threshold=5,
    recovery_timeout=900,
    name="llm_api"
)

def analyze_with_fallback(product_data: dict) -> dict:
    """
    带熔断的分析流程
    """
    try:
        # 通过熔断器调用 LLM API
        return llm_circuit_breaker.call(
            call_llm_api,
            prompt=build_analysis_prompt(product_data)
        )
    except CircuitOpenError:
        # 熔断器打开，降级至缓存
        return get_cached_analysis(product_data['id'])
```

---

## 5. 降级策略

### 5.1 降级场景

| 场景 | 降级方案 | 触发条件 | 降级效果 |
|------|---------|---------|---------|
| **LLM 服务不可用** | 使用缓存的分析结果 | 熔断器打开，或连续 3 次超时 | 返回最近一次成功分析 |
| **爬虫失败率 > 50%** | 切换至备用数据源（如 API） | 10 分钟内失败率超过阈值 | 使用 API 数据替代爬取 |
| **Redis 不可用** | 降级至内存缓存 | 连接失败，自动跳过 Redis | 临时缓存（进程级别） |
| **存储空间不足** | 仅保存最近 7 天数据 | 磁盘使用率 > 90% | 清理旧数据 |

### 5.2 降级代码示例

**LLM 降级**：
```python
def analyze_with_fallback(product_data: dict) -> dict:
    """
    带降级的分析流程
    
    优先级：
    1. 调用 LLM API 进行实时分析
    2. LLM 失败 → 使用缓存结果
    3. 缓存失效 → 返回简化分析
    
    Returns:
        分析结果（始终有返回值）
    """
    cache_key = f"analysis:{product_data['id']}"
    
    # 尝试实时分析
    try:
        result = llm_circuit_breaker.call(
            call_llm_api,
            prompt=build_analysis_prompt(product_data)
        )
        # 成功则缓存结果
        redis_client.set(cache_key, json.dumps(result), ex=3600)
        return result
        
    except CircuitOpenError:
        logger.warning("LLM 熔断，尝试缓存降级")
    
    # 尝试缓存
    cached = redis_client.get(cache_key)
    if cached:
        logger.info("使用缓存分析结果")
        return {**json.loads(cached), "source": "cache"}
    
    # 返回简化分析
    logger.warning("降级至简化分析")
    return {
        "product_id": product_data["id"],
        "sentiment_score": 0.5,  # 中性默认值
        "price_trend": "unknown",
        "source": "fallback"
    }
```

---

## 6. 错误日志与告警

### 6.1 日志格式

**结构化日志配置**：
```python
import logging
import json
from datetime import datetime

# 结构化日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(name)s | %(message)s',
    handlers=[
        logging.FileHandler('logs/error.log'),
        logging.StreamHandler()
    ]
)

class ErrorLogger:
    """错误日志记录器"""
    
    @staticmethod
    def log_error(
        error_type: str,
        module: str,
        details: dict,
        exception: Exception = None
    ):
        """记录结构化错误日志"""
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "error_type": error_type,
            "module": module,
            "details": details,
            "exception": str(exception) if exception else None
        }
        logging.error(json.dumps(log_entry, ensure_ascii=False))
```

**使用示例**：
```python
try:
    crawl_product(url)
except Exception as e:
    ErrorLogger.log_error(
        error_type="crawl_failure",
        module="crawler_agent",
        details={"url": url, "attempt": 3},
        exception=e
    )
```

### 6.2 告警规则

| 告警类型 | 触发条件 | 通知渠道 | 优先级 |
|---------|---------|---------|--------|
| **爬取失败率告警** | 10 分钟内失败率 > 30% | 钉钉/企业微信 | P1 |
| **熔断器打开告警** | 任意熔断器状态变为 OPEN | 钉钉/企业微信 + 邮件 | P0 |
| **LLM 超时告警** | 连续 5 次 LLM 调用超时 | 钉钉/企业微信 | P1 |
| **存储空间告警** | 磁盘使用率 > 85% | 邮件 | P2 |

---

## 7. 模块错误处理应用

### 7.1 爬虫模块

**错误处理要点**：
- 网络错误 → 重试 3 次（指数退避）
- 解析错误 → 记录 + 跳过
- 限流（429）→ 等待 + 重试
- 熔断 → 降级至备用数据源

**实现示例**：
```python
@retry_with_exponential_backoff(
    max_retries=3,
    base_delay=1.0,
    exceptions=(ConnectionError, TimeoutError)
)
def crawl_product(url: str) -> dict:
    """爬取商品数据"""
    try:
        # 爬取逻辑
        pass
    except HTTPError as e:
        if e.status_code == 429:
            # 限流，触发重试
            raise TimeoutError("Rate limited")
        elif e.status_code == 404:
            # 永久错误，不重试
            ErrorLogger.log_error(
                error_type="url_not_found",
                module="crawler",
                details={"url": url}
            )
            return None
        else:
            raise
```

### 7.2 Agent 协作模块

**错误处理要点**：
- LLM 超时 → 重试 2 次 + 熔断
- Agent 切换失败 → 降级至默认 Agent
- 上下文丢失 → 重建上下文

**实现示例**：
```python
def orchestrate_analysis(urls: list) -> dict:
    """编排分析流程"""
    try:
        # 调用各专业 Agent
        results = []
        for url in urls:
            try:
                result = llm_circuit_breaker.call(
                    call_price_agent, url=url
                )
                results.append(result)
            except CircuitOpenError:
                # 熔断降级
                results.append(get_cached_analysis(url))
        
        return {"status": "success", "results": results}
    
    except Exception as e:
        ErrorLogger.log_error(
            error_type="orchestration_failure",
            module="orchestrator",
            details={"urls_count": len(urls)},
            exception=e
        )
        return {"status": "failed", "error": str(e)}
```

### 7.3 存储模块

**错误处理要点**：
- Redis 不可用 → 降级至内存缓存
- 磁盘空间不足 → 清理旧数据
- 写入失败 → 重试 + 告警

---

## 8. 测试建议

### 8.1 单元测试

**测试重试机制**：
```python
def test_retry_exceeds_max():
    """测试超过最大重试次数"""
    mock_func = Mock(side_effect=ConnectionError("始终失败"))
    
    with pytest.raises(MaxRetriesExceeded):
        retry_with_exponential_backoff(
            mock_func,
            max_retries=3,
            exceptions=(ConnectionError,)
        )
    
    assert mock_func.call_count == 4  # 初始 + 3 次重试
```

**测试熔断器**：
```python
def test_circuit_breaker_opens():
    """测试熔断器打开"""
    breaker = CircuitBreaker(failure_threshold=3)
    mock_func = Mock(side_effect=Exception("失败"))
    
    # 连续失败 3 次
    for _ in range(3):
        try:
            breaker.call(mock_func)
        except:
            pass
    
    # 验证熔断器已打开
    assert breaker.state == CircuitState.OPEN
    
    # 验证拒绝新请求
    with pytest.raises(CircuitOpenError):
        breaker.call(mock_func)
```

### 8.2 集成测试

**测试降级流程**：
```python
def test_analyze_with_fallback():
    """测试分析降级流程"""
    # Mock LLM API 失败
    with patch('call_llm_api', side_effect=TimeoutError):
        result = analyze_with_fallback(product_data)
        
        # 验证降级至缓存
        assert result["source"] in ["cache", "fallback"]
```

---

## 相关链接

- [主架构文档](./2026-03-26-ecommerce-analysis-system.md)
- [测试策略文档](./TESTING-STRATEGY.md)
- [ADR-004：错误处理与测试策略](decisions/ADR-004-error-handling-and-testing.md)

---

**文档结束**
