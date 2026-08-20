// ===== 考公笔试复盘系统 - 科目专属复盘工作台 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Workspace = {
  state: {
    subject: null,
    activeTab: 0,
    reviewTasks: [],
    notes: [],
    errors: [],
    reportPeriod: 'day',   // v8.14.10 学习报告周期: day / week / month
    reportTodos: [],
    reportErrors: [],
    reportNotes: [],
    reportPendingSettle: false
  },

  // v8.14.10 学习报告（按画布设计稿：日/周/月三屏切换）
  // 学习时长来自待办按日计时 dailyTimes；错题/笔记/待办同周期聚合
  _pad2(n) { return String(n).padStart(2, '0'); },
  _dkey(d) { return d.getFullYear() + '-' + this._pad2(d.getMonth() + 1) + '-' + this._pad2(d.getDate()); },
  _fmtDur(ms) {
    ms = Math.max(0, Math.round(ms || 0));
    const h = Math.floor(ms / 3600000), m = Math.floor((ms % 3600000) / 60000);
    if (h > 0) return h + 'h ' + m + 'm';
    if (m > 0) return m + 'm';
    return Math.max(1, Math.round(ms / 60000)) + 'm';
  },
  _fmtMin(ms) {
    ms = Math.max(0, Math.round(ms || 0));
    const m = Math.round(ms / 60000);
    return m + 'm';
  },
  // 待办计时跨天结算：把计时中待办的时长按天拆入 dailyTimes（供日/周/月统计）
  _settleOngoing() {
    const now = new Date();
    const settled = [];
    (this.state.reportTodos || []).forEach(t => {
      if (!t.timerStartedAt) return;
      const from = t.timerStartedAt, to = now.getTime();
      if (!(from < to)) { t.timerStartedAt = null; settled.push(t); return; }
      if (!t.dailyTimes) t.dailyTimes = {};
      let cur = new Date(from);
      let pass = 0;
      while (cur < now) {
        const dayEnd = new Date(cur.getFullYear(), cur.getMonth(), cur.getDate() + 1);
        const segEnd = dayEnd < now ? dayEnd : now;
        const segStart = Math.max(from, cur.getTime());
        const segMs = Math.max(0, segEnd.getTime() - segStart);
        if (segMs > 0) {
          const k = this._dkey(cur);
          t.dailyTimes[k] = (t.dailyTimes[k] || 0) + segMs;
        }
        cur = dayEnd; pass++;
        if (pass > 400) break;
      }
      t.elapsedMs = (t.elapsedMs || 0) + (to - from);
      t.timerStartedAt = now.getTime(); // 保留进行中，已把本次累计段入账
      settled.push(t);
    });
    return settled;
  },

  async renderLearnReport(container) {
    const self = this;
    container.innerHTML = '';
    const [todos, errors, notes] = await Promise.all([
      App.DB.getTodos().catch(() => []),
      App.DB.getErrors().catch(() => []),
      App.DB.getNotes().catch(() => [])
    ]);
    this.state.reportTodos = todos;
    this.state.reportErrors = errors;
    this.state.reportNotes = notes;
    this.state.reportPeriod = this.state.reportPeriod || 'day';

    // v8.14.10 跨天结算：把仍在计时的待办时长按天拆分写入 dailyTimes 并持久化
    const settled = this._settleOngoing();
    if (settled.length) {
      await Promise.all(settled.map(t => App.DB.updateTodo(t).catch(() => {})));
    }

    // ===== 顶部返回 + 标题 =====
    // v8.15.31 复用全局 pageHeader（page-header__inner 限宽居中 + 标题居中），返回按钮位置与全局一致
    container.appendChild(App.Components.pageHeader('学习报告', null, null, { onBack: () => App.Router.navigate('home') }));

    // ===== 顶部周期切换胶囊（今日 / 本周 / 本月）=====
    const seg = document.createElement('div');
    seg.className = 'lr-seg';
    const segs = [['day', '今日'], ['week', '本周'], ['month', '本月']];
    seg.style.cssText = 'display:flex;margin:12px var(--page-padding) 6px;gap:6px;padding:4px;background:var(--bg-tertiary);border-radius:9999px;';
    segs.forEach(([k, label]) => {
      const chip = document.createElement('div');
      chip.style.cssText = 'flex:1;text-align:center;padding:7px 0;border-radius:9999px;font-size:13px;font-weight:500;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:background .18s,color .18s;';
      const on = this.state.reportPeriod === k;
      chip.style.background = on ? '#fff' : 'transparent';
      chip.style.color = on ? '#1D1D1F' : '#7A7A7A';
      chip.style.boxShadow = on ? '0 1px 4px rgba(0,0,0,0.08)' : 'none';
      chip.textContent = label;
      chip.addEventListener('click', () => {
        this.state.reportPeriod = k;
        seg.querySelectorAll('div').forEach((c, i) => {
          const on2 = segs[i][0] === k;
          c.style.background = on2 ? '#fff' : 'transparent';
          c.style.color = on2 ? '#1D1D1F' : '#7A7A7A';
          c.style.boxShadow = on2 ? '0 1px 4px rgba(0,0,0,0.08)' : 'none';
        });
        this.renderLearnBody(container);
      });
      seg.appendChild(chip);
    });
    container.appendChild(seg);

    this.renderLearnBody(container);
  },

  // 计算周期范围
  _periodRange() {
    const now = new Date();
    const k = this.state.reportPeriod;
    if (k === 'day') {
      const s = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      return { start: s.getTime(), end: s.getTime() + 86400000 };
    }
    if (k === 'week') {
      const day = now.getDay() || 7;
      const start = new Date(now); start.setDate(now.getDate() - day + 1); start.setHours(0, 0, 0, 0);
      return { start: start.getTime(), end: now.getTime() };
    }
    // month
    const start = new Date(now.getFullYear(), now.getMonth(), 1);
    return { start: start.getTime(), end: now.getTime() };
  },

  // v8.14.10 判断某"日键"(YYYY-MM-DD)是否落在当前报告周期内
  _inPeriod(dk) {
    const p = this.state.reportPeriod;
    if (!dk) return false;
    const parts = dk.split('-');
    if (parts.length < 3) return false;
    const y = parseInt(parts[0], 10), m = parseInt(parts[1], 10), d = parseInt(parts[2], 10);
    const now = new Date();
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(d)) return false;
    if (p === 'day') return y === now.getFullYear() && m === now.getMonth() + 1 && d === now.getDate();
    if (p === 'week') {
      const dow = now.getDay() || 7;
      const ws = new Date(now); ws.setDate(now.getDate() - dow + 1); ws.setHours(0, 0, 0, 0);
      const t = new Date(y, m - 1, d).getTime();
      return t >= ws.getTime() && t <= now.getTime();
    }
    return y === now.getFullYear() && m === now.getMonth() + 1;
  },

  // v8.14.10 待办 type key → 科目名（SUBJECTS 无 key，需显式映射）
  _TODO_SUBJECT_MAP: { yanyu: '言语理解', ziliao: '资料分析', panduan: '判断推理', shuliang: '数量关系', changshi: '常识判断', shenlun: '申论' },
  _subNameOfType(type) {
    const map = this._TODO_SUBJECT_MAP;
    return (type && map[type]) || '常识';
  },
  _subjectByName(name) {
    return App.Constants.SUBJECTS.find(s => s.name === name) || App.Constants.SUBJECTS[0];
  },

  renderLearnBody(container) {
    const self = this;
    const old = container.querySelector('.lr-body');
    if (old) old.remove();
    const body = document.createElement('div');
    body.className = 'lr-body';
    body.style.cssText = 'padding:var(--spacing-md) var(--page-padding) calc(var(--nav-height) + var(--safe-bottom) + 24px);';
    container.appendChild(body);

    const period = this.state.reportPeriod;
    const r = this._periodRange();
    const isToday = period === 'day';
    const periodTodos = this.state.reportTodos.filter(t => t.completed && (t.updatedAt || t.createdAt));
    // 待办明细：周期内完成的（completedAt 落在区间）
    const doneInPeriod = this.state.reportTodos.filter(t => {
      if (!t.completed) return false;
      const d = new Date(t.completedAt || t.updatedAt).getTime();
      return d >= r.start && d <= r.end;
    });

    // ===== 学习时长汇总 =====
    // 日：今日学习时长卡（含科目时长行）；周/月：大字汇总 + 副文案
    const SUBJECTS = App.Constants.SUBJECTS;
    const subjectTime = {};
    SUBJECTS.forEach(s => { subjectTime[s.name] = 0; });
    let totalTime = 0;
    this.state.reportTodos.forEach(t => {
      const target = self._subNameOfType(t.type);
      if (!t.dailyTimes) return;
      Object.keys(t.dailyTimes).forEach(dk => {
        if (self._inPeriod(dk)) {
          const v = t.dailyTimes[dk];
          subjectTime[target] = (subjectTime[target] || 0) + v;
          totalTime += v;
        }
      });
    });

    // 科目类型色（与首页/设计稿一致）
    const SUB_COLORS = [
      '#4A90E2', '#FF9F43', '#9B7BFF', '#34C759', '#6B8EAD', '#1ABC9C'
    ];

    // 日报告卡1：今日学习时长（头部 + 科目时长行）
    if (isToday) {
      const card1 = document.createElement('div');
      card1.className = 'lr-card';
      card1.style.cssText = 'background:#fff;border-radius:16px;padding:14px 16px;margin-bottom:var(--spacing-md);box-shadow:0 2px 10px rgba(0,0,0,0.04);';
      const hd = document.createElement('div');
      hd.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;';
      const hdl = document.createElement('div');
      hdl.style.cssText = 'display:flex;align-items:center;gap:8px;font-size:14px;font-weight:600;color:#1D1D1F;';
      hdl.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#2162D8" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>今日学习时长';
      hd.appendChild(hdl);
      const totalBig = document.createElement('div');
      totalBig.textContent = this._fmtDur(totalTime);
      totalBig.style.cssText = 'font-size:20px;font-weight:600;color:#0066CC;';
      hd.appendChild(totalBig);
      card1.appendChild(hd);
      // 科目时长行（6 科横排）
      const row = document.createElement('div');
      row.style.cssText = 'display:flex;justify-content:space-between;';
      SUBJECTS.forEach((s, i) => {
        const cell = document.createElement('div');
        cell.style.cssText = 'text-align:center;flex:1;';
        const dot = document.createElement('div');
        dot.style.cssText = 'width:8px;height:8px;border-radius:50%;background:' + SUB_COLORS[i] + ';margin:0 auto;';
        const nm = document.createElement('div');
        nm.style.cssText = 'font-size:11px;color:#7A7A7A;margin-top:4px;';
        nm.textContent = (s.icon || '') + ' ' + s.name.replace('理解', '').replace('判断推理', '判断').replace('数量关系', '数量').replace('资料分析', '资料').replace('常识判断', '常识');
        const tm = document.createElement('div');
        tm.style.cssText = 'font-size:12px;font-weight:600;color:#1D1D1F;margin-top:2px;';
        tm.textContent = subjectTime[s.name] > 0 ? this._fmtMin(subjectTime[s.name]) : '—';
        cell.appendChild(dot); cell.appendChild(nm); cell.appendChild(tm);
        row.appendChild(cell);
      });
      card1.appendChild(row);
      body.appendChild(card1);
    } else {
      // 周/月：时长汇总（大字）
      const sum = document.createElement('div');
      sum.style.cssText = 'padding:4px 2px 18px;';
      const big = document.createElement('div');
      big.textContent = this._fmtDur(totalTime);
      big.style.cssText = 'font-size:34px;font-weight:600;color:#1D1D1F;';
      sum.appendChild(big);
      const sub = document.createElement('div');
      const todoTotal = this.state.reportTodos.length;
      const todoDone = doneInPeriod.length;
      sub.textContent = (isToday ? '今日' : (period === 'week' ? '本周' : '本月')) + '学习时长 · ' + todoDone + ' 项待办完成';
      sub.style.cssText = 'font-size:13px;color:#7A7A7A;margin-top:2px;';
      sum.appendChild(sub);
      body.appendChild(sum);
    }

    // ===== 科目时长卡 =====
    const subCard = document.createElement('div');
    subCard.className = 'lr-card';
    subCard.style.cssText = 'background:#fff;border-radius:16px;padding:14px 16px;margin-bottom:var(--spacing-md);box-shadow:0 2px 10px rgba(0,0,0,0.04);';
    const subT = document.createElement('div');
    subT.textContent = '科目时长';
    subT.style.cssText = 'font-size:14px;font-weight:600;color:#1D1D1F;margin-bottom:10px;';
    subCard.appendChild(subT);
    SUBJECTS.forEach((s, i) => {
      const lr = document.createElement('div');
      lr.style.cssText = 'display:flex;align-items:center;gap:10px;padding:5px 0;';
      const dot = document.createElement('span');
      dot.style.cssText = 'width:8px;height:8px;border-radius:50%;background:' + SUB_COLORS[i] + ';flex-shrink:0;';
      const nm = document.createElement('span');
      nm.style.cssText = 'font-size:13px;color:#4B4B50;flex:0 0 60px;';
      nm.textContent = s.name.replace('理解', '').replace('判断推理', '判断').replace('数量关系', '数量').replace('资料分析', '资料').replace('常识判断', '常识');
      // 进度条
      const barWrap = document.createElement('div');
      barWrap.style.cssText = 'flex:1;height:8px;background:rgba(0,0,0,0.06);border-radius:4px;overflow:hidden;';
      const bar = document.createElement('div');
      const maxT = Math.max.apply(null, SUBJECTS.map(x => subjectTime[x.name])); 
      const pct = maxT > 0 ? Math.min(100, Math.round(subjectTime[s.name] / maxT * 100)) : 0;
      bar.style.cssText = 'height:100%;width:' + pct + '%;background:' + SUB_COLORS[i] + ';border-radius:4px;';
      barWrap.appendChild(bar);
      const tm = document.createElement('span');
      tm.style.cssText = 'font-size:13px;font-weight:600;color:#1D1D1F;flex:0 0 40px;text-align:right;';
      tm.textContent = subjectTime[s.name] > 0 ? this._fmtMin(subjectTime[s.name]) : '—';
      lr.appendChild(dot); lr.appendChild(nm); lr.appendChild(barWrap); lr.appendChild(tm);
      subCard.appendChild(lr);
    });
    body.appendChild(subCard);

    // ===== 周/月 额外卡片：错题统计 + 笔记动态 =====
    if (!isToday) {
      // 错题统计卡
      const errs = this.state.reportErrors.filter(e => {
        const d = new Date(e.createdAt).getTime();
        return d >= r.start && d <= r.end;
      });
      const allErrs = this.state.reportErrors;
      const unmasteredAll = allErrs.filter(e => e.status === '未掌握').length;
      const masteredAll = allErrs.filter(e => e.status === '已掌握').length;
      const errCard = document.createElement('div');
      errCard.className = 'lr-card';
      errCard.style.cssText = 'background:#fff;border-radius:16px;padding:14px 16px;margin-bottom:var(--spacing-md);box-shadow:0 2px 10px rgba(0,0,0,0.04);';
      const errT = document.createElement('div');
      errT.textContent = '错题统计';
      errT.style.cssText = 'font-size:14px;font-weight:600;color:#1D1D1F;margin-bottom:10px;';
      errCard.appendChild(errT);
      const stats = [['本周新增', errs.length], ['待掌握', unmasteredAll], ['已掌握', masteredAll], ['总错题', allErrs.length]];
      const grid = document.createElement('div');
      grid.style.cssText = 'display:flex;text-align:center;';
      stats.forEach(([lb, val]) => {
        const it = document.createElement('div');
        it.style.cssText = 'flex:1;';
        const v = document.createElement('div');
        v.textContent = val;
        v.style.cssText = 'font-size:20px;font-weight:700;color:#1D1D1F;';
        const l = document.createElement('div');
        l.textContent = period === 'week' ? lb.replace('本周', '本') : (lb === '本周新增' ? '本月新增' : lb);
        l.style.cssText = 'font-size:11px;color:#7A7A7A;margin-top:2px;';
        it.appendChild(v); it.appendChild(l);
        grid.appendChild(it);
      });
      errCard.appendChild(grid);
      body.appendChild(errCard);

      // 笔记动态卡
      const notes = this.state.reportNotes.slice().sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 3);
      const noteCard = document.createElement('div');
      noteCard.className = 'lr-card';
      noteCard.style.cssText = 'background:#fff;border-radius:16px;padding:14px 16px;margin-bottom:var(--spacing-md);box-shadow:0 2px 10px rgba(0,0,0,0.04);';
      const noteT = document.createElement('div');
      noteT.textContent = '笔记动态';
      noteT.style.cssText = 'font-size:14px;font-weight:600;color:#1D1D1F;margin-bottom:10px;';
      noteCard.appendChild(noteT);
      if (notes.length === 0) {
        const empty = document.createElement('div');
        empty.textContent = '暂无笔记';
        empty.style.cssText = 'font-size:13px;color:#9A9AA0;text-align:center;padding:10px 0;';
        noteCard.appendChild(empty);
      } else {
        notes.forEach(n => {
          const nrow = document.createElement('div');
          nrow.style.cssText = 'display:flex;align-items:center;gap:10px;padding:7px 0;';
          const sub = App.Constants.SUBJECTS.find(s => s.name === n.subject);
          const block = document.createElement('div');
          block.style.cssText = 'width:30px;height:30px;border-radius:8px;background:' + (sub ? sub.color : '#9AA0A6') + '22;display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;';
          block.textContent = sub ? (sub.icon || '') : '📝';
          const t2 = document.createElement('div');
          t2.style.cssText = 'flex:1;font-size:13px;font-weight:500;color:#1D1D1F;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;';
          t2.textContent = n.title || '未命名笔记';
          const d = document.createElement('div');
          const dt = new Date(n.createdAt);
          d.textContent = (dt. getMonth() + 1) + '月' + dt.getDate() + '日';
          d.style.cssText = 'font-size:11px;color:#9A9AA0;flex-shrink:0;';
          nrow.appendChild(block); nrow.appendChild(t2); nrow.appendChild(d);
          noteCard.appendChild(nrow);
        });
      }
      body.appendChild(noteCard);
    }

    // ===== 待办明细卡 =====
    const todoCard = document.createElement('div');
    todoCard.className = 'lr-card';
    todoCard.style.cssText = 'background:#fff;border-radius:16px;padding:0 16px;margin-bottom:var(--spacing-md);box-shadow:0 2px 10px rgba(0,0,0,0.04);';
    const th = document.createElement('div');
    th.textContent = '待办明细';
    th.style.cssText = 'font-size:14px;font-weight:600;color:#1D1D1F;padding:14px 0;border-bottom:1px solid #F2F2F4;';
    todoCard.appendChild(th);
    const list = doneInPeriod.slice().sort((a, b) => new Date(b.completedAt || b.updatedAt) - new Date(a.completedAt || a.updatedAt));
    if (list.length === 0) {
      const empty = document.createElement('div');
      empty.textContent = '本期暂无完成的待办';
      empty.style.cssText = 'font-size:13px;color:#9A9AA0;text-align:center;padding:16px 0;';
      todoCard.appendChild(empty);
    } else {
      list.forEach(t => {
        const sub = self._subjectByName(self._subNameOfType(t.type));
        const row = document.createElement('div');
        row.style.cssText = 'display:flex;align-items:center;gap:10px;padding:11px 0;border-bottom:1px solid #F2F2F4;';
        const check = document.createElement('div');
        check.style.cssText = 'width:16px;height:16px;border-radius:50%;background:#34C759;display:flex;align-items:center;justify-content:center;flex-shrink:0;';
        check.innerHTML = '<svg width="9" height="9" viewBox="0 0 10 10" fill="none"><path d="M2 5l2 2 3.5-4" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        const tx = document.createElement('div');
        tx.style.cssText = 'flex:1;font-size:13px;color:#1D1D1F;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;';
        tx.textContent = t.text || '待办';
        const tag = document.createElement('span');
        tag.style.cssText = 'font-size:11px;color:' + sub.color + ';background:' + sub.color + '1A;padding:3px 8px;border-radius:9999px;flex-shrink:0;';
        const tn = sub.name.replace('理解', '').replace('判断推理', '判断').replace('数量关系', '数量').replace('资料分析', '资料').replace('常识判断', '常识');
        tag.textContent = tn;
        const tm = document.createElement('div');
        const durMs = (t.dailyTimes ? Object.keys(t.dailyTimes).reduce((s2, dk) => s2 + (self._inPeriod(dk) ? t.dailyTimes[dk] : 0), 0) : 0);
        tm.textContent = durMs > 0 ? this._fmtMin(durMs) : '';
        tm.style.cssText = 'font-size:13px;font-weight:600;color:#1D1D1F;flex-shrink:0;min-width:34px;text-align:right;';
        row.appendChild(check); row.appendChild(tx); row.appendChild(tag); row.appendChild(tm);
        todoCard.appendChild(row);
      });
    }
    body.appendChild(todoCard);
  },

  async render(params) {
    const container = document.getElementById('page-workspace');
    container.innerHTML = '';
    // v8.14.10 学习报告重做：按画布设计稿（日/周/月三屏切换），替换原科目工作台
    this.renderLearnReport(container);
    return;
    // == 以下为原科目工作台（废弃，不再渲染） ==
    this.state.activeTab = parseInt(params.tab) || 0;

    // 返回栏（padding 由 .page-header 统一 CSS 控制：贴顶 + 安全区留白，勿用 inline 覆盖）
    const header = document.createElement('div');
    header.className = 'page-header';

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
          () => App.Router.navigate('error-detail?id=' + error.id),
          () => this.loadAndRenderTabs()
        );
        wrapper.appendChild(card);
      });
    }

    container.appendChild(wrapper);
  }
};

