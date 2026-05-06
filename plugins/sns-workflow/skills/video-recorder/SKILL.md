---
name: sns-workflow:video-recorder
description: 视频录制取证 —— 录制 bug 复现和修复验证过程的屏幕视频。配合 ui-verify 实现完整的 bug 取证闭环。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__click, mcp__chrome-devtools__fill, mcp__chrome-devtools__type_text, mcp__chrome-devtools__press_key, mcp__chrome-devtools__hover, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__list_pages
---

# 视频录制取证（Video Recorder）

录制 bug 复现与修复验证过程的屏幕视频，为 Harness Engineering 实践提供可回溯的视觉证据。每步自动截图作为帧，最终合成为带标注的 MP4/GIF。

**用法**:
- `--reproduce <描述>` — 按 bug 描述执行操作序列并录制复现过程
- `--verify` — 对同一操作序列录制修复后的验证过程
- `--custom` — 自由录制，手动指定操作步骤

**前置条件**: Chrome DevTools MCP 已连接，浏览器中可打开目标页面。需要 ffmpeg 用于视频合成。

**产物**: `.snsplay/task/video-*.mp4` + `.snsplay/task/video-recorder-*.json`

---

## 步骤 1: 参数解析与环境检查

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"
mkdir -p "$TASK_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RECORD_ID="video-recorder-${TIMESTAMP}"
FRAMES_DIR="$TASK_DIR/video-frames-${TIMESTAMP}"
mkdir -p "$FRAMES_DIR"

MODE="custom"
BUG_DESC=""
for arg in "$@"; do
  case "$arg" in
    --reproduce) MODE="reproduce" ;;
    --verify) MODE="verify" ;;
    --custom) MODE="custom" ;;
    *) [[ "$MODE" == "reproduce" ]] && BUG_DESC="${BUG_DESC:+$BUG_DESC }$arg" ;;
  esac
done

echo "=== 视频录制 ==="
echo "模式: $MODE"
echo "Artifact ID: $RECORD_ID"
echo "帧目录: $FRAMES_DIR"

# 检查 ffmpeg 可用性
if command -v ffmpeg &>/dev/null; then
  HAS_FFMPEG=true
  echo "ffmpeg: 可用"
else
  HAS_FFMPEG=false
  echo "警告: ffmpeg 不可用，将仅输出帧序列 GIF"
fi

# 检查 Chrome DevTools 连接
PAGE_COUNT=$(mcp__chrome-devtools__list_pages 2>/dev/null | grep -c '"id"' || echo "0")
if [[ "$PAGE_COUNT" -eq 0 ]]; then
  echo "警告: 当前无打开页面，后续操作将尝试打开新页面"
fi

if [[ "$MODE" == "reproduce" ]] && [[ -z "$BUG_DESC" ]]; then
  echo "错误: --reproduce 模式需要提供 Bug 描述"
  echo "用法: /sns-workflow:video-recorder --reproduce <bug 描述>"
  exit 1
fi
```

---

## 步骤 2: Bug 复现录制（--reproduce 模式）

**如果模式不是 `--reproduce`，跳过此步骤。**

### 2a: 解析 bug 描述与定位页面

根据 bug 描述提取目标 URL（匹配 `https?://` 模式）。如描述中包含 URL，使用 `mcp__chrome-devtools__navigate_page` 导航至该地址；否则使用当前已打开的页面。

使用 `mcp__chrome-devtools__take_snapshot` 获取页面结构，确认页面加载完成。

截取初始帧作为 frame-01：
```
mcp__chrome-devtools__take_screenshot
  filePath: "$FRAMES_DIR/frame-01.png"
  fullPage: true
```

### 2b: 执行复现操作序列

根据 bug 描述解析操作步骤，逐条执行。每步流程：

1. **定位元素**: `mcp__chrome-devtools__take_snapshot` 获取当前 a11y 树，找到目标元素的 `uid`
2. **执行操作**:
   - 点击按钮/链接 → `mcp__chrome-devtools__click`（`uid`）
   - 输入文本 → `mcp__chrome-devtools__fill`（`uid`, `value`）
   - 键盘操作 → `mcp__chrome-devtools__press_key`（`key`）
   - 悬停触发 → `mcp__chrome-devtools__hover`（`uid`）
3. **等待响应**: `mcp__chrome-devtools__wait_for`（`text: ["预期文本"]`, `timeout: 5000`）
4. **截取帧**: `mcp__chrome-devtools__take_screenshot`（`filePath: "$FRAMES_DIR/frame-NN.png"`, `fullPage: true`）
5. **采集错误**: `mcp__chrome-devtools__list_console_messages`（`types: ["error"]`），记录控制台错误

每步结果写入步骤列表，格式如下：
```json
{
  "order": 2,
  "action": "click",
  "target": "<元素描述或 uid>",
  "value": "",
  "screenshot": "frame-02.png",
  "console_errors": ["Error: ..."],
  "result": "success|error|unexpected_behavior"
}
```

### 2c: 判定复现结果

- 操作后出现 console error → `reproducible: true`
- 页面行为与 bug 描述一致 → `reproducible: true`
- 一切正常，无法复现 → `reproducible: false`
- 无法确定 → `reproducible: inconclusive`

---

## 步骤 3: 修复验证录制（--verify 模式）

**如果模式不是 `--verify`，跳过此步骤。**

### 3a: 读取复现 artifact 获取操作序列

查找最新的复现 artifact：
```bash
REPRO_ARTIFACT=$(ls -t "$TASK_DIR"/video-recorder-reproduce-*.json 2>/dev/null | head -1)
if [[ -z "$REPRO_ARTIFACT" ]]; then
  echo "警告: 未找到复现 artifact，将使用当前页面操作录制"
  REPRO_ARTIFACT=""
fi
```

如存在复现 artifact，读取其 `steps_executed` 字段，提取操作序列（action, target, value），按相同顺序重复执行。

### 3b: 执行验证操作序列

以与步骤 2b 完全相同的流程执行操作序列，但关注点不同：

- 每步验证预期行为（无 console error、正确响应）
- 截取帧到 `"$FRAMES_DIR/frame-NN.png"`
- 采集控制台消息，确认无新增 error

### 3c: 对比复现结果

| 对比维度 | 复现阶段 | 验证阶段 | 判定 |
|---------|---------|---------|-----|
| console errors | 有 N 条 | 有 M 条 | M < N → `fixed: true` |
| 页面行为 | 异常 | 正常 | 行为符合预期 → `fixed: true` |
| 网络请求 | 有失败 | 无失败 | 无失败 → `fixed: true` |

- 修复前后差异显著 → `fixed: true`
- 行为一致，问题仍然存在 → `fixed: false`
- 无法明确判定 → `fixed: inconclusive`

---

## 步骤 4: 自定义录制（--custom 模式）

**如果模式不是 `--custom`，跳过此步骤。**

在 custom 模式下，Agent 引导用户确认录制目标，然后自由执行操作并逐帧截图。每步操作后截取一帧，直到用户确认录制完成。

操作流程与步骤 2b 相同，但不需要 bug 描述解析，由 Agent 根据当前页面上下文自主决定操作步骤。

---

## 步骤 5: 视频合成

将帧序列合成为视频文件。

### 5a: 帧序列排序

```bash
FRAME_COUNT=$(ls "$FRAMES_DIR"/frame-*.png 2>/dev/null | wc -l)
echo "帧数: $FRAME_COUNT"

if [[ "$FRAME_COUNT" -lt 2 ]]; then
  echo "警告: 帧数不足 2 帧，无法合成视频"
  # 仍将 artifact 写入，video_path 留空
else
  # 继续合成流程
fi
```

### 5b: 使用 ffmpeg 合成 MP4

```bash
VIDEO_PATH="$TASK_DIR/video-repro-${TIMESTAMP}.mp4"

if $HAS_FFMPEG; then
  ffmpeg -y \
    -framerate 2 \
    -pattern_type glob \
    -i "$FRAMES_DIR/frame-*.png" \
    -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(1280-iw)/2:(720-ih)/2,drawtext=text='${MODE}':fontsize=24:fontcolor=white:x=10:y=10" \
    -c:v libx264 \
    -pix_fmt yuv420p \
    "$VIDEO_PATH" 2>/dev/null

  if [[ -f "$VIDEO_PATH" ]]; then
    VIDEO_SIZE=$(du -h "$VIDEO_PATH" | cut -f1)
    DURATION=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$VIDEO_PATH" 2>/dev/null)
    echo "视频: $VIDEO_PATH (${VIDEO_SIZE}, ${DURATION}s)"
  else
    echo "错误: MP4 合成失败"
    VIDEO_PATH=""
  fi
else
  VIDEO_PATH=""
fi
```

### 5c: 备用方案 — 合成 GIF

如 ffmpeg 不可用或 MP4 合成失败，使用 ImageMagick 合成 GIF：

```bash
GIF_PATH="$TASK_DIR/video-repro-${TIMESTAMP}.gif"

if [[ -z "$VIDEO_PATH" ]] && command -v convert &>/dev/null; then
  convert -delay 50 -loop 0 "$FRAMES_DIR"/frame-*.png "$GIF_PATH" 2>/dev/null
  if [[ -f "$GIF_PATH" ]]; then
    VIDEO_PATH="$GIF_PATH"
    echo "GIF: $GIF_PATH"
  fi
fi
```

如 ffmpeg 和 ImageMagick 都不可用，仅保留帧序列目录作为证据，`video_path` 字段为空。

---

## 步骤 6: 报告输出

将录制结果写入 artifact 文件。

```bash
ARTIFACT="$TASK_DIR/video-recorder-${RECORD_ID}.json"
```

使用 Write 工具写入以下 JSON 格式：

```json
{
  "id": "video-recorder-${TIMESTAMP}",
  "mode": "reproduce|verify|custom",
  "timestamp": "<当前 ISO 时间戳>",
  "video_path": ".snsplay/task/video-repro-${TIMESTAMP}.mp4",
  "frames_dir": ".snsplay/task/video-frames-${TIMESTAMP}",
  "frames_captured": 0,
  "duration_seconds": 0,
  "reproducible": true|false|inconclusive,
  "fixed": true|false|inconclusive,
  "steps_executed": [
    {
      "order": 1,
      "action": "navigate|click|fill|press_key|hover",
      "target": "<元素描述或 URL>",
      "value": "<输入值，如无则为空字符串>",
      "screenshot": "frame-01.png",
      "console_errors": ["Error: ..."],
      "result": "success|error|unexpected_behavior"
    }
  ],
  "console_errors": [
    "<所有捕获的控制台错误>"
  ],
  "description": "<bug 描述或录制说明>",
  "comparison": {
    "repro_errors": 0,
    "verify_errors": 0,
    "note": "<对比说明>"
  }
}
```

字段说明：
- `reproducible`: 仅在 `--reproduce` 模式下有意义
- `fixed`: 仅在 `--verify` 模式下有意义
- `comparison`: 仅在 `--verify` 模式下填充，对比复现阶段与验证阶段的错误数量

---

## 步骤 7: 汇总报告

```bash
echo ""
echo "=== 视频录制完成 ==="
echo "录制 ID: ${RECORD_ID}"
echo "模式: $MODE"
echo "帧数: $FRAME_COUNT"

if [[ -n "$VIDEO_PATH" ]]; then
  echo "视频: $VIDEO_PATH"
else
  echo "视频: 未生成（帧序列保留在 $FRAMES_DIR）"
fi

echo "Artifact: $ARTIFACT"

case "$MODE" in
  reproduce)
    echo "复现状态: ${REPRODUCIBLE:-unknown}"
    ;;
  verify)
    echo "修复状态: ${FIXED:-unknown}"
    ;;
  custom)
    echo "自定义录制完成"
    ;;
esac

echo ""
echo "后续操作:"
echo "  /sns-workflow:ui-verify --reproduce <描述>  → 补充 UI 取证"
echo "  /sns-workflow:video-recorder --verify        → 录制修复验证"
echo "  /sns-workflow:video-recorder --reproduce ... → 录制新的复现"
```
