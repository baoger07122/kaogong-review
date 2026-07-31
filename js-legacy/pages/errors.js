// ===== 考公笔试复盘系统 - 错题本页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Errors = {
  state: {
    subject: null,
    module: null,
    knowledgePoint: null,
    errorCause: null,
    status: null,
    search: '',
    allErrors: []
  },

  async render(params) {
    const container = document.getElementById('page-errors');
    container.innerHTML = '';

    // 左侧边栏（科目）+ 主内容区
    const layout = document.createElement('div');
    layout.className = 'with-sidebar';

    const sidebar = document.createElement('div');
    sidebar.className = 'sidebar';
    sidebar.id = 'error-sidebar';
    layout.appendChild(sidebar);

    const main = document.createElement('div');
    main.className = 'page-main';

    // 页面标题
    const header = document.createElement('div');
    header.className = 'page-header';
    header.innerHTML = `
      <div class="page-header__title">错题本</div>
      <div class="page-header__right" id="error-count">共 0 道</div>
    `;
    main.appendChild(header);

    // 搜索栏
    const searchBar = document.createElement('div');
    searchBar.className = 'search-bar';
    searchBar.innerHTML = `
      <span class="search-bar__icon">🔍</span>
      <input type="text" placeholder="搜索错题 / 知识点" id="error-search">
    `;
    main.appendChild(searchBar);

    searchBar.querySelector('input').addEventListener('input', App.Utils.debounce((e) => {
      this.state.search = e.target.value;
      this.refreshAll();
    }, 300));

    // 统计卡片区
    const statsRow = document.createElement('div');
    statsRow.className = 'stats-row';
    statsRow.id = 'error-stats';
    main.appendChild(statsRow);

    // 筛选区容器
    const filterArea = document.createElement('div');
    filterArea.id = 'error-filter-area';
    main.appendChild(filterArea);

    // 列表区
    const listArea = document.createElement('div');
    listArea.id = 'error-list';
    main.appendChild(listArea);

    layout.appendChild(main);
    container.appendChild(layout);

    // 加载数据并渲染
    await this.loadData();
    await this.renderSubjectGrid(sidebar);
    this.renderStats(statsRow);
    this.renderFilters(filterArea);
    await this.renderList(listArea);
  },

  async loadData() {
    this.state.allErrors = await App.DB.getErrors();
  },

  // 合并「本模块库 + 数据中已用值」得到可筛选的考点列表
  getDistinctKnowledgePoints(module) {
    const used = new Set();
    this.state.allErrors.forEach(e => {
      if (e.module === module) (e.knowledgePoints || []).forEach(kp => used.add(kp));
    });
    const lib = App.Tags.getKnowledgePoints(module);
    return Array.from(new Set([...lib, ...used]));
  },

  // 合并「错因库 + 数据中已用值」得到可筛选的错因列表
  getDistinctErrorCauses() {
    const used = new Set();
    this.state.allErrors.forEach(e => { if (e.errorCause) used.add(e.errorCause); });
    const lib = App.Tags.getErrorCauses();
    return Array.from(new Set([...lib, ...used]));
  },

  // ===== 智能拆分：把「题干 + 选项」整段文字解析为 题干 与 A/B/C/D 选项 =====
  parseQuestion(raw) {
    const text = (raw || '').replace(/\r\n/g, '\n').trim();
    if (!text) return { question: '', options: [] };

    // 选项标记：支持 A. / A、 / A： / （A） / 同行排列 等多种格式
    const re = /(^|\n|\s|：|（|\()([A-Ha-h])[\.、。:：)）]\s*/g;
    const matches = [];
    let m;
    while ((m = re.exec(text)) !== null) {
      matches.push({
        index: m.index,
        end: m.index + m[0].length
      });
    }

    if (matches.length >= 2) {
      const question = text.slice(0, matches[0].index).trim();
      const options = [];
      for (let i = 0; i < matches.length; i++) {
        const start = matches[i].end;
        const end = (i + 1 < matches.length) ? matches[i + 1].index : text.length;
        options.push(text.slice(start, end).trim());
      }
      return { question, options };
    }

    // 无标记：按行拆分（首行为题干，其余为选项）
    const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
    if (lines.length >= 2) {
      return { question: lines[0], options: lines.slice(1) };
    }
    return { question: text, options: [] };
  },

  // ===== AI 智能拆分弹窗 =====
  openSmartSplit(formData, rebuild) {
    const container = document.getElementById('modal-container');
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML = `
      <div class="modal-dialog" style="max-width:92%;">
        <div class="modal-dialog__header">
          <div class="modal-dialog__title">🤖 AI 智能拆分</div>
        </div>
        <div class="modal-dialog__body">
          <div style="font-size:var(--font-xs);color:var(--text-tertiary);margin-bottom:8px;line-height:1.6;">
            粘贴「题干 + 选项」整段文字，自动拆分成题干与 A/B/C/D 选项（支持换行或同行排列）
          </div>
        </div>
      </div>
    `;
    const body = overlay.querySelector('.modal-dialog__body');
    const ta = document.createElement('textarea');
    ta.className = 'form-textarea';
    ta.style.minHeight = '170px';
    ta.style.textAlign = 'left';
    ta.placeholder = '例：\n某市进行人口普查……下列说法正确的是？\nA. 选项一内容\nB. 选项二内容\nC. 选项三内容\nD. 选项四内容';
    body.appendChild(ta);

    const actions = document.createElement('div');
    actions.className = 'modal-dialog__actions';
    const cancel = document.createElement('button');
    cancel.className = 'btn-cancel';
    cancel.textContent = '取消';
    const ok = document.createElement('button');
    ok.className = 'btn-confirm';
    ok.textContent = '识别拆分';
    actions.appendChild(cancel);
    actions.appendChild(ok);
    overlay.querySelector('.modal-dialog').appendChild(actions);

    cancel.addEventListener('click', () => overlay.remove());
    overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
    ok.addEventListener('click', () => {
      const parsed = this.parseQuestion(ta.value);
      if (!parsed.question.trim() && parsed.options.filter(o => o.trim()).length === 0) {
        App.Components.toast('未识别到内容', 'error');
        return;
      }
      formData.question = parsed.question.trim();
      formData.options = [
        parsed.options[0] || '', parsed.options[1] || '',
        parsed.options[2] || '', parsed.options[3] || ''
      ];
      overlay.remove();
      if (rebuild) rebuild();
      App.Components.toast('已拆分填入 ✓', 'success');
    });

    container.appendChild(overlay);
    setTimeout(() => ta.focus(), 50);
  },

  async renderSubjectGrid(container) {
    const errorCounts = {};
    App.Constants.SUBJECTS.forEach(s => {
      errorCounts[s.name] = this.state.allErrors.filter(e => e.subject === s.name).length;
    });

    container.innerHTML = '';

    // 「全部」项
    const allItem = document.createElement('div');
    allItem.className = 'sidebar__item' + (this.state.subject === null ? ' active' : '');
    allItem.innerHTML = `
      <span class="sidebar__item-icon">📚</span>
      <span class="sidebar__item-name">全部</span>
    `;
    allItem.addEventListener('click', () => {
      this.state.subject = null;
      this.state.module = null;
      this.state.knowledgePoint = null;
      this.refreshAll();
    });
    container.appendChild(allItem);

    // 各科目
    App.Constants.SUBJECTS.forEach(s => {
      const item = document.createElement('div');
      item.className = 'sidebar__item' + (this.state.subject === s.name ? ' active' : '');
      const count = errorCounts[s.name];
      item.innerHTML = `
        <span class="sidebar__item-icon">${s.icon}</span>
        <span class="sidebar__item-name">${s.name}</span>
        ${count > 0 ? `<span class="sidebar__item-count">${count}</span>` : ''}
      `;
      item.addEventListener('click', () => {
        this.state.subject = (this.state.subject === s.name) ? null : s.name;
        this.state.module = null;
        this.state.knowledgePoint = null;
        this.refreshAll();
      });
      container.appendChild(item);
    });
  },

  renderStats(container) {
    const subject = this.state.subject;
    let errors = this.state.allErrors;
    if (subject) errors = errors.filter(e => e.subject === subject);

    const total = errors.length;
    const unmastered = errors.filter(e => e.status === '未掌握').length;
    const mastered = errors.filter(e => e.status === '已掌握').length;
    const todayStr = new Date().toISOString().slice(0, 10);
    const weekNew = errors.filter(e => e.createdAt.slice(0, 10) >= todayStr.slice(0, 8) + String(Math.max(1, parseInt(todayStr.slice(8)) - 7)).padStart(2, '0')).length;
    const thisWeekNew = errors.filter(e => {
      const d = new Date(e.createdAt);
      const now = new Date();
      const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      return d >= weekAgo;
    }).length;

    container.innerHTML = `
      <div class="stat-item">
        <div class="stat-item__value">${total}</div>
        <div class="stat-item__label">总错题</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value stat-item__value--danger">${unmastered}</div>
        <div class="stat-item__label">待掌握</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${mastered}</div>
        <div class="stat-item__label">已掌握</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${thisWeekNew}</div>
        <div class="stat-item__label">本周新增</div>
      </div>
    `;
  },

  renderFilters(container) {
    container.innerHTML = '';
    if (!this.state.subject) return;

    // 模块筛选
    const modules = App.Constants.getModules(this.state.subject);
    const moduleBar = App.Components.filterTags(
      modules.map(m => ({ name: m })),
      this.state.module,
      (mod) => {
        this.state.module = (this.state.module === mod) ? null : mod;
        this.state.knowledgePoint = null;
        this.refreshAll();
      }
    );
    container.appendChild(moduleBar);

    // 考点筛选
    if (this.state.module) {
      const kps = this.getDistinctKnowledgePoints(this.state.module);
      const kpBar = App.Components.filterTags(
        kps.map(k => ({ name: k })),
        this.state.knowledgePoint,
        (kp) => {
          this.state.knowledgePoint = (this.state.knowledgePoint === kp) ? null : kp;
          this.refreshAll();
        }
      );
      container.appendChild(kpBar);
    }

    // 错因筛选
    const causes = this.getDistinctErrorCauses();
    const causeBar = App.Components.filterTags(
      causes.map(c => ({ name: c })),
      this.state.errorCause,
      (cause) => {
        this.state.errorCause = (this.state.errorCause === cause) ? null : cause;
        this.refreshAll();
      }
    );
    container.appendChild(causeBar);

    // 状态筛选
    const statusBar = App.Components.filterTags(
      ['未掌握', '已掌握'],
      this.state.status,
      (status) => {
        this.state.status = (this.state.status === status) ? null : status;
        this.refreshAll();
      }
    );
    container.appendChild(statusBar);
  },

  async renderList(container) {
    container.innerHTML = '';

    // 构建筛选条件
    const filters = {};
    if (this.state.subject) filters.subject = this.state.subject;
    if (this.state.module) filters.module = this.state.module;
    if (this.state.knowledgePoint) filters.knowledgePoint = this.state.knowledgePoint;
    if (this.state.errorCause) filters.errorCause = this.state.errorCause;
    if (this.state.status) filters.status = this.state.status;
    if (this.state.search) filters.search = this.state.search;

    const errors = await App.DB.getErrors(filters);

    // 更新标题计数
    const countEl = document.getElementById('error-count');
    if (countEl) countEl.textContent = '共 ' + errors.length + ' 道';

    if (errors.length === 0) {
      container.appendChild(App.Components.emptyState(
        '📋',
        '还没有错题',
        '复盘时记录的错题会自动收录到这里',
        '添加错题',
        () => App.Router.navigate('error-form')
      ));
      return;
    }

    errors.forEach(error => {
      const card = App.Components.errorCard(
        error,
        // 左滑-标记掌握
        async (err) => {
          err.status = '已掌握';
          err.lastReviewDate = new Date().toISOString();
          err.reviewCount = (err.reviewCount || 0) + 1;
          await App.DB.updateError(err);
          App.Components.toast('已标记为掌握', 'success');
          this.refreshAll();
        },
        // 左滑-删除
        async (err) => {
          const confirmed = await App.Components.confirm(
            '删除错题',
            '确定要删除这道错题吗？此操作不可撤销。',
            '删除', '取消', true
          );
          if (confirmed) {
            await App.DB.remove('errors', err.id);
            App.Components.toast('已删除', 'success');
            this.refreshAll();
          }
        },
        // 点击进入详情
        () => App.Router.navigate('error-detail?id=' + error.id)
      );
      container.appendChild(card);
    });
  },

  refreshAll() {
    const sidebar = document.getElementById('error-sidebar');
    const statsRow = document.getElementById('error-stats');
    const filterArea = document.getElementById('error-filter-area');
    const listArea = document.getElementById('error-list');

    if (sidebar) this.renderSubjectGrid(sidebar);
    if (statsRow) this.renderStats(statsRow);
    if (filterArea) this.renderFilters(filterArea);
    if (listArea) this.renderList(listArea);
  },

  // ===== 错题详情页 =====
  async renderDetail(params) {
    const container = document.getElementById('page-error-detail');
    container.innerHTML = '';

    const errorId = params.id;
    if (!errorId) {
      App.Router.navigate('errors');
      return;
    }

    const error = await App.DB.get('errors', errorId);
    if (!error) {
      App.Components.toast('错题不存在', 'error');
      App.Router.navigate('errors');
      return;
    }

    // 返回栏 + 右上角：编辑题目按钮 + 三点菜单
    const header = App.Components.pageHeader('错题详情');
    const detailRight = header.querySelector('.page-header__right');
    if (detailRight) {
      detailRight.style.display = 'flex';
      detailRight.style.alignItems = 'center';
      detailRight.style.gap = '2px';
      detailRight.innerHTML = '';

      const editBtn = document.createElement('button');
      editBtn.className = 'detail-header-action';
      editBtn.textContent = '✏️';
      editBtn.title = '编辑题目信息';
      editBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        App.Router.navigate('error-form?id=' + error.id);
      });
      detailRight.appendChild(editBtn);

      const moreBtn = document.createElement('button');
      moreBtn.className = 'detail-header-action';
      moreBtn.textContent = '⋮';
      moreBtn.title = '更多操作';
      moreBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this._showErrorMenu(error);
      });
      detailRight.appendChild(moreBtn);
    }
    container.appendChild(header);

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) var(--page-padding);padding-bottom:calc(var(--nav-height) + var(--safe-bottom) + var(--spacing-lg));';

    // 题号 + 标签
    const headerInfo = document.createElement('div');
    headerInfo.style.cssText = 'margin-bottom:var(--spacing-md);';
    const subjectTagType = {
      '言语理解': 'primary', '数量关系': 'warning', '判断推理': 'success',
      '资料分析': 'purple', '常识判断': 'gold', '申论': 'teal'
    };
    const statusType = error.status === '已掌握' ? 'success' : 'danger';
    headerInfo.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px;">
        <span class="tag tag--${subjectTagType[error.subject] || 'neutral'}">${error.subject}</span>
        <span class="tag tag--neutral">${error.module}</span>
        ${(error.knowledgePoints || []).map(kp => `<span class="tag tag--neutral">${kp}</span>`).join('')}
        <span class="tag tag--neutral">${error.errorCause}</span>
        <span class="tag tag--${statusType}">${error.status}</span>
      </div>
    `;
    content.appendChild(headerInfo);

    // 题干
    const questionEl = document.createElement('div');
    questionEl.style.cssText = 'font-size:var(--font-md);line-height:1.7;margin-bottom:var(--spacing-md);padding:var(--spacing-md);background:var(--bg-tertiary);border-radius:var(--radius-md);';
    questionEl.textContent = error.question;
    content.appendChild(questionEl);

    // 选项
    const optionsList = document.createElement('div');
    optionsList.className = 'options-list';
    const letters = ['A', 'B', 'C', 'D'];
    (error.options || []).forEach((opt, idx) => {
      const letter = letters[idx] || String(idx);
      const isCorrect = letter === error.correctOption;
      const isWrong = letter === error.userOption;

      const item = document.createElement('div');
      item.className = 'option-item';
      if (isCorrect) item.classList.add('option-item--correct');
      if (isWrong) item.classList.add('option-item--wrong');

      let label = '';
      if (isCorrect && isWrong) label = ' ✅ 正确答案（你的选择）';
      else if (isCorrect) label = ' ✅ 正确答案';
      else if (isWrong) label = ' ❌ 你的选择';

      item.innerHTML = `
        <span class="option-item__letter">${letter}.</span>
        <span>${opt}${label}</span>
      `;
      optionsList.appendChild(item);
    });
    content.appendChild(optionsList);

    // 正确率
    const accuracyEl = document.createElement('div');
    accuracyEl.style.cssText = 'font-size:var(--font-sm);color:var(--text-secondary);margin-bottom:var(--spacing-md);';
    accuracyEl.innerHTML = `📊 全站正确率：<strong>${error.accuracy || 0}%</strong>`;
    content.appendChild(accuracyEl);

    // 题目来源
    if (error.questionSource) {
      const sourceEl = document.createElement('div');
      sourceEl.style.cssText = 'font-size:var(--font-sm);color:var(--text-secondary);margin-bottom:var(--spacing-md);';
      sourceEl.innerHTML = `📚 题目来源：<strong>${error.questionSource}</strong>`;
      content.appendChild(sourceEl);
    }

    // 解析分析笔记
    const noteTitle = document.createElement('div');
    noteTitle.style.cssText = 'font-size:var(--font-sm);font-weight:600;color:var(--text-secondary);margin-bottom:var(--spacing-sm);';
    noteTitle.innerHTML = '📝 解析分析笔记 <span style="font-weight:400;color:var(--text-tertiary);font-size:var(--font-xs);">（点击可编辑）</span>';
    content.appendChild(noteTitle);

    const noteContent = document.createElement('div');
    noteContent.className = 'card';
    noteContent.style.cssText = 'margin:0 0 4px 0;line-height:1.7;min-height:60px;cursor:pointer;';
    noteContent.innerHTML = error.analysisNote
      ? App.Utils.simpleMarkdown(error.analysisNote)
      : '<span style="color:var(--text-tertiary);">点击添加解析笔记</span>';
    content.appendChild(noteContent);

    // 点击就地编辑解析笔记
    let noteEditing = false;
    noteContent.addEventListener('click', () => {
      if (noteEditing) return;
      noteEditing = true;
      noteContent.style.cursor = 'default';
      const editor = App.Components.markdownEditor(error.analysisNote, '输入解析思路...');
      noteContent.innerHTML = '';
      noteContent.appendChild(editor.element);

      const actions = document.createElement('div');
      actions.style.cssText = 'display:flex;gap:8px;margin-top:8px;';
      const saveBtn = document.createElement('button');
      saveBtn.className = 'btn btn--primary btn--sm';
      saveBtn.textContent = '保存';
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'btn btn--outline btn--sm';
      cancelBtn.textContent = '取消';
      actions.appendChild(saveBtn);
      actions.appendChild(cancelBtn);
      noteContent.appendChild(actions);

      saveBtn.addEventListener('click', async () => {
        error.analysisNote = editor.getContent();
        await App.DB.updateError(error);
        App.Components.toast('已保存 ✓', 'success');
        this.renderDetail(params);
      });
      cancelBtn.addEventListener('click', () => {
        this.renderDetail(params);
      });
    });

    // 错题笔记（个人复盘心得）
    const enoteTitle = document.createElement('div');
    enoteTitle.style.cssText = 'font-size:var(--font-sm);font-weight:600;color:var(--text-secondary);margin:var(--spacing-md) 0 var(--spacing-sm);';
    enoteTitle.innerHTML = '📒 错题笔记 <span style="font-weight:400;color:var(--text-tertiary);font-size:var(--font-xs);">（点击可编辑，记录复盘心得）</span>';
    content.appendChild(enoteTitle);

    const enoteContent = document.createElement('div');
    enoteContent.className = 'card';
    enoteContent.style.cssText = 'margin:0 0 4px 0;line-height:1.7;min-height:60px;cursor:pointer;';
    enoteContent.innerHTML = error.note
      ? App.Utils.simpleMarkdown(error.note)
      : '<span style="color:var(--text-tertiary);">点击添加错题笔记</span>';
    content.appendChild(enoteContent);

    let enoteEditing = false;
    enoteContent.addEventListener('click', () => {
      if (enoteEditing) return;
      enoteEditing = true;
      enoteContent.style.cursor = 'default';
      const editor = App.Components.markdownEditor(error.note, '记录这道题的复盘心得、易错点提醒...');
      enoteContent.innerHTML = '';
      enoteContent.appendChild(editor.element);

      const actions = document.createElement('div');
      actions.style.cssText = 'display:flex;gap:8px;margin-top:8px;';
      const saveBtn = document.createElement('button');
      saveBtn.className = 'btn btn--primary btn--sm';
      saveBtn.textContent = '保存';
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'btn btn--outline btn--sm';
      cancelBtn.textContent = '取消';
      actions.appendChild(saveBtn);
      actions.appendChild(cancelBtn);
      enoteContent.appendChild(actions);

      saveBtn.addEventListener('click', async () => {
        error.note = editor.getContent();
        await App.DB.updateError(error);
        App.Components.toast('已保存 ✓', 'success');
        this.renderDetail(params);
      });
      cancelBtn.addEventListener('click', () => { this.renderDetail(params); });
    });

    // 复习信息
    const reviewInfo = document.createElement('div');
    reviewInfo.style.cssText = 'font-size:var(--font-xs);color:var(--text-tertiary);margin-bottom:var(--spacing-md);';
    reviewInfo.innerHTML = `
      收录于 ${App.Utils.formatDate(error.createdAt)} ·
      复习 ${error.reviewCount || 0} 次 ·
      上次复习 ${error.lastReviewDate ? App.Utils.formatDate(error.lastReviewDate) : '从未'}
    `;
    content.appendChild(reviewInfo);

    container.appendChild(content);
  },

  // ===== 错题详情页右上角三点菜单 =====
  async _showErrorMenu(error) {
    const isMastered = error.status === '已掌握';
    const action = await App.Components.actionSheet([
      { label: isMastered ? '↩️ 标记未掌握' : '✓ 标记已掌握', value: 'master' },
      { label: '📅 加入今日复习', value: 'review' },
      { label: '🗑️ 删除', value: 'delete' }
    ], error.question ? error.question.slice(0, 20) : '错题');
    if (!action) return;

    switch (action) {
      case 'master': {
        if (isMastered) {
          error.status = '未掌握';
          await App.DB.updateError(error);
          App.Components.toast('已标记为未掌握', 'success');
        } else {
          error.status = '已掌握';
          error.lastReviewDate = new Date().toISOString();
          error.reviewCount = (error.reviewCount || 0) + 1;
          await App.DB.updateError(error);
          App.Components.toast('已标记为掌握 ✓', 'success');
        }
        this.renderDetail({ id: error.id });
        break;
      }
      case 'review': {
        error.lastReviewDate = new Date().toISOString();
        error.reviewCount = (error.reviewCount || 0) + 1;
        await App.DB.updateError(error);
        App.Components.toast('已加入今日复习', 'success');
        this.renderDetail({ id: error.id });
        break;
      }
      case 'delete': {
        const confirmed = await App.Components.confirm(
          '删除错题',
          '确定删除这道错题？此操作不可撤销。',
          '删除', '取消', true
        );
        if (confirmed) {
          await App.DB.remove('errors', error.id);
          App.Components.toast('已删除', 'success');
          App.Router.navigate('errors');
        }
        break;
      }
    }
  },

  // ===== 新建/编辑错题表单 =====
  renderForm(params) {
    const container = document.getElementById('page-error-form');
    container.innerHTML = '';

    let isEdit = !!params.id;

    // 默认空白表单
    let formData = {
      subject: '',
      module: '',
      knowledgePoints: [],
      errorCause: '',
      question: '',
      options: ['', '', '', ''],
      correctOption: '',
      userOption: '',
      accuracy: '',
      analysisNote: '',
      note: '',
      questionSource: '',
      status: '未掌握',
      sourceExamId: params.examId || null
    };

    // 如果是编辑，加载数据；如果是新建，尝试恢复「同一篇正在录入」的草稿
    const loadAndRender = async () => {
      if (isEdit) {
        const error = await App.DB.get('errors', params.id);
        if (error) {
          formData = {
            subject: error.subject || '',
            module: error.module || '',
            knowledgePoints: error.knowledgePoints || [],
            errorCause: error.errorCause || '',
            question: error.question || '',
            options: error.options || ['', '', '', ''],
            correctOption: error.correctOption || '',
            userOption: error.userOption || '',
            accuracy: error.accuracy !== undefined ? String(error.accuracy) : '',
            analysisNote: error.analysisNote || '',
            note: error.note || '',
            questionSource: error.questionSource || '',
            status: error.status || '未掌握',
            sourceExamId: error.sourceExamId || null,
            id: error.id
          };
        }
        formData._formId = params.id;
      } else {
        // 新建/续编：仅当 sessionStorage 记录着「同一篇正在录入」的 id 时才续编；否则一律空白。
        const fid = App.Draft.getFormId('error');
        if (fid) {
          if (App.Draft.formIdIsTemp(fid)) {
            const d = App.Draft.loadForm('error', fid);
            if (d) Object.assign(formData, d);
            formData._formId = fid;
          } else {
            const error = await App.DB.get('errors', fid);
            if (error) {
              isEdit = true;
              formData = {
                subject: error.subject || '',
                module: error.module || '',
                knowledgePoints: error.knowledgePoints || [],
                errorCause: error.errorCause || '',
                question: error.question || '',
                options: error.options || ['', '', '', ''],
                correctOption: error.correctOption || '',
                userOption: error.userOption || '',
                accuracy: error.accuracy !== undefined ? String(error.accuracy) : '',
                analysisNote: error.analysisNote || '',
                note: error.note || '',
                questionSource: error.questionSource || '',
                status: error.status || '未掌握',
                sourceExamId: error.sourceExamId || null,
                id: error.id
              };
              formData._formId = fid;
            }
          }
        }
        if (!formData._formId) {
          formData._formId = App.Draft.newTempId();
          App.Draft.setFormId('error', formData._formId);
        }
        // 从某套卷点「加错题」时，关联回该套卷
        if (params.examId && !formData.sourceExamId) formData.sourceExamId = params.examId;
      }
      buildForm();
    };

    const buildForm = () => {
      container.innerHTML = '';

      // 返回栏
      container.appendChild(App.Components.pageHeader(
        isEdit ? '编辑错题' : '添加错题',
        isEdit ? '保存' : '提交',
        async () => {
          if (!formData.subject || !formData.module || formData.knowledgePoints.length === 0 || !formData.errorCause || !formData.question) {
            App.Components.toast('请先完成必填项', 'error');
            return;
          }
          await submitForm();
        }
      ));

      const form = document.createElement('div');
      form.className = 'form-page';

      // 科目
      form.appendChild(App.Components.formSelector(
        '科目',
        App.Constants.SUBJECTS,
        formData.subject,
        (val) => {
          formData.subject = val;
          formData.module = '';
          formData.knowledgePoints = [];
          buildForm();
        },
        true
      ));

      // 模块
      if (formData.subject) {
        form.appendChild(App.Components.formSelector(
          '模块',
          App.Constants.getModules(formData.subject),
          formData.module,
          (val) => {
            formData.module = val;
            formData.knowledgePoints = [];
            buildForm();
          },
          true
        ));
      }

      // 考点
      if (formData.module) {
        form.appendChild(App.Components.tagInput(
          '考点',
          App.Tags.getKnowledgePointSuggestions(formData.module),
          formData.knowledgePoints,
          (val) => { formData.knowledgePoints = val; },
          3,
          true,
          '输入自定义考点，回车添加',
          (v) => App.Tags.addKnowledgePoint(formData.module, v)
        ));
      }

      // 错因
      form.appendChild(App.Components.tagInput(
        '错因',
        App.Tags.getErrorCauseSuggestions(),
        formData.errorCause ? [formData.errorCause] : [],
        (val) => { formData.errorCause = val[0] || ''; },
        1,
        true,
        '选择或输入错因，回车添加',
        (v) => App.Tags.addErrorCause(v)
      ));

      // AI 智能拆分（题干 + 选项）
      const aiBtn = document.createElement('button');
      aiBtn.type = 'button';
      aiBtn.className = 'btn btn--outline btn--full';
      aiBtn.style.marginBottom = 'var(--spacing-md)';
      aiBtn.innerHTML = '🤖 AI 智能拆分题干与选项';
      aiBtn.addEventListener('click', () => this.openSmartSplit(formData, buildForm));
      form.appendChild(aiBtn);

      // 题目
      form.appendChild(App.Components.formInput(
        '题目',
        formData.question,
        '请输入完整题干',
        (val) => { formData.question = val; },
        'textarea',
        true
      ));

      // 选项
      const optionsGroup = document.createElement('div');
      optionsGroup.className = 'form-group';
      const optionsLabel = document.createElement('label');
      optionsLabel.className = 'form-label';
      optionsLabel.innerHTML = '选项<span class="required">*</span>';
      optionsGroup.appendChild(optionsLabel);

      ['A', 'B', 'C', 'D'].forEach((letter, idx) => {
        const input = document.createElement('input');
        input.className = 'form-input';
        input.style.marginBottom = '6px';
        input.placeholder = '选项 ' + letter;
        input.value = formData.options[idx] || '';
        input.addEventListener('input', () => {
          formData.options[idx] = input.value;
        });
        const wrapper = document.createElement('div');
        wrapper.style.display = 'flex';
        wrapper.style.alignItems = 'center';
        wrapper.style.gap = '8px';
        const letterSpan = document.createElement('span');
        letterSpan.style.cssText = 'font-weight:700;width:20px;flex-shrink:0;';
        letterSpan.textContent = letter;
        wrapper.appendChild(letterSpan);
        wrapper.appendChild(input);
        optionsGroup.appendChild(wrapper);
      });
      form.appendChild(optionsGroup);

      // 正确选项 + 错误选项
      const selectRow = document.createElement('div');
      selectRow.style.cssText = 'display:flex;gap:var(--spacing-md);';
      selectRow.appendChild(App.Components.formSelector(
        '正确选项',
        ['A', 'B', 'C', 'D'],
        formData.correctOption,
        (val) => { formData.correctOption = val; buildForm(); },
        true
      ));
      selectRow.appendChild(App.Components.formSelector(
        '你的选项',
        ['A', 'B', 'C', 'D'],
        formData.userOption,
        (val) => { formData.userOption = val; buildForm(); },
        false
      ));
      form.appendChild(selectRow);

      // 正确率
      form.appendChild(App.Components.formInput(
        '全站正确率（%）',
        formData.accuracy,
        '例如：65',
        (val) => { formData.accuracy = val; },
        'number',
        false
      ));

      // 题目来源
      form.appendChild(App.Components.formInput(
        '题目来源',
        formData.questionSource,
        '如：2023 国考真题 / 某机构模拟卷 / 日常练习',
        (val) => { formData.questionSource = val; },
        'text',
        false
      ));

      // 解析笔记
      const noteGroup = document.createElement('div');
      noteGroup.className = 'form-group';
      const noteLabel = document.createElement('label');
      noteLabel.className = 'form-label';
      noteLabel.textContent = '解析分析笔记';
      noteGroup.appendChild(noteLabel);

      const editor = App.Components.markdownEditor(formData.analysisNote, '输入解析思路...');
      noteGroup.appendChild(editor.element);
      formData._getNote = editor.getContent;
      form.appendChild(noteGroup);

      // 错题笔记（个人复盘心得，区别于解析分析）
      const enoteGroup = document.createElement('div');
      enoteGroup.className = 'form-group';
      const enoteLabel = document.createElement('label');
      enoteLabel.className = 'form-label';
      enoteLabel.textContent = '错题笔记（个人复盘心得）';
      enoteGroup.appendChild(enoteLabel);

      const enoteEditor = App.Components.markdownEditor(formData.note, '记录这道题的复盘心得、易错点提醒...');
      enoteGroup.appendChild(enoteEditor.element);
      formData._getENote = enoteEditor.getContent;
      form.appendChild(enoteGroup);

      container.appendChild(form);

      // 草稿自动暂存（localStorage 兜底）+ 触发 DB 自动保存
      App.Draft.autoSaveForm('error', formData._formId, container, function () {
        if (formData._getNote) { try { formData.analysisNote = formData._getNote(); } catch (e) {} }
        if (formData._getENote) { try { formData.note = formData._getENote(); } catch (e) {} }
        debouncedSaveToDB();
        return JSON.parse(JSON.stringify(formData));
      });
    };

    // 防抖自动保存到 DB
    let _errSaveTimer = null, _errSaving = false;
    function debouncedSaveToDB() {
      clearTimeout(_errSaveTimer);
      _errSaveTimer = setTimeout(async () => {
        if (_errSaving) return;
        // 必填项校验：科目、模块、考点、错因、题目
        if (!formData.subject || !formData.module || formData.knowledgePoints.length === 0 ||
            !formData.errorCause || !formData.question.trim()) return;
        _errSaving = true;
        try { await submitFormInternal(); } catch (e) {}
        _errSaving = false;
      }, 2000);
    }

    const submitFormInternal = async () => {
      if (formData._getNote) formData.analysisNote = formData._getNote();
      if (formData._getENote) formData.note = formData._getENote();

      const data = {
        subject: formData.subject, module: formData.module,
        knowledgePoints: formData.knowledgePoints, errorCause: formData.errorCause,
        question: formData.question, options: formData.options.filter(o => o.trim()),
        correctOption: formData.correctOption, userOption: formData.userOption || '',
        accuracy: parseInt(formData.accuracy) || 0,
        analysisNote: formData.analysisNote || '', note: formData.note || '',
        questionSource: formData.questionSource || '',
        status: formData.status || '未掌握', sourceExamId: formData.sourceExamId || null,
      };
      if (isEdit && formData.id) {
        data.id = formData.id;
        const existing = await App.DB.get('errors', formData.id);
        data.reviewCount = existing ? existing.reviewCount || 0 : 0;
        data.lastReviewDate = new Date().toISOString();
        data.createdAt = existing ? existing.createdAt : new Date().toISOString();
        await App.DB.updateError(data);
      } else {
        if (!formData.id) { await App.DB.addError(data); formData.id = data.id; isEdit = true; }
        else { data.id = formData.id; await App.DB.updateError(data); }
      }
    };

    const submitForm = async () => {
      clearTimeout(_errSaveTimer);
      if (formData._getNote) formData.analysisNote = formData._getNote();
      if (formData._getENote) formData.note = formData._getENote();
      if (!formData.subject) { App.Components.toast('请选择科目', 'error'); return; }
      if (!formData.module) { App.Components.toast('请选择模块', 'error'); return; }
      if (formData.knowledgePoints.length === 0) { App.Components.toast('请选择考点', 'error'); return; }
      if (!formData.errorCause) { App.Components.toast('请选择错因', 'error'); return; }
      if (!formData.question.trim()) { App.Components.toast('请输入题目', 'error'); return; }
      if (!formData.correctOption) { App.Components.toast('请选择正确选项', 'error'); return; }
      try {
        await submitFormInternal();
        App.Components.toast('已自动保存 ✓', 'success');
        App.Draft.clearForm('error');
        App.Router.navigate('errors');
      } catch (e) { App.Components.toast('保存失败', 'error'); }
    };

    loadAndRender();
  }
};
