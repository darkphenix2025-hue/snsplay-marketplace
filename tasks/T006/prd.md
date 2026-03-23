# PRD: 应用框架

## Overview

应用基础设施，包括后端API框架、前端Web框架和桌面端封装。

## Goals

- 搭建后端API服务
- 搭建前端Web应用
- 实现桌面端封装

## Quality Gates

- `pnpm typecheck` - 类型检查
- `pnpm lint` - 代码检查
- `pytest tests/` - 后端测试

## User Stories

### US-001: 后端API框架
**Description:** As a 开发者, I want 搭建后端API框架 so that 业务服务可以部署.

**Acceptance Criteria:**
- [ ] 使用FastAPI搭建API框架
- [ ] 实现API路由注册
- [ ] 实现统一错误处理
- [ ] 实现API文档

### US-002: 前端Web框架
**Description:** As a 开发者, I want 搭建前端框架 so that 用户界面可以开发.

**Acceptance Criteria:**
- [ ] 使用React + TypeScript
- [ ] 配置路由和状态管理
- [ ] 实现基础布局组件
- [ ] 配置ECharts

### US-003: 桌面端封装
**Description:** As a 开发者, I want 封装桌面应用 so that 用户可以在桌面使用.

**Acceptance Criteria:**
- [ ] 使用Tauri封装
- [ ] 配置应用窗口
- [ ] 实现系统托盘
- [ ] 配置自动更新

## Technical Considerations

### 技术栈
- 后端: Python 3.11+ / FastAPI / SQLite
- 前端: React 18 / TypeScript / TailwindCSS / ECharts
- 桌面: Tauri 2.0

### 项目结构
```
investment-analysis/
├── backend/           # Python FastAPI
│   ├── src/
│   ├── tests/
│   └── requirements.txt
├── frontend/          # React TypeScript
│   ├── src/
│   ├── package.json
│   └── vite.config.ts
└── src-tauri/         # Tauri desktop
    ├── src/
    └── Cargo.toml
```

## Non-Goals

- 移动端应用
- 云端部署配置