#!/usr/bin/env bash
# version.sh 单元测试
# 覆盖 test-plan.md: TC-UNIT-VER-01~05 + 预发布扩展

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/version.sh"

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

echo "=== TC-UNIT-VER-01: patch 递增 ==="
assert_eq "v1.5.1 patch bump" "v1.5.2" "$(sns_bump_version v1.5.1 patch)"

echo ""
echo "=== TC-UNIT-VER-02: minor 递增 ==="
assert_eq "v1.5.2 minor bump" "v1.6.0" "$(sns_bump_version v1.5.2 minor)"

echo ""
echo "=== TC-UNIT-VER-03: major 递增 ==="
assert_eq "v1.6.0 major bump" "v2.0.0" "$(sns_bump_version v1.6.0 major)"

echo ""
echo "=== TC-UNIT-VER-04: hotfix 目标版本必须大于线上版本 ==="
assert_true  "v1.6.1 > v1.6.0" "sns_version_gt v1.6.1 v1.6.0"
assert_false "v1.6.0 > v1.6.0" "sns_version_gt v1.6.0 v1.6.0"
assert_false "v1.5.9 > v1.6.0" "sns_version_gt v1.5.9 v1.6.0"

echo ""
echo "=== TC-UNIT-VER-05: tag 格式校验 ==="
assert_true  "v1.6.0 valid" "sns_validate_version v1.6.0"
assert_false "1.6.0 invalid (missing v)" "sns_validate_version 1.6.0"
assert_false "v1.6 invalid (missing patch)" "sns_validate_version v1.6"
assert_true  "v1.6.0-rc.1 valid (prerelease)" "sns_validate_version v1.6.0-rc.1"
assert_false "invalid invalid" "sns_validate_version invalid"

echo ""
echo "=== 额外: 空基线默认值 ==="
assert_eq "empty patch default" "v0.0.1" "$(sns_bump_version "" patch)"
assert_eq "empty minor default" "v0.1.0" "$(sns_bump_version "" minor)"
assert_eq "empty major default" "v1.0.0" "$(sns_bump_version "" major)"

echo ""
echo "=== 额外: parse_version ==="
assert_eq "parse major" "1" "$(sns_parse_version v1.2.3 major)"
assert_eq "parse minor" "2" "$(sns_parse_version v1.2.3 minor)"
assert_eq "parse patch" "3" "$(sns_parse_version v1.2.3 patch)"

echo ""
echo "=== 额外: version_gt 多场景 ==="
assert_true  "v2.0.0 > v1.9.9" "sns_version_gt v2.0.0 v1.9.9"
assert_true  "v1.3.0 > v1.2.9" "sns_version_gt v1.3.0 v1.2.9"
assert_false "v1.2.3 > v1.2.4" "sns_version_gt v1.2.3 v1.2.4"

echo ""
echo "=== TC-UNIT-PRE-01: 预发布格式校验 ==="
assert_true  "v1.5.0-beta valid" "sns_validate_version v1.5.0-beta"
assert_true  "v1.5.0-beta.2 valid" "sns_validate_version v1.5.0-beta.2"
assert_true  "v1.5.0-rc.1 valid" "sns_validate_version v1.5.0-rc.1"
assert_false "v1.5.0-alpha invalid" "sns_validate_version v1.5.0-alpha"
assert_false "v1.5.0-dev invalid" "sns_validate_version v1.5.0-dev"

echo ""
echo "=== TC-UNIT-PRE-02: is_prerelease ==="
assert_false "v1.5.0 is not prerelease" "sns_is_prerelease v1.5.0"
assert_true  "v1.5.0-beta is prerelease" "sns_is_prerelease v1.5.0-beta"
assert_true  "v1.5.0-rc.2 is prerelease" "sns_is_prerelease v1.5.0-rc.2"

echo ""
echo "=== TC-UNIT-PRE-03: parse prerelease ==="
assert_eq "parse beta prerelease" "" "$(sns_parse_version v1.5.0 prerelease)"
assert_eq "parse v1.5.0-beta prerelease" "beta" "$(sns_parse_version v1.5.0-beta prerelease)"
assert_eq "parse v1.5.0-beta.2 prerelease" "beta.2" "$(sns_parse_version v1.5.0-beta.2 prerelease)"
assert_eq "parse v1.5.0-rc.1 prerelease" "rc.1" "$(sns_parse_version v1.5.0-rc.1 prerelease)"
assert_eq "parse v1.5.0-rc.2 prerelease" "rc.2" "$(sns_parse_version v1.5.0-rc.2 prerelease)"

echo ""
echo "=== TC-UNIT-PRE-04: 预发布 version_gt ==="
# 正式 > 预发布
assert_true  "v1.5.0 > v1.5.0-rc.1" "sns_version_gt v1.5.0 v1.5.0-rc.1"
assert_true  "v1.5.0 > v1.5.0-beta" "sns_version_gt v1.5.0 v1.5.0-beta"
assert_false "v1.5.0-rc.1 > v1.5.0" "sns_version_gt v1.5.0-rc.1 v1.5.0"
# rc > beta
assert_true  "v1.5.0-rc.1 > v1.5.0-beta.3" "sns_version_gt v1.5.0-rc.1 v1.5.0-beta.3"
assert_false "v1.5.0-beta.3 > v1.5.0-rc.1" "sns_version_gt v1.5.0-beta.3 v1.5.0-rc.1"
# 同阶段序号递增
assert_true  "v1.5.0-beta.3 > v1.5.0-beta.2" "sns_version_gt v1.5.0-beta.3 v1.5.0-beta.2"
assert_true  "v1.5.0-rc.3 > v1.5.0-rc.2" "sns_version_gt v1.5.0-rc.3 v1.5.0-rc.2"
assert_false "v1.5.0-beta.2 > v1.5.0-beta.3" "sns_version_gt v1.5.0-beta.2 v1.5.0-beta.3"
# beta 首个 vs beta.2
assert_true  "v1.5.0-beta.2 > v1.5.0-beta" "sns_version_gt v1.5.0-beta.2 v1.5.0-beta"

echo ""
echo "=== TC-UNIT-PRE-05: sns_latest_tag 仅返回正式 tag ==="
# 创建 sandbox 验证（主仓库可能有已有 tag）
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

# 无 tag 时返回空
assert_eq "no tag returns empty" "" "$(sns_latest_tag)"

git tag -a "v1.5.0" -m "release"
git tag -a "v1.5.0-beta" -m "beta"
git tag -a "v1.5.0-beta.2" -m "beta2"
git tag -a "v1.5.0-rc.1" -m "rc1"
git tag -a "v1.6.0" -m "release"

assert_eq "latest tag is v1.6.0" "v1.6.0" "$(sns_latest_tag)"

echo ""
echo "=== TC-UNIT-PRE-06: sns_latest_prerelease_tag ==="
assert_eq "latest pre for v1.5.0" "v1.5.0-rc.1" "$(sns_latest_prerelease_tag v1.5.0)"
assert_eq "latest pre for v1.6.0" "" "$(sns_latest_prerelease_tag v1.6.0)"

echo ""
echo "=== TC-UNIT-PRE-07: sns_bump_prerelease ==="
# v1.5.0 已有 beta, beta.2, rc.1 → 默认递增 rc
assert_eq "bump rc.1 → rc.2" "v1.5.0-rc.2" "$(sns_bump_prerelease v1.5.0)"
# v1.6.0 无预发布 → 首个 beta
assert_eq "first beta" "v1.6.0-beta" "$(sns_bump_prerelease v1.6.0)"
# --rc 首个
assert_eq "first rc.1" "v1.6.0-rc.1" "$(sns_bump_prerelease v1.6.0 --rc)"
# v1.5.0 已在 rc 阶段，--rc 应报错
assert_false "already rc, --rc fails" "sns_bump_prerelease v1.5.0 --rc 2>/dev/null"

cd - > /dev/null

echo ""
echo "========================================="
echo "version.sh: $PASS passed, $FAIL failed"
echo "========================================="

[[ $FAIL -eq 0 ]] || exit 1
