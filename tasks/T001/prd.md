# PRD: 数据源服务模块

## Overview

统一的数据源服务层，整合 AKShare、通达信等多种数据源，为上层业务提供标准化的数据接口。

## Goals

- 统一多数据源接口
- 支持实时行情和历史数据
- 提供数据缓存机制
- 支持数据源热切换

## Quality Gates

- `pytest tests/test_data_source.py` - 数据源测试
- `mypy src/data_source` - 类型检查

## User Stories

### US-001: AKShare数据源集成
**Description:** As a 开发者, I want 通过统一接口调用AKShare获取A股行情数据 so that 系统可以获取股票基础数据.

**Acceptance Criteria:**
- [ ] 实现股票列表获取
- [ ] 实现实时行情获取
- [ ] 实现历史K线获取
- [ ] 实现财务数据获取

### US-002: 通达信实时行情接口
**Description:** As a 开发者, I want 获取通达信实时行情数据 so that 系统可以获取高频实时数据.

**Acceptance Criteria:**
- [ ] 实现通达信接口连接
- [ ] 实现实时行情订阅
- [ ] 实现行情数据解析

### US-003: 通达信历史数据导入
**Description:** As a 开发者, I want 导入通达信历史行情数据 so that 系统可以快速回测.

**Acceptance Criteria:**
- [ ] 支持读取通达信本地数据文件
- [ ] 支持批量导入历史数据
- [ ] 数据格式标准化转换

### US-004: 统一数据接口
**Description:** As a 开发者, I want 统一的数据访问接口 so that 上层业务不关心数据源细节.

**Acceptance Criteria:**
- [ ] 定义统一的数据模型
- [ ] 实现数据源适配器模式
- [ ] 提供数据源选择配置

## Technical Considerations

### 数据模型
```python
@dataclass
class StockInfo:
    code: str           # 股票代码
    name: str           # 股票名称
    market: str         # 市场 (SH/SZ)
    industry: str       # 行业
    concepts: List[str] # 概念标签

@dataclass
class MarketData:
    code: str
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: int
    amount: float
```

### 数据源适配器
```python
class DataSourceAdapter(ABC):
    @abstractmethod
    def get_stock_list(self) -> List[StockInfo]: ...
    @abstractmethod
    def get_realtime_quote(self, codes: List[str]) -> List[Quote]: ...
    @abstractmethod
    def get_history_kline(self, code: str, start: date, end: date) -> List[Kline]: ...
```

## Non-Goals

- 港股、美股数据支持（后续扩展）
- 期货行情数据
- 数据清洗和异常处理的高级功能