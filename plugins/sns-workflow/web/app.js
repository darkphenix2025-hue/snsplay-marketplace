/**
 * 工作流管理配置门户 - Alpine.js 应用
 *
 * 模块化拆分：
 *   app-presets.js  — AI 预设 CRUD、测试连接、密钥显示、模型选项
 *   app-chatroom.js — 辩论聊天室参与者管理
 *   app-v3.js       — 系统提示词、阶段（内联执行器）、工作流、设置
 *
 * 安全性：所有动态内容使用 x-text（自动转义）或 x-bind。
 * 动态数据不使用 innerHTML（防止 XSS）。
 */

function snsWorkflowApp() {
  return {
    // 当前激活的标签页
    tab: 'presets',

    // 共享 UI 状态
    loading: { presets: false, chatroom: false },
    saving: { chatroom: false },
    errorMsg: '',
    successMsg: '',
    darkMode: false,

    // Spread all mixins
    ...presetsMixin(),
    ...chatroomMixin(),
    ...v3Mixin(),

    /**
     * 初始化应用 — 加载预设、阶段定义和主题。
     */
    async init() {
      this.initTheme();
      await Promise.all([
        this.loadPresets(),
        this.loadStageDefinitions(),
      ]);
    },

    /**
     * 初始化主题：立即应用 localStorage（无闪烁），
     * 然后在后台同步服务器配置。
     */
    initTheme() {
      // 立即应用 localStorage 设置（无闪烁）
      const saved = localStorage.getItem('snsworkflow-theme');
      this.darkMode = saved === 'dark';
      if (this.darkMode) {
        document.body.setAttribute('data-theme', 'dark');
      }
      // 后台同步服务器配置
      fetch('/api/settings').then(r => r.ok ? r.json() : null).then(settings => {
        if (settings?.theme && settings.theme !== (this.darkMode ? 'dark' : 'light')) {
          this.darkMode = settings.theme === 'dark';
          if (this.darkMode) document.body.setAttribute('data-theme', 'dark');
          else document.body.removeAttribute('data-theme');
          localStorage.setItem('snsworkflow-theme', settings.theme);
        }
      }).catch(() => {});
    },

    /**
     * 切换明/暗主题。
     * 同时保存到 localStorage（即时）和服务器配置（持久）。
     */
    toggleTheme() {
      this.darkMode = !this.darkMode;
      const theme = this.darkMode ? 'dark' : 'light';
      if (this.darkMode) {
        document.body.setAttribute('data-theme', 'dark');
      } else {
        document.body.removeAttribute('data-theme');
      }
      localStorage.setItem('snsworkflow-theme', theme);
      // 保持 v3Settings 同步，避免"保存设置"时主题回滚
      if (this.v3Settings) this.v3Settings.theme = theme;
      // 异步保存到服务器
      fetch('/api/settings', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ theme }),
      }).catch(() => {});
    },

    /**
     * 显示错误消息（5 秒后自动清除）。
     */
    showError(msg) {
      this.errorMsg = msg;
      this.successMsg = '';
      setTimeout(() => { this.errorMsg = ''; }, 5000);
    },

    /**
     * 显示成功消息（3 秒后自动清除）。
     */
    showSuccess(msg) {
      this.successMsg = msg;
      this.errorMsg = '';
      setTimeout(() => { this.successMsg = ''; }, 3000);
    },
  };
}
