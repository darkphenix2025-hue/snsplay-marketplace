---
name: sns-workflow:heal
description: 错误自动恢复 —— 读取工作流错误上下文（日志/产物/Git 状态），分类错误类型，生成分步恢复指令和防复发建议。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, Glob
---

# 错误自动恢复

读取工作流错误上下文，分类错误类型，生成结构化的分步恢复计划。

**用法**:
- `--last` — 分析最后一次失败（默认）
- `--all` — 分析全部可用错误记录
- 无参数 — 等同于 `--last`

**错误来源**:
- `.snsplay/task/cli_trace.log` — CLI 进程 stderr
- `.snsplay/sns-workflow.log` — 调试日志
- `.snsplay/task/` 产物文件 — 工作流阶段状态
- `git status` / `git log` — Git 仓库状态

---

## 步骤 1: 收集错误上下文

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"
LOG_DIR="$ROOT/.snsplay"

MODE="last"
for arg in "$@"; do
  [[ "$arg" == "--all" ]] && MODE="all"
done

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HEAL_ID="heal-${TIMESTAMP}"

echo "=== 错误恢复 ==="
echo "分析模式: $MODE"
echo ""

# === 收集错误源 ===
ERROR_CONTEXT=""

# 1. cli_trace.log
if [[ -f "$TASK_DIR/cli_trace.log" ]]; then
  echo "=== cli_trace.log (最近 20 行) ==="
  TAIL_TRACE=$(tail -20 "$TASK_DIR/cli_trace.log" 2>/dev/null)
  echo "$TAIL_TRACE"
  ERROR_CONTEXT="${ERROR_CONTEXT}cli_trace.log:${TAIL_TRACE}"
else
  echo "无 cli_trace.log"
fi

echo ""

# 2. sns-workflow.log
LOG_FILE="$LOG_DIR/sns-workflow.log"
if [[ -f "$LOG_FILE" ]]; then
  LOG_ERRORS=$(grep -i 'error\|failed\|FAILED\|exception' "$LOG_FILE" 2>/dev/null | tail -20)
  if [[ -n "$LOG_ERRORS" ]]; then
    echo "=== 日志错误 (最近 20 项) ==="
    echo "$LOG_ERRORS"
    ERROR_CONTEXT="${ERROR_CONTEXT}
sns-workflow.log:${LOG_ERRORS}"
  fi
else
  echo "无 sns-workflow.log（debug 模式未启用）"
fi

echo ""

# 3. 工作流产物状态
echo "=== 工作流产物状态 ==="
if [[ -d "$TASK_DIR" ]]; then
  if [[ -f "$TASK_DIR/workflow-tasks.json" ]]; then
    echo "workflow-tasks.json 存在"
    STAGES=$(grep -o '"output_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/workflow-tasks.json" 2>/dev/null | sed 's/.*:"//;s/"$//')
    if [[ -n "$STAGES" ]]; then
      echo "$STAGES" | while read stage_file; do
        artifact="$TASK_DIR/$stage_file"
        status="missing"
        if [[ -f "$artifact" ]]; then
          art_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$artifact" 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
          [[ -n "$art_status" ]] && status="$art_status" || status="exists"
        fi
        echo "  $stage_file: $status"
      done
    fi
  else
    echo "无 workflow-tasks.json"
  fi

  [[ -f "$TASK_DIR/impl-result.json" ]] && {
    impl_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/impl-result.json" 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
    echo "impl-result.json: ${impl_status:-exists}"
  }
else
  echo ".snsplay/task/ 目录不存在"
fi

echo ""

# 4. Git 状态
echo "=== Git 状态 ==="
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
echo "当前分支: $BRANCH"

GIT_STATUS=$(git status --short 2>/dev/null)
if [[ -n "$GIT_STATUS" ]]; then
  echo "未提交变更:"
  echo "$GIT_STATUS" | head -10
else
  echo "工作树清洁"
fi

REMOTE_STATUS=$(git remote -v 2>/dev/null | head -1)
echo "远端: ${REMOTE_STATUS:-未配置}"

RECENT_ERRORS=$(git log --oneline -5 2>/dev/null | grep -i 'error\|fail\|fix\|hotfix' || echo "无相关记录")
echo "最近相关提交: $RECENT_ERRORS"
```

---

## 步骤 2: 分类错误类型

**审查指令**: 根据步骤 1 收集的上下文，将错误分类到以下类别之一。

**分类规则**（按优先级匹配，首个匹配生效）:

| 类别 | 触发模式（不区分大小写） | 严重度 |
|------|-------------------------|--------|
| `auth` | `auth`, `login`, `credential`, `permission denied`, `publickey`, `403`, `401` | high |
| `network` | `timeout`, `timed out`, `ETIMEDOUT`, `ENOTFOUND`, `ECONNREFUSED`, `network` | high |
| `conflict` | `conflict`, `CONFLICT`, `merge conflict`, `could not apply`, `could not merge` | medium |
| `git-state` | `detached HEAD`, `dirty worktree`, `uncommitted`, `unstaged`, `not a git repo` | medium |
| `version` | `invalid version`, `version format`, `tag already exists`, `semver` | low |
| `dependency` | `command not found`, `ENOENT`, `module not found`, `bun: not found`, `gh: not found` | medium |
| `permission` | `permission denied`, `chmod`, `EACCES`, `sudo` | medium |
| `artifact` | `manifest not found`, `artifact missing`, `stage output`, `no such file` (针对 .snsplay/) | medium |
| `unknown` | 不匹配以上任何模式 | info |

如果**未发现错误**（所有日志干净、产物状态正常、Git 状态清洁），输出 `overall_status: "healthy"`，跳过步骤 3。

---

## 步骤 3: 生成恢复计划

根据错误分类生成对应的恢复计划。

**如果分类为 `auth`**:
```
恢复步骤:
1. 检查 gh 认证状态: gh auth status
2. 如未认证，运行: gh auth login（按提示操作）
3. 检查 Git 凭据: git config --get credential.helper
4. 如使用 SSH，验证密钥: ssh -T git@github.com
```

**如果分类为 `network`**:
```
恢复步骤:
1. 检查网络连接: curl -sI https://github.com
2. 如使用代理，检查代理设置: echo $HTTP_PROXY $HTTPS_PROXY
3. 重试失败的操作
4. 如持续失败，考虑使用镜像或离线工作
```

**如果分类为 `conflict`**:
```
恢复步骤:
1. 列出冲突文件: git diff --name-only --diff-filter=U
2. 手动编辑每个冲突文件，解决 <<<<<<< / ======= / >>>>>>> 标记
3. 解决后标记已解决: git add <file>
4. 继续操作:
   - 如正在 rebase: git rebase --continue
   - 如正在 merge: git commit
   - 如想放弃: git rebase --abort / git merge --abort
5. 建议启用 rerere 避免未来重复解决: git config rerere.enabled true
```

**如果分类为 `git-state`**:
```
恢复步骤:
1. 查看当前状态: git status
2. 根据具体状态操作:
   - detached HEAD: git checkout <branch>
   - dirty worktree: git stash（保留变更）或 git checkout -- .（丢弃变更）
   - uncommitted changes: git add -A && git commit -m "wip" 或 git stash
3. 确认状态清洁后重试失败的操作
```

**如果分类为 `version`**:
```
恢复步骤:
1. 语义化版本格式: MAJOR.MINOR.PATCH（如 1.5.0）
2. 预发布版本: MAJOR.MINOR.PATCH-prerelease.N（如 1.5.0-beta.1）
3. Git tag 格式: v 前缀 + 版本号（如 v1.5.0）
4. 列出已有 tag: git tag -l | sort -V
5. 选择一个不冲突的版本号后重试
```

**如果分类为 `dependency`**:
```
恢复步骤:
1. 确定缺失工具名称（从错误信息提取）
2. 安装方式（选择适用的）:
   - gh CLI: brew install gh 或参考 https://cli.github.com
   - bun: curl -fsSL https://bun.sh/install | bash
   - node: nvm install --lts 或 brew install node
3. 安装后验证: <tool> --version
4. 重试失败的操作
```

**如果分类为 `artifact`**:
```
恢复步骤:
1. 检查 .snsplay/task/ 目录结构: ls -la .snsplay/task/
2. 确认前置阶段产物完整（如 review 需要 impl-result.json）
3. 如产物缺失，重新运行对应阶段
4. 如目录结构损坏，运行 /sns-workflow:setup 重新初始化
```

**如果分类为 `unknown`**:
```
恢复步骤:
1. 运行 /sns-workflow:observe 获取完整工作流状态
2. 检查 .snsplay/sns-workflow.log 获取详细日志
3. 检查 .snsplay/task/cli_trace.log 获取 CLI 错误
4. 如无法定位，提交 issue 并附上:
   - git branch --show-current
   - .snsplay/task/ 目录内容
   - 完整的错误输出
```

将恢复计划写入 JSON artifact:

```bash
mkdir -p "$TASK_DIR"
```

然后按下方输出 JSON 格式，写入 `$TASK_DIR/heal-${TIMESTAMP}.json`:

```json
{
  "id": "heal-${TIMESTAMP}",
  "timestamp": "<ISO 时间戳>",
  "mode": "last|all",
  "branch": "<当前分支>",
  "error_type": "auth|network|conflict|git-state|version|dependency|permission|artifact|unknown",
  "error_summary": "错误简要描述",
  "root_cause": "根因分析（1-2 句话）",
  "recovery_plan": [
    {
      "step": 1,
      "command": "具体修复命令（如无则为空字符串）",
      "description": "本步骤说明",
      "risk": "no|low|medium|high"
    }
  ],
  "prevention": "防止再次发生的建议",
  "related_artifacts": ["相关日志或产物文件列表"]
}
```

确保 artifact 文件存在且内容完整。如果 `overall_status` 为 `healthy`，省略 `recovery_plan` 字段。

---

## 步骤 4: 汇总报告

```bash
ARTIFACT="$TASK_DIR/heal-${TIMESTAMP}.json"
if [[ -f "$ARTIFACT" ]]; then
  echo ""
  echo "=== heal 完成 ==="
  echo "恢复 ID: ${HEAL_ID}"
  echo "Artifact: $ARTIFACT"

  ERROR_TYPE=$(grep -o '"error_type"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARTIFACT" 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
  echo "错误类型: ${ERROR_TYPE:-unknown}"

  STEPS=$(grep -c '"step"' "$ARTIFACT" 2>/dev/null || echo "0")
  echo "恢复步骤: $STEPS"

  if [[ "$ERROR_TYPE" == "healthy" ]]; then
    echo ""
    echo "状态: 工作流健康，未发现错误"
  else
    echo ""
    echo "=== 恢复指令 ==="
    echo ""
    echo "请逐条执行上述步骤 3 中的恢复指令。"
    echo "完成后重新运行失败的操作。"
    echo ""
    echo "预防建议:"
    grep -o '"prevention"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARTIFACT" 2>/dev/null | sed 's/.*:"//' | sed 's/"$//'
  fi
else
  echo "错误: heal artifact 未生成"
  exit 1
fi
```
