#!/usr/bin/env bash
# security-gate.sh — PreToolUse hook for security-check skill
# 在 Write/Edit/Bash 工具调用前执行 21 条正则安全检查，覆盖 9 个 CWE 类别
# Exit 0 = 允许，Exit 2 = 阻止

set -uo pipefail

# === 1. 读取 stdin ===
INPUT=$(cat)

# 提取 tool_name
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("tool_name",""))' 2>/dev/null || true)

if [[ -z "$TOOL_NAME" ]]; then
  echo '{}'
  exit 0
fi

# 提取 content / command / file_path
read -r CONTENT FILE_PATH <<< "$(printf '%s' "$INPUT" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
ti = d.get("tool_input", d)
if d.get("tool_name") == "Bash":
    print(ti.get("command", ""), "")
else:
    print(ti.get("new_string", ti.get("content", "")), ti.get("file_path", ""))
' 2>/dev/null || echo " ")"

if [[ -z "$CONTENT" ]]; then
  echo '{}'
  exit 0
fi

# === 2. 文档文件豁免 ===
EXT="${FILE_PATH##*.}"
EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
case "$EXT" in
  md|mdx|txt|rst|jsonl)
    echo '{}'
    exit 0
    ;;
esac

# === 3. 安全检查 ===
FINDINGS=""
FINDING_COUNT=0

add_finding() {
  local cwe="$1"
  local msg="$2"
  FINDINGS="${FINDINGS}  ${cwe}: ${msg}\n"
  FINDING_COUNT=$((FINDING_COUNT + 1))
}

# CWE-798: 硬编码密码/密钥/密钥 (8+ 字符字面量)
if printf '%s' "$CONTENT" | grep -qPi '(password|secret|api_key|apikey|api_secret|private_key|secret_key)\s*[:=]\s*["'\''][^\s"'\'']{8,}["'\'']'; then
  add_finding "CWE-798" "硬编码密钥/密码，请使用环境变量或密钥管理器"
fi

# CWE-798: AWS 访问密钥前缀
if printf '%s' "$CONTENT" | grep -qP '(?:A3T[A-Z0-9]|AKIA|ASIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA)[A-Z0-9]{16}'; then
  add_finding "CWE-798" "AWS 访问密钥，请使用 IAM 角色或环境变量"
fi

# CWE-798: PEM 私钥
if printf '%s' "$CONTENT" | grep -qP '-----BEGIN [\w ]*PRIVATE KEY-----'; then
  add_finding "CWE-798" "私钥检测，绝不应将私钥提交到代码仓库"
fi

# CWE-798: JWT tokens (eyJ 前缀)
if printf '%s' "$CONTENT" | grep -qP '\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'; then
  add_finding "CWE-798" "JWT token 检测，请使用环境变量或密钥管理器"
fi

# CWE-798: 数据库连接串带凭证
if printf '%s' "$CONTENT" | grep -qPi '\b(mongodb|postgres|postgresql|mysql|redis|amqp)://[^:/\s]+:[^@/\s]+@'; then
  add_finding "CWE-798" "数据库连接串包含凭证，请使用环境变量"
fi

# CWE-798: Bearer/OAuth tokens (40+ 字符)
if printf '%s' "$CONTENT" | grep -qP '["'\'']Bearer\s+[A-Za-z0-9+/=_-]{40,}["'\'']'; then
  add_finding "CWE-798" "硬编码 Bearer token，请使用环境变量"
fi

# CWE-798: Google/GitHub API 密钥前缀
if printf '%s' "$CONTENT" | grep -qP '\b(AIza[0-9A-Za-z_-]{35}|ghp_[0-9A-Za-z]{36}|gho_[0-9A-Za-z]{36}|ghs_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,})'; then
  add_finding "CWE-798" "已知前缀的 API 密钥，请使用环境变量"
fi

# CWE-89: SQL 字符串拼接
if printf '%s' "$CONTENT" | grep -qP '(\.execute|\.query|\.raw|\.\$?queryRawUnsafe|\.\$?executeRawUnsafe|\.whereRaw|\.havingRaw|\.orderByRaw|\.joinRaw)\s*\(\s*(f["'\'']|["'\''].*\+|["'\''].*\$\{|["'\''].*%\s*\()'; then
  add_finding "CWE-89" "SQL 字符串拼接，请使用参数化查询"
fi

# CWE-89: SQL 模板字面量注入
if printf '%s' "$CONTENT" | grep -qP '\.\$?(execute|query|raw|queryRawUnsafe|executeRawUnsafe|whereRaw|havingRaw|orderByRaw|joinRaw)\s*\(\s*`[^`]*\$\{'; then
  add_finding "CWE-89" "SQL 模板字面量插值，请使用参数化查询"
fi

# CWE-95: eval() + 用户输入
if printf '%s' "$CONTENT" | grep -qP '\beval\s*\([^)]*\b(req|request|input|user|param|query|body|data)\b'; then
  add_finding "CWE-95" "eval() 传入用户输入，绝不解包不可信数据"
fi

# CWE-79: innerHTML 变量赋值
if printf '%s' "$CONTENT" | grep -qP '\.innerHTML\s*=\s*[^"'\''<\s]'; then
  add_finding "CWE-79" "innerHTML 赋值变量，请使用 textContent 或先清理"
fi

# CWE-502: pickle 反序列化
if printf '%s' "$CONTENT" | grep -qP 'pickle\.loads?\('; then
  add_finding "CWE-502" "pickle 反序列化，请用 json 替代"
fi

# CWE-502: yaml.load 无 Loader
if printf '%s' "$CONTENT" | grep -qP 'yaml\.load\s*\((?![^)]*Loader\s*=)[^)]*\)'; then
  add_finding "CWE-502" "yaml.load() 无 Loader 参数，请用 yaml.safe_load()"
fi

# CWE-502: yaml 不安全方法
if printf '%s' "$CONTENT" | grep -qP 'yaml\.(unsafe_load|full_load)\s*\('; then
  add_finding "CWE-502" "yaml.unsafe_load/full_load 危险，请用 yaml.safe_load()"
fi

# CWE-502: Node.js 不安全反序列化
if printf '%s' "$CONTENT" | grep -qP '\.unserialize\s*\('; then
  add_finding "CWE-502" "不安全反序列化，node-serialize 对不可信数据从不安全"
fi

# CWE-643: XPath 拼接注入
if printf '%s' "$CONTENT" | grep -qP '\.xpath\s*\(\s*(f["'\'']|["'\''].*\+|["'\''].*\$\{|`[^`]*\$\{)'; then
  add_finding "CWE-643" "XPath 字符串拼接，请使用参数化 XPath"
fi

# CWE-1321: 原型链污染
if printf '%s' "$CONTENT" | grep -qP '\["?__proto__"?\]\s*=|\.__proto__\s*=|constructor\s*\[\s*["'\'']prototype["'\'']\s*\]|constructor\.prototype\s*[.=]'; then
  add_finding "CWE-1321" "原型链污染，绝不要赋值给 __proto__ 或 constructor.prototype"
fi

# CWE-1336: SSTI Jinja2
if printf '%s' "$CONTENT" | grep -qP '\bTemplate\s*\(\s*(?!["'\''])' || printf '%s' "$CONTENT" | grep -qP '\b(env|environment|jinja_env|jinja2_env|j2_env)\s*\.\s*from_string\s*\(\s*(?!["'\''])'; then
  add_finding "CWE-1336" "服务端模板注入风险 (Jinja2)，请使用静态模板"
fi

# CWE-1336: SSTI Handlebars
if printf '%s' "$CONTENT" | grep -qP 'Handlebars\.compile\s*\(\s*(?!["'\''])'; then
  add_finding "CWE-1336" "服务端模板注入风险 (Handlebars)，请使用预编译模板"
fi

# Bash 专属检查
if [[ "$TOOL_NAME" == "Bash" ]]; then
  # CWE-116: 编码数据管道到 shell
  if printf '%s' "$CONTENT" | grep -qP '\b(base64\s+(-d|--decode)|xxd\s+-r)\b'; then
    if printf '%s' "$CONTENT" | grep -qP '\|\s*(bash|sh|zsh|dash|ksh|eval|\$SHELL|source)\b|\b(bash|sh|zsh|dash|ksh)\s+-c\b'; then
      add_finding "CWE-116" "编码数据管道到 shell 执行"
    fi
  fi
  # CWE-95: Shell eval
  if printf '%s' "$CONTENT" | grep -qP '\beval\s+["'\'']'; then
    add_finding "CWE-95" "Shell eval 动态输入"
  fi
fi

# === 4. 输出结果 ===
if [[ "$FINDING_COUNT" -gt 0 ]]; then
  # 去重 CWE
  UNIQUE_CWES=$(printf '%b' "$FINDINGS" | grep -oP 'CWE-\d+' | sort -u | tr '\n' ', ' | sed 's/,$//')

  # 写入日志
  LOG_DIR="$HOME/.sns-workflow/security-gate"
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
  printf '[%s] BLOCKED (%s findings) tool=%s file=%s cwes=%s\n%s\n' \
    "$(date -Iseconds)" "$FINDING_COUNT" "$TOOL_NAME" "$FILE_PATH" "$UNIQUE_CWES" \
    "$(printf '%b' "$FINDINGS")" >> "$LOG_FILE" 2>/dev/null || true

  MSG_ESCAPED=$(printf '[security-check] 检测到 %d 项安全风险 (%s)，已阻止此操作：\n\n%b\n\n提示: 请使用安全替代方案（环境变量/参数化查询/safe_load 等）。如需忽略特定 CWE，请在 .sns-workflow/security-ignore 中添加。' \
    "$FINDING_COUNT" "$UNIQUE_CWES" "$FINDINGS" | sed 's/"/\\"/g' | tr '\n' '\\')

  printf '{"permissionDecision":"ask","message":"%s"}\n' "$MSG_ESCAPED"
  exit 2
fi

echo '{}'
exit 0
