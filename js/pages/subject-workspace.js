// ===== 考公笔试复盘系统 - 科目专属复盘工作台 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Workspace = {
  state: {
    subject: null,
    activeTab: 0,
    reviewTasks: [],
    notes: [],
    errors: []
  },

  async render(params) {
    const container = document.getElementById('page-workspace');
    container.innerHTML = '';

    // 从 URL 参数获取科目
    this.state.subject = params.subject || App.Constants.SUBJECTS[0].name;
    this.state.activeTab = parseInt(params.tab) || 0;

    // 返回栏
    const header = document.createElement('div');
    header.className = 'page-header';
    header.style.padding = 'var(--spacing-sm) var(--page-padding)';

    const backBtn = document.createElement('button');
    backBtn.className = 'page-header__back';
    backBtn.innerHTML = '‹ 返回';
    backBtn.addEventListener('click', () => App.Router.navigate('home'));
    header.appendChild(backBtn);

    // 科目切换器
    const subjectSelector = document.createElement('select');
    subjectSelector.className = 'form-select';
    subjectSelector.style.cssText = 'flex:1;margin:0 var(--spacing-sm);font-weight:600;';
    App.Constants.SUBJECTS.forEach(s => {
      subjectSelector.innerHTML += `<option value="${s.name}" ${this.state.subject === s.name ? 'selected' : ''}>${s.icon} ${s.name}</option>`;
    });
    subjectSelector.addEventListener('change', () => {
      this.state.subject = subjectSelector.value;
      this.loadAndRenderTabs();
    });
    header.appendChild(subjectSelector);

    container.appendChild(header);

    // Tab 栏
    const tabBar = App.Components.stickyTabs([
      { label: '复盘记录' },
      { label: '笔记框架' },
      { label: '知识点分类' },
      { label: '错题整理' }
    ], this.state.activeTab, (idx) => {
      this.state.activeTab = idx;
      this.renderTabContent();
    });
    tabBar.style.top = 'calc(var(--safe-top) + 44px)';
    container.appendChild(tabBar);

    // Tab 内容区
    const tabContent = document.createElement('div');
    tabContent.id = 'workspace-tab-content';
    container.appendChild(tabContent);

    // 加载数据
    await this.loadData();
    this.renderTabContent();
  },

  async loadData() {
    const subject = this.state.subject;
    [this.state.reviewTasks, this.state.notes, this.state.errors] = await Promise.all([
      App.DB.getReviewTasks(subject),
      App.DB.getNotes({ subject }),
      App.DB.getErrors({ subject })
    ]);
  },

  async loadAndRenderTabs() {
    await this.loadData();
    this.renderTabContent();
  },

  renderTabContent() {
    const container = document.getElementById('workspace-tab-content');
    if (!container) return;
    container.innerHTML = '';

    switch (this.state.activeTab) {
      case 0: this.renderReviewTab(container); break;
      case 1: this.renderNotesTab(container); break;
      case 2: this.renderKnowledgeTab(container); break;
      case 3: this.renderErrorsTab(container); break;
    }
  },

  // ===== Tab 1: 复盘记录 =====
  renderReviewTab(container) {
    const subject = this.state.subject;
    const tasks = this.state.reviewTasks;

    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'padding:var(--spacing-md) var(--page-padding);';

    if (tasks.length === 0) {
      // 检查是否有默认任务需要初始化
      const defaults = App.Constants.DEFAULT_REVIEW_TASKS[subject] || [];
      const initMsg = document.createElement('div');
      initMsg.style.cssText = 'margin-bottom:var(--spacing-md);text-align:center;';
      initMsg.innerHTML = `
        <div style="font-size:var(--font-sm);color:var(--text-tertiary);margin-bottom:var(--spacing-sm);">
          还没有复盘任务
        </div>
        ${defaults.length > 0 ? `
          <button class="btn btn--outline btn--sm" id="init-default-tasks">加载默认任务</button>
        ` : ''}
        <button class="btn btn--primary btn--sm" style="margin-left:8px;" id="add-custom-task">自定义任务</button>
      `;
      wrapper.appendChild(initMsg);

      if (defaults.length > 0) {
        wrapper.querySelector('#init-default-tasks').addEventListener('click', async () => {
          for (const taskText of defaults) {
            await App.DB.addReviewTask({
              subject,
              taskText,
              reviewNote: '',
              createdAt: new Date().toISOString()
            });
          }
          App.Components.toast('已加载默认任务', 'success');
          this.loadAndRenderTabs();
        });
      }

      wrapper.querySelector('#add-custom-task').addEventListener('click', () => {
        this.showAddTaskDialog(wrapper, subject);
      });
    } else {
      tasks.forEach((task, idx) => {
        const card = document.createElement('div');
        card.className = 'card';
        card.style.margin = '0 0 var(--spacing-sm) 0';

        card.innerHTML = `
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">
            <div style="display:flex;align-items:center;gap:8px;">
              <span style="font-size:var(--font-xs);color:var(--text-tertiary);">${idx + 1}</span>
              <span style="font-weight:600;">${task.taskText}</span>
            </div>
            <button class="btn--text" style="font-size:var(--font-xs);" id="del-task-${task.id}">✕</button>
          </div>
          <textarea class="form-textarea" placeholder="复盘笔记..." style="min-height:60px;margin-top:6px;"
            id="note-${task.id}">${task.reviewNote || ''}</textarea>
        `;

        // 删除
        card.querySelector('#del-task-' + task.id).addEventListener('click', async (e) => {
          e.stopPropagation();
          const confirmed = await App.Components.confirm('删除任务', '确定删除该复盘任务？', '删除', '取消', true);
          if (confirmed) {
            await App.DB.remove('subject_reviews', task.id);
            App.Components.toast('已删除', 'success');
            this.loadAndRenderTabs();
          }
        });

        // 自动保存笔记
        const textarea = card.querySelector('#note-' + task.id);
        textarea.addEventListener('input', App.Utils.debounce(async () => {
          task.reviewNote = textarea.value;
          await App.DB.updateReviewTask(task);
        }, 3000));

        wrapper.appendChild(card);
      });

      // 添加任务按钮
      const addBtn = document.createElement('button');
      addBtn.className = 'btn btn--outline btn--full';
      addBtn.style.marginTop = 'var(--spacing-md)';
      addBtn.textContent = '+ 添加任务';
      addBtn.addEventListener('click', () => this.showAddTaskDialog(wrapper, subject));
      wrapper.appendChild(addBtn);
    }

    container.appendChild(wrapper);
  },

  showAddTaskDialog(wrapper, subject) {
    const inputRow = document.createElement('div');
    inputRow.style.cssText = 'display:flex;gap:var(--spacing-sm);margin-bottom:var(--spacing-md);padding:0 var(--page-padding);';
    const input = document.createElement('input');
    input.className = 'form-input';
    input.placeholder = '输入复盘任务...';
    input.style.flex = '1';
    const addBtn = document.createElement('button');
    addBtn.className = 'btn btn--primary btn--sm';
    addBtn.textContent = '添加';
    addBtn.addEventListener('click', async () => {
      const text = input.value.trim();
      if (!text) { App.Components.toast('请输入任务内容', 'error'); return; }
      await App.DB.addReviewTask({
        subject,
        taskText: text,
        reviewNote: '',
        createdAt: new Date().toISOString()
      });
      input.value = '';
      App.Components.toast('已添加', 'success');
      this.loadAndRenderTabs();
    });
    inputRow.appendChild(input);
    inputRow.appendChild(addBtn);
    wrapper.insertBefore(inputRow, wrapper.firstChild);
  },

  // ===== Tab 2: 笔记框架 =====
  renderNotesTab(container) {
    const subject = this.state.subject;
    const notes = this.state.notes;

    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'padding:var(--spacing-md) var(--page-padding);';

    if (notes.length === 0) {
      wrapper.appendChild(App.Components.emptyState(
        '📝',
        '暂无笔记',
        '点击下方按钮开始记录',
        '新建笔记',
        () => App.Router.navigate('note-form?subject=' + encodeURIComponent(subject))
      ));
    } else {
      // 按模块-考点组织
      const treeData = {};
      notes.forEach(note => {
        const mod = note.module || '未分类';
        const kp = note.knowledgePoint || '未分类';
        if (!treeData[mod]) treeData[mod] = {};
        if (!treeData[mod][kp]) treeData[mod][kp] = [];
        treeData[mod][kp].push(note);
      });

      const treeContainer = document.createElement('div');
      treeContainer.className = 'note-tree';

      Object.entries(treeData).forEach(([modName, kps]) => {
        const kpNodes = [];
        Object.entries(kps).forEach(([kpName, kpNotes]) => {
          const noteItems = kpNotes.map(note =>
            App.Components.noteItem(note, (n) => App.Router.navigate('note-detail?id=' + n.id))
          );
          kpNodes.push(App.Components.noteTreeNode(kpName, '📌', kpNotes.length, true, noteItems));
        });
        treeContainer.appendChild(App.Components.noteTreeNode(
          modName, '📁',
          Object.values(kps).reduce((sum, arr) => sum + arr.length, 0),
          true,
          kpNodes
        ));
      });

      wrapper.appendChild(treeContainer);
    }

    container.appendChild(wrapper);
  },

  // ===== Tab 3: 知识点分类 =====
  renderKnowledgeTab(container) {
    const subject = this.state.subject;
    const errors = this.state.errors;
    const notes = this.state.notes;
    const modules = App.Constants.getModules(subject);

    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'padding:var(--spacing-md) var(--page-padding);';

    modules.forEach(modName => {
      const presetKps = App.Tags.getKnowledgePoints(modName);
      const usedCustom = new Set();
      errors.filter(e => e.module === modName).forEach(e => (e.knowledgePoints || []).forEach(kp => usedCustom.add(kp)));
      notes.filter(n => n.module === modName && n.knowledgePoint).forEach(n => usedCustom.add(n.knowledgePoint));
      const kps = Array.from(new Set([...presetKps, ...usedCustom]));

      const modCard = document.createElement('div');
      modCard.className = 'card';
      modCard.style.margin = '0 0 var(--spacing-md) 0';

      let kpListHtml = '';
      kps.forEach(kpName => {
        const kpErrors = errors.filter(e =>
          e.module === modName && (e.knowledgePoints || []).includes(kpName)
        );
        const kpNotes = notes.filter(n =>
          n.module === modName && n.knowledgePoint === kpName
        );
        const totalItems = kpErrors.length + kpNotes.length;
        const unmastered = kpErrors.filter(e => e.status === '未掌握').length;
        const masteryClass = totalItems === 0 ? 'mastery-dot--none' :
          (unmastered === 0 ? 'mastery-dot--mastered' : 'mastery-dot--familiar');

        kpListHtml += `
          <div style="display:flex;align-items:center;justify-content:space-between;padding:6px 0;font-size:var(--font-sm);border-bottom:1px solid var(--divider-color);">
            <span>
              <span class="mastery-dot ${masteryClass}"></span>
              ${kpName}
            </span>
            <span style="color:var(--text-tertiary);font-size:var(--font-xs);">
              错题${kpErrors.length} · 笔记${kpNotes.length}
            </span>
          </div>
        `;
      });

      modCard.innerHTML = `
        <div style="font-weight:600;font-size:var(--font-md);margin-bottom:8px;display:flex;align-items:center;gap:8px;">
          <span>📁</span> ${modName}
          <span style="font-weight:400;font-size:var(--font-xs);color:var(--text-tertiary);">${kps.length}个考点</span>
        </div>
        ${kpListHtml}
      `;

      wrapper.appendChild(modCard);
    });

    // 图例
    const legend = document.createElement('div');
    legend.style.cssText = 'display:flex;gap:var(--spacing-md);justify-content:center;font-size:var(--font-xs);color:var(--text-tertiary);margin-top:var(--spacing-sm);';
    legend.innerHTML = `
      <span><span class="mastery-dot mastery-dot--none"></span> 未学习</span>
      <span><span class="mastery-dot mastery-dot--familiar"></span> 有未掌握</span>
      <span><span class="mastery-dot mastery-dot--mastered"></span> 已掌握</span>
    `;
    wrapper.appendChild(legend);

    container.appendChild(wrapper);
  },

  // ===== Tab 4: 错题整理 =====
  renderErrorsTab(container) {
    const errors = this.state.errors;

    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'padding:var(--spacing-md) var(--page-padding);';

    if (errors.length === 0) {
      wrapper.appendChild(App.Components.emptyState(
        '📋',
        '该科目暂无错题',
        '做完题后记得把错题记录到错题本',
        '添加错题',
        () => App.Router.navigate('error-form?subject=' + encodeURIComponent(this.state.subject))
      ));
    } else {
      // 统计
      const unmastered = errors.filter(e => e.status === '未掌握').length;
      const mastered = errors.filter(e => e.status === '已掌握').length;

      const statsBar = document.createElement('div');
      statsBar.className = 'stats-row';
      statsBar.style.padding = '0';
      statsBar.style.marginBottom = 'var(--spacing-md)';
      statsBar.innerHTML = `
        <div class="stat-item"><div class="stat-item__value">${errors.length}</div><div class="stat-item__label">总错题</div></div>
        <div class="stat-item"><div class="stat-item__value stat-item__value--danger">${unmastered}</div><div class="stat-item__label">待掌握</div></div>
        <div class="stat-item"><div class="stat-item__value">${mastered}</div><div class="stat-item__label">已掌握</div></div>
        <div class="stat-item"><div class="stat-item__value">${errors.length > 0 ? Math.round(mastered/errors.length*100) : 0}%</div><div class="stat-item__label">掌握率</div></div>
      `;
      wrapper.appendChild(statsBar);

      errors.forEach(error => {
        const card = App.Components.errorCard(
          error,
          async (err) => {
            err.status = '已掌握';
            err.lastReviewDate = new Date().toISOString();
            err.reviewCount = (err.reviewCount || 0) + 1;
            await App.DB.updateError(err);
            App.Components.toast('已标记为掌握', 'success');
            this.loadAndRenderTabs();
          },
          async (err) => {
            const confirmed = await App.Components.confirm('删除错题', '确定删除？', '删除', '取消', true);
            if (confirmed) {
              await App.DB.remove('errors', err.id);
              App.Components.toast('已删除', 'success');
              this.loadAndRenderTabs();
            }
          },
          () => App.Router.navigate('error-detail?id=' + error.id)
        );
        wrapper.appendChild(card);
      });
    }

    container.appendChild(wrapper);
  }
};
