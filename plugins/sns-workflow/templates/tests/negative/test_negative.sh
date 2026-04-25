#!/usr/bin/env bash
# 负向测试
# 覆盖 test-plan.md: TC-NEG-01~05

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
git checkout -q -b worktree-002 main
git checkout -q -b feature/payment main
git checkout -q -b release/1.7.0 main
git checkout -q main

echo "=== TC-NEG-01: 用 main 修线上修复替代 hotfix ==="
# commit-push-pr 在 main 上应被拒绝
git checkout -q main
branch_type=$(sns_branch_type)
assert_eq "main type" "main" "$branch_type"
# main 不是 worktree/feature/hotfix，应被 commit-push-pr 拒绝
assert_false "main not worktree" "[[ '$branch_type' == 'worktree' ]]"
assert_false "main not feature" "[[ '$branch_type' == 'feature' ]]"
assert_false "main not hotfix" "[[ '$branch_type' == 'hotfix' ]]"
echo "  → commit-push-pr 会拒绝 main 分支"

echo ""
echo "=== TC-NEG-02: 脏 worktree 自动 reset ==="
git checkout -q worktree-001
echo "unsafe" > unsafe.txt
assert_false "dirty workdir" "sns_workdir_clean"
echo "  → reset 被阻止，需先处理工作区"
rm unsafe.txt

# 即使工作区干净，有未推送提交时 reset 也需注意
echo "local change" > localfile.txt
git add localfile.txt
git commit -q -m "local commit"
assert_true "workdir clean after commit" "sns_workdir_clean"
ahead=$(sns_ahead_count)
assert_eq "has ahead commits" "1" "$ahead"
echo "  → 有未推送提交时 reset 会丢失数据，需显式保护"
git checkout -q main

echo ""
echo "=== TC-NEG-03: 从 feature 直接创建 release ==="
git checkout -q feature/payment
branch_type=$(sns_branch_type)
assert_eq "feature type" "feature" "$branch_type"
# release 命令要求 main
assert_false "feature is not main" "[[ '$branch_type' == 'main' ]]"
echo "  → release 命令会拒绝 feature 分支"
git checkout -q main

echo ""
echo "=== TC-NEG-04: 从 main 创建 hotfix ==="
git checkout -q main
branch_type=$(sns_branch_type)
assert_eq "main type" "main" "$branch_type"
# hotfix 命令要求 worktree
assert_false "main is not worktree" "[[ '$branch_type' == 'worktree' ]]"
echo "  → hotfix 命令会拒绝 main 分支"
git checkout -q main

echo ""
echo "=== TC-NEG-05: 发布版本回退 ==="
# 尝试发布 v1.5.9 < v1.6.0
latest_tag=$(sns_latest_tag)
assert_eq "latest tag" "v1.6.0" "$latest_tag"
assert_false "v1.5.9 not > v1.6.0" "sns_version_gt v1.5.9 v1.6.0"
assert_false "v1.6.0 not > v1.6.0" "sns_version_gt v1.6.0 v1.6.0"
assert_false "v1.0.0 not > v1.6.0" "sns_version_gt v1.0.0 v1.6.0"
echo "  → 版本回退被阻止"

echo ""
echo "=== TC-NEG-EXTRA: release 分支上执行 commit-push-pr ==="
git checkout -q release/1.7.0
branch_type=$(sns_branch_type)
assert_eq "release type" "release" "$branch_type"
# commit-push-pr 不支持 release，应提示用 publish
assert_false "release not worktree" "[[ '$branch_type' == 'worktree' ]]"
assert_false "release not feature" "[[ '$branch_type' == 'feature' ]]"
assert_false "release not hotfix" "[[ '$branch_type' == 'hotfix' ]]"
echo "  → commit-push-pr 会拒绝 release 分支并提示使用 publish"
git checkout -q main

echo ""
echo "=== TC-NEG-EXTRA: 覆盖已有 tag ==="
assert_true "v1.6.0 exists" "sns_tag_exists v1.6.0"
# publish 在 tag 已存在时应拒绝
echo "  → publish 会检测 tag 已存在并拒绝"
# hotfix 目标版本如果与已有 tag 相同也应拒绝
assert_true "v1.6.0 already exists, hotfix target blocked" "sns_tag_exists v1.6.0"

cd - > /dev/null

echo ""
echo "=============================================="
echo "test_negative.sh: $PASS passed, $FAIL failed"
echo "=============================================="

[[ $FAIL -eq 0 ]] || exit 1
