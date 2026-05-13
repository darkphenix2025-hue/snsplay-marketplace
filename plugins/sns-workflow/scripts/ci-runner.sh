#!/usr/bin/env bash
# ci-runner.sh — 通用项目感知 CI 检查
# 自动检测项目类型并执行对应的 lint/test/build 命令
# 支持：Node.js / Python / Go / Rust / 用户自定义配置
# 优雅降级：项目无对应工具时 skip，不阻断流程

[[ -n "$_SNS_CI_LOADED" ]] && return 0
_SNS_CI_LOADED=true

# === 全局变量（由 sns_ci_detect 设置）===
CI_TYPE=""        # nodejs | python | go | rust | custom | unknown
CI_PM=""          # npm | yarn | pnpm | bun | pip | poetry | uv | none
CI_LINT_RESULT="" # pass | fail | skip
CI_TEST_RESULT=""
CI_BUILD_RESULT=""

# 超时保护
SNS_CI_TIMEOUT=${SNS_CI_TIMEOUT:-120}

# === 辅助函数 ===

_sns_ci_ts_ms() {
  local ts
  ts=$(date +%s%N 2>/dev/null || echo "0")
  if [[ "$ts" == "0" ]]; then
    echo 0
  else
    echo $(( ts / 1000000 ))
  fi
}

_sns_ci_duration() {
  local start_ms=$1
  local end_ms
  end_ms=$(_sns_ci_ts_ms)
  if [[ "$start_ms" -eq 0 ]] || [[ "$end_ms" -eq 0 ]]; then
    echo 0
  else
    echo $(( end_ms - start_ms ))
  fi
}

_sns_ci_run() {
  local label=$1
  local cmd=$2
  local timeout=${3:-$SNS_CI_TIMEOUT}

  echo "  → $label: $cmd"
  local start_ms
  start_ms=$(_sns_ci_ts_ms)

  local output
  if command -v timeout &>/dev/null; then
    output=$(eval "$cmd" 2>&1)
    local exit_code=$?
  else
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
  fi

  local duration_ms
  duration_ms=$(_sns_ci_duration "$start_ms")

  if [[ $exit_code -eq 0 ]]; then
    echo "    ✓ $label 通过 (${duration_ms}ms)"
    return 0
  else
    echo "    ✗ $label 失败 (exit=$exit_code, ${duration_ms}ms)"
    # 输出前 10 行错误摘要
    local err_head
    err_head=$(echo "$output" | head -10)
    if [[ -n "$err_head" ]]; then
      echo "$err_head" | sed 's/^/    | /'
    fi
    return 1
  fi
}

# === 核心函数 ===

sns_ci_detect() {
  CI_TYPE="unknown"
  CI_PM="none"

  # 1. 检查用户自定义配置
  local ROOT
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
  if [[ -f "$ROOT/.snsplay/ci.json" ]]; then
    CI_TYPE="custom"
    CI_PM="custom"
    return 0
  fi

  # 2. Node.js 项目检测
  if [[ -f "package.json" ]]; then
    CI_TYPE="nodejs"
    # 包管理器检测
    if [[ -f "bun.lockb" ]] || [[ -f "bun.lock" ]]; then
      CI_PM="bun"
    elif [[ -f "pnpm-lock.yaml" ]]; then
      CI_PM="pnpm"
    elif [[ -f "yarn.lock" ]]; then
      CI_PM="yarn"
    else
      CI_PM="npm"
    fi
    return 0
  fi

  # 3. Python 项目检测
  if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
    CI_TYPE="python"
    # 包管理器检测
    if [[ -f "poetry.lock" ]]; then
      CI_PM="poetry"
    elif [[ -f "uv.lock" ]]; then
      CI_PM="uv"
    else
      CI_PM="pip"
    fi
    return 0
  fi

  # 4. Go 项目检测
  if [[ -f "go.mod" ]]; then
    CI_TYPE="go"
    CI_PM="none"
    return 0
  fi

  # 5. Rust 项目检测
  if [[ -f "Cargo.toml" ]]; then
    CI_TYPE="rust"
    CI_PM="cargo"
    return 0
  fi
}

sns_ci_lint() {
  CI_LINT_RESULT="skip"
  local ci_config="$ROOT/.snsplay/ci.json"

  if [[ -f "$ci_config" ]]; then
    # 用户自定义配置
    local cmd
    cmd=$(python3 -c "import json; d=json.load(open('$ci_config')); print(d.get('lint',''))" 2>/dev/null || echo "")
    if [[ -n "$cmd" ]]; then
      if _sns_ci_run "Lint (custom)" "$cmd"; then
        CI_LINT_RESULT="pass"
      else
        CI_LINT_RESULT="fail"
        return 1
      fi
    fi
    return 0
  fi

  case "$CI_TYPE" in
    nodejs)
      # 检查 package.json 中是否有 lint script
      local has_lint=false
      if [[ -f "package.json" ]]; then
        has_lint=$(python3 -c "
import json
with open('package.json') as f: d=json.load(f)
print('true' if 'lint' in d.get('scripts',{}) else 'false')
" 2>/dev/null || echo "false")
      fi

      if [[ "$has_lint" == "true" ]]; then
        local pm_cmd
        case "$CI_PM" in
          yarn)  pm_cmd="yarn lint" ;;
          pnpm)  pm_cmd="pnpm lint" ;;
          bun)   pm_cmd="bun run lint" ;;
          *)     pm_cmd="npm run lint" ;;
        esac
        if _sns_ci_run "Lint ($CI_PM lint)" "$pm_cmd"; then
          CI_LINT_RESULT="pass"
        else
          CI_LINT_RESULT="fail"
          return 1
        fi
      else
        # 尝试直接用工具检查
        if command -v eslint &>/dev/null; then
          if _sns_ci_run "Lint (eslint)" "eslint ." "$SNS_CI_TIMEOUT"; then
            CI_LINT_RESULT="pass"
          else
            CI_LINT_RESULT="fail"
            return 1
          fi
        elif command -v jshint &>/dev/null; then
          if _sns_ci_run "Lint (jshint)" "jshint ."; then
            CI_LINT_RESULT="pass"
          else
            CI_LINT_RESULT="fail"
            return 1
          fi
        else
          echo "  → Lint: 未配置 lint 工具 (skip)"
          CI_LINT_RESULT="skip"
        fi
      fi
      ;;

    python)
      if command -v ruff &>/dev/null; then
        if _sns_ci_run "Lint (ruff)" "ruff check ."; then
          CI_LINT_RESULT="pass"
        else
          CI_LINT_RESULT="fail"
          return 1
        fi
      elif command -v flake8 &>/dev/null; then
        if _sns_ci_run "Lint (flake8)" "flake8 ."; then
          CI_LINT_RESULT="pass"
        else
          CI_LINT_RESULT="fail"
          return 1
        fi
      else
        echo "  → Lint: 未配置 lint 工具 (skip)"
        CI_LINT_RESULT="skip"
      fi
      ;;

    go)
      if command -v golangci-lint &>/dev/null; then
        if _sns_ci_run "Lint (golangci-lint)" "golangci-lint run"; then
          CI_LINT_RESULT="pass"
        else
          CI_LINT_RESULT="fail"
          return 1
        fi
      elif command -v go &>/dev/null; then
        if _sns_ci_run "Lint (go vet)" "go vet ./..."; then
          CI_LINT_RESULT="pass"
        else
          CI_LINT_RESULT="fail"
          return 1
        fi
      else
        echo "  → Lint: go 工具链不可用 (skip)"
        CI_LINT_RESULT="skip"
      fi
      ;;

    rust)
      if command -v cargo &>/dev/null; then
        if _sns_ci_run "Lint (cargo clippy)" "cargo clippy -- -D warnings" "$(( SNS_CI_TIMEOUT * 2 ))"; then
          CI_LINT_RESULT="pass"
        else
          CI_LINT_RESULT="fail"
          return 1
        fi
      else
        echo "  → Lint: cargo 不可用 (skip)"
        CI_LINT_RESULT="skip"
      fi
      ;;

    *)
      echo "  → Lint: 未知项目类型 (skip)"
      CI_LINT_RESULT="skip"
      ;;
  esac
  return 0
}

sns_ci_test() {
  CI_TEST_RESULT="skip"
  local ci_config="$ROOT/.snsplay/ci.json"

  if [[ -f "$ci_config" ]]; then
    local cmd
    cmd=$(python3 -c "import json; d=json.load(open('$ci_config')); print(d.get('test',''))" 2>/dev/null || echo "")
    if [[ -n "$cmd" ]]; then
      if _sns_ci_run "Test (custom)" "$cmd" "$(( SNS_CI_TIMEOUT * 2 ))"; then
        CI_TEST_RESULT="pass"
      else
        CI_TEST_RESULT="fail"
        return 1
      fi
    fi
    return 0
  fi

  case "$CI_TYPE" in
    nodejs)
      local has_test=false
      if [[ -f "package.json" ]]; then
        has_test=$(python3 -c "
import json
with open('package.json') as f: d=json.load(f)
print('true' if 'test' in d.get('scripts',{}) else 'false')
" 2>/dev/null || echo "false")
      fi

      if [[ "$has_test" == "true" ]]; then
        local pm_cmd
        case "$CI_PM" in
          yarn)  pm_cmd="yarn test" ;;
          pnpm)  pm_cmd="pnpm test" ;;
          bun)   pm_cmd="bun test" ;;
          *)     pm_cmd="npm test" ;;
        esac
        if _sns_ci_run "Test ($CI_PM test)" "$pm_cmd" "$(( SNS_CI_TIMEOUT * 2 ))"; then
          CI_TEST_RESULT="pass"
        else
          CI_TEST_RESULT="fail"
          return 1
        fi
      else
        echo "  → Test: 未配置 test script (skip)"
        CI_TEST_RESULT="skip"
      fi
      ;;

    python)
      if command -v pytest &>/dev/null; then
        if _sns_ci_run "Test (pytest)" "pytest --tb=short -q" "$(( SNS_CI_TIMEOUT * 2 ))"; then
          CI_TEST_RESULT="pass"
        else
          CI_TEST_RESULT="fail"
          return 1
        fi
      elif command -v unittest &>/dev/null 2>/dev/null || python3 -m unittest --help &>/dev/null 2>&1; then
        if _sns_ci_run "Test (unittest)" "python3 -m discover -s . -p 'test_*.py'"; then
          CI_TEST_RESULT="pass"
        else
          CI_TEST_RESULT="fail"
          return 1
        fi
      else
        echo "  → Test: 未配置 test 工具 (skip)"
        CI_TEST_RESULT="skip"
      fi
      ;;

    go)
      if command -v go &>/dev/null; then
        if _sns_ci_run "Test (go test)" "go test ./..." "$(( SNS_CI_TIMEOUT * 2 ))"; then
          CI_TEST_RESULT="pass"
        else
          CI_TEST_RESULT="fail"
          return 1
        fi
      else
        echo "  → Test: go 工具链不可用 (skip)"
        CI_TEST_RESULT="skip"
      fi
      ;;

    rust)
      if command -v cargo &>/dev/null; then
        if _sns_ci_run "Test (cargo test)" "cargo test" "$(( SNS_CI_TIMEOUT * 3 ))"; then
          CI_TEST_RESULT="pass"
        else
          CI_TEST_RESULT="fail"
          return 1
        fi
      else
        echo "  → Test: cargo 不可用 (skip)"
        CI_TEST_RESULT="skip"
      fi
      ;;

    *)
      echo "  → Test: 未知项目类型 (skip)"
      CI_TEST_RESULT="skip"
      ;;
  esac
  return 0
}

sns_ci_build() {
  CI_BUILD_RESULT="skip"
  local ci_config="$ROOT/.snsplay/ci.json"

  if [[ -f "$ci_config" ]]; then
    local cmd
    cmd=$(python3 -c "import json; d=json.load(open('$ci_config')); print(d.get('build',''))" 2>/dev/null || echo "")
    if [[ -n "$cmd" ]]; then
      if _sns_ci_run "Build (custom)" "$cmd" "$(( SNS_CI_TIMEOUT * 2 ))"; then
        CI_BUILD_RESULT="pass"
      else
        CI_BUILD_RESULT="fail"
        return 1
      fi
    fi
    return 0
  fi

  case "$CI_TYPE" in
    nodejs)
      local has_build=false
      if [[ -f "package.json" ]]; then
        has_build=$(python3 -c "
import json
with open('package.json') as f: d=json.load(f)
print('true' if 'build' in d.get('scripts',{}) else 'false')
" 2>/dev/null || echo "false")
      fi

      if [[ "$has_build" == "true" ]]; then
        local pm_cmd
        case "$CI_PM" in
          yarn)  pm_cmd="yarn build" ;;
          pnpm)  pm_cmd="pnpm build" ;;
          bun)   pm_cmd="bun run build" ;;
          *)     pm_cmd="npm run build" ;;
        esac
        if _sns_ci_run "Build ($CI_PM build)" "$pm_cmd" "$(( SNS_CI_TIMEOUT * 2 ))"; then
          CI_BUILD_RESULT="pass"
        else
          CI_BUILD_RESULT="fail"
          return 1
        fi
      else
        echo "  → Build: 未配置 build script (skip)"
        CI_BUILD_RESULT="skip"
      fi
      ;;

    go)
      if command -v go &>/dev/null; then
        if _sns_ci_run "Build (go build)" "go build ./..."; then
          CI_BUILD_RESULT="pass"
        else
          CI_BUILD_RESULT="fail"
          return 1
        fi
      else
        echo "  → Build: go 工具链不可用 (skip)"
        CI_BUILD_RESULT="skip"
      fi
      ;;

    rust)
      if command -v cargo &>/dev/null; then
        if _sns_ci_run "Build (cargo build)" "cargo build" "$(( SNS_CI_TIMEOUT * 3 ))"; then
          CI_BUILD_RESULT="pass"
        else
          CI_BUILD_RESULT="fail"
          return 1
        fi
      else
        echo "  → Build: cargo 不可用 (skip)"
        CI_BUILD_RESULT="skip"
      fi
      ;;

    *)
      # Python 无标准 build 步骤
      echo "  → Build: $CI_TYPE 无标准 build (skip)"
      CI_BUILD_RESULT="skip"
      ;;
  esac
  return 0
}

sns_ci_all() {
  local has_fail=false

  echo ""
  echo "=== CI 检查 ==="
  echo "  项目类型: $CI_TYPE"
  echo "  包管理器: $CI_PM"
  echo ""

  sns_ci_lint || has_fail=true
  echo ""
  sns_ci_test || has_fail=true
  echo ""
  sns_ci_build || has_fail=true

  echo ""
  if $has_fail; then
    echo "=== CI 结果: 部分失败 ==="
    echo "  Lint:  $CI_LINT_RESULT"
    echo "  Test:  $CI_TEST_RESULT"
    echo "  Build: $CI_BUILD_RESULT"
    return 1
  else
    echo "=== CI 结果: 通过 ==="
    echo "  Lint:  $CI_LINT_RESULT"
    echo "  Test:  $CI_TEST_RESULT"
    echo "  Build: $CI_BUILD_RESULT"
    return 0
  fi
}
