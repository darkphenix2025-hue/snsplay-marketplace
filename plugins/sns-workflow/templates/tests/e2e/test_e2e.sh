#!/usr/bin/env bash
# E2E 测试
# 覆盖 test-plan.md: TC-E2E-01~05

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

# 创建 worktrees
for i in 010 011 003; do
  git checkout -q -b "worktree-$i" main
done
git checkout -q main

echo "=== TC-E2E-01: 快捷模式完整路径 ==="
git checkout -q worktree-010

# sync (fetch + reset，无本地提交)
git fetch origin main
git reset --hard origin/main
assert_eq "synced to main" "0" "$(sns_behind_count)"

# 直接修改
echo "quick fix" > quickfix.txt
git add quickfix.txt
git commit -q -m "quick fix"

# 模拟 commit-push-pr: PR + merge + reset
git checkout -q main
git merge --squash worktree-010
git commit -q -m "squash: quick fix"
git push -q origin main

git checkout -q worktree-010
git fetch origin main
git reset --hard origin/main
assert_eq "worktree reset done" "0" "$(sns_ahead_count)"
assert_eq "worktree behind" "0" "$(sns_behind_count)"
echo "  → 快捷模式完整路径验证通过"
git checkout -q main

echo ""
echo "=== TC-E2E-02: Feature 模式完整路径 ==="
git checkout -q worktree-011

# sync
git fetch origin main
git reset --hard origin/main

# 创建 feature
git checkout -b feature/payment
assert_eq "on feature" "feature/payment" "$(git branch --show-current)"

# 开发
echo "payment" > payment.txt
git add payment.txt
git commit -q -m "feat: payment"

# 模拟 commit-push-pr: PR + merge + delete + 回到 worktree
git checkout -q main
git merge --squash feature/payment
git commit -q -m "squash: feature/payment"
git push -q origin main
git branch -D feature/payment

git checkout -q worktree-011
git fetch origin main
git reset --hard origin/main

assert_false "feature deleted" "git show-ref --verify --quiet refs/heads/feature/payment 2>/dev/null"
assert_eq "back on worktree" "worktree-011" "$(git branch --show-current)"
assert_eq "worktree clean" "0" "$(sns_ahead_count)"
echo "  → Feature 模式完整路径验证通过"
git checkout -q main

echo ""
echo "=== TC-E2E-03: Release 完整路径 ==="
latest_tag=$(sns_latest_tag)
release_ver=$(sns_bump_version "$latest_tag" minor)
release_branch_ver=$(echo "$release_ver" | sed 's/^v//')
release_branch="release/$release_branch_ver"

# 创建 release
git checkout -q main
git checkout -b "$release_branch"

# release 修复
echo "release fix" > releasefix.txt
git add releasefix.txt
git commit -q -m "release fix"

# publish: 打 tag
target_tag="v$release_branch_ver"
git tag -a "$target_tag" -m "Release $target_tag"
assert_true "tag created" "sns_tag_exists $target_tag"

# 回流 main
git checkout -q main
git merge "$release_branch" --no-edit
git push -q origin main

latest=$(sns_latest_tag)
assert_eq "latest is release tag" "$target_tag" "$latest"
echo "  → Release 完整路径验证通过"
git checkout -q main

echo ""
echo "=== TC-E2E-04: Hotfix 完整路径 ==="
# v1.6.0 已在 E2E-03 中创建，直接从它派生 hotfix
git checkout -q worktree-003
git checkout -b hotfix/1.6.1 v1.6.0

echo "hotfix fix" > hotfixfix.txt
git add hotfixfix.txt
git commit -q -m "hotfix: fix"

# 模拟 commit-push-pr: merge + tag + 回流
git checkout -q main
git merge hotfix/1.6.1 --no-edit
git tag -a "v1.6.1" -m "Hotfix v1.6.1"

assert_true "v1.6.1 exists" "sns_tag_exists v1.6.1"
assert_true "v1.6.1 > v1.6.0" "sns_version_gt v1.6.1 v1.6.0"

# 验证 main 包含 hotfix
assert_true "main has hotfix" "[[ -f hotfixfix.txt ]]"

latest=$(sns_latest_tag)
assert_eq "latest is hotfix" "v1.6.1" "$latest"
echo "  → Hotfix 完整路径验证通过"
git checkout -q main

echo ""
echo "=== TC-E2E-05: Hotfix 与活动 release 并行完整路径 ==="
# 创建 release/1.7.0
git checkout -q main
git checkout -b release/1.7.0

echo "release prep" > releaseprep.txt
git add releaseprep.txt
git commit -q -m "release prep"
git checkout -q main

# hotfix/1.6.2 从 v1.6.1 派生
git checkout -q worktree-010
git checkout -b hotfix/1.6.2 v1.6.1

echo "hotfix2 fix" > hotfix2fix.txt
git add hotfix2fix.txt
git commit -q -m "hotfix2: fix"

# hotfix → main + tag
git checkout -q main
git merge hotfix/1.6.2 --no-edit
git tag -a "v1.6.2" -m "Hotfix v1.6.2"

assert_true "v1.6.2 exists" "sns_tag_exists v1.6.2"

# hotfix → release/1.7.0 同步
git checkout -q release/1.7.0
git merge hotfix/1.6.2 --no-edit

assert_true "release has hotfix2" "[[ -f hotfix2fix.txt ]]"
assert_true "release has prep" "[[ -f releaseprep.txt ]]"

# release/1.7.0 继续发布
git tag -a "v1.7.0" -m "Release v1.7.0"
assert_true "v1.7.0 exists" "sns_tag_exists v1.7.0"

# 回流 main
git checkout -q main
git merge release/1.7.0 --no-edit

# 最终验证
assert_true "main has everything" "[[ -f hotfix2fix.txt && -f releaseprep.txt ]]"
latest=$(sns_latest_tag)
assert_eq "final latest is v1.7.0" "v1.7.0" "$latest"
echo "  → Hotfix 与活动 release 并行验证通过"

cd - > /dev/null

echo ""
echo "==========================================="
echo "test_e2e.sh: $PASS passed, $FAIL failed"
echo "==========================================="

[[ $FAIL -eq 0 ]] || exit 1
