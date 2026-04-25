#!/usr/bin/env bash
# hotfix 集成测试
# 覆盖 hotfix 创建逻辑的关键路径

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/version.sh"
source "$SCRIPT_DIR/../../scripts/context.sh"

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

git tag -a "v1.6.0" -m "release v1.6.0"
git push -q origin v1.6.0

git checkout -q -b worktree-001 main
git checkout -q main

echo "=== TC-HOTFIX-01: 从 worktree 创建 hotfix 分支 ==="
git checkout -q worktree-001
latest_tag=$(sns_latest_tag)
assert_eq "latest tag" "v1.6.0" "$latest_tag"

# 自动计算目标版本: patch+1
target_version=$(sns_bump_version "$latest_tag" patch)
assert_eq "target version" "v1.6.1" "$target_version"

# 校验: 目标版本 > 线上版本
assert_true "v1.6.1 > v1.6.0" "sns_version_gt v1.6.1 v1.6.0"

# 校验: 目标 tag 不存在
assert_false "v1.6.1 not exist" "sns_tag_exists v1.6.1"

# 创建 hotfix 分支（从 tag checkout）
branch_version=$(echo "$target_version" | sed 's/^v//')
git checkout -b "hotfix/$branch_version" "$latest_tag"
assert_eq "hotfix branch" "hotfix/$branch_version" "$(git branch --show-current)"
assert_eq "branch type" "hotfix" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-HOTFIX-02: 不允许在 main 上创建 hotfix ==="
git checkout -q main
branch_type=$(sns_branch_type)
assert_false "main is not worktree" "[[ '$branch_type' == 'worktree' ]]"
git checkout -q main

echo ""
echo "=== TC-HOTFIX-03: hotfix 版本必须递增 ==="
# 不允许目标 <= 线上版本
assert_false "v1.6.0 not > v1.6.0" "sns_version_gt v1.6.0 v1.6.0"
assert_false "v1.5.9 not > v1.6.0" "sns_version_gt v1.5.9 v1.6.0"

echo ""
echo "=== TC-HOTFIX-04: 指定版本参数校验 ==="
# 合法指定版本
specified="v1.6.2"
assert_true "v1.6.2 valid format" "sns_validate_version v1.6.2"
assert_true "v1.6.2 > v1.6.0" "sns_version_gt v1.6.2 v1.6.0"
assert_false "v1.6.2 not exist" "sns_tag_exists v1.6.2"

echo ""
echo "=== TC-HOTFIX-05: 脏工作区阻止 hotfix ==="
git checkout -q worktree-001
echo "dirty" > dirtyfile.txt
assert_false "dirty workdir blocked" "sns_workdir_clean"
rm dirtyfile.txt
git checkout -q main

cd - > /dev/null

echo ""
echo "==========================================="
echo "test_hotfix.sh: $PASS passed, $FAIL failed"
echo "==========================================="

[[ $FAIL -eq 0 ]] || exit 1
