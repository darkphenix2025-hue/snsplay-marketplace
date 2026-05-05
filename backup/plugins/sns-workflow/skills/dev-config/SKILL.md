---
name: sns-workflow:dev-config
description: 工作流管理 Web 配置门户，用于管理预设和工作流配置
user-invocable: true
allowed-tools: Bash
---

# 工作流管理 Web 配置门户

启动 Web 配置门户以管理 AI 提供商预设和工作流配置。

## 启动门户

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/config-server.ts" --cwd "${CLAUDE_PROJECT_DIR}"
```

服务器功能：
1. 默认使用端口 5050 启动（如被占用则使用随机端口）
2. 自动打开用户的默认浏览器
3. 提供 Alpine.js 单页应用进行可视化配置
4. 60 分钟无活动后自动关闭

## 门户功能

| 标签页 | 功能 |
|--------|------|
| **AI 预设** | 列出、添加、更新、删除预设；显示/隐藏 API 密钥 |
| **工作流配置** | 配置每个阶段使用的预设 |

## 启动输出

服务器成功启动时会向 stdout 打印单行 JSON：

```json
{ "port": 12345, "url": "http://localhost:12345" }
```

告诉用户：`Web 门户运行在 http://localhost:{port}。按 Ctrl+C 或关闭终端以停止。`

服务器还会自动打开浏览器。如果浏览器未打开（例如 SSH 环境），用户可以手动访问该 URL。

## 停止门户

门户在 60 分钟无活动后自动停止。手动停止方式：
- 在运行服务器的终端中按 `Ctrl+C`

## 安全说明

- 门户仅限 localhost 访问 —— CORS 限制为精确的 `http://localhost:{port}` 来源
- API 密钥默认屏蔽；使用"显示密钥"按钮临时查看完整密钥
- 门户自动关闭以最小化攻击窗口
