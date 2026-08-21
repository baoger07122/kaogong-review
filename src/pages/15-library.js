// ===== 学习库 V1：科目 → 模块 → 知识内容 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Library = {
  state: { subject: null, module: null, tab: 'all', search: '', items: [] },
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
    this.state.tab = ['all', 'wrong', 'note', 'word'].indexOf(params.tab) >= 0 ? params.tab : 'all';
    this.state.search = params.search || '';
    this.state.items = await App.Knowledge.getAll();

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
      header.innerHTML = '<div><div class="library-eyebrow">KNOWLEDGE HUB</div><h1>学习库</h1><p>把错题、笔记和词语沉淀为自己的知识资产</p></div>';
      container.appendChild(header);
      return;
    }
    const title = this.state.module || this.state.subject;
    const header = App.Components.pageHeader(title, null, null, {
      onBack: () => App.Router.navigate(this.state.module
        ? 'library?subject=' + encodeURIComponent(this.state.subject)
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
    const grid = document.createElement('div');
    grid.className = 'library-module-grid';
    App.Constants.getModules(this.state.subject).forEach(module => {
      const moduleItems = this._moduleItems(this.state.subject, module);
      const card = document.createElement('button');
      card.type = 'button';
      card.className = 'library-module-card';
      card.innerHTML = '<span class="library-module-card__name">' + this._escape(module) + '</span>' +
        '<span class="library-module-card__stats">错题 ' + App.Knowledge.count(moduleItems, { type: 'wrong' }) + '　笔记 ' + App.Knowledge.count(moduleItems, { type: 'note' }) + '　词语库 ' + App.Knowledge.count(moduleItems, { type: 'word' }) + '</span>' +
        '<span class="library-module-card__arrow">›</span>';
      card.addEventListener('click', () => App.Router.navigate('library?subject=' + encodeURIComponent(this.state.subject) + '&module=' + encodeURIComponent(module)));
      grid.appendChild(card);
    });
    container.appendChild(grid);
  },

  _renderModule(container) {
    const items = this._moduleItems(this.state.subject, this.state.module);
    const summary = document.createElement('div');
    summary.className = 'library-module-summary';
    summary.innerHTML = '<div class="library-module-summary__title">' + this._escape(this.state.module) + '</div>' +
      '<div class="library-module-summary__stats">错题 ' + App.Knowledge.count(items, { type: 'wrong' }) + '　笔记 ' + App.Knowledge.count(items, { type: 'note' }) + '　词语库 ' + App.Knowledge.count(items, { type: 'word' }) + '</div>';
    container.appendChild(summary);

    const tabs = document.createElement('div');
    tabs.className = 'library-tabs';
    [['all', '全部'], ['wrong', '错题'], ['note', '笔记'], ['word', '词语库']].forEach(([key, label]) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = this.state.tab === key ? 'is-active' : '';
      button.textContent = label;
      button.addEventListener('click', () => {
        this.state.tab = key;
        tabs.querySelectorAll('button').forEach(b => b.classList.remove('is-active'));
        button.classList.add('is-active');
        list.innerHTML = '';
        this._renderItemList(list, App.Knowledge.filter(items, { type: key, search: this.state.search }));
      });
      tabs.appendChild(button);
    });
    container.appendChild(tabs);
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
    if (!items.length) {
      container.innerHTML = '<div class="library-empty"><span>📚</span><strong>这里还没有内容</strong><small>可以通过右下角「+」新增错题、笔记或词语</small></div>';
      return;
    }

    // 错题沿用旧错题本的完整卡片：题干、辨析词语、考点/错因、思维误区和日期。
    // 学习库按当前产品要求固定为横向两列；旧错题本不传 columns，继续使用原自适应列数。
    const isWrongMasonry = this.state.tab === 'wrong' && items.every(item => item.type === 'wrong');
    if (isWrongMasonry) {
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

  _itemCard(item) {
    const card = document.createElement('article');
    card.className = 'library-item-card library-item-card--' + item.type;
    const date = item.updatedTime || item.createdTime;
    const meta = [item.module, date ? App.Utils.formatDate(date) : ''].filter(Boolean).join(' · ');
    const extra = item.type === 'wrong' && item.raw.errorCause
      ? '<div class="library-item-card__extra">错误原因：' + this._escape(item.raw.errorCause) + '</div>' : '';
    card.innerHTML = '<div class="library-item-card__top"><span class="library-type-pill">' + this._escape(item.typeLabel) + '</span><span class="library-item-card__meta">' + this._escape(meta) + '</span></div>' +
      '<h3>' + this._escape(item.title) + '</h3>' +
      '<p>' + this._escape(item.summary) + '</p>' + extra +
      '<span class="library-item-card__open">查看详情 ›</span>';
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
      '&module=' + encodeURIComponent(error.module || '') + '&tab=wrong';
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
      const action = await App.Components.actionSheet([
        { label: '📋 错题', value: 'wrong' },
        { label: '📝 笔记', value: 'note' },
        { label: '🔀 词语辨析', value: 'word' },
        { label: '💡 方法总结', value: 'method' }
      ], '新增内容');
      if (!action) return;
      const base = 'subject=' + encodeURIComponent(context.subject) + '&module=' + encodeURIComponent(context.module);
      if (action === 'wrong') App.Router.navigate('error-form?' + base);
      if (action === 'note') App.Router.navigate('note-form?' + base);
      if (action === 'method') App.Router.navigate('note-form?' + base + '&type=' + encodeURIComponent('解题方法'));
      if (action === 'word') App.Router.navigate('worddb?category=word-compare&create=1&' + base);
    });
    container.appendChild(fab);
  }
};
