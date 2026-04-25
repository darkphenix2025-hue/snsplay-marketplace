#!/usr/bin/env bash
# version.sh 单元测试
# 覆盖 test-plan.md: TC-UNIT-VER-01~05

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
assert_false "v1.6.0-rc.1 invalid (prerelease)" "sns_validate_version v1.6.0-rc.1"
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
echo "========================================="
echo "version.sh: $PASS passed, $FAIL failed"
echo "========================================="

[[ $FAIL -eq 0 ]] || exit 1
