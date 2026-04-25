#!/usr/bin/env bash
# sns-workflow 版本计算脚本
# 所有涉及版本号的技能 source 此脚本，消除重复代码
# 支持: vX.Y.Z（正式）, vX.Y.Z-beta, vX.Y.Z-beta.N, vX.Y.Z-rc.N（预发布）

# 校验版本号格式：vX.Y.Z 或 vX.Y.Z-beta[.N] 或 vX.Y.Z-rc.N
sns_validate_version() {
  local v="$1"
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-((beta|rc)(\.[0-9]+)?))?$ ]]
}

# 判断是否为预发布版本
sns_is_prerelease() {
  local v="$1"
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+- ]]
}

# 获取最新正式 tag（按语义版本降序，排除预发布）
sns_latest_tag() {
  git tag -l --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

# 校验 tag 是否存在
sns_tag_exists() {
  local v="$1"
  git tag -l "$v" | grep -q "$v"
}

# 从版本号解析 major/minor/patch/prerelease
# 用法: sns_parse_version v1.2.3 major
#       sns_parse_version v1.2.3-beta.2 prerelease
sns_parse_version() {
  local v="$1"
  local part="$2"
  local clean="${v#v}"
  local core="${clean%%-*}"
  case "$part" in
    major) echo "$core" | cut -d. -f1 ;;
    minor) echo "$core" | cut -d. -f2 ;;
    patch) echo "$core" | cut -d. -f3 ;;
    prerelease)
      if [[ "$clean" == *-* ]]; then
        echo "${clean#*-}"
      else
        echo ""
      fi
      ;;
  esac
}

# 版本号严格大于校验：$1 > $2 返回 0
# SemVer 优先级: major → minor → patch → 正式 > 预发布 → rc > beta → 序号
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
  [[ $a_patch -lt $b_patch ]] && return 1

  # core 版本相同，比较预发布
  local a_pre b_pre
  a_pre=$(sns_parse_version "$a" prerelease)
  b_pre=$(sns_parse_version "$b" prerelease)

  # 正式版 > 任何预发布
  [[ -z "$a_pre" && -n "$b_pre" ]] && return 0
  [[ -n "$a_pre" && -z "$b_pre" ]] && return 1
  # 两者都是正式版，相等
  [[ -z "$a_pre" && -z "$b_pre" ]] && return 1

  # 两者都是预发布，比较阶段
  local a_stage b_stage a_num b_num
  if [[ "$a_pre" =~ ^(beta|rc) ]]; then
    a_stage="${BASH_REMATCH[1]}"
  fi
  if [[ "$b_pre" =~ ^(beta|rc) ]]; then
    b_stage="${BASH_REMATCH[1]}"
  fi

  # rc > beta
  [[ "$a_stage" == "rc" && "$b_stage" == "beta" ]] && return 0
  [[ "$a_stage" == "beta" && "$b_stage" == "rc" ]] && return 1

  # 同阶段，比较序号
  a_num=$(echo "$a_pre" | grep -oE '[0-9]+$' || echo "0")
  b_num=$(echo "$b_pre" | grep -oE '[0-9]+$' || echo "0")
  [[ ${a_num:-0} -gt ${b_num:-0} ]] && return 0
  return 1
}

# 计算 bump 后的正式版本号
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

# 获取指定基础版本的最新预发布 tag
# 用法: sns_latest_prerelease_tag v1.5.0
# 返回: v1.5.0-rc.2 或空
sns_latest_prerelease_tag() {
  local base_version="$1"
  local core="${base_version#v}"
  git tag -l "v${core}-*" --sort=-version:refname 2>/dev/null | head -1
}

# 计算下一个预发布版本号
# 用法: sns_bump_prerelease v1.5.0          → v1.5.0-beta
#       sns_bump_prerelease v1.5.0 --rc      → v1.5.0-rc.1
# 规则:
#   无预发布 tag  → 首个 beta（或 --rc 时 rc.1）
#   最新 beta     → beta.N+1（或 --rc 时 rc.1）
#   最新 rc.N     → rc.N+1（--rc 报错已在 rc 阶段）
sns_bump_prerelease() {
  local base_version="$1"
  local shift_to_rc=false
  [[ "${2:-}" == "--rc" ]] && shift_to_rc=true

  local latest_pre
  latest_pre=$(sns_latest_prerelease_tag "$base_version")

  if [[ -z "$latest_pre" ]]; then
    if $shift_to_rc; then
      echo "${base_version}-rc.1"
    else
      echo "${base_version}-beta"
    fi
    return
  fi

  local pre
  pre=$(sns_parse_version "$latest_pre" prerelease)

  if [[ "$pre" =~ ^beta ]]; then
    if $shift_to_rc; then
      echo "${base_version}-rc.1"
    else
      local num
      num=$(echo "$pre" | grep -oE '[0-9]+$' || echo "0")
      if [[ "$num" == "0" ]]; then
        echo "${base_version}-beta.2"
      else
        echo "${base_version}-beta.$((num + 1))"
      fi
    fi
  elif [[ "$pre" =~ ^rc ]]; then
    if $shift_to_rc; then
      echo "错误: 已在 rc 阶段 ($latest_pre)" >&2
      return 1
    fi
    local num
    num=$(echo "$pre" | grep -oE '[0-9]+$')
    echo "${base_version}-rc.$((num + 1))"
  fi
}
