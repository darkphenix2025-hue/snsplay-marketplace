# PRD: 策略回测模块

## Overview

基于 BackTrader 框架的策略回测功能，支持自定义策略编写和回测结果展示。

## Goals

- 集成 BackTrader 框架
- 支持自定义策略编写
- 提供回测结果可视化

## Quality Gates

- `pytest tests/test_backtest.py` - 回测测试
- `mypy src/backtest` - 类型检查

## User Stories

### US-001: BackTrader框架集成
**Description:** As a 开发者, I want 集成BackTrader框架 so that 系统可以运行策略回测.

**Acceptance Criteria:**
- [ ] 集成BackTrader库
- [ ] 实现数据源适配
- [ ] 实现回测引擎封装

### US-002: 自定义策略引擎
**Description:** As a 投资者, I want 编写自定义策略 so that 我可以回测我的交易想法.

**Acceptance Criteria:**
- [ ] 定义策略模板接口
- [ ] 支持策略参数配置
- [ ] 提供策略示例库

### US-003: 回测结果展示
**Description:** As a 投资者, I want 看到回测结果 so that 我可以评估策略效果.

**Acceptance Criteria:**
- [ ] 显示收益曲线图
- [ ] 显示回测统计指标
- [ ] 显示交易记录明细
- [ ] 支持导出回测报告

## Technical Considerations

### 策略模板
```python
class BaseStrategy(bt.Strategy):
    params = (
        ('period', 20),
    )

    def __init__(self):
        # 初始化指标
        pass

    def next(self):
        # 策略逻辑
        pass
```

### 回测指标
- 总收益率
- 年化收益率
- 最大回撤
- 夏普比率
- 胜率

## Non-Goals

- 实盘自动交易
- 高频策略支持