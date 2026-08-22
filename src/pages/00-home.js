// ===== 考公笔试复盘系统 - 复盘首页 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Home = {
  async render(params) {
    // v8.11.1 页面重建前清理上轮计时刷新
    if (this._timerInterval) { clearInterval(this._timerInterval); this._timerInterval = null; }
    const container = document.getElementById('page-home');
    container.innerHTML = '';

    // 获取统计数据
    let stats, reviewQueue, todos;
    try {
      [stats, reviewQueue, todos] = await Promise.all([
        App.DB.getStats(),
        App.DB.getReviewQueue(),
        App.DB.getTodos()
      ]);
    } catch (e) {
      console.error('数据加载失败:', e);
      stats = { subjectStats: {}, totalErrors: 0, unmasteredErrors: 0 };
      reviewQueue = [];
      todos = [];
    }
    // v8.15.47 保存全部待办，供 hero 计时胶囊查找「正在计时的待办」
    this._allTodos = todos;

    // ===== 1. 顶部标题 + 搜索栏 =====
    const header = document.createElement('div');
    header.style.cssText = 'padding:var(--spacing-lg) var(--page-padding);padding-bottom:0;';
    header.innerHTML = `
      <div style="display:flex;align-items:center;gap:var(--spacing-sm);margin-bottom:var(--spacing-lg);">
        <div style="font-size:26px;font-weight:600;letter-spacing:-0.02em;color:var(--text-primary);">首页</div>
        <div class="search-bar" style="flex:1;margin:0;">
          <span class="search-bar__icon">🔍</span>
          <input type="text" placeholder="搜索错题 / 知识点" id="home-search"
            style="background:var(--bg-tertiary);height:40px;border-radius:9999px;padding-left:36px;">
        </div>
      </div>
    `;
    container.appendChild(header);

    // 搜索输入监听
    const searchInput = header.querySelector('#home-search');
    searchInput.addEventListener('input', App.Utils.debounce((e) => {
      if (e.target.value.trim()) {
        App.Router.navigate('errors?search=' + encodeURIComponent(e.target.value.trim()));
      }
    }, 500));

    // ===== 2. 功能图标网格 (5列) =====
    const featureGrid = document.createElement('div');
    featureGrid.className = 'feature-grid';

    const features = [
      // v8.12.20 对齐画布 7:101：待办统计（原学习统计）→ 学习报告（原学习周报，第5位挪到第2位）→ 速算练习 → 时政常识 → 考点管理
      { icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/><line x1="8" y1="14" x2="16" y2="14"/><line x1="8" y1="18" x2="13" y2="18"/></svg>', label: '待办统计', color: '#4A90E2', action: () => App.Router.navigate('study-stats') },
      { icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="18" y="3" width="4" height="18"/><rect x="10" y="8" width="4" height="13"/><rect x="2" y="13" width="4" height="8"/></svg>', label: '学习报告', color: '#9B7BFF', action: () => App.Router.navigate('workspace') },
      { icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="2" width="16" height="20" rx="2"/><line x1="8" y1="6" x2="16" y2="6"/><line x1="8" y1="10" x2="16" y2="10"/><line x1="8" y1="14" x2="10" y2="14"/><line x1="13" y1="14" x2="16" y2="14"/><line x1="8" y1="18" x2="10" y2="18"/><line x1="13" y1="18" x2="16" y2="18"/></svg>', label: '速算练习', color: '#FF9500', action: () => App.Router.navigate('speed-calc') },
      { icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>', label: '时政常识', color: '#F5C842', action: () => App.Router.navigate('notes?subject=' + encodeURIComponent('常识判断')) },
      { icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>', label: '考点管理', color: '#34C759', action: () => App.Router.navigate('kpmanage') }
    ];

    features.forEach(f => {
      const item = document.createElement('button');
      item.type = 'button';
      item.setAttribute('aria-label', '打开' + f.label);
      item.className = 'feature-grid-item';
      // v8.11.3 多彩 tinted 入口：浅色底 + 同色图标（对齐画布定稿）
      item.innerHTML = `
        <span class="feature-grid-item__icon" style="background:${f.color}1F;color:${f.color}">${f.icon}</span>
        <div class="feature-grid-item__name">${f.label}</div>
      `;
      item.addEventListener('click', f.action);
      featureGrid.appendChild(item);
    });
    container.appendChild(featureGrid);

    // ===== 3. 统计卡片区 (4列) =====
    const statsRow = document.createElement('div');
    statsRow.className = 'stats-row';
    statsRow.style.marginBottom = 'var(--spacing-xl)';

    const totalErrors = stats.totalErrors || 0;
    const unmastered = stats.unmasteredErrors || 0;
    const weekNew = stats.weekNewErrors || 0;
    const totalNotes = stats.totalNotes || 0;

    // v8.11.3 统计卡片区（4列）移除：对齐画布定稿首页结构（5入口 + Hero + 今日待办 + 便签），
    // 数据保留供 Hero 脚注使用（unmastered/weekNew）

    // ===== 7. 今日待办（丰富版） =====
    // v8.6.16 折叠状态持久化：上次折叠/已折叠，重新进入仍保持（localStorage kg_todo_ui）
    if (!this.todoState) {
      let saved = {};
      try { saved = JSON.parse(localStorage.getItem('kg_todo_ui')) || {}; } catch (e) { saved = {}; }
      this.todoState = { filter: 'all', type: 'yanyu', statsMode: null, dateFilter: 'today', filterOpen: false, collapsed: !!saved.collapsed, doneOpen: !!saved.doneOpen, notesOpen: {} };
    }
    const TODO_TYPES = [
      { key: 'yanyu', icon: '📖', label: '言语' },
      { key: 'ziliao', icon: '📊', label: '资料' },
      { key: 'panduan', icon: '🧩', label: '判断' },
      { key: 'shuliang', icon: '🔢', label: '数量' },
      { key: 'changshi', icon: '🌍', label: '常识' },
      { key: 'zhengzhi', icon: '🏛️', label: '政治' },
      { key: 'shenlun', icon: '✍️', label: '申论' }
    ];
    // v8.12.13 对齐画布：列表左侧类型缩写改单字（言/资/判/数/常/政/申）
    const TYPE_SHORT = { yanyu: '言', ziliao: '资', panduan: '判', shuliang: '数', changshi: '常', zhengzhi: '政', shenlun: '申' };
    const TODO_STATUS = [
      { key: 'pending', label: '未完成', color: '#FF9500' },
      { key: 'in_progress', label: '进行中', color: '#4A90E2' },
      { key: 'completed', label: '已完成', color: '#34C759' },
      { key: 'flagged', label: '重要', color: '#FF3B30' }
    ];
    // 旧类型（学习/复习/练习/其他）→ 新科目映射；未知类型兜底言语
    const LEGACY_TODO_TYPE_MAP = { study: 'yanyu', review: 'yanyu', practice: 'yanyu', other: 'yanyu' };
    const typeKeyOf = (todo) => {
      const raw = todo.type || 'yanyu';
      return TODO_TYPES.some(t => t.key === raw) ? raw : (LEGACY_TODO_TYPE_MAP[raw] || 'yanyu');
    };
    const statusOf = (todo) => {
      if (todo.status && TODO_STATUS.some(s => s.key === todo.status)) return todo.status;
      return todo.completed ? 'completed' : 'pending';
    };
    // v8.14.8 顺延统计口径：未完成事项自动顺延到今日（任何创建日期都归入今日，直至完成）；
    // 「今日统计」只统计"今天已完成"（completedAt 在今天），未完成不计入统计分母。
    const pad2 = (n) => String(n).padStart(2, '0');
    const nowD = new Date();
    const todayKey = nowD.getFullYear() + '-' + pad2(nowD.getMonth() + 1) + '-' + pad2(nowD.getDate());
    const todayStart = new Date(nowD.getFullYear(), nowD.getMonth(), nowD.getDate());
    const doneToday = (t) => {
      if (!t.completed) return false;
      const cd = new Date(t.completedAt || t.updatedAt);
      return cd >= todayStart && cd < new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
    };
    // 今日待办列表口径：未完成顺延 + 今日完成
    const isTodayTodo = (t) => t.completed ? doneToday(t) : true;
    const todayTodos = todos.filter(isTodayTodo);
    const completedCount = todos.filter(doneToday).length;   // 今日已完成数（唯一统计口径）
    // 未完成自动顺延：今日列表里仍会出现的待办总数（用于 Hero 展示"可继续的待办"）
    const totalCount = todos.filter(t => !t.completed).length + completedCount;
    const pct = totalCount > 0 ? Math.round(completedCount / totalCount * 100) : 0;

    // ===== Apple 风格浅蓝 Hero 卡：今日复盘进度 + 右侧倒数日（v8.11.1/8.11.4 对齐画布） =====
    const hero = document.createElement('div');
    hero.className = 'home-hero home-hero--split';
    hero.innerHTML = `
      <div class="home-hero__progress">
        <div class="home-hero__top">
          <span class="home-hero__label">今日待办</span>
        </div>
        <div class="home-hero__num">${completedCount}<span class="home-hero__unit"> 项已完成</span></div>
        <div class="home-hero__bar"><i style="width:${pct}%"></i></div>
        <div class="home-hero__foot">还有 ${unmastered} 道错题待掌握 · 本周新增 ${weekNew} 道</div>
        <!-- v8.15.47 计时胶囊：最近一个计时中的待办（无计时时隐藏） -->
        <div class="home-hero__timer" id="home-timer" style="display:none;"></div>
      </div>
      <div class="home-hero__countdown" id="home-countdown"></div>
    `;
    container.insertBefore(hero, featureGrid);
    this._renderCountdown(hero.querySelector('#home-countdown'));
    this._renderHomeTimer(hero);

    const todoWrap = document.createElement('div');
    todoWrap.style.cssText = 'padding:var(--spacing-lg) var(--page-padding) 0;';

    // 头部：标题 + 筛选下拉 + 概览 + 统计入口
    const todoHead = document.createElement('div');
    todoHead.style.cssText = 'display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--spacing-sm);';
    const filterLabelMap = { active: '进行中', done: '已完成', all: '全部' };
    const filterLabel = filterLabelMap[this.todoState.filter] || '全部';
    const buildFilterPanel = () => {
      const newPanel = document.createElement('div');
      newPanel.id = 'todo-filter-panel';
      newPanel.style.cssText = 'overflow:hidden;max-height:0;opacity:0;transform:translateY(-8px);transition:max-height 0.3s ease,opacity 0.24s ease,transform 0.24s ease;';
      const inner = document.createElement('div');
      inner.style.cssText = 'display:flex;gap:var(--spacing-sm);padding:var(--spacing-sm) var(--page-padding);background:var(--bg-tertiary);border-radius:var(--radius-md);';
      [['active','进行中'],['done','已完成'],['all','全部']].forEach(function (pair) {
        const key = pair[0], label = pair[1];
        const chip = document.createElement('div');
        const active = this.todoState.filter === key;
        chip.style.cssText = 'flex:1;text-align:center;padding:6px 0;border-radius:9999px;font-size:var(--font-xs);font-weight:500;cursor:pointer;-webkit-tap-highlight-color:transparent;' + (active ? 'background:var(--color-primary);color:#fff;' : 'background:var(--bg-card);color:var(--text-secondary);');
        chip.textContent = label;
        chip.addEventListener('click', (e) => {
          e.stopPropagation();
          this.todoState.filter = key;
          const lblSpan = document.getElementById('todo-filter-label-text');
          if (lblSpan) lblSpan.textContent = label;
          const p = document.getElementById('todo-filter-panel');
          const c = document.getElementById('todo-filter-caret');
          if (p) { p.style.maxHeight = '0px'; p.style.opacity = '0'; p.style.transform = 'translateY(-8px)'; const pp = p; setTimeout(() => { if (pp && pp.parentNode) pp.remove(); }, 300); }
          if (c) c.style.transform = 'rotate(0deg)';
          App.Utils.transitionSwap(todoCard, (c) => fillTodoList(c));
          this.todoState.filterOpen = false;
        });
        inner.appendChild(chip);
      }.bind(this));
      newPanel.appendChild(inner);
      return newPanel;
    };
    todoHead.innerHTML = `
      <div style='display:flex;align-items:center;gap:var(--spacing-sm);'>
        <div style='font-size:var(--font-lg);font-weight:600;display:flex;align-items:center;gap:7px;'>
          <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="3" width="11" height="10.5" rx="2.5"/><path d="M5.2 8.2L7 10L10.8 6.2"/></svg>
          <span>今日待办</span>
        </div>
      </div>
      <div style='display:flex;align-items:center;gap:8px;'>
        <!-- v8.12.13 取消标题区统计数字（对齐画布：仅保留新增按钮） -->
        <button id='todo-add-btn' type='button' style='border:none;background:var(--color-primary);color:#fff;height:30px;padding:0 14px;border-radius:15px;font-size:13px;font-weight:500;cursor:pointer;display:flex;align-items:center;gap:4px;-webkit-tap-highlight-color:transparent;'>＋ 新增</button>
      </div>
    `;
    // v8.12.4 对齐画布 7:134：今日待办标题行去掉折叠按钮 ▾（设计稿仅「计数 + 新增」）
    // v8.6.37 去除「统计」按钮及功能
    todoHead.querySelector('#todo-add-btn').addEventListener('click', (e) => {
      e.stopPropagation();
      const overlay = document.createElement('div');
      overlay.className = 'todo-modal-overlay';
      const card = document.createElement('div');
      card.className = 'todo-modal';
      const head = document.createElement('div');
      head.className = 'todo-modal__head';
      const htitle = document.createElement('div');
      htitle.className = 'todo-modal__title';
      htitle.textContent = '新增待办';
      const closeBtn = document.createElement('button');
      closeBtn.type = 'button';
      closeBtn.className = 'todo-modal__close';
      closeBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M3 3l6 6M9 3L3 9"/></svg>';
      head.appendChild(htitle); head.appendChild(closeBtn);
      const lbl1 = document.createElement('div');
      lbl1.className = 'todo-modal__label';
      lbl1.textContent = '待办内容';
      const input = document.createElement('textarea');
      input.className = 'todo-modal__input';
      input.placeholder = '输入待办内容…';
      input.rows = 2;
      const lbl2 = document.createElement('div');
      lbl2.className = 'todo-modal__label';
      lbl2.textContent = '科目';
      let curType = this.todoState.type || 'yanyu';
      const chips = document.createElement('div');
      chips.className = 'todo-modal__chips';
      const refreshChips = () => {
        chips.innerHTML = '';
        TODO_TYPES.forEach(t => {
          const on = t.key === curType;
          const c = document.createElement('div');
          c.className = 'todo-modal__chip' + (on ? ' on' : '');
          c.textContent = t.label;   // 纯文字（对齐画布）
          c.addEventListener('click', () => { curType = t.key; refreshChips(); });
          chips.appendChild(c);
        });
      };
      refreshChips();
      const actions = document.createElement('div');
      actions.className = 'todo-modal__actions';
      const cancelBtn = document.createElement('button');
      cancelBtn.type = 'button'; cancelBtn.className = 'todo-modal__btn todo-modal__btn--cancel'; cancelBtn.textContent = '取消';
      const okBtn = document.createElement('button');
      okBtn.type = 'button'; okBtn.className = 'todo-modal__btn todo-modal__btn--ok'; okBtn.textContent = '保存';
      actions.appendChild(cancelBtn); actions.appendChild(okBtn);
      card.appendChild(head);
      card.appendChild(lbl1); card.appendChild(input);
      card.appendChild(lbl2); card.appendChild(chips);
      card.appendChild(actions);
      overlay.appendChild(card);
      document.body.appendChild(overlay);
      const close = () => overlay.remove();
      closeBtn.addEventListener('click', close);
      overlay.addEventListener('click', (ev) => { if (ev.target === overlay) close(); });
      cancelBtn.addEventListener('click', close);
      okBtn.addEventListener('click', async () => {
        const text = input.value.trim();
        if (!text) { App.Components.toast('请输入待办内容', 'error'); return; }
        const newTodo = await App.DB.addTodo({ text: text, type: curType, completed: false, createdAt: new Date().toISOString() });
        todos.push(newTodo);
        App.Components.toast('已添加 ✓', 'success');
        close();
        refreshTodo();
      });
      setTimeout(() => input.focus(), 60);
    });
    todoWrap.appendChild(todoHead);

    // v8.12.12 进度条升级对齐画布：8px 高、圆角 4、品牌蓝渐变、右侧加 X/Y 已完成文字
    const progressBar = document.createElement('div');
    progressBar.style.cssText = 'display:flex;align-items:center;gap:10px;margin-bottom:var(--spacing-md);';
    const progressTrack = document.createElement('div');
    progressTrack.style.cssText = 'flex:1;height:8px;background:rgba(0,102,204,0.10);border-radius:4px;overflow:hidden;';
    const progressFill = document.createElement('div');
    progressFill.id = 'todo-progress-fill';
    // v8.14.8 只统计已完成：今日有完成即满格（突出完成成就感，不体现未完成数量）
    progressFill.style.cssText = 'height:100%;width:' + (completedCount > 0 ? 100 : 0) + '%;background:linear-gradient(90deg,#0066CC,#1E8FFF);border-radius:4px;transition:width 0.3s ease;';
    progressTrack.appendChild(progressFill);
    const progressLabel = document.createElement('div');
    progressLabel.id = 'todo-progress-label';
    progressLabel.style.cssText = 'font-size:12px;color:#7A7A7A;white-space:nowrap;';
    progressLabel.textContent = completedCount + ' 已完成';
    progressBar.appendChild(progressTrack);
    progressBar.appendChild(progressLabel);
    todoWrap.appendChild(progressBar);

    // 统计面板（就地展开/收起，不整页重绘）
    const buildStatsPanel = () => {
      const statsPanel = document.createElement('div');
      statsPanel.id = 'todo-stats-panel';
      statsPanel.className = 'todo-stats';
      statsPanel.style.animation = 'fadeIn 0.25s ease';
      const mode = this.todoState.statsMode;
      const pad = (n) => String(n).padStart(2, '0');
      const now = new Date();
      const todayStr = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
      const dateKey = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
      // v8.14.8 顺延统计：统计面板只统计"当日已完成"（completedAt 在今天），未完成自动顺延、不进入统计展示
      const isDoneToday = (todo) => {
        if (!todo.completed) return false;
        const c = new Date(todo.completedAt || todo.updatedAt);
        return dateKey(c) === todayStr;
      };
      const doneCount = todos.filter(isDoneToday).length;
      statsPanel.innerHTML = `
        <div class='todo-stats__tabs' id='todo-stats-tabs'></div>
        <div class='todo-stats__grid todo-stats__grid--doneonly'>
          <div class='todo-stats__card todo-stats__card--full'>
            <div class='todo-stats__value todo-stats__value--done'>${doneCount}</div>
            <div class='todo-stats__label'>今日已完成</div>
          </div>
        </div>
      `;
      // 统计固定为「今日」：只展示今日数据（与待办列表今日筛选一致），无周/月切换
      const tabsWrap = statsPanel.querySelector('#todo-stats-tabs');
      const tab = document.createElement('div');
      tab.className = 'todo-stats__tab active';
      tab.textContent = '今日';
      tabsWrap.appendChild(tab);
      return statsPanel;
    };

    // 日期筛选（默认今日，解决「今日待办」显示昨天待办的问题；v8.6.19 单行横向不换行）
    // v8.6.28 日期筛选：class + CSS !important 双保险（防横向变纵向）
    const dateRow = document.createElement('div');
    dateRow.className = 'todo-date-row';
    dateRow.style.cssText = 'display:flex;gap:var(--spacing-sm);margin-bottom:var(--spacing-sm);flex-wrap:nowrap;overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:none;';
    [['today','今日'],['week','最近7天'],['all','全部']].forEach(function (pair) {
      const key = pair[0], label = pair[1];
      const chip = document.createElement('div');
      const active = this.todoState.dateFilter === key;
      chip.style.cssText = 'padding:4px 12px;border-radius:9999px;font-size:var(--font-xs);font-weight:500;cursor:pointer;-webkit-tap-highlight-color:transparent;' + (active ? 'background:var(--color-primary);color:#fff;' : 'background:var(--bg-tertiary);color:var(--text-secondary);');
      chip.textContent = label;
      chip.dataset.dk = key;
      chip.addEventListener('click', () => {
        this.todoState.dateFilter = key;
        dateRow.querySelectorAll('[data-dk]').forEach(c => {
          const on = c.dataset.dk === key;
          c.style.background = on ? 'var(--color-primary)' : 'var(--bg-tertiary)';
          c.style.color = on ? '#fff' : 'var(--text-secondary)';
        });
        refreshTodo();
      });
      dateRow.appendChild(chip);
    }.bind(this));
    // v8.11.3 日期筛选行不再挂载（对齐画布定稿：新增走「＋新增」弹窗）

    // 待办卡片（v8.11.1 整合大胶囊容器）
    const todoCard = document.createElement('div');
    todoCard.className = 'todo-card';
    todoCard.style.cssText = 'margin-bottom:var(--spacing-md);';

    const fillTodoList = (card) => {
      card.innerHTML = '';
      let listTodos = todos.slice();
      // 已完成事项默认移到最下方（勾选完成后自动下沉）
      listTodos.sort((a, b) => {
        if (a.completed !== b.completed) return a.completed ? 1 : -1;
        return new Date(b.createdAt) - new Date(a.createdAt);
      });
    const nowDate = new Date();
    const todayStart = new Date(nowDate.getFullYear(), nowDate.getMonth(), nowDate.getDate());
    const weekStart = new Date(todayStart.getTime() - 6 * 24 * 60 * 60 * 1000);
    // v8.6.37 今日过滤 = 当天 00:00 ~ 24:00 区间（之前是 >= 今天起点，未来日期的待办也显示在今日）
    // v8.14.8 未完成自动顺延：未完成事项无论哪天创建都一直归入今日（直至完成）；已完成仅显示"当日完成的"
    if (this.todoState.dateFilter === 'today') {
      listTodos = listTodos.filter(t => {
        if (!t.completed) return true;                                   // 未完成 → 自动顺延到今日
        const cd = new Date(t.completedAt || t.updatedAt);
        return cd >= todayStart && cd < new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
      });
    } else if (this.todoState.dateFilter === 'week') {
      listTodos = listTodos.filter(t => {
        if (!t.completed) return true;                                   // 未完成 → 顺延始终归入
        const cd = new Date(t.completedAt || t.updatedAt);
        return cd >= weekStart;
      });
    }
    if (this.todoState.filter === 'active') listTodos = listTodos.filter(t => !t.completed);
    else if (this.todoState.filter === 'done') listTodos = listTodos.filter(t => t.completed);

    if (listTodos.length === 0) {
      // v8.11.6 空态对齐画布定稿：清单图标 + 主文案 + 副文案 + 新建待办按钮
      const emptyTxt = {
        all: ['还没有待办事项', '点击右上角 ＋ 新增，开启今日计划'],
        done: ['还没有已完成的待办', '勾选待办前的复选框即可标记完成'],
        active: ['没有进行中的待办，很棒！', '全部完成了，点击 ＋ 新增开启新计划']
      };
      const em = emptyTxt[this.todoState.filter] || emptyTxt.all;
      todoCard.innerHTML = `
        <div class="todo-empty">
          <svg width="44" height="44" viewBox="0 0 44 44" fill="none" stroke="#C7C7CC" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="5.5" y="8" width="33" height="31.5" rx="7"/><path d="M15 22L19.5 26.5L29.5 16.5"/><path d="M12 8V5H32V8"/></svg>
          <div class="todo-empty__title">${em[0]}</div>
          <div class="todo-empty__sub">${em[1]}</div>
          <button type="button" class="todo-empty__btn" id="todo-empty-add">＋ 新建待办</button>
        </div>
      `;
      const addEmptyBtn = todoCard.querySelector('#todo-empty-add');
      if (addEmptyBtn) addEmptyBtn.addEventListener('click', () => {
        const addBtn = document.getElementById('todo-add-btn');
        if (addBtn) addBtn.click();
      });
    } else {
      // v8.6.19 不再折叠已完成事项：全部待办直接显示（已完成沉底排序由 sort 保证）
      const renderItem = (todo) => {
        const item = document.createElement('div');
        item.className = 'todo-item' + (todo.completed ? ' completed' : '');
        // v8.12.18 就地编辑的保存引用（item 级），供点击切换用
        let editSave = null;
        const typeIcon = (TODO_TYPES.find(function (t) { return t.key === typeKeyOf(todo); }) || TODO_TYPES[0]).icon;
        const typeLabel = TYPE_SHORT[typeKeyOf(todo)] || (TODO_TYPES.find(function (t) { return t.key === typeKeyOf(todo); }) || TODO_TYPES[0]).label;
        const checkbox = document.createElement('div');
        checkbox.className = 'todo-checkbox' + (todo.completed ? ' checked' : '');
        checkbox.textContent = todo.completed ? '✓' : '';
        checkbox.addEventListener('click', async (e) => {
          e.stopPropagation();
          todo.completed = !todo.completed;
          todo.status = todo.completed ? 'completed' : (todo.status === 'completed' ? 'pending' : (todo.status || 'pending'));
          if (todo.completed) todo.completedAt = new Date().toISOString();
          else todo.completedAt = null;
          // v8.11.1 勾选完成时若正在计时，先结算累计时长
          // v8.14.10 结算时长同时写入 dailyTimes 按日分段（供学习报告日/周/月统计）
          if (todo.completed && todo.timerStartedAt) {
            const ms = Math.max(0, Date.now() - todo.timerStartedAt);
            todo.elapsedMs = todo.elapsedMs || 0;
            todo.elapsedMs += ms;
            todo.timerStartedAt = null;
            if (!todo.dailyTimes) todo.dailyTimes = {};
            const d = new Date(); const k = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
            todo.dailyTimes[k] = (todo.dailyTimes[k] || 0) + ms;
          }
          await App.DB.updateTodo(todo);
          App.Components.toast(todo.completed ? '已完成 ✓' : '已恢复', 'success');
          refreshTodo();
        });

        const content = document.createElement('div');
        content.className = 'todo-content';
        // v8.11.1 类型灰底胶囊标签 + 标题分离（对齐画布定稿）
        const titleLine = document.createElement('div');
        titleLine.className = 'todo-title-line';
        const typeTag = document.createElement('span');
        typeTag.className = 'todo-type-tag';
        typeTag.textContent = typeLabel;   // v8.11.5 纯文字（对齐画布：灰底胶囊内仅科目名，无 emoji）
        const title = document.createElement('div');
        title.className = 'todo-title';
        title.textContent = todo.text;
        titleLine.appendChild(typeTag);
        titleLine.appendChild(title);
        content.appendChild(titleLine);
        // v8.12.18 对齐画布 57:5：备注直接展示文字（有内容才显示，无折叠开关），左对齐标题
        let noteEl = null;
        if (todo.note) {
          noteEl = document.createElement('div');
          noteEl.className = 'todo-note';
          noteEl.textContent = todo.note;
          content.appendChild(noteEl);
        }

        // v8.12.18 对齐画布 57:5：点击标题行 → 标题原位变输入框（同行，光标闪烁）+ 显示备注输入行（左对齐标题）；失焦/回车自动保存
        const openNoteEdit = (targetItem) => {
          if (targetItem.dataset.editing === '1') return;
          targetItem.dataset.editing = '1';
          targetItem.classList.add('todo-item--editing');          // ① 标题原位变输入框：替换 titleLine 内的 title 元素（typeTag 之后同一行）
          const titleInput = document.createElement('input');
          titleInput.className = 'todo-inline-edit--apple__title';
          titleInput.type = 'text';
          titleInput.value = todo.text || '';
          titleInput.placeholder = '待办内容...';
          titleLine.replaceChild(titleInput, title);

          // ② 备注输入行：插入到 titleLine 之后（透明无底框，左对齐标题）
          const noteArea = document.createElement('textarea');
          noteArea.className = 'todo-inline-edit--apple__note';
          noteArea.placeholder = '添加备注...';
          noteArea.value = todo.note || '';
          noteArea.rows = 1;
          content.appendChild(noteArea);
          if (noteEl) noteEl.style.display = 'none';

          const closeEdit = (rerender) => {
            targetItem.dataset.editing = '0';
            targetItem.classList.remove('todo-item--editing');
            // 恢复 title 原位
            if (titleInput.parentNode) titleInput.parentNode.replaceChild(title, titleInput);
            if (noteArea.parentNode) noteArea.remove();
            if (noteEl) noteEl.style.display = '';
            if (rerender) refreshTodo();
          };

          const save = async () => {
            if (targetItem.dataset.editing !== '1') return;
            const newText = titleInput.value.trim();
            const newNote = noteArea.value.trim();
            let changed = false;
            if (newText && newText !== todo.text) { todo.text = newText; changed = true; }
            if (newNote !== (todo.note || '')) { todo.note = newNote; changed = true; }
            if (changed) {
              await App.DB.updateTodo(todo);
              if (title) title.textContent = todo.text;
              // 备注展示：有内容显示文字，空则移除
              if (todo.note) {
                if (!noteEl) {
                  noteEl = document.createElement('div');
                  noteEl.className = 'todo-note';
                  content.appendChild(noteEl);
                }
                noteEl.textContent = todo.note;
                noteEl.style.display = '';
              } else if (noteEl) {
                noteEl.remove(); noteEl = null;
              }
              App.Components.toast('已保存 ✓', 'success');
            }
            closeEdit(false);
          };
          // 挂载保存引用，供 item 点击 toggle（编辑中再点 = 保存退出）
          editSave = save;

          // 失焦保存：焦点仍在编辑区（标题/备注输入）时不保存，点外部才保存
          const saveIfLeaving = function () {
            setTimeout(function () {
              const active = document.activeElement;
              if (active === titleInput || active === noteArea) return;
              save();
            }, 120);
          };
          titleInput.addEventListener('blur', saveIfLeaving);
          noteArea.addEventListener('blur', saveIfLeaving);
          titleInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); save(); }
            if (e.key === 'Escape') { e.stopPropagation(); closeEdit(false); }
          });
          noteArea.addEventListener('keydown', (e) => { if (e.key === 'Escape') { e.stopPropagation(); closeEdit(false); } });
          // v8.12.18 修复：只在输入框本身拦截 click（防止编辑态点输入框误触发 toggle），
          // 不在 content 上全局拦截——否则退出编辑后点标题区域事件被吞，无法再次进入编辑
          titleInput.addEventListener('click', (e) => e.stopPropagation());
          noteArea.addEventListener('click', (e) => e.stopPropagation());
          // 光标闪烁：自动聚焦标题，光标置于末尾
          setTimeout(function () {
            titleInput.focus();
            try { titleInput.setSelectionRange(titleInput.value.length, titleInput.value.length); } catch (e) { /* 忽略 */ }
          }, 0);
        };

        item.addEventListener('click', (e) => {
          if (e.target === checkbox || e.target.closest('.todo-checkbox')) return;
          if (e.target.closest('.todo-item__edit-btn')) return;
          if (e.target.closest('.todo-timer')) return;
          // v8.12.18 toggle：编辑中再点 = 保存退出；未编辑 = 进入就地编辑
          if (item.dataset.editing === '1') {
            if (editSave) editSave();
            return;
          }
          openNoteEdit(item);
        });

        item.appendChild(checkbox);
        item.appendChild(content);

        // v8.11.1 学习计时：时长显示 + ▶/⏸ 计时按钮（点开始/暂停，累计存入 todo.elapsedMs）
        const fmtMs = (ms) => {
          const s = Math.max(0, Math.floor(ms / 1000));
          const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
          const p = (n) => String(n).padStart(2, '0');
          return h > 0 ? h + ':' + p(m) + ':' + p(sec) : p(m) + ':' + p(sec);
        };
        const timerWrap = document.createElement('div');
        timerWrap.className = 'todo-timer' + (todo.timerStartedAt ? ' running' : '');
        const timerText = document.createElement('span');
        timerText.className = 'todo-timer__text' + (todo.completed ? ' is-done' : '');
        const timerCalcMs = () => (todo.elapsedMs || 0) + (todo.timerStartedAt ? (Date.now() - todo.timerStartedAt) : 0);
        timerText.textContent = fmtMs(timerCalcMs());
        const timerBtn = document.createElement('div');
        timerBtn.className = 'todo-timer__btn';
        timerBtn.textContent = todo.timerStartedAt ? '⏸' : '▶';
        if (todo.completed) timerBtn.style.display = 'none';
        timerBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          if (todo.completed) { App.Components.toast('已完成待办无需计时', 'info'); return; }
          if (todo.timerStartedAt) {
            // v8.14.10 暂停时把本次计时写入 elapsedMs + dailyTimes（供学习报告分时统计）
            const ms = Math.max(0, Date.now() - todo.timerStartedAt);
            todo.elapsedMs = (todo.elapsedMs || 0) + ms;
            todo.timerStartedAt = null;
            if (!todo.dailyTimes) todo.dailyTimes = {};
            const dd = new Date(); const dk = dd.getFullYear() + '-' + String(dd.getMonth() + 1).padStart(2, '0') + '-' + String(dd.getDate()).padStart(2, '0');
            todo.dailyTimes[dk] = (todo.dailyTimes[dk] || 0) + ms;
            timerBtn.textContent = '▶';
            timerWrap.classList.remove('running');
            timerText.classList.remove('is-running');
            App.Components.toast('已暂停，累计 ' + fmtMs(todo.elapsedMs), 'info');
          } else {
            todo.timerStartedAt = Date.now();
            timerBtn.textContent = '⏸';
            timerWrap.classList.add('running');
            timerText.classList.add('is-running');
            App.Components.toast('开始计时 ⏱', 'success');
          }
          await App.DB.updateTodo(todo);
        });
        timerWrap.appendChild(timerText);
        timerWrap.appendChild(timerBtn);
        // 供页面级 interval 每秒刷新计时中的显示
        item._timerRefresh = () => { if (todo.timerStartedAt) timerText.textContent = fmtMs(timerCalcMs()); };
        item.appendChild(timerWrap);

        // v8.12.13 右侧编辑按钮：打开编辑待办弹窗（对齐画布 36:134：标题+类型+日历+删除+保存）
        const infoBtn = document.createElement('div');
        infoBtn.className = 'todo-item__edit-btn';
        infoBtn.title = '编辑待办';
        infoBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4z"/></svg>';
        item._infoBtn = infoBtn;
        infoBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          todoEditSheet(todo);
        });
        item.appendChild(infoBtn);

        card.appendChild(item);
      };
      listTodos.forEach(renderItem);
    }
    };
    // 轻量刷新：只更新计数、进度条和列表，绝不整页重绘
    // v8.6.8 修复删除待办后列表仍显示：refreshTodo 改用 DB 最新数据（原用 render 时闭包快照，
    // 删除只动 DB、快照未更新 → 待办「删了还在」）。改为重新 getTodos 再刷新列表与进度。
    const refreshTodo = async () => {
      try { todos = await App.DB.getTodos(); } catch (e) { /* 拉取失败保持旧数据 */ }
      // v8.14.8 只统计已完成：进度条显示"今日已完成"数量，完成后满格
      const cc = todos.filter(doneToday).length;
      const pp = cc > 0 ? 100 : 0;
      // v8.12.13 标题区计数已取消；进度条填充 + 右侧文字同步更新
      const pf = document.getElementById('todo-progress-fill');
      if (pf) pf.style.width = pp + '%';
      const pl = document.getElementById('todo-progress-label');
      if (pl) pl.textContent = cc + ' 已完成';
      App.Utils.transitionSwap(todoCard, (c) => fillTodoList(c));
    };

    // ===== v8.12.13 编辑待办弹窗（对齐画布 36:134：标题+类型+日历选日期+删除+保存） =====
    const todoEditSheet = (todo) => {
      const pad = (n) => String(n).padStart(2, '0');
      const isoDay = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
      let selDate = (todo.scheduleDate || todo.createdAt || new Date().toISOString()).slice(0, 10);
      let view = new Date(selDate.replace(/-/g, '/'));
      const tDef = TODO_TYPES.find(function (t) { return t.key === typeKeyOf(todo); }) || TODO_TYPES[0];

      const overlay = document.createElement('div');
      overlay.className = 'todo-edit-overlay';
      const dlg = document.createElement('div');
      dlg.className = 'todo-edit';

      const head = document.createElement('div');
      head.className = 'todo-edit__head';
      const headTitle = document.createElement('div');
      headTitle.className = 'todo-edit__title';
      headTitle.textContent = '编辑待办';
      const closeBtn = document.createElement('button');
      closeBtn.type = 'button';
      closeBtn.className = 'todo-edit__close';
      closeBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M3 3l6 6M9 3L3 9"/></svg>';
      head.appendChild(headTitle);
      head.appendChild(closeBtn);

      const info = document.createElement('div');
      info.className = 'todo-edit__info';
      // v8.14.8 左侧类型标签可点击：点开横向科目 chips 选类型（对齐「新增待办」）
      let curType = typeKeyOf(todo);
      const typeTag = document.createElement('span');
      typeTag.className = 'todo-edit__type-tag';
      typeTag.title = '点击更改科目';
      const typePickers = document.createElement('div');
      typePickers.className = 'todo-edit__type-picker todo-edit__type-picker--closed';
      typePickers.innerHTML = '';
      const refreshTag = () => {
        const def = TODO_TYPES.find(function (t) { return t.key === curType; }) || TODO_TYPES[0];
        typeTag.textContent = TYPE_SHORT[curType] || def.label;
        typePickers.innerHTML = '';
        TODO_TYPES.forEach(function (t) {
          const c = document.createElement('span');
          c.className = 'todo-edit__type-chip' + (t.key === curType ? ' on' : '');
          c.textContent = t.label;
          c.addEventListener('click', (e) => {
            e.stopPropagation();
            curType = t.key;
            refreshTag();
            closeTypePicker();
          });
          typePickers.appendChild(c);
        });
      };
      const closeTypePicker = () => { typePickers.classList.add('todo-edit__type-picker--closed'); typePickers.classList.remove('todo-edit__type-picker--open'); };
      typeTag.addEventListener('click', (e) => {
        e.stopPropagation();
        typePickers.classList.toggle('todo-edit__type-picker--open');
        typePickers.classList.toggle('todo-edit__type-picker--closed');
      });
      refreshTag();
      const titleInput = document.createElement('input');
      titleInput.className = 'todo-edit__title-input';
      titleInput.type = 'text';
      titleInput.value = todo.text || '';
      info.appendChild(typeTag);
      typePickers.id = 'todo-edit-type-picker';
      info.appendChild(titleInput);

      const secLabel = document.createElement('div');
      secLabel.className = 'todo-edit__section-label';
      secLabel.textContent = '日期';

      const cal = document.createElement('div');
      cal.className = 'todo-edit__cal';
      const renderCal = () => {
        cal.innerHTML = '';
        const monthRow = document.createElement('div');
        monthRow.className = 'todo-edit__cal-month';
        const prevBtn = document.createElement('button');
        prevBtn.type = 'button';
        prevBtn.className = 'todo-edit__cal-nav';
        prevBtn.textContent = '‹';
        const monthLabel = document.createElement('div');
        monthLabel.className = 'todo-edit__cal-month-label';
        monthLabel.textContent = view.getFullYear() + '年' + (view.getMonth() + 1) + '月';
        const nextBtn = document.createElement('button');
        nextBtn.type = 'button';
        nextBtn.className = 'todo-edit__cal-nav';
        nextBtn.textContent = '›';
        prevBtn.addEventListener('click', (e) => { e.stopPropagation(); view = new Date(view.getFullYear(), view.getMonth() - 1, 1); renderCal(); });
        nextBtn.addEventListener('click', (e) => { e.stopPropagation(); view = new Date(view.getFullYear(), view.getMonth() + 1, 1); renderCal(); });
        monthRow.appendChild(prevBtn);
        monthRow.appendChild(monthLabel);
        monthRow.appendChild(nextBtn);
        cal.appendChild(monthRow);

        const grid = document.createElement('div');
        grid.className = 'todo-edit__cal-grid';
        ['日','一','二','三','四','五','六'].forEach(function (w) {
          const h = document.createElement('div');
          h.className = 'todo-edit__cal-dow';
          h.textContent = w;
          grid.appendChild(h);
        });
        const firstDow = view.getDay();
        const dim = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();
        for (let i = 0; i < firstDow; i++) {
          const b = document.createElement('div');
          b.className = 'todo-edit__cal-cell blank';
          grid.appendChild(b);
        }
        const todayKeyStr = isoDay(new Date());
        for (let d = 1; d <= dim; d++) {
          const k = view.getFullYear() + '-' + pad(view.getMonth() + 1) + '-' + pad(d);
          const cell = document.createElement('div');
          cell.className = 'todo-edit__cal-cell';
          cell.textContent = d;
          if (k === todayKeyStr) cell.classList.add('is-today');
          if (k === selDate) cell.classList.add('is-selected');
          cell.addEventListener('click', (e) => {
            e.stopPropagation();
            selDate = k;
            cal.querySelectorAll('.todo-edit__cal-cell').forEach(function (c) { c.classList.remove('is-selected'); });
            cell.classList.add('is-selected');
          });
          grid.appendChild(cell);
        }
        cal.appendChild(grid);
      };
      renderCal();

      const delBtn = document.createElement('button');
      delBtn.type = 'button';
      delBtn.className = 'todo-edit__delete';
      delBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 4h9M5.5 4V2.5h3V4M3.5 4l.8 7h5.4l.8-7M6 6v3.5M8 6v3.5"/></svg>删除待办';

      const actions = document.createElement('div');
      actions.className = 'todo-edit__actions';
      const cancelBtn = document.createElement('button');
      cancelBtn.type = 'button';
      cancelBtn.className = 'todo-edit__btn todo-edit__btn--cancel';
      cancelBtn.textContent = '取消';
      const saveBtn = document.createElement('button');
      saveBtn.type = 'button';
      saveBtn.className = 'todo-edit__btn todo-edit__btn--save';
      saveBtn.textContent = '保存';
      actions.appendChild(cancelBtn);
      actions.appendChild(saveBtn);

      dlg.appendChild(head);
      dlg.appendChild(info);
      dlg.appendChild(typePickers);
      dlg.appendChild(secLabel);
      dlg.appendChild(cal);
      dlg.appendChild(delBtn);
      dlg.appendChild(actions);
      overlay.appendChild(dlg);
      document.body.appendChild(overlay);

      const close = () => overlay.remove();
      closeBtn.addEventListener('click', close);
      overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });
      cancelBtn.addEventListener('click', close);
      saveBtn.addEventListener('click', async () => {
        const newText = titleInput.value.trim();
        if (!newText) { App.Components.toast('请输入待办内容', 'error'); return; }
        let changed = false;
        if (newText !== todo.text) { todo.text = newText; changed = true; }
        // v8.14.8 编辑时可通过左侧类型标签更换科目，保存时写入
        if (curType !== (typeKeyOf(todo) || 'yanyu')) { todo.type = curType; changed = true; }
        const prevDate = (todo.scheduleDate || '').slice(0, 10);
        if (selDate !== prevDate) { todo.scheduleDate = selDate + 'T00:00:00.000Z'; changed = true; }
        todo.updatedAt = new Date().toISOString();
        if (changed) {
          await App.DB.updateTodo(todo);
          App.Components.toast('已保存 ✓', 'success');
        }
        close();
        refreshTodo();
      });
      delBtn.addEventListener('click', async () => {
        const ok = await App.Components.confirm('删除待办', '确定删除这项待办？', '删除', '取消', true);
        if (ok) {
          await App.DB.remove('todos', todo.id);
          App.Components.toast('已删除', 'success');
          close();
          refreshTodo();
        }
      });
      setTimeout(function () { titleInput.focus(); }, 60);
    };

    fillTodoList(todoCard);
    todoWrap.appendChild(todoCard);

    // 类型快捷栏（v8.6.19 与日期筛选一致：单行横向排布，不换行、超出横向滑动）
    // v8.6.28 类型快捷栏：class + CSS !important 双保险，杜绝任何外部样式覆盖导致横向变纵向
    const typeRow = document.createElement('div');
    typeRow.className = 'todo-type-row';
    typeRow.style.cssText = 'display:flex;gap:var(--spacing-sm);margin-bottom:var(--spacing-sm);flex-wrap:nowrap;overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:none;';
    typeRow.style.setProperty('-webkit-scrollbar-display', 'none');
    TODO_TYPES.forEach(function (t) {
      const active = this.todoState.type === t.key;
      const tc = document.createElement('div');
      tc.style.cssText = 'padding:5px 12px;border-radius:9999px;font-size:var(--font-xs);cursor:pointer;-webkit-tap-highlight-color:transparent;' + (active ? 'background:var(--color-primary-bg);color:var(--color-primary);border:1px solid var(--color-primary);' : 'background:var(--bg-tertiary);color:var(--text-tertiary);');
      tc.textContent = t.icon + ' ' + t.label;
      tc.dataset.tk = t.key;
      tc.addEventListener('click', () => {
        this.todoState.type = t.key;
        typeRow.querySelectorAll('[data-tk]').forEach(c => {
          const on = c.dataset.tk === t.key;
          c.style.cssText = 'padding:5px 12px;border-radius:9999px;font-size:var(--font-xs);cursor:pointer;-webkit-tap-highlight-color:transparent;' + (on ? 'background:var(--color-primary-bg);color:var(--color-primary);border:1px solid var(--color-primary);' : 'background:var(--bg-tertiary);color:var(--text-tertiary);');
        });
      });
      typeRow.appendChild(tc);
    }.bind(this));
    // v8.11.3 类型快捷栏不再挂载（对齐画布定稿：科目选择移入新增弹窗）

    // 添加输入
    const addTodoRow = document.createElement('div');
    addTodoRow.style.cssText = 'display:flex;gap:var(--spacing-sm);margin-bottom:var(--spacing-xl);';
    const addInput = document.createElement('input');
    addInput.className = 'form-input';
    addInput.placeholder = '添加待办事项...';
    addInput.style.flex = '1';
    const addBtn = document.createElement('button');
    addBtn.className = 'btn btn--primary btn--sm';
    addBtn.textContent = '添加';
    addBtn.addEventListener('click', async () => {
      const text = addInput.value.trim();
      if (!text) { App.Components.toast('请输入待办内容', 'error'); return; }
      const newTodo = await App.DB.addTodo({ text, type: this.todoState.type, completed: false, createdAt: new Date().toISOString() });
      todos.push(newTodo);
      addInput.value = '';
      App.Components.toast('已添加', 'success');
      refreshTodo();
    });
    addInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') addBtn.click(); });
    addTodoRow.appendChild(addInput);
    addTodoRow.appendChild(addBtn);
    // v8.11.3 行内添加输入不再挂载（对齐画布定稿：由标题栏「＋新增」弹窗替代）

    container.appendChild(todoWrap);

    // v8.11.1 每秒刷新计时中的待办时长显示（仅本页存在期间）
    if (this._timerInterval) clearInterval(this._timerInterval);
    this._timerInterval = setInterval(() => {
      todoCard.querySelectorAll('.todo-item').forEach((el) => {
        if (el._timerRefresh) el._timerRefresh();
      });
      // v8.15.47 同步刷新 hero 计时胶囊时长
      const tEl = document.getElementById('home-timer-time');
      const rt = this._runningTodo();
      if (tEl && rt && rt.timerStartedAt) tEl.textContent = this._fmtHeroMs(this._heroCalcMs(rt));
    }, 1000);

    // ===== 8. 便签（今日待办下方） =====
    await this._renderStickySection(container);

    // 底部留白
    const spacer = document.createElement('div');
    spacer.style.height = '80px';
    container.appendChild(spacer);
  },

  // ===== v8.11.1 倒数日（首页 Hero 右侧）=====
  // ===== v8.15.47 首页 hero 计时胶囊：最近一个计时中的待办（名称+时长+暂停/开始） =====
  _runningTodo() {
    const todos = this._allTodos || [];
    return todos
      .filter(t => t.timerStartedAt && !t.completed)
      .sort((a, b) => (b.timerStartedAt || 0) - (a.timerStartedAt || 0))[0] || null;
  },
  _heroCalcMs(t) {
    return (t.elapsedMs || 0) + (t.timerStartedAt ? (Date.now() - t.timerStartedAt) : 0);
  },
  _fmtHeroMs(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    const p = (n) => String(n).padStart(2, '0');
    return h > 0 ? h + ':' + p(m) + ':' + p(sec) : p(m) + ':' + p(sec);
  },
  _renderHomeTimer(hero) {
    const el = hero ? hero.querySelector('#home-timer') : document.getElementById('home-timer');
    if (!el) return;
    const rt = this._runningTodo();
    if (!rt) { el.style.display = 'none'; el.innerHTML = ''; return; }
    el.style.display = 'flex';
    const esc = (s) => String(s || '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const running = !!rt.timerStartedAt;
    const ico = running
      ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="#0066CC"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>'
      : '<svg width="14" height="14" viewBox="0 0 24 24" fill="#0066CC"><path d="M8 5.5v13l11-6.5z"/></svg>';
    el.innerHTML =
      '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0066CC" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="13" r="8"/><path d="M12 13l3-3M9 2h6"/></svg>' +
      '<span class="home-hero__timer-name">' + esc(rt.text || '待办') + '</span>' +
      '<span class="home-hero__timer-time" id="home-timer-time">' + this._fmtHeroMs(this._heroCalcMs(rt)) + '</span>' +
      '<span class="home-hero__timer-ico">' + ico + '</span>';
    el.onclick = async () => {
      // 复用待办列表计时按钮逻辑：暂停结算到 elapsedMs + dailyTimes，开始记录 timerStartedAt
      if (rt.timerStartedAt) {
        const ms = Math.max(0, Date.now() - rt.timerStartedAt);
        rt.elapsedMs = (rt.elapsedMs || 0) + ms;
        rt.timerStartedAt = null;
        if (!rt.dailyTimes) rt.dailyTimes = {};
        const dd = new Date();
        const dk = dd.getFullYear() + '-' + String(dd.getMonth() + 1).padStart(2, '0') + '-' + String(dd.getDate()).padStart(2, '0');
        rt.dailyTimes[dk] = (rt.dailyTimes[dk] || 0) + ms;
        await App.DB.updateTodo(rt);
        App.Components.toast('已暂停，累计 ' + this._fmtHeroMs(rt.elapsedMs), 'info');
      } else {
        rt.timerStartedAt = Date.now();
        await App.DB.updateTodo(rt);
        App.Components.toast('开始计时 ⏱', 'success');
      }
      // 重建首页刷新胶囊状态 + 待办列表计时按钮
      await this.render({});
    };
  },

  _countdownKey: 'kg_countdown',
  _loadCountdown() {
    try { return JSON.parse(localStorage.getItem(this._countdownKey)) || []; } catch (e) { return []; }
  },
  _saveCountdown(list) { try { localStorage.setItem(this._countdownKey, JSON.stringify(list)); } catch (e) {} },
  _daysUntil(dateStr) {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const t = new Date(dateStr + 'T00:00:00');
    if (isNaN(t.getTime())) return null;
    return Math.round((t.getTime() - today.getTime()) / 86400000);
  },
  _renderCountdown(el) {
    if (!el) return;
    const escapeHtml = (s) => String(s || '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const escapeAttr = escapeHtml;
    const list = this._loadCountdown();
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const todayStr = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
    let html = '<div class="home-hero__cd-title">倒数日</div>';
    if (!list.length) {
      html += '<div class="home-hero__cd-empty">暂无倒数日</div>';
    } else {
      list.slice(0, 4).forEach(it => {
        const d = this._daysUntil(it.date);
        if (d === null) return;
        const cls = d <= 0 ? ' is-passed' : (d <= 30 ? ' is-urgent' : '');
        html += '<div class="home-hero__cd-item" data-id="' + escapeAttr(it.id) + '">' +
          '<div class="home-hero__cd-info">' +
            '<div class="home-hero__cd-name">' + escapeHtml(it.name) + '</div>' +
            '<div class="home-hero__cd-date">' + (d === 0 ? '今天' : (d === 1 ? '明天' : it.date.slice(5).replace('-', '月') + '日')) + '</div>' +
          '</div>' +
          '<div class="home-hero__cd-num' + cls + '">' + (d === 0 ? '今' : (d < 0 ? '已过' : d)) + '<span class="home-hero__cd-unit">' + (d > 0 ? '天' : '') + '</span></div>' +
          '<div class="home-hero__cd-del" data-del="' + escapeAttr(it.id) + '">✕</div>' +
        '</div>';
      });
    }
    html += '<div class="home-hero__cd-add" id="home-cd-add">＋ 新增倒数日</div>';
    el.innerHTML = html;

    const addBtn = el.querySelector('#home-cd-add');
    if (addBtn) addBtn.addEventListener('click', (e) => { e.stopPropagation(); this._countdownSheet(() => this._renderCountdown(el)); });
    el.querySelectorAll('.home-hero__cd-del').forEach(b => {
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = b.getAttribute('data-del');
        const next = this._loadCountdown().filter(x => x.id !== id);
        this._saveCountdown(next);
        this._renderCountdown(el);
      });
    });
  },
  _countdownSheet(onDone) {
    const overlay = document.createElement('div');
    overlay.className = 'notion-mobile-sheet-overlay';
    const sheet = document.createElement('div');
    sheet.className = 'notion-mobile-sheet is-format';
    const handleBar = document.createElement('div');
    handleBar.className = 'notion-mobile-sheet__handle';
    sheet.appendChild(handleBar);
    const content = document.createElement('div');
    content.className = 'notion-mobile-sheet__content';
    const nameInput = document.createElement('input');
    nameInput.className = 'form-input';
    nameInput.placeholder = '如：国考笔试';
    nameInput.style.marginBottom = '10px';
    const dateInput = document.createElement('input');
    dateInput.type = 'date';
    dateInput.className = 'form-input';
    const today = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    dateInput.value = today.getFullYear() + '-' + pad(today.getMonth() + 1) + '-' + pad(today.getDate());
    dateInput.style.marginBottom = '10px';
    const preview = document.createElement('div');
    preview.className = 'cd-preview';
    const updatePreview = () => {
      if (!dateInput.value) { preview.textContent = ''; return; }
      const d = this._daysUntil(dateInput.value);
      preview.textContent = d === null ? '日期无效' : (d === 0 ? '就是今天 🎉' : (d > 0 ? '距离还有 ' + d + ' 天' : '已过去 ' + (-d) + ' 天'));
    };
    dateInput.addEventListener('change', updatePreview);
    updatePreview();
    const actions = document.createElement('div');
    actions.className = 'cd-actions';
    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button'; cancelBtn.className = 'btn'; cancelBtn.textContent = '取消';
    const okBtn = document.createElement('button');
    okBtn.type = 'button'; okBtn.className = 'btn btn--primary'; okBtn.textContent = '确定';
    actions.appendChild(cancelBtn); actions.appendChild(okBtn);
    content.appendChild(nameInput);
    content.appendChild(dateInput);
    content.appendChild(preview);
    content.appendChild(actions);
    sheet.appendChild(content);
    overlay.appendChild(sheet);
    document.body.appendChild(overlay);
    const close = () => overlay.remove();
    overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
    cancelBtn.addEventListener('click', close);
    okBtn.addEventListener('click', () => {
      const name = nameInput.value.trim();
      if (!name) { App.Components.toast('请输入事件名称', 'error'); return; }
      if (!dateInput.value) { App.Components.toast('请选择日期', 'error'); return; }
      const list = this._loadCountdown();
      list.push({ id: 'cd_' + Date.now(), name: name, date: dateInput.value });
      this._saveCountdown(list);
      App.Components.toast('已添加 ✓', 'success');
      close();
      if (onDone) onDone();
    });
    setTimeout(() => nameInput.focus(), 60);
  },

  // ===== 便签模块（首页） =====
  async _renderStickySection(container) {
    const wrap = document.createElement('div');
    wrap.id = 'home-sticky-section';
    wrap.style.cssText = 'padding:0 var(--page-padding);margin-top:var(--spacing-xl);';
    await this._fillStickySection(wrap);
    container.appendChild(wrap);
  },

  async _fillStickySection(wrap) {
    wrap.innerHTML = '';
    let stickies = [];
    try { stickies = await App.DB.getStickies(); } catch (e) {}

    // 标题栏：📝 便签（数量）  [+ 查看全部 ›]
    const head = document.createElement('div');
    head.style.cssText = 'display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--spacing-sm);';
    const left = document.createElement('div');
    left.style.cssText = 'display:flex;align-items:center;gap:var(--spacing-sm);';
    const titleSpan = document.createElement('span');
    titleSpan.style.cssText = 'font-size:var(--font-lg);font-weight:600;display:flex;align-items:center;gap:7px;';
    titleSpan.innerHTML = '<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M4 2.5H12C13.1 2.5 14 3.4 14 4.5V11.5C14 12.6 13.1 13.5 12 13.5H4C2.9 13.5 2 12.6 2 11.5V4.5C2 3.4 2.9 2.5 4 2.5Z"/><path d="M5 6H11M5 8.5H11M5 11H8.5"/></svg><span>便签</span>';
    left.appendChild(titleSpan);
    head.appendChild(left);

    // v8.12.19 便签标题行右侧：仅「＋ 新增」按钮（对齐今日待办 7:508 样式；用户确认不保留管理）
    const right = document.createElement('div');
    right.style.cssText = 'display:flex;align-items:center;gap:10px;';
    const addBtn = document.createElement('button');
    addBtn.type = 'button';
    addBtn.style.cssText = 'border:none;background:var(--color-primary);color:#fff;height:30px;padding:0 14px;border-radius:15px;font-size:13px;font-weight:500;cursor:pointer;display:flex;align-items:center;gap:4px;-webkit-tap-highlight-color:transparent;';
    addBtn.textContent = '＋ 新增';
    addBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      App.Components.stickySheet({
        title: '新增便签',
        onSave: async (data) => {
          try {
            await App.DB.addSticky(data);
            App.Components.toast('已新增便签 ✓', 'success');
            this._refreshStickySection();
          } catch (err) { App.Components.toast('保存失败', 'error'); }
        }
      });
    });
    right.appendChild(addBtn);

    head.appendChild(right);
    wrap.appendChild(head);

    // v8.6.10 首页便签：纵向瀑布流（两列，与管理页一致；替代原横向滚动卡片）
    const masonry = document.createElement('div');
    masonry.className = 'sticky-masonry sticky-masonry--home';
    if (stickies.length === 0) {
      // v8.12.19 空态胶囊（对齐画布 72:4 便签空状态）：图标 + 主文案 + 副文案 + 新建按钮
      const empty = document.createElement('div');
      empty.className = 'sticky-empty--capsule';
      empty.innerHTML =
        '<div class="sticky-empty__icon"><svg width="44" height="44" viewBox="0 0 44 44" fill="none"><rect x="5.5" y="8" width="33" height="31.5" rx="2" stroke="#C7C7CC" stroke-width="1.5"/><path d="M12 15h20M12 21h20M12 27h14" stroke="#C7C7CC" stroke-width="1.5" stroke-linecap="round"/><path d="M29 28l3 3 6-7" stroke="#C7C7CC" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>' +
        '<div class="sticky-empty__title">还没有便签</div>' +
        '<div class="sticky-empty__sub">点击右上角 ＋ 新增，写下第一条便签</div>' +
        '<button type="button" class="sticky-empty__btn"><svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="#0066CC" stroke-width="1.5" stroke-linecap="round"><path d="M7.5 2.5v10M2.5 7.5h10"/></svg><span>新建便签</span></button>';
      empty.querySelector('.sticky-empty__btn').addEventListener('click', (e) => {
        e.stopPropagation();
        App.Components.stickySheet({
          title: '新增便签',
          onSave: async (data) => {
            try {
              await App.DB.addSticky(data);
              App.Components.toast('已新增便签 ✓', 'success');
              this._refreshStickySection();
            } catch (err) { App.Components.toast('保存失败', 'error'); }
          }
        });
      });
      masonry.appendChild(empty);
    } else {
      const stickyGrid = App.Components.stickyMasonry(
        stickies.slice(0, 10),
        'sticky-masonry sticky-masonry--home',
        { onRefresh: () => this._refreshStickySection() }
      );
      wrap.appendChild(stickyGrid);
      return;
    }
    wrap.appendChild(masonry);
  },

  async _refreshStickySection() {
    const wrap = document.getElementById('home-sticky-section');
    if (!wrap) return;
    wrap.style.animation = 'none';
    void wrap.offsetWidth;
    wrap.style.animation = 'fadeIn 0.25s ease';
    await this._fillStickySection(wrap);
  }
};
