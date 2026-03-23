/**
 * v3 模块化架构混入 - 工作流管理配置门户。
 * 处理系统提示词、阶段（内联执行器）、工作流、设置，
 * 以及从 agency-agents 画廊导入系统提示词。
 */
function v3Mixin() {
  return {
    // 系统提示词
    systemPrompts: [],
    loadingSystemPrompts: false,

    async loadSystemPrompts() {
      this.loadingSystemPrompts = true;
      try {
        const resp = await fetch('/api/system-prompts');
        if (!resp.ok) { this.showError('加载系统提示词失败'); return; }
        const data = await resp.json();
        this.systemPrompts = data.prompts || [];
      } catch (e) { this.showError('加载系统提示词时网络错误'); }
      finally { this.loadingSystemPrompts = false; }
    },

    async deleteSystemPrompt(name) {
      if (!confirm('确定要删除自定义提示词 "' + name + '"？')) return;
      try {
        const resp = await fetch('/api/system-prompts/' + encodeURIComponent(name), { method: 'DELETE' });
        if (!resp.ok) { const err = await resp.json().catch(() => ({})); this.showError(err.error?.message || '删除失败'); return; }
        this.showSuccess('提示词已删除：' + name);
        await this.loadSystemPrompts();
      } catch (e) { this.showError('网络错误'); }
    },

    // ============================================================
    // 阶段（内联执行器 + 拖放）
    // ============================================================

    v3Stages: {},
    loadingStages: false,
    _execIdCounter: 0,

    async loadStages() {
      this.loadingStages = true;
      try {
        const [stagesResp] = await Promise.all([
          fetch('/api/stages'),
          this.systemPrompts.length > 0 ? Promise.resolve() : this.loadSystemPrompts(),
          this.presets && Object.keys(this.presets).length > 0 ? Promise.resolve() : this.loadPresets(),
        ]);
        if (!stagesResp.ok) { this.showError('加载阶段列表失败'); return; }
        const data = await stagesResp.json();

        // 为阶段中使用的所有预设预取模型选项
        const allPresets = new Set();
        for (const stage of Object.values(data.stages || {})) {
          for (const exec of (stage.executors || [])) {
            if (exec.preset) allPresets.add(exec.preset);
          }
        }
        await Promise.allSettled([...allPresets].map(p => this._fetchModelOptions(p)));

        // 为每个执行器分配稳定的 _id 用于 x-for 键控
        const stages = data.stages || {};
        for (const stage of Object.values(stages)) {
          for (const exec of (stage.executors || [])) {
            exec._id = ++this._execIdCounter;
          }
        }
        this.v3Stages = stages;
      } catch (e) { this.showError('加载阶段列表时网络错误'); }
      finally { this.loadingStages = false; }
    },

    async saveStage(stageType) {
      try {
        const stage = this.v3Stages[stageType];
        // 发送到服务器前移除客户端专用的 _id 字段
        const cleanExecutors = stage.executors.map(({ _id, ...rest }) => rest);
        const resp = await fetch('/api/stages/' + encodeURIComponent(stageType), {
          method: 'PUT', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ executors: cleanExecutors }),
        });
        if (!resp.ok) { const err = await resp.json().catch(() => ({})); this.showError(err.error?.message || '保存失败'); return; }
        this.showSuccess('阶段已保存：' + stageType);
      } catch (e) { this.showError('网络错误'); }
    },

    addExecutorToStage(stageType) {
      const firstPrompt = this.systemPrompts.length > 0 ? this.systemPrompts[0].name : '';
      const firstPreset = Object.keys(this.presets)[0] || '';
      if (!this.v3Stages[stageType]) this.v3Stages[stageType] = { executors: [] };
      const newExec = {
        _id: ++this._execIdCounter,
        system_prompt: firstPrompt,
        preset: firstPreset,
        model: '',
        parallel: false,
      };
      // 使用展开语法强制 Alpine 响应式更新
      this.v3Stages[stageType] = {
        ...this.v3Stages[stageType],
        executors: [...this.v3Stages[stageType].executors, newExec],
      };
      if (firstPreset) this._fetchModelOptions(firstPreset);
    },

    removeExecutorFromStage(stageType, index) {
      const execs = this.v3Stages[stageType].executors.filter((_, i) => i !== index);
      // 安全检查：多执行器时确保最后一个执行器为非并行
      if (execs.length > 1 && execs[execs.length - 1].parallel === true) {
        execs[execs.length - 1].parallel = false;
      }
      this.v3Stages[stageType] = {
        ...this.v3Stages[stageType],
        executors: execs,
      };
    },

    async onStagePresetChange(exec) {
      exec.model = '';
      await this._fetchModelOptions(exec.preset);
    },

    // SortableJS 初始化执行器行
    initSortableExecutors(el, stageType) {
      if (el._sortableInstance) el._sortableInstance.destroy();
      el._sortableInstance = Sortable.create(el, {
        animation: 150,
        handle: '.drag-handle',
        ghostClass: 'sortable-ghost',
        filter: '.is-synthesizer',
        onMove: (evt) => {
          const execs = this.v3Stages[stageType].executors;
          if (execs.length <= 1) return true;
          // 阻止在最后一行（合成器）之后放置
          const children = [...evt.to.children].filter(c => c.classList.contains('executor-row'));
          const relatedIdx = children.indexOf(evt.related);
          if (relatedIdx === children.length - 1 && evt.willInsertAfter) return false;
          return true;
        },
        onEnd: (evt) => {
          const execs = [...this.v3Stages[stageType].executors];
          const moved = execs.splice(evt.oldIndex, 1)[0];
          execs.splice(evt.newIndex, 0, moved);
          // 安全检查：多执行器时确保最后一个执行器为非并行
          if (execs.length > 1 && execs[execs.length - 1].parallel === true) {
            execs[execs.length - 1].parallel = false;
          }
          this.v3Stages[stageType] = { ...this.v3Stages[stageType], executors: execs };
        },
      });
    },

    // ============================================================
    // 工作流 (v3)
    // ============================================================

    v3Workflows: { feature_workflow: [], bugfix_workflow: [] },
    loadingWorkflows: false,

    async loadWorkflows() {
      this.loadingWorkflows = true;
      try {
        const resp = await fetch('/api/workflows');
        if (!resp.ok) { this.showError('加载工作流失败'); return; }
        const data = await resp.json();
        this.v3Workflows = { feature_workflow: data.feature_workflow || [], bugfix_workflow: data.bugfix_workflow || [] };
      } catch (e) { this.showError('加载工作流时网络错误'); }
      finally { this.loadingWorkflows = false; }
    },

    async saveWorkflows() {
      try {
        const resp = await fetch('/api/workflows', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(this.v3Workflows) });
        if (!resp.ok) { const err = await resp.json().catch(() => ({})); this.showError(err.error?.message || '保存失败'); return; }
        this.showSuccess('工作流已保存');
      } catch (e) { this.showError('网络错误'); }
    },

    addStageToWorkflow(workflowKey) { this.v3Workflows[workflowKey].push('plan-review'); },
    removeStageFromWorkflow(workflowKey, index) { this.v3Workflows[workflowKey].splice(index, 1); },

    moveStageInWorkflow(workflowKey, index, direction) {
      const arr = this.v3Workflows[workflowKey];
      const newIndex = index + direction;
      if (newIndex < 0 || newIndex >= arr.length) return;
      [arr[index], arr[newIndex]] = [arr[newIndex], arr[index]];
    },

    // ============================================================
    // 设置
    // ============================================================

    v3Settings: { max_iterations: 10, max_tdd_iterations: 5 },
    loadingSettings: false,

    async loadSettings() {
      this.loadingSettings = true;
      try {
        const resp = await fetch('/api/settings');
        if (!resp.ok) { this.showError('加载设置失败'); return; }
        this.v3Settings = await resp.json();
      } catch (e) { this.showError('加载设置时网络错误'); }
      finally { this.loadingSettings = false; }
    },

    async saveSettings() {
      try {
        const resp = await fetch('/api/settings', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(this.v3Settings) });
        if (!resp.ok) { const err = await resp.json().catch(() => ({})); this.showError(err.error?.message || '保存失败'); return; }
        this.showSuccess('设置已保存');
      } catch (e) { this.showError('网络错误'); }
    },

    // ============================================================
    // Agency Agents 导入
    // ============================================================

    showImportDialog: false,
    importLoading: false,
    importCategories: [],
    importSelectedCategory: '',
    importAgents: [],
    importSelectedAgents: {},
    importProgress: null,
    _importPrevFocus: null,

    async openImportDialog() {
      this._importPrevFocus = document.activeElement;
      this.showImportDialog = true;
      this.importSelectedCategory = '';
      this.importAgents = [];
      this.importSelectedAgents = {};
      this.importProgress = null;
      document.body.style.overflow = 'hidden';

      if (this.importCategories.length > 0) return;
      this.importLoading = true;
      try {
        const resp = await fetch('https://api.github.com/repos/msitarzewski/agency-agents/contents/');
        if (resp.status === 403) { this.showError('GitHub API 请求频率超限，请稍后重试'); this.showImportDialog = false; document.body.style.overflow = ''; return; }
        if (!resp.ok) { this.showError('加载画廊分类失败'); return; }
        const items = await resp.json();
        this.importCategories = items
          .filter(item => item.type === 'dir' && !item.name.startsWith('.') && item.name !== 'scripts' && item.name !== 'integrations')
          .map(item => ({ name: item.name, path: item.path }));
      } catch (e) { this.showError('加载画廊时网络错误'); }
      finally { this.importLoading = false; }
    },

    closeImportDialog() {
      this.showImportDialog = false;
      document.body.style.overflow = '';
      if (this._importPrevFocus) {
        this._importPrevFocus.focus();
        this._importPrevFocus = null;
      }
    },

    async selectImportCategory(category) {
      this.importSelectedCategory = category;
      this.importAgents = [];
      this.importSelectedAgents = {};
      this.importLoading = true;
      try {
        const resp = await fetch('https://api.github.com/repos/msitarzewski/agency-agents/contents/' + encodeURIComponent(category));
        if (resp.status === 403) { this.showError('GitHub API 请求频率超限'); return; }
        if (!resp.ok) { this.showError('加载 ' + category + ' 分类的代理失败'); return; }
        const items = await resp.json();
        this.importAgents = items
          .filter(item => item.name.endsWith('.md') && !item.name.toLowerCase().startsWith('readme'))
          .map(item => ({ name: item.name.replace('.md', ''), path: item.path, download_url: item.download_url, html_url: item.html_url }));
      } catch (e) { this.showError('加载代理时网络错误'); }
      finally { this.importLoading = false; }
    },

    /**
     * 将 agency-agents markdown 文件转换为 sns-workflow 系统提示词格式。
     */
    convertAgencyAgentToPrompt(filename, rawContent) {
      let name = filename;
      let description = '';
      let tools = '';
      let body = rawContent;

      if (rawContent.startsWith('---')) {
        const endIdx = rawContent.indexOf('\n---', 3);
        if (endIdx !== -1) {
          const yamlBlock = rawContent.slice(4, endIdx).trim();
          body = rawContent.slice(endIdx + 4).trim();
          for (const line of yamlBlock.split('\n')) {
            const colonIdx = line.indexOf(':');
            if (colonIdx === -1) continue;
            const key = line.slice(0, colonIdx).trim();
            const value = line.slice(colonIdx + 1).trim();
            if (key === 'name') name = value;
            if (key === 'description') description = value;
            if (key === 'tools') tools = value;
          }
        }
      }

      // Sanitize name: lowercase, hyphens, no special chars
      const safeName = name.toLowerCase()
        .replace(/[\s_]+/g, '-')
        .replace(/[^a-z0-9-]/g, '')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') || filename.toLowerCase().replace(/[^a-z0-9-]/g, '-');

      const safeDescription = description || (name + ' 代理，从 agency-agents 画廊导入');
      // 保留原始工具（如有）；否则默认为全面工具集以提供最大灵活性
      const safeTools = tools || 'Read, Write, Edit, Glob, Grep, Bash, LSP';

      const content = [
        '---',
        'name: ' + safeName,
        'description: ' + safeDescription,
        'tools: ' + safeTools,
        '---',
        '',
        body,
      ].join('\n');

      return { name: safeName, content };
    },

    async importSelectedPrompts() {
      const selected = Object.entries(this.importSelectedAgents)
        .filter(([_, v]) => v)
        .map(([name]) => this.importAgents.find(a => a.name === name))
        .filter(Boolean);
      if (selected.length === 0) return;

      // Pre-convert all names and check for batch slug duplicates
      const converted = selected.map(agent => ({
        agent,
        ...this.convertAgencyAgentToPrompt(agent.name, ''),
      }));
      const seen = new Set();
      const deduped = [];
      for (const item of converted) {
        if (seen.has(item.name)) continue;
        seen.add(item.name);
        deduped.push(item);
      }

      // 检查是否已存在自定义提示词（覆盖确认）
      const existingCustom = this.systemPrompts.filter(p => p.source === 'custom').map(p => p.name);
      const willOverwrite = deduped.filter(d => existingCustom.includes(d.name)).map(d => d.name);
      if (willOverwrite.length > 0) {
        if (!confirm('以下提示词已存在，将被覆盖：\n\n' + willOverwrite.join(', ') + '\n\n确定继续？')) return;
      }

      this.importProgress = '正在导入 0/' + deduped.length + '...';
      let imported = 0;
      const errors = [];

      for (const item of deduped) {
        try {
          // 获取完整原始内容
          const resp = await fetch(item.agent.download_url);
          if (!resp.ok) { errors.push(item.agent.name); continue; }
          const rawContent = await resp.text();
          const result = this.convertAgencyAgentToPrompt(item.agent.name, rawContent);

          const saveResp = await fetch('/api/system-prompts/' + encodeURIComponent(result.name), {
            method: 'PUT',
            headers: { 'Content-Type': 'text/plain' },
            body: result.content,
          });
          if (!saveResp.ok) {
            const err = await saveResp.json().catch(() => ({}));
            errors.push(item.agent.name + ': ' + (err.error?.message || '保存失败'));
            continue;
          }
          imported++;
        } catch (e) {
          errors.push(item.agent.name);
        }
        this.importProgress = '正在导入 ' + imported + '/' + deduped.length + '...';
      }

      this.importProgress = null;
      this.closeImportDialog();
      if (errors.length > 0) {
        this.showError('已导入 ' + imported + ' 个，失败：' + errors.join(', '));
      } else {
        this.showSuccess('已导入 ' + imported + ' 个系统提示词');
      }
      await this.loadSystemPrompts();
    },
  };
}
