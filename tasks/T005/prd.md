# PRD: 新闻数据模块

## Overview

整合AKShare新闻数据源，实现新闻与股票的关联匹配。

## Goals

- 获取财经新闻数据
- 实现新闻与股票关联
- 提供新闻查询接口

## Quality Gates

- `pytest tests/test_news.py` - 新闻模块测试

## User Stories

### US-001: AKShare新闻数据获取
**Description:** As a 开发者, I want 获取财经新闻数据 so that 系统可以展示相关新闻.

**Acceptance Criteria:**
- [ ] 集成AKShare新闻接口
- [ ] 实现新闻数据存储
- [ ] 支持增量更新

### US-002: 新闻关联匹配
**Description:** As a 投资者, I want 看到与股票相关的新闻 so that 我可以了解消息面.

**AcceptanceCriteria:**
- [ ] 通过股票代码/名称匹配
- [ ] 通过行业标签匹配
- [ ] 通过概念标签匹配
- [ ] 显示匹配相关性

## Technical Considerations

### 新闻数据模型
```python
@dataclass
class News:
    id: str
    title: str
    content: str
    source: str
    publish_time: datetime
    related_codes: List[str]    # 关联股票代码
    related_industries: List[str]  # 关联行业
    related_concepts: List[str]    # 关联概念
```

## Non-Goals

- 多新闻源聚合
- 新闻情感分析