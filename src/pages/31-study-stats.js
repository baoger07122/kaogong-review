// ===== 考公笔试复盘系统 - 学习统计页面（日历） =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.StudyStats = {
  _view: null,   // 当前查看的月份（Date，1号）
  _mode: 'month', // v8.12.22 周/月视图切换（默认月，对齐画布 10:507）
  _weekStart: null, // 周视图当前周的周一（Date）

  async render(params) {
    const container = document.getElementById('page-study-stats');
    container.innerHTML = '';
    if (!this._view) { this._view = new Date(); this._view.setDate(1); }
    const view = this._view;
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const key = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
    const todayKey = key(now);

    // 聚合每日待办：只统计「已完成」事项，且按「完成时间 completedAt」分组（而非新建时间 createdAt），
    // 实现完成事项自动顺延到完成当天展示；未完成事项不进日历（用户 v8.15.21 要求只显示已完成）。
    let todos = [];
    try { todos = await App.DB.getTodos(); } catch (e) { todos = []; }
    const byDay = {};
    todos.forEach(t => {
      if (!t.completed) return;   // 只统计已完成的待办
      const doneDate = t.completedAt || t.updatedAt || t.createdAt;   // 完成时间（兜底 updatedAt/createdAt）
      const k = key(new Date(doneDate));
      if (!byDay[k]) byDay[k] = { total: 0, done: 0, items: [] };
      byDay[k].total++;
      byDay[k].done++;
      byDay[k].items.push(t);
    });

    // 待办类型配色（与首页一致，科目色）
    const TODO_TYPE_COLORS = {
      yanyu: '#4A90E2',
      ziliao: '#34C759',
      panduan: '#9B7BFF',
      shuliang: '#FF9F43',
      changshi: '#6B8EAD',
      zhengzhi: '#E03131',
      shenlun: '#F08C00'
    };
    const LEGACY_COLOR_MAP = { study: 'yanyu', review: 'yanyu', practice: 'yanyu', other: 'yanyu' };
    const typeColorOf = (t) => {
      const raw = t.type || 'yanyu';
      const k = TODO_TYPE_COLORS[raw] ? raw : (LEGACY_COLOR_MAP[raw] || 'yanyu');
      return TODO_TYPE_COLORS[k];
    };
    const escapeHtml = (str) => String(str || '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    // 头部：返回 + 学习统计 顶栏（对齐画布 10:123：返回按钮 + 26px 标题）
    container.appendChild(App.Components.pageHeader('学习统计', null, null, {
      onBack: () => App.Router.back()
    }));
    const desc = document.createElement('div');
    desc.style.cssText = 'padding:0 var(--page-padding);margin-top:var(--spacing-sm);margin-bottom:var(--spacing-md);font-size:12px;color:var(--text-tertiary);line-height:1.6;';
    desc.textContent = '按日历查看每日已完成待办；点击日期可补充新建待办。';
    container.appendChild(desc);

    // v8.12.22 周/月 切换胶囊（对齐画布 10:507：灰底胶囊，选中白底+阴影深色字）
    const toggle = document.createElement('div');
    toggle.className = 'stats-toggle';
    const mkTab = (label, mode) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'stats-toggle__tab' + (this._mode === mode ? ' is-active' : '');
      b.textContent = label;
      b.addEventListener('click', () => {
        if (this._mode === mode) return;
        this._mode = mode;
        if (mode === 'week' && !this._weekStart) {
          const d = new Date();
          const day = (d.getDay() + 6) % 7; // 周一=0
          this._weekStart = new Date(d.getFullYear(), d.getMonth(), d.getDate() - day);
        }
        this.render({});
      });
      return b;
    };
    toggle.appendChild(mkTab('周', 'week'));
    toggle.appendChild(mkTab('月', 'month'));
    container.appendChild(toggle);

    if (this._mode === 'week') {
      // ===== 周视图：两周网格（对齐画布 10:512 / 10:645） =====
      const ws = this._weekStart;
      const fmtDate = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
      const mkDay = (d) => {
        const dk = fmtDate(d);
        const info = byDay[dk];
        const isToday = dk === todayKey;
        const isPast = d < new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const cell = document.createElement('div');
        cell.className = 'week-grid__day' + (info && info.total > 0 ? ' has-data' : '') + (isToday ? ' is-today' : '') + (isPast ? ' is-past' : '');
        const dateHtml = '<div class="week-grid__date">' + d.getDate() + (isToday ? '<span class="today-dot"></span>' : '') + '</div>';
        let todosHtml = '';
        if (info && info.total > 0) {
          const maxVisible = 6;
          info.items.slice(0, maxVisible).forEach(t => {
            const color = typeColorOf(t);
            todosHtml += '<div class="week-grid__todo' + (t.completed ? ' week-grid__todo--done' : '') + '" style="background:' + color + '22;color:' + color + '">' + escapeHtml(t.text) + '</div>';
          });
          if (info.items.length > maxVisible) todosHtml += '<div class="week-grid__more">+' + (info.items.length - maxVisible) + '</div>';
        }
        cell.innerHTML = dateHtml + todosHtml;
        cell.addEventListener('click', () => {
          const overlay = document.createElement('div');
          overlay.className = 'notion-mobile-sheet-overlay';
          const sheet = document.createElement('div');
          sheet.className = 'notion-mobile-sheet is-format';
          const handleBar = document.createElement('div');
          handleBar.className = 'notion-mobile-sheet__handle';
          sheet.appendChild(handleBar);
          const content = document.createElement('div');
          content.className = 'notion-mobile-sheet__content';
          const titleEl = document.createElement('div');
          titleEl.className = 'notion-mobile-fmt-title';
          titleEl.textContent = '在 ' + (d.getMonth() + 1) + '月' + d.getDate() + '日 新建待办';
          content.appendChild(titleEl);
          const input = document.createElement('textarea');
          input.className = 'notion-mobile-fmt-input';
          input.placeholder = '待办内容...';
          input.style.cssText = 'width:100%;box-sizing:border-box;min-height:80px;border:1px solid var(--border-color);border-radius:12px;padding:10px;font-size:14px;font-family:inherit;resize:none;outline:none;';
          content.appendChild(input);
          const actions = document.createElement('div');
          actions.style.cssText = 'display:flex;gap:10px;margin-top:12px;';
          const cancelBtn = document.createElement('button');
          cancelBtn.type = 'button';
          cancelBtn.textContent = '取消';
          cancelBtn.style.cssText = 'flex:1;height:42px;border-radius:21px;border:1px solid var(--border-color);background:#F5F5F7;color:var(--text-primary);font-size:14px;cursor:pointer;';
          const saveBtn = document.createElement('button');
          saveBtn.type = 'button';
          saveBtn.textContent = '保存';
          saveBtn.style.cssText = 'flex:1;height:42px;border-radius:21px;border:none;background:var(--gradient-primary);color:#fff;font-size:14px;font-weight:500;cursor:pointer;';
          actions.appendChild(cancelBtn);
          actions.appendChild(saveBtn);
          content.appendChild(actions);
          sheet.appendChild(content);
          overlay.appendChild(sheet);
          document.body.appendChild(overlay);
          cancelBtn.addEventListener('click', () => overlay.remove());
          saveBtn.addEventListener('click', async () => {
            const txt = input.value.trim();
            if (!txt) { App.Components.toast('待办内容不能为空', 'error'); return; }
            const iso = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T09:00:00.000Z';
            try {
              await App.DB.addTodo({ text: txt, completed: false, status: 'pending', type: 'yanyu', createdAt: iso });
              App.Components.toast('已添加 ✓', 'success');
              overlay.remove();
              this.render({});
            } catch (err) { App.Components.toast('保存失败', 'error'); }
          });
          setTimeout(() => { try { input.focus(); } catch (err) {} }, 100);
        });
        return cell;
      };
      const grid = document.createElement('div');
      grid.className = 'week-grid';
      const head = document.createElement('div');
      head.className = 'week-grid__head';
      ['一', '二', '三', '四', '五', '六', '日'].forEach(w => {
        const sEl = document.createElement('span');
        sEl.textContent = w;
        head.appendChild(sEl);
      });
      grid.appendChild(head);
      [0, 7].forEach(offset => {
        const row = document.createElement('div');
        row.className = 'week-grid__row';
        for (let i = 0; i < 7; i++) {
          const d = new Date(ws.getFullYear(), ws.getMonth(), ws.getDate() + offset + i);
          row.appendChild(mkDay(d));
        }
        grid.appendChild(row);
      });
      const hint = document.createElement('div');
      hint.className = 'week-grid__hint';
      hint.textContent = '↑ 滑动查看更多周';
      grid.appendChild(hint);
      container.appendChild(grid);
      const weekNav = document.createElement('div');
      weekNav.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:0 var(--page-padding) var(--spacing-sm);';
      const prevW = document.createElement('button');
      prevW.className = 'stats-nav-btn'; prevW.textContent = '◀ 上周';
      const weekLabel = document.createElement('div');
      weekLabel.style.cssText = 'font-size:var(--font-lg);font-weight:600;';
      weekLabel.textContent = (ws.getMonth() + 1) + '月' + ws.getDate() + '日 起';
      const nextW = document.createElement('button');
      nextW.className = 'stats-nav-btn'; nextW.textContent = '下周 ▶';
      prevW.addEventListener('click', () => { this._weekStart = new Date(ws.getFullYear(), ws.getMonth(), ws.getDate() - 7); this.render({}); });
      nextW.addEventListener('click', () => { this._weekStart = new Date(ws.getFullYear(), ws.getMonth(), ws.getDate() + 7); this.render({}); });
      weekNav.appendChild(prevW); weekNav.appendChild(weekLabel); weekNav.appendChild(nextW);
      container.insertBefore(weekNav, grid);
    } else {
    // ===== 月视图：月份切换 + 日历（保留原实现） =====
    const nav = document.createElement('div');
    nav.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:0 var(--page-padding) var(--spacing-sm);';
    const prevBtn = document.createElement('button');
    prevBtn.className = 'stats-nav-btn'; prevBtn.textContent = '◀ 上月';
    const monthLabel = document.createElement('div');
    monthLabel.style.cssText = 'font-size:var(--font-lg);font-weight:600;';
    // v8.12.24 修复：首次进入时月份标签为空——创建时即按当前 view 初始化文本
    monthLabel.textContent = view.getFullYear() + '年' + (view.getMonth() + 1) + '月';
    const nextBtn = document.createElement('button');
    nextBtn.className = 'stats-nav-btn'; nextBtn.textContent = '下月 ▶';
    const refresh = () => {
      this.render({});
    };
    prevBtn.addEventListener('click', () => { view.setMonth(view.getMonth() - 1); refresh(); });
    nextBtn.addEventListener('click', () => { view.setMonth(view.getMonth() + 1); refresh(); });
    nav.appendChild(prevBtn); nav.appendChild(monthLabel); nav.appendChild(nextBtn);
    container.appendChild(nav);

    const cal = document.createElement('div');
    cal.className = 'study-cal';
    const weeks = ['日', '一', '二', '三', '四', '五', '六'];
    weeks.forEach(w => {
      const h = document.createElement('div');
      h.className = 'study-cal__dow';
      h.textContent = w;
      cal.appendChild(h);
    });
    const firstDow = view.getDay();
    const daysInMonth = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();
    for (let i = 0; i < firstDow; i++) {
      const blank = document.createElement('div');
      blank.className = 'study-cal__cell study-cal__cell--blank';
      cal.appendChild(blank);
    }
    for (let d = 1; d <= daysInMonth; d++) {
      const cell = document.createElement('div');
      const k = view.getFullYear() + '-' + pad(view.getMonth() + 1) + '-' + pad(d);
      const info = byDay[k];
      cell.className = 'study-cal__cell';
      if (k === todayKey) cell.classList.add('is-today');
      let inner = '<div class="study-cal__day">' + d + '</div>';
      if (info && info.total > 0) {
        const cls = info.done === info.total ? 'is-done' : (info.done > 0 ? 'is-part' : 'is-undo');
        cell.classList.add('has-data', cls);
        inner += '<div class="study-cal__todos">';
        const maxVisible = 5;
        info.items.slice(0, maxVisible).forEach(t => {
          const color = typeColorOf(t);
          const doneCls = t.completed ? ' study-cal__todo--done' : '';
          inner += '<div class="study-cal__todo' + doneCls + '" style="--todo-color:' + color + '">' + escapeHtml(t.text) + '</div>';
        });
        if (info.items.length > maxVisible) {
          inner += '<div class="study-cal__more">+' + (info.items.length - maxVisible) + '</div>';
        }
        inner += '</div>';
      } else {
        cell.classList.add('no-data');
      }
      cell.innerHTML = inner;
      cell.addEventListener('click', async (e) => {
        if (e.target.closest('.study-cal__todo') || e.target.closest('.study-cal__more')) return;
        const overlay = document.createElement('div');
        overlay.className = 'notion-mobile-sheet-overlay';
        const sheet = document.createElement('div');
        sheet.className = 'notion-mobile-sheet is-format';
        const handleBar = document.createElement('div');
        handleBar.className = 'notion-mobile-sheet__handle';
        sheet.appendChild(handleBar);
        const content = document.createElement('div');
        content.className = 'notion-mobile-sheet__content';
        const titleEl = document.createElement('div');
        titleEl.className = 'notion-mobile-fmt-title';
        titleEl.textContent = '在 ' + (view.getMonth() + 1) + '月' + d + '日 新建待办';
        content.appendChild(titleEl);
        const input = document.createElement('textarea');
        input.className = 'notion-mobile-fmt-input';
        input.placeholder = '待办内容...';
        input.style.cssText = 'width:100%;box-sizing:border-box;min-height:80px;border:1px solid var(--border-color);border-radius:12px;padding:10px;font-size:14px;font-family:inherit;resize:none;outline:none;';
        content.appendChild(input);
        const typeRow = document.createElement('div');
        typeRow.style.cssText = 'display:flex;flex-wrap:wrap;gap:8px;margin-top:10px;';
        let selectedType = 'yanyu';
        Object.keys(TODO_TYPE_COLORS).forEach(tk => {
          const chip = document.createElement('button');
          chip.type = 'button';
          chip.textContent = ({ yanyu: '言语', ziliao: '资料', panduan: '判断', shuliang: '数量', changshi: '常识', zhengzhi: '政治', shenlun: '申论' })[tk] || tk;
          chip.style.cssText = 'height:28px;padding:0 12px;border-radius:14px;border:1px solid var(--border-color);background:#fff;font-size:12px;cursor:pointer;';
          chip.addEventListener('click', () => {
            selectedType = tk;
            typeRow.querySelectorAll('button').forEach(x => x.style.cssText = 'height:28px;padding:0 12px;border-radius:14px;border:1px solid var(--border-color);background:#fff;font-size:12px;cursor:pointer;');
            chip.style.cssText = 'height:28px;padding:0 12px;border-radius:14px;border:1px solid ' + TODO_TYPE_COLORS[tk] + ';background:' + TODO_TYPE_COLORS[tk] + '22;color:' + TODO_TYPE_COLORS[tk] + ';font-size:12px;font-weight:600;cursor:pointer;';
          });
          typeRow.appendChild(chip);
        });
        content.appendChild(typeRow);
        const actions = document.createElement('div');
        actions.style.cssText = 'display:flex;gap:10px;margin-top:12px;';
        const cancelBtn = document.createElement('button');
        cancelBtn.type = 'button';
        cancelBtn.textContent = '取消';
        cancelBtn.style.cssText = 'flex:1;height:42px;border-radius:21px;border:1px solid var(--border-color);background:#F5F5F7;color:var(--text-primary);font-size:14px;cursor:pointer;';
        const saveBtn = document.createElement('button');
        saveBtn.type = 'button';
        saveBtn.textContent = '保存';
        saveBtn.style.cssText = 'flex:1;height:42px;border-radius:21px;border:none;background:var(--gradient-primary);color:#fff;font-size:14px;font-weight:500;cursor:pointer;';
        actions.appendChild(cancelBtn);
        actions.appendChild(saveBtn);
        content.appendChild(actions);
        sheet.appendChild(content);
        overlay.appendChild(sheet);
        document.body.appendChild(overlay);
        cancelBtn.addEventListener('click', () => overlay.remove());
        saveBtn.addEventListener('click', async () => {
          const txt = input.value.trim();
          if (!txt) { App.Components.toast('待办内容不能为空', 'error'); return; }
          const iso = view.getFullYear() + '-' + pad(view.getMonth() + 1) + '-' + pad(d) + 'T09:00:00.000Z';
          try {
            await App.DB.addTodo({ text: txt, completed: false, status: 'pending', type: selectedType, createdAt: iso });
            App.Components.toast('已添加 ✓', 'success');
            overlay.remove();
            this.render({});
          } catch (err) { App.Components.toast('保存失败', 'error'); }
        });
        setTimeout(() => { try { input.focus(); } catch (err) {} }, 100);
      });
      cal.appendChild(cell);
    }
    container.appendChild(cal);
    }

    // 底部留白
    const spacer = document.createElement('div');
    spacer.style.height = 'var(--spacing-xl)';
    container.appendChild(spacer);
  }
};




