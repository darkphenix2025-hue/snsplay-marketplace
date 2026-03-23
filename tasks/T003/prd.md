# PRD: 投资组合管理模块

## Overview

投资组合管理功能，支持手动录入持仓、追踪收益、展示持仓明细。

## Goals

- 支持持仓记录管理
- 自动计算收益
- 提供持仓汇总视图

## Quality Gates

- `pytest tests/test_portfolio.py` - 组合管理测试
- `mypy src/portfolio` - 类型检查

## User Stories

### US-001: 持仓数据模型
**Description:** As a 开发者, I want 定义持仓数据模型 so that 系统可以存储和管理持仓数据.

**Acceptance Criteria:**
- [ ] 定义Position数据模型
- [ ] 定义Portfolio聚合模型
- [ ] 实现数据持久化

### US-002: 持仓管理API
**Description:** As a 投资者, I want 管理持仓记录 so that 我可以追踪我的投资.

**Acceptance Criteria:**
- [ ] 实现添加持仓接口
- [ ] 实现编辑持仓接口
- [ ] 实现删除持仓接口
- [ ] 实现查询持仓接口

### US-003: 收益计算服务
**Description:** As a 投资者, I want 看到持仓收益 so that 我了解投资表现.

**Acceptance Criteria:**
- [ ] 计算持仓成本
- [ ] 计算浮动盈亏
- [ ] 计算收益率
- [ ] 计算持仓占比

## Technical Considerations

### 数据模型
```python
@dataclass
class Position:
    id: str
    code: str           # 股票代码
    name: str           # 股票名称
    shares: int         # 持仓股数
    cost_price: float   # 成本价
    buy_date: date      # 买入日期
    notes: str          # 备注

@dataclass
class Portfolio:
    id: str
    name: str
    positions: List[Position]
    created_at: datetime
    updated_at: datetime
```

## Non-Goals

- 券商账户自动同步
- 分红送股自动调整