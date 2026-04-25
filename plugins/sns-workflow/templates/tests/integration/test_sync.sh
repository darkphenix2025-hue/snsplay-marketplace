#!/usr/bin/env bash
# sync 集成测试
# 覆盖 test-plan.md: TC-SYNC-01~03

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

git tag -a "v1.5.0" -m "baseline"
git push -q origin v1.5.0

# 创建 worktree
git checkout -q -b worktree-001 main
git checkout -q main

echo "=== TC-SYNC-01: worktree 正常同步 ==="
# 在 main 上新增提交
git checkout -q main
echo "main-change" > mainfile.txt
git add mainfile.txt
git commit -q -m "main change"
git push -q origin main

# 切到 worktree，检测 behind
git checkout -q worktree-001
behind=$(sns_behind_count)
assert_eq "behind count" "1" "$behind"

# 模拟 sync: fetch + reset (无本地提交)
git fetch origin main
git reset --hard origin/main
behind_after=$(sns_behind_count)
assert_eq "behind after sync" "0" "$behind_after"
git checkout -q main

echo ""
echo "=== TC-SYNC-02: 脏工作区阻止同步 ==="
git checkout -q worktree-001
echo "dirty" > dirtyfile.txt
assert_false "dirty workdir blocks sync" "sns_workdir_clean"
rm dirtyfile.txt
git checkout -q main

echo ""
echo "=== TC-SYNC-03: rebase 冲突处理 ==="
# 在 worktree 上有本地提交
git checkout -q worktree-001
echo "wt-content" > conflict.txt
git add conflict.txt
git commit -q -m "worktree change"

# 在 main 上修改同一文件
git checkout -q main
echo "main-content" > conflict.txt
git add conflict.txt
git commit -q -m "main change same file"
git push -q origin main

git checkout -q worktree-001
git fetch origin main
ahead=$(sns_ahead_count)
behind=$(sns_behind_count)
assert_eq "ahead before rebase" "1" "$ahead"
assert_eq "behind before rebase" "1" "$behind"

# rebase 应冲突
rebase_result=0
git rebase origin/main 2>/dev/null || rebase_result=$?
assert_true "rebase conflict detected" "[[ $rebase_result -ne 0 ]]"
git rebase --abort 2>/dev/null || true
git checkout -q main

cd - > /dev/null

echo ""
echo "========================================="
echo "test_sync.sh: $PASS passed, $FAIL failed"
echo "========================================="

[[ $FAIL -eq 0 ]] || exit 1
