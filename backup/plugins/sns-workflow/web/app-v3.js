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

    // 本地 agents 目录导入
    showLocalImportDialog: false,
    localImportLoading: false,
    localImportCategories: [],
    localImportSelectedCategory: '',
    localImportAgents: [],
    localImportSelectedAgents: {},
    localImportProgress: null,
    _localImportPrevFocus: null,

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

    async openLocalImportDialog() {
      this._localImportPrevFocus = document.activeElement;
      this.showLocalImportDialog = true;
      this.localImportSelectedCategory = '';
      this.localImportAgents = [];
      this.localImportSelectedAgents = {};
      this.localImportProgress = null;
      document.body.style.overflow = 'hidden';

      if (this.localImportCategories.length > 0) return;
      this.localImportLoading = true;
      try {
        const resp = await fetch('/api/local-agents/categories');
        if (!resp.ok) { this.showError('加载本地分类失败'); return; }
        const data = await resp.json();
        this.localImportCategories = (data.categories || []).map(name => ({ name }));
      } catch (e) { this.showError('加载本地分类时网络错误'); }
      finally { this.localImportLoading = false; }
    },

    closeLocalImportDialog() {
      this.showLocalImportDialog = false;
      document.body.style.overflow = '';
      if (this._localImportPrevFocus) {
        this._localImportPrevFocus.focus();
        this._localImportPrevFocus = null;
      }
    },

    async selectLocalCategory(category) {
      this.localImportSelectedCategory = category;
      this.localImportAgents = [];
      this.localImportSelectedAgents = {};
      this.localImportLoading = true;
      try {
        const resp = await fetch('/api/local-agents/' + encodeURIComponent(category));
        if (!resp.ok) { this.showError('加载 ' + category + ' 分类的 Agent 失败'); return; }
        const data = await resp.json();
        this.localImportAgents = (data.agents || []).map(a => ({
          name: a.name,
          path: a.path,
          filePath: a.filePath,
        }));
      } catch (e) { this.showError('加载 Agent 时网络错误'); }
      finally { this.localImportLoading = false; }
    },

    async importFromLocalAgents() {
      const selected = Object.entries(this.localImportSelectedAgents)
        .filter(([_, v]) => v)
        .map(([name]) => this.localImportAgents.find(a => a.name === name))
        .filter(Boolean);
      if (selected.length === 0) return;

      const category = this.localImportSelectedCategory;
      const converted = selected.map(agent => ({
        agent,
        ...this.convertAgencyAgentToPrompt(agent.name, '', category),
      }));
      const seen = new Set();
      const deduped = [];
      for (const item of converted) {
        if (seen.has(item.name)) continue;
        seen.add(item.name);
        deduped.push(item);
      }

      const existingCustom = this.systemPrompts.filter(p => p.source === 'custom').map(p => p.name);
      const willOverwrite = deduped.filter(d => existingCustom.includes(d.name)).map(d => d.name);
      if (willOverwrite.length > 0) {
        if (!confirm('以下提示词已存在，将被覆盖：\n\n' + willOverwrite.join(', ') + '\n\n确定继续？')) return;
      }

      this.localImportProgress = '正在导入 0/' + deduped.length + '...';
      let imported = 0;
      const errors = [];

      for (const item of deduped) {
        try {
          const resp = await fetch('/api/local-agents/' + encodeURIComponent(this.localImportSelectedCategory) + '/' + encodeURIComponent(item.agent.name + '.md'));
          if (!resp.ok) { errors.push(item.agent.name); continue; }
          const rawContent = await resp.text();
          const result = this.convertAgencyAgentToPrompt(item.agent.name, rawContent, this.localImportSelectedCategory);

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
        this.localImportProgress = '正在导入 ' + imported + '/' + deduped.length + '...';
      }

      this.localImportProgress = null;
      this.closeLocalImportDialog();
      if (errors.length > 0) {
        this.showError('已导入 ' + imported + ' 个，失败：' + errors.join(', '));
      } else {
        this.showSuccess('已导入 ' + imported + ' 个系统提示词');
      }
      await this.loadSystemPrompts();
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
     * Agent 类别汉化映射表（分类名称）
     */
    AGENT_CATEGORY_ZH: {
      // 分类名称翻译
      'design': '设计',
      'paid-media': '付费媒体',
      'sales': '销售',
      'spatial-computing': '空间计算',
      'project-management': '项目管理',
      'specialized': '专业领域',
      'product': '产品',
      'academic': '学术',
      'testing': '测试',
      'support': '支持',
      'hr': '人力资源',
      'marketing': '市场营销',
      'finance': '财务',
      'supply-chain': '供应链',
      'game-development': '游戏开发',
      'legal': '法务',
      'engineering': '工程',
      'strategy': '战略',
      // 职位类型翻译（用于 Agent 名称翻译）
      'product-manager': '产品经理',
      'software-engineer': '软件工程师',
      'designer': '设计师',
      'data-scientist': '数据科学家',
      'devops': '运维工程师',
      'security': '安全专家',
      'qa': '测试工程师',
      'marketing': '市场营销',
      'sales': '销售',
      'support': '客户支持',
      'hr': '人力资源',
      'finance': '财务',
      'legal': '法务',
      'operations': '运营',
      'consultant': '顾问',
      'researcher': '研究员',
      'writer': '作家',
      'editor': '编辑',
      'translator': '翻译',
      'coach': '教练',
      'therapist': '治疗师',
      'doctor': '医生',
      'lawyer': '律师',
      'accountant': '会计师',
      'architect': '建筑师',
      'engineer': '工程师',
      'scientist': '科学家',
      'teacher': '教师',
      'student': '学生',
      'artist': '艺术家',
      'musician': '音乐家',
      'photographer': '摄影师',
      'videographer': '视频制作人',
      'gamer': '游戏玩家',
      'streamer': '主播',
      'influencer': '网红',
      'entrepreneur': '企业家',
      'manager': '经理',
      'executive': '高管',
      'director': '总监',
      'vp': '副总裁',
      'ceo': '首席执行官',
      'cto': '首席技术官',
      'cfo': '首席财务官',
      'coo': '首席运营官',
      'cmo': '首席营销官',
    },

    /**
     * 翻译 Agent 名称（将连字符分隔的英文转换为中文）
     */
    translateAgentName(enName, category) {
      // 常见的 agent 名称模式映射
      const NAME_PATTERNS_ZH = {
        'senior': '高级',
        'lead': '首席',
        'principal': '资深',
        'staff': '专家',
        'junior': '初级',
        'assistant': '助理',
        'specialist': '专员',
        'expert': '专家',
        'consultant': '顾问',
        'analyst': '分析师',
        'strategist': '策略师',
        'coordinator': '协调员',
        'automation': '自动化',
        'ai': 'AI',
        'ml': '机器学习',
        'data': '数据',
        'growth': '增长',
        'performance': '绩效',
        'content': '内容',
        'social': '社交',
        'seo': 'SEO',
        'email': '邮件',
        'paid': '付费',
        'organic': '自然',
        'conversion': '转化',
        'retention': '留存',
        'engagement': '互动',
        'community': '社区',
        'brand': '品牌',
        'product': '产品',
        'project': '项目',
        'program': '计划',
        'portfolio': '组合',
        'risk': '风险',
        'compliance': '合规',
        'audit': '审计',
        'tax': '税务',
        'payroll': '薪酬',
        'recruitment': '招聘',
        'training': '培训',
        'learning': '学习',
        'development': '开发',
        'research': '研究',
        'innovation': '创新',
        'design': '设计',
        'ux': '用户体验',
        'ui': '界面',
        'frontend': '前端',
        'backend': '后端',
        'fullstack': '全栈',
        'devops': '运维',
        'sre': '站点可靠性',
        'security': '安全',
        'qa': '测试',
        'testing': '测试',
        'automation-engineer': '自动化工程师',
        'test': '测试',
        'bug': '缺陷',
        'feature': '功能',
        'release': '发布',
        'deployment': '部署',
        'infrastructure': '基础设施',
        'cloud': '云',
        'platform': '平台',
        'api': 'API',
        'integration': '集成',
        'migration': '迁移',
        'optimization': '优化',
        'performance-engineer': '性能工程师',
        'scalability': '扩展性',
        'reliability': '可靠性',
        'monitoring': '监控',
        'observability': '可观测性',
        'analytics': '分析',
        'business': '业务',
        'system': '系统',
        'network': '网络',
        'database': '数据库',
        'db': '数据库',
        'data-engineer': '数据工程师',
        'ml-engineer': '机器学习工程师',
        'ai-engineer': 'AI 工程师',
        'research-scientist': '研究科学家',
        'applied': '应用',
        'computer-vision': '计算机视觉',
        'nlp': '自然语言处理',
        'speech': '语音',
        'robotics': '机器人',
        'embedded': '嵌入式',
        'iot': '物联网',
        'mobile': '移动',
        'ios': 'iOS',
        'android': 'Android',
        'web': 'Web',
        'desktop': '桌面',
        'game': '游戏',
        'graphics': '图形',
        'multimedia': '多媒体',
        'audio': '音频',
        'video': '视频',
        'image': '图像',
        'document': '文档',
        'knowledge': '知识',
        'information': '信息',
        'content-strategist': '内容策略师',
        'technical-writer': '技术文档工程师',
        'documentation': '文档',
        'localization': '本地化',
        'internationalization': '国际化',
        'accessibility': '无障碍',
        'usability': '可用性',
        'user-research': '用户研究',
        'user-interface': '用户界面',
        'interaction': '交互',
        'visual': '视觉',
        'motion': '动效',
        '3d': '3D',
        'ar': '增强现实',
        'vr': '虚拟现实',
        'xr': '扩展现实',
        'metaverse': '元宇宙',
        'blockchain': '区块链',
        'crypto': '加密货币',
        'defi': '去中心化金融',
        'nft': 'NFT',
        'web3': 'Web3',
        'smart-contract': '智能合约',
        'protocol': '协议',
        'consensus': '共识',
        'cryptography': '密码学',
        'privacy': '隐私',
        'identity': '身份',
        'access': '访问',
        'authentication': '认证',
        'authorization': '授权',
        'encryption': '加密',
        'decryption': '解密',
        'signing': '签名',
        'verification': '验证',
        'validation': '校验',
        'testing-automation': '测试自动化',
        'quality': '质量',
        'assurance': '保证',
        'control': '控制',
        'management': '管理',
        'governance': '治理',
        'strategy': '战略',
        'planning': '规划',
        'execution': '执行',
        'delivery': '交付',
        'shipping': '交付',
        'logistics': '物流',
        'supply': '供应链',
        'chain': '链',
        'procurement': '采购',
        'sourcing': '寻源',
        'vendor': '供应商',
        'supplier': '供应商',
        'customer': '客户',
        'client': '客户',
        'partner': '合作伙伴',
        'alliance': '联盟',
        'ecosystem': '生态',
        'marketplace': '市场',
        'platform-strategist': '平台策略师',
        'ecosystem-manager': '生态经理',
        // 常见职位后缀
        'manager': '经理',
        'engineer': '工程师',
        'scientist': '科学家',
        'designer': '设计师',
        'developer': '开发者',
        'architect': '架构师',
        'director': '总监',
        'executive': '高管',
        'officer': '官',
        'head': '负责人',
        'chief': '首席',
        'vp': '副总裁',
        'president': '总裁',
        // 常见专业术语
        'feedback': '反馈',
        'synthesizer': '合成器',
        'synthesis': '综合分析',
        'analyzer': '分析师',
        'analysis': '分析',
        'specialist': '专家',
        'operator': '运营师',
        'consultant': '顾问',
        'advisor': '顾问',
        'coach': '教练',
        'mentor': '导师',
        'facilitator': '引导师',
        'advocate': '倡导者',
        'evangelist': '布道师',
        'ninja': '忍者',
        'guru': '大师',
        'rockstar': '明星',
        'wizard': '奇才',
        'champion': ' champion',
        'lead': '主管',
        'principal': '首席',
        'staff': '资深',
        'senior': '高级',
        'junior': '初级',
        'intern': '实习生',
        'apprentice': '学徒',
        'trainee': '培训生',
        'assistant': '助理',
        'associate': '专员',
        'coordinator': '协调员',
        'administrator': '管理员',
        'admin': '管理员',
        'support': '支持',
        'service': '服务',
        'success': '成功',
        'experience': '体验',
        'journey': '旅程',
        'lifecycle': '生命周期',
        'operations': '运营',
        'ops': '运营',
        'finance': '财务',
        'sales': '销售',
        'marketing': '市场',
        'hr': '人力资源',
        'legal': '法务',
        'it': '信息技术',
        'cs': '客户服务',
        'r&d': '研发',
        'rd': '研发',
        // 产品管理术语
        'sprint': '冲刺',
        'prioritizer': '优先级排序',
        'trend': '趋势',
        'researcher': '研究员',
        'nudge': '助推',
        'behavioral': '行为',
        'insight': '洞察',
        'strategy': '战略',
        'vision': '愿景',
        'roadmap': '路线图',
        'backlog': '待办',
        'epic': '史诗',
        'story': '故事',
        'task': '任务',
        'bug': '缺陷',
        'feature': '功能',
        'release': '发布',
        'iteration': '迭代',
        'kanban': '看板',
        'scrum': 'Scrum',
        'agile': '敏捷',
        'waterfall': '瀑布',
        'lean': '精益',
        'startup': '创业',
        'enterprise': '企业',
        'saas': 'SaaS',
        'b2b': 'B2B',
        'b2c': 'B2C',
        'growth': '增长',
        'retention': '留存',
        'acquisition': '获客',
        'activation': '激活',
        'revenue': '收入',
        'referral': '推荐',
        'kpi': 'KPI',
        'okr': 'OKR',
        'metric': '指标',
        'dashboard': '仪表盘',
        'experiment': '实验',
        'ab-test': 'A/B 测试',
        'hypothesis': '假设',
        'validation': '验证',
        'discovery': '发现',
        'delivery': '交付',
        'outcome': '成果',
        'output': '产出',
        'impact': '影响力',
        'value': '价值',
        'stakeholder': '干系人',
        'customer': '客户',
        'user': '用户',
        'persona': '角色',
        'journey-map': '旅程地图',
        'wireframe': '线框图',
        'prototype': '原型',
        'mockup': '模型',
        'mvp': 'MVP',
        'pmf': 'PMF',
        'churn': '流失',
        'ltv': 'LTV',
        'cac': 'CAC',
        'arr': 'ARR',
        'mrr': 'MRR',
        // 其他常见术语
        'engine': '引擎',
        'tool': '工具',
        'tools': '工具',
        'kit': '工具包',
        'box': '盒子',
        'lab': '实验室',
        'studio': '工作室',
        'hub': '中心',
        'center': '中心',
        'base': '基地',
        'station': '站',
        'port': '端口',
        'gate': '门',
        'way': '方式',
        'path': '路径',
        'route': '路线',
        'guide': '指南',
        'helper': '助手',
        'bot': '机器人',
        'agent': '代理',
        'copilot': '副驾',
        'partner': '伙伴',
        'buddy': '伙伴',
        'friend': '朋友',
        'master': '大师',
        'expert': '专家',
        'pro': '专业',
        'plus': '增强',
        'max': '极限',
        'ultra': '超级',
        'lite': '轻量',
        'mini': '迷你',
        'micro': '微型',
        'nano': '纳米',
        'auto': '自动',
        'smart': '智能',
        'rapid': '快速',
        'fast': '快速',
        'quick': '快速',
        'instant': '即时',
        'realtime': '实时',
        'live': '实时',
        'dynamic': '动态',
        'static': '静态',
        'active': '主动',
        'passive': '被动',
        'proactive': '主动',
        'reactive': '响应',
      };

      // 获取类别的中文名称
      const categoryZh = this.AGENT_CATEGORY_ZH[category] || '';

      // 将连字符或空格分隔的名称拆分为单词
      const parts = enName.split(/[-\s]+/);
      const translatedParts = [];

      for (const part of parts) {
        // 转换为小写进行匹配（不区分大小写）
        const partLower = part.toLowerCase();

        // 完全匹配优先
        if (NAME_PATTERNS_ZH[partLower]) {
          translatedParts.push(NAME_PATTERNS_ZH[partLower]);
        }
        // 尝试部分匹配（如 engineer -> 工程师）
        else if (partLower.endsWith('engineer') && partLower !== 'engineer') {
          const prefix = partLower.slice(0, -8);
          const prefixZh = NAME_PATTERNS_ZH[prefix] || prefix;
          translatedParts.push(prefixZh + '工程师');
        }
        else if (partLower.endsWith('manager') && partLower !== 'manager') {
          const prefix = partLower.slice(0, -7);
          const prefixZh = NAME_PATTERNS_ZH[prefix] || prefix;
          translatedParts.push(prefixZh + '经理');
        }
        else if (partLower.endsWith('specialist') && partLower !== 'specialist') {
          const prefix = partLower.slice(0, -10);
          const prefixZh = NAME_PATTERNS_ZH[prefix] || prefix;
          translatedParts.push(prefixZh + '专员');
        }
        else {
          // 无法翻译的保留原文
          translatedParts.push(part);
        }
      }

      // 组合翻译结果：类别 + 名称
      if (categoryZh && translatedParts.length > 0) {
        // 如果名称中已包含类别含义，避免重复
        const nameZh = translatedParts.join('');
        if (nameZh.includes(categoryZh)) {
          return nameZh;
        }
        return categoryZh + nameZh;
      }

      return translatedParts.join('') || enName;
    },

    /**
     * 将 agency-agents markdown 文件转换为 sns-workflow 系统提示词格式。
     * @param {string} filename - 文件名（不含 .md）
     * @param {string} rawContent - 原始文件内容
     * @param {string} category - 所属类别（用于汉化）
     */
    convertAgencyAgentToPrompt(filename, rawContent, category = '') {
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

      // 汉化名称（如果有类别信息）
      const chineseName = category ? this.translateAgentName(name, category) : name;

      // 使用中文描述：优先使用汉化后的名称生成描述
      const safeDescription = chineseName + ' 代理，从 agency-agents 画廊导入';
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

      return { name: safeName, content, chineseName };
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
        ...this.convertAgencyAgentToPrompt(agent.name, '', this.importSelectedCategory),
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
          const result = this.convertAgencyAgentToPrompt(item.agent.name, rawContent, this.importSelectedCategory);

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
