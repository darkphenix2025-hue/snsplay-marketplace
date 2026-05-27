---
name: sns-workflow:ai-security-review
description: AI 安全审计 —— 深度审查代码变更中的安全漏洞，包括数据流追踪、暴露上下文、利用路径分析、7步验证 Pipeline。配合 security-check 实现两级安全门禁。
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob
---

# AI 安全审查技能

对代码变更进行深度安全审计，超越正则匹配，通过数据流追踪和上下文分析发现 security-check 无法检测的复杂漏洞。

**两级安全体系中的第二级**: 当 security-check 发现风险时自动触发，或在 PR 合并前手动调用。

---

## 使用场景

1. **自动触发**: 在 qa-gate 阶段中，security-check 发现风险时自动调用
2. **手动审计**: 对特定文件/目录进行全面安全审查
3. **提交前审查**: PR 创建前对变更代码进行最终安全验证

---

## 步骤 1: 确定审查范围

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "ai-security-review" "$*"

# 确定审查范围
SCOPE="${1:-diff}"  # diff | file <path> | dir <path> | full

case "$SCOPE" in
  diff)
    TARGET_FILES=$(git diff --name-only HEAD 2>/dev/null || git diff --cached --name-only 2>/dev/null || echo "")
    MODE="代码变更审查"
    ;;
  file)
    TARGET_FILES="${2:?请指定文件路径}"
    MODE="单文件审查: $TARGET_FILES"
    ;;
  dir)
    TARGET_FILES=$(find "${2:-.}" -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | head -50)
    MODE="目录审查: ${2:-.}"
    ;;
  full)
    TARGET_FILES=$(find . -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.go" -o -name "*.rs" \) -not -path "./node_modules/*" -not -path "./dist/*" -not -path "./.git/*" 2>/dev/null | head -100)
    MODE="全量审查"
    ;;
esac

if [[ -z "$TARGET_FILES" ]]; then
  echo "未找到可审查的代码文件"
  sns_skill_end "success"
  exit 0
fi

echo "=== AI 安全审查 ==="
echo "模式: $MODE"
echo "文件数: $(echo "$TARGET_FILES" | wc -l)"
echo ""
```

---

## 步骤 2: 静态安全规则扫描

以下安全规则需要逐项检查。请对每个目标文件执行以下扫描:

### 输入验证类

1. **跨信任边界输入未验证** (CWE-20): 检查所有 HTTP 请求处理、CLI 参数、数据库读取、文件读取、外部 API 响应的入口点，确认是否存在类型/长度/格式/范围验证。

2. **SQL/NoSQL/LDAP 注入** (CWE-89/90): 搜索 `.query()`, `.execute()`, `db.find()`, `ldap.search()` 等调用，追踪其参数来源。如果是字符串拼接或模板字面量构建，标记为风险。注意 ORM 自动参数化（如 SQLAlchemy 的 `session.query().filter()`）是安全的。

3. **命令注入** (CWE-78): 搜索 `subprocess.run()`, `os.system()`, `child_process.exec()`, `spawn()`, `eval()`, `exec()` 等调用，检查参数是否经过清洗。

### 认证授权类

4. **缺少认证/授权检查**: 检查所有 API 路由端点，确认是否存在认证中间件或装饰器。对敏感操作（删除、修改权限、支付等）检查是否有额外的授权验证。

5. **硬编码凭证** (CWE-798): 搜索密码、API 密钥、Token、私钥的硬编码使用。注意环境变量引用（如 `os.environ.get()`、`process.env`）是安全的，但 `os.environ.get("KEY", "default_value")` 中默认值可能是风险。

6. **弱加密/不安全的默认值** (CWE-327/328): 检查加密算法选择（禁止 MD5、SHA-1、DES、RC4），确认 TLS 版本要求（>= 1.2），检查随机数生成（必须使用安全随机源如 `secrets`、`crypto/rand`）。

### 数据保护类

7. **敏感数据泄露** (CWE-209/311/312): 检查错误响应是否包含堆栈跟踪、日志中是否记录敏感信息（密码、Token、PII）、静态和传输中数据是否加密。

8. **不安全的反序列化** (CWE-502): 搜索 `pickle.loads()`, `yaml.load()`, `JSON.parse()` 后直接实例化对象的模式。检查 `node-serialize.unserialize()`。

9. **原型链污染** (CWE-1321): 检查是否使用 `Object.assign()`、展开运算符、或递归合并函数处理用户输入的对象。搜索 `__proto__`、`constructor.prototype` 的直接引用。

10. **XSS/模板注入** (CWE-79/1336): 检查前端代码中的 `innerHTML`、`dangerouslySetInnerHTML`、`v-html`，以及后端模板渲染中的动态模板构建（Jinja2 `Template()`、Handlebars.compile()）。

### AI 特定类

11. **Prompt 注入/泄露** (OWASP ASI): 检查 AI/LLM 调用是否对用户输入做了注入防护（如分隔符、转义、系统提示词保护）。

12. **依赖供应链风险**: 检查新引入的依赖包，确认其知名度（下载量、维护者数量、发布时间）。

---

## 步骤 3: 7 步验证 Pipeline

对每个发现的安全问题，执行以下验证:

1. **证据验证** — 读取被标记的文件行，确认代码确实存在该问题
2. **数据流追踪** — 对于注入类发现，追踪输入来源（用户控制 vs 内部构造）
3. **规则范围** — 确认代码确实违反了安全规则（而非误报）
4. **缓解因素** — 检查是否有框架自动转义、锁文件、安全头、WAF 等缓解措施
5. **技术上下文** — 确认使用的技术栈是否已内置处理（如 ORM 自动参数化）
6. **暴露上下文** — 判断漏洞是否可被外部访问（公开 API / 认证接口 / 管理员功能 / 内部函数）
7. **利用路径** — 分析完整的利用链是否可行

判定结论: **CONFIRMED** (确认) | **LIKELY** (可能) | **FALSE-POSITIVE** (误报)

---

## 步骤 4: 输出安全审计报告

```bash
REPORT_DIR=".snsplay/task"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/ai-security-review-$(date +%s).json"

# 生成报告
echo "
=== AI 安全审查报告 ===
时间: $(date -Iseconds)
模式: $MODE

发现统计:
  确认 (CONFIRMED): $CONFIRMED_COUNT
  可能 (LIKELY): $LIKELY_COUNT
  误报 (FALSE-POSITIVE): $FP_COUNT
  总计: $TOTAL_COUNT

严重级别分布:
  Critical: $CRITICAL_COUNT
  High: $HIGH_COUNT
  Medium: $MEDIUM_COUNT
  Low: $LOW_COUNT

详细发现物:
" > "$REPORT"

# 逐个输出发现物
for finding in "${FINDINGS[@]}"; do
  echo "$finding" >> "$REPORT"
  echo "---" >> "$REPORT"
done

echo ""
echo "=== 审查完成 ==="
echo "报告已保存至: $REPORT"

sns_skill_end "success"
```

---

## Hook 集成

本技能可作为 qa-gate 的可选阶段被自动调用，或在 security-check hook 发现风险时由 Agent 主动触发。

**推荐触发条件**:
- PR 合并前 `qa-gate` 阶段
- security-check 发现任何 CWE-798/CWE-89/CWE-95 风险时
- 新增 API 端点或修改认证逻辑时
