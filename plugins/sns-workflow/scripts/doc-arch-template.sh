#!/usr/bin/env bash
# sns-workflow 渐进式文档架构规则
# 供 doc-garden 技能、hook、commit-push-pr 共用

# === 架构定义 ===
SNS_DOC_REQUIRED_DIRS=(
  "design-docs"
  "exec-plans"
  "exec-plans/active"
  "exec-plans/completed"
  "generated"
  "product-specs"
  "references"
)

SNS_DOC_REQUIRED_FILES=(
  "docs/ARCHITECTURE.md"
  "docs/DESIGN.md"
  "docs/PLANS.md"
  "docs/QUALITY.md"
  "docs/SECURITY.md"
)

SNS_DOC_INDEX_FILES=(
  "docs/design-docs/index.md"
  "docs/product-specs/index.md"
  "docs/exec-plans/index.md"
  "docs/references/index.md"
)

SNS_DOC_CLAUDE_MD_MAX_LINES=150

# === 辅助函数 ===
_sns_doc_root() {
  # 1. 先查找 CLAUDE.md
  local dir="${PWD}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/CLAUDE.md" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # 2. 回退：查找 git 根目录
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$git_root" ]]; then
    echo "$git_root"
    return 0
  fi
  # 3. 最后回退：使用当前目录
  echo "${PWD}"
}

# === 检查架构合规性 ===
# 输出: 缺失项列表（每行一个），如无缺失则输出 "合规"
# 参数: --quiet (仅返回退出码，无输出)
sns_doc_check() {
  local quiet=false
  [[ "$1" == "--quiet" ]] && quiet=true
  local report=false
  [[ "$1" == "--report" ]] && report=true

  local root
  root=$(_sns_doc_root)

  local missing=()
  local issues=()

  # 检查必需目录
  for d in "${SNS_DOC_REQUIRED_DIRS[@]}"; do
    if [[ ! -d "$root/docs/$d" ]]; then
      missing+=("目录缺失: docs/$d")
    fi
  done

  # 检查必需文件
  for f in "${SNS_DOC_REQUIRED_FILES[@]}"; do
    if [[ ! -f "$root/$f" ]]; then
      missing+=("文件缺失: $f")
    fi
  done

  # 检查 CLAUDE.md
  if [[ -f "$root/CLAUDE.md" ]]; then
    local lines
    lines=$(wc -l < "$root/CLAUDE.md")
    if [[ "$lines" -gt "$SNS_DOC_CLAUDE_MD_MAX_LINES" ]]; then
      issues+=("CLAUDE.md 过长 ($lines 行 > $SNS_DOC_CLAUDE_MD_MAX_LINES 行)")
    fi
    if ! grep -q "文档地图\|docs/" "$root/CLAUDE.md" 2>/dev/null; then
      issues+=("CLAUDE.md 缺少文档地图索引")
    fi
  fi

  # 检查 index.md
  for idx in "${SNS_DOC_INDEX_FILES[@]}"; do
    if [[ ! -f "$root/$idx" ]]; then
      issues+=("索引缺失: $idx")
    fi
  done

  # 输出
  if [[ ${#missing[@]} -eq 0 && ${#issues[@]} -eq 0 ]]; then
    $quiet || echo "合规"
    return 0
  fi

  $quiet || {
    [[ ${#missing[@]} -gt 0 ]] && echo "--- 缺失项 ---"
    for m in "${missing[@]}"; do echo "  $m"; done
    [[ ${#issues[@]} -gt 0 ]] && echo "--- 警告项 ---"
    for i in "${issues[@]}"; do echo "  $i"; done
    $report || echo "--- 总计数: ${#missing[@]} 缺失, ${#issues[@]} 警告 ---"
  }

  return 1
}

# === 修复架构（创建缺失的目录和模板文件） ===
# 参数: --auto (自动模式，不提示确认)
sns_doc_fix() {
  local auto=false
  [[ "$1" == "--auto" ]] && auto=true

  local root
  root=$(_sns_doc_root)

  local fixed=()

  # 如果 CLAUDE.md 不存在，创建最小化的导航文件
  if [[ ! -f "$root/CLAUDE.md" ]]; then
    local project_name
    project_name=$(basename "$root")
    cat > "$root/CLAUDE.md" <<TMPL
# ${project_name}

## 文档地图

| 目录 | 内容 | 索引 |
|------|------|------|
| docs/design-docs/ | 设计决策 | [index](docs/design-docs/index.md) |
| docs/exec-plans/ | 执行计划 | [PLANS](docs/PLANS.md) |
| docs/references/ | 参考资料 | [index](docs/references/index.md) |
| docs/product-specs/ | 产品规格 | [index](docs/product-specs/index.md) |

根级文档: [ARCHITECTURE](docs/ARCHITECTURE.md) · [DESIGN](docs/DESIGN.md) · [QUALITY](docs/QUALITY.md) · [SECURITY](docs/SECURITY.md)
TMPL
    fixed+=("创建 CLAUDE.md（最小导航）")

    # 同时创建 AGENTS.md 符号链接
    if [[ ! -f "$root/AGENTS.md" ]] && [[ ! -L "$root/AGENTS.md" ]]; then
      ln -sf CLAUDE.md "$root/AGENTS.md"
      fixed+=("创建 AGENTS.md → CLAUDE.md 符号链接")
    fi
  fi

  # 创建缺失目录
  for d in "${SNS_DOC_REQUIRED_DIRS[@]}"; do
    if [[ ! -d "$root/docs/$d" ]]; then
      mkdir -p "$root/docs/$d"
      fixed+=("创建目录: docs/$d")
    fi
  done

  # 创建缺失模板文件
  for f in "${SNS_DOC_REQUIRED_FILES[@]}"; do
    if [[ ! -f "$root/$f" ]]; then
      cat > "$root/$f" <<TMPL
# $(basename "$f" .md)

> 此文件为自动生成，请根据项目实际情况填写内容。
TMPL
      fixed+=("创建模板: $f")
    fi
  done

  # 创建缺失 index.md
  for idx in "${SNS_DOC_INDEX_FILES[@]}"; do
    if [[ ! -f "$root/$idx" ]]; then
      local dir_name
      dir_name=$(basename "$(dirname "$idx")")
      cat > "$root/$idx" <<TMPL
# $(basename "$idx" /index.md) 索引

## 文档列表

> 请在此列出本目录下的文档及其简要说明。

| 文件 | 描述 |
|------|------|
TMPL
      fixed+=("创建索引: $idx")
    fi
  done

  if [[ ${#fixed[@]} -eq 0 ]]; then
    echo "文档架构已完整，无需修复"
  else
    echo "已修复 ${#fixed[@]} 项:"
    for f in "${fixed[@]}"; do echo "  $f"; done
  fi

  return 0
}

# === 首次迁移：将现有文件整理到目标架构 ===
sns_doc_migrate() {
  local root
  root=$(_sns_doc_root)

  local migrated=()
  local skipped=()

  # 0. 确保 CLAUDE.md 存在（由 sns_doc_fix 自动创建）
  if [[ ! -f "$root/CLAUDE.md" ]]; then
    echo "CLAUDE.md 不存在，将自动创建最小导航文件"
  fi

  # 1. 先创建目录骨架
  sns_doc_fix --auto >/dev/null 2>&1
  echo "已创建目录骨架"

  # 2. 迁移 workflow-development-spec.md（拆分）
  local spec_src="$root/docs/workflow-specs/workflow-development-spec.md"
  if [[ -f "$spec_src" ]]; then
    # 检查是否已有 ARCHITECTURE.md
    if [[ ! -f "$root/docs/ARCHITECTURE.md" ]] || [[ ! -s "$root/docs/ARCHITECTURE.md" ]]; then
      # 复制到 ARCHITECTURE.md（保留原始内容作为起点）
      cp "$spec_src" "$root/docs/ARCHITECTURE.md"
      migrated+=("docs/workflow-specs/workflow-development-spec.md → docs/ARCHITECTURE.md")
    fi

    # 如果 skill-conventions.md 不存在，也从 spec 提取一份
    if [[ ! -f "$root/docs/references/skill-conventions.md" ]]; then
      cp "$spec_src" "$root/docs/references/skill-conventions.md"
      migrated+=("docs/workflow-specs/workflow-development-spec.md → docs/references/skill-conventions.md")
    fi
  fi

  # 3. 迁移 versioning_guide.md
  if [[ -f "$root/docs/workflow-specs/versioning_guide.md" ]]; then
    if [[ ! -f "$root/docs/design-docs/versioning-model.md" ]]; then
      cp "$root/docs/workflow-specs/versioning_guide.md" "$root/docs/design-docs/versioning-model.md"
      migrated+=("docs/workflow-specs/versioning_guide.md → docs/design-docs/versioning-model.md")
    fi
  fi

  # 4. 迁移 test-plan.md
  if [[ -f "$root/docs/workflow-specs/test-plan.md" ]]; then
    if [[ ! -f "$root/docs/QUALITY.md" ]] || [[ ! -s "$root/docs/QUALITY.md" ]]; then
      cp "$root/docs/workflow-specs/test-plan.md" "$root/docs/QUALITY.md"
      migrated+=("docs/workflow-specs/test-plan.md → docs/QUALITY.md")
    fi
  fi

  # 5. 迁移 skill-development-plan.md
  if [[ -f "$root/docs/workflow-specs/skill-development-plan.md" ]]; then
    if [[ ! -f "$root/docs/exec-plans/active/skill-refactor-plan.md" ]]; then
      cp "$root/docs/workflow-specs/skill-development-plan.md" "$root/docs/exec-plans/active/skill-refactor-plan.md"
      migrated+=("docs/workflow-specs/skill-development-plan.md → docs/exec-plans/active/skill-refactor-plan.md")
    fi
  fi

  # 6. 迁移 dual-line-model.md
  if [[ -f "$root/docs/git-workflow/dual-line-model.md" ]]; then
    if [[ ! -f "$root/docs/references/git-workflow.md" ]]; then
      cp "$root/docs/git-workflow/dual-line-model.md" "$root/docs/references/git-workflow.md"
      migrated+=("docs/git-workflow/dual-line-model.md → docs/references/git-workflow.md")
    fi
  fi

  # 7. 迁移 SVG 图表
  if [[ -d "$root/docs/git-workflow" ]]; then
    mkdir -p "$root/docs/references/diagrams"
    for svg in "$root/docs/git-workflow"/*.svg; do
      if [[ -f "$svg" ]] && [[ ! -f "$root/docs/references/diagrams/$(basename "$svg")" ]]; then
        cp "$svg" "$root/docs/references/diagrams/"
        migrated+=("docs/git-workflow/$(basename "$svg") → docs/references/diagrams/")
      fi
    done
  fi

  # 8. 合并 plugins/sns-workflow/docs/workflow.md → docs/ARCHITECTURE.md
  if [[ -f "$root/plugins/sns-workflow/docs/workflow.md" ]]; then
    local arch="$root/docs/ARCHITECTURE.md"
    # 追加到 ARCHITECTURE.md 末尾（作为 v2/v3 架构参考）
    cat >> "$arch" <<SEPARATOR

---

## SNS-Workflow 架构参考 (v2/v3)

> 以下内容由迁移脚本自动追加，来自 plugins/sns-workflow/docs/workflow.md

SEPARATOR
    cat "$root/plugins/sns-workflow/docs/workflow.md" >> "$arch"
    migrated+=("plugins/sns-workflow/docs/workflow.md → docs/ARCHITECTURE.md (追加)")
  fi

  # 9. 迁移 provider-dispatch.md
  if [[ -f "$root/plugins/sns-workflow/docs/workflow-refs/provider-dispatch.md" ]]; then
    if [[ ! -f "$root/docs/references/provider-dispatch.md" ]]; then
      cp "$root/plugins/sns-workflow/docs/workflow-refs/provider-dispatch.md" "$root/docs/references/provider-dispatch.md"
      migrated+=("plugins/.../provider-dispatch.md → docs/references/provider-dispatch.md")
    fi
  fi

  # 10. 迁移 requirements（标记为外部项目）
  if [[ -f "$root/docs/requirements/investment-analysis-system.md" ]]; then
    if [[ ! -f "$root/docs/product-specs/investment-analysis-system.md" ]]; then
      cp "$root/docs/requirements/investment-analysis-system.md" "$root/docs/product-specs/"
      migrated+=("docs/requirements/* → docs/product-specs/")
    fi
  fi

  # 11. 创建 AGENTS.md 符号链接
  if [[ ! -f "$root/AGENTS.md" ]] && [[ ! -L "$root/AGENTS.md" ]]; then
    ln -sf CLAUDE.md "$root/AGENTS.md"
    migrated+=("创建 AGENTS.md → CLAUDE.md 符号链接")
  fi

  # 输出汇总
  echo ""
  echo "=== 迁移完成 ==="
  if [[ ${#migrated[@]} -gt 0 ]]; then
    echo "已迁移 ${#migrated[@]} 项:"
    for m in "${migrated[@]}"; do echo "  $m"; done
  fi
  if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "已跳过 ${#skipped[@]} 项（目标已存在）:"
    for s in "${skipped[@]}"; do echo "  $s"; done
  fi
  echo ""
  echo "注意: 原始文件保留在原位置，未被删除。"
  echo "请手动检查 docs/ 目录内容并调整。"

  return 0
}
