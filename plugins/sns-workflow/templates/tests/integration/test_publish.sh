#!/usr/bin/env bash
# publish 集成测试
# 覆盖 test-plan.md: TC-PUB-01~03

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

# 创建 release 分支
git checkout -q -b release/1.6.0 main
echo "rc fix" > rcfix.txt
git add rcfix.txt
git commit -q -m "rc fix"
git checkout -q main

echo "=== TC-PUB-01: 在匹配 release 分支上发布 ==="
git checkout -q release/1.6.0
branch_type=$(sns_branch_type)
assert_eq "on release" "release" "$branch_type"
assert_true "workdir clean" "sns_workdir_clean"

# 提取版本号
current_branch=$(git branch --show-current)
branch_version=$(echo "$current_branch" | sed 's/^release\///')
target_tag="v$branch_version"
assert_eq "target tag" "v1.6.0" "$target_tag"

# 校验 tag 格式
assert_true "tag valid" "sns_validate_version $target_tag"

# 校验 tag 不存在
assert_false "tag not exist" "sns_tag_exists $target_tag"

# 校验版本递增
assert_true "v1.6.0 > v1.5.0" "sns_version_gt $target_tag v1.5.0"

# 模拟打 tag
git tag -a "$target_tag" -m "Release $target_tag"
assert_true "tag now exists" "sns_tag_exists $target_tag"
git checkout -q main

echo ""
echo "=== TC-PUB-02: 在非 release 分支上拒绝发布 ==="
# main 上拒绝
git checkout -q main
branch_type=$(sns_branch_type)
assert_eq "main type" "main" "$branch_type"
assert_false "main is not release" "[[ '$branch_type' == 'release' ]]"
git checkout -q main

# worktree 上拒绝
git checkout -q -b worktree-001 main
branch_type=$(sns_branch_type)
assert_eq "worktree type" "worktree" "$branch_type"
assert_false "worktree is not release" "[[ '$branch_type' == 'release' ]]"
git checkout -q main

echo ""
echo "=== TC-PUB-03: 重复 tag 拒绝 ==="
# v1.6.0 已在上一步创建
git checkout -q release/1.6.0
assert_true "v1.6.0 exists now" "sns_tag_exists v1.6.0"
# 再次尝试发布同一版本 → 应拒绝
assert_true "duplicate tag detected" "sns_tag_exists v1.6.0"
git checkout -q main

echo ""
echo "=== TC-PUB-EXTRA: 版本不匹配拒绝 ==="
git checkout -q -b release/1.7.0 main
current_branch=$(git branch --show-current)
branch_version=$(echo "$current_branch" | sed 's/^release\///')
target_tag="v$branch_version"
# 尝试在 release/1.7.0 上发布 1.6.0
param_tag="v1.6.0"
assert_false "param != branch version" "[[ '$param_tag' == '$target_tag' ]]"
git checkout -q main

echo ""
echo "=== TC-PUB-EXTRA: 脏工作区拒绝 ==="
git checkout -q release/1.7.0
echo "dirty" > dirtyfile.txt
assert_false "dirty blocks publish" "sns_workdir_clean"
rm dirtyfile.txt
git checkout -q main

echo ""
echo "============================================="
echo "test_publish.sh: $PASS passed, $FAIL failed"
echo "============================================="

[[ $FAIL -eq 0 ]] || exit 1
