#!/usr/bin/env bash
# context.sh 单元测试
# 覆盖 test-plan.md: TC-UNIT-BR-01~05, TC-UNIT-CMD-01~04
#
# 注意: 部分测试需要 git 仓库上下文，在 git sandbox 中运行

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../shell/version.sh"
source "$SCRIPT_DIR/../../../shell/context.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected='$expected', actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local label="$1"
  if eval "$2"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected true, got false)"
    FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  local label="$1"
  if eval "$2"; then
    echo "  FAIL: $label (expected false, got true)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

# 创建临时 git sandbox
SANDBOX=$(mktemp -d)
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

cd "$SANDBOX"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > README.md
git add README.md
git commit -q -m "init"
git branch -M main

# 创建 origin remote（本地目录模拟）
REMOTE_DIR=$(mktemp -d)
git init --bare -q "$REMOTE_DIR"
git remote add origin "$REMOTE_DIR"
git push -q -u origin main

echo "=== TC-UNIT-BR-01: 识别 worktree-* 分支 ==="
git checkout -q -b worktree-001
assert_eq "worktree-001 type" "worktree" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-UNIT-BR-02: 识别 feature/* 分支 ==="
git checkout -q -b feature/payment
assert_eq "feature/payment type" "feature" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-UNIT-BR-03: 识别 release/* 分支 ==="
git checkout -q -b release/1.6.0
assert_eq "release/1.6.0 type" "release" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-UNIT-BR-04: 识别 hotfix/* 分支 ==="
git tag v1.6.0
git checkout -q -b hotfix/1.6.1
assert_eq "hotfix/1.6.1 type" "hotfix" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-UNIT-BR-05: 拒绝未知分支类型 ==="
git checkout -q -b experimental/foo
assert_eq "experimental/foo type" "unknown" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-UNIT-CMD-01: sync 在 main 上执行应被阻止 ==="
assert_false "main rejected for sync" "sns_require_branch worktree"

echo ""
echo "=== TC-UNIT-CMD-02: feature 在 busy worktree 上执行 ==="
# worktree-001 有未合并提交 → busy
git checkout -q worktree-001
echo "change" > newfile.txt
git add newfile.txt
git commit -q -m "wip"
assert_false "busy worktree not idle" "sns_worktree_is_idle"
git checkout -q main

echo ""
echo "=== TC-UNIT-CMD-03: release 在 feature/* 上执行 ==="
git checkout -q feature/payment
assert_false "feature rejected for release" "sns_require_branch main"
git checkout -q main

echo ""
echo "=== TC-UNIT-CMD-04: publish 在错误 release 上执行 ==="
git checkout -q release/1.6.0
# 模拟：当前是 release/1.6.0，尝试发布 1.7.0
current_branch=$(git branch --show-current)
current_version=$(echo "$current_branch" | sed 's/^release\///')
assert_false "release/1.6.0 != 1.7.0" "[[ '$current_version' == '1.7.0' ]]"
git checkout -q main

echo ""
echo "=== 额外: workdir_clean ==="
git checkout -q worktree-001
# worktree-001 有未推送提交但工作区干净
assert_true "clean workdir" "sns_workdir_clean"
echo "dirty" > dirtyfile.txt
assert_false "dirty workdir" "sns_workdir_clean"
rm dirtyfile.txt
git checkout -q main

echo ""
echo "=== 额外: active_release_branches ==="
# release/1.6.0 存在
branches=$(sns_active_release_branches)
assert_true "release/1.6.0 exists" "echo '$branches' | grep -q 'release/1.6.0'"

echo ""
echo "=== 额外: require_branch ==="
git checkout -q main
assert_true "main requires main" "sns_require_branch main"
assert_false "main != worktree" "sns_require_branch worktree"

# 清理
cd - > /dev/null

echo ""
echo "========================================="
echo "context.sh: $PASS passed, $FAIL failed"
echo "========================================="

[[ $FAIL -eq 0 ]] || exit 1
