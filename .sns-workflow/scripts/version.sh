#!/usr/bin/env bash
# sns-workflow 版本计算脚本
# 所有涉及版本号的技能 source 此脚本，消除重复代码

sns_validate_version() {
  local v="$1"
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

sns_latest_tag() {
  git tag -l --sort=-version:refname | head -1
}

sns_bump_version() {
  local tag="${1:-}"
  local bump_type="$2"
  local major minor patch

  if [[ -z "$tag" ]]; then
    case "$bump_type" in
      patch)  echo "v0.0.1"; return ;;
      minor)  echo "v0.1.0"; return ;;
      major)  echo "v1.0.0"; return ;;
    esac
  fi

  major=$(echo "$tag" | sed 's/^v//' | cut -d. -f1)
  minor=$(echo "$tag" | sed 's/^v//' | cut -d. -f2)
  patch=$(echo "$tag" | sed 's/^v//' | cut -d. -f3)

  case "$bump_type" in
    patch) patch=$((patch + 1));;
    minor) minor=$((minor + 1)); patch=0;;
    major) major=$((major + 1)); minor=0; patch=0;;
  esac

  echo "v${major}.${minor}.${patch}"
}
