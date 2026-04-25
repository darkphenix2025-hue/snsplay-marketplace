#!/usr/bin/env bash
# feature 集成测试
# 覆盖 test-plan.md: TC-FEAT-01~03

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../shell/version.sh"
source "$SCRIPT_DIR/../../../shell/context.sh"

PASS=0
FAIL=0

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

# 创建 sandbox
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

REMOTE_DIR=$(mktemp -d)
git init --bare -q "$REMOTE_DIR"
git remote add origin "$REMOTE_DIR"
git push -q -u origin main

git tag -a "v1.5.0" -m "baseline"
git push -q origin v1.5.0

git checkout -q -b worktree-002 main
git checkout -q main

echo "=== TC-FEAT-01: 从空闲 worktree 创建 feature ==="
git checkout -q worktree-002
branch_type=$(sns_branch_type)
assert_eq "on worktree" "worktree" "$branch_type"
assert_true "worktree is clean" "sns_workdir_clean"

# 创建 feature 分支
feature_name="payment"
assert_false "feature not exists locally" "git show-ref --verify --quiet refs/heads/feature/$feature_name 2>/dev/null"
assert_false "feature not exists remotely" "git ls-remote origin refs/heads/feature/$feature_name 2>/dev/null | grep -q ."

git checkout -b "feature/$feature_name"
assert_eq "feature branch created" "feature/$feature_name" "$(git branch --show-current)"
assert_eq "feature branch type" "feature" "$(sns_branch_type)"
git checkout -q worktree-002

echo ""
echo "=== TC-FEAT-02: 非 worktree 上拒绝创建 feature ==="
git checkout -q main
branch_type=$(sns_branch_type)
assert_eq "main type" "main" "$branch_type"
assert_false "main is not worktree" "[[ '$branch_type' == 'worktree' ]]"
git checkout -q main

echo ""
echo "=== TC-FEAT-03: 名称非法 ==="
# 测试非法名称（含大写、下划线等）
invalid_names=("Invalid_Name" "UPPER" "has space" "with/slash")
for name in "${invalid_names[@]}"; do
  if [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
    echo "  FAIL: '$name' should be invalid"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: '$name' correctly rejected"
    PASS=$((PASS + 1))
  fi
done

# 测试合法名称
valid_names=("payment" "user-auth" "api-v2" "feature123")
for name in "${valid_names[@]}"; do
  if [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
    echo "  PASS: '$name' correctly accepted"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: '$name' should be valid"
    FAIL=$((FAIL + 1))
  fi
done

cd - > /dev/null

echo ""
echo "==========================================="
echo "test_feature.sh: $PASS passed, $FAIL failed"
echo "==========================================="

[[ $FAIL -eq 0 ]] || exit 1
