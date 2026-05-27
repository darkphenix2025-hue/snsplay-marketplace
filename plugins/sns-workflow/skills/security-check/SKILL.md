---
name: sns-workflow:security-check
description: 安全门禁 —— 硬编码正则检查 21 种危险代码模式（9 个 CWE 类别），Write/Edit/Bash 前自动触发。覆盖硬编码密钥、SQL 注入、XSS、反序列化、SSTI、原型链污染等。
user-invocable: true
allowed-tools: Bash
---

# 安全门禁技能

在代码写入/编辑/Shell 执行前，自动检查 21 种已知危险代码模式。

**两级安全体系中的第一级**: 硬编码正则匹配，零延迟，自动拦截。
第二级为 `ai-security-review`，由 AI 进行深度数据流分析。

---

## 检查范围

| CWE 类别 | 检查内容 | 规则数 |
|----------|---------|--------|
| CWE-798 | 硬编码密钥/密码、AWS Key、PEM 私钥、JWT、连接串、Bearer token、Google/GitHub API Key | 7 |
| CWE-89 | SQL 字符串拼接、模板字面量注入 | 2 |
| CWE-95 | eval() 用户输入、Shell eval 动态输入 | 2 |
| CWE-79 | innerHTML 变量赋值 | 1 |
| CWE-502 | pickle、yaml 不安全加载、Node.js 反序列化 | 4 |
| CWE-643 | XPath 拼接注入 | 1 |
| CWE-1321 | 原型链污染 | 1 |
| CWE-1336 | SSTI (Jinja2 + Handlebars) | 2 |
| CWE-116 | 编码数据管道到 Shell | 1 |

**豁免文件**: `.md`, `.mdx`, `.txt`, `.rst`, `.jsonl` 文档文件不扫描。

---

## 步骤 1: 手动执行安全检查

当用户主动调用此技能时，扫描当前 git diff 中的变更文件。

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "security-check" "$*"

# 获取变更文件列表
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || git diff --cached --name-only 2>/dev/null || echo "")

if [[ -z "$CHANGED_FILES" ]]; then
  echo "没有检测到代码变更，无需扫描"
  sns_skill_end "success"
  exit 0
fi

echo "=== 安全检查: 扫描 $(echo "$CHANGED_FILES" | wc -l) 个变更文件 ==="
echo ""

GATE_SCRIPT="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/skills/security-check/bin/security-gate.sh"
TOTAL_FINDINGS=0

for file in $CHANGED_FILES; do
  # 跳过文档文件
  EXT="${file##*.}"
  case "$(echo "$EXT" | tr '[:upper:]' '[:lower:]')" in
    md|mdx|txt|rst|jsonl) continue ;;
  esac

  # 读取文件内容
  if [[ -f "$file" ]]; then
    CONTENT=$(cat "$file" 2>/dev/null || true)
    if [[ -n "$CONTENT" ]]; then
      # 模拟 tool_input 构造
      MOCK_INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s}}' \
        "$file" "$(printf '%s' "$CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')")

      RESULT=$(printf '%s' "$MOCK_INPUT" | bash "$GATE_SCRIPT" 2>&1 || true)
      if echo "$RESULT" | grep -q "FINDING\|BLOCKED\|CWE-"; then
        echo "  $file:"
        echo "$RESULT" | grep -oP 'CWE-\d+:.*' | while read line; do
          echo "    $line"
          TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
        done
      fi
    fi
  fi
done

echo ""
if [[ "$TOTAL_FINDINGS" -gt 0 ]]; then
  echo "=== 发现 $TOTAL_FINDINGS 项安全风险 ==="
  echo "建议: 运行 /sns-workflow:ai-security-review 进行深度 AI 审查"
else
  echo "=== 安全检查通过: 未发现已知危险模式 ==="
fi

sns_skill_end "success"
```

---

## Hook 触发

本技能的 `bin/security-gate.sh` 已注册为 PreToolUse hook，在每次 Write/Edit/Bash 工具调用前自动触发，无需手动运行。

**配置位置**: `plugins/sns-workflow/hooks/hooks.json`
