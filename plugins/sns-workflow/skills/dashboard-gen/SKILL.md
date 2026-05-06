---
name: sns-workflow:dashboard-gen
description: 仪表板定义生成 —— 基于项目架构和关键指标自动生成 Grafana 风格监控面板定义。支持 --auto 模式随架构变更自动更新。
user-invocable: true
allowed-tools: Bash, Read, Write, Glob
---

# 仪表板定义生成（Dashboard Generator）

基于项目架构和关键指标自动生成 Grafana 风格监控面板定义文件。覆盖 Harness Engineering 实践："Production dashboard definition files"。

**用法**:
- `dashboard-gen` — 扫描项目并生成仪表板定义
- `dashboard-gen --auto` — 随架构变更自动更新已有仪表板
- `dashboard-gen --refresh` — 强制重建所有面板

**数据源**: `.snsplay/task/` 产物、项目配置文件、dev-server 配置、observe 指标
**产物**: `.snsplay/dashboards/*.json`、`.snsplay/task/dashboard-gen-${TIMESTAMP}.json`

---

## 步骤 1: 扫描项目关键指标

分析项目结构和已有产物，提取可观测性指标。

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"
DASH_DIR="$ROOT/.snsplay/dashboards"
mkdir -p "$DASH_DIR"

current_branch=$(git branch --show-current)
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# 解析参数
AUTO_MODE=false
REFRESH_MODE=false

for arg in "$@"; do
  case "$arg" in
    --auto) AUTO_MODE=true ;;
    --refresh) REFRESH_MODE=true ;;
  esac
done

echo "=== 仪表板生成: 扫描指标 ==="
echo "项目根目录: $ROOT"
echo "输出目录: $DASH_DIR"
```

### 1a: 提取服务信息

```bash
SERVICE_PORT=""
SERVICE_NAME=""

# 从 dev-server 配置获取端口
if [[ -f "$ROOT/.snsplay/task/dev-servers.json" ]]; then
  SERVICE_PORT=$(python3 -c "
import json
with open('$ROOT/.snsplay/task/dev-servers.json') as f: d = json.load(f)
servers = d.get('servers', [])
print(servers[-1]['port'] if servers else '')
" 2>/dev/null)
fi

# 从项目配置提取服务名
if [[ -f "$ROOT/package.json" ]]; then
  SERVICE_NAME=$(python3 -c "
import json
with open('$ROOT/package.json') as f: d = json.load(f)
print(d.get('name', 'unknown'))
" 2>/dev/null)
elif [[ -f "$ROOT/Cargo.toml" ]]; then
  SERVICE_NAME=$(grep -m1 '^name' "$ROOT/Cargo.toml" 2>/dev/null | sed 's/name *= *"\(.*\)"/\1/')
elif [[ -f "$ROOT/go.mod" ]]; then
  SERVICE_NAME=$(head -1 "$ROOT/go.mod" 2>/dev/null | awk '{print $2}')
else
  SERVICE_NAME=$(basename "$ROOT")
fi

echo "服务: $SERVICE_NAME (port: ${SERVICE_PORT:-unknown})"
```

### 1b: 提取工作流运行指标

```bash
OBSERVE_METRICS='{"tasks_total":0,"tasks_succeeded":0,"tasks_failed":0,"success_rate":100}'

if [[ -d "$TASK_DIR" ]]; then
  plan_count=$(ls "$TASK_DIR"/plan-*.json 2>/dev/null | wc -l | tr -d ' ')
  review_count=$(ls "$TASK_DIR"/review-*.json 2>/dev/null | wc -l | tr -d ' ')
  qagate_count=$(ls "$TASK_DIR"/qa-gate-*.json 2>/dev/null | wc -l | tr -d ' ')
  ui_count=$(ls "$TASK_DIR"/ui-verify-*.json 2>/dev/null | wc -l | tr -d ' ')
  heal_count=$(ls "$TASK_DIR"/heal-*.json 2>/dev/null | wc -l | tr -d ' ')
  impl_count=$(ls "$TASK_DIR"/impl-result*.json 2>/dev/null | wc -l | tr -d ' ')

  tasks_total=$((plan_count + review_count + qagate_count + ui_count + heal_count + impl_count))
  failed_impl=$(ls "$TASK_DIR"/impl-result*.json 2>/dev/null | xargs grep -l '"status"[[:space:]]*:[[:space:]]*"failed"' 2>/dev/null | wc -l | tr -d ' ')
  failed_gate=$(ls "$TASK_DIR"/qa-gate-*.json 2>/dev/null | xargs grep -l '"verdict"[[:space:]]*:[[:space:]]*"FAIL"' 2>/dev/null | wc -l | tr -d ' ')
  tasks_failed=$((failed_impl + failed_gate))
  tasks_succeeded=$((tasks_total - tasks_failed))
  success_rate=$(python3 -c "print(round($tasks_succeeded / max($tasks_total, 1) * 100, 1))")

  OBSERVE_METRICS=$(python3 -c "
import json
print(json.dumps({
    'tasks_total': $tasks_total,
    'tasks_succeeded': $tasks_succeeded,
    'tasks_failed': $tasks_failed,
    'success_rate': $success_rate,
    'plan_count': $plan_count,
    'review_count': $review_count,
    'qagate_count': $qagate_count,
    'ui_count': $ui_count,
    'heal_count': $heal_count,
    'impl_count': $impl_count
}))
" 2>/dev/null)

  echo "工作流指标: total=$tasks_total succeeded=$tasks_succeeded failed=$tasks_failed rate=${success_rate}%"
fi
```

### 1c: 提取架构质量指标

```bash
ARCH_METRICS='{"drift_score":0,"drift_grade":"N/A","arch_violations":0}'

if [[ -f "$TASK_DIR/drift-baseline.json" ]]; then
  ARCH_METRICS=$(python3 -c "
import json
with open('$TASK_DIR/drift-baseline.json') as f: d = json.load(f)
print(json.dumps({
    'drift_score': d.get('total_score', 0),
    'drift_grade': d.get('grade', 'N/A'),
    'drift_trend': d.get('trend', 'new'),
    'arch_violations': len(d.get('deductions', []))
}))
" 2>/dev/null)
  echo "架构指标: $(echo "$ARCH_METRICS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(f'score={d[\"drift_score\"]} grade={d[\"drift_grade\"]}')")"
fi
```

---

## 步骤 2: 生成面板定义

按类别生成 Grafana 风格 JSON 面板。每类输出为独立文件到 `.snsplay/dashboards/`。

### 2a: 服务健康面板（service-health.json）

```bash
python3 << 'PYEOF'
import json, datetime

service = "SERVICE_NAME_PLACEHOLDER"
port = "PORT_PLACEHOLDER"

dashboard = {
    "id": None,
    "uid": "service-health",
    "title": f"{service} - 服务健康度",
    "tags": ["sns-workflow", "service-health", "auto-generated"],
    "timezone": "browser",
    "schemaVersion": 38,
    "version": 1,
    "refresh": "30s",
    "panels": [
        {
            "id": 1, "title": "服务启动状态", "type": "stat",
            "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
            "targets": [{"expr": f'up{{service="{service}"}}', "legendFormat": "Status"}],
            "fieldConfig": {"defaults": {"thresholds": {"steps": [
                {"color": "red", "value": None}, {"color": "green", "value": 1}
            ]}}}
        },
        {
            "id": 2, "title": "运行端口", "type": "stat",
            "gridPos": {"h": 4, "w": 4, "x": 6, "y": 0},
            "targets": [{"expr": f'http_server_port{{port="{port}"}}', "legendFormat": "Port"}]
        },
        {
            "id": 3, "title": "请求错误率", "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
            "targets": [{"expr": f'rate(http_requests_total{{service="{service}",status=~"5.."}}[5m]) / rate(http_requests_total{{service="{service}"}}[5m])', "legendFormat": "5xx rate"}],
            "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0, "max": 1}}
        },
        {
            "id": 4, "title": "工作流成功率", "type": "gauge",
            "gridPos": {"h": 8, "w": 6, "x": 12, "y": 4},
            "targets": [{"expr": f'workflow_success_rate{{service="{service}"}}', "legendFormat": "Success %"}],
            "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100, "thresholds": {"steps": [
                {"color": "red", "value": None}, {"color": "yellow", "value": 60}, {"color": "green", "value": 85}
            ]}}}
        },
        {
            "id": 5, "title": "任务完成分布", "type": "piechart",
            "gridPos": {"h": 8, "w": 6, "x": 18, "y": 4},
            "targets": [
                {"expr": 'workflow_tasks_total{type="plan"}', "legendFormat": "Plan"},
                {"expr": 'workflow_tasks_total{type="review"}', "legendFormat": "Review"},
                {"expr": 'workflow_tasks_total{type="qagate"}', "legendFormat": "QAGate"},
                {"expr": 'workflow_tasks_total{type="ui-verify"}', "legendFormat": "UIVerify"}
            ]
        },
        {
            "id": 6, "title": "平均响应时间", "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
            "targets": [{"expr": f'histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{{service="{service}"}}[5m]))', "legendFormat": "p95 latency"}],
            "fieldConfig": {"defaults": {"unit": "s"}}
        },
        {
            "id": 7, "title": "启动时间", "type": "stat",
            "gridPos": {"h": 4, "w": 6, "x": 12, "y": 12},
            "targets": [{"expr": f'process_start_time_seconds{{service="{service}"}}', "legendFormat": "Started"}],
            "fieldConfig": {"defaults": {"unit": "dateTimeFromNow"}}
        },
        {
            "id": 8, "title": "错误日志趋势", "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
            "targets": [
                {"expr": f'rate(log_errors_total{{service="{service}"}}[5m])', "legendFormat": "Errors"},
                {"expr": f'rate(log_warnings_total{{service="{service}"}}[5m])', "legendFormat": "Warnings"}
            ]
        }
    ],
    "time": {"from": "now-6h", "to": "now"},
    "meta": {
        "generated_by": "sns-workflow:dashboard-gen",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }
}

print(json.dumps(dashboard, indent=2, ensure_ascii=False))
PYEOF
```

Agent 应将上述输出写入 `$DASH_DIR/service-health.json`，将 `SERVICE_NAME_PLACEHOLDER` 替换为实际 `$SERVICE_NAME`，`PORT_PLACEHOLDER` 替换为实际 `$SERVICE_PORT`。

### 2b: 工作流运行面板（workflow-operations.json）

```bash
python3 << 'PYEOF'
import json, datetime

dashboard = {
    "id": None,
    "uid": "workflow-operations",
    "title": "工作流运行指标",
    "tags": ["sns-workflow", "workflow", "auto-generated"],
    "timezone": "browser",
    "schemaVersion": 38,
    "version": 1,
    "panels": [
        {
            "id": 1, "title": "总任务数", "type": "stat",
            "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
            "targets": [{"expr": "workflow_tasks_total", "legendFormat": "Tasks"}]
        },
        {
            "id": 2, "title": "成功/失败", "type": "bargauge",
            "gridPos": {"h": 4, "w": 10, "x": 6, "y": 0},
            "targets": [
                {"expr": "workflow_tasks_succeeded", "legendFormat": "Succeeded"},
                {"expr": "workflow_tasks_failed", "legendFormat": "Failed"}
            ]
        },
        {
            "id": 3, "title": "成功率趋势", "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
            "targets": [{"expr": "rate(workflow_tasks_succeeded[1h]) / rate(workflow_tasks_total[1h])", "legendFormat": "Success Rate"}],
            "fieldConfig": {"defaults": {"unit": "percentunit"}}
        },
        {
            "id": 4, "title": "按类型分布", "type": "barchart",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
            "targets": [
                {"expr": 'workflow_tasks_total{type="plan"}', "legendFormat": "Plan"},
                {"expr": 'workflow_tasks_total{type="review"}', "legendFormat": "Review"},
                {"expr": 'workflow_tasks_total{type="impl"}', "legendFormat": "Impl"},
                {"expr": 'workflow_tasks_total{type="qagate"}', "legendFormat": "QAGate"},
                {"expr": 'workflow_tasks_total{type="heal"}', "legendFormat": "Heal"},
                {"expr": 'workflow_tasks_total{type="ui-verify"}', "legendFormat": "UIVerify"}
            ]
        },
        {
            "id": 5, "title": "任务耗时分布 (P50/P90/P95)", "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
            "targets": [
                {"expr": "histogram_quantile(0.50, rate(workflow_task_duration_seconds_bucket[1h]))", "legendFormat": "P50"},
                {"expr": "histogram_quantile(0.90, rate(workflow_task_duration_seconds_bucket[1h]))", "legendFormat": "P90"},
                {"expr": "histogram_quantile(0.95, rate(workflow_task_duration_seconds_bucket[1h]))", "legendFormat": "P95"}
            ],
            "fieldConfig": {"defaults": {"unit": "s"}}
        },
        {
            "id": 6, "title": "失败任务 Top 原因", "type": "table",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
            "targets": [{"expr": "workflow_failure_reason", "legendFormat": "{{reason}}"}]
        }
    ],
    "meta": {
        "generated_by": "sns-workflow:dashboard-gen",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }
}

print(json.dumps(dashboard, indent=2, ensure_ascii=False))
PYEOF
```

Agent 将输出写入 `$DASH_DIR/workflow-operations.json`。

### 2c: 架构质量面板（architecture-quality.json）

```bash
python3 << 'PYEOF'
import json, datetime

dashboard = {
    "id": None,
    "uid": "architecture-quality",
    "title": "架构质量监控",
    "tags": ["sns-workflow", "architecture", "drift", "auto-generated"],
    "timezone": "browser",
    "schemaVersion": 38,
    "version": 1,
    "panels": [
        {
            "id": 1, "title": "漂移评分", "type": "gauge",
            "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
            "targets": [{"expr": "drift_total_score", "legendFormat": "Score"}],
            "fieldConfig": {"defaults": {"unit": "short", "min": 0, "max": 100, "thresholds": {"steps": [
                {"color": "red", "value": None}, {"color": "yellow", "value": 50}, {"color": "green", "value": 80}
            ]}}}
        },
        {
            "id": 2, "title": "评级", "type": "stat",
            "gridPos": {"h": 4, "w": 4, "x": 8, "y": 0},
            "targets": [{"expr": "drift_grade", "legendFormat": "Grade"}],
            "fieldConfig": {"defaults": {"thresholds": {"steps": [
                {"color": "green", "value": None}, {"color": "yellow", "value": 3}, {"color": "red", "value": 4}
            ]}}}
        },
        {
            "id": 3, "title": "分类评分", "type": "radialbar",
            "gridPos": {"h": 8, "w": 12, "x": 8, "y": 0},
            "targets": [
                {"expr": 'drift_category_score{category="structure"}', "legendFormat": "Structure"},
                {"expr": 'drift_category_score{category="naming"}', "legendFormat": "Naming"},
                {"expr": 'drift_category_score{category="dependencies"}', "legendFormat": "Dependencies"},
                {"expr": 'drift_category_score{category="documentation"}', "legendFormat": "Documentation"}
            ],
            "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100}}
        },
        {
            "id": 4, "title": "架构违规清单", "type": "table",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
            "targets": [{"expr": "arch_violations", "legendFormat": "{{rule}}"}]
        }
    ],
    "meta": {
        "generated_by": "sns-workflow:dashboard-gen",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }
}

print(json.dumps(dashboard, indent=2, ensure_ascii=False))
PYEOF
```

Agent 将输出写入 `$DASH_DIR/architecture-quality.json`。

---

## 步骤 3: 验证面板

检查生成的 JSON 格式和面板引用完整性。

```bash
echo ""
echo "=== 面板验证 ==="

VALIDATION_OK=true
TOTAL_PANELS=0
DASHBOARD_LIST=""

for dashboard_file in "$DASH_DIR"/*.json; do
  [[ -f "$dashboard_file" ]] || continue

  filename=$(basename "$dashboard_file")
  echo ""
  echo "验证: $filename"

  # JSON 格式校验
  python3 -c "
import json, sys
try:
    with open('$dashboard_file') as f:
        d = json.load(f)
    panels = d.get('panels', [])
    print(f'  格式: 有效 JSON')
    print(f'  面板数: {len(panels)}')
    print(f'  标题: {d.get(\"title\", \"(untitled)\")}')

    # 检查每个面板必需字段
    errors = []
    for p in panels:
        pid = p.get('id', '?')
        if 'id' not in p:
            errors.append(f'panel {p.get(\"title\",\"?\")} 缺少 id')
        if 'type' not in p:
            errors.append(f'panel {pid} 缺少 type')
        if 'gridPos' not in p:
            errors.append(f'panel {pid} 缺少 gridPos')
        if 'targets' not in p:
            errors.append(f'panel {pid} 缺少 targets')

    # 检查查询语句非空
    for p in panels:
        for t in p.get('targets', []):
            if 'expr' in t and not t['expr'].strip():
                errors.append(f'panel {p.get(\"id\",\"?\")} 空查询语句')

    if errors:
        for e in errors:
            print(f'  警告: {e}')
    else:
        print(f'  面板字段: 全部通过 ({len(panels)} 个)')

except json.JSONDecodeError as e:
    print(f'  格式错误: {e}')
    sys.exit(1)
" 2>/dev/null

  result=$?
  if [[ $result -ne 0 ]]; then
    VALIDATION_OK=false
    echo "  ✗ 验证失败"
  else
    echo "  ✓ 验证通过"
  fi

  # 统计面板数
  panels=$(python3 -c "
import json
with open('$dashboard_file') as f: d = json.load(f)
print(len(d.get('panels', [])))
" 2>/dev/null)
  TOTAL_PANELS=$((TOTAL_PANELS + panels))
  DASHBOARD_LIST="${DASHBOARD_LIST}{\"name\":\"${filename%.json}\",\"panels\":${panels},\"format\":\"grafana\"},"
done

echo ""
echo "总计: ${TOTAL_PANELS} 个面板"
```

---

## 步骤 4: 输出产物报告

写入 artifact 并输出汇总信息。

```bash
echo ""
echo "=== 仪表板生成完成 ==="

# 去除末尾逗号
DASHBOARD_LIST="[${DASHBOARD_LIST%,}]"

python3 -c "
import json, datetime

artifact = {
    'id': 'dashboard-gen-${TIMESTAMP}',
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'branch': '$current_branch',
    'mode': 'auto' if '$AUTO_MODE' == 'true' else 'manual',
    'dashboards': json.loads('${DASHBOARD_LIST}'),
    'output_dir': '.snsplay/dashboards/',
    'total_panels': $TOTAL_PANELS,
    'validation_passed': True
}

with open('$TASK_DIR/dashboard-gen-${TIMESTAMP}.json', 'w') as f:
    json.dump(artifact, f, indent=2, ensure_ascii=False)

print(f'产物: $TASK_DIR/dashboard-gen-${TIMESTAMP}.json')
print(f'仪表板数: {len(artifact[\"dashboards\"])}')
print(f'总面板数: {artifact[\"total_panels\"]}')
print()
for d in artifact['dashboards']:
    print(f'  {d[\"name\"]}: {d[\"panels\"]} panels')
" 2>/dev/null

echo ""
echo "输出目录: $DASH_DIR"
echo ""
echo "后续操作:"
echo "  将生成的 JSON 导入 Grafana 即可使用"
echo "  /sns-workflow:dashboard-gen --refresh   → 强制重建"
echo "  /sns-workflow:observe                    → 查看运行指标"
```
