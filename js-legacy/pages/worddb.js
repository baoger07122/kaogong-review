// ===== 考公笔试复盘系统 - 词语库页面（Notion 数据库风格） =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.WordDB = {
  state: {
    category: null,
    words: [],
    searchQuery: '',
    sentiment: '',
    sortBy: 'name',
    expandedRowId: null,
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

    // 返回栏 + 标题
    container.appendChild(App.Components.pageHeader(
      this._getCategoryTitle(),
      '导入',
      () => { this._importSampleData(); }
    ));

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

  // ===== 表格渲染 =====
  async _loadAndRender(tableArea) {
    await this._loadWords();
    this._renderTable(tableArea);
  },

  _renderTable(tableArea) {
    tableArea.innerHTML = '';

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
    return ['名称', '属性', '更新时间', '操作'];
  },

  _renderRow(word, idx) {
    const row = document.createElement('div');
    row.className = 'worddb-row';
    row.dataset.id = word.id;

    const isExpanded = this.state.expandedRowId === word.id;
    if (isExpanded) row.classList.add('expanded');

    // 行主区域（始终可见）
    const main = document.createElement('div');
    main.className = 'worddb-row__main';

    // 名称列
    const nameCell = document.createElement('div');
    nameCell.className = 'worddb-cell worddb-cell--name';
    nameCell.textContent = word.name;
    main.appendChild(nameCell);

    // 属性列（感情色彩 / 词性 / 成员数）
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
    if (this.state.category.includes('compare')) {
      const count = (word.members && word.members.length) ||
        (word.name ? word.name.split(/\s*(?:vs|对比|、)\s*/).length : 1);
      const mTag = document.createElement('span');
      mTag.className = 'worddb-mcount-tag';
      mTag.textContent = count + ' 个成员';
      propCell.appendChild(mTag);
    }
    main.appendChild(propCell);

    // 时间列
    const timeCell = document.createElement('div');
    timeCell.className = 'worddb-cell worddb-cell--time';
    timeCell.textContent = (word.updatedAt || word.createdAt || '').slice(0, 10);
    main.appendChild(timeCell);

    // 操作列
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

    row.appendChild(main);

    // 展开详情区
    if (isExpanded) {
      const detail = this._renderDetail(word);
      row.appendChild(detail);
    }

    // 点击行主区域展开/收起
    main.addEventListener('click', (e) => {
      if (e.target.closest('.worddb-open-btn')) return;
      this.state.expandedRowId = isExpanded ? null : word.id;
      this._refreshTable();
    });

    return row;
  },

  // ===== 展开详情 =====
  _renderDetail(word) {
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
      cmp.innerHTML = '<strong>辨析要点</strong><div class="worddb-detail-text">' + this._escapeHtml(word.compareNote).replace(/\n/g, '<br>') + '</div>';
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

  // ===== 新增/编辑弹窗表单 =====
  async _showWordForm(existingWord) {
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

    // 词语名称
    form.innerHTML = `
      <div class="worddb-form-group">
        <label class="worddb-form-label">名称 *</label>
        <input type="text" class="worddb-form-input" id="wf-name" value="${this._escapeHtml(word.name)}" placeholder="输入${this.CATEGORY_TITLES[this.state.category] || '词语'}名称">
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
    this.state.words = await App.DB.getWords({
      category: this.state.category,
      subject: this.state.subject,
      module: this.state.module,
      search: this.state.searchQuery,
      sentiment: this.state.sentiment || null
    });
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
