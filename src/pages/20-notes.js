// ===== 考公笔试复盘系统 - 笔记页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Notes = {
  state: {
    subject: null,
    module: null,
    knowledgePoint: null,
    type: null,
    search: '',
    searchVisible: false,
    allNotes: []
  },

  _noteTypeColorBg(color) {
    const hex = String(color || '').replace('#', '');
    return /^[0-9a-fA-F]{6}$/.test(hex)
      ? 'rgba(' + [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16)).join(',') + ',0.12)'
      : 'rgba(0,102,204,0.12)';
  },

  _noteContextMatches(note, subject, module) {
    return note && note.subject === subject && (module ? note.module === module : !note.module);
  },

  _noteTypeOptions(subject, module, current) {
    const types = subject ? App.NoteTypes.getForContext(subject, module).slice() : [];
    const selected = current || App.NoteTypes.UNCLASSIFIED;
    if (selected !== App.NoteTypes.UNCLASSIFIED && !types.some(t => t.name === selected)) {
      types.push({
        name: selected,
        color: App.NoteTypes.getColor(selected, subject, module),
        enabled: false
      });
    }
    return [{ name: App.NoteTypes.UNCLASSIFIED, color: '#8E8E93', enabled: true }].concat(types);
  },

  async openNoteTypePicker(note, onSaved) {
    const subject = note.subject || '';
    const module = note.module || '';
    const modal = App.Components.centeredModal({ title: '修改标签' });
    if (!modal) return;

    const hint = document.createElement('div');
    hint.className = 'app-centered-modal__hint';
    hint.textContent = '选择当前模块标签';
    modal.body.appendChild(hint);

    let selected = note.type || App.NoteTypes.UNCLASSIFIED;
    const options = document.createElement('div');
    options.className = 'note-type-picker';
    const renderOptions = () => {
      options.innerHTML = '';
      this._noteTypeOptions(subject, module, selected).forEach(type => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'note-type-picker__option' + (type.name === selected ? ' is-selected' : '');
        button.textContent = type.name;
        button.style.setProperty('--note-type-color', type.color || '#0066CC');
        button.addEventListener('click', () => { selected = type.name; renderOptions(); });
        options.appendChild(button);
      });
    };
    renderOptions();
    modal.body.appendChild(options);

    const actions = document.createElement('div');
    actions.className = 'todo-modal__actions app-centered-modal__actions';
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'todo-modal__btn todo-modal__btn--cancel';
    cancel.textContent = '取消';
    cancel.addEventListener('click', () => modal.close());
    const save = document.createElement('button');
    save.type = 'button';
    save.className = 'todo-modal__btn todo-modal__btn--ok';
    save.textContent = '保存';
    save.addEventListener('click', async () => {
      const next = selected || App.NoteTypes.UNCLASSIFIED;
      note.type = next;
      try {
        await App.DB.updateNote(note);
        App.Utils.rememberSelect.set('note', subject, module, next);
        modal.close();
        App.Components.toast('标签已更新', 'success');
        if (typeof onSaved === 'function') await onSaved(note);
      } catch (e) {
        App.Components.toast('标签保存失败', 'error');
      }
    });
    actions.appendChild(cancel);
    actions.appendChild(save);
    modal.body.appendChild(actions);
  },

  async openNoteTypeEditor(context, name, onDone) {
    const subject = context && context.subject;
    const module = context && context.module;
    const editing = !!name;
    const list = App.NoteTypes.getForContextAll(subject, module);
    const current = editing ? list.find(t => t.name === name) : null;
    const draft = {
      name: current ? current.name : '',
      color: current ? current.color : '#0066CC'
    };
    const modal = App.Components.centeredModal({ title: editing ? '编辑标签' : '新增标签' });
    if (!modal) return;

    const scope = document.createElement('div');
    scope.className = 'app-centered-modal__hint';
    scope.textContent = '当前范围：' + subject + (module ? ' / ' + module : '（科目级）');
    modal.body.appendChild(scope);

    const label = document.createElement('div');
    label.className = 'app-centered-modal__field-label';
    label.textContent = '标签名称';
    modal.body.appendChild(label);
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'todo-modal__input app-centered-modal__text-input';
    input.placeholder = '例如：高频考点';
    input.value = draft.name;
    input.addEventListener('input', () => { draft.name = input.value; });
    modal.body.appendChild(input);

    const colorLabel = document.createElement('div');
    colorLabel.className = 'app-centered-modal__field-label';
    colorLabel.textContent = '标签颜色';
    modal.body.appendChild(colorLabel);
    const colorRow = document.createElement('div');
    colorRow.className = 'note-type-color-picker';
    const colors = Array.from(new Set((App.NoteTypes.DEFAULT_COLORS || []).concat(['#0066CC', '#FF9500', '#34C759', '#9B7BFF'])));
    const renderColors = () => {
      colorRow.innerHTML = '';
      colors.forEach(color => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'note-type-color-picker__dot' + (draft.color === color ? ' is-selected' : '');
        b.style.background = color;
        b.title = color;
        b.addEventListener('click', () => { draft.color = color; renderColors(); });
        colorRow.appendChild(b);
      });
    };
    renderColors();
    modal.body.appendChild(colorRow);

    const preview = document.createElement('div');
    preview.className = 'note-type-editor__preview';
    const updatePreview = () => {
      preview.textContent = draft.name.trim() || '标签预览';
      preview.style.background = this._noteTypeColorBg(draft.color);
      preview.style.color = draft.color;
    };
    input.addEventListener('input', updatePreview);
    colorRow.addEventListener('click', updatePreview);
    updatePreview();
    modal.body.appendChild(preview);

    const actions = document.createElement('div');
    actions.className = 'todo-modal__actions app-centered-modal__actions';
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'todo-modal__btn todo-modal__btn--cancel';
    cancel.textContent = '取消';
    cancel.addEventListener('click', () => modal.close());
    const save = document.createElement('button');
    save.type = 'button';
    save.className = 'todo-modal__btn todo-modal__btn--ok';
    save.textContent = '保存';
    save.addEventListener('click', async () => {
      const nextName = draft.name.trim();
      if (!nextName) { App.Components.toast('请输入标签名称', 'error'); return; }
      if (!editing && list.some(t => t.name === nextName)) {
        App.Components.toast('已存在同名标签', 'error'); return;
      }
      if (editing) {
        if (!App.NoteTypes.renameForContext(subject, module, name, nextName, draft.color)) {
          App.Components.toast('标签保存失败', 'error'); return;
        }
        try {
          const notes = await App.DB.getNotes();
          for (const note of notes) {
            if (this._noteContextMatches(note, subject, module) && note.type === name) {
              note.type = nextName;
              await App.DB.updateNote(note);
            }
          }
        } catch (e) { /* 标签已保存，历史笔记同步失败时保留当前配置 */ }
      } else if (!App.NoteTypes.addForContext(subject, module, nextName, draft.color)) {
        App.Components.toast('标签保存失败', 'error'); return;
      }
      modal.close();
      App.Components.toast('标签已保存', 'success');
      if (typeof onDone === 'function') await onDone();
    });
    actions.appendChild(cancel);
    actions.appendChild(save);
    modal.body.appendChild(actions);
    setTimeout(() => input.focus(), 60);
  },

  async render(params) {
    const container = document.getElementById('page-notes');
    container.innerHTML = '';
    if (params && Object.prototype.hasOwnProperty.call(params, 'subject')) {
      const requestedSubject = params.subject || null;
      const isKnownSubject = !!requestedSubject && App.Constants.SUBJECTS.some(s => s.name === requestedSubject);
      this.state.subject = isKnownSubject ? requestedSubject : null;
      const modules = this.state.subject ? App.Constants.getModules(this.state.subject) : [];
      this.state.module = this.state.subject && params.module && modules.indexOf(params.module) !== -1 ? params.module : null;
      const requestedType = params.type || params.noteType || null;
      this.state.type = requestedType === App.NoteTypes.UNCLASSIFIED ? null : requestedType;
      this.state.knowledgePoint = null;
    }

    // 左侧边栏（科目 - 模块）+ 主内容区（与错题本一致）
    const layout = document.createElement('div');
    layout.className = 'with-sidebar';

    const sidebar = document.createElement('div');
    sidebar.className = 'sidebar';
    sidebar.id = 'note-sidebar';
    layout.appendChild(sidebar);

    const main = document.createElement('div');
    main.className = 'page-main';

    // 页面标题
    // v8.14.11 顶栏搜索常驻（对齐画布「iPad-笔记」7:31：大标题 + 搜索栏 + 三点更多）
    const stickyWrap = document.createElement('div');
    stickyWrap.className = 'page-sticky';
    const header = document.createElement('div');
    header.className = 'page-header note-page-header';
    const kw = (this.state.search || '').replace(/"/g, '&quot;');
    header.innerHTML = `
      <div class="page-header__title" style="font-size:26px;font-weight:600;">笔记</div>
      <div class="note-header-search">
        <span class="search-bar__icon">🔍</span>
        <input type="text" placeholder="搜索笔记标题 / 内容" id="note-search" value="${kw}">
      </div>
      <button class="page-header__more" id="note-more" title="更多" aria-label="更多">
        <svg width="16" height="4" viewBox="0 0 16 4" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="2" cy="2" r="1.6" fill="#4A4A4A"/>
          <circle cx="8" cy="2" r="1.6" fill="#4A4A4A"/>
          <circle cx="14" cy="2" r="1.6" fill="#4A4A4A"/>
        </svg>
      </button>
    `;
    stickyWrap.appendChild(header);
    main.appendChild(stickyWrap);
    header.querySelector('#note-more').addEventListener('click', (e) => {
      e.stopPropagation();
      this._showPageMenu();
    });
    // 顶栏搜索常驻：输入即过滤列表
    const nSearch = header.querySelector('#note-search');
    nSearch.addEventListener('input', App.Utils.debounce((e) => {
      this.state.search = e.target.value;
      const listArea = document.getElementById('note-tree-area');
      if (listArea) this.renderList(listArea);
    }, 300));

    // 模块chips（对齐画布 8:4：选中科目后，列表区顶部横向选择该科目模块）
    const moduleFilterArea = document.createElement('div');
    moduleFilterArea.id = 'note-module-filter';
    main.appendChild(moduleFilterArea);

    // 类型chips（对齐画布：按笔记类型筛选）
    const typeFilterArea = document.createElement('div');
    typeFilterArea.id = 'note-type-filter';
    main.appendChild(typeFilterArea);

    // 考点筛选条（科目-模块由侧边栏管理，与错题本一致）
    const filterArea = document.createElement('div');
    filterArea.id = 'note-filter-area';
    main.appendChild(filterArea);

    const listArea = document.createElement('div');
    listArea.id = 'note-tree-area';
    main.appendChild(listArea);

    layout.appendChild(main);
    container.appendChild(layout);

    // 与错题本保持一致：笔记页常驻右下角新建入口，空状态按钮只作为无数据时的辅助入口。
    // 复用现有 FAB 样式，不改变笔记页整体布局；当前筛选的科目/模块会带入新建表单。
    const fab = document.createElement('button');
    fab.type = 'button';
    fab.className = 'sc-fab fab--solid-blue';
    fab.setAttribute('aria-label', '新建笔记');
    fab.title = '新建笔记';
    fab.innerHTML = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>';
    fab.addEventListener('click', () => {
      const query = [];
      if (this.state.subject) query.push('subject=' + encodeURIComponent(this.state.subject));
      if (this.state.module) query.push('module=' + encodeURIComponent(this.state.module));
      if (this.state.type) query.push('type=' + encodeURIComponent(this.state.type));
      App.Router.navigate('note-form' + (query.length ? '?' + query.join('&') : ''));
    });
    container.appendChild(fab);

    // 加载数据
    await this.loadData();
    this.renderSubjectGrid(sidebar);
    this.renderModuleFilter(moduleFilterArea);
    this.renderTypeFilter(typeFilterArea);
    this.renderFilters(filterArea);
    this.renderList(listArea);
  },

  async loadData() {
    this.state.allNotes = await App.DB.getNotes();
  },

  // 左侧科目窄栏（对齐画布「iPad-笔记」7:1005：窄栏80，科目图标+名竖排，选中浅蓝圆角12）
  // 模块选择交由列表区顶部「模块chips」承担（对齐画布 8:4）
  renderSubjectGrid(container) {
    // 完全复用错题本侧边栏风格（科目-模块树 + 计数 + 展开箭头 + SVG图标 + 二级模块）
    this._expanded = this._expanded || {};
    const noteCounts = {};
    App.Constants.SUBJECTS.forEach(s => {
      noteCounts[s.name] = this.state.allNotes.filter(n => n.subject === s.name).length;
    });

    container.innerHTML = '';

    // 「全部」项
    const allItem = document.createElement('div');
    allItem.className = 'sidebar__item' + (this.state.subject === null ? ' active' : '');
    allItem.innerHTML = `
      <span class="sidebar__item-icon" style="color:${this.state.subject === null ? '#0066CC' : '#7A7A7A'}">${App.Pages.Errors._subjectIconSvg('全部') || '📚'}</span>
      <span class="sidebar__item-name">全部</span>
    `;
    allItem.addEventListener('click', () => {
      this.state.subject = null;
      this.state.module = null;
      this.state.knowledgePoint = null;
      this.state.type = null;
      this._expanded = {};
      this.refreshAll();
    });
    container.appendChild(allItem);

    // 各科目（可展开 -> 模块）
    App.Constants.SUBJECTS.forEach(s => {
      const isActive = this.state.subject === s.name;
      const expanded = !!this._expanded[s.name];
      const modules = App.Constants.getModules(s.name);

      const row = document.createElement('div');
      row.className = 'sidebar__item' + (isActive ? ' active' : '') + (expanded ? ' sidebar__item--expanded' : '');
      const count = noteCounts[s.name];
      row.innerHTML = `
        <span class="sidebar__item-icon" style="color:${isActive ? '#0066CC' : s.color}">${App.Pages.Errors._subjectIconSvg(s.name) || s.icon}</span>
        <span class="sidebar__item-name">${s.name}</span>
        ${count > 0 ? `<span class="sidebar__item-count">${count}</span>` : ''}
        <span class="sidebar__arrow"><svg width="8" height="5" viewBox="0 0 8 5" fill="none"><path d="M1 1l3 3 3-3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
      `;
      // 箭头：展开/收起该科目下的模块
      row.querySelector('.sidebar__arrow').addEventListener('click', (e) => {
        e.stopPropagation();
        this._expanded[s.name] = !this._expanded[s.name];
        this.renderSubjectGrid(container);
      });
      // 点击科目行：选中科目，并在展开/收起模块之间切换；不再重复点击跳回「全部」
      row.addEventListener('click', () => {
        const sameSubject = this.state.subject === s.name;
        this.state.subject = s.name;
        this.state.module = null;
        this.state.knowledgePoint = null;
        this.state.type = null;
        if (!App.Constants.isFlatSubject(s.name)) this._expanded[s.name] = sameSubject ? !this._expanded[s.name] : true;
        this.refreshAll();
      });
      container.appendChild(row);

      // 模块（仅在该科目展开时显示，作为左侧二级导航；扁平科目如资料分析无模块层，不显示）
      if (expanded && !App.Constants.isFlatSubject(s.name)) {
        modules.forEach(mod => {
          const mCount = this.state.allNotes.filter(n => n.subject === s.name && n.module === mod).length;
          const sub = document.createElement('div');
          sub.className = 'sidebar__sub' + (isActive && this.state.module === mod ? ' active' : '');
          sub.innerHTML = `
            <span class="sidebar__sub-name">${mod}</span>
            ${mCount > 0 ? `<span class="sidebar__sub-count">${mCount}</span>` : ''}
          `;
          sub.addEventListener('click', (e) => {
            e.stopPropagation();
            this.state.subject = s.name;
            this.state.module = (this.state.module === mod) ? null : mod;
            this.state.knowledgePoint = null;
            this.state.type = null;
            this.refreshAll();
          });
          container.appendChild(sub);
        });
      }
    });
  },

  // 模块chips（对齐画布 8:4：选中科目后，列表区顶部横向选择该科目模块）
  renderModuleFilter(container) {
    container.innerHTML = '';
    if (!this.state.subject) return;
    const modules = App.Constants.getModules(this.state.subject);
    if (!modules || !modules.length) return;
    const wrap = document.createElement('div');
    wrap.classList.add('note-modchips');
    // 「全部」chip
    const mkChip = (label, active, onClick) => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'note-modchip' + (active ? ' active' : '');
      chip.textContent = label;
      chip.addEventListener('click', onClick);
      return chip;
    };
    wrap.appendChild(mkChip('全部', !this.state.module, () => {
      this.state.module = null;
      this.state.knowledgePoint = null;
      this.refreshAll();
    }));
    modules.forEach(mod => {
      wrap.appendChild(mkChip(mod, this.state.module === mod, () => {
        this.state.module = (this.state.module === mod) ? null : mod;
        this.state.knowledgePoint = null;
        this.refreshAll();
      }));
    });
    container.appendChild(wrap);
  },

  // 类型chips（对齐画布 A3：按笔记类型筛选，含「全部」）
  renderTypeFilter(container) {
    container.innerHTML = '';
    const hasContext = !!(this.state.subject && (
      this.state.module || App.Constants.isFlatSubject(this.state.subject)
    ));
    if (!hasContext) {
      const hint = document.createElement('div');
      hint.className = 'note-type-scope-hint';
      hint.textContent = '选择具体模块后显示该模块的笔记标签';
      container.appendChild(hint);
      return;
    }
    const types = App.NoteTypes.getForContext(this.state.subject, this.state.module);
    const wrap = document.createElement('div');
    wrap.classList.add('note-modchips');
    const mk = (label, active, onClick) => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'note-modchip' + (active ? ' active' : '');
      chip.textContent = label;
      chip.addEventListener('click', onClick);
      return chip;
    };
    wrap.appendChild(mk('全部', !this.state.type, () => {
      this.state.type = null;
      this.refreshFiltersAndList();
    }));
    types.forEach(t => {
      const isActive = this.state.type === t.name;
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'note-modchip' + (isActive ? ' active' : '');
      chip.style.cssText = isActive ? ('background:' + hexToRgba4(t.color, 0.14) + ';color:' + t.color + ';') : '';
      chip.textContent = t.name;
      chip.addEventListener('click', () => {
        this.state.type = (this.state.type === t.name) ? null : t.name;
        this.refreshFiltersAndList();
      });
      wrap.appendChild(chip);
    });
    function hexToRgba4(hex, a) {
      const h = String(hex).replace('#', '');
      if (/^[0-9a-fA-F]{6}$/.test(h)) return 'rgba(' + [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)).join(',') + ',' + a + ')';
      return 'rgba(0,102,204,' + a + ')';
    }
    container.appendChild(wrap);
  },

  // 考点筛选条（科目-模块由侧边栏管理；仅选中科目后显示）
  renderFilters(container) {
    container.innerHTML = '';
    if (!this.state.subject) return;

    let scope = this.state.allNotes.slice();
    scope = scope.filter(n => n.subject === this.state.subject);
    if (this.state.module) scope = scope.filter(n => n.module === this.state.module);

    const usedKps = new Set();
    scope.forEach(n => { if (n.knowledgePoint) usedKps.add(n.knowledgePoint); });
    if (!usedKps.size) return;

    // 考点顺序跟随标签库（排序后立即生效；扁平科目用科目级合并标签）
    const libOrder = App.Constants.isFlatSubject(this.state.subject)
      ? App.Tags.getSubjectKnowledgePoints(this.state.subject)
      : App.Tags.getKnowledgePoints(this.state.module);
    const kpItems = libOrder.filter(k => usedKps.has(k)).map(k => ({ name: k })).concat(
      Array.from(usedKps).filter(k => !libOrder.includes(k)).map(k => ({ name: k }))
    );
    const row = document.createElement('div');
    row.className = 'tag-select-row';
    row.appendChild(App.Components.tagSelect(
      kpItems,
      this.state.knowledgePoint,
      (kp) => {
        this.state.knowledgePoint = (this.state.knowledgePoint === kp) ? null : kp;
        this.refreshFiltersAndList();
      },
      { kind: 'kp', module: this.state.module || this.state.subject, onDone: () => this.refreshFiltersAndList(), placeholder: '考点' }
    ));
    container.appendChild(row);
  },

  // 扁平笔记卡片列表（按标签展示）
  renderList(container) {
    container.innerHTML = '';

    let notes = this.state.allNotes.slice();
    if (this.state.subject) notes = notes.filter(n => n.subject === this.state.subject);
    if (this.state.module) notes = notes.filter(n => n.module === this.state.module);
    if (this.state.knowledgePoint) notes = notes.filter(n => n.knowledgePoint === this.state.knowledgePoint);
    if (this.state.type) notes = notes.filter(n => this.state.type === App.NoteTypes.UNCLASSIFIED
      ? (!n.type || n.type === App.NoteTypes.UNCLASSIFIED)
      : n.type === this.state.type);
    if (this.state.search) {
      const kw = this.state.search.toLowerCase();
      const noteText = (n) => {
        // content 兼容：JSON 块数组（新数据）或 Markdown 字符串（历史数据）
        if (Array.isArray(n.content)) {
          try { return JSON.stringify(n.content).toLowerCase(); } catch (e) { return ''; }
        }
        return (n.content || '').toLowerCase();
      };
      notes = notes.filter(n =>
        n.title.toLowerCase().includes(kw) ||
        noteText(n).includes(kw)
      );
    }

    // 顶部不再显示笔记统计（用户 v8.2.11 指定）

    if (notes.length === 0) {
      // v8.15.1 笔记空状态对齐错题本空状态（.eerr-empty 卡片：图标+文案+新建按钮，靠上）
      const empty = document.createElement('div');
      empty.className = 'eerr-empty';
      const icon = document.createElement('div');
      icon.className = 'eerr-empty__icon';
      icon.innerHTML = '<svg width="44" height="44" viewBox="0 0 44 44" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6.5 8.5a3 3 0 013-3H20l3 3h11a3 3 0 013 3v24a3 3 0 01-3 3H9.5a3 3 0 01-3-3z" stroke="#C7C7CC" stroke-width="1.8" stroke-linejoin="round"/><path d="M14 19h17M14 25h17M14 31h10" stroke="#C7C7CC" stroke-width="1.8" stroke-linecap="round"/></svg>';
      empty.appendChild(icon);
      const title = document.createElement('div');
      title.className = 'eerr-empty__title';
      title.textContent = '还没有笔记';
      empty.appendChild(title);
      const desc = document.createElement('div');
      desc.className = 'eerr-empty__desc';
      desc.textContent = '点击「新建笔记」，记录你的第一条复盘';
      empty.appendChild(desc);
      const action = document.createElement('button');
      action.type = 'button';
      action.className = 'eerr-empty__action';
      action.textContent = '＋ 新建笔记';
      action.addEventListener('click', () => {
        App.Draft.clearForm('note');
        let q = '';
        if (this.state.subject) {
          q = '?subject=' + encodeURIComponent(this.state.subject);
          if (this.state.module) q += '&module=' + encodeURIComponent(this.state.module);
          if (this.state.type) q += '&type=' + encodeURIComponent(this.state.type);
        }
        App.Router.navigate('note-form' + q);
      });
      empty.appendChild(action);
      container.appendChild(empty);
      return;
    }

    notes.forEach((note, idx) => container.appendChild(this.buildNoteCard(note, null, {
      hideType: !!this.state.type,
      hideSubject: !!this.state.subject
    })));
  },

  // 笔记卡片：iPad 分屏优先——分类、日期和摘要集中呈现，减少无效留白。
  buildNoteCard(note, returnTo, cardOpts) {
    cardOpts = cardOpts || {};
    const card = document.createElement('div');
    card.className = 'note-item note-item--card note-item--compact';
    // 摘要：统一转为可读纯文本，避免旧块数据在列表出现 JSON 碎片。
    let summary = '';
    try {
      let txt = App.Utils.toNoteHtml(note.content || '');
      txt = String(txt).replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
      if (!txt || txt === '""' || txt === '[]') txt = '';
      if (txt) summary = App.Utils.truncate(txt, 70);
    } catch (e) { summary = ''; }
    let dateTxt = '';
    try {
      const dd = new Date(note.updatedAt);
      if (!isNaN(dd.getTime())) dateTxt = (dd.getMonth() + 1) + ' 月 ' + dd.getDate() + ' 日';
    } catch (e) { dateTxt = ''; }
    // 类型 pill（对齐画布：类型在笔记卡上显示效果）
    const hasType = !!(note.type && note.type !== App.NoteTypes.UNCLASSIFIED);
    const displayType = hasType ? note.type : '';
    const tc = hasType
      ? App.NoteTypes.getColor(note.type, note.subject, note.module)
      : '#8E8E93';
    const typePill = cardOpts.hideType || !hasType ? '' : `<button type="button" class="note-type-pill" style="background:${this._noteTypeColorBg(tc)};color:${tc};">${displayType}</button>`;
    const location = [!cardOpts.hideSubject && note.subject, note.module, note.knowledgePoint].filter(Boolean).join(' · ');
    card.innerHTML = `
      <div class="note-item__body">
        <div class="note-item__topline">
          <div class="note-item__title">${App.Utils.truncate(note.title, 48)}</div>
          <time class="note-item__date">${dateTxt}</time>
        </div>
        ${summary ? `<div class="note-item__summary">${summary}</div>` : ''}
        ${(typePill || location) ? `<div class="note-item__meta">${typePill}${location ? `<div class="note-item__location">${location}</div>` : ''}</div>` : ''}
      </div>
    `;
    const detailRoute = 'note-detail?id=' + encodeURIComponent(note.id) +
      (returnTo ? '&returnTo=' + encodeURIComponent(returnTo) : '');
    const typeButton = card.querySelector('.note-type-pill');
    if (typeButton) {
      typeButton.addEventListener('click', (e) => {
        e.stopPropagation();
        App.Pages.Notes.openNoteTypePicker(note, async () => {
          if (returnTo && /^errors(?:\?|$)/.test(returnTo) && App.Pages.Errors && App.Pages.Errors.refreshAll) {
            await App.Pages.Errors.refreshAll();
          } else if (App.Pages.Notes.refreshAll) {
            App.Pages.Notes.refreshAll();
          }
        });
      });
    }
    card.addEventListener('click', () => App.Router.navigate(detailRoute));
    return card;
  },

  // 局部刷新：筛选条即时切换不动画，列表仅做进入动画
  refreshFiltersAndList() {
    const moduleFilter = document.getElementById('note-module-filter');
    const typeFilter = document.getElementById('note-type-filter');
    const filterArea = document.getElementById('note-filter-area');
    const listArea = document.getElementById('note-tree-area');
    if (moduleFilter) this.renderModuleFilter(moduleFilter);
    if (typeFilter) this.renderTypeFilter(typeFilter);
    if (filterArea) this.renderFilters(filterArea);
    if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderList(c));
  },

  refreshAll() {
    const sidebar = document.getElementById('note-sidebar');
    const moduleFilter = document.getElementById('note-module-filter');
    const typeFilter = document.getElementById('note-type-filter');
    const filterArea = document.getElementById('note-filter-area');
    const listArea = document.getElementById('note-tree-area');
    if (sidebar) this.renderSubjectGrid(sidebar);
    if (moduleFilter) this.renderModuleFilter(moduleFilter);
    if (typeFilter) this.renderTypeFilter(typeFilter);
    if (filterArea) this.renderFilters(filterArea);
    if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderList(c));
  },

  // 右上角三点菜单（v8.14.11 搜索已常驻顶栏，菜单只保留轻量项）
  async _showPageMenu() {
    App.Components.toast('暂无可选项', 'info');
  },

  // ===== 笔记详情页（Notion 式无模式就地编辑：点击即编辑，失焦即保存回查看） =====
  async renderDetail(params) {
    const container = document.getElementById('page-note-detail');
    container.innerHTML = '';
    this._detailParams = params || {};
    const detailReturnRoute = params && typeof params.returnTo === 'string' && /^(?:errors|notes)(?:\?|$)/.test(params.returnTo)
      ? params.returnTo
      : 'notes';

    const noteId = params.id;
    if (!noteId) { App.Router.navigate(detailReturnRoute); return; }

    const note = await App.DB.get('notes', noteId);
    if (!note) {
      App.Components.toast('笔记不存在', 'error');
      App.Router.navigate(detailReturnRoute);
      return;
    }

    // v8.5.5 彻底去块：content 统一为完整 HTML 字符串。
    // 历史数据（JSON 块数组 / 旧 Markdown）→ toNoteHtml 转 HTML 并存回 DB（一次性迁移，用户无感）
    const contentHtml = App.Utils.toNoteHtml(note.content);
    if (note.content !== contentHtml) {
      note.content = contentHtml;
      try { await App.DB.updateNote(note); } catch (e) { /* 迁移写回失败不影响查看 */ }
    }

    // 返回栏 + 右上角：✍️ 手写 + ⋮ 菜单（无「编辑」按钮——点击标题/正文即就地编辑）
    const header = App.Components.pageHeader('笔记详情', '⋮', () => this._showDetailMenu(note), {
      onBack: () => App.Router.navigate(detailReturnRoute)
    });
    const moreBtn = header.querySelector('.page-header__right');
    if (moreBtn) {
      moreBtn.classList.add('note-detail-more');
      const doodleBtn = document.createElement('button');
      doodleBtn.className = 'detail-header-action';
      doodleBtn.textContent = '✍️';
      doodleBtn.title = '手写笔记';
      doodleBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this._openDoodle(note, params);
      });
      moreBtn.parentNode.insertBefore(doodleBtn, moreBtn);
    }
    // 保存右上角按钮区引用：编辑态把字数标签整合进这里（⋮ 三个点附近）
    this._noteActionsEl = moreBtn;
    container.appendChild(header);

    const content = document.createElement('div');
    content.className = 'note-detail-content';

    // 面包屑
    const breadcrumb = document.createElement('div');
    breadcrumb.className = 'breadcrumb';
    breadcrumb.style.marginBottom = 'var(--spacing-md)';
    const pathParts = [note.subject, note.module, note.knowledgePoint].filter(Boolean);
    breadcrumb.innerHTML = pathParts.map((part, index) =>
      (index ? '<span class="breadcrumb__sep">›</span>' : '') + '<span class="breadcrumb__item">' + part + '</span>'
    ).join('');
    if (pathParts.length) content.appendChild(breadcrumb);

    // 标题（点击就地编辑，无模式切换）
    const titleEl = document.createElement('div');
    titleEl.className = 'note-detail-title';
    titleEl.textContent = note.title || '';
    titleEl.addEventListener('click', () => this._editTitleInPlace(titleEl, note, metaEl));
    content.appendChild(titleEl);

    // 紧凑信息条：让正文保留完整阅读宽度，并明确就地编辑方式。
    const infoEl = document.createElement('div');
    infoEl.className = 'note-detail-info';
    const infoBits = [];
    if (note.type && note.type !== App.NoteTypes.UNCLASSIFIED) {
      infoBits.push('<button type="button" class="note-detail-info__chip">' + note.type + '</button>');
    }
    infoBits.push('<span class="note-detail-info__hint">轻点标题或正文即可编辑</span>');
    infoEl.innerHTML = infoBits.join('');
    const detailTypeButton = infoEl.querySelector('.note-detail-info__chip');
    if (detailTypeButton) {
      detailTypeButton.addEventListener('click', (e) => {
        e.stopPropagation();
        this.openNoteTypePicker(note, () => this.renderDetail(params));
      });
    }
    content.appendChild(infoEl);

    // 正文（完整 HTML 直通渲染；点击就地编辑为 HTML 编辑器）
    const bodyEl = document.createElement('div');
    bodyEl.className = 'card note-detail-body note-detail-body--reading';
    bodyEl.setAttribute('data-tap-edit', '');
    // 查看态直接渲染保存的 HTML（v8.5.5 去块后不再逐块翻译，格式 100% 保真）
    bodyEl.innerHTML = note.content
      ? '<div class="note-render-pad note-html-body">' + note.content + '</div>'
      : '<div class="note-render-pad"><span style="color:var(--text-tertiary);">暂无内容，点击开始编辑</span></div>';
    bodyEl.addEventListener('click', (e) => this._editBodyInPlace(bodyEl, note, metaEl, e));
    content.appendChild(bodyEl);

    // 编辑时间
    const metaEl = document.createElement('div');
    metaEl.className = 'note-detail-meta';
    metaEl.textContent = '最后编辑于 ' + App.Utils.formatDateTime(note.updatedAt);
    content.appendChild(metaEl);

    // 关联错题
    if (note.linkedErrors && note.linkedErrors.length > 0) {
      const linkedSection = document.createElement('div');
      linkedSection.className = 'linked-section';
      linkedSection.innerHTML = `<div class="linked-section__title">关联错题（${note.linkedErrors.length}）</div>`;
      for (const errId of note.linkedErrors) {
        try {
          const err = await App.DB.get('errors', errId);
          if (err) {
            const errItem = document.createElement('div');
            errItem.style.cssText = 'padding:8px;margin-bottom:4px;background:var(--bg-tertiary);border-radius:var(--radius-sm);font-size:var(--font-sm);cursor:pointer;';
            errItem.textContent = App.Utils.truncate(err.question, 50);
            errItem.addEventListener('click', () => App.Router.navigate('error-detail?id=' + err.id));
            linkedSection.appendChild(errItem);
          }
        } catch (e) {}
      }
      content.appendChild(linkedSection);
    }

    // 手写笔记区域（点击可重新编辑，可隐藏但保留数据）
    const doodlePreview = document.createElement('div');
    doodlePreview.className = 'doodle-preview' + (note.doodleHidden ? ' doodle-preview--collapsed' : '');
    if (note.doodle && !note.doodleHidden) {
      doodlePreview.innerHTML =
        '<div class="doodle-preview__header">' +
          '<div class="doodle-preview__title">✍️ 手写笔记区域</div>' +
          '<button class="doodle-preview__hide" type="button" title="隐藏（数据仍保留）">✕</button>' +
        '</div>' +
        '<img class="doodle-preview__img" src="' + note.doodle + '" alt="手写笔记">';
      const hideBtn = doodlePreview.querySelector('.doodle-preview__hide');
      hideBtn.addEventListener('click', async (e) => {
        e.stopPropagation();
        note.doodleHidden = true;
        try { await App.DB.updateNote(note); } catch (err) {}
        this.renderDetail(params);
      });
    } else if (!note.doodle) {
      doodlePreview.innerHTML = '<div class="doodle-preview__empty">✍️ 暂无手写笔记，点击右上角铅笔图标添加</div>';
    }
    doodlePreview.addEventListener('click', () => this._openDoodle(note, params));
    content.appendChild(doodlePreview);

    container.appendChild(content);
  },

  // ===== 标题就地编辑（点击 → input → 失焦/回车自动保存并回查看） =====
  _editTitleInPlace(titleEl, note, metaEl) {
    if (this._titleEditing) return;
    this._titleEditing = true;
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'note-detail-title-input';
    input.value = note.title || '';
    titleEl.replaceWith(input);
    input.focus();
    try { input.setSelectionRange(input.value.length, input.value.length); } catch (e) {}

    const commit = () => {
      if (!this._titleEditing) return;
      this._titleEditing = false;
      const v = input.value.trim();
      if (v && v !== note.title) {
        note.title = v;
        this._saveNoteContent(note, note.content, { refreshMeta: metaEl });
      }
      // 就地恢复标题查看渲染（不重渲染整页，保留滚动位置）
      const restored = document.createElement('div');
      restored.className = 'note-detail-title';
      restored.textContent = note.title || '';
      restored.addEventListener('click', () => this._editTitleInPlace(restored, note, metaEl));
      input.replaceWith(restored);
    };
    input.addEventListener('blur', commit);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); input.blur(); }
    });
  },

  // ===== 正文就地编辑（点击 → 块编辑器 → 失焦/键盘收起自动保存回查看） =====
  _editBodyInPlace(bodyEl, note, metaEl, clickEvent) {
    if (this._bodyEditor) return;   // 已在编辑中，忽略重复进入
    const inst = this._bodyEditor = { note, metaEl, editorWrap: bodyEl, editor: null, exiting: false, _saveTimer: null };

    // 点击位置 → 渲染 HTML 中的行索引（尽力定位光标到点击处所在块）
    const targetIdx = this._resolveClickBlock(bodyEl, clickEvent);

    // 保留 .card 卡片容器（白底/圆角/内边距全程不变），仅清空内部内容挂入块编辑器
    // —— 切换时卡片外观零变化，不再出现「替换成无样式容器」导致的页面重排闪烁
    bodyEl.classList.add('note-detail-body--editing');
    bodyEl.innerHTML = '';

    // v8.5.5 彻底去块：正文用 HTML 直通编辑器（单连续富文本，保存 = innerHTML 原样直存）
    const editor = App.Components.htmlEditor(
      (typeof note.content === 'string' ? note.content : App.Utils.toNoteHtml(note.content)) || '',
      {
        placeholder: false,   // 用户要求去掉空白段占位文字
        onChange: (html) => {
          if (inst.countEl) inst.countEl.textContent = App.Utils.countHtmlText(html) + ' 字';
          this._debouncedBodySave(inst, html);
        }
      }
    );
    bodyEl.appendChild(editor.element);
    inst.editor = editor;

    // 字数标签：插入右上角按钮区（⋮ 三个点附近），编辑时实时更新
    const countEl = document.createElement('span');
    countEl.className = 'note-edit-count';
    countEl.textContent = App.Utils.countHtmlText((typeof note.content === 'string' ? note.content : '')) + ' 字';
    if (this._noteActionsEl && this._noteActionsEl.parentNode) {
      this._noteActionsEl.parentNode.insertBefore(countEl, this._noteActionsEl);
    }
    inst.countEl = countEl;

    // 光标定位到点击处（HTML 直通：聚焦编辑区，尽力定位到点击行附近）
    this._focusBlockAt(editor, targetIdx);

    // 失焦退出：点击编辑区外（排除格式栏/弹层）或键盘收起（移动端 focusout relatedTarget=null）
    // 底部悬浮格式栏（notion-toolbar / notion-mobile-toolbar）+ 格式/插入面板弹层（notion-mobile-sheet*）点击不退出编辑
    const TOOLBAR = '.notion-toolbar, .notion-mobile-toolbar, .slash-menu, .block-menu, .block-sheet, .format-sheet, [data-mobile-toolbar], .actionsheet-overlay, .modal-overlay, .notion-mobile-sheet-overlay, .notion-mobile-sheet';
    setTimeout(() => {
      inst._docDown = (e) => {
        const t = e.target;
        if (!t || bodyEl.contains(t)) return;
        if (t.closest && t.closest(TOOLBAR)) return;
        this._exitBodyEdit(inst);
      };
      document.addEventListener('mousedown', inst._docDown, true);

      inst._focusOut = (e) => {
        if (bodyEl.contains(e.target)) return;
        if (e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest(TOOLBAR)) return;
        // 延迟小步：避免与「点击格式栏按钮」的焦点转移冲突
        setTimeout(() => this._exitBodyEdit(inst), 150);
      };
      document.addEventListener('focusout', inst._focusOut, true);
    }, 0);
  },

  // ===== 退出正文编辑：取最新 JSON 块 → 保存 → 复用原卡片容器恢复查看渲染 =====
  _exitBodyEdit(inst) {
    if (!inst || inst.exiting) return;
    inst.exiting = true;
    const data = inst.editor
      ? (typeof inst.editor.getHtml === 'function' ? inst.editor.getHtml() : inst.editor.getEditorData())
      : (typeof inst.note.content === 'string' ? inst.note.content : App.Utils.toNoteHtml(inst.note.content));
    this._clearBodyDebounce(inst);
    this._saveNoteContent(inst.note, data, { refreshMeta: inst.metaEl }).finally(() => {
      // 复用原 .card 卡片容器恢复查看渲染（容器从未被替换，卡片外观与滚动位置均不跳动）
      const bodyEl = inst.editorWrap;
      if (bodyEl && bodyEl.parentNode) {
        bodyEl.classList.remove('note-detail-body--editing');
        bodyEl.innerHTML = data
          ? '<div class="note-render-pad note-html-body">' + data + '</div>'
          : '<div class="note-render-pad"><span style="color:var(--text-tertiary);">暂无内容，点击开始编辑</span></div>';
        bodyEl.addEventListener('click', (e) => this._editBodyInPlace(bodyEl, inst.note, inst.metaEl, e));
      }
      // 清理全局监听
      if (inst._docDown) document.removeEventListener('mousedown', inst._docDown, true);
      if (inst._focusOut) document.removeEventListener('focusout', inst._focusOut, true);
      // 移除右上角字数标签
      if (inst.countEl && inst.countEl.parentNode) inst.countEl.parentNode.removeChild(inst.countEl);
      if (this._bodyEditor === inst) this._bodyEditor = null;
    });
  },

  // ===== 双保险保存：防抖（2 秒）+ 失焦强制保存 =====
  _debouncedBodySave(inst, content) {
    if (inst._saveTimer) clearTimeout(inst._saveTimer);
    inst._saveTimer = setTimeout(() => {
      inst._saveTimer = null;
      if (inst.exiting) return;
      this._saveNoteContent(inst.note, content, { refreshMeta: inst.metaEl });
    }, 2000);
  },
  _clearBodyDebounce(inst) {
    if (inst && inst._saveTimer) { clearTimeout(inst._saveTimer); inst._saveTimer = null; }
  },

  // ===== 统一保存：写 DB（保留 linkedErrors/linkedReviews/doodle）+ 刷新「最后编辑于」 =====
  async _saveNoteContent(note, content, opts) {
    const o = opts || {};
    try {
      const existing = note.id ? await App.DB.get('notes', note.id) : null;
      const payload = {
        id: note.id, subject: note.subject || '', module: note.module || '',
        knowledgePoint: note.knowledgePoint || '', type: note.type || App.NoteTypes.UNCLASSIFIED, title: note.title || '未命名笔记',
        content: content || '',
        linkedErrors: note.linkedErrors || [],
        linkedReviews: existing ? existing.linkedReviews || [] : [],
        doodle: note.doodle, doodleHidden: note.doodleHidden,
        updatedAt: new Date().toISOString()
      };
      await App.DB.updateNote(payload);
      note.content = content || '';
      note.updatedAt = payload.updatedAt;
      if (o.refreshMeta && o.refreshMeta.textContent) {
        o.refreshMeta.textContent = '最后编辑于 ' + App.Utils.formatDateTime(payload.updatedAt);
      }
      return true;
    } catch (e) {
      return false;
    }
  },

  // ===== 点击位置 → 渲染 HTML 行索引（供块编辑器定位光标） =====
  _resolveClickBlock(bodyEl, e) {
    if (!bodyEl || !e) return 0;
    try {
      const y = e.clientY;
      const rows = Array.from(bodyEl.querySelectorAll('p, ul, ol, h1, h2, h3, h4, blockquote, pre, hr, .mformula, .md-preview-blank'));
      if (!rows.length) return 0;
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i].getBoundingClientRect();
        if (y <= r.bottom) return i;
      }
      return rows.length - 1;
    } catch (err) { return 0; }
  },

  // ===== 聚焦块编辑器到指定块（光标置于块末尾） =====
  // 防抖动（v8.4.15）：① focus({preventScroll:true}) 阻止浏览器自动滚动 ② rAF 延迟到布局稳定后再聚焦，
  // 避免「编辑器刚插入 DOM、布局未稳定时基于旧布局自动滚动」导致点击进入编辑时页面跳动
  _focusBlockAt(editor, idx) {
    if (!editor || !editor.element) return;
    try {
      const requestFrame = (typeof requestAnimationFrame === 'function')
        ? requestAnimationFrame : function (cb) { setTimeout(cb, 0); };
      requestFrame(() => {
        try {
          let editable = null;
          // v8.5.5 彻底去块：htmlEditor 为单连续富文本区，聚焦到点击行附近（第 idx 个段落）
          if (editor.area) {
            const paras = Array.from(editor.area.querySelectorAll('p, h1, h2, h3, li, blockquote, pre'));
            editable = paras.length ? paras[Math.max(0, Math.min(idx || 0, paras.length - 1))] : editor.area;
          } else {
            // 旧块编辑器：聚焦到第 idx 个块
            const blocks = editor.element.querySelectorAll('.notion-block');
            if (!blocks.length) return;
            const i = Math.max(0, Math.min(idx || 0, blocks.length - 1));
            editable = blocks[i].querySelector('.notion-editable') || blocks[i];
          }
          try {
            editable.focus({ preventScroll: true });
          } catch (e1) {
            editable.focus();
          }
          const sel = window.getSelection();
          const range = document.createRange();
          range.selectNodeContents(editable);
          range.collapse(false);
          sel.removeAllRanges();
          sel.addRange(range);
          // 题目/返回栏采用 sticky 顶部布局，光标若落在其下方，先把当前行
          // 放到可视区中部，避免用户开始输入时仍被顶部区域盖住。
          const sticky = document.querySelector('.page-sticky, .page-header');
          const stickyRect = sticky && sticky.getBoundingClientRect ? sticky.getBoundingClientRect() : null;
          const editorRect = editable.getBoundingClientRect ? editable.getBoundingClientRect() : null;
          if (editorRect && stickyRect && editorRect.top < stickyRect.bottom + 12) {
            editable.scrollIntoView({ block: 'center', inline: 'nearest' });
          }
        } catch (e2) {}
      });
    } catch (err) {}
  },


  // ===== 打开手写笔记覆盖层（铅笔图标触发） =====
  _openDoodle(note, params) {
    if (note.doodleHidden) {
      note.doodleHidden = false;
      App.DB.updateNote(note).catch(() => {});
    }
    App.Components.doodleOverlay({
      initial: note.doodle || null,
      onChange: async (dataURL) => {
        note.doodle = dataURL || null;
        try { await App.DB.updateNote(note); } catch (e) {}
      }
    }).then(async (dataURL) => {
      note.doodle = dataURL || null;
      try { await App.DB.updateNote(note); } catch (e) {}
      this.renderDetail(params);
    });
  },

  // ===== 详情页右上角三点菜单 =====
  async _showDetailMenu(note) {
    const action = await App.Components.actionSheet([
      { label: '🏷️ 修改标签', value: 'changeType' },
      { label: '📋 复制副本', value: 'duplicate' },
      { label: '📂 移动位置', value: 'move' },
      { label: '🗑️ 删除', value: 'delete' }
    ], note.title);
    if (!action) return;

    switch (action) {
      case 'changeType':
        await this.openNoteTypePicker(note, () => this.renderDetail(Object.assign({}, this._detailParams, { id: note.id })));
        break;
      case 'delete': {
        const confirmed = await App.Components.confirm(
          '删除笔记',
          '确定删除「' + note.title + '」？此操作不可撤销。',
          '删除', '取消', true
        );
        if (confirmed) {
          await App.DB.remove('notes', note.id);
          App.Components.toast('已删除', 'success');
          App.Router.navigate('notes');
        }
        break;
      }
      case 'move': {
        // 级联选择：科目 → 模块 → 考点
        const sOpt = App.Constants.SUBJECTS.map(s => ({
          icon: '<span style="font-size:22px">' + s.icon + '</span>',
          label: s.name,
          desc: '选择「' + s.name + '」模块',
          value: s.name
        }));
        const newSubject = await App.Components.centeredPicker(sOpt, '移动到', '选择目标科目');
        if (!newSubject) return;

        const mods = App.Constants.getModules(newSubject);
        const mOpt = mods.map(m => ({ icon: '📂', label: m, desc: newSubject + ' — ' + m, value: m }));
        const newModule = await App.Components.centeredPicker(mOpt, '选择模块', '选择「' + newSubject + '」下的模块');
        if (!newModule) return;

        const kps = App.Tags.getKnowledgePointSuggestions(newModule);
        const kOpt = kps.map(k => ({ icon: '🏷️', label: k, desc: newModule + ' — ' + k, value: k }));
        kOpt.push({ icon: '✏️', label: '+ 自定义考点', desc: '手动输入新考点名称', value: '__custom__' });
        let newKp = await App.Components.centeredPicker(kOpt, '选择考点', '选择或自定义「' + newModule + '」的考点', { kind: 'kp', module: newModule });
        if (newKp === '__custom__') {
          const name = prompt('输入自定义考点名称：');
          if (name && name.trim()) { newKp = name.trim(); App.Tags.addKnowledgePoint(newModule, name.trim()); }
        }
        if (!newKp) return;

        // 更新笔记分类
        note.subject = newSubject;
        note.module = newModule;
        note.knowledgePoint = newKp;
        note.updatedAt = Date.now();
        await App.DB.updateNote(note);
        App.Components.toast('已移动到 ' + newSubject + ' › ' + newModule + ' › ' + newKp, 'success');
        // 刷新当前页面以显示新分类
        this.renderDetail({ id: note.id });
        break;
      }
      case 'duplicate': {
        const copy = JSON.parse(JSON.stringify(note));
        delete copy.id;
        copy.title = (copy.title || '未命名笔记') + ' 副本';
        copy.createdAt = Date.now();
        copy.updatedAt = Date.now();
        const newId = await App.DB.addNote(copy);
        App.Components.toast('已创建副本', 'success');
        // 跳转到新副本的详情页
        App.Router.navigate('note-detail?id=' + newId);
        break;
      }
    }
  },

  // ===== 新建/编辑笔记表单 =====
  renderForm(params) {
    const container = document.getElementById('page-note-form');
    container.innerHTML = '';

    let isEdit = !!params.id;
    const returnRoute = params && typeof params.returnTo === 'string' && /^(?:errors|notes)(?:\?|$)/.test(params.returnTo)
      ? params.returnTo
      : 'notes';

    let formData = {
      subject: params.subject || '',
      module: '',
      knowledgePoint: '',
      type: params.type || params.noteType || params.tag || '',
      title: '',
      content: '',
      linkedErrors: []
    };
    let removeDraftAutosave = null;
    const saveFormDraftNow = () => {
      try {
        if (formData._getContent) formData.content = formData._getContent();
        App.Draft.saveForm('note', formData._formId, JSON.parse(JSON.stringify(formData)));
      } catch (e) {}
    };

    const loadAndRender = async () => {
      if (isEdit) {
        const note = await App.DB.get('notes', params.id);
        if (note) {
          formData = {
            subject: note.subject || '',
            module: note.module || '',
            knowledgePoint: note.knowledgePoint || '',
            type: note.type || App.NoteTypes.UNCLASSIFIED,
            title: note.title || '',
            content: note.content || '',
            linkedErrors: note.linkedErrors || [],
            id: note.id
          };
        }
        formData._formId = params.id;
      } else {
        // 新建/续编：仅当 sessionStorage 记录着「同一篇正在录入」的 id 时才续编；否则一律空白。
        const fid = App.Draft.getFormId('note');
        if (fid) {
          if (App.Draft.formIdIsTemp(fid)) {
            // 尚未建成 DB 记录：从 localStorage 草稿续编
            const d = App.Draft.loadForm('note', fid);
            if (d) Object.assign(formData, d);
            formData._formId = fid;
          } else {
            // 已是真实记录 id：从 DB 续编（权威，不会重复建记录）
            const note = await App.DB.get('notes', fid);
            if (note) {
              isEdit = true;
              formData = {
                subject: note.subject || '', module: note.module || '',
                knowledgePoint: note.knowledgePoint || '', type: note.type || App.NoteTypes.UNCLASSIFIED, title: note.title || '',
                content: note.content || '', linkedErrors: note.linkedErrors || [],
                id: note.id
              };
              formData._formId = fid;
            }
          }
        }
        if (!formData._formId) {
          formData._formId = App.Draft.newTempId();
          App.Draft.setFormId('note', formData._formId);
        }
        // URL 参数 subject/module 优先级高于草稿（用户从某科目点新建）
        if (params.subject) {
          formData.subject = params.subject;
          if (params.module && App.Constants.getModules(params.subject).indexOf(params.module) !== -1) {
            formData.module = params.module;
          }
        }
        // 仍未指定科目时，默认带入上次选择的科目-模块
        if (!formData.subject) {
          const last = App.Utils.rememberSelect.get('note');
          if (last && last.subject) {
            formData.subject = last.subject;
            formData.module = (last.module && App.Constants.getModules(last.subject).indexOf(last.module) !== -1) ? last.module : '';
          }
        }
        // 标签和科目/模块一样：从标签筛选页进入时优先带入 URL 标签，
        // 否则使用当前模块上次使用的标签，最后回退到“未分类”。
        if (!formData.type) {
          const last = App.Utils.rememberSelect.get('note');
          const sameLastContext = !!last
            && last.subject === formData.subject
            && (last.module || '') === (formData.module || '');
          const candidate = params.type || params.noteType || params.tag
            || (sameLastContext && last.type) || '';
          const types = formData.subject
            ? App.NoteTypes.getForContext(formData.subject, formData.module)
            : [];
          if (candidate === App.NoteTypes.UNCLASSIFIED || types.some(t => t.name === candidate)) {
            formData.type = candidate;
          } else {
            formData.type = App.NoteTypes.UNCLASSIFIED;
          }
        }
      }
      buildForm();
    };

    const buildForm = () => {
      // 重建前先把编辑器内容同步回 formData，避免重渲染丢失草稿
      if (formData._getContent) {
        try { formData.content = formData._getContent(); } catch (e) {}
      }
      if (removeDraftAutosave) {
        try { removeDraftAutosave(); } catch (e) {}
        removeDraftAutosave = null;
      }
      container.innerHTML = '';

      container.appendChild(App.Components.pageHeader(
        isEdit ? '编辑笔记' : '新建笔记',
        '保存',
        async () => {
          if (!formData.title.trim()) {
            App.Components.toast('请输入笔记标题', 'error');
            return;
          }
          await submitForm();
        }
      ));

      const form = document.createElement('div');
      form.className = 'form-page';

      // ===== 标题（普通输入框，无灰色占位） =====
      const titleInput = document.createElement('input');
      titleInput.type = 'text';
      titleInput.className = 'note-title-input';
      titleInput.placeholder = '请输入笔记标题…';
      titleInput.value = formData.title || '';
      titleInput.addEventListener('input', () => { formData.title = titleInput.value; });
      form.appendChild(titleInput);

      // ===== 笔记类型选择（对齐画布：类型chips，可多选? 单选一个类型） =====
      const typeWrap = document.createElement('div');
      typeWrap.className = 'note-type-field';
      typeWrap.innerHTML = '<div class="note-type-kw">标签（当前模块）</div>';
      const chipsBox = document.createElement('div');
      chipsBox.className = 'note-modchips';
      const renderTypeChips = () => {
        chipsBox.innerHTML = '';
        const hasContext = !!(formData.subject && (
          formData.module || App.Constants.isFlatSubject(formData.subject)
        ));
        const types = hasContext
          ? App.NoteTypes.getForContext(formData.subject, formData.module)
          : [];
        if (formData.type && !types.some(t => t.name === formData.type)) {
          // 旧笔记可能引用已停用/历史标签，保留其当前值，避免编辑时无声丢失。
          types.push({
            name: formData.type,
            color: App.NoteTypes.getColor(formData.type, formData.subject, formData.module),
            enabled: false
          });
        }
        const mk = (label, active, onClick) => {
          const b = document.createElement('button');
          b.type = 'button';
          b.className = 'note-modchip note-modchip--type' + (active ? ' active' : '');
          b.textContent = label;
          b.addEventListener('click', onClick);
          return b;
        };
        chipsBox.appendChild(mk(App.NoteTypes.UNCLASSIFIED, formData.type === App.NoteTypes.UNCLASSIFIED, () => { formData.type = App.NoteTypes.UNCLASSIFIED; renderTypeChips(); }));
        types.forEach(t => {
          const c = t.color;
          const isActive = formData.type === t.name;
          const b = document.createElement('button');
          b.type = 'button';
          b.className = 'note-modchip note-modchip--type' + (isActive ? ' active' : '');
          b.style.cssText = isActive ? ('background:' + hexToRgba3(c, 0.14) + ';color:' + c + ';') : '';
          b.textContent = t.enabled === false ? (t.name + '（历史）') : t.name;
          b.disabled = t.enabled === false && !isActive;
          b.addEventListener('click', () => { formData.type = t.name; renderTypeChips(); });
          chipsBox.appendChild(b);
        });
        if (!hasContext) {
          const hint = document.createElement('span');
          hint.className = 'note-type-scope-hint';
          hint.textContent = '选择科目和模块后显示可用标签';
          chipsBox.appendChild(hint);
        }
      };
      renderTypeChips();
      typeWrap.appendChild(chipsBox);
      form.appendChild(typeWrap);

      function hexToRgba3(hex, a) {
        const h = String(hex).replace('#', '');
        if (/^[0-9a-fA-F]{6}$/.test(h)) return 'rgba(' + [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)).join(',') + ',' + a + ')';
        return 'rgba(0,102,204,' + a + ')';
      }

      // ===== 单一分类选择框（科目 › 模块 › 考点 级联） =====
      const catSelector = document.createElement('button');
      catSelector.type = 'button';
      catSelector.className = 'note-cat-selector';
      const updateCatLabel = () => {
        const parts = [formData.subject, formData.module, formData.knowledgePoint].filter(Boolean);
        catSelector.innerHTML = parts.length
          ? `<span class="note-cat-icon">🏷️</span><span class="note-cat-text">${parts.join(' › ')}</span><span class="note-cat-clear" title="清除分类">✕</span>`
          : `<span class="note-cat-icon">🏷️</span><span class="note-cat-text note-cat-placeholder">+ 选择科目 / 模块 / 考点</span>`;
      };
      catSelector.addEventListener('click', async (e) => {
        if (e.target.classList.contains('note-cat-clear')) {
          formData.subject = ''; formData.module = ''; formData.knowledgePoint = '';
          formData.type = App.NoteTypes.UNCLASSIFIED;
          updateCatLabel();
          renderTypeChips();
          return;
        }
        // 科目选择（居中弹窗）
        const sOpt = App.Constants.SUBJECTS.map(s => ({
          icon: '<span style="font-size:22px">' + s.icon + '</span>',
          label: s.name,
          desc: App.Constants.isFlatSubject(s.name) ? '选择「' + s.name + '」考点' : '选择「' + s.name + '」模块',
          value: s.name
        }));
        const s = await App.Components.centeredPicker(sOpt, '选择科目', '请先选择考试科目，再选择具体模块和考点');
        if (!s) return;
        formData.subject = s; formData.module = ''; formData.knowledgePoint = '';

        // 扁平科目（资料分析）：无模块层，直接选考点
        if (App.Constants.isFlatSubject(s)) {
          const kps = App.Tags.getSubjectKnowledgePoints(s);
          const kOpt = kps.map(k => ({
            icon: '🏷️',
            label: k,
            desc: s + ' — ' + k,
            value: k
          }));
          kOpt.push({ icon: '✏️', label: '+ 自定义考点', desc: '手动输入新考点名称', value: '__custom__' });
          const k = await App.Components.centeredPicker(kOpt, '选择考点', '选择或自定义「' + s + '」的考点', { kind: 'kp', module: s });
          if (k === '__custom__') {
            const name = prompt('输入自定义考点名称：');
            if (name && name.trim()) { formData.knowledgePoint = name.trim(); App.Tags.addSubjectKnowledgePoint(s, name.trim()); }
          } else if (k) { formData.knowledgePoint = k; }
          updateCatLabel();
          renderTypeChips();
          return;
        }

        // 模块选择
        const mods = App.Constants.getModules(s);
        const mOpt = mods.map(m => ({
          icon: '📂',
          label: m,
          desc: s.name + ' — ' + m,
          value: m
        }));
        const m = await App.Components.centeredPicker(mOpt, '选择模块', '选择「' + s + '」下的知识模块');
        if (!m) { updateCatLabel(); renderTypeChips(); return; }
        formData.module = m; formData.knowledgePoint = '';

        // 考点选择
        const kps = App.Tags.getKnowledgePointSuggestions(m);
        const kOpt = kps.map(k => ({
          icon: '🏷️',
          label: k,
          desc: m + ' — ' + k,
          value: k
        }));
        kOpt.push({ icon: '✏️', label: '+ 自定义考点', desc: '手动输入新考点名称', value: '__custom__' });
        const k = await App.Components.centeredPicker(kOpt, '选择考点', '选择或自定义「' + m + '」的考点', { kind: 'kp', module: m });
        if (k === '__custom__') {
          const name = prompt('输入自定义考点名称：');
          if (name && name.trim()) { formData.knowledgePoint = name.trim(); App.Tags.addKnowledgePoint(m, name.trim()); }
        } else if (k) { formData.knowledgePoint = k; }
        updateCatLabel();
        renderTypeChips();
      });
      updateCatLabel();
      form.appendChild(catSelector);

      // ===== 正文 HTML 直通编辑器（v8.5.5 去块；所见即所得，保存 = innerHTML 直存）=====
      // 历史数据（JSON 块 / 旧 MD）先迁移为 HTML
      const contentHtml = App.Utils.toNoteHtml(formData.content);
      if (formData.content !== contentHtml) formData.content = contentHtml;
      const editor = App.Components.htmlEditor(contentHtml, {
        placeholder: false,
        onChange: function (html) {
          formData.content = html;
          debouncedSaveToDB();
        }
      });
      form.appendChild(editor.element);
      formData._getContent = editor.getHtml;

      // 关联错题
      const linkGroup = document.createElement('div');
      linkGroup.className = 'form-group';
      const linkLabel = document.createElement('label');
      linkLabel.className = 'form-label';
      linkLabel.textContent = '关联错题（可选）';
      linkGroup.appendChild(linkLabel);

      const linkBtn = document.createElement('button');
      linkBtn.className = 'btn btn--outline btn--sm';
      linkBtn.textContent = '选择错题';
      linkBtn.addEventListener('click', async () => {
        const errors = await App.DB.getErrors({ subject: formData.subject });
        if (errors.length === 0) {
          App.Components.toast('该科目暂无错题', 'error');
          return;
        }

        const options = errors.map(e => ({
          label: App.Utils.truncate(e.question, 30),
          value: e.id
        }));
        const selected = await App.Components.actionSheet(options, '选择关联错题');
        if (selected && !formData.linkedErrors.includes(selected)) {
          formData.linkedErrors.push(selected);
          renderLinkedErrors();
          saveFormDraftNow();
          debouncedSaveToDB();
        }
      });
      linkGroup.appendChild(linkBtn);

      // 只更新关联错题列表，不销毁编辑器 DOM，避免格式、光标和滚动位置丢失。
      const linkedList = document.createElement('div');
      linkedList.style.cssText = 'margin-top:8px;';
      const renderLinkedErrors = () => {
        linkedList.innerHTML = '';
        if (!formData.linkedErrors.length) {
          linkedList.style.display = 'none';
          return;
        }
        linkedList.style.display = '';
        formData.linkedErrors.forEach((errId) => {
          const row = document.createElement('div');
          row.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:4px 0;font-size:var(--font-sm);';
          const text = document.createElement('span');
          text.style.color = 'var(--text-secondary)';
          text.textContent = '关联错题 ' + String(errId).slice(-6);
          row.appendChild(text);
          const removeBtn = document.createElement('button');
          removeBtn.className = 'btn--text';
          removeBtn.type = 'button';
          removeBtn.textContent = '移除';
          removeBtn.addEventListener('click', () => {
            formData.linkedErrors = formData.linkedErrors.filter(id => id !== errId);
            renderLinkedErrors();
            saveFormDraftNow();
            debouncedSaveToDB();
          });
          row.appendChild(removeBtn);
          linkedList.appendChild(row);
        });
      };
      linkGroup.appendChild(linkedList);
      renderLinkedErrors();

      form.appendChild(linkGroup);

      container.appendChild(form);

      // 草稿自动暂存（localStorage 兜底，按表单 id 隔离，避免旧草稿串入新笔记）
      removeDraftAutosave = App.Draft.autoSaveForm('note', formData._formId, container, function () {
        if (formData._getContent) { try { formData.content = formData._getContent(); } catch (e) {} }
        return JSON.parse(JSON.stringify(formData));
      });
    };

    // 防抖自动保存到 DB（2 秒无操作后执行）
    let _saveTimer = null;
    let _saving = false;
    function debouncedSaveToDB() {
      clearTimeout(_saveTimer);
      _saveTimer = setTimeout(async () => {
        if (_saving) return;
        if (!formData.title.trim()) return;
        _saving = true;
        try { await submitFormInternal(); } catch (e) {}
        _saving = false;
      }, 2000);
    }

    // 核心保存逻辑
    const submitFormInternal = async () => {
      if (formData._getContent) formData.content = formData._getContent();
      formData.type = formData.type || App.NoteTypes.UNCLASSIFIED;
      App.Utils.rememberSelect.set('note', formData.subject, formData.module, formData.type);
      if (!formData.subject || !formData.title.trim()) return;

      if (isEdit && formData.id) {
        const existing = await App.DB.get('notes', formData.id);
        await App.DB.updateNote({
          id: formData.id, subject: formData.subject, module: formData.module,
          knowledgePoint: formData.knowledgePoint, type: formData.type, title: formData.title,
          content: formData.content, linkedErrors: formData.linkedErrors,
          linkedReviews: existing ? existing.linkedReviews || [] : [],
          updatedAt: new Date().toISOString()
        });
      } else {
        if (!formData.id) {
          formData.id = await App.DB.addNote({
            subject: formData.subject, module: formData.module,
            knowledgePoint: formData.knowledgePoint, type: formData.type,
            title: formData.title || '未命名笔记', content: formData.content,
            linkedErrors: formData.linkedErrors, linkedReviews: [],
            updatedAt: new Date().toISOString()
          });
          isEdit = true;
        } else {
          await App.DB.updateNote({
            id: formData.id, subject: formData.subject, module: formData.module,
            knowledgePoint: formData.knowledgePoint, type: formData.type, title: formData.title,
            content: formData.content, linkedErrors: formData.linkedErrors,
            linkedReviews: [], updatedAt: new Date().toISOString()
          });
        }
      }
    };

    // 手动/离开时强制保存
    const submitForm = async () => {
      clearTimeout(_saveTimer);
      if (formData._getContent) formData.content = formData._getContent();
      if (!formData.subject) { App.Components.toast('请选择科目', 'error'); return; }
      if (!formData.title.trim()) { App.Components.toast('请输入标题', 'error'); return; }
      try {
        await submitFormInternal();
        App.Components.toast('已保存 ✓', 'success');
        App.Draft.clearForm('note');
        App.Router.navigate(returnRoute);
      } catch (e) { App.Components.toast('保存失败', 'error'); }
    };

    loadAndRender();
  },

  _getNoteTypeContext(params) {
    const p = params || {};
    const errorState = App.Pages.Errors && App.Pages.Errors.state ? App.Pages.Errors.state : {};
    const firstSubject = App.Constants.SUBJECTS[0] ? App.Constants.SUBJECTS[0].name : '';
    let subject = p.subject || errorState.subject || firstSubject;
    if (!App.Constants.SUBJECTS.some(s => s.name === subject)) subject = firstSubject;
    const modules = App.Constants.getModules(subject);
    const flat = App.Constants.isFlatSubject(subject);
    let module = flat ? '' : (p.module || errorState.module || modules[0] || '');
    if (!flat && modules.indexOf(module) === -1) module = modules[0] || '';
    return { subject, module, modules, flat };
  },

  _noteTypeManageRoute(context) {
    const query = [];
    if (context && context.subject) query.push('subject=' + encodeURIComponent(context.subject));
    if (context && context.module) query.push('module=' + encodeURIComponent(context.module));
    return 'note-type-manage' + (query.length ? '?' + query.join('&') : '');
  },

  _noteTypeFormRoute(context, name) {
    const query = [];
    if (context && context.subject) query.push('subject=' + encodeURIComponent(context.subject));
    if (context && context.module) query.push('module=' + encodeURIComponent(context.module));
    if (name) query.push('name=' + encodeURIComponent(name));
    return 'note-type-form' + (query.length ? '?' + query.join('&') : '');
  },

  // ===== 笔记类型管理页（A4，对齐画布 8:170：返回+标题+说明+类型列表+新增按钮） =====
  async renderTypeManage(params) {
    const container = document.getElementById('page-note-type-manage');
    container.innerHTML = '';
    const context = this._getNoteTypeContext(params);
    await this.loadData();

    container.appendChild(App.Components.pageHeader(
      '笔记类型',
      '', () => App.Router.navigate('settings')
    ));

    const body = document.createElement('div');
    body.className = 'ntype-manage-body';

    const hint = document.createElement('div');
    hint.className = 'ntype-manage-hint';
    hint.textContent = '先选择科目和模块，下面的标签只对当前范围生效';
    body.appendChild(hint);

    const selectors = document.createElement('div');
    selectors.className = 'ntype-context-selectors';
    const subjectField = document.createElement('label');
    subjectField.className = 'ntype-context-field';
    subjectField.innerHTML = '<span>选择科目</span>';
    const subjectSelect = document.createElement('select');
    App.Constants.SUBJECTS.forEach(s => {
      const option = document.createElement('option');
      option.value = s.name;
      option.textContent = s.name;
      option.selected = s.name === context.subject;
      subjectSelect.appendChild(option);
    });
    subjectField.appendChild(subjectSelect);
    selectors.appendChild(subjectField);

    const moduleField = document.createElement('label');
    moduleField.className = 'ntype-context-field';
    moduleField.innerHTML = '<span>选择模块</span>';
    const moduleSelect = document.createElement('select');
    const buildModuleOptions = () => {
      moduleSelect.innerHTML = '';
      const isFlat = App.Constants.isFlatSubject(subjectSelect.value);
      if (isFlat) {
        const option = document.createElement('option');
        option.value = '';
        option.textContent = '科目级标签';
        moduleSelect.appendChild(option);
        moduleSelect.disabled = true;
        return;
      }
      moduleSelect.disabled = false;
      App.Constants.getModules(subjectSelect.value).forEach(mod => {
        const option = document.createElement('option');
        option.value = mod;
        option.textContent = mod;
        option.selected = mod === context.module;
        moduleSelect.appendChild(option);
      });
    };
    buildModuleOptions();
    moduleField.appendChild(moduleSelect);
    selectors.appendChild(moduleField);
    body.appendChild(selectors);

    const goToContext = () => {
      const next = {
        subject: subjectSelect.value,
        module: App.Constants.isFlatSubject(subjectSelect.value) ? '' : moduleSelect.value
      };
      App.Router.navigate(this._noteTypeManageRoute(next));
    };
    subjectSelect.addEventListener('change', () => {
      const nextModules = App.Constants.getModules(subjectSelect.value);
      if (!App.Constants.isFlatSubject(subjectSelect.value) && nextModules.length) {
        context.module = nextModules[0];
      } else {
        context.module = '';
      }
      buildModuleOptions();
      goToContext();
    });
    moduleSelect.addEventListener('change', goToContext);

    const scopeTitle = document.createElement('div');
    scopeTitle.className = 'ntype-scope-title';
    scopeTitle.textContent = context.subject + (context.module ? ' / ' + context.module : '');
    body.appendChild(scopeTitle);

    const listBox = document.createElement('div');
    listBox.className = 'ntype-list';
    const renderRows = () => {
      listBox.innerHTML = '';
      const types = App.NoteTypes.getForContextAll(context.subject, context.module);
      const noteMatches = (n) => n.subject === context.subject && (
        context.module ? n.module === context.module : !n.module
      );
      if (!types.length) {
        const empty = document.createElement('div');
        empty.className = 'ntype-empty';
        empty.textContent = '暂无标签，点击下方新增';
        listBox.appendChild(empty);
        return;
      }
      types.forEach((t, idx) => {
        const count = (this.state.allNotes || []).filter(n => noteMatches(n) && n.type === t.name).length;
        const row = document.createElement('div');
        row.className = 'ntype-row' + (t.enabled === false ? ' is-disabled' : '');
        const left = document.createElement('div');
        left.className = 'ntype-row__left';
        const handle = document.createElement('span');
        handle.className = 'ntype-drag-handle';
        handle.textContent = '☷';
        const dot = document.createElement('span');
        dot.className = 'ntype-dot';
        dot.style.background = t.color;
        const name = document.createElement('span');
        name.className = 'ntype-name';
        name.textContent = t.name;
        left.appendChild(handle); left.appendChild(dot); left.appendChild(name);
        row.appendChild(left);

        const right = document.createElement('div');
        right.className = 'ntype-row__right';
        const num = document.createElement('span');
        num.className = 'ntype-count';
        num.textContent = count + ' 篇';
        right.appendChild(num);
        const op = (label, title, className, onClick) => {
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'ntype-op' + (className ? ' ' + className : '');
          btn.title = title;
          btn.textContent = label;
          btn.addEventListener('click', (e) => { e.stopPropagation(); onClick(); });
          right.appendChild(btn);
        };
        op('↑', '上移', '', () => { if (App.NoteTypes.moveForContext(context.subject, context.module, t.name, 'up')) renderRows(); });
        op('↓', '下移', '', () => { if (App.NoteTypes.moveForContext(context.subject, context.module, t.name, 'down')) renderRows(); });
        op('编辑', '编辑标签', '', () => this.openNoteTypeEditor(context, t.name, renderRows));
        op(t.enabled === false ? '启用' : '停用', t.enabled === false ? '启用标签' : '停用标签', t.enabled === false ? '' : 'ntype-op--danger', async () => {
          if (t.enabled !== false) {
            const ok = await App.Components.confirm('停用标签', '停用后，新建笔记时不会再显示「' + t.name + '」，已有笔记仍会保留。确定继续吗？', '停用', '取消', true);
            if (!ok) return;
          }
          App.NoteTypes.setEnabledForContext(context.subject, context.module, t.name, t.enabled === false);
          renderRows();
        });
        op('删除', '删除标签', 'ntype-op--danger', async () => {
          const count = (this.state.allNotes || []).filter(n => noteMatches(n) && n.type === t.name).length;
          const ok = await App.Components.confirm(
            '删除标签',
            '删除「' + t.name + '」后，' + count + ' 篇相关笔记会转为“未分类”，笔记内容不会删除。确定继续吗？',
            '删除', '取消', true
          );
          if (!ok) return;
          if (!App.NoteTypes.removeForContext(context.subject, context.module, t.name)) {
            App.Components.toast('标签删除失败', 'error'); return;
          }
          try {
            const notes = await App.DB.getNotes();
            for (const note of notes) {
              if (noteMatches(note) && note.type === t.name) {
                note.type = App.NoteTypes.UNCLASSIFIED;
                await App.DB.updateNote(note);
              }
            }
          } catch (e) { /* 配置已删除，笔记同步失败时下次可继续整理 */ }
          App.Components.toast('标签已删除', 'success');
          renderRows();
        });
        row.appendChild(right);
        row.addEventListener('click', () => this.openNoteTypeEditor(context, t.name, renderRows));
        listBox.appendChild(row);
        if (idx < types.length - 1) {
          const sep = document.createElement('div');
          sep.className = 'ntype-sep';
          listBox.appendChild(sep);
        }
      });
    };
    renderRows();
    body.appendChild(listBox);

    const addBtn = document.createElement('button');
    addBtn.type = 'button';
    addBtn.className = 'ntype-add';
    addBtn.textContent = '+ 新增标签';
    addBtn.addEventListener('click', () => this.openNoteTypeEditor(context, '', renderRows));
    body.appendChild(addBtn);

    const footerHint = document.createElement('div');
    footerHint.className = 'ntype-manage-hint ntype-manage-hint--footer';
    footerHint.textContent = '删除标签不会删除笔记，相关笔记会转为“未分类”；标签只在当前科目和模块内生效。';
    body.appendChild(footerHint);

    container.appendChild(body);
  },

  // ===== 新增/编辑笔记类型页（A5/A6，对齐画布 10:1：名称+色板+预览+保存） =====
  async renderTypeForm(params) {
    const container = document.getElementById('page-note-type-form');
    container.innerHTML = '';
    const context = this._getNoteTypeContext(params);
    const editing = !!(params && params.name);
    const list = App.NoteTypes.getForContextAll(context.subject, context.module);
    let d = editing
      ? (list.find(t => t.name === params.name) || { name: '', color: '#0066CC' })
      : { name: '', color: '#0066CC' };

    const header = App.Components.pageHeader(
      editing ? '编辑类型' : '新增类型',
      '保存',
      async () => {
        const nm = d.name.trim();
        if (!nm) { App.Components.toast('请输入类型名称', 'error'); return; }
        if (!editing && list.some(t => t.name === nm)) {
          App.Components.toast('已存在同名类型', 'error'); return;
        }
        if (editing) {
          // 改名：只更新当前科目/模块，并同步该范围内的笔记
          const updated = App.NoteTypes.renameForContext(context.subject, context.module, params.name, nm, d.color);
          if (!updated) { App.Components.toast('标签保存失败', 'error'); return; }
          try {
            const notes = await App.DB.getNotes();
            for (const n of notes) {
              const sameScope = n.subject === context.subject && (
                context.module ? n.module === context.module : !n.module
              );
              if (sameScope && n.type === params.name) { n.type = nm; await App.DB.updateNote(n); }
            }
          } catch (e) { /* ignore */ }
        } else {
          if (!App.NoteTypes.addForContext(context.subject, context.module, nm, d.color)) {
            App.Components.toast('标签保存失败', 'error'); return;
          }
        }
        App.Components.toast('已保存', 'success');
        App.Router.navigate(this._noteTypeManageRoute(context));
      }
    );
    container.appendChild(header);

    const body = document.createElement('div');
    body.className = 'ntype-form';

    const scopeHint = document.createElement('div');
    scopeHint.className = 'ntype-form-scope';
    scopeHint.textContent = '当前范围：' + context.subject + (context.module ? ' / ' + context.module : '（科目级）');
    body.appendChild(scopeHint);

    // 名称区
    const nameLabel = document.createElement('div');
    nameLabel.className = 'ntype-label';
    nameLabel.textContent = '名称';
    body.appendChild(nameLabel);
    const nameInput = document.createElement('input');
    nameInput.className = 'ntype-input';
    nameInput.placeholder = '输入类型名称，如：高频考点';
    nameInput.value = d.name;
    nameInput.addEventListener('input', () => { d.name = nameInput.value; refreshPreview(); });
    body.appendChild(nameInput);

    // 颜色区
    const colorLabel = document.createElement('div');
    colorLabel.className = 'ntype-label';
    colorLabel.textContent = '颜色';
    body.appendChild(colorLabel);
    const palette = document.createElement('div');
    palette.className = 'ntype-palette';
    const COLORS = ['#0066CC', '#FF9500', '#34C759', '#9B7BFF', '#00BFA5', '#FF3B30', '#FF5B9E'];
    COLORS.forEach(c => {
      const sw = document.createElement('button');
      sw.type = 'button';
      sw.className = 'ntype-swatch' + (d.color === c ? ' active' : '');
      sw.style.background = c;
      if (d.color === c) sw.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="M20 6L9 17l-5-5"/></svg>';
      sw.addEventListener('click', () => { d.color = c; buildPalette(); refreshPreview(); });
      palette.appendChild(sw);
    });
    const buildPalette = () => {
      palette.innerHTML = '';
      COLORS.forEach(c => {
        const sw = document.createElement('button');
        sw.type = 'button';
        sw.className = 'ntype-swatch' + (d.color === c ? ' active' : '');
        sw.style.background = c;
        if (d.color === c) sw.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="M20 6L9 17l-5-5"/></svg>';
        sw.addEventListener('click', () => { d.color = c; buildPalette(); refreshPreview(); });
        palette.appendChild(sw);
      });
    };
    body.appendChild(palette);

    // 预览区
    const prevLabel = document.createElement('div');
    prevLabel.className = 'ntype-label';
    prevLabel.textContent = '预览';
    body.appendChild(prevLabel);
    const prevCard = document.createElement('div');
    prevCard.className = 'ntype-preview';
    const prevPill = document.createElement('div');
    prevPill.className = 'ntype-pill';
    prevCard.appendChild(prevPill);
    const prevNote = document.createElement('div');
    prevNote.className = 'ntype-preview-note';
    prevNote.textContent = '新类型在笔记卡上的显示效果';
    prevCard.appendChild(prevNote);
    body.appendChild(prevCard);
    const refreshPreview = () => {
      const c = d.color || '#0066CC';
      const txt = d.name.trim() || '高频考点';
      prevPill.style.background = hexToRgba2(c, 0.12);
      prevPill.style.color = c;
      prevPill.textContent = txt;
    };

    // 提示
    const tip = document.createElement('div');
    tip.className = 'ntype-tip';
    tip.textContent = '保存后即可在笔记页顶部按此类型筛选';
    body.appendChild(tip);

    // hex→rgba(alpha)
    function hexToRgba2(hex, a) {
      const h = String(hex).replace('#', '');
      if (/^[0-9a-fA-F]{6}$/.test(h)) {
        return 'rgba(' + [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)).join(',') + ',' + a + ')';
      }
      return 'rgba(0,102,204,' + a + ')';
    }

    buildPalette();
    refreshPreview();
    container.appendChild(body);
  }
};
