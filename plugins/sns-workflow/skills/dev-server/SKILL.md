---
name: sns-workflow:dev-server
description: Per-worktree 开发服务器管理 —— 自动检测项目类型、启动/停止/端口分配/健康检查。配合 ui-verify 实现真正的 per-worktree 验证闭环。
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Per-worktree 开发服务器管理

自动检测项目类型，为当前 worktree 启动独立的开发服务器实例。每个 worktree 运行在独立端口上，互不冲突。配合 ui-verify 实现完整的 per-worktree 验证闭环。

**用法**:
- `start [--port <port>] [--open]` — 启动开发服务器
- `stop` — 停止当前 worktree 的服务器
- `status` — 显示所有 worktree 服务器状态
- `--help` — 显示帮助

**数据目录**: `.snsplay/task/dev-servers.json`（跟踪所有 running servers）

---

## 步骤 1: 环境验证

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"
mkdir -p "$TASK_DIR"

SERVER_TRACKER="$TASK_DIR/dev-servers.json"

# 初始化 tracker（如果不存在）
if [[ ! -f "$SERVER_TRACKER" ]]; then
  echo '{"servers":[]}' > "$SERVER_TRACKER"
fi
```

---

## 步骤 2: 命令解析

```bash
COMMAND="start"
CUSTOM_PORT=""
OPEN_BROWSER=false

for arg in "$@"; do
  case "$arg" in
    start) COMMAND="start" ;;
    stop) COMMAND="stop" ;;
    status) COMMAND="status" ;;
    --port) ;; # skip, next arg is port
    --open) OPEN_BROWSER=true ;;
    *)
      if [[ "$CUSTOM_PORT" == "PENDING" ]]; then
        CUSTOM_PORT="$arg"
      elif [[ -z "$CUSTOM_PORT" ]] && [[ "$arg" =~ ^[0-9]+$ ]]; then
        CUSTOM_PORT="$arg"
      fi
      ;;
  esac
done

# 如果 --port 后面没跟值，尝试下一个参数
if [[ "$CUSTOM_PORT" == "PENDING" ]]; then
  CUSTOM_PORT="8080"  # 默认回退
fi

[[ -z "$CUSTOM_PORT" ]] && CUSTOM_PORT=""
```

---

## 步骤 3: 项目类型检测

自动检测项目类型并确定 dev server 命令和默认端口。

```bash
PROJECT_TYPE="unknown"
DEV_COMMAND=""
DEFAULT_PORT=""
BUILD_DIR=""

if [[ -f "package.json" ]]; then
  # 检测框架类型
  if grep -q '"next"' package.json 2>/dev/null; then
    PROJECT_TYPE="nextjs"
    DEV_COMMAND="npx next dev"
    DEFAULT_PORT="3000"
    BUILD_DIR=".next"
  elif grep -q '"vite"' package.json 2>/dev/null || grep -q '"@vitejs' package.json 2>/dev/null; then
    PROJECT_TYPE="vite"
    if grep -q '"react"' package.json 2>/dev/null; then
      PROJECT_TYPE="vite-react"
    elif grep -q '"vue"' package.json 2>/dev/null; then
      PROJECT_TYPE="vite-vue"
    fi
    DEV_COMMAND="npx vite"
    DEFAULT_PORT="5173"
    BUILD_DIR="dist"
  elif grep -q '"create-react-app"' package.json 2>/dev/null || grep -q '"react-scripts"' package.json 2>/dev/null; then
    PROJECT_TYPE="cra"
    DEV_COMMAND="npx react-scripts start"
    DEFAULT_PORT="3000"
    BUILD_DIR="build"
  elif grep -q '"svelte"' package.json 2>/dev/null; then
    PROJECT_TYPE="svelte"
    DEV_COMMAND="npx svelte-kit dev"
    DEFAULT_PORT="5173"
    BUILD_DIR=".svelte-kit"
  elif grep -q '"remix"' package.json 2>/dev/null; then
    PROJECT_TYPE="remix"
    DEV_COMMAND="npx remix dev"
    DEFAULT_PORT="3000"
    BUILD_DIR="build"
  elif grep -q '"nuxt"' package.json 2>/dev/null; then
    PROJECT_TYPE="nuxt"
    DEV_COMMAND="npx nuxt dev"
    DEFAULT_PORT="3000"
    BUILD_DIR=".nuxt"
  elif grep -q '"astro"' package.json 2>/dev/null; then
    PROJECT_TYPE="astro"
    DEV_COMMAND="npx astro dev"
    DEFAULT_PORT="4321"
    BUILD_DIR="dist"
  elif grep -q '"express"' package.json 2>/dev/null; then
    PROJECT_TYPE="express"
    DEV_COMMAND="npx nodemon server.js"
    DEFAULT_PORT="3000"
    BUILD_DIR=""
  else
    # 检查 scripts.dev 或 scripts.start
    if grep -q '"dev"' package.json 2>/dev/null; then
      DEV_COMMAND=$(python3 -c "
import json
with open('package.json') as f: d = json.load(f)
print(d.get('scripts',{}).get('dev',''))" 2>/dev/null)
      DEV_COMMAND="npm run dev"
      PROJECT_TYPE="npm-scripts"
    else
      DEV_COMMAND="npx http-server ."
      DEFAULT_PORT="8080"
      PROJECT_TYPE="static"
    fi
  fi

  # 检测包管理器
  if [[ -f "yarn.lock" ]]; then
    DEV_COMMAND=$(echo "$DEV_COMMAND" | sed 's/npx /yarn /g' | sed 's/npm run/yarn /g')
  elif [[ -f "pnpm-lock.yaml" ]]; then
    DEV_COMMAND=$(echo "$DEV_COMMAND" | sed 's/npx /pnpm /g' | sed 's/npm run/pnpm /g')
  elif [[ -f "bun.lockb" ]] || [[ -f "bun.lock" ]]; then
    DEV_COMMAND=$(echo "$DEV_COMMAND" | sed 's/npx /bun /g' | sed 's/npm run/bun /g')
  fi

elif [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
  if grep -q 'fastapi\|flask\|django' pyproject.toml 2>/dev/null || grep -q 'fastapi\|flask\|django' requirements.txt 2>/dev/null; then
    if grep -q 'fastapi' pyproject.toml 2>/dev/null || grep -q 'fastapi' requirements.txt 2>/dev/null; then
      PROJECT_TYPE="fastapi"
      DEV_COMMAND="uvicorn main:app --reload"
    elif grep -q 'flask' pyproject.toml 2>/dev/null || grep -q 'flask' requirements.txt 2>/dev/null; then
      PROJECT_TYPE="flask"
      DEV_COMMAND="flask run"
    else
      PROJECT_TYPE="django"
      DEV_COMMAND="python manage.py runserver"
    fi
    DEFAULT_PORT="8000"
  else
    PROJECT_TYPE="python-static"
    DEV_COMMAND="python -m http.server"
    DEFAULT_PORT="8000"
  fi

elif [[ -f "Cargo.toml" ]]; then
  PROJECT_TYPE="rust"
  DEV_COMMAND="cargo watch -x 'run'"
  DEFAULT_PORT="8080"

elif [[ -f "go.mod" ]]; then
  PROJECT_TYPE="go"
  DEV_COMMAND="go run main.go"
  DEFAULT_PORT="8080"

else
  PROJECT_TYPE="static"
  DEV_COMMAND="npx http-server ."
  DEFAULT_PORT="8080"
fi

PORT="${CUSTOM_PORT:-$DEFAULT_PORT}"

echo "=== 开发服务器 ==="
echo "项目类型: $PROJECT_TYPE"
echo "默认命令: $DEV_COMMAND"
echo "端口: $PORT"
```

---

## 步骤 4: 命令执行

### 4a: status — 显示所有服务器状态

```bash
if [[ "$COMMAND" == "status" ]]; then
  echo ""
  echo "=== 工作树服务器状态 ==="

  servers=$(python3 -c "
import json
with open('$SERVER_TRACKER') as f:
    d = json.load(f)
for s in d.get('servers', []):
    print(f\"{s['branch']}|{s['port']}|{s['type']}|{s['pid']}|{s['url']}\")
" 2>/dev/null)

  if [[ -z "$servers" ]]; then
    echo "  无运行中的服务器"
  else
    while IFS='|' read -r s_branch s_port s_type s_pid s_url; do
      # 检查进程是否仍在运行
      if kill -0 "$s_pid" 2>/dev/null; then
        status="运行中"
        icon="✓"
      else
        status="已停止"
        icon="✗"
      fi
      echo "  $icon [$s_branch] $s_url ($s_type, PID: $s_pid, 状态: $status)"
    done <<< "$servers"
  fi

  echo ""
  echo "提示: 运行 /sns-workflow:dev-server start 启动服务器"
  exit 0
fi
```

### 4b: stop — 停止当前 worktree 的服务器

```bash
if [[ "$COMMAND" == "stop" ]]; then
  echo ""
  echo "=== 停止服务器: $current_branch ==="

  # 查找并停止
  found=false
  servers=$(python3 -c "
import json
with open('$SERVER_TRACKER') as f:
    d = json.load(f)
for s in d.get('servers', []):
    print(f\"{s['branch']}|{s['port']}|{s['pid']}\")
" 2>/dev/null)

  while IFS='|' read -r s_branch s_port s_pid; do
    [[ -z "$s_branch" ]] && continue
    if [[ "$s_branch" == "$current_branch" ]]; then
      if kill -0 "$s_pid" 2>/dev/null; then
        kill "$s_pid" 2>/dev/null && echo "  已停止 PID $s_pid (端口 $s_port)"
      else
        echo "  进程已不存在 (PID $s_pid)"
      fi
      found=true
    fi
  done <<< "$servers"

  if $found; then
    # 从 tracker 中移除
    python3 -c "
import json
with open('$SERVER_TRACKER') as f:
    d = json.load(f)
d['servers'] = [s for s in d.get('servers', []) if s['branch'] != '$current_branch']
with open('$SERVER_TRACKER', 'w') as f:
    json.dump(d, f, indent=2)
"
  else
    echo "  当前分支无运行中的服务器"
  fi

  exit 0
fi
```

### 4c: start — 启动开发服务器

```bash
if [[ "$COMMAND" == "start" ]]; then
  # 检查是否已有服务器运行
  existing_pid=$(python3 -c "
import json
with open('$SERVER_TRACKER') as f:
    d = json.load(f)
for s in d.get('servers', []):
    if s['branch'] == '$current_branch':
        print(s['pid'])
        break
" 2>/dev/null)

  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "  服务器已在运行 (PID: $existing_pid, 端口: $PORT)"
    echo "  URL: http://localhost:$PORT"
    echo ""
    echo "停止: /sns-workflow:dev-server stop"
    exit 0
  fi

  # 检查端口是否被占用
  if lsof -i :"$PORT" >/dev/null 2>&1; then
    echo "  端口 $PORT 已被占用"
    echo ""
    echo "选择:"
    echo "  1. 使用其他端口: /sns-workflow:dev-server start --port <port>"
    echo "  2. 停止占用进程: lsof -i :$PORT | grep LISTEN"
    echo "  3. 查看状态: /sns-workflow:dev-server status"
    exit 1
  fi

  echo ""
  echo "=== 启动开发服务器 ==="
  echo "项目类型: $PROJECT_TYPE"
  echo "命令: $DEV_COMMAND"
  echo "端口: $PORT"
  echo "分支: $current_branch"
  echo ""

  # 构建完整命令（添加端口参数）
  FULL_COMMAND="$DEV_COMMAND"
  case "$PROJECT_TYPE" in
    vite|vite-react|vite-vue)
      FULL_COMMAND="$DEV_COMMAND --port $PORT"
      ;;
    nextjs|nuxt|svelte|remix|astro)
      FULL_COMMAND="$DEV_COMMAND -- -p $PORT"
      ;;
    fastapi|flask|django)
      FULL_COMMAND="$DEV_COMMAND --port $PORT"
      ;;
    static|cra)
      FULL_COMMAND="$DEV_COMMAND -p $PORT"
      ;;
    *)
      FULL_COMMAND="$DEV_COMMAND --port $PORT"
      ;;
  esac

  # 后台启动
  nohup $FULL_COMMAND > "$TASK_DIR/dev-server-${current_branch}.log" 2>&1 &
  SERVER_PID=$!

  echo "  PID: $SERVER_PID"
  echo "  日志: $TASK_DIR/dev-server-${current_branch}.log"

  # 健康检查（等待服务器启动）
  echo ""
  echo "等待服务器启动..."
  READY=false
  for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE "^[23]"; then
      READY=true
      break
    fi
    # 检查进程是否存活
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "  错误: 服务器进程已退出 (PID $SERVER_PID)"
      echo "  查看日志: cat $TASK_DIR/dev-server-${current_branch}.log"
      exit 1
    fi
    sleep 1
  done

  if $READY; then
    SERVER_URL="http://localhost:$PORT"

    # 注册到 tracker
    python3 -c "
import json, datetime
with open('$SERVER_TRACKER') as f:
    d = json.load(f)
# 移除同分支旧记录
d['servers'] = [s for s in d.get('servers', []) if s['branch'] != '$current_branch']
d['servers'].append({
    'branch': '$current_branch',
    'port': $PORT,
    'type': '$PROJECT_TYPE',
    'pid': $SERVER_PID,
    'url': '$SERVER_URL',
    'started_at': datetime.datetime.utcnow().isoformat() + 'Z'
})
with open('$SERVER_TRACKER', 'w') as f:
    json.dump(d, f, indent=2)
"

    echo ""
    echo "=== 服务器已启动 ==="
    echo "URL: $SERVER_URL"
    echo "PID: $SERVER_PID"
    echo "分支: $current_branch"
    echo "类型: $PROJECT_TYPE"
    echo ""
    echo "后续操作:"
    echo "  停止: /sns-workflow:dev-server stop"
    echo "  状态: /sns-workflow:dev-server status"
    echo "  UI 验证: /sns-workflow:ui-verify --verify"
    echo "  日志: tail -f $TASK_DIR/dev-server-${current_branch}.log"
  else
    echo "  错误: 服务器启动超时 (30s)"
    echo "  查看日志: tail -20 $TASK_DIR/dev-server-${current_branch}.log"
    exit 1
  fi
fi
```

---

## 步骤 5: 与 ui-verify 集成

启动服务器后，Agent 可自动调用 ui-verify 进行验证：

```bash
# 自动化验证流程（Agent 执行）:
# 1. /sns-workflow:dev-server start     → 启动服务器于 http://localhost:$PORT
# 2. 等待 30 秒直到服务器就绪
# 3. /sns-workflow:ui-verify --verify    → 对比基线，检测 UI 回归
# 4. /sns-workflow:dev-server stop       → 停止服务器
```

**验证闭环**:
```
dev-server start → ui-verify snapshot/verify → 确认无回归 → commit → dev-server stop
```

---

## 辅助: 清理孤立进程

```bash
# 清理已退出但仍留在 tracker 中的记录
python3 -c "
import json
with open('$SERVER_TRACKER') as f:
    d = json.load(f)
cleaned = []
for s in d.get('servers', []):
    if not kill -0(s['pid'], 2>/dev/null):
        print(f\"清理孤立记录: {s['branch']} (PID {s['pid']})\")
    else:
        cleaned.append(s)
d['servers'] = cleaned
with open('$SERVER_TRACKER', 'w') as f:
    json.dump(d, f, indent=2)
"
```
