#!/usr/bin/env bash
# sns-workflow 版本计算脚本
# 所有涉及版本号的技能 source 此脚本，消除重复代码

# 校验版本号格式：vX.Y.Z
sns_validate_version() {
  local v="$1"
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# 获取最新 tag（按语义版本降序）
sns_latest_tag() {
  git tag -l --sort=-version:refname | head -1
}

# 校验 tag 是否存在
sns_tag_exists() {
  local v="$1"
  git tag -l "$v" | grep -q "$v"
}

# 从版本号解析 major/minor/patch
# 用法: sns_parse_version v1.2.3 major
sns_parse_version() {
  local v="$1"
  local part="$2"
  local clean="${v#v}"
  case "$part" in
    major) echo "$clean" | cut -d. -f1 ;;
    minor) echo "$clean" | cut -d. -f2 ;;
    patch) echo "$clean" | cut -d. -f3 ;;
  esac
}

# 版本号严格大于校验：$1 > $2 返回 0
sns_version_gt() {
  local a="$1"
  local b="$2"
  local a_major a_minor a_patch b_major b_minor b_patch

  a_major=$(sns_parse_version "$a" major)
  a_minor=$(sns_parse_version "$a" minor)
  a_patch=$(sns_parse_version "$a" patch)
  b_major=$(sns_parse_version "$b" major)
  b_minor=$(sns_parse_version "$b" minor)
  b_patch=$(sns_parse_version "$b" patch)

  [[ $a_major -gt $b_major ]] && return 0
  [[ $a_major -lt $b_major ]] && return 1
  [[ $a_minor -gt $b_minor ]] && return 0
  [[ $a_minor -lt $b_minor ]] && return 1
  [[ $a_patch -gt $b_patch ]] && return 0
  return 1
}

# 计算 bump 后的版本号
# 用法: sns_bump_version <tag> <type>
#   tag:  基线版本，如 v1.2.3；为空时使用默认值
#   type: patch | minor | major
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

  major=$(sns_parse_version "$tag" major)
  minor=$(sns_parse_version "$tag" minor)
  patch=$(sns_parse_version "$tag" patch)

  # 容错：解析失败时返回空
  if [[ -z "$major" || -z "$minor" || -z "$patch" ]]; then
    echo ""
    return 1
  fi

  case "$bump_type" in
    patch) patch=$((patch + 1));;
    minor) minor=$((minor + 1)); patch=0;;
    major) major=$((major + 1)); minor=0; patch=0;;
  esac

  echo "v${major}.${minor}.${patch}"
}
