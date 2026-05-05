# Requirements: 投资分析系统

## Overview

为个人投资者打造的综合投资分析平台，整合多数据源，提供行情展示、投资组合管理、策略回测等功能。支持 Web 和桌面双端。

## Goals

- 提供实时和历史行情数据展示
- 支持投资组合管理和收益追踪
- 基于 BackTrader 实现策略回测功能
- 整合新闻数据辅助投资决策

## User Stories

### US-001: 数据源集成
**Description:** As a 投资者, I want 系统能获取多个数据源的行情数据 so that 我可以全面了解市场情况.

**Acceptance Criteria:**
- [ ] AKShare 数据源集成成功
- [ ] 通达信实时行情接口集成
- [ ] 通达信历史行情数据导入
- [ ] 新闻数据源集成

### US-002: K线图展示
**Description:** As a 投资者, I want 查看股票K线图 so that 我可以分析价格走势.

**Acceptance Criteria:**
- [ ] 支持日K、周K、月K切换
- [ ] 支持缩放和拖拽
- [ ] 显示成交量

### US-003: 分时图展示
**Description:** As a 投资者, I want 查看当日分时图 so that 我可以把握盘中走势.

**Acceptance Criteria:**
- [ ] 显示当日分时价格曲线
- [ ] 显示均价线
- [ ] 显示成交量柱状图

### US-004: 技术指标图
**Description:** As a 投资者, I want 在K线图上叠加技术指标 so that 我可以进行技术分析.

**Acceptance Criteria:**
- [ ] 支持常见指标：MA、MACD、KDJ、RSI、BOLL
- [ ] 指标参数可配置
- [ ] 支持多指标叠加显示

### US-005: 投资组合管理
**Description:** As a 投资者, I want 手动录入和管理持仓 so that 我可以追踪投资收益.

**Acceptance Criteria:**
- [ ] 支持添加/编辑/删除持仓记录
- [ ] 自动计算持仓成本和盈亏
- [ ] 显示持仓明细和汇总

### US-006: 策略回测
**Description:** As a 投资者, I want 回测自定义交易策略 so that 我可以验证策略有效性.

**Acceptance Criteria:**
- [ ] 基于 BackTrader 框架
- [ ] 支持自定义策略编写
- [ ] 显示回测收益曲线
- [ ] 显示回测统计指标（收益率、最大回撤等）

### US-007: 新闻关联
**Description:** As a 投资者, I want 查看与股票相关的新闻 so that 我可以了解影响股价的消息面.

**Acceptance Criteria:**
- [ ] 通过股票代码/名称关联新闻
- [ ] 通过行业/概念标签关联新闻
- [ ] 新闻列表按时间排序

## Scope

| IN Scope | OUT of Scope |
|----------|--------------|
| A股市场行情 | 港股、美股、期货 |
| K线图、分时图、技术指标 | 复杂的量化因子分析 |
| 手动录入持仓 | 券商账户自动同步 |
| BackTrader策略回测 | 实盘自动交易 |
| AKShare新闻数据 | 多新闻源聚合 |
| Web + 桌面应用 | 移动端应用 |
| 风险评估模块预留 | 风险评估具体实现 |

## Quality Gates

- `pnpm typecheck` - Type checking
- `pnpm lint` - Linting
- `pytest` - Python backend tests

## Technical Considerations

### 数据源
- **AKShare**: Python 库，支持A股行情、财务数据、新闻
- **通达信**: 本地接口，需安装通达信客户端

### 技术栈建议
- **前端**: React/Vue + ECharts + Tauri (桌面封装)
- **后端**: Python FastAPI + BackTrader
- **数据库**: SQLite/PostgreSQL

### 架构
```
┌─────────────────┐     ┌─────────────────┐
│   Web Frontend  │     │ Desktop (Tauri) │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │
              ┌──────┴──────┐
              │   API Gateway │
              └──────┬──────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
    ┌────┴────┐ ┌────┴────┐ ┌────┴────┐
    │行情服务  │ │组合服务  │ │回测服务  │
    └────┬────┘ └────┬────┘ └────┬────┘
         │           │           │
    ┌────┴────┐      │      ┌────┴────┐
    │数据源   │      │      │BackTrader│
    │AKShare  │      │      │         │
    │通达信   │      │      │         │
    └─────────┘      │      └─────────┘
                ┌────┴────┐
                │ Database │
                └─────────┘
```

## Open Questions

- [ ] 桌面端是否需要离线数据支持？
- [ ] 是否需要用户登录和数据同步？
- [ ] 策略回测的历史数据范围？
- [ ] 新闻数据更新频率？