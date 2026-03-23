# PRD: 行情展示模块

## Overview

前端行情展示组件，包括K线图、分时图、技术指标图，使用ECharts实现可视化。

## Goals

- 提供专业的行情图表展示
- 支持多种技术指标叠加
- 实现流畅的交互体验

## Quality Gates

- `pnpm typecheck` - Type checking
- `pnpm lint` - Linting

## User Stories

### US-001: K线图组件
**Description:** As a 投资者, I want 查看专业K线图 so that 我可以分析股票走势.

**Acceptance Criteria:**
- [ ] 支持日K、周K、月K切换
- [ ] 支持缩放和拖拽
- [ ] 显示成交量柱状图
- [ ] 支持十字光标和Tooltip

### US-002: 分时图组件
**Description:** As a 投资者, I want 查看当日分时图 so that 我可以把握盘中走势.

**Acceptance Criteria:**
- [ ] 显示当日分时价格曲线
- [ ] 显示均价线
- [ ] 显示成交量柱状图
- [ ] 支持时间范围选择

### US-003: 技术指标组件
**Description:** As a 投资者, I want 在图表上叠加技术指标 so that 我可以进行技术分析.

**Acceptance Criteria:**
- [ ] 支持MA、MACD、KDJ、RSI、BOLL
- [ ] 指标参数可配置
- [ ] 支持多指标叠加

## Technical Considerations

### 技术栈
- React + TypeScript
- ECharts 5.x
- Tauri (桌面封装)

### 组件接口
```typescript
interface KlineProps {
  code: string;
  data: KlineData[];
  period: 'day' | 'week' | 'month';
  indicators: Indicator[];
}
```

## Non-Goals

- 复杂的画线工具
- 自定义指标编辑器