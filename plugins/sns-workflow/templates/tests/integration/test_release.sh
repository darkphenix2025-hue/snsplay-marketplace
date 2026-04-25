#!/usr/bin/env bash
# release 集成测试
# 覆盖 test-plan.md: TC-REL-01~03

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

git checkout -q -b worktree-001 main
git checkout -q main

echo "=== TC-REL-01: 从 main 创建 release ==="
git checkout -q main
branch_type=$(sns_branch_type)
assert_eq "on main" "main" "$branch_type"
assert_true "main is clean" "sns_workdir_clean"

# 计算 release 版本
latest_tag=$(sns_latest_tag)
assert_eq "latest tag" "v1.5.0" "$latest_tag"

release_version=$(sns_bump_version "$latest_tag" minor)
assert_eq "release version" "v1.6.0" "$release_version"

# 校验版本递增
assert_true "v1.6.0 > v1.5.0" "sns_version_gt $release_version $latest_tag"

# 校验无同名分支
branch_ver=$(echo "$release_version" | sed 's/^v//')
release_branch="release/$branch_ver"
assert_false "branch not exist" "git show-ref --verify --quiet refs/heads/$release_branch 2>/dev/null"

# 创建 release 分支
git checkout -b "$release_branch"
assert_eq "release branch created" "$release_branch" "$(git branch --show-current)"
assert_eq "release type" "release" "$(sns_branch_type)"
git checkout -q main

echo ""
echo "=== TC-REL-02: release 版本不能小于等于线上版本 ==="
# 尝试创建 release/1.5.0 (等于线上 v1.5.0)
assert_false "v1.5.0 not > v1.5.0" "sns_version_gt v1.5.0 v1.5.0"

# 尝试创建 release/1.4.0 (小于线上)
assert_false "v1.4.0 not > v1.5.0" "sns_version_gt v1.4.0 v1.5.0"

echo ""
echo "=== TC-REL-03: 非 main 分支拒绝创建 release ==="
git checkout -q worktree-001
branch_type=$(sns_branch_type)
assert_eq "worktree type" "worktree" "$branch_type"
assert_false "worktree is not main" "[[ '$branch_type' == 'main' ]]"
git checkout -q main

echo ""
echo "=== TC-REL-EXTRA: 活动存在时阻止新 release ==="
# release/1.6.0 已存在
active=$(sns_active_release_branches)
assert_true "release/1.6.0 exists" "echo '$active' | grep -q 'release/1.6.0'"

echo ""
echo "=== TC-REL-EXTRA: 脏工作区阻止创建 ==="
git checkout -q main
echo "dirty" > dirtyfile.txt
assert_false "dirty workdir blocks" "sns_workdir_clean"
rm dirtyfile.txt

cd - > /dev/null

echo ""
echo "============================================"
echo "test_release.sh: $PASS passed, $FAIL failed"
echo "============================================"

[[ $FAIL -eq 0 ]] || exit 1
