// ===== 学习库 V1：科目 → 模块 → 知识内容 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Library = {
  state: { subject: null, module: null, tab: 'all', search: '', items: [], stickies: [] },
  SUBJECT_ORDER: ['言语理解', '判断推理', '资料分析', '数量关系', '常识判断', '申论'],

  _escape(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  },

  _query(extra) {
    const q = Object.assign({}, extra || {});
    if (this.state.subject) q.subject = this.state.subject;
    if (this.state.module) q.module = this.state.module;
    const list = Object.keys(q).filter(k => q[k] !== undefined && q[k] !== null && q[k] !== '')
      .map(k => encodeURIComponent(k) + '=' + encodeURIComponent(q[k]));
    return list.length ? '?' + list.join('&') : '';
  },

  async render(params) {
    params = params || {};
    const knownSubjects = this.SUBJECT_ORDER;
    const subject = knownSubjects.indexOf(params.subject || '') >= 0 ? params.subject : null;
    const modules = subject ? App.Constants.getModules(subject) : [];
    const module = subject && params.module && modules.indexOf(params.module) >= 0 ? params.module : null;
    this.state.subject = subject;
    this.state.module = module;
    const requestedView = params.view || params.tab || 'all';
    this.state.tab = ['all', 'wrong', 'note', 'word'].indexOf(requestedView) >= 0 ? requestedView : 'all';
    if (this.state.tab === 'word' && module !== '逻辑填空') this.state.tab = 'all';
    this.state.search = params.search || '';
    this.state.items = await App.Knowledge.getAll();
    try { this.state.stickies = await App.DB.getStickies(); } catch (e) { this.state.stickies = []; }

    const container = document.getElementById('page-library');
    if (this._masonryInst) {
      try { this._masonryInst.destroy(); } catch (e) {}
      this._masonryInst = null;
    }
    container.innerHTML = '';
    const body = document.createElement('div');
    body.className = 'library-page';
    container.appendChild(body);

    this._renderHeader(body);
    const search = this._renderSearch(body);
    const content = document.createElement('div');
    content.className = 'library-content';
    body.appendChild(content);

    const renderContent = () => {
      content.innerHTML = '';
      if (!this.state.subject) this._renderHome(content);
      else if (!this.state.module) this._renderSubject(content);
      else this._renderModule(content);
    };
    search.input.value = this.state.search;
    search.input.addEventListener('input', () => {
      this.state.search = search.input.value;
      renderContent();
    });
    renderContent();
    this._renderFab(body);
  },

  _renderHeader(container) {
    if (!this.state.subject) {
      const header = document.createElement('div');
      header.className = 'library-header';
      header.innerHTML = '<div><h1>学习库</h1></div>';
      container.appendChild(header);
      return;
    }
    const title = this.state.module || this.state.subject;
    const header = App.Components.pageHeader(title, null, null, {
      onBack: () => App.Router.navigate(this.state.module
        ? (this.state.tab === 'all'
          ? 'library?subject=' + encodeURIComponent(this.state.subject)
          : this._moduleRoute('all'))
        : 'library')
    });
    container.appendChild(header);
    if (this.state.module) {
      const trail = document.createElement('div');
      trail.className = 'library-breadcrumb';
      trail.textContent = this.state.subject + '  /  ' + this.state.module;
      container.appendChild(trail);
    }
  },

  _renderSearch(container) {
    const wrap = document.createElement('label');
    wrap.className = 'library-search';
    wrap.innerHTML = '<span aria-hidden="true">⌕</span><input type="search" placeholder="搜索科目、模块或知识内容" aria-label="搜索学习库"><button type="button" class="library-search__clear" aria-label="清除搜索">×</button>';
    const input = wrap.querySelector('input');
    const clear = wrap.querySelector('.library-search__clear');
    clear.addEventListener('click', () => { input.value = ''; input.dispatchEvent(new Event('input')); input.focus(); });
    container.appendChild(wrap);
    return { input };
  },

  _subjectItems(subject) { return App.Knowledge.filter(this.state.items, { subject }); },
  _moduleItems(subject, module) { return App.Knowledge.filter(this.state.items, { subject, module }); },

  _renderHome(container) {
    const query = this.state.search.trim();
    if (query) {
      const results = App.Knowledge.filter(this.state.items, { search: query }).slice(0, 30);
      const title = document.createElement('div');
      title.className = 'library-section-title';
      title.innerHTML = '<span>搜索结果</span><small>' + results.length + ' 条</small>';
      container.appendChild(title);
      this._renderItemList(container, results);
      return;
    }

    const title = document.createElement('div');
    title.className = 'library-section-title';
    title.innerHTML = '<span>按科目浏览</span><small>选择科目进入模块</small>';
    container.appendChild(title);
    const grid = document.createElement('div');
    grid.className = 'library-subject-grid';
    this.SUBJECT_ORDER.forEach(name => {
      const subject = App.Constants.SUBJECTS.find(s => s.name === name) || { name, color: '#0066CC', icon: '📚' };
      const items = this._subjectItems(name);
      const card = document.createElement('button');
      card.type = 'button';
      card.className = 'library-subject-card';
      card.style.setProperty('--subject-color', subject.color || '#0066CC');
      card.innerHTML = '<span class="library-subject-card__icon">' + this._escape(subject.icon || '📚') + '</span>' +
        '<span class="library-subject-card__name">' + this._escape(name) + '</span>' +
        '<span class="library-subject-card__stats"><b>' + App.Knowledge.count(items, { type: 'wrong' }) + '</b> 错题 · <b>' + App.Knowledge.count(items, { type: 'note' }) + '</b> 笔记 · <b>' + App.Knowledge.count(items, { type: 'word' }) + '</b> 词语</span>' +
        '<span class="library-subject-card__arrow">›</span>';
      card.addEventListener('click', () => App.Router.navigate('library?subject=' + encodeURIComponent(name)));
      grid.appendChild(card);
    });
    container.appendChild(grid);
  },

  _renderSubject(container) {
    const items = this._subjectItems(this.state.subject);
    const summary = document.createElement('div');
    summary.className = 'library-stat-strip';
    summary.innerHTML = '<div><strong>' + App.Knowledge.count(items, { type: 'wrong' }) + '</strong><span>错题</span></div>' +
      '<div><strong>' + App.Knowledge.count(items, { type: 'note' }) + '</strong><span>笔记</span></div>' +
      '<div><strong>' + App.Knowledge.count(items, { type: 'word' }) + '</strong><span>词语库</span></div>';
    container.appendChild(summary);

    const title = document.createElement('div');
    title.className = 'library-section-title';
    title.innerHTML = '<span>模块</span><small>选择模块查看全部内容</small>';
    container.appendChild(title);
    const list = document.createElement('div');
    list.className = 'library-module-list';
    App.Constants.getModules(this.state.subject).forEach(module => {
      const moduleItems = this._moduleItems(this.state.subject, module);
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'library-module-row';
      row.innerHTML = '<span class="library-module-row__name">' + this._escape(module) + '</span>' +
        '<span class="library-module-row__stats">错题 ' + App.Knowledge.count(moduleItems, { type: 'wrong' }) + '　笔记 ' + App.Knowledge.count(moduleItems, { type: 'note' }) + '　词语库 ' + App.Knowledge.count(moduleItems, { type: 'word' }) + '</span>' +
        '<span class="library-module-row__arrow" aria-hidden="true">›</span>';
      row.addEventListener('click', () => App.Router.navigate('library?subject=' + encodeURIComponent(this.state.subject) + '&module=' + encodeURIComponent(module)));
      list.appendChild(row);
    });
    container.appendChild(list);
  },

  _moduleRoute(view, context) {
    const subject = context && context.subject ? context.subject : this.state.subject;
    const module = context && context.module ? context.module : this.state.module;
    const query = 'subject=' + encodeURIComponent(subject || '') + '&module=' + encodeURIComponent(module || '');
    return 'library?' + query + (view && view !== 'all' ? '&view=' + encodeURIComponent(view) : '');
  },

  _isWordModule() { return this.state.module === '逻辑填空'; },

  _sortRecent(items) {
    return (items || []).slice().sort((a, b) => new Date(b.updatedTime || b.createdTime || 0) - new Date(a.updatedTime || a.createdTime || 0));
  },

  _moduleStickies() {
    const search = this.state.search.trim().toLowerCase();
    return (this.state.stickies || []).filter(sticky => {
      if (sticky.subject !== this.state.subject || sticky.module !== this.state.module) return false;
      return !search || String(sticky.content || '').toLowerCase().includes(search);
    });
  },

  _sectionHead(title, count, actionText, onAction) {
    const head = document.createElement('div');
    head.className = 'library-module-section__head';
    const titleEl = document.createElement('div');
    titleEl.className = 'library-module-section__title';
    titleEl.textContent = title + (count == null ? '' : '（' + count + '）');
    head.appendChild(titleEl);
    if (actionText && onAction) {
      const action = document.createElement('button');
      action.type = 'button';
      action.className = 'library-module-section__link';
      action.textContent = actionText;
      action.addEventListener('click', onAction);
      head.appendChild(action);
    }
    return head;
  },

  _sectionEmpty(text) {
    const empty = document.createElement('div');
    empty.className = 'library-section-empty';
    empty.textContent = text;
    return empty;
  },

  _renderRecentWrong(container, items) {
    const recent = this._sortRecent(items).slice(0, 4);
    if (!recent.length) {
      container.appendChild(this._sectionEmpty('暂无错题，点击右下角「+」新增错题'));
      return;
    }
    const masonryWrap = document.createElement('div');
    masonryWrap.className = 'error-masonry-wrap library-error-masonry-wrap library-recent-wrong';
    container.appendChild(masonryWrap);
    const inst = App.Components.masonryGrid(masonryWrap, {
      columns: 2,
      onOpen: (error) => this._openWrongDetail(error)
    });
    this._masonryInst = inst;
    inst.render(recent.map(item => item.raw), false);
  },

  _openStickySheet() {
    App.Components.stickySheet({
      title: '新增便签',
      onSave: async (data) => {
        try {
          await App.DB.addSticky(Object.assign({}, data, {
            subject: this.state.subject,
            module: this.state.module
          }));
          App.Components.toast('已新增便签 ✓', 'success');
          this.render({ subject: this.state.subject, module: this.state.module, view: 'all', search: this.state.search });
        } catch (e) { App.Components.toast('保存失败', 'error'); }
      }
    });
  },

  _renderModuleAll(container, items) {
    const visibleItems = App.Knowledge.filter(items, { search: this.state.search });
    const stickies = this._moduleStickies();

    const stickySection = document.createElement('section');
    stickySection.className = 'library-module-section';
    stickySection.appendChild(this._sectionHead('便签', stickies.length, '查看全部', () => App.Router.navigate('stickies?subject=' + encodeURIComponent(this.state.subject) + '&module=' + encodeURIComponent(this.state.module))));
    const stickyTools = document.createElement('div');
    stickyTools.className = 'library-module-section__tools';
    const addSticky = document.createElement('button');
    addSticky.type = 'button';
    addSticky.className = 'library-module-section__add';
    addSticky.textContent = '＋ 新增便签';
    addSticky.addEventListener('click', () => this._openStickySheet());
    stickyTools.appendChild(addSticky);
    stickySection.querySelector('.library-module-section__head').appendChild(stickyTools);
    const stickyGrid = document.createElement('div');
    stickyGrid.className = 'sticky-masonry sticky-masonry--home library-module-sticky-masonry';
    if (!stickies.length) stickyGrid.appendChild(this._sectionEmpty('暂无本模块便签，先记下一条零碎想法吧'));
    else stickies.slice(0, 4).forEach(sticky => stickyGrid.appendChild(App.Components.stickyCard(sticky, { onRefresh: () => this.render({ subject: this.state.subject, module: this.state.module, view: 'all', search: this.state.search }) })));
    stickySection.appendChild(stickyGrid);
    container.appendChild(stickySection);

    const wrongItems = visibleItems.filter(item => item.type === 'wrong');
    const wrongSection = document.createElement('section');
    wrongSection.className = 'library-module-section';
    wrongSection.appendChild(this._sectionHead('错题本', wrongItems.length, '查看全部', () => App.Router.navigate(this._moduleRoute('wrong'))));
    this._renderRecentWrong(wrongSection, wrongItems);
    container.appendChild(wrongSection);

    const noteItems = visibleItems.filter(item => item.type === 'note' || item.type === 'method');
    const noteSection = document.createElement('section');
    noteSection.className = 'library-module-section';
    noteSection.appendChild(this._sectionHead('笔记', noteItems.length, '查看全部', () => App.Router.navigate(this._moduleRoute('note'))));
    const noteList = document.createElement('div');
    noteList.className = 'library-item-list library-item-list--recent';
    if (!noteItems.length) noteList.appendChild(this._sectionEmpty('暂无笔记，点击右下角「+」新增笔记'));
    else this._sortRecent(noteItems).slice(0, 4).forEach(item => noteList.appendChild(this._itemCard(item)));
    noteSection.appendChild(noteList);
    container.appendChild(noteSection);

    if (this._isWordModule()) {
      const wordLink = document.createElement('button');
      wordLink.type = 'button';
      wordLink.className = 'library-module-word-link';
      wordLink.innerHTML = '<span>词语库</span><span>仅逻辑填空模块使用　›</span>';
      wordLink.addEventListener('click', () => App.Router.navigate(this._moduleRoute('word')));
      container.appendChild(wordLink);
    }
  },

  _renderModule(container) {
    const items = this._moduleItems(this.state.subject, this.state.module);
    const moduleStats = '错题 ' + App.Knowledge.count(items, { type: 'wrong' }) + '　笔记 ' + App.Knowledge.count(items, { type: 'note' }) +
      (this._isWordModule() ? '　词语库 ' + App.Knowledge.count(items, { type: 'word' }) : '');
    const summary = document.createElement('div');
    summary.className = 'library-module-summary';
    summary.innerHTML = '<div class="library-module-summary__title">' + this._escape(this.state.module) + '</div>' +
      '<div class="library-module-summary__stats">' + moduleStats + '</div>';
    container.appendChild(summary);

    if (this.state.tab === 'all') {
      this._renderModuleAll(container, items);
      return;
    }

    const viewTitle = this.state.tab === 'wrong' ? '错题本' : (this.state.tab === 'note' ? '笔记' : '词语库');
    const viewHead = document.createElement('div');
    viewHead.className = 'library-view-heading';
    viewHead.innerHTML = '<strong>' + this._escape(viewTitle) + '</strong><span>返回「全部」查看模块概览</span>';
    container.appendChild(viewHead);
    const list = document.createElement('div');
    list.className = 'library-item-list';
    container.appendChild(list);
    this._renderItemList(list, App.Knowledge.filter(items, { type: this.state.tab, search: this.state.search }));
  },

  _renderItemList(container, items) {
    if (this._masonryInst) {
      try { this._masonryInst.destroy(); } catch (e) {}
      this._masonryInst = null;
    }
    container.classList.remove('library-item-list--masonry');
    if (!items.length) {
      const hint = this.state.module && !this._isWordModule() ? '可以通过右下角「+」新增错题或笔记' : '可以通过右下角「+」新增错题、笔记或词语';
      container.innerHTML = '<div class="library-empty"><span>📚</span><strong>这里还没有内容</strong><small>' + hint + '</small></div>';
      return;
    }

    // 学习库错题页回退到旧错题本卡片：保留题干、辨析词语、标签、错因、复盘和日期。
    // 仅学习库错题页固定为两列；旧错题本页面仍使用原有的自适应列数。
    const isWrongMasonry = this.state.tab === 'wrong' && items.every(item => item.type === 'wrong');
    if (isWrongMasonry) {
      container.classList.add('library-item-list--masonry');
      const masonryWrap = document.createElement('div');
      masonryWrap.className = 'error-masonry-wrap library-error-masonry-wrap';
      container.appendChild(masonryWrap);
      const inst = App.Components.masonryGrid(masonryWrap, {
        columns: 2,
        onOpen: (error) => this._openWrongDetail(error)
      });
      this._masonryInst = inst;
      inst.render(items.map(item => item.raw), false);
      return;
    }

    items.slice().sort((a, b) => new Date(b.updatedTime || b.createdTime || 0) - new Date(a.updatedTime || a.createdTime || 0))
      .forEach(item => container.appendChild(this._itemCard(item)));
  },

  _itemIndexTitle(item) {
    if (item.type !== 'wrong') return item.title;
    const raw = item.raw || {};
    const groups = Array.isArray(raw.compareGroups) ? raw.compareGroups : [];
    const compareWords = groups.map(group => {
      if (Array.isArray(group && group.words)) return group.words.filter(Boolean).join(' VS ');
      return group && group.words ? String(group.words) : '';
    }).filter(Boolean);
    if (compareWords.length) return compareWords.join(' · ');
    const points = Array.isArray(raw.knowledgePoints) ? raw.knowledgePoints.filter(Boolean) : [];
    if (points.length) return points.slice(0, 2).join(' · ');
    if (raw.knowledgePoint) return String(raw.knowledgePoint);
    return raw.errorCause || '待复盘错题';
  },

  _itemCard(item) {
    const card = document.createElement('article');
    card.className = 'library-item-card library-item-card--' + item.type;
    const date = item.updatedTime || item.createdTime;
    const meta = item.module || '';
    const wrongSummary = item.type === 'wrong' && item.raw
      ? [item.raw.errorCause ? '错误原因：' + item.raw.errorCause : '', item.raw.pitfall ? '复盘：' + item.raw.pitfall : ''].filter(Boolean).join(' · ')
      : '';
    const summary = wrongSummary || item.summary;
    card.innerHTML = '<div class="library-item-card__top"><span class="library-type-pill">' + this._escape(item.typeLabel) + '</span><span class="library-item-card__meta">' + this._escape(meta) + '</span></div>' +
      '<h3>' + this._escape(this._itemIndexTitle(item)) + '</h3>' +
      '<p>' + this._escape(summary) + '</p>' +
      '<div class="library-item-card__bottom"><span class="library-item-card__date">' + this._escape(date ? App.Utils.formatDate(date) : '') + '</span><span class="library-item-card__open" aria-hidden="true">›</span></div>';
    card.addEventListener('click', () => this._openItem(item));
    return card;
  },

  _openItem(item) {
    if (item.sourceStore === 'errors') {
      this._openWrongDetail(item.raw || { id: item.sourceId, subject: item.subject, module: item.module });
    } else if (item.sourceStore === 'notes') {
      App.Router.navigate('note-detail?id=' + encodeURIComponent(item.sourceId));
    } else {
      const category = item.sourceCategory || 'word-def';
      App.Router.navigate('worddb?category=' + encodeURIComponent(category) + '&subject=' + encodeURIComponent(item.subject) + '&module=' + encodeURIComponent(item.module));
    }
  },

  _openWrongDetail(error) {
    const returnTo = 'library?subject=' + encodeURIComponent(error.subject || '') +
      '&module=' + encodeURIComponent(error.module || '') + '&view=wrong';
    App.Router.navigate('error-detail?id=' + encodeURIComponent(error.id) +
      '&returnTo=' + encodeURIComponent(returnTo));
  },

  async _getContext() {
    let subject = this.state.subject;
    if (!subject) {
      subject = await App.Components.centeredPicker(this.SUBJECT_ORDER.map(name => ({ icon: '📚', label: name, value: name })), '选择科目', '新增内容必须先绑定科目');
      if (!subject) return null;
    }
    let module = this.state.module;
    if (!module) {
      const modules = App.Constants.getModules(subject);
      module = await App.Components.centeredPicker(modules.map(name => ({ icon: '📂', label: name, value: name })), '选择模块', '新增内容必须绑定到具体模块');
      if (!module) return null;
    }
    return { subject, module };
  },

  _renderFab(container) {
    const fab = document.createElement('button');
    fab.type = 'button';
    fab.className = 'sc-fab fab--solid-blue library-fab';
    fab.setAttribute('aria-label', '新增学习内容');
    fab.title = '新增学习内容';
    fab.innerHTML = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>';
    fab.addEventListener('click', async () => {
      const context = await this._getContext();
      if (!context) return;
      const actions = [
        { label: '📋 错题', value: 'wrong' },
        { label: '📝 笔记', value: 'note' },
        { label: '💡 方法总结', value: 'method' }
      ];
      if (context.module === '逻辑填空') actions.splice(2, 0, { label: '🔀 词语辨析', value: 'word' });
      const action = await App.Components.actionSheet(actions, '新增内容');
      if (!action) return;
      const base = 'subject=' + encodeURIComponent(context.subject) + '&module=' + encodeURIComponent(context.module);
      if (action === 'wrong') App.Router.navigate('error-form?' + base + '&returnTo=' + encodeURIComponent(this._moduleRoute('wrong', context)));
      if (action === 'note') App.Router.navigate('note-form?' + base);
      if (action === 'method') App.Router.navigate('note-form?' + base + '&type=' + encodeURIComponent('解题方法'));
      if (action === 'word' && context.module === '逻辑填空') App.Router.navigate('worddb?category=word-compare&create=1&' + base);
    });
    container.appendChild(fab);
  }
};

