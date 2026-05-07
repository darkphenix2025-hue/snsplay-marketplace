#!/usr/bin/env bash
# skill-logger.sh — Skill execution tracking logger (bash-level)
# Writes to ~/.sns-workflow/skill-executions.log
#
# Usage (in SKILL.md bash block, after sourcing context.sh):
#   source "$SHELL_DIR/skill-logger.sh"
#   sns_skill_start "skill-name" "$*"
#   sns_skill_step "step-name" "details"
#   sns_skill_error "error description"
#   sns_skill_end "success" "details"

[[ -n "$_SNS_LOGGER_LOADED" ]] && return 0
_SNS_LOGGER_LOADED=true

_SNS_LOG_DIR="${HOME}/.sns-workflow"
_SNS_LOG_FILE="$_SNS_LOG_DIR/skill-executions.log"
_SNS_SKILL_LOG_DIR="$_SNS_LOG_DIR/skills"
_SNS_SKILL_NAME=""
_SNS_SKILL_START_TS=""
_SNS_SKILL_ENDED=false
_SNS_MAX_LOG_SIZE=$((5 * 1024 * 1024))  # 5 MB

_sns_log_rotate() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local size
  size=$(wc -c < "$f" 2>/dev/null || echo 0)
  [[ "$size" -lt "$_SNS_MAX_LOG_SIZE" ]] && return 0
  [[ -f "${f}.2" ]] && mv -f "${f}.2" "${f}.3" 2>/dev/null
  [[ -f "${f}.1" ]] && mv -f "${f}.1" "${f}.2" 2>/dev/null
  mv -f "$f" "${f}.1" 2>/dev/null
  return 0
}

_sns_log_write() {
  local line="$1"
  mkdir -p "$_SNS_LOG_DIR" "$_SNS_SKILL_LOG_DIR" 2>/dev/null
  { echo "$line" >> "$_SNS_LOG_FILE"; } 2>/dev/null
  if [[ -n "$_SNS_SKILL_NAME" ]]; then
    { echo "$line" >> "$_SNS_SKILL_LOG_DIR/${_SNS_SKILL_NAME}.log"; } 2>/dev/null
  fi
  _sns_log_rotate "$_SNS_LOG_FILE"
  if [[ -n "$_SNS_SKILL_NAME" ]]; then
    _sns_log_rotate "$_SNS_SKILL_LOG_DIR/${_SNS_SKILL_NAME}.log"
  fi
  return 0
}

_sns_ts() {
  date -u +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ
}

# 安全守卫: 即使脚本中途退出，也确保 sns_skill_end 被调用
_sns_logger_trap() {
  if [[ "$_SNS_SKILL_ENDED" != "true" ]] && [[ -n "$_SNS_SKILL_NAME" ]]; then
    _sns_log_write "{\"ts\":\"$(_sns_ts)\",\"skill\":\"${_SNS_SKILL_NAME}\",\"action\":\"end\",\"status\":\"failed\",\"duration_ms\":0,\"details\":\"unexpected exit\"}"
  fi
}
trap '_sns_logger_trap' EXIT

sns_skill_start() {
  _SNS_SKILL_NAME="${1:-unknown}"
  _SNS_SKILL_START_TS=$(_sns_ts)
  local args="${2:-}"
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  _sns_log_write "{\"ts\":\"${_SNS_SKILL_START_TS}\",\"skill\":\"${_SNS_SKILL_NAME}\",\"action\":\"start\",\"args\":\"${args}\",\"pid\":$$,\"branch\":\"${branch}\"}"
}

sns_skill_step() {
  local step="${1:-unknown}"
  local details="${2:-}"
  local ts
  ts=$(_sns_ts)
  local escaped_details="${details//\"/\\\"}"
  _sns_log_write "{\"ts\":\"${ts}\",\"skill\":\"${_SNS_SKILL_NAME}\",\"action\":\"step\",\"step\":\"${step}\",\"details\":\"${escaped_details}\"}"
}

sns_skill_error() {
  local error="${1:-unknown error}"
  local ts
  ts=$(_sns_ts)
  local escaped="${error//\"/\\\"}"
  _sns_log_write "{\"ts\":\"${ts}\",\"skill\":\"${_SNS_SKILL_NAME}\",\"action\":\"error\",\"error\":\"${escaped}\"}"
}

sns_skill_end() {
  local status="${1:-unknown}"
  local details="${2:-}"
  local ts
  ts=$(_sns_ts)
  local duration_ms=0
  if [[ -n "$_SNS_SKILL_START_TS" ]]; then
    local start_epoch end_epoch
    start_epoch=$(date -d "${_SNS_SKILL_START_TS}" +%s 2>/dev/null || echo 0)
    end_epoch=$(date -d "${ts}" +%s 2>/dev/null || echo 0)
    duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
  fi
  local escaped="${details//\"/\\\"}"
  _sns_log_write "{\"ts\":\"${ts}\",\"skill\":\"${_SNS_SKILL_NAME}\",\"action\":\"end\",\"status\":\"${status}\",\"duration_ms\":${duration_ms},\"details\":\"${escaped}\"}"
  _SNS_SKILL_ENDED=true
  _SNS_SKILL_NAME=""
  _SNS_SKILL_START_TS=""
}
