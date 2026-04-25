#!/usr/bin/env bash
# commit-push-pr 集成测试
# 覆盖 test-plan.md: TC-CPP-01~05
# 注意: PR 相关操作（gh CLI）在测试中模拟，仅验证 git 本地逻辑

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
git checkout -q main

echo "=== TC-CPP-01: worktree 路径分支识别 ==="
git checkout -q worktree-001
echo "change" > newfile.txt
git add newfile.txt
git commit -q -m "worktree change"

branch_type=$(sns_branch_type)
assert_eq "worktree type" "worktree" "$branch_type"

# 模拟: worktree 有未推送提交
ahead=$(sns_ahead_count)
assert_eq "worktree has ahead" "1" "$ahead"
git checkout -q main

echo ""
echo "=== TC-CPP-02: feature 路径分支识别 ==="
git checkout -q worktree-002
git checkout -q -b feature/payment

branch_type=$(sns_branch_type)
assert_eq "feature type" "feature" "$branch_type"

# 模拟: feature 修改
echo "feat" > feature.txt
git add feature.txt
git commit -q -m "feature change"
git checkout -q main

echo ""
echo "=== TC-CPP-03: hotfix 路径分支识别与版本提取 ==="
# 从 tag 创建 hotfix
git checkout -q worktree-001
git checkout -q -b hotfix/1.6.1 v1.6.0

branch_type=$(sns_branch_type)
assert_eq "hotfix type" "hotfix" "$branch_type"

# 提取版本号
branch_version=$(echo "$(git branch --show-current)" | sed 's/^hotfix\///')
target_tag="v$branch_version"
assert_eq "hotfix target tag" "v1.6.1" "$target_tag"
assert_true "tag format valid" "sns_validate_version $target_tag"
assert_false "tag not exist yet" "sns_tag_exists $target_tag"
assert_true "version gt" "sns_version_gt $target_tag v1.6.0"

# 模拟 hotfix 修复
echo "fix" > fix.txt
git add fix.txt
git commit -q -m "hotfix fix"
git checkout -q main

echo ""
echo "=== TC-CPP-04: 无变更时识别 ==="
git checkout -q worktree-002
git reset --hard origin/main
assert_true "clean workdir" "sns_workdir_clean"
# 无变更 → git add -A 后 staged 为空
git add -A
staged=$(git diff --cached --stat)
assert_true "no staged changes" "[[ -z '$staged' ]]"
git checkout -q main

echo ""
echo "=== TC-CPP-05: 未知分支类型拒绝 ==="
git checkout -q -b experimental/foo
branch_type=$(sns_branch_type)
assert_eq "experimental type" "unknown" "$branch_type"
assert_false "unknown not worktree" "[[ '$branch_type' == 'worktree' ]]"
assert_false "unknown not feature" "[[ '$branch_type' == 'feature' ]]"
assert_false "unknown not hotfix" "[[ '$branch_type' == 'hotfix' ]]"
git checkout -q main

echo ""
echo "=== TC-CPP-EXTRA: main 分支直接提交 ==="
branch_type=$(sns_branch_type)
assert_eq "main type" "main" "$branch_type"
assert_true "main is a valid cpp context" "[[ '$branch_type' == 'main' ]]"
# main 路径: commit + push 直接提交，不产生 tag

echo ""
echo "=== TC-CPP-EXTRA: release 分支 rc 迭代 ==="
git checkout -q -b release/1.7.0 main
branch_type=$(sns_branch_type)
assert_eq "release type" "release" "$branch_type"
assert_true "release is a valid cpp context" "[[ '$branch_type' == 'release' ]]"
# 模拟 rc 迭代修复
echo "rc fix" > rcfix.txt
git add rcfix.txt
git commit -q -m "fix(1.7.0): rc update"
# rc 修复不产生 tag
latest=$(sns_latest_tag)
assert_eq "rc fix does not create tag" "v1.6.0" "$latest"
git checkout -q main

echo ""
echo "=== TC-CPP-EXTRA: worktree reset 安全校验 ==="
git checkout -q worktree-001
echo "unsafe" > unsafe.txt
assert_false "dirty workdir blocks reset" "sns_workdir_clean"
rm unsafe.txt

# 干净但 ahead → reset 安全
git reset --hard origin/main
assert_true "clean workdir allows reset" "sns_workdir_clean"
git checkout -q main

cd - > /dev/null

echo ""
echo "==================================================="
echo "test_commit_push_pr.sh: $PASS passed, $FAIL failed"
echo "==================================================="

[[ $FAIL -eq 0 ]] || exit 1
