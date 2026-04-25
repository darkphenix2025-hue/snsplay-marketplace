#!/usr/bin/env bash
# 场景测试
# 覆盖 test-plan.md: TC-SCN-01~05

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
git checkout -q -b worktree-002 main
git checkout -q -b worktree-003 main
git checkout -q main

echo "=== TC-SCN-01: 快捷模式版本演进 ==="
# worktree-001 直接修改并模拟合并
git checkout -q worktree-001
echo "quick fix" > quickfix.txt
git add quickfix.txt
git commit -q -m "quick fix"

# 模拟: worktree PR 合并到 main
git checkout -q main
git merge --squash worktree-001
git commit -q -m "squash: quick fix from worktree-001"
git push -q origin main

# worktree reset 到最新 main
git checkout -q worktree-001
git fetch origin main
git reset --hard origin/main
assert_eq "worktree synced" "0" "$(sns_ahead_count)"
assert_eq "worktree behind" "0" "$(sns_behind_count)"

# 验证: 不产生正式 tag
latest=$(sns_latest_tag)
assert_eq "tag unchanged" "v1.5.0" "$latest"
echo "  → 快捷模式不产生 tag，main 接收合并"
git checkout -q main

echo ""
echo "=== TC-SCN-02: Feature 模式版本演进 ==="
git checkout -q worktree-002
git checkout -q -b feature/payment

echo "payment feature" > payment.txt
git add payment.txt
git commit -q -m "feat: payment"

# 模拟: feature PR 合并到 main
git checkout -q main
git merge --squash feature/payment
git commit -q -m "squash: feature/payment"
git push -q origin main

# feature 删除，worktree 回收
git branch -D feature/payment
git checkout -q worktree-002
git fetch origin main
git reset --hard origin/main

assert_false "feature deleted" "git show-ref --verify --quiet refs/heads/feature/payment 2>/dev/null"
assert_eq "worktree synced" "0" "$(sns_ahead_count)"

latest=$(sns_latest_tag)
assert_eq "tag unchanged after feature" "v1.5.0" "$latest"
echo "  → Feature 模式不产生 tag"
git checkout -q main

echo ""
echo "=== TC-SCN-03: release 候选演进 ==="
# 从 main 创建 release
latest_tag=$(sns_latest_tag)
release_ver=$(sns_bump_version "$latest_tag" minor)
release_branch_ver=$(echo "$release_ver" | sed 's/^v//')
release_branch="release/$release_branch_ver"

git checkout -q main
git checkout -b "$release_branch"

# 模拟: release 上的修复迭代
echo "rc1 fix" > rc1.txt
git add rc1.txt
git commit -q -m "rc.1 fix"

echo "rc2 fix" > rc2.txt
git add rc2.txt
git commit -q -m "rc.2 fix"

# publish: 打 tag
target_tag="v$release_branch_ver"
assert_false "tag not exist before publish" "sns_tag_exists $target_tag"
assert_true "version gt" "sns_version_gt $target_tag $latest_tag"

git tag -a "$target_tag" -m "Release $target_tag"
assert_true "tag created" "sns_tag_exists $target_tag"

# 回流 main
git checkout -q main
git merge "$release_branch" --no-edit
git push -q origin main

latest=$(sns_latest_tag)
assert_eq "new tag is latest" "$target_tag" "$latest"
echo "  → release 演进后生成正式 tag $target_tag"
git checkout -q main

echo ""
echo "=== TC-SCN-04: hotfix 与主线并行 ==="
# 先回到 v1.5.0 之前的 sandbox（重设 tag）
git tag -d v1.6.0 2>/dev/null || true
git tag -a "v1.6.0" -m "release v1.6.0" main

# main 继续开发
echo "dev" > dev.txt
git add dev.txt
git commit -q -m "dev: new feature"

# hotfix 从 tag 创建
git checkout -q worktree-003
git checkout -b hotfix/1.6.1 v1.6.0

echo "hotfix" > hotfix.txt
git add hotfix.txt
git commit -q -m "hotfix: fix"

# 模拟 hotfix 合并 + 打 tag
git checkout -q main
git merge hotfix/1.6.1 --no-edit
git tag -a "v1.6.1" -m "Hotfix v1.6.1"

assert_true "v1.6.1 exists" "sns_tag_exists v1.6.1"
assert_true "v1.6.1 > v1.6.0" "sns_version_gt v1.6.1 v1.6.0"

latest=$(sns_latest_tag)
assert_eq "latest is hotfix tag" "v1.6.1" "$latest"

# main 应同时包含 hotfix 和原有开发
assert_true "main has hotfix" "[[ -f hotfix.txt ]]"
assert_true "main has dev" "[[ -f dev.txt ]]"
echo "  → hotfix 回流 main 后，main 包含两者"
git checkout -q main

echo ""
echo "=== TC-SCN-05: 活动 release 存在时的 hotfix ==="
# 创建 release/1.7.0
git checkout -q main
git checkout -b release/1.7.0

echo "release work" > releasework.txt
git add releasework.txt
git commit -q -m "release prep"

git checkout -q main

# 同时创建 hotfix
git checkout -q worktree-001
git checkout -b hotfix/1.6.2 v1.6.1

echo "hotfix2" > hotfix2.txt
git add hotfix2.txt
git commit -q -m "hotfix2: another fix"

# hotfix 合并到 main
git checkout -q main
git merge hotfix/1.6.2 --no-edit
git tag -a "v1.6.2" -m "Hotfix v1.6.2"

assert_true "v1.6.2 exists" "sns_tag_exists v1.6.2"

# hotfix 同步到 release/1.7.0
git checkout -q release/1.7.0
git merge hotfix/1.6.2 --no-edit

assert_true "release has hotfix2" "[[ -f hotfix2.txt ]]"
assert_true "release has releasework" "[[ -f releasework.txt ]]"
echo "  → hotfix 同步到活动 release"

# 验证 release 仍能正常发布
git tag -a "v1.7.0" -m "Release v1.7.0"
assert_true "v1.7.0 exists" "sns_tag_exists v1.7.0"
echo "  → 后续 v1.7.0 包含 hotfix 修复"

cd - > /dev/null

echo ""
echo "==============================================="
echo "test_scenarios.sh: $PASS passed, $FAIL failed"
echo "==============================================="

[[ $FAIL -eq 0 ]] || exit 1
