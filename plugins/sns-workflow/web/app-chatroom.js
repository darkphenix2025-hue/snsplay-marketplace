/**
 * 辩论聊天室配置混入 - 工作流管理配置门户。
 * 处理参与者管理和 PK 阶段配置。
 */
function chatroomMixin() {
  return {
    chatroomConfig: null,

    async loadChatroomConfig() {
      this.loading.chatroom = true;
      try {
        const [configResp, presetsResp] = await Promise.all([
          fetch('/api/chatroom-config'),
          this.presets && Object.keys(this.presets).length > 0 ? Promise.resolve(null) : fetch('/api/presets'),
          this.systemPrompts.length > 0 ? Promise.resolve() : this.loadSystemPrompts(),
        ]);
        if (!configResp.ok) { const err = await configResp.json().catch(() => ({})); this.showError(err.error?.message || '加载聊天室配置失败'); return; }
        const data = await configResp.json();
        if (presetsResp) { const pd = await presetsResp.json(); this.presets = pd.presets || {}; }

        const participantPresets = new Set((data.config.participants || []).map(p => p.preset).filter(Boolean));
        await Promise.allSettled([...participantPresets].map(p => this._fetchModelOptions(p)));
        this.chatroomConfig = data.config;
      } catch (e) { this.showError('加载聊天室配置时网络错误'); }
      finally { this.loading.chatroom = false; }
    },

    async saveChatroomConfig() {
      this.saving.chatroom = true;
      try {
        const payload = { participants: this.chatroomConfig.participants, max_rounds: this.chatroomConfig.max_rounds };
        const resp = await fetch('/api/chatroom-config', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        if (!resp.ok) { const err = await resp.json().catch(() => ({})); this.showError(err.error?.message || '保存失败'); return; }
        this.showSuccess('聊天室配置已保存');
      } catch (e) { this.showError('网络错误'); }
      finally { this.saving.chatroom = false; }
    },

    async resetChatroomToDefault() {
      if (!confirm('确定要将聊天室配置重置为出厂默认值吗？')) return;
      try {
        const resp = await fetch('/api/chatroom-config/defaults');
        if (!resp.ok) { this.showError('加载默认配置失败'); return; }
        const data = await resp.json();
        this.chatroomConfig = data.config;
        this.showSuccess('聊天室配置已重置为出厂默认');
      } catch (e) { this.showError('网络错误'); }
    },

    addParticipant() {
      if (!this.chatroomConfig || this.chatroomConfig.participants.length >= 10) return;
      const firstPreset = Object.keys(this.presets)[0] || '';
      this.chatroomConfig.participants.push({ system_prompt: '', preset: firstPreset, model: '' });
      if (firstPreset) this._fetchModelOptions(firstPreset);
    },

    removeParticipant(index) { if (this.chatroomConfig) this.chatroomConfig.participants.splice(index, 1); },

    async onParticipantProviderChange(index) {
      if (!this.chatroomConfig) return;
      const participant = this.chatroomConfig.participants[index]; if (!participant) return;
      participant.model = ''; await this._fetchModelOptions(participant.preset);
    },
  };
}
