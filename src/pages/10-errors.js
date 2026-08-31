// ===== 考公笔试复盘系统 - 错题本页面 =====
// ===== 考公笔试复盘系统 - 错题本页面 =====
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
    searchVisible: false,
    allErrors: [],
    allNotes: [],
    allStickies: [],
    view: 'wrong',
    noteType: null,
    gallerySize: 'md',   // 画廊窗口大小: sm 小 / md 中 / lg 大
    gallerySizeAuto: true // 是否自动根据窗口宽度选择密度（用户手动切换后变为 false）
  },

  // 根据错题自身的科目/模块生成列表路由，避免详情页依赖浏览器历史返回。
  _buildErrorListRoute(error) {
    const query = [];
    if (error && error.subject) query.push('subject=' + encodeURIComponent(error.subject));
    if (error && error.module) query.push('module=' + encodeURIComponent(error.module));
    return 'errors' + (query.length ? '?' + query.join('&') : '');
  },

  _buildErrorDetailRoute(error, edit) {
    const id = error && error.id != null ? encodeURIComponent(String(error.id)) : '';
    return 'error-detail?id=' + id + (edit ? '&edit=1' : '');
  },

  _buildErrorEditRoute(error) {
    const id = error && error.id != null ? encodeURIComponent(String(error.id)) : '';
    const returnTo = this._buildErrorListRoute(error);
    return 'error-form?id=' + id + '&returnTo=' + encodeURIComponent(returnTo);
  },

  // v8.12.30 错题本侧边栏 SVG 图标（像素级还原设计稿：直接引用设计稿导出路径，fill/stroke 用 currentColor）
  // 每科目图标形状与设计稿 7:688/700/729/738/749/757 完全一致；颜色由外层 style(color) 控制（未选中主题色/选中蓝）
  _subjectIconSvg(subjectName) {
    const ICON = {
      全部: '<svg width="20" height="20" viewBox="0 0 20 20"><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 2.5 2.5)" width="5.8333" height="5.8333" rx="1.25" ry="1.25"/><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 11.6667 2.5)" width="5.8333" height="5.8333" rx="1.25" ry="1.25"/><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 2.5 11.6667)" width="5.8333" height="5.8333" rx="1.25" ry="1.25"/><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 11.6667 11.6667)" width="5.8333" height="5.8333" rx="1.25" ry="1.25"/></svg>',
      言语理解: '<svg width="20" height="20" viewBox="0 0 20 20"><path fill="currentColor" transform="matrix(1 0 0 1 1.66667 1.66667)" d="M2.0833 -0.75Q0.9097 -0.75 0.0799 0.0799L0.0799 0.0799Q-0.75 0.9097 -0.75 2.0833L-0.75 16.25Q-0.759 16.5644 -0.5303 16.7803Q-0.3144 17.0091 0 17Q0.3144 17.0091 0.5303 16.7803Q0.759 16.5644 0.75 16.25Q0.75 15.6977 1.1405 15.3072Q1.531 14.9167 2.0833 14.9167L7.5 14.9167Q7.8144 14.9257 8.0303 14.697Q8.259 14.4811 8.25 14.1667L8.25 0Q8.259 -0.3144 8.0303 -0.5303Q7.8144 -0.759 7.5 -0.75L2.0833 -0.75ZM0.75 13.7411Q1.3495 13.4167 2.0833 13.4167L6.75 13.4167L6.75 0.75L2.0833 0.75Q1.531 0.75 1.1405 1.1405Q0.75 1.531 0.75 2.0833L0.75 13.7411Z" fill-rule="evenodd"/><path fill="currentColor" transform="matrix(1 0 0 1 10.8333 1.66667)" d="M8.25 2.0833Q8.25 0.9097 7.4201 0.0799Q6.5903 -0.75 5.4167 -0.75L0 -0.75Q-0.3144 -0.759 -0.5303 -0.5303Q-0.759 -0.3144 -0.75 0L-0.75 14.1667Q-0.759 14.4811 -0.5303 14.697Q-0.3144 14.9257 0 14.9167L5.4167 14.9167Q5.969 14.9167 6.3595 15.3072Q6.75 15.6977 6.75 16.25Q6.741 16.5644 6.9697 16.7803Q7.1856 17.0091 7.5 17Q7.8144 17.0091 8.0303 16.7803Q8.259 16.5644 8.25 16.25L8.25 2.0833ZM6.75 13.7411L6.75 2.0833Q6.75 1.531 6.3595 1.1405Q5.969 0.75 5.4167 0.75L0.75 0.75L0.75 13.4167L5.4167 13.4167Q6.1505 13.4167 6.75 13.7411Z" fill-rule="evenodd"/></svg>',
      资料分析: '<svg width="20" height="20" viewBox="0 0 20 20"><path fill="currentColor" transform="matrix(1 0 0 1 4.16667 3.75)" d="M5.303 -0.5303Q5.0743 -0.3144 5.0833 0L5.0833 13.3333Q5.0743 13.6477 5.303 13.8636Q5.5189 14.0924 5.8333 14.0833Q6.1477 14.0924 6.3636 13.8636Q6.5924 13.6477 6.5833 13.3333L6.5833 0Q6.5924 -0.3144 6.3637 -0.5303Q6.1477 -0.759 5.8333 -0.75Q5.5189 -0.759 5.303 -0.5303ZM-0.75 6.6667L-0.75 13.3333Q-0.759 13.6477 -0.5303 13.8636Q-0.3144 14.0924 0 14.0833Q0.3144 14.0924 0.5303 13.8636Q0.759 13.6477 0.75 13.3333L0.75 6.6667Q0.759 6.3523 0.5303 6.1363Q0.3144 5.9076 0 5.9167Q-0.3144 5.9076 -0.5303 6.1363Q-0.759 6.3523 -0.75 6.6667ZM10.9167 9.1667L10.9167 13.3333Q10.9076 13.6477 11.1363 13.8636Q11.3523 14.0924 11.6667 14.0833Q11.9811 14.0924 12.197 13.8636Q12.4257 13.6477 12.4167 13.3333L12.4167 9.1667Q12.4257 8.8523 12.197 8.6363Q11.9811 8.4076 11.6667 8.4167Q11.3523 8.4076 11.1363 8.6363Q10.9076 8.8523 10.9167 9.1667Z" fill-rule="evenodd"/><path fill="currentColor" transform="matrix(1 0 0 1 2.91667 17.0833)" d="M14.1667 -0.75L0 -0.75Q-0.3144 -0.759 -0.5303 -0.5303Q-0.759 -0.3144 -0.75 0Q-0.759 0.3144 -0.5303 0.5303Q-0.3144 0.759 0 0.75L14.1667 0.75Q14.4811 0.759 14.697 0.5303Q14.9257 0.3144 14.9167 0Q14.9257 -0.3144 14.697 -0.5303Q14.4811 -0.759 14.1667 -0.75Z" fill-rule="evenodd"/></svg>',
      判断推理: '<svg width="20" height="20" viewBox="0 0 20 20"><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 3.33333 3.33333)" width="5.8333" height="5.8333" rx="1.25" ry="1.25"/><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 10 3.33333)" width="6.6667" height="5.8333" rx="1.25" ry="1.25"/><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 3.33333 10.8333)" width="6.6667" height="5.8333" rx="1.25" ry="1.25"/><rect fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 11.6667 10.8333)" width="5" height="5.8333" rx="1.25" ry="1.25"/></svg>',
      数量关系: '<svg width="20" height="20" viewBox="0 0 20 20"><path fill="currentColor" transform="matrix(1 0 0 1 3.33333 3.33333)" d="M4.9167 3.4167L4.9167 0Q4.9257 -0.3144 4.697 -0.5303Q4.4811 -0.759 4.1667 -0.75Q3.8523 -0.759 3.6363 -0.5303Q3.4076 -0.3144 3.4167 0L3.4167 3.4167L0 3.4167Q-0.3144 3.4076 -0.5303 3.6363Q-0.759 3.8523 -0.75 4.1667Q-0.759 4.4811 -0.5303 4.697Q-0.3144 4.9257 0 4.9167L3.4167 4.9167L3.4167 8.4167L0 8.4167Q-0.3144 8.4076 -0.5303 8.6364Q-0.759 8.8523 -0.75 9.1667Q-0.759 9.4811 -0.5303 9.697Q-0.3144 9.9257 0 9.9167L3.4167 9.9167L3.4167 13.3333Q3.4076 13.6477 3.6363 13.8637Q3.8523 14.0924 4.1667 14.0833Q4.4811 14.0924 4.697 13.8637Q4.9257 13.6477 4.9167 13.3333L4.9167 9.9167L8.4167 9.9167L8.4167 13.3333Q8.4076 13.6477 8.6364 13.8637Q8.8523 14.0924 9.1667 14.0833Q9.4811 14.0924 9.697 13.8637Q9.9257 13.6477 9.9167 13.3333L9.9167 9.9167L13.3333 9.9167Q13.6477 9.9257 13.8637 9.697Q14.0924 9.4811 14.0833 9.1667Q14.0924 8.8523 13.8637 8.6364Q13.6477 8.4076 13.3333 8.4167L9.9167 8.4167L9.9167 4.9167L13.3333 4.9167Q13.6477 4.9257 13.8637 4.697Q14.0924 4.4811 14.0833 4.1667Q14.0924 3.8523 13.8637 3.6363Q13.6477 3.4076 13.3333 3.4167L9.9167 3.4167L9.9167 0Q9.9257 -0.3144 9.697 -0.5303Q9.4811 -0.759 9.1667 -0.75Q8.8523 -0.759 8.6364 -0.5303Q8.4076 -0.3144 8.4167 0L8.4167 3.4167L4.9167 3.4167ZM4.9167 4.9167L4.9167 8.4167L8.4167 8.4167L8.4167 4.9167L4.9167 4.9167Z" fill-rule="evenodd"/></svg>',
      常识判断: '<svg width="20" height="20" viewBox="0 0 20 20"><path fill="currentColor" transform="matrix(1 0 0 1 4.97378 2.49993)" d="M1.7471 0.2571Q3.2288 -0.7594 5.0251 -0.7499Q6.8136 -0.7594 8.2953 0.2571Q9.7768 1.2734 10.4161 2.9532Q11.0554 4.633 10.625 6.3781Q10.1945 8.1233 8.8476 9.3123Q8.8436 9.3158 8.8397 9.3192Q8.8357 9.3226 8.8316 9.326Q8.2687 9.7956 8.2687 10.4167Q8.2778 10.7311 8.049 10.9471Q7.8331 11.1758 7.5187 11.1667L2.5237 11.1667Q2.2093 11.1758 1.9934 10.9471Q1.7647 10.7311 1.7737 10.4167Q1.7737 9.7956 1.2108 9.326Q1.2068 9.3226 1.2028 9.3192Q1.1988 9.3158 1.1949 9.3123Q-0.1521 8.1233 -0.5826 6.3781Q-1.013 4.633 -0.3737 2.9532Q0.2656 1.2734 1.7471 0.2571ZM2.5956 1.494Q1.5008 2.2451 1.0282 3.4868Q0.5556 4.7287 0.8738 6.0189Q1.1908 7.3043 2.1804 8.1815Q2.9479 8.8254 3.1766 9.6667L6.8658 9.6667Q7.0946 8.8254 7.8621 8.1815Q8.8516 7.3043 9.1686 6.0189Q9.4869 4.7287 9.0143 3.4868Q8.5417 2.2451 7.4468 1.494Q6.3521 0.7431 5.0173 0.7501Q3.6903 0.7431 2.5956 1.494ZM7.5187 11.7501L2.5237 11.7501L2.5237 13.2501L7.5187 13.2501L7.5187 11.7501ZM6.6862 14.2501L3.3562 14.2501L3.3562 15.7501L6.6862 15.7501L6.6862 14.2501Z" fill-rule="evenodd"/></svg>',
      申论: '<svg width="20" height="20" viewBox="0 0 20 20"><path fill="none" stroke="currentColor" stroke-width="1.5" transform="matrix(1 0 0 1 3.5 2.5)" d="M5 -0.75H11.5L15.5 3.25V13.5A2 2 0 0 1 13.5 15.5H6.5A2 2 0 0 1 4.5 13.5V1.25Q4.4888 0.9556 4.6888 0.75Q4.9096 0.5258 5.22 0.53" fill-rule="evenodd"/><line x1="6.5" y1="6.5" x2="13.5" y2="6.5" stroke="currentColor" stroke-width="1.3"/><line x1="6.5" y1="10" x2="13.5" y2="10" stroke="currentColor" stroke-width="1.3"/></svg>',
    };
    return ICON[subjectName] || null;
  },

  async render(params) {
    const container = document.getElementById('page-errors');
    container.innerHTML = '';
    this.state.view = params && (params.view === 'notes' || params.tab === 'notes')
      ? 'notes'
      : (params && (params.view === 'stickies' || params.tab === 'stickies') ? 'stickies' : 'wrong');

    // 详情页返回会携带错题所属科目/模块；从 URL 恢复筛选上下文，
    // 这样直接刷新或复制链接打开列表时也不会退回到全部错题。
    const hasSubjectParam = params && Object.prototype.hasOwnProperty.call(params, 'subject');
    if (hasSubjectParam) {
      const requestedSubject = params.subject || null;
      const isKnownSubject = !!requestedSubject && App.Constants.SUBJECTS.some(s => s.name === requestedSubject);
      this.state.subject = isKnownSubject ? requestedSubject : null;
      const modules = this.state.subject ? App.Constants.getModules(this.state.subject) : [];
      this.state.module = (this.state.subject && params.module && modules.indexOf(params.module) !== -1)
        ? params.module : null;
      this.state.knowledgePoint = null;
      this.state.errorCause = null;
      this.state.status = null;
      this.state.noteType = null;
      this.state.search = '';
      this.state.searchVisible = false;
      this._expanded = this._expanded || {};
      if (this.state.subject && !App.Constants.isFlatSubject(this.state.subject)) {
        this._expanded[this.state.subject] = true;
      }
    }

    // 自动模式下根据窗口宽度选择画廊密度
    if (this.state.gallerySizeAuto) {
      const w = window.innerWidth;
      this.state.gallerySize = w < 600 ? 'sm' : (w < 1100 ? 'md' : 'lg');
    }

    // 左侧边栏（科目）+ 主内容区
    const layout = document.createElement('div');
    layout.className = 'with-sidebar';

    const sidebar = document.createElement('div');
    sidebar.className = 'sidebar';
    sidebar.id = 'error-sidebar';
    layout.appendChild(sidebar);

    const main = document.createElement('div');
    main.className = 'page-main';

    // 页面标题 + 搜索区 + 统计卡片区 → 打包进固定区（滚动时吸顶）
    const stickyWrap = document.createElement('div');
    stickyWrap.className = 'page-sticky';

    // 页面标题
    const header = document.createElement('div');
    header.className = 'page-header';
    header.innerHTML = `
      <div class="page-header__right" style="display:flex;align-items:center;gap:6px;margin-left:auto;">
        <button class="page-header__more" id="error-more" title="更多" aria-label="更多">
          <svg width="16" height="4" viewBox="0 0 16 4" fill="none" xmlns="http://www.w3.org/2000/svg">
            <circle cx="2" cy="2" r="1.6" fill="#4A4A4A"/>
            <circle cx="8" cy="2" r="1.6" fill="#4A4A4A"/>
            <circle cx="14" cy="2" r="1.6" fill="#4A4A4A"/>
          </svg>
        </button>
      </div>
    `;
    stickyWrap.appendChild(header);
    header.querySelector('#error-more').addEventListener('click', (e) => {
      e.stopPropagation();
      this._showPageMenu();
    });

    const viewTabs = document.createElement('div');
    viewTabs.id = 'error-view-tabs';
    stickyWrap.appendChild(viewTabs);
    this.renderViewTabs(viewTabs);

    // 搜索区（通过右上角三点菜单展开）
    const searchArea = document.createElement('div');
    searchArea.id = 'error-search-area';
    stickyWrap.appendChild(searchArea);

    main.appendChild(stickyWrap);

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

    // v8.14.10 错题本右下角新增按钮：圆形蓝色填充 + 号，点击新建错题
    const fab = document.createElement('button');
    fab.type = 'button';
    fab.className = 'sc-fab fab--solid-blue';
    fab.setAttribute('aria-label', '新增错题');
    fab.title = '新增错题';
    fab.innerHTML = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>';
    fab.addEventListener('click', () => {
      if (this.state.view === 'stickies') {
        this._openStickyEditor();
        return;
      }
      const query = [];
      if (this.state.subject) query.push('subject=' + encodeURIComponent(this.state.subject));
      if (this.state.module) query.push('module=' + encodeURIComponent(this.state.module));
      if (this.state.view === 'notes' && this.state.noteType) query.push('type=' + encodeURIComponent(this.state.noteType));
      const formRoute = this.state.view === 'notes' ? 'note-form' : 'error-form';
      query.push('returnTo=' + encodeURIComponent(this._viewRoute(this.state.view)));
      App.Router.navigate(formRoute + '?' + query.join('&'));
    });
    fab.setAttribute('aria-label', this.state.view === 'notes' ? '新建笔记' : (this.state.view === 'stickies' ? '新增便签' : '新增错题'));
    fab.title = this.state.view === 'notes' ? '新建笔记' : (this.state.view === 'stickies' ? '新增便签' : '新增错题');
    container.appendChild(fab);

    // 加载数据并渲染
    await this.loadData();
    await this.renderSubjectGrid(sidebar);
    this.renderViewTabs(viewTabs);
    if (this.state.view === 'notes') {
      this.renderNoteFilters(filterArea);
      this.renderNotesList(listArea);
    } else if (this.state.view === 'stickies') {
      filterArea.innerHTML = '';
      this.renderStickiesList(listArea);
    } else {
      this.renderFilters(filterArea);
      await this.renderList(listArea);
    }
  },

  _viewRoute(view) {
    const query = [];
    if (this.state.subject) query.push('subject=' + encodeURIComponent(this.state.subject));
    if (this.state.module) query.push('module=' + encodeURIComponent(this.state.module));
    if (view === 'notes' || view === 'stickies') query.push('view=' + view);
    return 'errors' + (query.length ? '?' + query.join('&') : '');
  },

  _getModuleStickies() {
    if (!this.state.subject || (!this.state.module && !App.Constants.isFlatSubject(this.state.subject))) return [];
    return (this.state.allStickies || []).filter(sticky => {
      return sticky.subject === this.state.subject && sticky.module === (this.state.module || '');
    }).sort((a, b) => {
      if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
      return new Date(b.createdAt || b.updatedAt || 0) - new Date(a.createdAt || a.updatedAt || 0);
    });
  },

  renderViewTabs(container) {
    container.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'errors-view-tabs';
    const errorCount = this.state.allErrors.filter(error =>
      (!this.state.subject || error.subject === this.state.subject) &&
      (!this.state.module || error.module === this.state.module)
    ).length;
    const noteCount = this.state.allNotes.filter(note =>
      (!this.state.subject || note.subject === this.state.subject) &&
      (!this.state.module || note.module === this.state.module)
    ).length;
    const stickyCount = this._getModuleStickies().length;
    const views = [
      ['wrong', '错题', errorCount],
      ['notes', '笔记', noteCount],
      ['stickies', '便签', stickyCount]
    ];
    // 词语库只属于“言语理解 / 逻辑填空”模块，并作为当前模块的横向页签入口。
    // 仅选中科目或进入其他模块时，不展示该入口。
    if (this.state.subject === '言语理解' && this.state.module === '逻辑填空') {
      views.push(['worddb', '词语库', null]);
    }
    views.forEach(([view, label, count]) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = this.state.view === view ? 'is-active' : '';
      button.textContent = label + (count === null ? '' : ' ' + count);
      button.addEventListener('click', () => {
        if (view === 'worddb') {
          App.Router.navigate('worddb?subject=' + encodeURIComponent('言语理解') + '&module=' + encodeURIComponent('逻辑填空'));
        } else if (this.state.view !== view) {
          App.Router.navigate(this._viewRoute(view));
        }
      });
      wrap.appendChild(button);
    });
    container.appendChild(wrap);
  },

  async loadData() {
    const result = await Promise.all([
      App.DB.getErrors(),
      App.DB.getNotes(),
      App.DB.getStickies().catch(() => [])
    ]);
    this.state.allErrors = result[0];
    this.state.allNotes = result[1];
    this.state.allStickies = result[2] || [];
  },

  // 合并「本模块库 + 数据中已用值」得到可筛选的考点列表（扁平科目传科目名，合并该科目所有模块）
  getDistinctKnowledgePoints(module) {
    const used = new Set();
    this.state.allErrors.forEach(e => {
      if (e.module === module || (App.Constants.isFlatSubject(module) && e.subject === module)) (e.knowledgePoints || []).forEach(kp => used.add(kp));
    });
    const lib = App.Constants.isFlatSubject(module)
      ? App.Tags.getSubjectKnowledgePoints(module)
      : App.Tags.getKnowledgePoints(module);
    return Array.from(new Set([...lib, ...used]));
  },

  // 合并「错因库 + 数据中已用值」得到可筛选的错因列表
  getDistinctErrorCauses() {
    const used = new Set();
    this.state.allErrors.forEach(e => { if (e.errorCause) used.add(e.errorCause); });
    const lib = App.Tags.getErrorCauses();
    return Array.from(new Set([...lib, ...used]));
  },

  // ===== 智能拆分 v2：把「题干 + 选项」整段文字解析为 题干 与 A/B/C/D 选项 =====
  // 相比旧版：全角归一化、多种标记格式、A→B→C→D 序列校验（避免题干中的字母被误判）、多重兜底策略
  parseQuestion(raw) {
    let text = (raw || '').replace(/\r\n/g, '\n');
    // 1) 归一化：全角字母 Ａ-Ｈ/ａ-ｈ → 半角；全角句点 ．﹒· → .；去掉行首多余空白
    text = text.replace(/[Ａ-Ｈａ-ｈ]/g, ch => String.fromCharCode(ch.charCodeAt(0) - 0xFEE0));
    text = text.replace(/[．﹒]/g, '.');
    text = text.split('\n').map(l => l.replace(/^[ \t\u3000]+/, '')).join('\n').trim();
    if (!text) return { question: '', options: [] };

    // 题干规范：OCR 粘贴的题干含大量换行噪音，先把题目部分所有换行/空白合并为一行，
    // 再单独拆出最后一句（问题，以 。！？!? 结尾）换行显示，便于看清提问
    const breakLastSentence = (q) => {
      if (!q) return q;
      const t = q.replace(/\s+/g, ' ').trim();
      const m = t.match(/^([\s\S]*?)([^。！？!?]+[。！？!?])\s*$/);
      if (m && m[1].trim() && m[2].trim()) {
        return m[1].trim() + '\n' + m[2].trim();
      }
      return t;
    };

    // 2) 收集所有候选选项标记（记录字母，供序列校验）
    const candidates = [];
    let m;
    // 形式一：A. / A、 / A。 / A： / A） 等（前面须是行首、空白或 ：（ 等分隔符）
    const re1 = /(^|[\n\s\u3000：:；;（(])([A-Ha-h])\s*[\.、。:：)）]\s*/g;
    while ((m = re1.exec(text)) !== null) {
      candidates.push({ letter: m[2].toUpperCase(), index: m.index + m[1].length, end: m.index + m[0].length });
    }
    // 形式二：（A）/ (A) / 【A】 / [A]
    const re2 = /[（(【\[]\s*([A-Ha-h])\s*[）)】\]]\s*/g;
    while ((m = re2.exec(text)) !== null) {
      candidates.push({ letter: m[1].toUpperCase(), index: m.index, end: m.index + m[0].length });
    }
    // 形式三：行首裸字母 + 空格（OCR 常见丢标点：「A 选项内容」）
    const re3 = /(^|\n)([A-Ha-h])[ \t\u3000]+(?=\S)/g;
    while ((m = re3.exec(text)) !== null) {
      candidates.push({ letter: m[2].toUpperCase(), index: m.index + m[1].length, end: m.index + m[0].length });
    }
    candidates.sort((a, b) => a.index - b.index || a.end - b.end);

    // 3) 序列校验：从每个 'A' 出发贪心找 A→B→C→D… 连续递增链，
    //    取最长链；等长取起点最靠后的（题干中出现的干扰字母通常在前面）
    let best = null;
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].letter !== 'A') continue;
      const chain = [candidates[i]];
      let want = 'B';
      for (let j = i + 1; j < candidates.length; j++) {
        if (candidates[j].letter === want && candidates[j].index >= chain[chain.length - 1].end) {
          chain.push(candidates[j]);
          want = String.fromCharCode(want.charCodeAt(0) + 1);
        }
      }
      if (chain.length >= 2 && (!best || chain.length > best.length ||
          (chain.length === best.length && chain[0].index > best[0].index))) {
        best = chain;
      }
    }
    if (best) {
      const question = text.slice(0, best[0].index).replace(/[（(【\[]\s*$/, '').trim();
      const options = best.map((c, i) => {
        const start = c.end;
        const end = (i + 1 < best.length) ? best[i + 1].index : text.length;
        return text.slice(start, end).trim().replace(/\s*\n\s*/g, ' ');
      });
      return { question: breakLastSentence(question), options };
    }

    // 4) 兜底一：①②③④ 行首标记作为选项
    const circleLines = text.split('\n').map(l => l.trim()).filter(Boolean);
    const circleIdx = circleLines.findIndex(l => /^[①②③④⑤⑥⑦⑧]/.test(l));
    if (circleIdx > 0 && circleLines.slice(circleIdx).every(l => /^[①②③④⑤⑥⑦⑧]/.test(l))) {
      return {
        question: breakLastSentence(circleLines.slice(0, circleIdx).join('\n')),
        options: circleLines.slice(circleIdx).map(l => l.replace(/^[①②③④⑤⑥⑦⑧]\s*[\.、。:：]?\s*/, ''))
      };
    }

    // 5) 兜底二：按行拆分——以最后一个含「？/?/（ ）」的行为题干结尾，其后各行为选项
    const lines = circleLines;
    if (lines.length >= 2) {
      let qEnd = 0;
      for (let i = 0; i < lines.length - 1; i++) {
        if (/[？?]\s*$|（\s*）|\(\s*\)/.test(lines[i])) qEnd = i;
      }
      return { question: breakLastSentence(lines.slice(0, qEnd + 1).join('\n')), options: lines.slice(qEnd + 1) };
    }
    return { question: breakLastSentence(text), options: [] };
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
            粘贴「题干 + 选项」整段文字，自动拆分成题干与 A/B/C/D 选项。支持 A. / A、 / （A） / 全角Ａ / 丢标点「A 内容」/ ①②③④ 等多种格式，自动排除题干中的干扰字母
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
    this._expanded = this._expanded || {};
    const errorCounts = {};
    App.Constants.SUBJECTS.forEach(s => {
      errorCounts[s.name] = this.state.allErrors.filter(e => e.subject === s.name).length;
    });

    container.innerHTML = '';

    // 「全部」项
    const allItem = document.createElement('div');
    allItem.className = 'sidebar__item' + (this.state.subject === null ? ' active' : '');
    allItem.innerHTML = `
      <span class="sidebar__item-icon" style="color:${this.state.subject === null ? '#0066CC' : '#7A7A7A'}">${this._subjectIconSvg('全部') || '📚'}</span>
      <span class="sidebar__item-name">全部</span>
    `;
    allItem.addEventListener('click', () => {
      this.state.subject = null;
      this.state.module = null;
      this.state.knowledgePoint = null;
      this.state.noteType = null;
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
      const count = errorCounts[s.name];
      row.innerHTML = `
        <span class="sidebar__item-icon" style="color:${isActive ? '#0066CC' : s.color}">${this._subjectIconSvg(s.name) || s.icon}</span>
        <span class="sidebar__item-name">${s.name}</span>
        ${count > 0 ? `<span class="sidebar__item-count">${count}</span>` : ''}
        ${!App.Constants.isFlatSubject(s.name) ? '<span class="sidebar__arrow"><svg width="8" height="5" viewBox="0 0 8 5" fill="none"><path d="M1 1l3 3 3-3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></span>' : ''}
      `;
      // 箭头：展开/收起该科目下的模块
      const arrow = row.querySelector('.sidebar__arrow');
      if (arrow) arrow.addEventListener('click', (e) => {
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
        this.state.noteType = null;
        // 第一次点击展开，再点一次收起；科目仍保持选中。
        if (!App.Constants.isFlatSubject(s.name)) this._expanded[s.name] = sameSubject ? !this._expanded[s.name] : true;
        this.refreshAll();
      });
      container.appendChild(row);

      // 模块（仅在该科目展开时显示，作为左侧二级导航；扁平科目如资料分析无模块层，不显示）
      if (expanded && !App.Constants.isFlatSubject(s.name)) {
        modules.forEach(mod => {
          const mCount = this.state.allErrors.filter(e => e.subject === s.name && e.module === mod).length;
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
            this.state.noteType = null;
            this.refreshAll();
          });
          container.appendChild(sub);
        });
      }
    });
  },

  renderStats(container) {
    const subject = this.state.subject;
    let errors = this.state.allErrors;
    if (subject) errors = errors.filter(e => e.subject === subject);
    if (this.state.module) errors = errors.filter(e => e.module === this.state.module);

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

    const row = document.createElement('div');
    row.className = 'tag-select-row';

    // 考点筛选（模块已在左侧导航选择；扁平科目如资料分析按科目级考点筛选）
    if (this.state.module || App.Constants.isFlatSubject(this.state.subject)) {
      const kps = this.getDistinctKnowledgePoints(this.state.module || this.state.subject);
      row.appendChild(App.Components.tagSelect(
        kps.map(k => ({ name: k })),
        this.state.knowledgePoint,
        (kp) => {
          this.state.knowledgePoint = (this.state.knowledgePoint === kp) ? null : kp;
          this.refreshFiltersAndList();
        },
        { kind: 'kp', module: this.state.module || this.state.subject, onDone: () => this.refreshFiltersAndList(), placeholder: '考点' }
      ));
    }

    // 错因筛选
    const causes = this.getDistinctErrorCauses();
    row.appendChild(App.Components.tagSelect(
      causes.map(c => ({ name: c })),
      this.state.errorCause,
      (cause) => {
        this.state.errorCause = (this.state.errorCause === cause) ? null : cause;
        this.refreshFiltersAndList();
      },
      { kind: 'ec', module: this.state.module, onDone: () => this.refreshFiltersAndList(), placeholder: '错因' }
    ));

    // 状态筛选
    row.appendChild(App.Components.tagSelect(
      ['未掌握', '已掌握'],
      this.state.status,
      (status) => {
        this.state.status = (this.state.status === status) ? null : status;
        this.refreshFiltersAndList();
      },
      { placeholder: '状态', showMenu: false }
    ));

    // 画廊窗口大小切换（小 / 中 / 大）
    const sizeSwitch = document.createElement('div');
    sizeSwitch.className = 'gallery-size-switch';
    const curSize = this.state.gallerySize || 'md';
    [['sm', '小'], ['md', '中'], ['lg', '大']].forEach((pair) => {
      const key = pair[0], label = pair[1];
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'gallery-size-switch__btn' + (curSize === key ? ' active' : '');
      b.textContent = label;
      b.title = key === 'sm' ? '小窗口' : key === 'md' ? '中窗口' : '大窗口';
      b.addEventListener('click', () => {
        this.state.gallerySize = key;
        this.state.gallerySizeAuto = false;
        this.refreshAll();
      });
      sizeSwitch.appendChild(b);
    });
    row.appendChild(sizeSwitch);

    container.appendChild(row);
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

    if (errors.length === 0) {
      // v8.14.11 按画布「iPad-错题本-空状态」卡片式空态（对齐便签/待办空态风格），胶囊靠上不居中
      const empty = document.createElement('div');
      empty.className = 'eerr-empty';
      const icon = document.createElement('div');
      icon.className = 'eerr-empty__icon';
      icon.innerHTML = '<svg width="44" height="44" viewBox="0 0 44 44" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="5.5" y="8" width="33" height="31.5" rx="4" stroke="#C7C7CC" stroke-width="1.8"/><path d="M11 15h11M11 20h11M11 25h11M11 30h7" stroke="#C7C7CC" stroke-width="1.8" stroke-linecap="round"/><path d="M27 27l3 3 6-7" stroke="#A1A1A6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      empty.appendChild(icon);
      const title = document.createElement('div');
      title.className = 'eerr-empty__title';
      title.textContent = '还没有错题';
      empty.appendChild(title);
      const desc = document.createElement('div');
      desc.className = 'eerr-empty__desc';
      desc.textContent = '点击「新建错题」，收录你的第一道题';
      empty.appendChild(desc);
      const action = document.createElement('button');
      action.type = 'button';
      action.className = 'eerr-empty__action';
      action.textContent = '＋ 新建错题';
      action.addEventListener('click', () => {
        let q = '';
        if (this.state.subject) {
          q = '?subject=' + encodeURIComponent(this.state.subject);
          if (this.state.module) q += '&module=' + encodeURIComponent(this.state.module);
        }
        q += (q ? '&' : '?') + 'returnTo=' + encodeURIComponent(this._viewRoute('wrong'));
        App.Router.navigate('error-form' + q);
      });
      empty.appendChild(action);
      container.appendChild(empty);
      return;
    }

    // JS 瀑布流模式：多列卡片（手机2/平板3/桌面4列），卡片放入最矮列，图片懒加载
    const masonryWrap = document.createElement('div');
    masonryWrap.className = 'error-masonry-wrap';
    container.appendChild(masonryWrap);
    // 先销毁旧实例（若存在）
    if (this._masonryInst) { try { this._masonryInst.destroy(); } catch (e) {} this._masonryInst = null; }
    const inst = App.Components.masonryGrid(masonryWrap, {
      onOpen: (error) => App.Router.navigate(this._buildErrorDetailRoute(error))
    });
    this._masonryInst = inst;
    inst.render(errors, false);
    // 列表区存引用，供局部刷新后再次挂载
    masonryWrap.dataset.masonry = '1';
  },

  renderNoteFilters(container) {
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
    wrap.className = 'note-modchips errors-note-types';
    const addChip = (label, active, onClick, color) => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'note-modchip' + (active ? ' active' : '');
      if (active && color) chip.style.cssText = 'background:' + color + '22;color:' + color + ';';
      chip.textContent = label;
      chip.addEventListener('click', onClick);
      wrap.appendChild(chip);
    };
    addChip('全部', !this.state.noteType, () => {
      this.state.noteType = null;
      this.refreshFiltersAndList();
    });
    types.forEach(type => addChip(type.name, this.state.noteType === type.name, () => {
      this.state.noteType = this.state.noteType === type.name ? null : type.name;
      this.refreshFiltersAndList();
    }, type.color));
    container.appendChild(wrap);
  },

  _noteSearchText(note) {
    let content = '';
    try { content = App.Utils.toNoteHtml(note.content || '').replace(/<[^>]*>/g, ' '); } catch (e) {}
    return [note.title || '', content, note.subject || '', note.module || '', note.knowledgePoint || ''].join(' ').toLowerCase();
  },

  renderNotesList(container) {
    container.innerHTML = '';
    let notes = (this.state.allNotes || []).filter(note =>
      (!this.state.subject || note.subject === this.state.subject) &&
      (!this.state.module || note.module === this.state.module) &&
      (!this.state.noteType || (this.state.noteType === App.NoteTypes.UNCLASSIFIED
        ? (!note.type || note.type === App.NoteTypes.UNCLASSIFIED)
        : note.type === this.state.noteType))
    );
    if (this.state.search) {
      const keyword = this.state.search.trim().toLowerCase();
      notes = notes.filter(note => this._noteSearchText(note).includes(keyword));
    }
    notes.sort((a, b) => new Date(b.updatedAt || b.createdAt || 0) - new Date(a.updatedAt || a.createdAt || 0));

    if (!notes.length) {
      const empty = document.createElement('div');
      empty.className = 'eerr-empty';
      empty.innerHTML = '<div class="eerr-empty__icon">📝</div><div class="eerr-empty__title">还没有笔记</div><div class="eerr-empty__desc">点击「新建笔记」，记录你的第一条复盘</div>';
      const action = document.createElement('button');
      action.type = 'button';
      action.className = 'eerr-empty__action';
      action.textContent = '＋ 新建笔记';
      action.addEventListener('click', () => {
        const query = [];
        if (this.state.subject) query.push('subject=' + encodeURIComponent(this.state.subject));
        if (this.state.module) query.push('module=' + encodeURIComponent(this.state.module));
        if (this.state.noteType) query.push('type=' + encodeURIComponent(this.state.noteType));
        query.push('returnTo=' + encodeURIComponent(this._viewRoute('notes')));
        App.Router.navigate('note-form?' + query.join('&'));
      });
      empty.appendChild(action);
      container.appendChild(empty);
      return;
    }

    notes.forEach(note => container.appendChild(App.Pages.Notes.buildNoteCard(note, this._viewRoute('notes'), {
      hideType: !!this.state.noteType,
      hideSubject: !!this.state.subject
    })));
  },

  // 便签只属于当前模块，不读取首页便签，也不在不同模块之间混合展示。
  _openStickyEditor() {
    if (!this.state.subject || (!this.state.module && !App.Constants.isFlatSubject(this.state.subject))) {
      App.Components.toast('请先选择具体科目和模块', 'info');
      return;
    }
    const subject = this.state.subject;
    const module = this.state.module || '';
    App.Components.stickySheet({
      title: '新增便签',
      onSave: async (data) => {
        try {
          await App.DB.addSticky(Object.assign({}, data, { subject: subject, module: module }));
          App.Components.toast('已新增便签 ✓', 'success');
          await this.loadData();
          this.refreshAll();
        } catch (e) {
          App.Components.toast('保存失败', 'error');
        }
      }
    });
  },

  renderStickiesList(container) {
    container.innerHTML = '';
    const hasContext = !!(this.state.subject && (this.state.module || App.Constants.isFlatSubject(this.state.subject)));

    let stickies = hasContext ? this._getModuleStickies().slice() : [];
    if (this.state.search) {
      const keyword = this.state.search.trim().toLowerCase();
      stickies = stickies.filter(sticky => String(sticky.content || '').toLowerCase().includes(keyword));
    }
    if (!stickies.length) {
      const empty = document.createElement('div');
      empty.className = 'eerr-empty errors-sticky-empty';
      empty.innerHTML = hasContext
        ? '<div class="eerr-empty__icon">📝</div><div class="eerr-empty__title">这个模块还没有便签</div><div class="eerr-empty__desc">添加只会保存在当前模块内</div>'
        : '<div class="eerr-empty__icon">📝</div><div class="eerr-empty__title">先选择一个模块</div><div class="eerr-empty__desc">每个模块的便签相互独立</div>';
      container.appendChild(empty);
      return;
    }

    const grid = App.Components.stickyMasonry(stickies, 'errors-sticky-list', {
      onRefresh: async () => { await this.loadData(); this.refreshAll(); }
    });
    container.appendChild(grid);
  },

  // 局部刷新：筛选条即时切换不动画，列表仅做进入动画
  refreshFiltersAndList() {
    const filterArea = document.getElementById('error-filter-area');
    const listArea = document.getElementById('error-list');
    if (this.state.view === 'notes') {
      if (filterArea) this.renderNoteFilters(filterArea);
      if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderNotesList(c));
    } else if (this.state.view === 'stickies') {
      if (filterArea) filterArea.innerHTML = '';
      if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderStickiesList(c));
    } else {
      if (filterArea) this.renderFilters(filterArea);
      if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderList(c));
    }
  },

  refreshAll() {
    const sidebar = document.getElementById('error-sidebar');
    const searchArea = document.getElementById('error-search-area');
    const filterArea = document.getElementById('error-filter-area');
    const listArea = document.getElementById('error-list');

    if (sidebar) this.renderSubjectGrid(sidebar);
    const tabs = document.getElementById('error-view-tabs');
    if (tabs) this.renderViewTabs(tabs);
    if (searchArea) this.renderSearchBar(searchArea);
    if (this.state.view === 'notes') {
      if (filterArea) this.renderNoteFilters(filterArea);
      if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderNotesList(c));
    } else if (this.state.view === 'stickies') {
      if (filterArea) filterArea.innerHTML = '';
      if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderStickiesList(c));
    } else {
      if (filterArea) this.renderFilters(filterArea);
      if (listArea) App.Utils.transitionSwap(listArea, (c) => this.renderList(c));
    }
  },

  // 右上角三点菜单
  async _showPageMenu() {
    const searchName = this.state.view === 'notes' ? '笔记' : (this.state.view === 'stickies' ? '便签' : '错题');
    const action = await App.Components.actionSheet([
      { label: '🔍 ' + (this.state.searchVisible ? '隐藏搜索' : '搜索' + searchName), value: 'search' }
    ], '学习库');
    if (action === 'search') {
      this.state.searchVisible = !this.state.searchVisible;
      const searchArea = document.getElementById('error-search-area');
      if (searchArea) this.renderSearchBar(searchArea);
    }
  },

  renderSearchBar(container) {
    container.innerHTML = '';
    if (!this.state.searchVisible) return;
    const searchBar = document.createElement('div');
    searchBar.className = 'search-bar';
    searchBar.style.marginBottom = 'var(--spacing-md)';
    const val = (this.state.search || '').replace(/"/g, '&quot;');
    searchBar.innerHTML = `
      <span class="search-bar__icon">🔍</span>
      <input type="text" placeholder="${this.state.view === 'notes' ? '搜索笔记标题 / 内容' : (this.state.view === 'stickies' ? '搜索便签内容' : '搜索错题 / 知识点')}" id="error-search" value="${val}">
    `;
    container.appendChild(searchBar);
    const input = searchBar.querySelector('input');
    input.addEventListener('input', App.Utils.debounce((e) => {
      this.state.search = e.target.value;
      if (this.state.view === 'notes') this.renderNotesList(document.getElementById('error-list'));
      else if (this.state.view === 'stickies') this.renderStickiesList(document.getElementById('error-list'));
      else this.renderList(document.getElementById('error-list'));
    }, 300));
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

    // 数据迁移：旧版 error.doodle 迁移为底部独立手写笔记；screenDoodle 用于屏幕勾画
    if (error.doodle && !error.handNote) {
      error.handNote = error.doodle;
      delete error.doodle;
      error.doodleHidden = false;
      await App.DB.updateError(error).catch(() => {});
    }

    // 返回栏 + 右上角：屏幕勾画铅笔 + 三点菜单（编辑已整合进三点菜单）
    const header = App.Components.pageHeader('错题详情', null, null, {
      onBack: () => App.Router.navigate(this._buildErrorListRoute(error))
    });
    const detailRight = header.querySelector('.page-header__right');
    if (detailRight) {
      detailRight.style.display = 'flex';
      detailRight.style.alignItems = 'center';
      detailRight.style.gap = '2px';
      detailRight.innerHTML = '';

      const doodleBtn = document.createElement('button');
      doodleBtn.className = 'detail-header-action';
      doodleBtn.title = error.screenDoodle ? '屏幕勾画' : '屏幕勾画';
      doodleBtn.innerHTML = '✍️';
      doodleBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this._openScreenDoodle(error, params);
      });
      detailRight.appendChild(doodleBtn);

      const editBtn = document.createElement('button');
      editBtn.className = 'detail-header-action';
      editBtn.textContent = '✎';
      editBtn.title = '编辑错题';
      editBtn.setAttribute('aria-label', '编辑错题');
      editBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        App.Router.navigate(this._buildErrorEditRoute(error));
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
    content.className = 'error-detail-content';
    content.style.cssText = 'padding:var(--spacing-md) var(--page-padding);padding-bottom:calc(var(--safe-bottom) + var(--spacing-lg));';

    // 题号 + 标签
    const headerInfo = document.createElement('div');
    headerInfo.style.cssText = 'margin-bottom:var(--spacing-md);';
    const subjectTagType = {
      '言语理解': 'primary', '数量关系': 'warning', '判断推理': 'success',
      '资料分析': 'purple', '常识判断': 'gold', '申论': 'teal'
    };
    const statusType = error.status === '已掌握' ? 'success' : 'danger';
    const kps = (error.knowledgePoints || []);
    let detailLines = '';
    if (kps.length) {
      detailLines += `<div style="margin-bottom:4px;"><span style="font-weight:600;color:var(--text-secondary);font-size:var(--font-xs);">考点：</span>${kps.map(kp => `<span class="tag tag--neutral">${kp}</span>`).join('')}</div>`;
    }
    if (error.errorCause) {
      detailLines += `<div style="margin-bottom:4px;"><span style="font-weight:600;color:var(--text-secondary);font-size:var(--font-xs);">错因：</span><span class="tag tag--neutral">${error.errorCause}</span></div>`;
    }
    if (error.pitfall) {
      detailLines += `<div style="margin-bottom:4px;"><span style="font-weight:600;color:var(--text-secondary);font-size:var(--font-xs);">思维误区：</span><span style="font-size:var(--font-sm);color:var(--text-secondary);">${error.pitfall}</span></div>`;
    }
    headerInfo.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px;">
        <span class="tag tag--${statusType}">${error.status}</span>
      </div>
      ${detailLines}
    `;
    content.appendChild(headerInfo);

    // 图片（多张，有图才展示；位于题目上方；点击全屏预览；宽度自适应压缩）
    const errorImages = (error.images && error.images.length) ? error.images : (error.image ? [error.image] : []);
    if (errorImages.length) {
      const imgWrap = document.createElement('div');
      imgWrap.className = 'error-detail-images';
      errorImages.forEach((src, i) => {
        const img = document.createElement('img');
        img.className = 'error-detail-image';
        img.src = src;
        img.alt = '错题图片' + (i + 1);
        img.addEventListener('click', () => {
          const overlay = document.createElement('div');
          overlay.className = 'notion-image-preview';
          const big = document.createElement('img');
          big.className = 'notion-image-preview__img';
          big.src = src;
          const close = () => overlay.remove();
          overlay.appendChild(big);
          overlay.addEventListener('click', (e) => { if (e.target === overlay || e.target === big) close(); });
          document.getElementById('modal-container').appendChild(overlay);
          requestAnimationFrame(() => overlay.classList.add('is-visible'));
        });
        imgWrap.appendChild(img);
      });
      content.appendChild(imgWrap);
    }

    // 题干（white-space:pre-line 保留编辑页手动换行）
    const questionEl = document.createElement('div');
    questionEl.style.cssText = 'font-size:var(--font-md);line-height:1.7;margin-bottom:var(--spacing-md);padding:var(--spacing-md);background:var(--bg-tertiary);border-radius:var(--radius-md);white-space:pre-line;';
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

    // 逻辑填空词语辨析：按空位顺序展示用户记录的多组辨析
    const compareGroups = (error.subject === '言语理解' && error.module === '逻辑填空' && Array.isArray(error.compareGroups))
      ? error.compareGroups.filter(g => g && (g.words || g.relation))
      : [];
    if (compareGroups.length) {
      const compareSection = document.createElement('section');
      compareSection.className = 'error-detail-compare';
      const compareHeading = document.createElement('div');
      compareHeading.className = 'error-detail-compare__title';
      compareHeading.textContent = '词语辨析';
      compareSection.appendChild(compareHeading);
      compareGroups.forEach((group, index) => {
        const groupEl = document.createElement('div');
        groupEl.className = 'error-detail-compare__group';
        const groupLabel = document.createElement('div');
        groupLabel.className = 'error-detail-compare__index';
        groupLabel.textContent = '第' + (index + 1) + '组';
        groupEl.appendChild(groupLabel);
        if (group.words) {
          const words = document.createElement('div');
          words.className = 'error-detail-compare__words';
          words.textContent = group.words;
          groupEl.appendChild(words);
        }
        if (group.relation) {
          const relation = document.createElement('div');
          relation.className = 'error-detail-compare__relation';
          relation.textContent = group.relation;
          groupEl.appendChild(relation);
        }
        compareSection.appendChild(groupEl);
      });
      content.appendChild(compareSection);
    }

    // 错题笔记（个人复盘心得）
    const enoteTitle = document.createElement('div');
    enoteTitle.style.cssText = 'font-size:var(--font-sm);font-weight:600;color:var(--text-secondary);margin:0 0 var(--spacing-sm);';
    enoteTitle.innerHTML = '📒 错题笔记 <span style="font-weight:400;color:var(--text-tertiary);font-size:var(--font-xs);">（点击可编辑，记录复盘心得）</span>';
    content.appendChild(enoteTitle);

    const enoteContent = document.createElement('div');
    enoteContent.className = 'card';
    enoteContent.style.cssText = 'margin:0 0 4px 0;line-height:1.7;min-height:60px;cursor:pointer;';
    // v8.6.3 对齐笔记：错题笔记统一存完整 HTML（历史 Markdown 自动迁移，用户无感）
    const enoteHtml = App.Utils.toNoteHtml(error.note);
    if (error.note !== enoteHtml) {
      error.note = enoteHtml;
      try { await App.DB.updateError(error); } catch (e) { /* 迁移写回失败不影响查看 */ }
    }
    enoteContent.innerHTML = error.note
      ? '<div class="note-html-body">' + error.note + '</div>'
      : '<span style="color:var(--text-tertiary);">点击添加错题笔记</span>';
    content.appendChild(enoteContent);

    let enoteEditing = false;
    enoteContent.addEventListener('click', () => {
      if (enoteEditing) return;
      enoteEditing = true;
      enoteContent.style.cursor = 'default';
      // 替换为编辑器前先锁定当前高度，避免清空内容导致塌陷/抖动
      enoteContent.style.minHeight = Math.max(enoteContent.offsetHeight, 60) + 'px';
      // v8.6.3 对齐笔记：单连续富文本编辑器（保存 = innerHTML 直存）
      const editor = App.Components.htmlEditor(
        (typeof error.note === 'string' ? error.note : '') || '',
        { placeholder: false, onChange: function (html) { error.note = html; } }
      );
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
        error.note = editor.getHtml();
        await App.DB.updateError(error);
        App.Components.toast('已保存 ✓', 'success');
        this.renderDetail(params);
      });
      cancelBtn.addEventListener('click', () => { this.renderDetail(params); });
    });

    // 底部独立手写笔记区域（始终显示，点击可编辑）
    const handNotePreview = document.createElement('div');
    handNotePreview.className = 'doodle-preview';
    if (error.handNote) {
      handNotePreview.innerHTML =
        '<div class="doodle-preview__header">' +
          '<div class="doodle-preview__title">✍️ 手写笔记区域</div>' +
        '</div>' +
        '<img class="doodle-preview__img" src="' + error.handNote + '" alt="手写笔记">';
    } else {
      handNotePreview.innerHTML = '<div class="doodle-preview__empty">✍️ 暂无手写笔记，点击添加</div>';
    }
    handNotePreview.addEventListener('click', () => this._openHandNote(error, params));
    content.appendChild(handNotePreview);

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

  // ===== 错题详情页就地编辑 =====
  // 详情页只替换当前内容区，不再跳转到独立表单页面；返回/取消时恢复原详情。
  _openInlineErrorEditor(error) {
    const content = document.querySelector('#page-error-detail .error-detail-content');
    if (!content || this._inlineErrorEditing) return;
    this._inlineErrorEditing = true;

    const draft = {
      subject: error.subject || '',
      module: error.module || '',
      knowledgePoints: Array.isArray(error.knowledgePoints) ? error.knowledgePoints.slice() : [],
      errorCause: error.errorCause || '',
      pitfall: error.pitfall || '',
      question: error.question || '',
      options: (error.options || []).slice(),
      correctOption: error.correctOption || '',
      userOption: error.userOption || '',
      accuracy: error.accuracy == null ? '' : String(error.accuracy),
      questionSource: error.questionSource || '',
      status: error.status || '未掌握'
    };
    while (draft.options.length < 4) draft.options.push('');

    content.innerHTML = '';
    content.classList.add('error-detail-content--editing');

    const heading = document.createElement('div');
    heading.className = 'error-inline-edit__heading';
    heading.innerHTML = '<strong>就地编辑错题</strong><span>修改后直接保存，仍停留在当前详情页</span>';
    content.appendChild(heading);

    const form = document.createElement('div');
    form.className = 'error-inline-edit';
    const field = (label, value, multiline) => {
      const group = document.createElement('label');
      group.className = 'error-inline-edit__field';
      const name = document.createElement('span');
      name.textContent = label;
      const input = document.createElement(multiline ? 'textarea' : 'input');
      input.value = value || '';
      input.className = 'error-inline-edit__input';
      if (multiline) input.rows = label === '题干' ? 5 : 3;
      group.appendChild(name);
      group.appendChild(input);
      return { group, input };
    };
    const picker = (label, value, options, onPick) => {
      const group = document.createElement('div');
      group.className = 'error-inline-edit__field';
      group._pickerOptions = options || [];
      const name = document.createElement('span');
      name.textContent = label;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'error-inline-edit__picker';
      button.textContent = value || '请选择';
      button.addEventListener('click', async () => {
        const selected = await App.Components.centeredPicker((group._pickerOptions || []).map(v => ({ label: v, value: v })), '选择' + label, '');
        if (selected !== undefined && selected !== null && selected !== '') {
          onPick(selected);
          button.textContent = selected;
        }
      });
      group.appendChild(name);
      group.appendChild(button);
      return group;
    };

    const subjectPicker = picker('科目', draft.subject, App.Constants.SUBJECTS.map(s => s.name), (value) => {
      draft.subject = value;
      draft.module = '';
      modulePicker._pickerOptions = App.Constants.getModules(value);
      modulePicker.querySelector('button').textContent = '请选择';
    });
    form.appendChild(subjectPicker);
    const modulePicker = picker('模块', draft.module, App.Constants.getModules(draft.subject), (value) => { draft.module = value; });
    form.appendChild(modulePicker);

    const kp = field('考点（多个用逗号分隔）', draft.knowledgePoints.join('、'), false);
    kp.input.addEventListener('input', () => { draft.knowledgePoints = kp.input.value.split(/[、,，]/).map(v => v.trim()).filter(Boolean); });
    form.appendChild(kp.group);
    const cause = field('错因', draft.errorCause, false);
    cause.input.addEventListener('input', () => { draft.errorCause = cause.input.value; });
    form.appendChild(cause.group);
    const question = field('题干', draft.question, true);
    question.input.addEventListener('input', () => { draft.question = question.input.value; });
    form.appendChild(question.group);

    const optionsTitle = document.createElement('div');
    optionsTitle.className = 'error-inline-edit__section-title';
    optionsTitle.textContent = '选项';
    form.appendChild(optionsTitle);
    ['A', 'B', 'C', 'D'].forEach((letter, index) => {
      const opt = field(letter, draft.options[index], false);
      opt.input.addEventListener('input', () => { draft.options[index] = opt.input.value; });
      form.appendChild(opt.group);
    });
    const answerRow = document.createElement('div');
    answerRow.className = 'error-inline-edit__grid';
    answerRow.appendChild(picker('正确选项', draft.correctOption, ['A', 'B', 'C', 'D'], value => { draft.correctOption = value; }));
    answerRow.appendChild(picker('你的选项', draft.userOption, ['A', 'B', 'C', 'D'], value => { draft.userOption = value; }));
    form.appendChild(answerRow);

    const pitfall = field('思维误区', draft.pitfall, true);
    pitfall.input.addEventListener('input', () => { draft.pitfall = pitfall.input.value; });
    form.appendChild(pitfall.group);
    const source = field('题目来源', draft.questionSource, false);
    source.input.addEventListener('input', () => { draft.questionSource = source.input.value; });
    form.appendChild(source.group);
    const metaRow = document.createElement('div');
    metaRow.className = 'error-inline-edit__grid';
    const accuracy = field('全站正确率（%）', draft.accuracy, false);
    accuracy.input.type = 'number';
    accuracy.input.addEventListener('input', () => { draft.accuracy = accuracy.input.value; });
    metaRow.appendChild(accuracy.group);
    metaRow.appendChild(picker('状态', draft.status, ['未掌握', '已掌握'], value => { draft.status = value; }));
    form.appendChild(metaRow);

    const actions = document.createElement('div');
    actions.className = 'error-inline-edit__actions';
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'btn btn--outline';
    cancel.textContent = '取消';
    cancel.addEventListener('click', () => { this._inlineErrorEditing = false; this.renderDetail({ id: error.id }); });
    const save = document.createElement('button');
    save.type = 'button';
    save.className = 'btn btn--primary';
    save.textContent = '保存修改';
    save.addEventListener('click', async () => {
      if (!draft.subject || (!App.Constants.isFlatSubject(draft.subject) && !draft.module) || !draft.question.trim()) {
        App.Components.toast('请先完成科目、模块和题干', 'error');
        return;
      }
      if (!draft.knowledgePoints.length) draft.knowledgePoints = [App.Constants.DEFAULT_REVIEW_TAG || '待复盘'];
      error.subject = draft.subject;
      error.module = draft.module;
      error.knowledgePoints = draft.knowledgePoints;
      error.errorCause = draft.errorCause || App.Constants.DEFAULT_REVIEW_TAG || '待复盘';
      error.pitfall = draft.pitfall;
      error.question = draft.question.trim();
      error.options = draft.options.map(v => String(v || '').trim()).filter(Boolean);
      error.correctOption = draft.correctOption;
      error.userOption = draft.userOption;
      error.accuracy = parseInt(draft.accuracy, 10) || 0;
      error.questionSource = draft.questionSource;
      error.status = draft.status;
      try {
        await App.DB.updateError(error);
        this._inlineErrorEditing = false;
        App.Components.toast('已保存 ✓', 'success');
        this.renderDetail({ id: error.id });
      } catch (e) { App.Components.toast('保存失败，请重试', 'error'); }
    });
    actions.appendChild(cancel);
    actions.appendChild(save);
    form.appendChild(actions);
    content.appendChild(form);

    // 让进入编辑态后立即有可见焦点，避免用户误以为输入框没有生效。
    const firstInput = form.querySelector('input, textarea');
    if (firstInput) {
      requestAnimationFrame(() => {
        try { firstInput.focus({ preventScroll: true }); } catch (e) { firstInput.focus(); }
      });
    }
  },

  // 统一处理列表和详情页删除，先删除本地记录，再确保登录状态下立即删除云端记录。
  // 这样不会因为 500ms 防抖队列尚未发送，随后同步又把旧错题拉回本机。
  async _deleteError(error) {
    if (!error || error.id == null) return false;
    const confirmed = await App.Components.confirm(
      '删除错题',
      '确定删除这道错题？此操作不可撤销。',
      '删除', '取消', true
    );
    if (!confirmed) return false;

    try {
      await App.DB.remove('errors', error.id);
    } catch (e) {
      App.Components.toast('删除失败，请重试', 'error');
      return false;
    }

    let cloudPending = false;
    if (App.Cloud && App.Cloud.isLoggedIn && App.Cloud.isLoggedIn() && App.Cloud.deleteNow) {
      try {
        await App.Cloud.deleteNow('errors', error.id);
      } catch (e) {
        // 本地删除已经完成，云端删除仍会保留在队列中重试。
        cloudPending = true;
      }
    }
    this.state.allErrors = (this.state.allErrors || []).filter(item => String(item.id) !== String(error.id));
    App.Components.toast(
      cloudPending ? '已从本机删除，云端删除将在联网后重试' : '已删除',
      cloudPending ? 'warning' : 'success'
    );
    return true;
  },

  // ===== 错题详情页右上角三点菜单 =====
  async _showErrorMenu(error) {
    const isMastered = error.status === '已掌握';
    const action = await App.Components.actionSheet([
      { label: '✏️ 编辑题目', value: 'edit' },
      { label: isMastered ? '↩️ 标记未掌握' : '✓ 标记已掌握', value: 'master' },
      { label: '📅 加入今日复习', value: 'review' },
      { label: '🗑️ 删除', value: 'delete' }
    ], error.question ? error.question.slice(0, 20) : '错题');
    if (!action) return;

    switch (action) {
      case 'edit': {
        App.Router.navigate(this._buildErrorEditRoute(error));
        break;
      }
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
        const deleted = await this._deleteError(error);
        if (deleted) App.Router.navigate(this._buildErrorListRoute(error));
        break;
      }
    }
  },

  // ===== 打开屏幕勾画覆盖层（右上角铅笔图标触发） =====
  _openScreenDoodle(error, params) {
    App.Components.doodleOverlay({
      initial: error.screenDoodle || null,
      onChange: async (dataURL) => {
        error.screenDoodle = dataURL || null;
        try { await App.DB.updateError(error); } catch (e) {}
      }
    }).then(async (dataURL) => {
      error.screenDoodle = dataURL || null;
      try { await App.DB.updateError(error); } catch (e) {}
      this.renderDetail(params);
    });
  },

  // ===== 打开底部手写笔记覆盖层 =====
  _openHandNote(error, params) {
    App.Components.doodleOverlay({
      initial: error.handNote || null,
      onChange: async (dataURL) => {
        error.handNote = dataURL || null;
        try { await App.DB.updateError(error); } catch (e) {}
      }
    }).then(async (dataURL) => {
      error.handNote = dataURL || null;
      try { await App.DB.updateError(error); } catch (e) {}
      this.renderDetail(params);
    });
  },

  // ===== 新建/编辑错题表单 =====
  renderForm(params) {
    const container = document.getElementById('page-error-form');
    container.innerHTML = '';

    let isEdit = !!params.id;
    const returnRoute = params && typeof params.returnTo === 'string' && /^(?:error-detail|errors|notes)(?:\?|$)/.test(params.returnTo)
      ? params.returnTo
      : 'errors';

    // 默认空白表单
    let formData = {
      subject: '',
      module: '',
      knowledgePoints: [App.Constants.DEFAULT_REVIEW_TAG || '待复盘'],
      errorCause: App.Constants.DEFAULT_REVIEW_TAG || '待复盘',
      pitfall: '',
      images: [],
      question: '',
      options: ['', '', '', ''],
      correctOption: '',
      userOption: '',
      accuracy: '',
      note: '',
      questionSource: '',
      status: '未掌握',
      sourceExamId: params.examId || null,
      // 言语-逻辑填空错题：支持多个空位分别记录词语辨析
      compareGroups: [{ words: '', relation: '' }]
    };

    // 如果是编辑，加载数据；如果是新建，尝试恢复「同一篇正在录入」的草稿
    const loadAndRender = async () => {
      if (isEdit) {
        const error = await App.DB.get('errors', params.id);
        if (error) {
          // v8.14.11 编辑申论错题 → 切到申论专属表单
          if (error.subject === '申论') {
            App.Pages.Errors.renderShenlunForm({ id: params.id, returnTo: params.returnTo });
            return;
          }
          formData = {
            subject: error.subject || '',
            module: error.module || '',
            knowledgePoints: error.knowledgePoints || [],
            errorCause: error.errorCause || '',
            pitfall: error.pitfall || '',
            images: (error.images && error.images.length) ? error.images.slice() : (error.image ? [error.image] : []),
            question: error.question || '',
            options: error.options || ['', '', '', ''],
            correctOption: error.correctOption || '',
            userOption: error.userOption || '',
            accuracy: error.accuracy !== undefined ? String(error.accuracy) : '',
            note: error.note || '',
            questionSource: error.questionSource || '',
            status: error.status || '未掌握',
            sourceExamId: error.sourceExamId || null,
            compareGroups: Array.isArray(error.compareGroups) && error.compareGroups.length
              ? error.compareGroups.map(g => ({ words: g.words || '', relation: g.relation || '' }))
              : [{ words: '', relation: '' }],
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
                pitfall: error.pitfall || '',
                images: (error.images && error.images.length) ? error.images.slice() : (error.image ? [error.image] : []),
                question: error.question || '',
                options: error.options || ['', '', '', ''],
                correctOption: error.correctOption || '',
                userOption: error.userOption || '',
                accuracy: error.accuracy !== undefined ? String(error.accuracy) : '',
                note: error.note || '',
                questionSource: error.questionSource || '',
                status: error.status || '未掌握',
                sourceExamId: error.sourceExamId || null,
                compareGroups: Array.isArray(error.compareGroups) && error.compareGroups.length
                  ? error.compareGroups.map(g => ({ words: g.words || '', relation: g.relation || '' }))
                  : [{ words: '', relation: '' }],
                id: error.id
              };
              formData._formId = fid;
            }
          }
        }
        // URL 参数指定科目-模块（从某科目点新建）优先
        if (!formData.subject && params.subject) {
          formData.subject = params.subject;
          if (params.module && App.Constants.getModules(params.subject).indexOf(params.module) !== -1) {
            formData.module = params.module;
          }
        }
        // 仍未指定科目时，默认带入上次选择的科目-模块
        if (!formData.subject) {
          const last = App.Utils.rememberSelect.get('error');
          if (last && last.subject) {
            formData.subject = last.subject;
            formData.module = (last.module && App.Constants.getModules(last.subject).indexOf(last.module) !== -1) ? last.module : '';
          }
        }
        if (!formData._formId) {
          formData._formId = App.Draft.newTempId();
          App.Draft.setFormId('error', formData._formId);
        }
        // 从某套卷点「加错题」时，关联回该套卷
        if (params.examId && !formData.sourceExamId) formData.sourceExamId = params.examId;
      }

      // v8.14.11 申论错题统一走专属表单：无论从哪条路径进入，只要科目固定为申论即切换
      if (formData.subject === '申论') {
        App.Pages.Errors.renderShenlunForm(isEdit && formData._formId
          ? { id: formData.id || formData._formId, returnTo: returnRoute }
          : { module: formData.module || '', returnTo: returnRoute });
        return;
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
          if (!formData.subject || (!App.Constants.isFlatSubject(formData.subject) && !formData.module) || formData.knowledgePoints.length === 0 || !formData.errorCause || !formData.question) {
            App.Components.toast('请先完成必填项', 'error');
            return;
          }
          await submitForm();
        }
      ));

      const form = document.createElement('div');
      form.className = 'form-page manual-card-form';

      // v8.14.11 卡片式重构（对齐画布"iPad-添加错题"10:758）：把扁平 form-group 分组进卡片
      // efCard: 白底 + 1px #E0E0E0 边框 + 圆角16 卡片容器
      const efCard = (children) => {
        const card = document.createElement('div');
        card.className = 'ef-card';
        (Array.isArray(children) ? children : [children]).forEach(c => { if (c) card.appendChild(c); });
        return card;
      };
      // efBox: 行内并排两栏（答案/来源等）
      const efBox = (a, b) => {
        const row = document.createElement('div');
        row.className = 'ef-box';
        if (a) row.appendChild(a);
        if (b) row.appendChild(b);
        return row;
      };

      // ===== 卡片一：科目 + 模块（扁平科目资料分析等直接隐藏模块，仅科目） =====
      const isFlatError = App.Constants.isFlatSubject(formData.subject);
      // v8.14.11 灰底选择条：显示当前值 + 右侧箭头，点击打开居中选择弹窗
      const efSelectBar = (label, value, placeholder, onClick) => {
        const row = document.createElement('div');
        row.className = 'ef-selectbar';
        if (label) {
          const lb = document.createElement('div');
          lb.className = 'ef-selectbar__label';
          lb.textContent = label;
          row.appendChild(lb);
        }
        const valEl = document.createElement('div');
        valEl.className = 'ef-selectbar__value' + (value ? '' : ' ef-selectbar__value--ph');
        valEl.textContent = value || placeholder || ('请选择' + (label || ''));
        row.appendChild(valEl);
        const arrow = document.createElement('div');
        arrow.className = 'ef-selectbar__arrow';
        arrow.innerHTML = '<svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M2 4l4 4 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        row.appendChild(arrow);
        row.addEventListener('click', onClick);
        return row;
      };
      const subjectSel = efSelectBar('科目', formData.subject, '请选择科目', () => {
        App.Components.pickerModal({
          title: '选择科目',
          mode: 'list',
          options: App.Constants.SUBJECTS.map(function (s) { return typeof s === 'string' ? s : s.name; }),
          selected: formData.subject,
          onDone: (val) => {
            if (!val) return;
            // v8.14.11 科目选「申论」→ 切换为申论专属表单
            if (val === '申论') {
              App.Draft.clearForm('error');
              App.Pages.Errors.renderShenlunForm({ module: formData.module, returnTo: returnRoute });
              return;
            }
            formData.subject = val;
            formData.module = '';
            formData.knowledgePoints = [];
            buildForm();
          }
        });
      });
      const topCardChildren = [subjectSel];
      if (formData.subject && !isFlatError) {
        topCardChildren.push(efSelectBar('模块', formData.module, '请选择模块', () => {
          App.Components.pickerModal({
            title: '选择模块',
            mode: 'list',
            options: App.Constants.getModules(formData.subject),
            selected: formData.module,
            onDone: (val) => {
              formData.module = val;
              formData.knowledgePoints = [];
              buildForm();
            }
          });
        }));
      }
      form.appendChild(efCard(topCardChildren));

      // ===== 卡片二：考点（最多3个）+ 错因 + 思维误区 =====
      const kpEcChildren = [];
      // 考点（多选，最多3个）弹窗
      if (formData.module || (isFlatError && formData.subject)) {
        kpEcChildren.push(efSelectBar('考点', formData.knowledgePoints && formData.knowledgePoints.length ? formData.knowledgePoints.join('、') : '', '最多选 3 个', () => {
          App.Components.pickerModal({
            title: '选择考点',
            mode: 'chips',
            options: isFlatError ? App.Tags.getSubjectKnowledgePoints(formData.subject) : App.Tags.getKnowledgePointSuggestions(formData.module),
            selected: formData.knowledgePoints,
            max: 3,
            allowCustom: true,
            manage: { kind: 'kp', module: formData.module },
            placeholder: '输入自定义考点，回车添加',
            onAddCustom: (v) => { if (isFlatError) App.Tags.addSubjectKnowledgePoint(formData.subject, v); else App.Tags.addKnowledgePoint(formData.module, v); },
            onDone: (sel) => { formData.knowledgePoints = sel; buildForm(); }
          });
        }));
      }
      // 错因（单选）弹窗
      kpEcChildren.push(efSelectBar('错因', formData.errorCause, '请选择错因', () => {
        App.Components.pickerModal({
          title: '选择错因',
          mode: 'chips',
          options: isFlatError ? App.Tags.getSubjectErrorCauses(formData.subject) : App.Tags.getMergedErrorCauses(formData.module),
          selected: formData.errorCause ? [formData.errorCause] : [],
          max: 1,
          allowCustom: true,
          manage: { kind: 'ec', module: formData.module },
          placeholder: '选择或输入错因，回车添加',
          onAddCustom: (v) => { if (isFlatError) App.Tags.addSubjectErrorCause(formData.subject, v); else App.Tags.addModuleErrorCause(formData.module, v); },
          onDone: (sel) => { formData.errorCause = (sel && sel.length) ? sel[0] : ''; buildForm(); }
        });
      }));
      kpEcChildren.push(App.Components.formInput(
        '思维误区',
        formData.pitfall,
        '一句话记录这道题容易踩的思维误区（可选）',
        (val) => { formData.pitfall = val; },
        'input'
      ));
      form.appendChild(efCard(kpEcChildren));

      // 言语理解-逻辑填空专属：多个空位分别记录词语辨析
      if (formData.subject === '言语理解' && formData.module === '逻辑填空') {
        if (!Array.isArray(formData.compareGroups) || !formData.compareGroups.length) {
          formData.compareGroups = [{ words: '', relation: '' }];
        }
        const compareCard = document.createElement('div');
        compareCard.className = 'ef-card error-compare-card';
        const compareTitle = document.createElement('div');
        compareTitle.className = 'error-compare-card__title';
        compareTitle.textContent = '词语辨析';
        compareCard.appendChild(compareTitle);

        formData.compareGroups.forEach((group, index) => {
          const groupEl = document.createElement('div');
          groupEl.className = 'error-compare-group';
          const groupHead = document.createElement('div');
          groupHead.className = 'error-compare-group__head';
          const groupLabel = document.createElement('span');
          groupLabel.textContent = '第' + (index + 1) + '组';
          groupHead.appendChild(groupLabel);
          if (formData.compareGroups.length > 1) {
            const removeBtn = document.createElement('button');
            removeBtn.type = 'button';
            removeBtn.className = 'error-compare-group__remove';
            removeBtn.textContent = '删除本组';
            removeBtn.addEventListener('click', () => {
              formData.compareGroups.splice(index, 1);
              buildForm();
            });
            groupHead.appendChild(removeBtn);
          }
          groupEl.appendChild(groupHead);
          groupEl.appendChild(App.Components.formInput(
            '辨析词语', group.words || '', '如：不足 vs 疏漏',
            (val) => { group.words = val; }, 'input'
          ));
          groupEl.appendChild(App.Components.formInput(
            '辨析关系', group.relation || '', '记录两个词语在语义、搭配或使用场景上的区别',
            (val) => { group.relation = val; }, 'textarea'
          ));
          compareCard.appendChild(groupEl);
        });

        const addGroupBtn = document.createElement('button');
        addGroupBtn.type = 'button';
        addGroupBtn.className = 'error-compare-card__add';
        addGroupBtn.textContent = '+ 添加辨析组';
        addGroupBtn.addEventListener('click', () => {
          formData.compareGroups.push({ words: '', relation: '' });
          buildForm();
        });
        compareCard.appendChild(addGroupBtn);
        form.appendChild(compareCard);
      }

      // 图片（可选）：支持多张；点击插入，逐张删除
      const imgGroup = document.createElement('div');
      imgGroup.className = 'form-group';
      const imgLabel = document.createElement('label');
      imgLabel.className = 'form-label';
      imgLabel.textContent = '图片（可选）';
      imgGroup.appendChild(imgLabel);

      const imgFileInput = document.createElement('input');
      imgFileInput.type = 'file';
      imgFileInput.accept = 'image/*';
      imgFileInput.multiple = true;   // 支持一次选多张
      imgFileInput.style.display = 'none';
      const pickImg = () => imgFileInput.click();
      const readImg = (file) => {
        return new Promise((resolve) => {
          if (!file || !/^image\//.test(file.type)) { App.Components.toast('仅支持图片格式', 'error'); resolve(false); return; }
          if (file.size > 2 * 1024 * 1024) { App.Components.toast('图片过大（>2MB），建议压缩后重试', 'error'); resolve(false); return; }
          const reader = new FileReader();
          reader.onload = () => { resolve(reader.result); };
          reader.onerror = () => { App.Components.toast('图片读取失败，请重试', 'error'); resolve(false); };
          reader.readAsDataURL(file);
        });
      };
      imgFileInput.addEventListener('change', async () => {
        const files = imgFileInput.files ? Array.from(imgFileInput.files) : [];
        imgFileInput.value = '';
        if (files.length === 0) return;
        // 一次选多张：逐张读取并追加
        for (const f of files) {
          const dataUrl = await readImg(f);
          if (dataUrl) {
            if (!Array.isArray(formData.images)) formData.images = [];
            formData.images.push(dataUrl);
          }
        }
        buildForm();
      });
      imgGroup.appendChild(imgFileInput);

      // 已添加图片网格（多张）
      const imgList = Array.isArray(formData.images) ? formData.images : [];
      if (imgList.length > 0) {
        const grid = document.createElement('div');
        grid.className = 'error-form-image__grid';
        imgList.forEach((src, idx) => {
          const item = document.createElement('div');
          item.className = 'error-form-image__item';
          const img = document.createElement('img');
          img.className = 'error-form-image__img';
          img.src = src;
          img.alt = '错题图片' + (idx + 1);
          const delBtn = document.createElement('button');
          delBtn.type = 'button';
          delBtn.className = 'error-form-image__del';
          delBtn.textContent = '×';
          delBtn.title = '删除这张图片';
          delBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            formData.images.splice(idx, 1);
            buildForm();
          });
          item.appendChild(img);
          item.appendChild(delBtn);
          grid.appendChild(item);
        });
        imgGroup.appendChild(grid);
        // 继续添加按钮（追加，不替换）
        const moreBtn = document.createElement('button');
        moreBtn.type = 'button';
        moreBtn.className = 'btn btn--outline btn--full';
        moreBtn.style.marginTop = 'var(--spacing-sm)';
        moreBtn.innerHTML = '➕ 继续添加图片';
        moreBtn.addEventListener('click', (e) => { e.stopPropagation(); pickImg(); });
        imgGroup.appendChild(moreBtn);
      } else {
        // 无图：仅「插入图片」按钮，不占位
        const addBtn = document.createElement('button');
        addBtn.type = 'button';
        addBtn.className = 'btn btn--outline btn--full';
        addBtn.style.marginBottom = 'var(--spacing-md)';
        addBtn.innerHTML = '🖼️ 插入图片';
        addBtn.addEventListener('click', (e) => { e.stopPropagation(); pickImg(); });
        imgGroup.appendChild(addBtn);
      }
      // ===== 卡片三：图片（可选） =====
      form.appendChild(efCard(imgGroup));

      // AI 智能拆分（题干 + 选项）
      const aiBtn = document.createElement('button');
      aiBtn.type = 'button';
      aiBtn.className = 'btn btn--outline ef-ai-btn';
      aiBtn.innerHTML = '🤖 AI 智能拆分题干与选项';
      aiBtn.addEventListener('click', () => this.openSmartSplit(formData, buildForm));
      form.appendChild(aiBtn);

      // ===== 卡片四：题目 + 选项 ABCD =====
      const qCardChildren = [];
      qCardChildren.push(App.Components.formInput(
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
        input.className = 'form-input error-form-option-input';
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
      qCardChildren.push(optionsGroup);
      form.appendChild(efCard(qCardChildren));

      // ===== 卡片五：答案（正确选项/你的选项 + 正确率/来源） =====
      const ansCardChildren = [];

      // 正确选项 + 你的选项（并排）
      const selRow = efBox(
        App.Components.formSelector(
          '正确选项',
          ['A', 'B', 'C', 'D'],
          formData.correctOption,
          (val) => { formData.correctOption = val; buildForm(); },
          true
        ),
        App.Components.formSelector(
          '你的选项',
          ['A', 'B', 'C', 'D'],
          formData.userOption,
          (val) => { formData.userOption = val; buildForm(); },
          false
        )
      );
      ansCardChildren.push(selRow);

      // 正确率 + 题目来源（并排）
      ansCardChildren.push(efBox(
        App.Components.formInput(
          '全站正确率（%）',
          formData.accuracy,
          '例如：65',
          (val) => { formData.accuracy = val; },
          'number',
          false
        ),
        App.Components.formInput(
          '题目来源',
          formData.questionSource,
          '如：2023 国考真题',
          (val) => { formData.questionSource = val; },
          'text',
          false
        )
      ));
      form.appendChild(efCard(ansCardChildren));

      // ===== 卡片六：错题笔记（个人复盘心得） =====
      const enoteGroup = document.createElement('div');
      enoteGroup.className = 'form-group';
      const enoteLabel = document.createElement('label');
      enoteLabel.className = 'form-label';
      enoteLabel.textContent = '错题笔记（个人复盘心得）';
      enoteGroup.appendChild(enoteLabel);

      // v8.6.3 对齐笔记：错题笔记统一存完整 HTML（历史 Markdown 自动迁移），单连续富文本编辑器
      const enoteHtml = App.Utils.toNoteHtml(formData.note);
      if (formData.note !== enoteHtml) formData.note = enoteHtml;
      const enoteEditor = App.Components.htmlEditor(enoteHtml, {
        placeholder: false,
        onChange: function (html) { formData.note = html; }
      });
      enoteGroup.appendChild(enoteEditor.element);
      formData._getENote = enoteEditor.getHtml;
      form.appendChild(efCard(enoteGroup));

      // ===== 保存按钮（底部渐变主色，全宽圆角25） =====
      const saveBtn = document.createElement('button');
      saveBtn.type = 'button';
      saveBtn.className = 'btn ef-save-btn';
      saveBtn.innerHTML = isEdit ? '保存修改' : '保存错题';
      saveBtn.addEventListener('click', async () => {
        if (!formData.subject || (!App.Constants.isFlatSubject(formData.subject) && !formData.module) || formData.knowledgePoints.length === 0 || !formData.errorCause || !formData.question) {
          App.Components.toast('请先完成必填项', 'error');
          return;
        }
        await submitForm();
      });
      form.appendChild(saveBtn);

      container.appendChild(form);

      // 草稿自动暂存（localStorage 兜底）+ 触发 DB 自动保存
      App.Draft.autoSaveForm('error', formData._formId, container, function () {
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
      if (formData._getENote) formData.note = formData._getENote();
      App.Utils.rememberSelect.set('error', formData.subject, formData.module);

      const data = {
        subject: formData.subject, module: formData.module,
        knowledgePoints: formData.knowledgePoints, errorCause: formData.errorCause,
        pitfall: formData.pitfall || '',
        images: formData.images && formData.images.length ? formData.images.slice() : [],
        question: formData.question, options: formData.options.filter(o => o.trim()),
        correctOption: formData.correctOption, userOption: formData.userOption || '',
        accuracy: parseInt(formData.accuracy) || 0,
        note: formData.note || '',
        questionSource: formData.questionSource || '',
        status: formData.status || '未掌握', sourceExamId: formData.sourceExamId || null,
        compareGroups: (formData.subject === '言语理解' && formData.module === '逻辑填空' && Array.isArray(formData.compareGroups))
          ? formData.compareGroups
            .map(g => ({ words: (g.words || '').trim(), relation: (g.relation || '').trim() }))
            .filter(g => g.words || g.relation)
          : []
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
      if (formData._getENote) formData.note = formData._getENote();
      if (!formData.subject) { App.Components.toast('请选择科目', 'error'); return; }
      if (!App.Constants.isFlatSubject(formData.subject) && !formData.module) { App.Components.toast('请选择模块', 'error'); return; }
      if (formData.knowledgePoints.length === 0) { App.Components.toast('请选择考点', 'error'); return; }
      if (!formData.errorCause) { App.Components.toast('请选择错因', 'error'); return; }
      if (!formData.question.trim()) { App.Components.toast('请输入题目', 'error'); return; }
      if (!formData.correctOption) { App.Components.toast('请选择正确选项', 'error'); return; }
      try {
        await submitFormInternal();
        App.Components.toast('已自动保存 ✓', 'success');
        App.Draft.clearForm('error');
        App.Router.navigate(returnRoute);
      } catch (e) { App.Components.toast('保存失败', 'error'); }
    };

    loadAndRender();
  }
};

// v8.14.11 申论专属错题表单（对齐画布"iPad-新建错题-申论"113:1）
// 需求：科目选「申论」时自动切换为本表单；扩展现有 errors 存储（subject='申论' + 扩展字段）
App.Pages.Errors.renderShenlunForm = function (params) {
  const container = document.getElementById('page-error-form');
  container.innerHTML = '';
  const self = App.Pages.Errors;

  let isEdit = !!params.id;
  const returnRoute = params && typeof params.returnTo === 'string' && /^(?:error-detail|errors|notes)(?:\?|$)/.test(params.returnTo)
    ? params.returnTo
    : 'errors';
  // 申论错题数据（扁平存于 errors 记录上，与通用错题共存）
  let d = {
    subject: '申论', module: '', question: '',
    score: '', totalScore: '', source: '',
    myFramework: '', stdFramework: '', paragraph: '',
    bias: [{ wrong: '', right: '' }],
    wrongList: [''], missedList: [''],
    note: '', status: '待吸收', _formId: null, id: null
  };

  const loadAndRender = async () => {
    if (isEdit) {
      const e = await App.DB.get('errors', params.id);
      if (e) {
        d = {
          subject: '申论', module: e.module || '', question: e.question || '',
          score: e.score !== undefined ? String(e.score) : '',
          totalScore: e.totalScore !== undefined ? String(e.totalScore) : '',
          source: e.source || e.questionSource || '',
          myFramework: e.myFramework || '', stdFramework: e.stdFramework || '', paragraph: e.paragraph || '',
          bias: (e.bias && e.bias.length) ? e.bias.slice() : [{ wrong: '', right: '' }],
          wrongList: (e.wrongList && e.wrongList.length) ? e.wrongList.slice() : [''],
          missedList: (e.missedList && e.missedList.length) ? e.missedList.slice() : [''],
          note: e.note || '', status: e.status || '待吸收', _formId: e.id, id: e.id
        };
      }
      if (!d._formId) d._formId = params.id;
    } else {
      const fid = App.Draft.getFormId('shenlun');
      if (fid) {
        if (App.Draft.formIdIsTemp(fid)) {
          const dr = App.Draft.loadForm('shenlun', fid);
          if (dr) Object.assign(d, dr);
          d._formId = fid;
        } else {
          const e = await App.DB.get('errors', fid);
          if (e && e.subject === '申论') {
            isEdit = true;
            d = {
              subject: '申论', module: e.module || '', question: e.question || '',
              score: e.score !== undefined ? String(e.score) : '',
              totalScore: e.totalScore !== undefined ? String(e.totalScore) : '',
              source: e.source || e.questionSource || '',
              myFramework: e.myFramework || '', stdFramework: e.stdFramework || '', paragraph: e.paragraph || '',
              bias: (e.bias && e.bias.length) ? e.bias.slice() : [{ wrong: '', right: '' }],
              wrongList: (e.wrongList && e.wrongList.length) ? e.wrongList.slice() : [''],
              missedList: (e.missedList && e.missedList.length) ? e.missedList.slice() : [''],
              note: e.note || '', status: e.status || '待吸收', _formId: fid, id: e.id
            };
          }
        }
      }
      if (params.module && App.Constants.getModules('申论').indexOf(params.module) !== -1) d.module = params.module;
      if (!d._formId) {
        d._formId = App.Draft.newTempId();
        App.Draft.setFormId('shenlun', d._formId);
      }
    }
    build();
  };

  const build = () => {
    container.innerHTML = '';

    container.appendChild(App.Components.pageHeader(
      isEdit ? '编辑申论错题' : '添加申论错题',
      '', null
    ));

    const form = document.createElement('div');
    form.className = 'form-page shenlun-form';

    // 卡片容器辅助
    const slCard = (title, children) => {
      const card = document.createElement('div');
      card.className = 'ef-card sl-card';
      if (title) {
        const t = document.createElement('div');
        t.className = 'sl-card__title';
        t.textContent = title;
        card.appendChild(t);
      }
      (Array.isArray(children) ? children : [children]).forEach(c => { if (c) card.appendChild(c); });
      return card;
    };
    const slRow = (label, control) => {
      const row = document.createElement('div');
      row.className = 'sl-row';
      if (label) {
        const lb = document.createElement('div');
        lb.className = 'sl-row__label';
        lb.textContent = label;
        row.appendChild(lb);
      }
      if (control) row.appendChild(control);
      return row;
    };
    const slField = (placeholder) => {
      const input = document.createElement('input');
      input.className = 'form-input sl-field';
      input.placeholder = placeholder || '';
      return input;
    };
    const slArea = (placeholder) => {
      const ta = document.createElement('textarea');
      ta.className = 'form-textarea sl-area';
      ta.placeholder = placeholder || '';
      return ta;
    };

    // v8.14.11 灰底选择条（与普通错题表单一致的弹窗选择）：显示当前值 + 右侧箭头，点击打开居中弹窗
    const efSelectBar = (label, value, placeholder, onClick) => {
      const row = document.createElement('div');
      row.className = 'ef-selectbar';
      if (label) {
        const lb = document.createElement('div');
        lb.className = 'ef-selectbar__label';
        lb.textContent = label;
        row.appendChild(lb);
      }
      const valEl = document.createElement('div');
      valEl.className = 'ef-selectbar__value' + (value ? '' : ' ef-selectbar__value--ph');
      valEl.textContent = value || placeholder || ('请选择' + (label || ''));
      row.appendChild(valEl);
      const arrow = document.createElement('div');
      arrow.className = 'ef-selectbar__arrow';
      arrow.innerHTML = '<svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M2 4l4 4 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      row.appendChild(arrow);
      row.addEventListener('click', onClick);
      return row;
    };

    // ===== 模块1：题目信息 =====
    const m1 = [];
    // ① 题干（挪到模块选择框上方）
    const qArea = slArea('粘贴/输入申论题目题干…');
    qArea.value = d.question;
    qArea.addEventListener('input', () => { d.question = qArea.value; });
    m1.push(slRow('题干', qArea));

    // ② 模块（改为弹窗选择，挪到题干下方）
    const moduleBar = efSelectBar('模块', d.module, '归纳概括 / 综合分析 / 提出对策…', () => {
      App.Components.pickerModal({
        title: '选择模块',
        mode: 'list',
        options: App.Constants.getModules('申论'),
        selected: d.module,
        onDone: (val) => { if (val) d.module = val; if (typeof build === 'function') build(); }
      });
    });
    m1.push(moduleBar);

    // ③ 得分标题
    const scoreTitle = document.createElement('div');
    scoreTitle.className = 'sl-score-title';
    scoreTitle.textContent = '得分';
    m1.push(scoreTitle);

    // ④ 得分 / 总分（并排）
    const scoreInput = slField('得分');
    scoreInput.type = 'number'; scoreInput.value = d.score;
    scoreInput.addEventListener('input', () => { d.score = scoreInput.value; });
    const totalInput = slField('总分');
    totalInput.type = 'number'; totalInput.value = d.totalScore;
    totalInput.addEventListener('input', () => { d.totalScore = totalInput.value; });
    const scoreRow = document.createElement('div');
    scoreRow.className = 'sl-score-row';
    const scA = document.createElement('div'); scA.className = 'sl-score-item';
    const scAl = document.createElement('span'); scAl.className = 'sl-score-label'; scAl.textContent = '得分';
    scA.appendChild(scAl); scA.appendChild(scoreInput);
    const scB = document.createElement('div'); scB.className = 'sl-score-item';
    const scBl = document.createElement('span'); scBl.className = 'sl-score-label'; scBl.textContent = '总分';
    scB.appendChild(scBl); scB.appendChild(totalInput);
    scoreRow.appendChild(scA); scoreRow.appendChild(scB);
    m1.push(scoreRow);

    const srcInput = slField('如 2024年国考申论真题');
    srcInput.value = d.source;
    srcInput.addEventListener('input', () => { d.source = srcInput.value; });
    m1.push(slRow('来源', srcInput));
    form.appendChild(slCard('题目信息', m1));

    // ===== 模块2：框架对比 =====
    const m2 = [];
    // 我的答案框架：蓝色标题 + textarea
    const myWrap = document.createElement('div');
    myWrap.className = 'sl-frame';
    const myTitle = document.createElement('div');
    myTitle.className = 'sl-frame__label sl-frame__label--blue';
    myTitle.textContent = '我的答案框架';
    myWrap.appendChild(myTitle);
    const myA = slArea('我的答题框架要点…');
    myA.value = d.myFramework;
    myA.addEventListener('input', () => { d.myFramework = myA.value; });
    myWrap.appendChild(myA);
    m2.push(myWrap);
    // 标准答案框架：绿色标题 + textarea
    const stdWrap = document.createElement('div');
    stdWrap.className = 'sl-frame';
    const stdTitle = document.createElement('div');
    stdTitle.className = 'sl-frame__label sl-frame__label--green';
    stdTitle.textContent = '标准答案框架';
    stdWrap.appendChild(stdTitle);
    const stdA = slArea('标准答案框架要点…');
    stdA.value = d.stdFramework;
    stdA.addEventListener('input', () => { d.stdFramework = stdA.value; });
    stdWrap.appendChild(stdA);
    m2.push(stdWrap);
    form.appendChild(slCard('框架对比', m2));

    // ===== 模块3：逐段分析差距 =====
    const m3 = [];
    const hint = document.createElement('div');
    hint.className = 'sl-hint';
    hint.textContent = '对照我的答案与标准答案，逐段分析哪里多写、少写、移位';
    m3.push(hint);
    const pA = slArea('逐段写出与标准答案的差距…');
    pA.value = d.paragraph;
    pA.addEventListener('input', () => { d.paragraph = pA.value; });
    m3.push(pA);
    form.appendChild(slCard('逐段分析差距', m3));

    // ===== 模块4：核心思维偏差表 =====
    const m4 = [];
    const tblHead = document.createElement('div');
    tblHead.className = 'sl-tbl-head';
    tblHead.innerHTML = '<span>偏差编号</span><span>我的错误</span><span>正确思维</span>';
    m4.push(tblHead);
    const tblWrap = document.createElement('div');
    tblWrap.className = 'sl-tbl';
    const renderBias = () => {
      tblWrap.innerHTML = '';
      d.bias.forEach((row, idx) => {
        const r = document.createElement('div');
        r.className = 'sl-tbl-row';
        const num = document.createElement('span'); num.className = 'sl-tbl-num'; num.textContent = (idx + 1);
        const w = document.createElement('input'); w.className = 'form-input sl-tbl-input'; w.placeholder = '我的错误'; w.value = row.wrong || '';
        w.addEventListener('input', () => { row.wrong = w.value; });
        const rt = document.createElement('input'); rt.className = 'form-input sl-tbl-input'; rt.placeholder = '正确思维'; rt.value = row.right || '';
        rt.addEventListener('input', () => { row.right = rt.value; });
        r.appendChild(num); r.appendChild(w); r.appendChild(rt);
        tblWrap.appendChild(r);
      });
    };
    renderBias();
    m4.push(tblWrap);
    const addBiasBtn = document.createElement('button');
    addBiasBtn.type = 'button';
    addBiasBtn.className = 'sl-addbtn';
    addBiasBtn.innerHTML = '＋ 添加一行';
    addBiasBtn.addEventListener('click', () => { d.bias.push({ wrong: '', right: '' }); renderBias(); });
    m4.push(addBiasBtn);
    form.appendChild(slCard('核心思维偏差', m4));

    // ===== 模块5：踩分点错误/遗漏清单 =====
    const m5 = [];
    const wrongWrap = document.createElement('div');
    wrongWrap.className = 'sl-listwrap';
    const wrongL = document.createElement('div');
    wrongL.className = 'sl-listlabel sl-listlabel--red';
    wrongL.textContent = '我错误的';
    wrongWrap.appendChild(wrongL);
    const wrongClips = document.createElement('div');
    wrongClips.className = 'sl-clips';
    const renderWrongClips = () => {
      wrongClips.innerHTML = '';
      d.wrongList.forEach((v, idx) => {
        if (idx === 0) {
          const inp = document.createElement('input');
          inp.className = 'form-input sl-clip-input';
          inp.placeholder = '漏掉了踩分点「对策具体可操作性」…';
          inp.value = v;
          inp.addEventListener('input', () => { d.wrongList[0] = inp.value; });
          wrongClips.appendChild(inp);
        } else {
          const chip = document.createElement('span');
          chip.className = 'sl-chip';
          chip.textContent = v;
          const x = document.createElement('span'); x.className = 'sl-chip-x'; x.textContent = '×';
          x.addEventListener('click', () => { d.wrongList.splice(idx, 1); renderWrongClips(); });
          chip.appendChild(x);
          wrongClips.appendChild(chip);
        }
      });
    };
    renderWrongClips();
    wrongWrap.appendChild(wrongClips);
    const addWrongBtn = document.createElement('button');
    addWrongBtn.type = 'button';
    addWrongBtn.className = 'sl-addbtn sl-addbtn--sm';
    addWrongBtn.innerHTML = '＋ 添加踩分点';
    addWrongBtn.addEventListener('click', () => {
      const lastVal = d.wrongList[0] || '';
      if (!lastVal.trim()) { App.Components.toast('请先填写第一项', 'error'); return; }
      d.wrongList.push(lastVal); d.wrongList[0] = ''; renderWrongClips();
    });
    wrongWrap.appendChild(addWrongBtn);
    m5.push(wrongWrap);

    const missedWrap = document.createElement('div');
    missedWrap.className = 'sl-listwrap';
    const missedL = document.createElement('div');
    missedL.className = 'sl-listlabel sl-listlabel--green';
    missedL.textContent = '我遗漏的';
    missedWrap.appendChild(missedL);
    const missedClips = document.createElement('div');
    missedClips.className = 'sl-clips';
    const renderMissedClips = () => {
      missedClips.innerHTML = '';
      d.missedList.forEach((v, idx) => {
        if (idx === 0) {
          const inp = document.createElement('input');
          inp.className = 'form-input sl-clip-input';
          inp.placeholder = '遗漏了「分条作答、序号清晰」…';
          inp.value = v;
          inp.addEventListener('input', () => { d.missedList[0] = inp.value; });
          missedClips.appendChild(inp);
        } else {
          const chip = document.createElement('span');
          chip.className = 'sl-chip';
          chip.textContent = v;
          const x = document.createElement('span'); x.className = 'sl-chip-x'; x.textContent = '×';
          x.addEventListener('click', () => { d.missedList.splice(idx, 1); renderMissedClips(); });
          chip.appendChild(x);
          missedClips.appendChild(chip);
        }
      });
    };
    renderMissedClips();
    missedWrap.appendChild(missedClips);
    const addMissedBtn = document.createElement('button');
    addMissedBtn.type = 'button';
    addMissedBtn.className = 'sl-addbtn sl-addbtn--sm';
    addMissedBtn.innerHTML = '＋ 添加踩分点';
    addMissedBtn.addEventListener('click', () => {
      const lastVal = d.missedList[0] || '';
      if (!lastVal.trim()) { App.Components.toast('请先填写第一项', 'error'); return; }
      d.missedList.push(lastVal); d.missedList[0] = ''; renderMissedClips();
    });
    missedWrap.appendChild(addMissedBtn);
    m5.push(missedWrap);
    form.appendChild(slCard('踩分点错误/遗漏清单', m5));

    // ===== 复盘笔记（可选） =====
    const enoteGroup = document.createElement('div');
    enoteGroup.className = 'ef-card';
    const enoteLabel = document.createElement('label');
    enoteLabel.className = 'form-label';
    enoteLabel.textContent = '复盘笔记（一句话总结本次错因，可选）';
    enoteGroup.appendChild(enoteLabel);
    const enoteHtml = App.Utils.toNoteHtml(d.note);
    if (d.note !== enoteHtml) d.note = enoteHtml;
    const enoteEditor = App.Components.htmlEditor(enoteHtml, {
      placeholder: false,
      onChange: function (html) { d.note = html; }
    });
    enoteGroup.appendChild(enoteEditor.element);
    d._getENote = enoteEditor.getHtml;
    form.appendChild(enoteGroup);

    // ===== 底部保存按钮 =====
    const saveBtn = document.createElement('button');
    saveBtn.type = 'button';
    saveBtn.className = 'btn ef-save-btn';
    saveBtn.innerHTML = '保存申论错题';
    saveBtn.addEventListener('click', async () => {
      if (!d.module || !d.question.trim()) { App.Components.toast('请先填模块和题干', 'error'); return; }
      await submit();
    });
    form.appendChild(saveBtn);

    container.appendChild(form);

    // 草稿自动暂存
    App.Draft.autoSaveForm('shenlun', d._formId, container, function () {
      if (d._getENote) { try { d.note = d._getENote(); } catch (e) {} }
      return JSON.parse(JSON.stringify(d));
    });
  };

  const submit = async () => {
    if (d._getENote) { try { d.note = d._getENote(); } catch (e) {} }
    if (!d.module) { App.Components.toast('请选择模块', 'error'); return; }
    if (!d.question.trim()) { App.Components.toast('请输入题干', 'error'); return; }

    const data = {
      subject: '申论', module: d.module, question: d.question,
      score: parseInt(d.score) || 0, totalScore: parseInt(d.totalScore) || 0,
      source: d.source || '', questionSource: d.source || '',
      myFramework: d.myFramework || '', stdFramework: d.stdFramework || '', paragraph: d.paragraph || '',
      bias: (d.bias || []).filter(r => r.wrong || r.right),
      wrongList: (d.wrongList || []).filter(x => x.trim()),
      missedList: (d.missedList || []).filter(x => x.trim()),
      note: d.note || '', status: d.status || '待吸收',
      isShenlun: true,
      knowledgePoints: [], options: [], errorCause: '', pitfall: '',
      sourceExamId: null
    };

    try {
      App.Utils.rememberSelect.set('error', '申论', d.module);
      if (d.id) {
        data.id = d.id;
        const existing = await App.DB.get('errors', d.id);
        data.reviewCount = existing ? existing.reviewCount || 0 : 0;
        data.lastReviewDate = new Date().toISOString();
        data.createdAt = existing ? existing.createdAt : new Date().toISOString();
        await App.DB.updateError(data);
      } else {
        await App.DB.addError(data);
      }
      App.Components.toast('已保存 ✓', 'success');
      App.Draft.clearForm('shenlun');
      App.Router.navigate(returnRoute);
    } catch (e) { App.Components.toast('保存失败', 'error'); }
  };

  loadAndRender();
};

// 错题本画廊：窗口尺寸变化时，自动模式下重新选择密度
(function galleryResizeAuto() {
  let resizeTimer = null;
  function update() {
    const page = App.Pages.Errors;
    if (!page || !page.state || !page.state.gallerySizeAuto) return;
    const w = window.innerWidth;
    const size = w < 600 ? 'sm' : (w < 1100 ? 'md' : 'lg');
    if (size !== page.state.gallerySize) {
      page.state.gallerySize = size;
      if (App.Router && App.Router.currentPage === 'errors' && page.refreshAll) {
        page.refreshAll();
      }
    }
  }
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(update, 250);
  });
})();


