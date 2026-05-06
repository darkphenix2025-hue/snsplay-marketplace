---
name: sns-workflow:ui-verify
description: UI 验证与审计 — 页面快照基线化、变更比对、Bug 复现取证、Lighthouse 可访问性与性能审计。支持 --snapshot / --verify / --reproduce / --audit 四种模式。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, Glob, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__click, mcp__chrome-devtools__fill, mcp__chrome-devtools__list_console_messages, mcp__chrome-devtools__list_network_requests, mcp__chrome-devtools__evaluate_script, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__lighthouse_audit, mcp__chrome-devtools__performance_start_trace, mcp__chrome-devtools__performance_stop_trace, mcp__chrome-devtools__performance_analyze_insight, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__press_key, mcp__chrome-devtools__type_text, mcp__chrome-devtools__hover, mcp__chrome-devtools__drag, mcp__chrome-devtools__emulate, mcp__chrome-devtools__resize_page
---

# UI 验证与审计

对当前页面进行快照基线化、变更比对、Bug 复现取证、性能与可访问性审计。

**用法**:
- `--snapshot`（默认）— 基线化当前页面（DOM 快照 + 截图 + 元信息）
- `--verify` — 对比基线，报告差异
- `--reproduce <描述>` — 根据 Bug 描述自动复现并取证
- `--audit` — Lighthouse 审计 + 性能追踪 + Core Web Vitals

**前置条件**: Chrome DevTools MCP 服务已连接（CDP WebSocket），浏览器中已打开目标页面。

---

## 步骤 1: 参数解析与环境校验

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"
mkdir -p "$TASK_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERIFY_ID="ui-verify-${TIMESTAMP}"
BASELINE_PATH="$TASK_DIR/ui-verify-baseline.json"

MODE="snapshot"
BUG_DESC=""
for arg in "$@"; do
  case "$arg" in
    --verify) MODE="verify" ;;
    --reproduce) MODE="reproduce" ;;
    --audit) MODE="audit" ;;
    --snapshot) MODE="snapshot" ;;
    *) [[ "$MODE" == "reproduce" ]] && BUG_DESC="${BUG_DESC:+$BUG_DESC }$arg" ;;
  esac
done

echo "=== UI 验证 ==="
echo "模式: $MODE"
echo "Artifact ID: $VERIFY_ID"

if [[ "$MODE" == "verify" ]] && [[ ! -f "$BASELINE_PATH" ]]; then
  echo "错误: 缺少基线文件 ($BASELINE_PATH)"
  echo "请先运行 /sns-workflow:ui-verify --snapshot 建立基线"
  exit 1
fi

if [[ "$MODE" == "reproduce" ]] && [[ -z "$BUG_DESC" ]]; then
  echo "警告: --reproduce 模式未提供 Bug 描述"
  echo "用法: /sns-workflow:ui-verify --reproduce <bug 描述>"
  echo "将使用当前页面作为复现环境"
fi
```

---

## 步骤 2: 页面快照（snapshot / verify 模式）

使用 `mcp__chrome-devtools__take_snapshot` 获取当前页面的无障碍树快照。不使用 `verbose: true`，保留标准精度的 a11y 树。

快照中每个元素有一个唯一 `uid`，用于后续交互操作定位。

将完整快照文本保存下来，供后续步骤写入 artifact。

---

## 步骤 3: 页面截图

使用 `mcp__chrome-devtools__take_screenshot` 获取全屏截图：
- `fullPage: true`
- `format: "png"`
- `filePath: ".snsplay/task/ui-verify-screenshot-${TIMESTAMP}.png"`（保存为文件而非 base64）

截图文件路径后续写入 artifact。

---

## 步骤 4: 收集页面元信息

使用 `mcp__chrome-devtools__evaluate_script` 收集：
- `document.title`
- `document.URL`
- `window.innerWidth` × `window.innerHeight`
- `document.documentElement.lang`

使用 `mcp__chrome-devtools__list_console_messages` 收集当前控制台消息（仅 `error` 和 `warn` 类型）。

使用 `mcp__chrome-devtools__list_network_requests` 收集网络请求摘要（总数 + 失败数）。

---

## 步骤 5: 写入基线 Artifact（snapshot 模式）

```bash
mkdir -p "$TASK_DIR"
echo "请将步骤 2-4 收集的数据写入以下文件:"
echo "  基线: $BASELINE_PATH"
echo "  历史: $TASK_DIR/ui-verify-${TIMESTAMP}.json"
```

按下方 JSON 格式使用 Write 工具写入。**同时写入两个路径**：基线文件（覆盖）和时间戳文件（追加历史）。

```json
{
  "id": "ui-verify-${TIMESTAMP}",
  "mode": "snapshot",
  "timestamp": "<当前 ISO 时间戳>",
  "page_info": {
    "url": "<document.URL>",
    "title": "<document.title>",
    "viewport": { "width": 1920, "height": 1080 },
    "lang": "<document.documentElement.lang>"
  },
  "snapshot": {
    "a11y_tree": "<take_snapshot 返回的完整文本>",
    "node_count": "<a11y 树中的节点总数>"
  },
  "screenshot_path": ".snsplay/task/ui-verify-screenshot-${TIMESTAMP}.png",
  "console_errors": [
    { "level": "error|warn", "text": "<消息内容>", "source": "<来源>" }
  ],
  "network_summary": {
    "total": "<请求总数>",
    "failed": "<状态码 >= 400 的请求数>"
  }
}
```

如果当前模式为 `--verify`，跳过此步骤，进入步骤 6。

---

## 步骤 6: 差异分析（verify 模式）

**如果模式不是 `--verify`，跳过此步骤。**

1. 使用 `Read` 工具读取 `$BASELINE_PATH`，解析 `page_info`、`snapshot.a11y_tree`、`console_errors`、`network_summary`。

2. 使用 `mcp__chrome-devtools__take_snapshot` 获取当前页面快照（当前 a11y 树）。

3. 使用 `mcp__chrome-devtools__take_screenshot`（`fullPage: true`，`filePath: ".snsplay/task/ui-verify-screenshot-${TIMESTAMP}.png"`）获取当前截图。

4. 使用 `mcp__chrome-devtools__list_console_messages`（`types: ["error", "warn"]`）获取当前控制台消息。

5. **对比分析**（agent 执行，非 bash）:

   **a11y 树对比**:
   - 找出新增节点：当前快照有但基线没有的元素（按 role + name 匹配）
   - 找出删除节点：基线有但当前快照没有的元素
   - 找出文本变更：相同元素但文本内容不同
   - 找出属性变更：相同元素但 role、checked、expanded、disabled 等状态属性变化

   **控制台对比**:
   - 基线中没有但当前出现的 error/warn → `new_console_errors`

   **页面信息对比**:
   - URL 是否变更
   - 标题是否变更
   - viewport 是否变更

6. **写入差异 artifact**:

```json
{
  "id": "ui-verify-${TIMESTAMP}",
  "mode": "verify",
  "timestamp": "<当前 ISO 时间戳>",
  "baseline_id": "<基线 artifact 的 id 字段>",
  "baseline_timestamp": "<基线 artifact 的 timestamp 字段>",
  "page_info": {
    "url": "<当前 URL>",
    "title": "<当前标题>",
    "url_changed": true,
    "title_changed": false
  },
  "diff": {
    "nodes_added": [
      { "role": "<角色>", "name": "<无障碍名称>", "uid": "<uid>" }
    ],
    "nodes_removed": [
      { "role": "<角色>", "name": "<无障碍名称>", "uid": "<uid>" }
    ],
    "text_changed": [
      { "uid": "<uid>", "name": "<元素名>", "baseline": "<原文>", "current": "<现文>" }
    ],
    "attribute_changed": [
      { "uid": "<uid>", "name": "<元素名>", "attribute": "<属性>", "baseline": "<原值>", "current": "<现值>" }
    ],
    "new_console_errors": [
      { "level": "error|warn", "text": "<消息>" }
    ]
  },
  "screenshot_path": ".snsplay/task/ui-verify-screenshot-${TIMESTAMP}.png",
  "summary": {
    "total_changes": 0,
    "severity": "none|minor|moderate|significant",
    "description": "<2-3 句话描述差异概况>"
  }
}
```

**严重度判定规则**:
- `none`: 无任何差异
- `minor`: 仅有文本内容微调或新增非关键节点（< 5 处）
- `moderate`: 有节点删除或新增超过 5 处，或出现新的 console error
- `significant`: 关键节点（按钮、表单、导航）被删除或属性变更，或 console error 超过 3 条

---

## 步骤 7: Bug 复现取证（reproduce 模式）

**如果模式不是 `--reproduce`，跳过此步骤。**

### 7a: 确认复现环境

使用 `mcp__chrome-devtools__list_pages` 检查当前是否有打开的页面。

如 bug 描述中包含 URL（匹配 `https?://` 开头的文本），使用 `mcp__chrome-devtools__navigate_page` 导航到该 URL。如无 URL，使用当前已打开的页面。

### 7b: 解析 Bug 描述并执行交互

根据 bug 描述中的关键操作，按顺序执行交互。每一步：

1. 使用 `mcp__chrome-devtools__take_snapshot` 获取当前页面结构，定位目标元素的 `uid`
2. 根据操作类型调用对应 MCP 工具：
   - 点击按钮/链接 → `mcp__chrome-devtools__click`（`uid: "<目标 uid>"`）
   - 输入文本 → `mcp__chrome-devtools__fill`（`uid: "<输入框 uid>"`, `value: "<值>"`）
   - 按键 → `mcp__chrome-devtools__press_key`（`key: "Enter|Tab|Escape"`）
   - 悬停 → `mcp__chrome-devtools__hover`（`uid: "<目标 uid>"`）
3. 等待响应：`mcp__chrome-devtools__wait_for`（`text: ["预期出现的文本"]`, `timeout: 5000`）
4. 截取证据：`mcp__chrome-devtools__take_screenshot`（`filePath: ".snsplay/task/ui-verify-repro-step{N}-${TIMESTAMP}.png"`）
5. 检查控制台：`mcp__chrome-devtools__list_console_messages`（`types: ["error"]`）
6. 记录本步骤结果：`success`（正常）/ `error`（控制台报错）/ `unexpected_behavior`（异常表现）

**判断是否复现**:
- 操作后出现控制台 error → 标记 `reproducible: true`
- 页面行为与描述一致（如"点击无响应"确实无响应）→ 标记 `reproducible: true`
- 操作后一切正常 → 标记 `reproducible: false`
- 无法确定 → 标记 `reproducible: inconclusive`

### 7c: 收集失败网络请求

使用 `mcp__chrome-devtools__list_network_requests` 收集所有请求，筛选状态码 >= 400 的失败请求。

### 7d: 写入复现 artifact

```json
{
  "id": "ui-verify-${TIMESTAMP}",
  "mode": "reproduce",
  "timestamp": "<当前 ISO 时间戳>",
  "bug_description": "<bug 描述原文>",
  "target_url": "<目标 URL>",
  "reproducible": true,
  "reproduction_steps": [
    {
      "step": 1,
      "action": "navigate|click|fill|press_key|hover",
      "target": "<元素描述或 uid>",
      "value": "<输入值，如无则为空字符串>",
      "screenshot_path": ".snsplay/task/ui-verify-repro-step1-${TIMESTAMP}.png",
      "result": "success|error|unexpected_behavior",
      "console_errors": [],
      "note": "<本步骤观察到的现象>"
    }
  ],
  "failed_requests": [
    { "url": "<请求 URL>", "status": 404, "method": "GET" }
  ],
  "evidence_summary": "<复现结果描述，2-3 句话>",
  "screenshots": [
    ".snsplay/task/ui-verify-repro-step1-${TIMESTAMP}.png"
  ]
}
```

---

## 步骤 8: Lighthouse 审计（audit 模式）

**如果模式不是 `--audit`，跳过此步骤。**

### 8a: 运行 Lighthouse

使用 `mcp__chrome-devtools__lighthouse_audit`（`device: "desktop"`, `mode: "navigation"`）运行审计。

记录以下分数：
- Performance
- Accessibility
- Best Practices
- SEO

记录所有 accessibility issues（按 severity 分类）。

### 8b: 性能追踪

使用 `mcp__chrome-devtools__performance_start_trace`（`reload: true`, `autoStop: true`）开始性能追踪。

追踪完成后，对每个可用的 insight 使用 `mcp__chrome-devtools__performance_analyze_insight` 获取详细分析。

记录 Core Web Vitals 指标：
- LCP (Largest Contentful Paint)
- INP (Interaction to Next Paint)
- CLS (Cumulative Layout Shift)
- TTFB (Time to First Byte)
- FCP (First Contentful Paint)

### 8c: 辅助审计信息

使用 `mcp__chrome-devtools__list_console_messages` 收集全部控制台消息。

使用 `mcp__chrome-devtools__list_network_requests` 收集全部网络请求，计算总请求数、总大小、失败数。

使用 `mcp__chrome-devtools__evaluate_script` 收集：
```javascript
() => {
  return {
    images: document.images.length,
    stylesheets: document.styleSheets.length,
    scripts: document.scripts.length,
    domNodes: document.querySelectorAll('*').length,
    ariaElements: document.querySelectorAll('[aria-label], [aria-labelledby], [role]').length
  }
}
```

使用 `mcp__chrome-devtools__take_screenshot`（`fullPage: true`，`filePath: ".snsplay/task/ui-verify-screenshot-${TIMESTAMP}.png"`）获取审计截图。

### 8d: 写入审计 artifact

```json
{
  "id": "ui-verify-${TIMESTAMP}",
  "mode": "audit",
  "timestamp": "<当前 ISO 时间戳>",
  "page_info": {
    "url": "<当前 URL>",
    "title": "<当前标题>"
  },
  "lighthouse": {
    "performance": { "score": 0.0 },
    "accessibility": { "score": 0.0 },
    "best_practices": { "score": 0.0 },
    "seo": { "score": 0.0 }
  },
  "performance_trace": {
    "metrics": {
      "LCP": "<毫秒>",
      "INP": "<毫秒>",
      "CLS": "<数值>",
      "TTFB": "<毫秒>",
      "FCP": "<毫秒>"
    },
    "insights": [
      { "name": "<洞察名称>", "description": "<描述>" }
    ]
  },
  "accessibility_issues": [
    {
      "severity": "critical|serious|moderate|minor",
      "id": "<lighthouse 规则 ID>",
      "description": "<问题描述>",
      "elements": ["<CSS 选择器或元素描述>"]
    }
  ],
  "resource_summary": {
    "dom_nodes": 0,
    "images": 0,
    "stylesheets": 0,
    "scripts": 0,
    "aria_elements": 0
  },
  "console_messages": [
    { "level": "error|warn|info", "text": "<消息>" }
  ],
  "network_summary": {
    "total_requests": 0,
    "failed_requests": 0,
    "slow_requests": [
      { "url": "<URL>", "duration_ms": 0 }
    ]
  },
  "screenshot_path": ".snsplay/task/ui-verify-screenshot-${TIMESTAMP}.png",
  "summary": {
    "overall_health": "excellent|good|fair|poor",
    "critical_issues": 0,
    "recommendations": ["<建议 1>", "<建议 2>"]
  }
}
```

**健康度判定规则**:
- `excellent`: 所有 Lighthouse 分数 >= 0.9，无 console error，Core Web Vitals 全部达标
- `good`: 所有分数 >= 0.7，critical accessibility issues = 0
- `fair`: 有分数 < 0.7 或存在 serious 级别 accessibility issues
- `poor`: 有分数 < 0.5 或存在 critical accessibility issues 或 > 10 条 console errors

---

## 步骤 9: 汇总报告

```bash
ARTIFACT="$TASK_DIR/ui-verify-${TIMESTAMP}.json"

if [[ -f "$ARTIFACT" ]]; then
  echo ""
  echo "=== ui-verify 完成 ==="
  echo "验证 ID: ${VERIFY_ID}"
  echo "模式: $MODE"
  echo "Artifact: $ARTIFACT"

  case "$MODE" in
    snapshot)
      echo "状态: 基线已保存"
      echo "基线: $BASELINE_PATH"
      NODE_COUNT=$(grep -o '"node_count"[[:space:]]*:[[:space:]]*[0-9]*' "$ARTIFACT" 2>/dev/null | head -1 | sed 's/.*://' || echo "?")
      echo "节点数: ${NODE_COUNT}"
      ;;
    verify)
      SEVERITY=$(grep -o '"severity"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARTIFACT" 2>/dev/null | tail -1 | sed 's/.*:"//;s/"$//' || echo "unknown")
      TOTAL=$(grep -o '"total_changes"[[:space:]]*:[[:space:]]*[0-9]*' "$ARTIFACT" 2>/dev/null | sed 's/.*://' || echo "0")
      echo "差异严重度: ${SEVERITY}"
      echo "变更总数: ${TOTAL:-0}"
      ;;
    reproduce)
      REPRO=$(grep -o '"reproducible"[[:space:]]*:[[:space:]]*[a-z]*' "$ARTIFACT" 2>/dev/null | head -1 | sed 's/.*://' || echo "unknown")
      STEPS=$(grep -c '"step"' "$ARTIFACT" 2>/dev/null || echo "0")
      echo "可复现: ${REPRO}"
      echo "复现步骤: ${STEPS}"
      ;;
    audit)
      HEALTH=$(grep -o '"overall_health"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARTIFACT" 2>/dev/null | sed 's/.*:"//;s/"$//' || echo "unknown")
      CRITICAL=$(grep -o '"critical_issues"[[:space:]]*:[[:space:]]*[0-9]*' "$ARTIFACT" 2>/dev/null | sed 's/.*://' || echo "0")
      echo "页面健康度: ${HEALTH}"
      echo "关键问题: ${CRITICAL:-0}"
      ;;
  esac
else
  echo "错误: ui-verify artifact 未生成"
  exit 1
fi
```
