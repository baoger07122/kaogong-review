App.Pages.WordDB = {
  state: {
    category: null,
    words: [],
    searchQuery: '',
    sentiment: '',
    sortBy: 'name',
    expandedRowId: null,
    compareSearchOpen: false,
    subject: '言语理解',
    module: '逻辑填空'
  },

  // 分类配置
  CATEGORIES: [
    { key: 'idiom-def', label: '成语释义', icon: '📖', desc: '成语的含义、用法与感情色彩' },
    { key: 'idiom-compare', label: '成语组辨析', icon: '🔀', desc: '近义/反义成语对比辨析' },
    { key: 'word-def', label: '实词释义', icon: '📝', desc: '实词的含义、用法与搭配' },
    { key: 'word-compare', label: '实词组辨析', icon: '⚖️', desc: '近义/反义实词对比辨析' }
  ],

  CATEGORY_TITLES: {
    'idiom-def': '成语',
    'idiom-compare': '成语组',
    'word-def': '实词',
    'word-compare': '实词组'
  },

  SENTIMENTS: ['褒义', '贬义', '中性'],

  // ===== 主入口 =====
  async render(params) {
    const container = document.getElementById('page-worddb');
    container.innerHTML = '';

    this.state.category = params.category || 'idiom-def';
    this.state.subject = params.subject || '言语理解';
    this.state.module = params.module || '逻辑填空';
    this.state.expandedRowId = null;
    this.state.searchQuery = '';
    this.state.compareSearchOpen = false;

    // 返回栏 + 标题；实词组辨析将搜索收进右上角更多菜单，新增使用右下角悬浮按钮。
    const pageHeader = App.Components.pageHeader(
      this._getCategoryTitle(),
      this.state.category === 'word-compare' ? '⋮' : '导入',
      this.state.category === 'word-compare'
        ? () => { this._showComparePageMenu(); }
        : () => { this._importSampleData(); }
    );
    if (this.state.category === 'word-compare') {
      const titleEl = pageHeader.querySelector('.page-header__title');
      if (titleEl) titleEl.style.fontSize = 'var(--font-xxl)';
      const pageMenu = pageHeader.querySelector('.page-header__right');
      if (pageMenu) pageMenu.classList.add('worddb-page-menu');
    }
    container.appendChild(pageHeader);

    // 分类子 Tab（4 个分类切换）
    const catBar = document.createElement('div');
    catBar.className = 'worddb-cat-bar';
    const catTabs = App.Components.stickyTabs(
      this.CATEGORIES.map(c => ({ label: c.icon + ' ' + c.label })),
      this.CATEGORIES.findIndex(c => c.key === this.state.category),
      (idx) => {
        this.state.category = this.CATEGORIES[idx].key;
        this.state.expandedRowId = null;
        this.state.searchQuery = '';
        this.state.sentiment = '';
        this.render({ category: this.state.category });
      }
    );
    catBar.appendChild(catTabs);
    container.appendChild(catBar);

    // 工具栏
    const toolbar = document.createElement('div');
    toolbar.className = 'worddb-toolbar';
    this._renderToolbar(toolbar);
    container.appendChild(toolbar);

    // 表格区域
    const tableArea = document.createElement('div');
    tableArea.className = 'worddb-table-area';
    tableArea.id = 'worddb-table-area';
    container.appendChild(tableArea);

    if (this.state.category === 'word-compare') {
      // 与错题本保持一致：新增入口固定在右下角，不占用列表横向空间。
      const fab = document.createElement('button');
      fab.type = 'button';
      fab.className = 'sc-fab fab--solid-blue worddb-compare-fab';
      fab.setAttribute('aria-label', '新增实词辨析');
      fab.title = '新增实词辨析';
      fab.innerHTML = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>';
      fab.addEventListener('click', () => { this._showWordForm(null); });
      container.appendChild(fab);
    }

    // 加载数据并渲染表格
    await this._loadAndRender(tableArea);
  },

  _getCategoryTitle() {
    const cat = this.CATEGORIES.find(c => c.key === this.state.category);
    return (cat ? cat.label : '词语库') + '\n' + this.state.subject + ' · ' + this.state.module;
  },

  // ===== 工具栏 =====
  _renderToolbar(container) {
    container.innerHTML = '';

    // 实词组辨析默认隐藏搜索框，由页面右上角“…”菜单唤出。
    if (this.state.category === 'word-compare') {
      container.classList.add('worddb-toolbar--compare');

      if (!this.state.compareSearchOpen) return;

      const searchPanel = document.createElement('div');
      searchPanel.className = 'worddb-compare-search-panel' + (this.state.compareSearchOpen ? ' is-open' : '');
      searchPanel.innerHTML = '<span class="worddb-search-icon" aria-hidden="true">⌕</span><input type="search" class="worddb-search-input" placeholder="搜索词语、解释或核心区别..."><button type="button" class="worddb-compare-search-close" aria-label="关闭搜索">×</button>';
      const searchInput = searchPanel.querySelector('.worddb-search-input');
      searchInput.value = this.state.searchQuery;
      let searchTimer = null;
      searchInput.addEventListener('input', () => {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => {
          this.state.searchQuery = searchInput.value;
          this._refreshTable();
        }, 180);
      });
      searchPanel.querySelector('.worddb-compare-search-close').addEventListener('click', () => {
        this.state.compareSearchOpen = false;
        this._renderToolbar(container);
      });
      container.appendChild(searchPanel);
      setTimeout(() => searchInput.focus(), 0);
      return;
    }

    // 左侧：筛选下拉（感情色彩）
    const filterBtn = document.createElement('button');
    filterBtn.className = 'worddb-filter-btn';
    const renderFilterBtn = () => {
      const label = this.state.sentiment || '全部感情色彩';
      filterBtn.innerHTML = this._escapeHtml(label) + ' <span class="worddb-filter-caret">▾</span>';
    };
    renderFilterBtn();

    const sentimentOpts = this.SENTIMENTS.map(s => ({ label: s, value: s }));
    sentimentOpts.unshift({ label: '全部感情色彩', value: '' });

    filterBtn.addEventListener('click', async () => {
      const sel = await App.Components.centeredPicker(sentimentOpts, '筛选感情色彩', '选择要显示的词语感情色彩');
      if (sel !== undefined && sel !== null) {
        this.state.sentiment = sel;
        renderFilterBtn();
        this._refreshTable();
      }
    });
    container.appendChild(filterBtn);

    // 搜索框
    const searchWrap = document.createElement('div');
    searchWrap.className = 'worddb-search-wrap';
    searchWrap.innerHTML = '<span class="worddb-search-icon">🔍</span><input type="text" class="worddb-search-input" placeholder="搜索词语/释义...">';
    const searchInput = searchWrap.querySelector('.worddb-search-input');
    searchInput.value = this.state.searchQuery;
    let searchTimer = null;
    searchInput.addEventListener('input', () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => {
        this.state.searchQuery = searchInput.value;
        this._refreshTable();
      }, 300);
    });
    container.appendChild(searchWrap);

    // 右侧：新增按钮
    const addBtn = document.createElement('button');
    addBtn.className = 'worddb-add-btn';
    addBtn.textContent = '+ 新增';
    addBtn.addEventListener('click', () => { this._showWordForm(null); });
    container.appendChild(addBtn);
  },

  async _showComparePageMenu() {
    const action = await App.Components.actionSheet([
      {
        label: this.state.compareSearchOpen ? '隐藏搜索' : '搜索辨析',
        value: 'toggle-search'
      }
    ], '实词组辨析');
    if (action !== 'toggle-search') return;

    this.state.compareSearchOpen = !this.state.compareSearchOpen;
    const toolbar = document.querySelector('#page-worddb .worddb-toolbar');
    if (toolbar) this._renderToolbar(toolbar);
  },

  // ===== 表格渲染 =====
  async _loadAndRender(tableArea) {
    await this._loadWords();
    // 首次进入页面直接展开最新一条，避免新建内容被折叠在首行之后。
    if (this.state.category === 'word-compare'
      && !this.state.searchQuery.trim()
      && this.state.expandedRowId === null
      && this.state.words.length) {
      this.state.expandedRowId = this.state.words[0].id;
    }
    this._renderTable(tableArea);
  },

  _renderTable(tableArea) {
    tableArea.innerHTML = '';
    tableArea.classList.toggle('worddb-table-area--compare', this.state.category === 'word-compare');

    if (this.state.words.length === 0) {
      this._renderEmpty(tableArea);
      return;
    }

    // 表头
    const thead = document.createElement('div');
    thead.className = 'worddb-thead';
    const cols = this._getColumns();
    cols.forEach(col => {
      const th = document.createElement('div');
      th.className = 'worddb-th';
      th.textContent = col;
      thead.appendChild(th);
    });
    tableArea.appendChild(thead);

    // 表体
    const tbody = document.createElement('div');
    tbody.className = 'worddb-tbody';
    this.state.words.forEach((word, idx) => {
      const row = this._renderRow(word, idx);
      tbody.appendChild(row);
    });
    tableArea.appendChild(tbody);
  },

  _getColumns() {
    if (this.state.category === 'word-compare') {
      return ['词语组', '核心区别', '更新时间'];
    }
    return ['名称', '属性', '更新时间', '操作'];
  },

  _getLinkedWordName(wordId) {
    if (!wordId) return '待关联';
    const linked = (this.state.definitionWords || []).find(w => w.id === wordId);
    return linked ? linked.name : '词语已删除';
  },

  _renderRow(word, idx) {
    const row = document.createElement('div');
    row.className = 'worddb-row';
    row.dataset.id = word.id;

    const isExpanded = this.state.expandedRowId === word.id;
    if (isExpanded) row.classList.add('expanded');

    // 行主区域（始终可见）
    const main = document.createElement('div');
    const isWordCompare = this.state.category === 'word-compare';
    main.className = 'worddb-row__main' + (isWordCompare ? ' worddb-row__main--compare' : '');

    // 名称列
    const nameCell = document.createElement('div');
    nameCell.className = 'worddb-cell worddb-cell--name';
    nameCell.textContent = isWordCompare ? this._getCompareGroupName(word) : word.name;
    main.appendChild(nameCell);

    if (isWordCompare) {
      const summaryCell = document.createElement('div');
      summaryCell.className = 'worddb-cell worddb-cell--summary';
      summaryCell.textContent = word.compareNote || word.meaning || '—';
      main.appendChild(summaryCell);
    }

    // 属性列（感情色彩 / 词性 / 成员数）
    if (!isWordCompare) {
      const propCell = document.createElement('div');
      propCell.className = 'worddb-cell worddb-cell--prop';
      if (word.sentiment) {
        const tag = document.createElement('span');
        tag.className = 'worddb-sentiment worddb-sentiment--' + (word.sentiment === '褒义' ? 'pos' : word.sentiment === '贬义' ? 'neg' : 'neu');
        tag.textContent = word.sentiment;
        propCell.appendChild(tag);
      }
      if (word.pos) {
        const posTag = document.createElement('span');
        posTag.className = 'worddb-pos-tag';
        posTag.textContent = word.pos;
        propCell.appendChild(posTag);
      }
      main.appendChild(propCell);
    }

    // 时间列
    const timeCell = document.createElement('div');
    timeCell.className = 'worddb-cell worddb-cell--time';
    timeCell.textContent = (word.updatedAt || word.createdAt || '').slice(0, 10);
    main.appendChild(timeCell);

    // 其他分类保留原有“展开”操作列；实词组辨析整行点击展开。
    if (!isWordCompare) {
      const actionCell = document.createElement('div');
      actionCell.className = 'worddb-cell worddb-cell--action';
      const openBtn = document.createElement('button');
      openBtn.className = 'worddb-open-btn';
      openBtn.textContent = isExpanded ? '收起' : '展开';
      openBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this.state.expandedRowId = isExpanded ? null : word.id;
        this._refreshTable();
      });
      actionCell.appendChild(openBtn);
      main.appendChild(actionCell);
    }

    row.appendChild(main);

    // 展开详情区
    if (isExpanded) {
      const detail = this._renderDetail(word);
      row.appendChild(detail);
    }

    // 点击行主区域展开/收起
    main.addEventListener('click', async (e) => {
      if (e.target.closest('.worddb-open-btn')) return;
      const preservePosition = isWordCompare;
      const anchorTop = preservePosition ? main.getBoundingClientRect().top : 0;
      const beforeScrollY = preservePosition ? window.scrollY : 0;
      this.state.expandedRowId = isExpanded ? null : word.id;
      await this._refreshTable();
      if (preservePosition) {
        const anchor = Array.from(document.querySelectorAll('.worddb-row__main'))
          .find(el => el.closest('.worddb-row') && el.closest('.worddb-row').dataset.id === word.id);
        if (anchor) {
          window.scrollTo(0, beforeScrollY + anchor.getBoundingClientRect().top - anchorTop);
        }
      }
    });

    return row;
  },

  // ===== 实词组辨析专用数据与详情 =====
  _getCompareTerms(word) {
    if (word && Array.isArray(word.compareWords) && word.compareWords.length) {
      return word.compareWords.map(term => ({
        name: String(term && term.name || ''),
        meaning: String(term && term.meaning || ''),
        wordId: term && (term.wordId || term.id) || null
      }));
    }

    const terms = [];
    ['wordAId', 'wordBId'].forEach(key => {
      const id = word && word[key];
      const linked = (this.state.definitionWords || []).find(item => item.id === id);
      if (linked) terms.push({ name: linked.name || '', meaning: linked.meaning || '', wordId: id });
    });
    if (!terms.length) {
      terms.push({ name: String(word && word.name || ''), meaning: String(word && word.meaning || ''), wordId: null });
    }
    return terms;
  },

  _getCompareGroupName(word) {
    const names = this._getCompareTerms(word).map(term => term.name.trim()).filter(Boolean);
    return names.length > 1 ? names.join(' vs ') : (word && word.name) || names[0] || '未命名实词辨析';
  },

  _syncCompareWordFields(word) {
    const terms = this._getCompareTerms(word);
    word.compareWords = terms;
    const names = terms.map(term => term.name.trim()).filter(Boolean);
    if (names.length) word.name = names.join(' vs ');
    const detailText = terms
      .filter(term => term.name.trim() || term.meaning.trim())
      .map(term => term.name.trim() ? term.name.trim() + '：' + term.meaning.trim() : term.meaning.trim())
      .join('\n');
    // 旧记录只有一个未拆分的名称时，保留原 meaning，避免无意改写历史内容。
    if (detailText && !(terms.length === 1 && word.name === terms[0].name && word.meaning)) {
      word.meaning = detailText;
    }
    word.wordAId = terms[0] && terms[0].wordId || null;
    word.wordBId = terms[1] && terms[1].wordId || null;
    return word;
  },

  _renderCompareDetail(word) {
    const detail = document.createElement('div');
    detail.className = 'worddb-detail worddb-compare-detail';

    const head = document.createElement('div');
    head.className = 'worddb-compare-detail__head';
    const menuBtn = document.createElement('button');
    menuBtn.type = 'button';
    menuBtn.className = 'worddb-compare-menu';
    menuBtn.textContent = '···';
    menuBtn.title = '更多操作';
    menuBtn.setAttribute('aria-label', '更多操作');
    menuBtn.addEventListener('click', async (event) => {
      event.stopPropagation();
      const action = await App.Components.actionSheet([
        { label: '🗑 删除辨析', value: 'delete' }
      ], this._getCompareGroupName(word));
      if (action !== 'delete') return;
      if (!confirm('确定删除「' + this._getCompareGroupName(word) + '」吗？')) return;
      await App.DB.deleteWord(word.id);
      this.state.expandedRowId = null;
      await this._loadAndRender(document.getElementById('worddb-table-area'));
      App.Components.toast('已删除', 'success');
    });
    head.appendChild(menuBtn);
    detail.appendChild(head);

    const termsSection = document.createElement('div');
    termsSection.className = 'worddb-detail-section';
    termsSection.innerHTML = '<strong>词语解释</strong>';
    const termsWrap = document.createElement('div');
    termsWrap.className = 'worddb-compare-terms';
    this._getCompareTerms(word).forEach((term, index) => {
      const termBlock = document.createElement('div');
      termBlock.className = 'worddb-compare-term';

      const canEditTerm = index < 2;
      if (!canEditTerm) termBlock.classList.add('worddb-compare-term--readonly');

      const name = document.createElement('div');
      name.className = 'worddb-compare-term__name' + (canEditTerm ? ' worddb-inline-editable' : '');
      name.textContent = term.name || '点击添加词语';
      name.title = canEditTerm ? '点击编辑词语' : 'V1 暂支持查看，后续开放编辑';
      if (canEditTerm) {
        name.addEventListener('click', event => {
          event.stopPropagation();
          this._startCompareInlineEdit(name, word, index, 'name');
        });
      }

      const meaning = document.createElement('div');
      meaning.className = 'worddb-compare-term__meaning' + (canEditTerm ? ' worddb-inline-editable' : '');
      meaning.textContent = term.meaning || '点击添加解释';
      meaning.title = canEditTerm ? '点击编辑解释' : 'V1 暂支持查看，后续开放编辑';
      if (canEditTerm) {
        meaning.addEventListener('click', event => {
          event.stopPropagation();
          this._startCompareInlineEdit(meaning, word, index, 'meaning', true);
        });
      }

      termBlock.appendChild(name);
      termBlock.appendChild(meaning);
      termsWrap.appendChild(termBlock);
    });
    termsSection.appendChild(termsWrap);
    detail.appendChild(termsSection);

    const coreSection = document.createElement('div');
    coreSection.className = 'worddb-detail-section worddb-compare-core';
    coreSection.innerHTML = '<strong>核心区别</strong>';
    const core = document.createElement('div');
    core.className = 'worddb-detail-text worddb-inline-editable';
    core.textContent = word.compareNote || '点击添加核心区别';
    core.title = '点击编辑核心区别';
    core.addEventListener('click', event => {
      event.stopPropagation();
      this._startCompareInlineEdit(core, word, null, 'compareNote', true);
    });
    coreSection.appendChild(core);
    detail.appendChild(coreSection);

    if (word.example) {
      const example = document.createElement('div');
      example.className = 'worddb-detail-section';
      example.innerHTML = '<strong>例句</strong><div class="worddb-detail-example">' + this._escapeHtml(word.example) + '</div>';
      detail.appendChild(example);
    }
    return detail;
  },

  _startCompareInlineEdit(target, word, termIndex, field, multiline) {
    if (target.dataset.editing === 'true') return;
    target.dataset.editing = 'true';
    target.classList.add('is-editing');
    const terms = this._getCompareTerms(word);
    const initial = field === 'compareNote'
      ? String(word.compareNote || '')
      : String(terms[termIndex] && terms[termIndex][field] || '');
    const editor = document.createElement(multiline ? 'textarea' : 'input');
    editor.className = 'worddb-inline-editor';
    editor.value = initial;
    editor.placeholder = field === 'name' ? '输入词语名称' : field === 'meaning' ? '输入该词的独立解释' : '输入核心区别';
    if (multiline) editor.rows = field === 'compareNote' ? 3 : 2;
    target.textContent = '';
    target.appendChild(editor);
    editor.addEventListener('click', event => event.stopPropagation());
    let saved = false;
    const save = async () => {
      if (saved) return;
      saved = true;
      const value = editor.value.trim();
      if (field === 'compareNote') {
        word.compareNote = value;
      } else {
        if (!terms[termIndex]) terms[termIndex] = { name: '', meaning: '', wordId: null };
        terms[termIndex][field] = value;
        word.compareWords = terms;
        this._syncCompareWordFields(word);
      }
      try {
        await App.DB.updateWord(word);
        App.Components.toast('已保存', 'success');
        this._refreshTable();
      } catch (error) {
        console.error(error);
        App.Components.toast('保存失败，请重试', 'error');
        target.dataset.editing = 'false';
      }
    };
    editor.addEventListener('blur', save);
    editor.addEventListener('keydown', event => {
      if (!multiline && event.key === 'Enter') {
        event.preventDefault();
        editor.blur();
      }
      if (multiline && event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        editor.blur();
      }
    });
    editor.focus();
    editor.select();
  },

  // ===== 展开详情 =====
  _renderDetail(word) {
    if (word.category === 'word-compare') return this._renderCompareDetail(word);
    const detail = document.createElement('div');
    detail.className = 'worddb-detail';

    // 拼音
    if (word.pinyin) {
      const py = document.createElement('div');
      py.className = 'worddb-detail-py';
      py.textContent = word.pinyin;
      detail.appendChild(py);
    }

    // 释义
    if (word.meaning) {
      const meaning = document.createElement('div');
      meaning.className = 'worddb-detail-section';
      meaning.innerHTML = '<strong>释义</strong><div class="worddb-detail-text">' + this._escapeHtml(word.meaning).replace(/\n/g, '<br>') + '</div>';
      detail.appendChild(meaning);
    }

    if (word.category === 'word-def' && word.myUnderstanding) {
      const understanding = document.createElement('div');
      understanding.className = 'worddb-detail-section';
      understanding.innerHTML = '<strong>我的理解</strong><div class="worddb-detail-text">' + this._escapeHtml(word.myUnderstanding).replace(/\n/g, '<br>') + '</div>';
      detail.appendChild(understanding);
    }

    if (word.category === 'word-def' && word.collocations) {
      const collocations = document.createElement('div');
      collocations.className = 'worddb-detail-section';
      collocations.innerHTML = '<strong>常见搭配</strong><div class="worddb-detail-text">' + this._escapeHtml(word.collocations).replace(/\n/g, '<br>') + '</div>';
      detail.appendChild(collocations);
    }

    if (word.category === 'word-def' && word.source) {
      const source = document.createElement('div');
      source.className = 'worddb-detail-section';
      source.innerHTML = '<strong>来源</strong><div class="worddb-detail-text">' + this._escapeHtml(word.source).replace(/\n/g, '<br>') + '</div>';
      detail.appendChild(source);
    }

    if (word.category === 'word-compare') {
      const linkedWords = document.createElement('div');
      linkedWords.className = 'worddb-detail-section';
      linkedWords.innerHTML = '<strong>基础信息</strong>';
      const pair = document.createElement('div');
      pair.className = 'worddb-linked-pair';
      const addWordChip = (label, type) => {
        const chip = document.createElement('span');
        chip.className = 'worddb-linked-chip worddb-linked-chip--' + type + (label === '待关联' ? ' is-pending' : '');
        chip.textContent = label;
        pair.appendChild(chip);
      };
      addWordChip(this._getLinkedWordName(word.wordAId), 'a');
      const vs = document.createElement('span');
      vs.className = 'worddb-linked-vs';
      vs.textContent = 'vs';
      pair.appendChild(vs);
      addWordChip(this._getLinkedWordName(word.wordBId), 'b');
      linkedWords.appendChild(pair);
      detail.appendChild(linkedWords);
    }

    // 例句
    if (word.example) {
      const ex = document.createElement('div');
      ex.className = 'worddb-detail-section';
      ex.innerHTML = '<strong>例句</strong><div class="worddb-detail-example">' + this._escapeHtml(word.example) + '</div>';
      detail.appendChild(ex);
    }

    // 辨析要点（compare 类型）
    if (word.compareNote) {
      const cmp = document.createElement('div');
      cmp.className = 'worddb-detail-section';
      cmp.innerHTML = '<strong>' + (word.category === 'word-compare' ? '我的辨析' : '辨析要点') + '</strong><div class="worddb-detail-text">' + this._escapeHtml(word.compareNote).replace(/\n/g, '<br>') + '</div>';
      detail.appendChild(cmp);
    }

    // 关联错题
    const errSection = document.createElement('div');
    errSection.className = 'worddb-detail-section';
    errSection.innerHTML = '<strong>关联错题</strong>';

    const errList = document.createElement('div');
    errList.className = 'worddb-related-errors';

    if (word.relatedErrorIds && word.relatedErrorIds.length > 0) {
      (async () => {
        for (const eid of word.relatedErrorIds) {
          const err = await App.DB.get('errors', eid);
          if (!err) continue;
          const chip = document.createElement('div');
          chip.className = 'worddb-err-chip';
          chip.textContent = (err.question || '').slice(0, 20) + '...';
          chip.title = err.question;
          chip.addEventListener('click', () => {
            App.Router.navigate('error-detail?id=' + eid);
          });
          errList.appendChild(chip);
        }
      })();
    } else {
      errList.innerHTML = '<span style="color:var(--text-tertiary);font-size:12px;">暂无关联错题</span>';
    }

    // +关联按钮
    const linkBtn = document.createElement('button');
    linkBtn.className = 'worddb-link-btn';
    linkBtn.textContent = '+ 关联错题';
    linkBtn.addEventListener('click', () => { this._linkError(word); });
    errSection.appendChild(errList);
    errSection.appendChild(linkBtn);
    detail.appendChild(errSection);

    // 操作按钮行
    const actions = document.createElement('div');
    actions.className = 'worddb-detail-actions';
    const editBtn = document.createElement('button');
    editBtn.className = 'worddb-edit-btn';
    editBtn.textContent = '✏️ 编辑';
    editBtn.addEventListener('click', () => { this._showWordForm(word); });
    actions.appendChild(editBtn);

    const delBtn = document.createElement('button');
    delBtn.className = 'worddb-del-btn';
    delBtn.textContent = '🗑 删除';
    delBtn.addEventListener('click', async () => {
      if (confirm('确定删除「' + word.name + '」吗？')) {
        await App.DB.deleteWord(word.id);
        this.state.expandedRowId = null;
        this._loadAndRender(document.getElementById('worddb-table-area'));
        App.Components.toast('已删除', 'success');
      }
    });
    actions.appendChild(delBtn);
    detail.appendChild(actions);

    return detail;
  },

  // ===== 空状态 =====
  _renderEmpty(container) {
    const empty = document.createElement('div');
    empty.className = 'worddb-empty';
    if (this.state.category === 'word-compare' && this.state.searchQuery.trim()) {
      empty.innerHTML = `
        <div class="worddb-empty-title">没有找到匹配的辨析内容</div>
        <div class="worddb-empty-desc">可尝试搜索词语名称、独立解释或核心区别。</div>
      `;
      container.appendChild(empty);
      return;
    }
    empty.innerHTML = `
      <div class="worddb-empty-icon">📚</div>
      <div class="worddb-empty-title">暂无${this._getCategoryTitle().split('\n')[0]}记录</div>
      <div class="worddb-empty-desc">点击上方「+ 新增」添加第一条${this.CATEGORY_TITLES[this.state.category] || '词语'}，或导入示例数据</div>
      <button class="worddb-import-btn" id="worddb-import-sample">📥 导入示例数据</button>
    `;
    container.appendChild(empty);
    empty.querySelector('#worddb-import-sample').addEventListener('click', () => {
      this._importSampleData();
    });
  },

  // ===== 实词组辨析新增/编辑 =====
  async _showCompareForm(existingWord) {
    const isEdit = !!existingWord;
    const word = existingWord ? Object.assign({}, existingWord) : {
      category: 'word-compare',
      module: this.state.module,
      subject: this.state.subject,
      name: '',
      meaning: '',
      example: '',
      compareNote: '',
      compareWords: [
        { name: '', meaning: '', wordId: null },
        { name: '', meaning: '', wordId: null }
      ],
      relatedErrorIds: []
    };
    const legacyCompare = isEdit && !Array.isArray(existingWord.compareWords);
    word.compareWords = this._getCompareTerms(word).map(term => ({
      name: term.name,
      meaning: term.meaning,
      wordId: term.wordId || null
    }));
    while (word.compareWords.length < 2) {
      word.compareWords.push({ name: '', meaning: '', wordId: null });
    }

    const overlay = document.createElement('div');
    overlay.className = 'cp-overlay';
    const card = document.createElement('div');
    card.className = 'cp-card cp-card--form worddb-compare-form';

    const header = document.createElement('div');
    header.className = 'cp-header';
    header.innerHTML = '<span class="cp-title">' + (isEdit ? '编辑' : '新增') + '实词辨析</span>';
    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'cp-close';
    closeBtn.textContent = '✕';
    closeBtn.addEventListener('click', () => overlay.remove());
    header.appendChild(closeBtn);
    card.appendChild(header);

    const form = document.createElement('div');
    form.className = 'worddb-form';
    const termsList = document.createElement('div');
    termsList.className = 'worddb-compare-terms-editor';
    form.appendChild(termsList);

    const renderTerms = () => {
      termsList.innerHTML = '';
      word.compareWords.forEach((term, index) => {
        const block = document.createElement('div');
        block.className = 'worddb-compare-term-editor';
        const head = document.createElement('div');
        head.className = 'worddb-compare-term-editor__head';
        const isReadonlyExtra = index >= 2;
        const label = document.createElement('span');
        label.textContent = isReadonlyExtra ? '词语 ' + (index + 1) + '（当前只读）' : '词语 ' + (index + 1);
        const linkBtn = document.createElement('button');
        linkBtn.type = 'button';
        linkBtn.className = 'worddb-term-link-btn';
        linkBtn.hidden = true;
        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'worddb-form-input';
        input.placeholder = '输入词语名称';
        input.value = term.name || '';
        const meaning = document.createElement('textarea');
        meaning.className = 'worddb-form-textarea';
        meaning.placeholder = '输入该词的独立解释（可选）';
        meaning.value = term.meaning || '';

        const updateLinkHint = () => {
          const query = input.value.trim().toLowerCase();
          const match = (this.state.definitionWords || []).find(item => (item.name || '').trim().toLowerCase() === query);
          const linked = term.wordId && (this.state.definitionWords || []).find(item => item.id === term.wordId);
          if (match && match.id !== term.wordId) {
            linkBtn.hidden = false;
            linkBtn.textContent = '关联已有实词：' + match.name;
            linkBtn.onclick = () => {
              term.wordId = match.id;
              if (!term.meaning.trim()) {
                term.meaning = match.meaning || '';
                meaning.value = term.meaning;
              }
              updateLinkHint();
            };
          } else if (linked) {
            linkBtn.hidden = false;
            linkBtn.textContent = '已关联：' + linked.name;
            linkBtn.onclick = () => { term.wordId = null; updateLinkHint(); };
          } else {
            linkBtn.hidden = true;
            linkBtn.textContent = '';
            linkBtn.onclick = null;
          }
        };
        if (isReadonlyExtra) {
          input.readOnly = true;
          meaning.readOnly = true;
          linkBtn.hidden = true;
        } else {
          input.addEventListener('input', () => {
            term.name = input.value;
            updateLinkHint();
          });
          meaning.addEventListener('input', () => { term.meaning = meaning.value; });
        }
        if (!isReadonlyExtra) updateLinkHint();

        head.appendChild(label);
        head.appendChild(linkBtn);
        block.appendChild(head);
        block.appendChild(input);
        block.appendChild(meaning);

        if (isReadonlyExtra) block.classList.add('worddb-compare-term-editor--readonly');
        termsList.appendChild(block);
      });
    };
    renderTerms();

    const coreGroup = document.createElement('div');
    coreGroup.className = 'worddb-form-group';
    coreGroup.innerHTML = '<label class="worddb-form-label">核心区别</label>';
    const coreInput = document.createElement('textarea');
    coreInput.className = 'worddb-form-textarea';
    coreInput.placeholder = '输入这组词语的核心区别';
    coreInput.value = word.compareNote || '';
    coreGroup.appendChild(coreInput);
    form.appendChild(coreGroup);

    const exampleGroup = document.createElement('div');
    exampleGroup.className = 'worddb-form-group';
    exampleGroup.innerHTML = '<label class="worddb-form-label">例句（可选）</label>';
    const exampleInput = document.createElement('textarea');
    exampleInput.className = 'worddb-form-textarea';
    exampleInput.placeholder = '输入例句';
    exampleInput.value = word.example || '';
    exampleGroup.appendChild(exampleInput);
    form.appendChild(exampleGroup);
    card.appendChild(form);

    const footer = document.createElement('div');
    footer.className = 'cp-cancel-row';
    const saveBtn = document.createElement('button');
    saveBtn.type = 'button';
    saveBtn.className = 'cp-cancel-btn';
    saveBtn.style.cssText = 'background:var(--color-primary);color:#fff;font-weight:600;';
    saveBtn.textContent = '保存';
    saveBtn.addEventListener('click', async () => {
      const validTerms = word.compareWords.filter(term => term.name.trim());
      if (validTerms.length < 2 && !legacyCompare) {
        App.Components.toast('至少需要填写两个词语', 'error');
        return;
      }
      if (!validTerms.length) {
        App.Components.toast('请输入词语名称', 'error');
        return;
      }
      word.compareWords = word.compareWords.map(term => ({
        name: term.name.trim(),
        meaning: term.meaning.trim(),
        wordId: term.wordId || null
      })).filter(term => term.name || term.meaning);
      word.compareNote = coreInput.value.trim();
      word.example = exampleInput.value.trim();
      this._syncCompareWordFields(word);
      try {
        if (isEdit) await App.DB.updateWord(word);
        else await App.DB.addWord(word);
        overlay.remove();
        if (!isEdit) this.state.expandedRowId = word.id;
        this._refreshTable();
        App.Components.toast('已保存', 'success');
      } catch (error) {
        console.error(error);
        App.Components.toast('保存失败，请重试', 'error');
      }
    });
    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'cp-cancel-btn';
    cancelBtn.textContent = '取消';
    cancelBtn.addEventListener('click', () => overlay.remove());
    footer.appendChild(saveBtn);
    footer.appendChild(cancelBtn);
    card.appendChild(footer);

    overlay.appendChild(card);
    overlay.addEventListener('click', event => { if (event.target === overlay) overlay.remove(); });
    document.getElementById('modal-container').appendChild(overlay);
  },

  // ===== 新增/编辑弹窗表单 =====
  async _showWordForm(existingWord) {
    if (this.state.category === 'word-compare') return this._showCompareForm(existingWord);
    const isEdit = !!existingWord;
    const word = existingWord || {
      category: this.state.category,
      module: this.state.module,
      subject: this.state.subject,
      name: '',
      pinyin: '',
      meaning: '',
      example: '',
      sentiment: '',
      tags: [],
      groupId: null,
      compareNote: '',
      myUnderstanding: '',
      collocations: '',
      source: '',
      wordAId: null,
      wordBId: null,
      antonyms: [],
      synonyms: [],
      relatedErrorIds: []
    };

    // 创建居中弹窗表单
    const overlay = document.createElement('div');
    overlay.className = 'cp-overlay';

    const card = document.createElement('div');
    card.className = 'cp-card cp-card--form';

    // 标题行
    const header = document.createElement('div');
    header.className = 'cp-header';
    header.innerHTML = `<span class="cp-title">${isEdit ? '编辑' : '新增'}${this.CATEGORY_TITLES[this.state.category] || '词语'}</span>`;
    const closeBtn = document.createElement('button');
    closeBtn.className = 'cp-close';
    closeBtn.innerHTML = '✕';
    closeBtn.addEventListener('click', () => { overlay.remove(); });
    header.appendChild(closeBtn);
    card.appendChild(header);

    // 表单内容
    const form = document.createElement('div');
    form.className = 'worddb-form';

    const isWordDefinition = this.state.category === 'word-def';
    const isWordCompare = this.state.category === 'word-compare';
    let linkedFields = null;

    if (isWordCompare) {
      linkedFields = document.createElement('div');
      linkedFields.className = 'worddb-linked-form-fields';
      linkedFields.innerHTML = `
        <div class="worddb-form-group">
          <label class="worddb-form-label">词语A *</label>
          <button type="button" class="worddb-form-picker worddb-word-picker" id="wf-word-a">${this._escapeHtml(this._getLinkedWordName(word.wordAId))}</button>
        </div>
        <div class="worddb-form-group">
          <label class="worddb-form-label">词语B *</label>
          <button type="button" class="worddb-form-picker worddb-word-picker" id="wf-word-b">${this._escapeHtml(this._getLinkedWordName(word.wordBId))}</button>
        </div>
      `;
    }

    // 词语名称
    form.innerHTML = `
      <div class="worddb-form-group">
        <label class="worddb-form-label">名称 *</label>
        <input type="text" class="worddb-form-input" id="wf-name" value="${this._escapeHtml(word.name)}" placeholder="输入${this.CATEGORY_TITLES[this.state.category] || '词语'}名称"${isWordCompare ? ' readonly' : ''}>
      </div>
      <div class="worddb-form-group">
        <label class="worddb-form-label">拼音</label>
        <input type="text" class="worddb-form-input" id="wf-pinyin" value="${this._escapeHtml(word.pinyin || '')}" placeholder="拼音（可选）">
      </div>
      <div class="worddb-form-group">
        <label class="worddb-form-label">释义 *</label>
        <textarea class="worddb-form-textarea" id="wf-meaning" placeholder="输入详细释义...">${this._escapeHtml(word.meaning || '')}</textarea>
      </div>
      <div class="worddb-form-group">
        <label class="worddb-form-label">例句</label>
        <textarea class="worddb-form-textarea" id="wf-example" placeholder="输入例句...">${this._escapeHtml(word.example || '')}</textarea>
      </div>
      <div class="worddb-form-group">
        <label class="worddb-form-label">感情色彩</label>
        <div id="wf-sentiment-btn" class="worddb-form-picker">${word.sentiment || '+ 选择感情色彩'}</div>
      </div>
    `;

    if (isWordCompare) {
      const nameGroup = form.firstElementChild;
      form.insertBefore(linkedFields, nameGroup);
      const syncLinkedWords = () => {
        const aName = this._getLinkedWordName(word.wordAId);
        const bName = this._getLinkedWordName(word.wordBId);
        form.querySelector('#wf-word-a').textContent = aName;
        form.querySelector('#wf-word-b').textContent = bName;
        form.querySelector('#wf-name').value = (word.wordAId && word.wordBId) ? aName + ' vs ' + bName : (word.name || '');
      };
      form.querySelector('#wf-word-a').addEventListener('click', async () => {
        const selected = await this._pickWordEntity('选择词语A', word.wordBId);
        if (!selected) return;
        word.wordAId = selected.id;
        syncLinkedWords();
      });
      form.querySelector('#wf-word-b').addEventListener('click', async () => {
        const selected = await this._pickWordEntity('选择词语B', word.wordAId);
        if (!selected) return;
        word.wordBId = selected.id;
        syncLinkedWords();
      });
    }

    if (isWordDefinition) {
      const personalFields = document.createElement('div');
      personalFields.innerHTML = `
        <div class="worddb-form-group">
          <label class="worddb-form-label">我的理解</label>
          <textarea class="worddb-form-textarea" id="wf-understanding" placeholder="记录自己的理解...">${this._escapeHtml(word.myUnderstanding || '')}</textarea>
        </div>
        <div class="worddb-form-group">
          <label class="worddb-form-label">常见搭配</label>
          <textarea class="worddb-form-textarea" id="wf-collocations" placeholder="如：经验不足、准备不足...">${this._escapeHtml(word.collocations || '')}</textarea>
        </div>
        <div class="worddb-form-group">
          <label class="worddb-form-label">来源</label>
          <input type="text" class="worddb-form-input" id="wf-source" value="${this._escapeHtml(word.source || '')}" placeholder="如：手动整理">
        </div>
      `;
      form.appendChild(personalFields);
    }

    // 辨析类额外字段
    if (this.state.category.includes('compare')) {
      const extra = document.createElement('div');
      extra.innerHTML = `
        <div class="worddb-form-group">
          <label class="worddb-form-label">辨析要点</label>
          <textarea class="worddb-form-textarea" id="wf-compare" placeholder="输入辨析要点...">${this._escapeHtml(word.compareNote || '')}</textarea>
        </div>
      `;
      form.appendChild(extra.firstElementChild);
    }

    card.appendChild(form);

    // 感情色彩选择器绑定
    const sentBtn = form.querySelector('#wf-sentiment-btn');
    let selectedSentiment = word.sentiment || '';
    const renderSentBtn = () => {
      if (selectedSentiment) {
        sentBtn.textContent = selectedSentiment;
        sentBtn.style.color = selectedSentiment === '褒义' ? '#2E7D32'
          : selectedSentiment === '贬义' ? '#C62828' : '#616161';
      } else {
        sentBtn.textContent = '+ 选择感情色彩';
        sentBtn.style.color = '';
      }
    };
    renderSentBtn();
    sentBtn.addEventListener('click', async () => {
      const opts = this.SENTIMENTS.map(s => ({
        icon: s === '褒义' ? '😊' : s === '贬义' ? '😠' : '😐',
        label: s,
        value: s,
        desc: s === '褒义' ? '积极正面' : s === '贬义' ? '消极负面' : '中立客观'
      }));
      const sel = await App.Components.centeredPicker(opts, '选择感情色彩', '选择该词语的感情色彩倾向');
      if (sel) {
        selectedSentiment = sel;
        renderSentBtn();
      }
    });

    // 底部按钮
    const footer = document.createElement('div');
    footer.className = 'cp-cancel-row';
    const saveBtn = document.createElement('button');
    saveBtn.className = 'cp-cancel-btn';
    saveBtn.style.cssText = 'background:var(--color-primary);color:#fff;font-weight:600;';
    saveBtn.textContent = '保存';
    saveBtn.addEventListener('click', async () => {
      word.name = form.querySelector('#wf-name').value.trim();
      word.pinyin = form.querySelector('#wf-pinyin').value.trim();
      word.meaning = form.querySelector('#wf-meaning').value.trim();
      word.example = form.querySelector('#wf-example').value.trim();
      word.sentiment = selectedSentiment;
      if (isWordDefinition) {
        word.myUnderstanding = form.querySelector('#wf-understanding').value.trim();
        word.collocations = form.querySelector('#wf-collocations').value.trim();
        word.source = form.querySelector('#wf-source').value.trim();
      }
      if (isWordCompare) {
        word.name = form.querySelector('#wf-name').value.trim();
        if ((!word.wordAId || !word.wordBId) && !isEdit) {
          App.Components.toast('请选择词语A和词语B', 'error');
          return;
        }
        if ((word.wordAId && !word.wordBId) || (!word.wordAId && word.wordBId)) {
          App.Components.toast('请完整选择词语A和词语B', 'error');
          return;
        }
      }

      const cmpEl = form.querySelector('#wf-compare');
      if (cmpEl) word.compareNote = cmpEl.value.trim();

      if (!word.name) { App.Components.toast('请输入名称', 'error'); return; }
      if (!word.meaning) { App.Components.toast('请输入释义', 'error'); return; }

      try {
        if (isEdit) {
          await App.DB.updateWord(word);
          App.Components.toast('已更新 ✓', 'success');
        } else {
          await App.DB.addWord(word);
          App.Components.toast('已保存 ✓', 'success');
        }
        overlay.remove();
        this._refreshTable();
      } catch (e) {
        console.error(e);
        App.Components.toast('保存失败，请重试', 'error');
      }
    });

    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'cp-cancel-btn';
    cancelBtn.textContent = '取消';
    cancelBtn.addEventListener('click', () => { overlay.remove(); });
    footer.appendChild(saveBtn);
    footer.appendChild(cancelBtn);
    card.appendChild(footer);

    overlay.appendChild(card);
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) overlay.remove();
    });

    document.getElementById('modal-container').appendChild(overlay);
  },

  async _pickWordEntity(title, excludedId) {
    const candidates = await App.DB.getWords({
      category: 'word-def',
      subject: this.state.subject,
      module: this.state.module
    });
    const available = candidates.filter(w => w.id !== excludedId);
    if (!available.length) {
      App.Components.toast('请先在「实词释义」中新增可选词语', 'info');
      return null;
    }

    return new Promise(resolve => {
      const overlay = document.createElement('div');
      overlay.className = 'cp-overlay';
      const card = document.createElement('div');
      card.className = 'cp-card worddb-word-selector';
      card.innerHTML = '<div class="cp-header"><span class="cp-title">' + this._escapeHtml(title) + '</span></div>';
      const close = document.createElement('button');
      close.className = 'cp-close';
      close.textContent = '✕';
      const finish = (value) => { overlay.remove(); resolve(value || null); };
      close.addEventListener('click', () => finish(null));
      card.querySelector('.cp-header').appendChild(close);

      const search = document.createElement('input');
      search.type = 'search';
      search.className = 'worddb-form-input worddb-word-selector__search';
      search.placeholder = '搜索已有实词…';
      card.appendChild(search);
      const list = document.createElement('div');
      list.className = 'worddb-word-selector__list';
      const renderList = () => {
        const query = search.value.trim().toLowerCase();
        const filtered = available.filter(w => !query || (w.name || '').toLowerCase().includes(query) || (w.pinyin || '').toLowerCase().includes(query) || (w.meaning || '').toLowerCase().includes(query));
        list.innerHTML = '';
        if (!filtered.length) {
          list.innerHTML = '<div class="worddb-word-selector__empty">未找到匹配的实词</div>';
          return;
        }
        filtered.forEach(item => {
          const button = document.createElement('button');
          button.type = 'button';
          button.className = 'worddb-word-selector__item';
          button.innerHTML = '<strong>' + this._escapeHtml(item.name) + '</strong>' + (item.pinyin ? '<span>' + this._escapeHtml(item.pinyin) + '</span>' : '') + (item.meaning ? '<small>' + this._escapeHtml(item.meaning) + '</small>' : '');
          button.addEventListener('click', () => finish(item));
          list.appendChild(button);
        });
      };
      search.addEventListener('input', renderList);
      renderList();
      card.appendChild(list);
      overlay.appendChild(card);
      overlay.addEventListener('click', e => { if (e.target === overlay) finish(null); });
      document.getElementById('modal-container').appendChild(overlay);
      setTimeout(() => search.focus(), 0);
    });
  },

  // ===== 关联错题 =====
  async _linkError(word) {
    const errors = await App.DB.getErrors({ subject: this.state.subject, module: this.state.module });
    const linkedIds = word.relatedErrorIds || [];
    const available = errors.filter(e => !linkedIds.includes(e.id));

    if (available.length === 0) {
      App.Components.toast('该模块暂无可关联的错题', 'info');
      return;
    }

    const opts = available.slice(0, 10).map(e => ({
      icon: '📋',
      label: (e.question || '').slice(0, 25),
      desc: e.errorCause || '未分类',
      value: e.id
    }));

    const sel = await App.Components.centeredPicker(opts, '选择要关联的错题', '选择后会将此词语与错题双向关联');
    if (sel) {
      if (!word.relatedErrorIds) word.relatedErrorIds = [];
      word.relatedErrorIds.push(sel);
      await App.DB.updateWord(word);

      // 双向：error 也记录关联
      const err = await App.DB.get('errors', sel);
      if (err) {
        if (!err.relatedWordIds) err.relatedWordIds = [];
        if (!err.relatedWordIds.includes(word.id)) {
          err.relatedWordIds.push(word.id);
          await App.DB.updateError(err);
        }
      }

      this._refreshTable();
      App.Components.toast('已关联 ✓', 'success');
    }
  },

  // ===== 导入示例数据 =====
  async _importSampleData() {
    const samples = this._getSampleData();
    for (const s of samples) {
      s.category = this.state.category;
      s.module = this.state.module;
      s.subject = this.state.subject;
      await App.DB.addWord(s);
    }
    App.Components.toast('已导入 ' + samples.length + ' 条示例数据 ✓', 'success');
    this._loadAndRender(document.getElementById('worddb-table-area'));
  },

  _getSampleData() {
    switch (this.state.category) {
      case 'idiom-def':
        return [
          { name: '寡见鲜闻', pinyin: 'guǎ jiàn xiān wén', meaning: '很少见到，极为罕见。形容事物稀少或珍贵。', example: '这种现象真是寡见鲜闻，值得深入研究。', sentiment: '贬义', tags: ['高频'] },
          { name: '不一而足', pinyin: 'bù yī ér zú', meaning: '不止一种或一次。指同类事物或情况很多。', example: '造成错误的原因不一而足，需要逐一排查。', sentiment: '中性', tags: ['高频'] },
          { name: '更仆难尽', pinyin: 'gèng pū nán jìn', meaning: '形容数量极多，难以一一列举。', example: '这类问题更仆难尽，无法在短时间内完全解决。', sentiment: '中性', tags: [] },
          { name: '亦庄亦谐', pinyin: 'yì zhuāng yì xié', meaning: '既庄重又风趣幽默。形容风格兼具严肃与轻松。', example: '他的讲课风格亦庄亦谐，深受学生喜爱。', sentiment: '褒义', tags: [] },
          { name: '以邻为壑', pinyin: 'yǐ lín wéi hè', meaning: '把邻国当作排水沟。比喻只顾自己利益，把困难转嫁给别人。', example: '这种以邻为壑的做法是不负责任的。', sentiment: '贬义', tags: ['易混淆'] },
          { name: '步步为营', pinyin: 'bù bù wéi yíng', meaning: '军队每向前推进一步就设下一道营垒。形容行动谨慎，稳扎稳打。', example: '复习要步步为营，切忌贪多求快。', sentiment: '褒义', tags: ['高频'] },
          { name: '山重水复', pinyin: 'shān chóng shuǐ fù', meaning: '山峦重叠，河流曲折。形容道路艰难曲折，也比喻事情经历许多周折。', example: '经过山重水复的努力，终于找到了正确答案。', sentiment: '中性', tags: [] },
          { name: '钟灵毓秀', pinyin: 'zhōng líng yù xiù', meaning: '凝聚了天地的灵气，孕育了优秀人物。形容山川秀美，人才辈出。', example: '江南之地钟灵毓秀，历代文人墨客辈出。', sentiment: '褒义', tags: [] },
          { name: '深入浅出', pinyin: 'shē rù qiǎn chū', meaning: '讲话或文章的内容深刻，语言文字却浅显易懂。', example: '这本书深入浅出地讲解了复杂的算法原理。', sentiment: '褒义', tags: ['高频'] },
          { name: '微言大义', pinyin: 'wēi yán dà yì', meaning: '精微的语言中包含深刻的道理。', example: '孔子之言微言大义，值得反复品味。', sentiment: '褒义', tags: [] },
          { name: '丝丝入扣', pinyin: 'sī sī rù kòu', meaning: '形容织布纹理紧密，也形容文章或艺术表演十分细致，合乎规范。', example: '他的分析丝丝入扣，逻辑严密。', sentiment: '褒义', tags: [] },
          { name: '笔底生花', pinyin: 'bǐ dǐ shēng huā', meaning: '形容文采斐然，笔下生辉。', example: '这位作家的文章笔底生花，读来令人陶醉。', sentiment: '褒义', tags: [] },
          { name: '舌战群儒', pinyin: 'shé zhàn qún rú', meaning: '同很多人辩论。形容能言善辩，口才好。', example: '他在辩论会上舌战群儒，无人能敌。', sentiment: '褒义', tags: [] }
        ];
      case 'idiom-compare':
        return [
          { name: '屡见不鲜 vs 寡见鲜闻', groupId: 'g1', meaning: '都表示"常见"，但"屡见不鲜"偏中性，"寡见鲜闻"含贬义，强调不该发生的事却出现了。', compareNote: '"屡见不鲜"用于描述常见现象；"寡见鲜闻"带有批评意味，指本不该出现的情况却频繁出现。', sentiment: '中性', tags: ['易混淆'] },
          { name: '不以为然 vs 不以为意', groupId: 'g2', meaning: '"不以为然"=不认为是对的（不同意）；"不以为意"=不放在心上（不在意）。', compareNote: '前者是对观点的态度，后者是对事物的重视程度。注意"然"和"意"的区别。', sentiment: '中性', tags: ['易混淆'] },
          { name: '一蹴而就 vs 一劳永逸', groupId: 'g3', meaning: '"一蹴而就"=一步成功（强调容易）；"一劳永逸"=辛苦一次永久受益（强调彻底）。', compareNote: '前者侧重过程简单快捷；后者侧重结果持久稳定。考题中常考查语境区分。', sentiment: '中性', tags: ['高频'] },
          { name: '按部就班 vs 循序渐进', groupId: 'g4', meaning: '"按部就班"=按照一定步骤/条理办事；"循序渐进"=由浅入深逐步推进。', compareNote: '两者都强调有步骤有顺序，但"按部就班"偏重遵循既定程序，"循序渐进"偏重程度递进。', sentiment: '中性', tags: [] }
        ];
      case 'word-def':
        return [
          { name: '贯彻', pos: '动词', meaning: '彻底实现或体现（方针、政策、精神等）。', example: '我们必须贯彻执行这一政策。', sentiment: '中性', tags: ['高频'] },
          { name: '落实', pos: '动词', meaning: '使计划、措施等得以实现和完成。', example: '要把会议精神落实到具体工作中去。', sentiment: '中性', tags: ['高频'] },
          { name: '鉴于', pos: '介词/连词', meaning: '考虑到；由于，表示以某种情况为前提。', example: '鉴于当前形势，我们需要调整策略。', sentiment: '中性', tags: [] },
          { name: '亟待', pos: '副词', meaning: '急切地等待；迫切需要。', example: '这一问题亟待解决。', sentiment: '中性', tags: ['高频'] },
          { name: '毋庸', pos: '副词', meaning: '无须；不用（多用于"置疑""讳言"等）。', example: '毋庸置疑，这是最佳方案。', sentiment: '中性', tags: [] },
          { name: '乃至', pos: '连词', meaning: '甚至；以至于（表示程度加深或范围扩大）。', example: '这个问题影响到公司乃至整个行业。', sentiment: '中性', tags: [] },
          { name: '大致', pos: '副词/形容词', meaning: '大体上；基本上。', example: '情况大致如他所料。', sentiment: '中性', tags: [] },
          { name: '往往', pos: '副词', meaning: '常常；经常（表示某种情况具有规律性）。', example: '这类题目往往设置陷阱。', sentiment: '中性', tags: ['高频'] },
          { name: '不免', pos: '副词', meaning: '免不了；难免（表示某种情况不可避免）。', example: '初学者在这一点上不免会犯错。', sentiment: '中性', tags: [] },
          { name: '倘若', pos: '连词', meaning: '如果；假如（用于假设语气）。', example: '倘若明天下雨，比赛将延期举行。', sentiment: '中性', tags: [] }
        ];
      case 'word-compare':
        return [
          { name: '贯彻 vs 落实', groupId: 'w1', pos: '动词', meaning: '都表示"执行/实现"，但"贯彻"强调自上而下彻底执行，"落实"强调使计划落地变为现实。', compareNote: '"贯彻"多接方针/政策/精神；"落实"多接计划/措施/任务。', sentiment: '中性', tags: ['易混淆'] },
          { name: '鉴于 vs 由于', groupId: 'w2', pos: '介词/连词', meaning: '都可用于引出原因/依据，但"鉴于"更正式，常用于公文；"由于"更通用。', compareNote: '"鉴于"隐含"考虑到"之意，语气更强；"由于"是纯因果引出。', sentiment: '中性', tags: ['易混淆'] },
          { name: '亟待 vs 急需', groupId: 'w3', pos: '副词', meaning: '都表示"急需"，但"亟待"更正式，强调客观上的紧迫性；"急需"可主观可客观。', compareNote: '"亟待"多用于书面语、官方表述；"急需"口语书面均可。', sentiment: '中性', tags: [] },
          { name: '乃至 vs 甚至', groupId: 'w4', pos: '连词', meaning: '都表示递进/范围扩展，"乃至"更正式，"甚至"更口语化。', compareNote: '两者可互换使用，但"乃至"在公文中更常见。', sentiment: '中性', tags: [] }
        ];
      default:
        return [
          { name: '示例词语', meaning: '这是一个示例', example: '这是例句', sentiment: '中性', tags: [] }
        ];
    }
  },

  // ===== 数据加载 =====
  async _loadWords() {
    const filters = {
      category: this.state.category,
      subject: this.state.subject,
      module: this.state.module,
      sentiment: this.state.sentiment || null
    };
    // 实词组辨析的搜索还要覆盖每个词的独立解释与核心区别，故在本地补充筛选。
    if (this.state.category !== 'word-compare') filters.search = this.state.searchQuery;
    this.state.words = await App.DB.getWords(filters);
    if (this.state.category === 'word-compare' && this.state.searchQuery.trim()) {
      const query = this.state.searchQuery.trim().toLowerCase();
      this.state.words = this.state.words.filter(word => {
        const terms = Array.isArray(word.compareWords) ? word.compareWords : [];
        const haystack = [
          word.name,
          word.meaning,
          word.compareNote,
          ...terms.flatMap(term => [term && term.name, term && term.meaning])
        ].filter(Boolean).join('\n').toLowerCase();
        return haystack.includes(query);
      });
    }
    if (this.state.category === 'word-compare') {
      this.state.words.sort((a, b) => new Date(b.updatedAt || b.createdAt || 0) - new Date(a.updatedAt || a.createdAt || 0));
    }
    if (this.state.category === 'word-compare') {
      this.state.definitionWords = await App.DB.getWords({
        category: 'word-def', subject: this.state.subject, module: this.state.module
      });
    } else {
      this.state.definitionWords = [];
    }
  },

  async _refreshTable() {
    const tableArea = document.getElementById('worddb-table-area');
    if (!tableArea) return;
    await this._loadWords();
    this._renderTable(tableArea);
  },

  // ===== 工具方法 =====
  _escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
};
