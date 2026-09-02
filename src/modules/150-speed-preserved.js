// ===== 【速算练习】速算练习模块 v8.6.14 重设计（13题型 / 6设置开关 / 强制屏幕键盘 / 蓝白风格） =====
// 设置存 localStorage kg_speed_settings；历史记录 kg_speed_records（兼容旧 speedCalcHistory 展示）
App.Pages.SpeedCalc = {
  state: {
    view: 'home',        // home | practice | result | history
    type: null,
    mode: 'train',       // train | race
    questions: [],       // [{expr, answer, user, correct, timeUsed}]
    idx: 0,
    startTime: 0,
    qStart: 0,
    timerId: null,
    qTimerId: null,
    raceTimerId: null,
    autoNextTimer: null,
    currentInput: '',
    doodleData: null,
    showAns: true
  },
  SETTINGS_KEY: 'kg_speed_settings',
  RECORDS_KEY: 'kg_speed_records',

  // 题型定义（13 种；无 gen 的为 ▼ 占位题型）
  // v8.6.20 题型定义 v2：基础计算 19 项 + 资料分析-增长相关 6 项，每题带评级秒数 s:{excellent,good,pass}
  // v8.6.24 题型定义：基础计算 10 项 + 资料分析 3 项（基期/增量/实战占位），自定义练习整合进基础模块
  TYPES: {
    // ===== 基础计算（10）=====
    addsub2:  { name: '两位数加减',     s: { excellent: 18, good: 22, pass: 28 }, gen: () => { const a = randInt(10, 99), b = randInt(10, 99); return Math.random() < 0.5 ? makeQ(a + ' + ' + b, a + b) : makeQ((a + b) + ' - ' + b, a); } },
    add3:     { name: '三位数加法',     s: { excellent: 35, good: 45, pass: 60 }, gen: () => { const a = randInt(100, 999), b = randInt(100, 999); return makeQ(a + ' + ' + b, a + b); } },
    sub3:     { name: '三位数减法',     s: { excellent: 35, good: 45, pass: 60 }, gen: () => { const a = randInt(300, 999), b = randInt(100, a - 1); return makeQ(a + ' - ' + b, a - b); } },
    addsub3:  { name: '三位数加减',     s: { excellent: 40, good: 50, pass: 70 }, gen: () => { const a = randInt(100, 999), b = randInt(100, 999); return Math.random() < 0.5 ? makeQ(a + ' + ' + b, a + b) : makeQ((a + b) + ' - ' + b, a); } },
    mul2x1:   { name: '两位数乘一位数', s: { excellent: 20, good: 28, pass: 40 }, gen: () => { const a = randInt(10, 99), b = randInt(2, 9); return makeQ(a + ' × ' + b, a * b); } },
    mul3x1:   { name: '三位数乘一位数', s: { excellent: 35, good: 45, pass: 60 }, gen: () => { const a = randInt(100, 999), b = randInt(2, 9); return makeQ(a + ' × ' + b, a * b); } },
    div3x1:   { name: '三位数除一位数', s: { excellent: 24, good: 30, pass: 38 }, gen: () => { const d = randInt(2, 9), n = randInt(100, 999); const a = Math.round(n / d * 100) / 100; return makeQ(n + ' ÷ ' + d, a); } },
    div5x3:   { name: '五位数除三位数', s: { excellent: 45, good: 70, pass: 100 }, gen: () => { const d = randInt(100, 999), n = randInt(10000, 99999); const a = Math.round(n / d * 100) / 100; return makeQ(n + ' ÷ ' + d, a); } },
    spDen:    { name: '特殊分母练习',   s: { excellent: 10, good: 15, pass: 20 }, gen: () => { const pool = [[5, '5%'], [12.5, '12.5%'], [25, '25%'], [37.5, '37.5%'], [50, '50%'], [75, '75%'], [87.5, '87.5%']]; const p = pool[randInt(0, pool.length - 1)], n = randInt(40, 400); return makeQ(n + ' × ' + p[1] + ' =', Math.round(n * p[0] / 100)); } },
    est05:    { name: '估算练习', s: { excellent: 20, good: 30, pass: 45 }, gen: () => { const a = randInt(11, 99), b = randInt(11, 99), ra = Math.round(a / 10) * 10, rb = Math.round(b / 10) * 10; return makeQ(a + ' × ' + b + ' ≈', ra * rb); } },
    // ===== 资料分析（3）=====
    base:     { name: '基期练习',       s: { excellent: 35, good: 50, pass: 70 }, gen: () => { const b = randInt(100, 9999), r = randInt(2, 30), cur = Math.round(b * (100 + r) / 100); return makeQ('现期 ' + cur + '，同比 +' + r + '%，求基期', Math.round(cur * 100 / (100 + r))); } },
    growth:   { name: '增量练习',       s: { excellent: 30, good: 45, pass: 60 }, gen: () => { const b = randInt(100, 9999), r = randInt(2, 30); return makeQ('基期 ' + b + '，增长率 ' + r + '%，求增量', Math.round(b * r / 100)); } },
    dataReal: { name: '资料分析实战',   s: null, gen: null }
  },

  defaultSettings() {
    return { confirmAuto: true, useScreenKeyboard: true, sequential: false, nightMode: false, noNegative: false, quickMemo: true, selectedType: 'addsub2', lastActiveType: 'addsub2', questionCount: 10, mode: 'train' };
  },
  loadSettings() {
    try { return Object.assign(this.defaultSettings(), JSON.parse(localStorage.getItem(this.SETTINGS_KEY)) || {}); }
    catch (e) { return this.defaultSettings(); }
  },
  saveSettings(s) { try { localStorage.setItem(this.SETTINGS_KEY, JSON.stringify(s)); } catch (e) {} },

  loadHistory() {
    try {
      const list = JSON.parse(localStorage.getItem(this.RECORDS_KEY)) || [];
      if (list.length) return list;
      return JSON.parse(localStorage.getItem('speedCalcHistory')) || [];
    } catch (e) { return []; }
  },
  saveHistory(list) { try { localStorage.setItem(this.RECORDS_KEY, JSON.stringify(list)); } catch (e) {} },

  async render(params) {
    const container = document.getElementById('page-speed-calc');
    container.innerHTML = '';
    // v8.15.36 先解绑上一轮的橡皮筋拦截器，避免重复绑定
    this._unbindRubberLock();
    if (this.state.timerId) { clearInterval(this.state.timerId); this.state.timerId = null; }
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
    if (this.state.autoNextTimer) { clearTimeout(this.state.autoNextTimer); this.state.autoNextTimer = null; }
    const view = this.state.view;
    // v8.15.52 兼容手机/平板：做题页始终锁滚动；首页仅宽屏(iPad>480px)一屏锁定，
    //   手机窄屏首页内容多，需允许纵向滚动（避免 3 列卡片溢出/裁切）。
    const isNarrow = window.innerWidth <= 480;
    // 结果页与做题页同为沉浸式一屏视图；统一锁定页面滚动与 iOS 橡皮筋回弹。
    const lockScroll = (view === 'practice' || view === 'result' || (view === 'home' && !isNarrow));
    document.body.classList.toggle('sc-lock', lockScroll);
    document.body.style.overflow = lockScroll ? 'hidden' : '';
    document.documentElement.style.overflow = lockScroll ? 'hidden' : '';
    if (lockScroll) this._bindRubberLock(container);
    // v8.18.2 非锁定视图（历史/回看/统计/估算表等）显式恢复容器可滚动：
    //   避免从 practice/home 切过来时残留 height:100dvh;overflow:hidden 导致内容被裁剪无法滚动
    if (!lockScroll) {
      container.style.cssText = 'min-height:0;display:flex;flex-direction:column;box-sizing:border-box;overflow-y:auto;';
    }
    if (view === 'home') this.renderHome(container);
    else if (view === 'custom') this.renderCustom(container);
    else if (view === 'estimate') this.renderEstimate(container);
    else if (view === 'estTable') this.renderEstTable(container);
    else if (view === 'practice') this.renderPractice(container);
    else if (view === 'result') this.renderResult(container);
    else if (view === 'history') this.renderHistory(container);
    else if (view === 'historyDetail') this.renderHistoryDetail(container);
    else if (view === 'stats') this.renderStats(container);
  },

  show(view) {
    this.state.view = view;
    // v8.15.46 做题页(practice) + 结果页(result) 沉浸式隐藏底部导航（结果页底栏按钮不被主导航遮挡）
    const nav = document.getElementById('bottom-nav');
    if (nav) nav.classList.toggle('nav--hidden', view === 'practice' || view === 'result');
    if (view !== 'practice') {
      if (this.state.timerId) { clearInterval(this.state.timerId); this.state.timerId = null; }
      if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
      if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
      if (this.state.autoNextTimer) { clearTimeout(this.state.autoNextTimer); this.state.autoNextTimer = null; }
    }
    this.render({});
  },

  // v8.15.36 iOS standalone 橡皮筋回弹拦截：在非被动 touchmove 上，仅当纵向位移 > 阈值才 preventDefault，
  //   从而阻断 window/body 的回弹滚动，同时不影响普通点击（tap 几乎无位移，不会命中阈值）。
  _bindRubberLock(container) {
    this._unbindRubberLock();
    let startY = null, startX = null;
    const onStart = (e) => { const t = e.touches && e.touches[0]; if (t) { startY = t.clientY; startX = t.clientX; } };
    const onMove = (e) => {
      const t = e.touches && e.touches[0];
      if (!t || startY == null) return;
      // v8.18.x 按键丢失修复：touch 起点在可点元素（按钮/卡片等）上 → 放行不拦截，避免误吞点击
      try {
        const tg = e.target;
        if (tg && typeof tg.closest === 'function' && tg.closest('button, .sc-type-card, .sc-hcap, [role="button"], .sc-custom-cell, .sc-numpad__btn')) return;
      } catch (err) {}
      const dy = t.clientY - startY, dx = t.clientX - startX;
      // 纵向位移明显且以纵向为主 → 判定为意图滚动，阻止（含回弹）
      if (Math.abs(dy) > 20 && Math.abs(dy) > Math.abs(dx)) {
        e.preventDefault();
        e.stopPropagation();
      }
    };
    const onEnd = () => { startY = null; startX = null; };
    container.addEventListener('touchstart', onStart, { passive: true });
    container.addEventListener('touchmove', onMove, { passive: false });
    container.addEventListener('touchend', onEnd, { passive: true });
    container.addEventListener('touchcancel', onEnd, { passive: true });
    this._rubberLock = { el: container, onStart, onMove, onEnd };
  },
  _unbindRubberLock() {
    if (this._rubberLock && this._rubberLock.el) {
      const l = this._rubberLock;
      l.el.removeEventListener('touchstart', l.onStart);
      l.el.removeEventListener('touchmove', l.onMove);
      l.el.removeEventListener('touchend', l.onEnd);
      l.el.removeEventListener('touchcancel', l.onEnd);
    }
    this._rubberLock = null;
  },

  // ===== 顶部栏（simple=true 时仅「返回+标题」，不含更多/眼睛；hideEye=true 时仅隐藏眼睛按钮）=====
  _topbar(container, title, onBack, extraRight, simple, hideEye) {
    const noOps = !!simple;
    const header = App.Components.pageHeader(title, null, null, {
      onBack: onBack,
      rightHtml: (extraRight || '') +
                 (noOps ? '' :
                 '<button class="sc-topbar__icon" type="button" id="sc-more" title="更多">⋯</button>' +
                 (hideEye ? '' : '<button class="sc-topbar__icon" type="button" id="sc-eye" title="显示/隐藏答案输入">👁</button>'))
    });
    if (!noOps) {
      header.querySelector('#sc-more').addEventListener('click', () => {
        App.Components.actionSheet([
          { text: '查看历史记录', icon: '🕘', action: () => this.show('history') },
          { text: '清除全部历史记录', icon: '🗑', danger: true, action: async () => {
            const ok = await App.Components.confirm('清除历史', '确定清空所有速算练习记录？', '清除', '取消', true);
            if (ok) { this.saveHistory([]); App.Components.toast('已清除', 'success'); this.render({}); }
          } }
        ]);
      });
      const eyeBtn = header.querySelector('#sc-eye');
      if (eyeBtn) {
        eyeBtn.addEventListener('click', () => {
          this.state.showAns = !this.state.showAns;
          if (this.state.view === 'practice') this.render({});
          else App.Components.toast(this.state.showAns ? '显示答案输入' : '隐藏答案输入', 'info');
        });
      }
    }
    container.appendChild(header);
  },

  // 速算按键音效：触感由全局 App.Haptics 统一处理，这里只保留原有声音反馈。
  // iOS 把 PWA 切到后台后，即使 AudioContext 仍报告 running，音频输出也可能已经失效。
  // 返回前台后的下一次按键强制在用户手势中重建/恢复 context，避免「第一次有声、切后台后静音」。
  _tapKeySound() {
    try {
      const isIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
      if (!isIOS) return;
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      // 仅绑定一次生命周期标记。hidden/pageshow 时不播放声音（不在用户手势内），只标记为下次按键重置。
      if (!this._hapticLifecycleBound) {
        const markReset = () => { this._hapticNeedsReset = true; };
        document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') markReset(); });
        window.addEventListener('pageshow', markReset);
        this._hapticLifecycleBound = true;
      }
      let ctx = this._hapticCtx;
      if (this._hapticNeedsReset || !ctx || ctx.state !== 'running') {
        try { if (ctx && typeof ctx.close === 'function') ctx.close(); } catch (e) {}
        ctx = this._hapticCtx = new AC();
        this._hapticNeedsReset = false;
      }
      const play = () => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.value = 55;
        // v8.18.2 按键音量设为 14
        gain.gain.setValueAtTime(14, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.07);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start();
        osc.stop(ctx.currentTime + 0.07);
      };
      // 先请求 resume；旧版直接调用后立刻 start 会与 iOS 恢复过程竞争，表现为无声。
      if (ctx.state === 'running') play();
      else if (typeof ctx.resume === 'function') ctx.resume().then(() => {
        if (ctx.state === 'running') play();
      }).catch(() => { this._hapticNeedsReset = true; });
    } catch (e) {}
  },

  // ============================================================
  // v8.15 估算练习（零五十估算优化）+ 估算表
  // 逻辑：A(真实分母,随机三位) → B(估算分母,查估算表)；C(估算结果,随机) → D(真实结果,要填)，D≈C×B/A，误差≤3%
  // ============================================================
  EST_KEY: 'kg_speed_est_table',
  loadEstTable() {
    try {
      const rows = JSON.parse(localStorage.getItem(this.EST_KEY)) || [];
      if (rows.length) return rows;
    } catch (e) {}
    return [
      { min: 101, max: 149, value: 100 },
      { min: 150, max: 179, value: 143 },
      { min: 180, max: 199, value: 188 },
      { min: 200, max: 249, value: 200 },
      { min: 250, max: 299, value: 250 },
      { min: 300, max: 399, value: 300 },
      { min: 400, max: 499, value: 400 },
      { min: 500, max: 599, value: 500 }
    ];
  },
  saveEstTable(rows) { try { localStorage.setItem(this.EST_KEY, JSON.stringify(rows)); } catch (e) {} },
  findEstVal(A) {
    const rows = this.loadEstTable();
    const hit = rows.find(r => r && r.min != null && r.max != null && A >= r.min && A <= r.max);
    return hit ? hit.value : null;
  },
  startEstimate() {
    const table = this.loadEstTable();
    if (!table.length || !table.some(r => r && r.min != null && r.max != null)) {
      App.Components.toast('请先在估算表中填写数据区间', 'error');
      return;
    }
    const settings = this.loadSettings();
    const count = settings.questionCount || 10;
    const questions = [];
    let tries = 0;
    while (questions.length < count && tries < 600) {
      tries++;
      const A = randInt(101, 999);
      const B = this.findEstVal(A);
      if (B == null) continue;                       // 估算表未覆盖 → 忽略
      const C = randInt(10, 999);                    // 随机二/三位数
      const D = Math.round((C * B / A) * 100) / 100;
      questions.push({ A: A, B: B, C: C, D: D, q: 'estimate', expr: (A + '→' + B + ' / ' + C + '→?'), answer: D, correct: null, user: '' });
    }
    if (!questions.length) { App.Components.toast('请先在估算表中填写数据区间', 'error'); return; }
    this.state.type = 'est05';
    this.state.questions = questions;
    this.state.idx = 0;
    this.state.startTime = Date.now();
    this.state.qStart = Date.now();
    this.state.currentInput = '';
    this.state.doodleData = null;
    this.state.showAns = true;
    if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    this.show('estimate');
  },

  // ===== 视图：估算表编辑页 =====
  renderEstTable(container) {
    const self = this;
    this._topbar(container, '估算表', () => this.show('home'), '', true);

    const body = document.createElement('div');
    body.className = 'sc-page';

    // 顶部：标题 + 新增
    const header = document.createElement('div');
    header.className = 'sc-esttable-header';
    const title = document.createElement('div');
    title.className = 'sc-esttable-title';
    title.textContent = '范围 → 估算值';
    const addBtn = document.createElement('button');
    addBtn.type = 'button';
    addBtn.className = 'sc-esttable-add';
    addBtn.textContent = '+ 新增';
    header.appendChild(title);
    header.appendChild(addBtn);
    body.appendChild(header);

    // 表头
    const cols = document.createElement('div');
    cols.className = 'sc-esttable-cols';
    cols.innerHTML = '<span>范围</span><span>估算值</span>';
    body.appendChild(cols);

    const sortHint = document.createElement('div');
    sortHint.className = 'sc-esttable-sort';
    sortHint.textContent = '新增行后自动按起始数字排序';
    body.appendChild(sortHint);

    // 列表
    const list = document.createElement('div');
    list.className = 'sc-esttable-list';
    const renderRows = () => {
      list.innerHTML = '';
      const rows = self.loadEstTable().slice().sort((a, b) => (a.min || 0) - (b.min || 0));
      if (!rows.length) {
        const empty = document.createElement('div');
        empty.className = 'sc-esttable-empty';
        empty.textContent = '暂无估算区间，点「+ 新增」添加';
        list.appendChild(empty);
      }
      rows.forEach((r, i) => {
        const row = document.createElement('div');
        row.className = 'sc-esttable-row';
        const rg = document.createElement('span');
        rg.className = 'sc-esttable-row__range';
        rg.textContent = r.min + ' ~ ' + r.max;
        const right = document.createElement('span');
        right.style.display = 'flex'; right.style.alignItems = 'center';
        const val = document.createElement('span');
        val.className = 'sc-esttable-row__value';
        val.textContent = String(r.value);
        const del = document.createElement('button');
        del.type = 'button';
        del.className = 'sc-esttable-row__del';
        del.textContent = '✕';
        del.addEventListener('click', () => {
          // 页面按起始数字排序展示，删除时必须使用相同顺序，否则会删掉另一行。
          const rows2 = self.loadEstTable().slice().sort((a, b) => (a.min || 0) - (b.min || 0));
          rows2.splice(i, 1);
          self.saveEstTable(rows2);
          renderRows();
        });
        right.appendChild(val);
        right.appendChild(del);
        row.appendChild(rg);
        row.appendChild(right);
        list.appendChild(row);
      });
    };
    renderRows();
    body.appendChild(list);

    container.appendChild(body);

    // 新增行弹窗
    addBtn.addEventListener('click', () => {
      const overlay = document.createElement('div');
      overlay.className = 'notion-mobile-sheet-overlay';
      const card = document.createElement('div');
      card.className = 'sc-notion-card';
      card.style.cssText = 'position:absolute;left:50%;top:38%;transform:translate(-50%,-50%);width:420px;max-width:calc(100vw - 40px);background:#fff;border-radius:22px;padding:22px;box-sizing:border-box;box-shadow:0 18px 60px rgba(0,0,0,0.22);';
      const cardTitle = document.createElement('div');
      cardTitle.style.cssText = 'font-size:17px;font-weight:600;color:#1D1D1F;margin-bottom:16px;';
      cardTitle.textContent = '新增估算行';
      card.appendChild(cardTitle);

      const mkField = (label, placeholder, val) => {
        const f = document.createElement('div');
        f.className = 'sc-estmodal-field';
        const lb = document.createElement('div');
        lb.className = 'sc-estmodal-label';
        lb.textContent = label;
        const inp = document.createElement('input');
        inp.type = 'number';
        inp.className = 'sc-estmodal-input';
        inp.value = val != null ? val : '';
        inp.placeholder = placeholder;
        f.appendChild(lb);
        f.appendChild(inp);
        card.appendChild(f);
        return inp;
      };
      // 范围：最小值 ~ 最大值 两个输入框
      const rField = document.createElement('div');
      rField.className = 'sc-estmodal-field';
      const rLabel = document.createElement('div');
      rLabel.className = 'sc-estmodal-label';
      rLabel.textContent = '范围';
      const rWrap = document.createElement('div');
      rWrap.className = 'sc-estmodal-range';
      const minInp = document.createElement('input');
      minInp.type = 'number'; minInp.className = 'sc-estmodal-input'; minInp.placeholder = '最小值';
      const tilde = document.createElement('span');
      tilde.style.cssText = 'color:#9A9AA0;font-size:16px;';
      tilde.textContent = '~';
      const maxInp = document.createElement('input');
      maxInp.type = 'number'; maxInp.className = 'sc-estmodal-input'; maxInp.placeholder = '最大值';
      rWrap.appendChild(minInp);
      rWrap.appendChild(tilde);
      rWrap.appendChild(maxInp);
      rField.appendChild(rLabel);
      rField.appendChild(rWrap);
      card.appendChild(rField);
      const valInp = mkField('估算值', '如 400', '');

      const btnRow = document.createElement('div');
      btnRow.style.cssText = 'display:flex;gap:12px;margin-top:6px;';
      const cancel = document.createElement('button');
      cancel.type = 'button';
      cancel.style.cssText = 'flex:1;height:46px;border:none;border-radius:23px;background:#ECECF2;color:#3A3A3E;font-size:15px;font-weight:500;cursor:pointer;';
      cancel.textContent = '取消';
      cancel.addEventListener('click', () => overlay.remove());
      const ok = document.createElement('button');
      ok.type = 'button';
      ok.style.cssText = 'flex:1;height:46px;border:none;border-radius:23px;background:linear-gradient(135deg,#0066CC,#2996FF);color:#fff;font-size:15px;font-weight:600;cursor:pointer;';
      ok.textContent = '保存';
      ok.addEventListener('click', () => {
        const mn = parseInt(minInp.value, 10), mx = parseInt(maxInp.value, 10), v = parseFloat(valInp.value);
        if (isNaN(mn) || isNaN(mx) || isNaN(v)) { App.Components.toast('请填写范围与估算值', 'error'); return; }
        if (mn >= mx) { App.Components.toast('最小值需小于最大值', 'error'); return; }
        const rows = self.loadEstTable();
        rows.push({ min: mn, max: mx, value: v });
        self.saveEstTable(rows);
        overlay.remove();
        renderRows();
      });
      btnRow.appendChild(cancel);
      btnRow.appendChild(ok);
      card.appendChild(btnRow);

      overlay.appendChild(card);
      overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
      document.body.appendChild(overlay);
    });
  },

  // ===== 视图：估算练习做题页 =====
  renderEstimate(container) {
    const self = this;
    const settings = this.loadSettings();
    const q = this.state.questions[this.state.idx];
    const total = this.state.questions.length;
    const submitted = q.correct !== null;
    this.state.currentInput = q.user !== undefined && q.user !== '' ? String(q.user) : '';

    container.style.cssText = 'height:calc(100svh - var(--nav-height, 56px) - var(--safe-bottom, 0px));display:flex;flex-direction:column;overflow:hidden;';
    this._topbar(container, '估算练习', () => { this.show('home'); });

    // 状态栏
    const statusBar = document.createElement('div');
    statusBar.className = 'sc-statusbar';
    statusBar.innerHTML = '<div class="sc-statusbar__pos">' + (this.state.idx + 1) + '/' + total + '</div><div class="sc-statusbar__timer" id="sc-estp-timer">0:00</div>';
    container.appendChild(statusBar);
    const tick = () => { const el = container.querySelector('#sc-estp-timer'); if (el) el.textContent = fmtClock((Date.now() - this.state.startTime) / 1000); };
    tick();
    this.state.timerId = setInterval(tick, 100);

    // 题目体
    const body = document.createElement('div');
    body.className = 'sc-estp-body';
    const hint = document.createElement('div');
    hint.className = 'sc-estp-hint';
    hint.textContent = '按 A→B 的比例，把 C 缩放成 D';
    body.appendChild(hint);
    const mkRow = (lVal, isB, rVal, isAnswer) => {
      const row = document.createElement('div');
      row.className = 'sc-estp-row';
      const colL = document.createElement('div');
      colL.className = 'sc-estp-col--l';
      colL.innerHTML = '<span class="sc-estp-num">' + lVal + '</span>';
      const arrow = document.createElement('div');
      arrow.className = 'sc-estp-arrow';
      arrow.textContent = '→';
      const colR = document.createElement('div');
      colR.className = 'sc-estp-col--r';
      if (isAnswer) {
        const ans = document.createElement('div');
        ans.className = 'sc-estp-answer' + (q.user === '' ? ' sc-estp-answer--empty' : '');
        ans.id = 'sc-estp-answer';
        ans.textContent = q.user !== '' ? q.user : '答案';
        colR.appendChild(ans);
      } else {
        colR.innerHTML = '<span class="sc-estp-num ' + (isB ? 'sc-estp-num--b' : '') + '">' + rVal + '</span>';
      }
      row.appendChild(colL); row.appendChild(arrow); row.appendChild(colR);
      return row;
    };
    body.appendChild(mkRow(q.A, false, q.B, false));
    body.appendChild(mkRow(q.C, false, null, true));
    container.appendChild(body);

    // 提交
    const submit = () => {
      if (submitted) return;
      const val = parseFloat(self.state.currentInput);
      if (isNaN(val) || self.state.currentInput === '') { App.Components.toast('请输入答案', 'error'); return; }
      q.user = val;
      q.timeUsed = Math.round((Date.now() - self.state.qStart) / 100) / 10;
      q.correct = Math.abs(val - q.D) <= Math.max(1.5, Math.abs(q.D) * 0.03);
      const disp = container.querySelector('#sc-estp-answer');
      if (disp) { disp.textContent = val; disp.classList.remove('sc-estp-answer--empty'); }
      App.Components.toast(q.correct ? '✓' : '✗', q.correct ? 'success' : 'error');
      setTimeout(() => self.next(), 350);
    };

    // 数字键盘（复用现有样式/布局）
    const numpad = document.createElement('div');
    numpad.className = 'sc-numpad sc-numpad--v2';
    numpad.style.cssText = 'flex-shrink:0;';
    const NUM_ROWS = [['1','2','3'],['4','5','6'],['7','8','9'],['+/-','0','.']];
    const FUNC_KEYS = [{ k: 'clear', label: 'C', cls: 'func' }, { k: 'backspace', label: '⌫', cls: 'func' }, { k: 'confirm', label: '✓', cls: 'confirm tall' }];
    const kb = document.createElement('div');
    kb.className = 'sc-numpad__kb';
    const grid = document.createElement('div');
    grid.className = 'sc-numpad__grid';
    const funcCol = document.createElement('div');
    funcCol.className = 'sc-numpad__func';
    const press = (key) => {
      if (submitted) return;
      switch (key) {
        case 'clear': self.state.currentInput = self.state.currentInput.slice(0, -1); break;   // C = 删一个
        case 'backspace': self.state.currentInput = ''; break;                                   // ⌫ = 清空全部
        case 'confirm': submit(); return;
        case '+/-': { const s = self.state.currentInput; self.state.currentInput = s.startsWith('-') ? s.slice(1) : (s ? '-' + s : s); break; }
        case '.': if (!self.state.currentInput.includes('.')) self.state.currentInput += '.'; break;
        default: if (self.state.currentInput.length < 10) self.state.currentInput += key;
      }
      const disp = container.querySelector('#sc-estp-answer');
      if (disp) { disp.textContent = self.state.currentInput || '答案'; disp.classList.toggle('sc-estp-answer--empty', !self.state.currentInput); }
    };
    const mkBtn = (k, extraCls) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'sc-numpad__btn' + (k.cls ? ' sc-numpad__btn--' + k.cls : '') + (extraCls || '');
      b.textContent = k.label || k.k;
      b.addEventListener('click', () => press(k.k));
      // 与普通速算键盘一致：保留按键音效，触感由全局 App.Haptics 统一处理。
      b.addEventListener('pointerdown', () => this._tapKeySound());
      return b;
    };
    NUM_ROWS.forEach(row => row.forEach(k => grid.appendChild(mkBtn({ k: k, label: k }))));
    FUNC_KEYS.forEach(k => funcCol.appendChild(mkBtn(k)));
    kb.appendChild(grid);
    kb.appendChild(funcCol);
    numpad.appendChild(kb);
    container.appendChild(numpad);
  },

  // ===== 视图：题型选择首页 =====
renderHome(container) {
    const self = this;
    const settings = this.loadSettings();
    // v8.15.36 保持上次练习记忆：优先恢复「上次激活题型」（普通题型或自定义练习）
    // lastActiveType 记录最后选的题型：'custom' 或 普通题型 key，普通与自定义统一记忆。
    if (settings.lastActiveType === 'custom') {
      const presets = this.loadCustomPresets();
      const last = presets.lastUsed;
      if (last && (typeof last.type === 'string' || (Array.isArray(last.types) && last.types.length))) {
        this.state.type = 'custom';
        this.resetCustomState();
      } else {
        // 无有效自定义记忆，回退普通题型
        this.state.type = (settings.selectedType && this.TYPES[settings.selectedType]) ? settings.selectedType : null;
      }
    } else {
      this.state.type = (settings.lastActiveType && this.TYPES[settings.lastActiveType]) ? settings.lastActiveType
        : ((settings.selectedType && this.TYPES[settings.selectedType]) ? settings.selectedType : null);
    }
    this.state.mode = settings.mode || 'train';

    // v8.15.52 首页：宽屏(iPad)一屏锁定不滚动；手机窄屏允许纵向滚动（内容多，避免裁切）
    const isNarrowHome = window.innerWidth <= 480;
    container.style.cssText = isNarrowHome
      ? 'min-height:100dvh;display:flex;flex-direction:column;box-sizing:border-box;overflow-y:auto;'
      : 'height:100dvh;min-height:0;display:flex;flex-direction:column;overflow:hidden;box-sizing:border-box;';

    this._topbar(container, '速算练习', () => App.Router.back(), '', true);

    // v8.13.1 首页操作行：历史 + 统计 + 确定开关（三胶囊同排）
    const actionRow = document.createElement('div');
    actionRow.className = 'sc-action-row sc-action-row--home';
    const histBtn = document.createElement('button');
    histBtn.type = 'button';
    histBtn.className = 'sc-action-chip';
    histBtn.innerHTML = '<svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.5" cy="5.5" r="4.3"/><path d="M5.5 3.2V5.5l1.7 1"/></svg><span>历史</span>';
    histBtn.addEventListener('click', () => this.show('history'));
    const statBtn = document.createElement('button');
    statBtn.type = 'button';
    statBtn.className = 'sc-action-chip';
    statBtn.innerHTML = '<svg width="11" height="11" viewBox="0 0 11 11" fill="none"><rect x="2" y="6" width="2.2" height="3.6" rx="0.6" fill="currentColor"/><rect x="4.6" y="4.4" width="2.2" height="5.2" rx="0.6" fill="currentColor"/><rect x="7.2" y="2.6" width="2.2" height="7" rx="0.6" fill="currentColor"/></svg><span>统计</span>';
    statBtn.addEventListener('click', () => this.show('stats'));
    const estBtn = document.createElement('button');
    estBtn.type = 'button';
    estBtn.className = 'sc-action-chip';
    estBtn.innerHTML = '<svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"><path d="M2 3.2V7.8C2 8.5 2.5 9 3.2 9H7.8C8.5 9 9 8.5 9 7.8V3.2C9 2.5 8.5 2 7.8 2H3.2C2.5 2 2 2.5 2 3.2Z"/><path d="M2.5 5h6M2.5 7h6"/></svg><span>估算表</span>';
    estBtn.addEventListener('click', () => this.show('estTable'));
    const confirmChip = document.createElement('div');
    confirmChip.className = 'sc-action-chip sc-action-chip--confirm';
    const confirmSw = document.createElement('div');
    confirmSw.className = 'sc-confirm-row__switch' + (settings.confirmAuto ? ' on' : '');
    confirmSw.innerHTML = '<span class="sc-confirm-row__dot"></span>';
    confirmSw.addEventListener('click', () => {
      settings.confirmAuto = !settings.confirmAuto;
      confirmSw.classList.toggle('on', settings.confirmAuto);
      this.saveSettings(settings);
    });
    confirmChip.innerHTML = '<svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.5" cy="5.5" r="4.2"/><path d="M3.6 5.7l1.4 1.5 2.4-2.7"/></svg><span>确定</span>';
    confirmChip.appendChild(confirmSw);
    // v8.15 历史/统计/估算表 靠左一组，确定开关置右，不占满整行
    const leftGroup = document.createElement('div');
    leftGroup.className = 'sc-action-left';
    leftGroup.appendChild(histBtn);
    leftGroup.appendChild(statBtn);
    leftGroup.appendChild(estBtn);
    actionRow.appendChild(leftGroup);
    actionRow.appendChild(confirmChip);
    container.appendChild(actionRow);

    const body = document.createElement('div');
    body.className = 'sc-page sc-page--home';

    // ===== v8.6.24 模块卡片（基础计算 10 项 + 自定义练习 / 资料分析 3 项）=====
    const MODULES = [
      { key: 'base', title: '基础计算', icon: '🧮', types: ['addsub2', 'add3', 'sub3', 'addsub3', 'mul2x1', 'mul3x1', 'div3x1', 'div5x3', 'spDen', 'est05'], custom: true },
      { key: 'growth', title: '资料分析', icon: '📈', types: ['base', 'growth', 'dataReal'] }
    ];
    const startBtn = document.createElement('button');
    startBtn.type = 'button';
    startBtn.className = 'sc-btn sc-start-btn-v2' + (this.state.type ? '' : ' disabled');
    startBtn.textContent = this.state.type ? (this.state.type === 'custom' ? '开始自定义练习' : '开始练习') : '请先选择题型';
    const renderModuleCard = (mod) => {
      const card = document.createElement('div');
      card.className = 'sc-module-card';
      const head = document.createElement('div');
      head.className = 'sc-module-head';
      const typeCount = mod.types.length;
      head.innerHTML =
        '<div class="sc-module-icon">' + mod.icon + '</div>' +
        '<div class="sc-module-title">' + mod.title + '</div>' +
        '<div class="sc-module-count">' + typeCount + '/' + typeCount + ' 可练习</div>' +
        '<div class="sc-module-arrow">❯</div>';
      const scIcon = (key) => {
        const m = { addsub2: '±', add3: '+', sub3: '−', addsub3: '±', mul2x1: '×', mul3x1: '×', div3x1: '÷', div5x3: '÷', spDen: '%', est05: '≈', base: '📈', growth: '📊', dataReal: '📋', custom: '+' };
        return m[key] || '•';
      };
      const tags = document.createElement('div');
      tags.className = 'sc-type-grid';
      mod.types.forEach(key => {
        const t = this.TYPES[key];
        const hasDrop = !t.gen;   // ▼ 占位题型
        const tag = document.createElement('div');
        tag.className = 'sc-type-card' + (this.state.type === key ? ' selected' : '');
        tag.dataset.tk = key;
        tag.innerHTML =
          '<div class="sc-type-card__icon">' + scIcon(key) + '</div>' +
          '<div class="sc-type-card__body">' +
            '<div class="sc-type-card__name">' + t.name + (hasDrop ? ' <span class="sc-type-item__drop">▾</span>' : '') + '</div>' +
            '<div class="sc-type-card__rate">' + (t.s ? '合格 ' + t.s.pass + 's' : '即将上线') + '</div>' +
          '</div>';
        tag.addEventListener('click', (e) => {
          e.stopPropagation();
          if (!t.gen) { App.Components.toast(t.name + '功能即将上线', 'info'); return; }
          this.state.type = key;
          settings.selectedType = key;
          settings.lastActiveType = key;
          this.saveSettings(settings);
          body.querySelectorAll('.sc-type-card').forEach(x => x.classList.remove('selected'));
          tag.classList.add('selected');
          startBtn.classList.remove('disabled');
          startBtn.textContent = '开始练习';
        });
        tags.appendChild(tag);
      });
      // 自定义练习整合进基础模块：点击弹小窗选择（不进新页面）
      if (mod.custom) {
        const ctag = document.createElement('div');
        ctag.className = 'sc-type-card' + (this.state.type === 'custom' ? ' selected' : '');
        ctag.innerHTML =
          '<div class="sc-type-card__icon">' + scIcon('custom') + '</div>' +
          '<div class="sc-type-card__body">' +
            '<div class="sc-type-card__name">自定义练习 <span class="sc-type-item__drop">▾</span></div>' +
            '<div class="sc-type-card__rate">自选题型组合</div>' +
          '</div>';
        ctag.addEventListener('click', (e) => {
          e.stopPropagation();
          self.renderCustomSheet(() => {
            this.state.type = 'custom';
            body.querySelectorAll('.sc-type-card').forEach(x => x.classList.remove('selected'));
            ctag.classList.add('selected');
            startBtn.classList.remove('disabled');
            startBtn.textContent = '开始自定义练习';
          });
        });
        tags.appendChild(ctag);
      }
      // 头部点击折叠/展开标签云
      let open = true;
      head.addEventListener('click', (e) => {
        if (e.target.closest('.sc-type-card')) return;
        open = !open;
        tags.style.display = open ? '' : 'none';
        head.querySelector('.sc-module-arrow').style.transform = open ? '' : 'rotate(90deg)';
      });
      card.appendChild(head);
      card.appendChild(tags);
      return card;
    };
    MODULES.forEach(m => body.appendChild(renderModuleCard(m)));

    // ===== 底部操作区：题量 / 模式（居中按钮，点击弹小窗选择）+ 开始练习 =====
    const optsRow = document.createElement('div');
    optsRow.className = 'sc-opts-row';
    const countBtn = document.createElement('button');
    countBtn.type = 'button';
    countBtn.className = 'sc-opt-btn';
    const modeBtn = document.createElement('button');
    modeBtn.type = 'button';
    modeBtn.className = 'sc-opt-btn';
    const refreshOpts = () => {
      countBtn.textContent = '题量: ' + (settings.questionCount || 10) + ' ▾';
      modeBtn.textContent = '模式: ' + (this.state.mode === 'race' ? '竞速' : '训练') + ' ▾';
    };
    refreshOpts();
    countBtn.addEventListener('click', () => this.pickOption('题量选择', [10, 15, 20].map(n => ({ v: n, label: n + ' 题' })), settings.questionCount || 10, (n) => { settings.questionCount = n; this.saveSettings(settings); refreshOpts(); }));
    modeBtn.addEventListener('click', () => this.pickOption('模式选择', [{ v: 'train', label: '训练模式' }, { v: 'race', label: '竞速模式' }], this.state.mode, (m) => { this.state.mode = m; settings.mode = m; this.saveSettings(settings); refreshOpts(); }));
    optsRow.appendChild(countBtn);
    optsRow.appendChild(modeBtn);
    body.appendChild(optsRow);

    startBtn.addEventListener('click', () => {
      if (!this.state.type) { App.Components.toast('请先选择题型', 'error'); return; }
      this.startPractice();
    });
    body.appendChild(startBtn);

    container.appendChild(body);

    // ===== 右下角速记悬浮按钮（保留）=====
    const fab = document.createElement('button');
    fab.type = 'button';
    fab.className = 'sc-fab';
    fab.textContent = '速记';
    fab.title = '快速记一笔';
    fab.addEventListener('click', () => {
      App.Components.stickySheet({
        title: '速记',
        onSave: async (data) => {
          try { await App.DB.addSticky(data); App.Components.toast('已速记 ✓', 'success'); }
          catch (e) { App.Components.toast('保存失败', 'error'); }
        }
      });
    });
    container.appendChild(fab);
  },

  // 通用小窗选择器（题量/模式等）：底部弹层单选
  pickOption(title, options, current, cb) {
    const overlay = document.createElement('div');
    overlay.className = 'notion-mobile-sheet-overlay';
    const sheet = document.createElement('div');
    sheet.className = 'notion-mobile-sheet is-format';
    const handleBar = document.createElement('div');
    handleBar.className = 'notion-mobile-sheet__handle';
    sheet.appendChild(handleBar);
    const content = document.createElement('div');
    content.className = 'notion-mobile-sheet__content';
    content.innerHTML = '<div class="notion-mobile-fmt-title">' + title + '</div>' +
      '<div class="sc-opt-list">' + options.map(o =>
        '<div class="sc-opt-item' + (String(o.v) === String(current) ? ' selected' : '') + '" data-v="' + String(o.v) + '">' + o.label + '</div>').join('') + '</div>';
    sheet.appendChild(content);
    overlay.appendChild(sheet);
    document.body.appendChild(overlay);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
    content.querySelectorAll('.sc-opt-item').forEach(it => it.addEventListener('click', () => {
      const v = it.dataset.v;
      overlay.remove();
      if (cb) cb(/^\d+$/.test(v) ? parseInt(v, 10) : v);
    }));
  },

  // v8.15 自定义练习弹窗（设计稿重构）：底部 Sheet（浅灰底）+ 题型选择置顶 + 数字设置[数字范围/固定数字] + 最近使用
  renderCustomSheet(onDone) {
    const self = this;
    if (!this.state.custom) this.resetCustomState();
    const cs = this.state.custom;
    const presets = this.loadCustomPresets();
    if (typeof cs.type !== 'string') cs.type = null;
    if (!Array.isArray(cs.fixedNums)) cs.fixedNums = [];

    const overlay = document.createElement('div');
    overlay.className = 'notion-mobile-sheet-overlay';
    const sheet = document.createElement('div');
    sheet.className = 'notion-mobile-sheet sc-custom-sheet sc-picker-sheet';
    const content = document.createElement('div');
    content.className = 'notion-mobile-sheet__content';

    // v8.15 弹窗打开时锁定背景滚动，避免横/竖屏下滑动穿透到速算练习原生页面；关闭恢复。
    // v8.15.26 改用统一 _lockScroll/_unlockScroll（仅锁 body overflow，不拦截 touchmove），
    // 避免在 iPad Safari 上 touchmove preventDefault 干扰按钮点击导致「弹窗完全卡死」。
    App.Components._lockScroll ? App.Components._lockScroll() : (document.body.style.overflow = 'hidden');
    const closeOverlay = () => {
      if (App.Components._unlockScroll) App.Components._unlockScroll();
      else document.body.style.overflow = '';
      if (overlay.parentNode) overlay.remove();
    };

    // 标题行
    const titleRow = document.createElement('div');
    titleRow.className = 'sc-custom-sheet-title';
    titleRow.innerHTML = '<div class="sc-custom-sheet-title__text">自定义练习</div><button type="button" class="sc-custom-sheet-title__close" aria-label="关闭">✕</button>';
    titleRow.querySelector('.sc-custom-sheet-title__close').addEventListener('click', () => closeOverlay());
    content.appendChild(titleRow);

    const body = document.createElement('div');
    body.className = 'sc-custom-sheet-body';

    // ===== 题型选择（置顶，11 种多选）=====
    const tyTitle = document.createElement('div');
    tyTitle.className = 'sc-custom-block-title';
    tyTitle.textContent = '题型选择';
    body.appendChild(tyTitle);
    const typeGrid = document.createElement('div');
    typeGrid.className = 'sc-custom-grid';
    const renderTypes = () => {
      typeGrid.innerHTML = '';
      this.CUSTOM_ORDER.forEach(key => {
        const c = document.createElement('div');
        c.className = 'sc-custom-cell' + (cs.type === key ? ' selected' : '');
        c.textContent = this.CUSTOM_TYPES[key].name;
        c.addEventListener('click', () => {
          // 单选：点已选取消，点其他替换
          cs.type = cs.type === key ? null : key;
          renderTypes(); renderOk();
        });
        typeGrid.appendChild(c);
      });
    };
    renderTypes();
    body.appendChild(typeGrid);

    // ===== 数字设置（白底卡 + 横排 tab 切换；对所有题型生效）=====
    const numTitle = document.createElement('div');
    numTitle.className = 'sc-custom-block-title';
    numTitle.textContent = '数字设置';
    const dnumCard = document.createElement('div');
    dnumCard.className = 'sc-dnum-card';
    // v8.15.26 撤回显隐控制：数字设置对所有题型都显示并生效（这是自定义练习的核心逻辑）

    // 横排选择按钮组：数字范围 / 固定数字
    const tabs = document.createElement('div');
    tabs.className = 'sc-dnum-tabs';
    const renderTabs = () => {
      tabs.innerHTML = '';
      [['range', '数字范围'], ['fixed', '固定数字']].forEach(function (pair) {
        const mode = pair[0], label = pair[1];
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'sc-dnum-tab' + (cs.mode === mode ? ' selected' : '');
        b.textContent = label;
        b.addEventListener('click', function () { cs.mode = mode; renderTabs(); renderNumInputs(); });
        tabs.appendChild(b);
      });
    };
    renderTabs();
    dnumCard.appendChild(tabs);

    // 数字输入区（随 tab 切换）
    const numInputArea = document.createElement('div');
    const renderNumInputs = () => {
      numInputArea.innerHTML = '';
      const hint = document.createElement('div');
      hint.className = 'sc-dnum-hint';
      if (cs.mode === 'range') {
        hint.textContent = '在范围内随机出题';
        numInputArea.appendChild(hint);
        const rangeWrap = document.createElement('div');
        rangeWrap.className = 'sc-dnum-range';
        const mk = (label, val, cb) => {
          const cell = document.createElement('div');
          const lb = document.createElement('span');
          lb.className = 'sc-dnum-range__label';
          lb.textContent = label;
          const inp = document.createElement('input');
          inp.type = 'number';
          inp.className = 'sc-dnum-range-input';
          inp.value = val != null ? val : '';
          inp.placeholder = label === '最小值' ? '001' : '999';
          inp.addEventListener('input', () => cb(parseInt(inp.value, 10) || null));
          cell.appendChild(lb); cell.appendChild(inp);
          return cell;
        };
        rangeWrap.appendChild(mk('最小值', cs.rangeMin, (v) => { cs.rangeMin = v; }));
        const tilde = document.createElement('span');
        tilde.className = 'sc-dnum-range__tilde'; tilde.textContent = '~';
        rangeWrap.appendChild(tilde);
        rangeWrap.appendChild(mk('最大值', cs.rangeMax, (v) => { cs.rangeMax = v; }));
        numInputArea.appendChild(rangeWrap);
      } else {
        hint.textContent = '可多选，出题时随机取用';
        numInputArea.appendChild(hint);
        const row = document.createElement('div');
        row.className = 'sc-dnum-fixrow';
        for (let i = 2; i <= 9; i++) {
          (function (n) {
            const b = document.createElement('button');
            b.type = 'button';
            b.className = 'sc-dnum-fix' + (cs.fixedNums.includes(n) ? ' selected' : '');
            b.textContent = String(n);
            b.addEventListener('click', () => {
              if (cs.fixedNums.includes(n)) cs.fixedNums = cs.fixedNums.filter(x => x !== n);
              else cs.fixedNums.push(n);
              renderNumInputs(); renderOk();
            });
            row.appendChild(b);
          })(i);
        }
        numInputArea.appendChild(row);
      }
    };
    renderNumInputs();
    dnumCard.appendChild(numInputArea);
    body.appendChild(numTitle);
    body.appendChild(dnumCard);

    // ===== 最近使用 =====
    const histTitle = document.createElement('div');
    histTitle.className = 'sc-custom-block-title';
    histTitle.textContent = '最近使用';
    body.appendChild(histTitle);
    const histGrid = document.createElement('div');
    histGrid.className = 'sc-custom-hist';
    if (presets.history.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'sc-custom-histempty';
      empty.textContent = '暂无历史，完成一次自定义练习后自动记录';
      histGrid.appendChild(empty);
    } else {
      presets.history.forEach((h) => {
        const card = document.createElement('div');
        card.className = 'sc-custom-histcard';
        card.innerHTML = '<div class="sc-custom-histcard__name">' + (h.name || '') + '</div>' +
          '<div class="sc-custom-histcard__sub">' + (h.subName || '') + '</div>';
        card.addEventListener('click', () => {
          // v8.15.28 最近使用点击只回填配置并选中（不直接开始），返回主页后由「开始练习」触发
          cs.type = (typeof h.type === 'string' && this.CUSTOM_TYPES[h.type] && this.CUSTOM_TYPES[h.type].gen) ? h.type
            : (Array.isArray(h.types) && h.types.length && this.CUSTOM_TYPES[h.types[0]] && this.CUSTOM_TYPES[h.types[0]].gen) ? h.types[0]
            : null;
          cs.mode = (h.mode === 'range' || h.mode === 'fixed') ? h.mode : 'fixed';
          cs.rangeMin = h.rangeMin != null ? h.rangeMin : null;
          cs.rangeMax = h.rangeMax != null ? h.rangeMax : null;
          cs.fixedNums = (Array.isArray(h.fixedNums) ? h.fixedNums : []).filter(n => n >= 2 && n <= 9);
          closeOverlay();
          if (onDone) onDone();
        });
        histGrid.appendChild(card);
      });
    }
    body.appendChild(histGrid);

    content.appendChild(body);
    sheet.appendChild(content);

    // 底部操作栏（v8.15.26 改用 sheet 内 flex 定位，不再 fixed，避免遮挡内容底部）
    const foot = document.createElement('div');
    foot.className = 'sc-custom-foot sc-sheet-foot';
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'sc-custom-footbtn sc-custom-footbtn--cancel';
    cancel.textContent = '取消';
    cancel.addEventListener('click', () => closeOverlay());
    const ok = document.createElement('button');
    ok.type = 'button';
    ok.className = 'sc-custom-footbtn sc-custom-footbtn--ok';
    const renderOk = () => {
      const hasType = !!cs.type;
      const hasNum = cs.mode === 'range' ? (cs.rangeMin != null && cs.rangeMax != null) : (Array.isArray(cs.fixedNums) && cs.fixedNums.length > 0);
      ok.textContent = '确定';
      ok.classList.toggle('disabled', !hasType || !hasNum);
    };
    renderOk();
    ok.addEventListener('click', () => {
      if (!cs.type) { App.Components.toast('请选择一个题型', 'error'); return; }
      if (cs.mode === 'range' && (cs.rangeMin == null || cs.rangeMax == null)) { App.Components.toast('请设置数字范围', 'error'); return; }
      if (cs.mode === 'fixed' && !cs.fixedNums.length) { App.Components.toast('请选择至少一个固定数字', 'error'); return; }
      closeOverlay();
      if (onDone) onDone();
    });
    foot.appendChild(cancel);
    foot.appendChild(ok);
    sheet.appendChild(foot);

    overlay.appendChild(sheet);
    document.body.appendChild(overlay);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) closeOverlay(); });
  },

  // 自定义练习小窗：11 个题型多选 → 确定（不进入新页面）
  // v8.6.26 自定义练习 Sheet 弹窗（完整版：已选标签行 / 11 题型多选 / 数据特征 / 最近使用）
  // v8.6.33 双项配置：最上部「第一项 / 第二项」tab，各自独立编辑（题型+数据特征）
  showCustomPicker(onDone) {
    const self = this;
    if (!this.state.custom) this.resetCustomState();
    const cs = this.state.custom;
    if (!cs.items) this.resetCustomState();
    const presets = this.loadCustomPresets();
    let curKey = 'item1';
    const itemOf = (k) => {
      if (!cs.items[k]) cs.items[k] = { types: [], featureType: 'fixedFirst', fixedNum: 9, randMin: null, randMax: null };
      return cs.items[k];
    };
    let types = itemOf(curKey).types.slice();
    let featureType = itemOf(curKey).featureType || 'fixedFirst';
    let fixedNum = itemOf(curKey).fixedNum || 9;
    let randMin = itemOf(curKey).randMin, randMax = itemOf(curKey).randMax;
    const saveCur = () => {
      const it = itemOf(curKey);
      it.types = types.slice();
      it.featureType = featureType;
      it.fixedNum = fixedNum;
      it.randMin = randMin;
      it.randMax = randMax;
    };

    const overlay = document.createElement('div');
    overlay.className = 'notion-mobile-sheet-overlay';
    const sheet = document.createElement('div');
    sheet.className = 'notion-mobile-sheet is-format sc-picker-sheet';
    const handleBar = document.createElement('div');
    handleBar.className = 'notion-mobile-sheet__handle';
    sheet.appendChild(handleBar);
    const content = document.createElement('div');
    content.className = 'notion-mobile-sheet__content';

    // 标题
    const title = document.createElement('div');
    title.className = 'sc-picker-title';
    title.textContent = '自定义练习·选择题型（可多选）';
    content.appendChild(title);

    // v8.6.33 第一项 / 第二项 双配置 tab（各自独立编辑，切换前自动保存当前项）
    const tabRow = document.createElement('div');
    tabRow.className = 'sc-picker-tabs';
    const renderTabs = () => {
      tabRow.innerHTML = '';
      ['item1', 'item2'].forEach(k => {
        const tb = document.createElement('div');
        tb.className = 'sc-picker-tab' + (k === curKey ? ' selected' : '');
        tb.textContent = k === 'item1' ? '第一项' : '第二项';
        const cnt = itemOf(k).types.length;
        if (cnt > 0) tb.textContent += ' (' + cnt + ')';
        tb.addEventListener('click', () => {
          if (k === curKey) return;
          saveCur();
          curKey = k;
          types = itemOf(k).types.slice();
          featureType = itemOf(k).featureType || 'fixedFirst';
          fixedNum = itemOf(k).fixedNum || 9;
          randMin = itemOf(k).randMin;
          randMax = itemOf(k).randMax;
          renderTabs();
          renderSelRow();
          renderTypeGrid();
          renderFeat();
          renderOk();
        });
        tabRow.appendChild(tb);
      });
    };
    renderTabs();
    content.appendChild(tabRow);

    // ===== 已选标签行（动态，无已选项时隐藏）=====
    const selRow = document.createElement('div');
    selRow.className = 'sc-picker-selrow';
    const renderSelRow = () => {
      selRow.innerHTML = '';
      if (!types.length) { selRow.style.display = 'none'; return; }
      selRow.style.display = 'flex';
      types.forEach(key => {
        const pill = document.createElement('span');
        pill.className = 'sc-custom-selpill';
        pill.innerHTML = '<span>' + this.CUSTOM_TYPES[key].name + '</span><span class="sc-custom-selx">✕</span>';
        pill.querySelector('.sc-custom-selx').addEventListener('click', () => {
          types.splice(types.indexOf(key), 1);
          renderSelRow();
          renderTypeGrid();
          renderOk();
        });
        selRow.appendChild(pill);
      });
    };
    content.appendChild(selRow);

    // ===== 题型网格（3 列多选）=====
    const typeGrid = document.createElement('div');
    typeGrid.className = 'sc-custom-grid';
    const renderTypeGrid = () => {
      typeGrid.innerHTML = '';
      this.CUSTOM_ORDER.forEach(key => {
        const c = document.createElement('div');
        c.className = 'sc-custom-cell' + (types.includes(key) ? ' selected' : '');
        c.textContent = this.CUSTOM_TYPES[key].name;
        c.addEventListener('click', () => {
          if (types.includes(key)) types.splice(types.indexOf(key), 1);
          else types.push(key);
          renderTypeGrid();
          renderSelRow();
          renderOk();
        });
        typeGrid.appendChild(c);
      });
    };
    renderTypeGrid();
    content.appendChild(typeGrid);

    // ===== 数据特征 =====
    const featTitle = document.createElement('div');
    featTitle.className = 'sc-picker-feattitle';
    featTitle.innerHTML = '<span>数据特征</span><span class="sc-custom-clear">清空</span>';
    featTitle.querySelector('.sc-custom-clear').addEventListener('click', () => {
      featureType = 'fixedFirst';
      fixedNum = 9;
      randMin = null;
      randMax = null;
      renderFeat();
    });
    content.appendChild(featTitle);
    const featWrap = document.createElement('div');
    featWrap.className = 'sc-custom-feat';
    const renderFeat = () => {
      featWrap.innerHTML = '';
      const typeRow = document.createElement('div');
      typeRow.className = 'sc-custom-feat-types';
      [['fixedFirst', '固定首位'], ['randomRange', '随机范围']].forEach(pair => {
        const b = document.createElement('div');
        b.className = 'sc-custom-feat-type' + (featureType === pair[0] ? ' selected' : '');
        b.textContent = pair[1];
        b.addEventListener('click', () => { featureType = pair[0]; renderFeat(); });
        typeRow.appendChild(b);
      });
      featWrap.appendChild(typeRow);
      if (featureType === 'fixedFirst') {
        const numGrid = document.createElement('div');
        numGrid.className = 'sc-custom-numgrid';
        for (let i = 1; i <= 9; i++) {
          const n = document.createElement('div');
          n.className = 'sc-custom-num' + (fixedNum === i ? ' selected' : '');
          n.textContent = String(i);
          n.addEventListener('click', () => { fixedNum = i; renderFeat(); });
          numGrid.appendChild(n);
        }
        featWrap.appendChild(numGrid);
      } else {
        const rangeRow = document.createElement('div');
        rangeRow.className = 'sc-custom-range';
        const mkInput = (label, val, cb) => {
          const cell = document.createElement('div');
          cell.className = 'sc-custom-range-cell';
          const lb = document.createElement('span');
          lb.textContent = label;
          const inp = document.createElement('input');
          inp.type = 'number';
          inp.className = 'sc-custom-range-input';
          inp.value = val != null ? val : '';
          inp.addEventListener('change', () => cb(parseInt(inp.value, 10) || null));
          cell.appendChild(lb);
          cell.appendChild(inp);
          return cell;
        };
        rangeRow.appendChild(mkInput('最小值', randMin, (v) => { randMin = v; }));
        rangeRow.appendChild(mkInput('最大值', randMax, (v) => { randMax = v; }));
        featWrap.appendChild(rangeRow);
      }
    };
    renderFeat();
    content.appendChild(featWrap);

    // ===== 最近使用（4 列，点击填充配置，不关闭）=====
    const histTitle = document.createElement('div');
    histTitle.className = 'sc-picker-histtitle';
    histTitle.textContent = '最近使用';
    content.appendChild(histTitle);
    const histGrid = document.createElement('div');
    histGrid.className = 'sc-custom-hist';
    if (presets.history.length === 0) {
      const hint = document.createElement('div');
      hint.className = 'sc-custom-histempty';
      hint.textContent = '暂无历史，完成一次自定义练习后自动记录';
      histGrid.appendChild(hint);
    } else {
      presets.history.forEach(h => {
        const card = document.createElement('div');
        card.className = 'sc-custom-histcard';
        card.innerHTML = '<div class="sc-custom-histcard__name">' + (h.name || '') + '</div>' +
          '<div class="sc-custom-histcard__sub">' + (h.subName || '') + '</div>' +
          (h.number ? '<div class="sc-custom-histcard__num">' + h.number + '</div>' : '');
        card.addEventListener('click', () => {
          types.length = 0;
          if (Array.isArray(h.types) && h.types.length) h.types.forEach(t => types.push(t));
          featureType = h.featureType || 'fixedFirst';
          fixedNum = h.number || fixedNum;
          randMin = h.randomMin != null ? h.randomMin : null;
          randMax = h.randomMax != null ? h.randomMax : null;
          renderTypeGrid();
          renderSelRow();
          renderFeat();
          renderOk();
        });
        histGrid.appendChild(card);
      });
    }
    content.appendChild(histGrid);

    sheet.appendChild(content);

    // ===== 底部固定操作栏（sticky 于 Sheet 底部）=====
    const foot = document.createElement('div');
    foot.className = 'sc-picker-foot';
    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'sc-custom-footbtn sc-custom-footbtn--cancel';
    cancelBtn.textContent = '取消';
    cancelBtn.addEventListener('click', () => overlay.remove());
    const okBtn = document.createElement('button');
    okBtn.type = 'button';
    okBtn.className = 'sc-custom-footbtn sc-custom-footbtn--ok';
    const renderOk = () => {
      okBtn.textContent = '确定';
      okBtn.classList.toggle('disabled', types.length === 0);
    };
    renderOk();
    okBtn.addEventListener('click', () => {
      if (!types.length) { App.Components.toast('请至少选择一个题型', 'error'); return; }
      saveCur();
      const i1 = itemOf('item1'), i2 = itemOf('item2');
      const p = this.loadCustomPresets();
      p.lastUsed = {
        types: i1.types.slice(), featureType: i1.featureType, fixedNum: i1.fixedNum, randomMin: i1.randMin, randomMax: i1.randMax,
        item2Types: i2.types.slice(), item2FeatureType: i2.featureType, item2FixedNum: i2.fixedNum, item2RandomMin: i2.randMin, item2RandomMax: i2.randMax,
        settings: Object.assign({}, cs.settings)
      };
      this.saveCustomPresets(p);
      overlay.remove();
      if (onDone) onDone(types.slice());
    });
    foot.appendChild(cancelBtn);
    foot.appendChild(okBtn);
    sheet.appendChild(foot);

    overlay.appendChild(sheet);
    document.body.appendChild(overlay);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
  },

    CUSTOM_TYPES: {
    jinwei:   { name: '进位练习', gen: () => { const a = randInt(11, 88), lo = Math.max(10 - (a % 10), 1); const b = Math.floor(a / 10) * 10 + randInt(lo, 9); return makeQ(a + ' + ' + b, a + b); } },
    tuiwei:   { name: '退位练习', gen: () => { const t = randInt(2, 9), u = randInt(1, 8); const a = t * 10 + u, b = (t - 1) * 10 + (u + 1); return makeQ(a + ' - ' + b, a - b); } },
    jjMul:    { name: '九九乘法', gen: () => { const a = randInt(2, 9), b = randInt(2, 9); return makeQ(a + ' × ' + b, a * b); } },
    jjDiv:    { name: '九九除法', gen: () => { const d = randInt(2, 9), q = randInt(2, 9); return makeQ((d * q) + ' ÷ ' + d, q); } },
    addsub2c: { name: '两位数加减', gen: () => { const a = randInt(10, 99), b = randInt(10, 99); return Math.random() < 0.5 ? makeQ(a + ' + ' + b, a + b) : makeQ((a + b) + ' - ' + b, a); } },
    mul2x1c:  { name: '两位数乘一位数', gen: () => { const a = randInt(10, 99), b = randInt(2, 9); return makeQ(a + ' × ' + b, a * b); } },
    div3x1c:  { name: '三位数除一位数', gen: () => { const d = randInt(2, 9), n = randInt(100, 999); const a = Math.round(n / d * 100) / 100; return makeQ(n + ' ÷ ' + d, a); } },
    div5x3c:  { name: '五位数除三位数', gen: () => { const d = randInt(100, 999), n = randInt(10000, 99999); const a = Math.round(n / d * 100) / 100; return makeQ(n + ' ÷ ' + d, a); } },
    divRem:   { name: '除法取余', gen: () => { const d = randInt(3, 9), q = randInt(2, 9), r = randInt(1, d - 1), a = d * q + r; return makeQ(a + ' ÷ ' + d + ' 余?', r); } },
    mulHead:  { name: '乘法截首', gen: () => { const a = randInt(11, 99), b = randInt(3, 9), p = a * b, s = String(p), first = parseInt(s.charAt(0), 10); return makeQ(a + ' × ' + b + ' 首位?', first); } },
    mulEstc:  { name: '乘法估算', gen: () => { const a = randInt(11, 99), b = randInt(11, 99), ra = Math.round(a / 10) * 10, rb = Math.round(b / 10) * 10; return makeQ(a + ' × ' + b + ' ≈', ra * rb); } }
  },
  CUSTOM_ORDER: ['jinwei', 'tuiwei', 'jjMul', 'jjDiv', 'addsub2c', 'mul2x1c', 'div3x1c', 'div5x3c', 'divRem', 'mulHead', 'mulEstc'],

  // v8.15 数字设置应用（v8.15.29：数字设置只针对第二个操作数 B，不动第一个操作数 A）：
  //   二元表达式形如「A op B」，题型自带 A（如五位数被除数 34567），数字设置只调 B（除数/第二个数）。
  //   mode='range'  → 数字范围(001-999)：把表达式最后一个数字(B)替换为 range 内随机多位数，保留 A；
  //   mode='fixed'  → 固定数字(2-9 可多选)：把表达式最后一个数字(B)替换为从选中数字里随机取的一个数字。
  // 仅对纯四则运算表达式生效（含 ≈/余/首位 等语义的题型跳过，避免答案错位）；重算答案用简易求值器。
  _applyCustomFeature(q, feature) {
    let newExpr = null;
    const expr = String(q.expr);
    const isArith = /^[\d\s+\-×÷.]+$/.test(expr);
    if (!isArith) return q;
    if (feature && feature.mode === 'range' && feature.min != null && feature.max != null) {
      const lo = Math.max(1, Math.min(Math.round(feature.min), 999));
      const hi = Math.max(lo, Math.min(Math.round(feature.max), 999));
      newExpr = expr.replace(/\d+(?=\s*$)/, () => String(randInt(lo, hi)));
    } else if (feature && feature.mode === 'fixed' && Array.isArray(feature.nums) && feature.nums.length) {
      const nums = feature.nums.filter(n => n >= 1 && n <= 9);
      if (!nums.length) return q;
      const d = nums[randInt(0, nums.length - 1)];
      newExpr = expr.replace(/\d+(?=\s*$)/, () => String(d));
    } else if (feature && feature.type === 'fixedFirst' && feature.number) {
      newExpr = expr.replace(/\d+/g, (m) => String(feature.number) + m.slice(1));
    } else if (feature && feature.type === 'randomRange' && feature.min != null && feature.max != null) {
      newExpr = expr.replace(/^\d+/, () => String(randInt(feature.min, feature.max)));
    }
    if (newExpr === null || newExpr === expr) return q;
    const ans = this._evalArith(newExpr);
    if (ans === null) return q;
    return makeQ(newExpr, Math.round(ans * 100) / 100);
  },
  // 简易四则求值（×÷→*/，去空格，Function 求值；非法返回 null）
  _evalArith(expr) {
    const e = String(expr).replace(/×/g, '*').replace(/÷/g, '/').replace(/\s+/g, '');
    if (!e || !/^[0-9+\-*/.]+$/.test(e)) return null;
    try { const r = Function('"use strict"; return (' + e + ');')(); return (typeof r === 'number' && isFinite(r)) ? r : null; } catch (err) { return null; }
  },
  // 答案展示：整数原样，小数默认保留小数点后两位（v8.15）
  fmtAns(v) {
    const n = Number(v);
    if (!isFinite(n)) return String(v == null ? '' : v);
    return Number.isInteger(n) ? String(n) : n.toFixed(2);
  },

  // ===== 自定义配置持久化（kg_speed_custom_presets）=====
  CUSTOM_KEY: 'kg_speed_custom_presets',
  loadCustomPresets() {
    try {
      const d = JSON.parse(localStorage.getItem(this.CUSTOM_KEY)) || {};
      return { lastUsed: d.lastUsed || null, history: Array.isArray(d.history) ? d.history : [] };
    } catch (e) { return { lastUsed: null, history: [] }; }
  },
  saveCustomPresets(data) {
    try { localStorage.setItem(this.CUSTOM_KEY, JSON.stringify(data)); } catch (e) {}
  },
  resetCustomState() {
    const presets = this.loadCustomPresets();
    const last = presets.lastUsed || {};
    // v8.15 重构：单一题型单选 + 数字设置（数字范围 range / 固定数字 fixed 二选一），默认跟随全局设置
    const lastType = Array.isArray(last.types) && last.types.length ? last.types[0]
      : (typeof last.type === 'string' ? last.type : null);
    this.state.custom = {
      type: lastType,
      mode: (last.mode === 'range' || last.mode === 'fixed') ? last.mode : (last.featureType === 'randomRange' ? 'range' : 'fixed'),
      rangeMin: last.rangeMin != null ? last.rangeMin : (last.randomMin != null ? last.randomMin : 1),
      rangeMax: last.rangeMax != null ? last.rangeMax : (last.randomMax != null ? last.randomMax : 99),
      fixedNums: Array.isArray(last.fixedNums) ? last.fixedNums.slice() : (last.fixedNum != null ? [last.fixedNum] : []),
      settings: {}
    };
  },

  // ===== 视图：自定义练习配置页 =====
  renderCustom(container) {
    const self = this;
    if (!this.state.custom) this.resetCustomState();
    const cs = this.state.custom;
    const presets = this.loadCustomPresets();

    this._topbar(container, '自定义练习', () => this.show('home'));

    const body = document.createElement('div');
    body.className = 'sc-page sc-custom';
    body.style.cssText = 'padding-bottom:110px;';

    // ===== 2.1 顶部设置开关栏（横排 6 个 Switch）=====
    const swBar = document.createElement('div');
    swBar.className = 'sc-custom-swbar';
    [['confirmAuto', '确定'], ['useScreenKeyboard', '键盘'], ['sequential', '顺序'], ['nightMode', '夜间'], ['noNegative', '否'], ['quickMemo', '速记']].forEach(pair => {
      const key = pair[0], label = pair[1];
      const cell = document.createElement('div');
      cell.className = 'sc-custom-swcell';
      const sw = document.createElement('div');
      sw.className = 'sc-switch sc-switch--sm' + (cs.settings[key] ? ' is-on' : '');
      sw.innerHTML = '<span class="sc-switch__dot"></span>';
      sw.addEventListener('click', () => {
        sw.classList.toggle('is-on');
        cs.settings[key] = sw.classList.contains('is-on');
      });
      cell.appendChild(sw);
      const lb = document.createElement('div');
      lb.className = 'sc-custom-swlabel';
      lb.textContent = label;
      cell.appendChild(lb);
      swBar.appendChild(cell);
    });
    body.appendChild(swBar);

    // ===== 2.2 已选题型标签行 =====
    const selRow = document.createElement('div');
    selRow.className = 'sc-custom-selrow';
    const renderSelRow = () => {
      selRow.innerHTML = '';
      if (!cs.types.length) {
        const hint = document.createElement('span');
        hint.className = 'sc-custom-selhint';
        hint.textContent = '请下方选择题型';
        selRow.appendChild(hint);
        return;
      }
      cs.types.forEach(key => {
        const pill = document.createElement('span');
        pill.className = 'sc-custom-selpill';
        pill.innerHTML = '<span>' + this.CUSTOM_TYPES[key].name + '</span><span class="sc-custom-selx">✕</span>';
        pill.querySelector('.sc-custom-selx').addEventListener('click', (e) => {
          e.stopPropagation();
          cs.types = cs.types.filter(k => k !== key);
          renderSelRow();
          renderTypeGrid();
          renderOkBtn();
        });
        selRow.appendChild(pill);
      });
    };
    renderSelRow();
    body.appendChild(selRow);

    // ===== 2.3 题型选择（3 列网格，多选）=====
    const typeTitle = document.createElement('div');
    typeTitle.className = 'sc-custom-title';
    typeTitle.textContent = '题型选择';
    body.appendChild(typeTitle);
    const typeGrid = document.createElement('div');
    typeGrid.className = 'sc-custom-grid';
    const renderTypeGrid = () => {
      typeGrid.innerHTML = '';
      this.CUSTOM_ORDER.forEach(key => {
        const t = this.CUSTOM_TYPES[key];
        const card = document.createElement('div');
        card.className = 'sc-custom-cell' + (cs.types.includes(key) ? ' selected' : '');
        card.textContent = t.name;
        card.addEventListener('click', () => {
          if (cs.types.includes(key)) cs.types = cs.types.filter(k => k !== key);
          else cs.types.push(key);
          renderSelRow();
          renderTypeGrid();
          renderOkBtn();
        });
        typeGrid.appendChild(card);
      });
    };
    renderTypeGrid();
    body.appendChild(typeGrid);

    // ===== 2.4 数据特征 =====
    const featTitle = document.createElement('div');
    featTitle.className = 'sc-custom-title sc-custom-title--row';
    featTitle.innerHTML = '<span>数据特征</span><span class="sc-custom-clear">清空</span>';
    featTitle.querySelector('.sc-custom-clear').addEventListener('click', () => {
      cs.featureType = 'fixedFirst';
      cs.fixedNum = 9;
      cs.randMin = null;
      cs.randMax = null;
      renderFeat();
    });
    body.appendChild(featTitle);

    const featWrap = document.createElement('div');
    featWrap.className = 'sc-custom-feat';
    const renderFeat = () => {
      featWrap.innerHTML = '';
      // 特征类型单选
      const typeRow = document.createElement('div');
      typeRow.className = 'sc-custom-feat-types';
      [['fixedFirst', '固定首位'], ['randomRange', '随机范围']].forEach(pair => {
        const b = document.createElement('div');
        b.className = 'sc-custom-feat-type' + (cs.featureType === pair[0] ? ' selected' : '');
        b.textContent = pair[1];
        b.addEventListener('click', () => {
          cs.featureType = pair[0];
          renderFeat();
        });
        typeRow.appendChild(b);
      });
      featWrap.appendChild(typeRow);
      // 固定首位：1-9 单选
      if (cs.featureType === 'fixedFirst') {
        const numGrid = document.createElement('div');
        numGrid.className = 'sc-custom-numgrid';
        for (let i = 1; i <= 9; i++) {
          const n = document.createElement('div');
          n.className = 'sc-custom-num' + (cs.fixedNum === i ? ' selected' : '');
          n.textContent = String(i);
          n.addEventListener('click', () => {
            cs.fixedNum = i;
            renderFeat();
          });
          numGrid.appendChild(n);
        }
        featWrap.appendChild(numGrid);
      } else {
        // 随机范围（占位输入）
        const rangeRow = document.createElement('div');
        rangeRow.className = 'sc-custom-range';
        const mkInput = (label, val, cb) => {
          const cell = document.createElement('div');
          cell.className = 'sc-custom-range-cell';
          const lb = document.createElement('span');
          lb.textContent = label;
          const inp = document.createElement('input');
          inp.type = 'number';
          inp.className = 'sc-custom-range-input';
          inp.value = val != null ? val : '';
          inp.addEventListener('change', () => cb(parseInt(inp.value, 10) || null));
          cell.appendChild(lb);
          cell.appendChild(inp);
          return cell;
        };
        rangeRow.appendChild(mkInput('最小值', cs.randMin, (v) => { cs.randMin = v; }));
        rangeRow.appendChild(mkInput('最大值', cs.randMax, (v) => { cs.randMax = v; }));
        featWrap.appendChild(rangeRow);
      }
    };
    renderFeat();
    body.appendChild(featWrap);

    // ===== 2.5 最近使用（4 列网格）=====
    const histTitle = document.createElement('div');
    histTitle.className = 'sc-custom-title';
    histTitle.textContent = '最近使用';
    body.appendChild(histTitle);
    const histGrid = document.createElement('div');
    histGrid.className = 'sc-custom-hist';
    if (presets.history.length === 0) {
      const hint = document.createElement('div');
      hint.className = 'sc-custom-histempty';
      hint.textContent = '暂无历史，完成一次自定义练习后自动记录';
      histGrid.appendChild(hint);
    } else {
      presets.history.forEach(h => {
        const card = document.createElement('div');
        card.className = 'sc-custom-histcard';
        card.innerHTML = '<div class="sc-custom-histcard__name">' + h.name + '</div>' +
          '<div class="sc-custom-histcard__sub">' + (h.subName || '') + '</div>' +
          (h.number ? '<div class="sc-custom-histcard__num">' + h.number + '</div>' : '');
        card.addEventListener('click', () => {
          // 加载历史配置 → 进入做题页
          self.startCustomPractice(h);
        });
        histGrid.appendChild(card);
      });
    }
    body.appendChild(histGrid);

    container.appendChild(body);

    // ===== 2.6 底部固定操作栏 =====
    const foot = document.createElement('div');
    foot.className = 'sc-custom-foot';
    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'sc-custom-footbtn sc-custom-footbtn--cancel';
    cancelBtn.textContent = '取消';
    cancelBtn.addEventListener('click', () => this.show('home'));
    const okBtn = document.createElement('button');
    okBtn.type = 'button';
    okBtn.className = 'sc-custom-footbtn sc-custom-footbtn--ok';
    const renderOkBtn = () => {
      okBtn.textContent = '确定';
      okBtn.classList.toggle('disabled', cs.types.length === 0);
    };
    renderOkBtn();
    okBtn.addEventListener('click', () => {
      if (!cs.types.length) { App.Components.toast('请至少选择一个题型', 'error'); return; }
      this.startCustomPractice();
    });
    foot.appendChild(cancelBtn);
    foot.appendChild(okBtn);
    container.appendChild(foot);
  },

  // 开始自定义练习：保存配置 + 生成题目 + 进入做题页
  // hist（可选）：从最近使用历史进入时使用历史记录配置
  startCustomPractice(hist) {
    if (!this.state.custom) this.resetCustomState();
    const cs = this.state.custom;
    if (hist) {
      cs.type = (typeof hist.type === 'string' && this.CUSTOM_TYPES[hist.type] && this.CUSTOM_TYPES[hist.type].gen) ? hist.type
        : (Array.isArray(hist.types) && hist.types.length && this.CUSTOM_TYPES[hist.types[0]] && this.CUSTOM_TYPES[hist.types[0]].gen) ? hist.types[0]
        : null;
      cs.mode = (hist.mode === 'range' || hist.mode === 'fixed') ? hist.mode : 'fixed';
      cs.rangeMin = hist.rangeMin != null ? hist.rangeMin : 1;
      cs.rangeMax = hist.rangeMax != null ? hist.rangeMax : 99;
      cs.fixedNums = (Array.isArray(hist.fixedNums) ? hist.fixedNums : []).filter(n => n >= 2 && n <= 9);
    }
    const key = cs.type;
    const hasNum = cs.mode === 'range' ? (cs.rangeMin != null && cs.rangeMax != null) : (Array.isArray(cs.fixedNums) && cs.fixedNums.length > 0);
    if (!this.CUSTOM_TYPES[key] || !this.CUSTOM_TYPES[key].gen || !hasNum) { App.Components.toast('请先选择题型并设置数字', 'error'); return; }
    const settings = this.loadSettings();
    const count = settings.questionCount || 10;
    const mode = this.state.mode || 'train';
    this.state.type = 'custom';
    this.state.mode = mode;

    // 出题：用所选单选题型 gen，再按数字设置（数字范围 / 固定数字）套用数字规则。
    // v8.15.26 撤回白名单限制：数字设置对所有题型都生效（这是自定义练习的核心逻辑，调整被除数等数字）。
    this.state.questions = [];
    for (let i = 0; i < count; i++) {
      let q = this.CUSTOM_TYPES[key].gen();
      if (cs.mode === 'range' && cs.rangeMin != null && cs.rangeMax != null) {
        q = this._applyCustomFeature(q, { mode: 'range', min: cs.rangeMin, max: cs.rangeMax });
      } else if (cs.mode === 'fixed' && Array.isArray(cs.fixedNums) && cs.fixedNums.length) {
        q = this._applyCustomFeature(q, { mode: 'fixed', nums: cs.fixedNums });
      }
      q.user = '';
      q.correct = null;
      this.state.questions.push(q);
    }
    this.state.idx = 0;
    this.state.startTime = Date.now();
    this.state.qStart = Date.now();
    this.state.currentInput = '';
    this.state.doodleData = null;
    this.state.autoNextTimer = null;

    // 保存配置 + 历史（最多 12 条，新置顶）
    const presets = this.loadCustomPresets();
    const fixedLabel = cs.fixedNums.slice().sort((a, b) => a - b).join('、');
    const histItem = {
      id: Date.now(),
      type: key,
      mode: cs.mode,
      rangeMin: cs.mode === 'range' ? cs.rangeMin : null,
      rangeMax: cs.mode === 'range' ? cs.rangeMax : null,
      fixedNums: cs.mode === 'fixed' ? cs.fixedNums.slice() : null,
      name: this.CUSTOM_TYPES[key].name,
      subName: cs.mode === 'range' ? ('数字 ' + cs.rangeMin + '-' + cs.rangeMax) : (fixedLabel ? '固定 ' + fixedLabel : '固定数字'),
      date: new Date().toISOString().slice(0, 10)
    };
    presets.lastUsed = {
      type: key,
      mode: cs.mode,
      rangeMin: cs.rangeMin,
      rangeMax: cs.rangeMax,
      fixedNums: cs.fixedNums.slice(),
      settings: Object.assign({}, cs.settings)
    };
    presets.history = [histItem].concat(presets.history.filter(h => h.id !== histItem.id)).slice(0, 12);
    this.saveCustomPresets(presets);
    // v8.15.36 记录「上次激活 = 自定义练习」，下次进入默认选中自定义配置
    const _s = this.loadSettings();
    _s.lastActiveType = 'custom';
    this.saveSettings(_s);

    if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    this.show('practice');
  },

  // 开始练习：按设置题量生成并进入练习视图
  startPractice() {
    // v8.6.24 自定义练习：type='custom' 时走自定义生成（题型组合 + 数据特征）
    if (this.state.type === 'custom') { this.startCustomPractice(); return; }
    // v8.15 估算练习：走估算修正专项
    if (this.state.type === 'est05') { this.startEstimate(); return; }
    const settings = this.loadSettings();
    const count = settings.questionCount || 10;
    const gen = this.TYPES[this.state.type].gen;
    this.state.questions = [];
    for (let i = 0; i < count; i++) this.state.questions.push(gen());
    this.state.questions.forEach(q => { q.user = ''; q.correct = null; });
    this.state.idx = 0;
    this.state.startTime = Date.now();
    this.state.qStart = Date.now();
    this.state.currentInput = '';
    this.state.doodleData = null;
    this.state.autoNextTimer = null;
    if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    this.show('practice');
  },

  // ===== 视图：练习（强制屏幕数字键盘）=====
  renderPractice(container) {
    const self = this;
    const settings = this.loadSettings();
    const q = this.state.questions[this.state.idx];
    const total = this.state.questions.length;
    const isRace = this.state.mode === 'race';
    const submitted = q.correct !== null;
    const confirmAuto = settings.confirmAuto;
    this.state.currentInput = q.user && q.user !== '' ? String(q.user) : '';
    if (settings.nightMode) container.classList.add('sc-night');
    // v8.6.23 一屏布局：整页不滑动（顶栏/状态栏/题目区/键盘全部放一个屏幕内）
    // v8.15.24 补 min-height:0 —— CSS #page-speed-calc 有 min-height:100vh 会把 height 撑大。
    // v8.15.28 做题页已隐藏底部导航，直接用 100dvh 满屏 + numpad 自身 safe-bottom 兜底，键盘贴最底。
    container.style.cssText = 'height:100dvh;min-height:0;display:flex;flex-direction:column;overflow:hidden;box-sizing:border-box;';

    // v8.6.27 左上角退出按钮：弹出「继续练习 / 退出练习」两选项；v8.15.26 取消小眼睛按钮
    this._topbar(container, (this.state.type === "custom" ? "自定义练习" : this.TYPES[this.state.type].name), async () => {
      const go = await App.Components.confirm('退出练习', '当前练习进度将丢失，确定退出吗？', '退出', '继续', true);
      if (go) this.show('home');
    }, '', false, true);

    // ===== 状态栏：1/10  笔  重开  计时（100ms 刷新）；v8.15.26 重开按钮移到状态栏上侧 =====
    const statusBar = document.createElement('div');
    statusBar.className = 'sc-statusbar';
    statusBar.innerHTML =
      '<div class="sc-statusbar__pos">' + (this.state.idx + 1) + '/' + total + '</div>' +
      '<button class="sc-statusbar__pen" type="button" title="草稿涂鸦">✍️</button>' +
      '<button class="sc-statusbar__restart" type="button" title="重新开始">重开</button>' +
      '<div class="sc-statusbar__timer" id="sc-timer">0:00</div>';
    statusBar.querySelector('.sc-statusbar__pen').addEventListener('click', () => {
      App.Components.doodleOverlay({
        initial: self.state.doodleData || null,
        onChange: (dataURL) => { self.state.doodleData = dataURL || null; }
      });
    });
    statusBar.querySelector('.sc-statusbar__restart').addEventListener('click', async () => {
      const go = await App.Components.confirm('重新开始', '确定重新开始本轮练习？', '重开', '取消', true);
      if (go) self.startPractice();
    });
    container.appendChild(statusBar);
    const tick = () => {
      const el = container.querySelector('#sc-timer');
      if (el) el.textContent = fmtClock((Date.now() - this.state.startTime) / 1000);
    };
    tick();
    this.state.timerId = setInterval(tick, 100);

    // ===== 题目展示区（flex 居中，占满剩余空间）=====
    const body = document.createElement('div');
    body.className = 'sc-practice';
    body.style.cssText = 'flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:center;align-items:center;padding:12px 16px;';

    // v8.15.32 算式与答案同一行（flex 居中），输入变长时算式自动向左退让、整体保持居中
    const exprRow = document.createElement('div');
    exprRow.className = 'sc-practice__row';
    const expr = document.createElement('div');
    expr.className = 'sc-practice__expr';
    expr.textContent = q.expr;
    exprRow.appendChild(expr);
    // 等号连接符
    const eq = document.createElement('span');
    eq.className = 'sc-practice__eq';
    eq.textContent = ' =';
    exprRow.appendChild(eq);

    // 答案显示（div 模拟输入，禁止系统键盘）
    const answerDisplay = document.createElement('div');
    answerDisplay.className = 'sc-practice__answer';
    answerDisplay.textContent = this.state.showAns ? (this.state.currentInput || ' ') : '· · ·';
    exprRow.appendChild(answerDisplay);
    body.appendChild(exprRow);

    // 提交：立即下一题 + 弹出小对/错提示；每题用时只保留到结果页和历史记录
    const submit = () => {
      if (submitted) return;
      const val = parseFloat(self.state.currentInput);
      if (isNaN(val) || self.state.currentInput === '') { App.Components.toast('请输入答案', 'error'); return; }
      q.user = val;
      // v8.6.25 记录每题用时（做题页不显示，结果页表格展示）
      q.timeUsed = Math.round((Date.now() - self.state.qStart) / 100) / 10;
      // v8.15.34 全局误差 ±3%：|输入-答案| ≤ 3%×|答案|（兜底 0.011 绝对容差用于答案接近 0 的题）即算正确；
      //   同时记录误差百分比(保留1位小数)供结果页展示。
      const errAbs = Math.abs(val - q.answer);
      const errPct = Math.abs(q.answer) < 1e-9 ? (errAbs > 1e-9 ? 999 : 0) : (errAbs / Math.abs(q.answer)) * 100;
      q.correct = errAbs <= Math.max(0.011, Math.abs(q.answer) * 0.03);
      q.errPct = Math.round(errPct * 10) / 10;
      // v8.6.38 正确反馈：全屏淡青闪烁（inset box-shadow 覆盖）+ 顶部统计数字跳动
      if (q.correct) {
        const scBox = container;
        scBox.classList.remove('sc-flash-ok');
        void scBox.offsetWidth;
        scBox.classList.add('sc-flash-ok');
        container.querySelectorAll('.sc-statusbar__num, .sc-statusbar__pos').forEach(el => {
          el.classList.remove('sc-num-pop');
          void el.offsetWidth;
          el.classList.add('sc-num-pop');
        });
      }
      // 所有题型统一只反馈对错；每题用时仍保留在结果页和历史记录中。
      App.Components.toast(q.correct ? '✓' : '✗', q.correct ? 'success' : 'error');
      if (isRace) {
        self.next();
      } else {
        self.next();
      }
    };

    // ===== 强制屏幕数字键盘（div 模拟，底部固定不伸缩）=====
    const numpad = document.createElement('div');
    numpad.className = 'sc-numpad sc-numpad--v2';
    numpad.style.cssText = 'flex-shrink:0;';
    // v8.6.32 应用持久化的键盘尺寸（高度/宽度调节）
    if (settings.keyboardH) numpad.style.height = settings.keyboardH + 'px';
    if (settings.keyboardW) numpad.style.width = settings.keyboardW + '%';
    // v8.6.38 键盘布局：左侧 3×4 数字网格（浅灰底大圆角黑字）+ 右侧功能列（深绿底，✓ 双倍高提交键）
    const NUM_ROWS = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['+/-', '0', '.']
    ];
    const FUNC_KEYS = [
      { k: 'clear', label: 'C', cls: 'func' },
      { k: 'backspace', label: '⌫', cls: 'func' },
      { k: 'confirm', label: '✓', cls: 'confirm tall' }
    ];
    const kb = document.createElement('div');
    kb.className = 'sc-numpad__kb';
    const grid = document.createElement('div');
    grid.className = 'sc-numpad__grid';
    const funcCol = document.createElement('div');
    funcCol.className = 'sc-numpad__func';
    const press = (key) => {
      if (submitted) return;
      switch (key) {
        case 'clear': self.state.currentInput = self.state.currentInput.slice(0, -1); break;   // C = 删一个
        case 'backspace': self.state.currentInput = ''; break;                                   // ⌫ = 清空全部
        case 'confirm': submit(); return;
        case '+/-': {
          const s = self.state.currentInput;
          self.state.currentInput = s.startsWith('-') ? s.slice(1) : (s ? '-' + s : s);
          break;
        }
        case '.': if (!self.state.currentInput.includes('.')) self.state.currentInput += '.'; break;
        default:
          if (self.state.currentInput.length < 10) self.state.currentInput += key;
      }
      // v8.6.38 输入动画：数字弹入（scale 0.8→1）
      const disp = container.querySelector('.sc-practice__answer');
      if (disp) {
        disp.textContent = self.state.showAns ? (self.state.currentInput || ' ') : '· · ·';
        disp.classList.remove('sc-ans-pop');
        void disp.offsetWidth;
        disp.classList.add('sc-ans-pop');
      }
      // 确定开关 ON：答案位数为整数时位数与正确答案一致 → 自动提交（小数答案需手动按 ✓）
      if (confirmAuto && !submitted && Number.isInteger(q.answer) && !isNaN(parseFloat(self.state.currentInput)) && self.state.currentInput.length === String(q.answer).length) {
        submit();
      }
    };
    const mkBtn = (k, extraCls) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'sc-numpad__btn' + (k.cls ? ' sc-numpad__btn--' + k.cls : '') + (extraCls || '');
      b.textContent = k.label || k.k;
      b.addEventListener('click', () => press(k.k));
      // 按键音效保留；触感由全局 App.Haptics 统一触发。
      b.addEventListener('pointerdown', () => this._tapKeySound());
      return b;
    };
    NUM_ROWS.forEach(row => row.forEach(k => grid.appendChild(mkBtn({ k: k }))));
    FUNC_KEYS.forEach(fk => funcCol.appendChild(mkBtn(fk)));
    kb.appendChild(grid);
    kb.appendChild(funcCol);
    numpad.appendChild(kb);

    container.appendChild(body);
    container.appendChild(numpad);

    this.state.qStart = Date.now();
  },

  // 下一题 / 完成
  next() {
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    if (this.state.autoNextTimer) { clearTimeout(this.state.autoNextTimer); this.state.autoNextTimer = null; }
    if (this.state.idx >= this.state.questions.length - 1) {
      this.finish();
    } else {
      this.state.idx++;
      this.state.doodleData = null;
      this.render({});
    }
  },

  // 完成：统计 + 存历史（kg_speed_records）+ 结果页
  finish() {
    if (this.state.timerId) { clearInterval(this.state.timerId); this.state.timerId = null; }
    if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    if (this.state.autoNextTimer) { clearTimeout(this.state.autoNextTimer); this.state.autoNextTimer = null; }
    const qs = this.state.questions;
    const correct = qs.filter(q => q.correct === true).length;
    const totalTime = Math.round((Date.now() - this.state.startTime) / 100) / 10;
    const avgTime = qs.length ? Math.round(totalTime / qs.length * 10) / 10 : 0;
    const record = {
      id: 'sc_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      type: (this.state.type === "custom" ? "自定义练习" : this.TYPES[this.state.type].name),
      // v8.15.33 自定义练习存完整标题（题型 + 数字设置），历史页显示用
      name: this.state.type === 'custom' ? this._customLabel(this.state.custom) : null,
      mode: this.state.mode === 'race' ? '竞速模式' : '训练模式',
      count: qs.length,
      correct: correct,
      totalTime: totalTime,
      avgTime: avgTime,
      date: new Date().toISOString(),
      details: qs.map(q => ({ q: q.expr, user: q.user, correct: q.answer, isRight: q.correct === true, time: q.timeUsed || 0 }))
    };
    const list = this.loadHistory();
    list.unshift(record);
    this.saveHistory(list.slice(0, 200));
    this.show('result');
  },

  // ===== 视图：结果页 =====
  // ===== v8.6.25 视图：练习完成结果页（摘要 + 5 列表格 + 重来/复练/返回）=====
  renderResult(container) {
    const self = this;
    const qs = this.state.questions;
    const total = qs.length;
    const totalTime = Math.round((Date.now() - this.state.startTime) / 100) / 10;
    const typeName = (this.state.type === "custom" ? "自定义练习" : this.TYPES[this.state.type].name);
    const fmTotal = (sec) => { sec = Math.max(0, Math.round(sec || 0)); const m = Math.floor(sec / 60), s = sec % 60; return m + ':' + (s < 10 ? '0' : '') + s; };

    // v8.15.37 结果页：去掉 ⋯/👁，右上角换成 ✍️ 涂鸦按钮（复用错题本 doodleOverlay 涂鸦）
    this._topbar(container, typeName, () => this.show('home'),
      '<button class="sc-topbar__icon" type="button" id="sc-doodle" title="涂鸦">✍️</button>', true);
    const doodleBtn = container.querySelector('#sc-doodle');
    if (doodleBtn) {
      doodleBtn.addEventListener('click', () => {
        App.Components.doodleOverlay({
          initial: self.state.doodleData || null,
          onChange: (dataURL) => { self.state.doodleData = dataURL || null; }
        });
      });
    }

    const body = document.createElement('div');
    body.className = 'sc-page';
    body.style.cssText = 'padding-bottom:110px;';

    // v8.15.47 评级标准：从做题页移到结果页左上角（同款灰字）
    const std = document.createElement('div');
    std.className = 'sc-standard';
    const sT2 = this.state.type === 'custom' ? null : this.TYPES[this.state.type].s;
    std.textContent = '误差 ±3%   合格: ' + (sT2 ? sT2.pass : 28) + 's  良好: ' + (sT2 ? sT2.good : 22) + 's  优秀: ' + (sT2 ? sT2.excellent : 18) + 's';
    body.appendChild(std);

    // ===== 统计摘要区 =====
    const summary = document.createElement('div');
    summary.className = 'sc-result-summary';
    summary.innerHTML =
      '<div class="sc-result-summary__type">' + typeName + '</div>' +
      '<div class="sc-result-summary__time">本次练习用时:' + fmTotal(totalTime) + ' 加油</div>';
    body.appendChild(summary);

    // ===== 结果表格（题号/题目/正确答案/你的答案/误差/用时）=====
    const table = document.createElement('div');
    table.className = 'sc-result-table';
    const head = document.createElement('div');
    head.className = 'sc-result-table__head';
    head.innerHTML =
      '<div class="sc-rt-col">#</div>' +
      '<div class="sc-rt-col">题目</div>' +
      '<div class="sc-rt-col">正确答案</div>' +
      '<div class="sc-rt-col">你的答案</div>' +
      '<div class="sc-rt-col">误差</div>' +
      '<div class="sc-rt-col">用时</div>';
    table.appendChild(head);
    qs.forEach((q, i) => {
      const ua = q.user !== undefined && q.user !== '' ? q.user : '—';
      // v8.15.34 误差百分比(保留1位小数)；未作答显示 —
      const answered = q.user !== undefined && q.user !== '';
      const errCell = answered
        ? (q.errPct != null ? q.errPct.toFixed(1) + '%' : '—')
        : '—';
      const row = document.createElement('div');
      row.className = 'sc-result-table__row' + (q.correct ? '' : ' wrong');
      row.innerHTML =
        '<div class="sc-rt-col sc-rt-col--no">' + (i + 1) + '</div>' +
        '<div class="sc-rt-col sc-rt-col--q">' + q.expr + '</div>' +
        '<div class="sc-rt-col sc-rt-col--ans">= ' + self.fmtAns(q.answer) + '</div>' +
        '<div class="sc-rt-col sc-rt-col--user ' + (q.correct ? 'ok' : 'no') + '">' + ua + (q.correct ? '✓' : '✗') + '</div>' +
        '<div class="sc-rt-col sc-rt-col--err ' + (q.correct ? 'ok' : 'no') + '">' + errCell + '</div>' +
        '<div class="sc-rt-col sc-rt-col--t">' + (q.timeUsed || 0).toFixed(1) + 's</div>';
      table.appendChild(row);
    });
    body.appendChild(table);

    container.appendChild(body);

    // ===== 底部固定三按钮：重来 / 复练 / 返回 =====
    const foot = document.createElement('div');
    foot.className = 'sc-result-foot';
    const mkBtn = (label, cls, fn) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'sc-result-footbtn ' + cls;
      b.textContent = label;
      b.addEventListener('click', fn);
      return b;
    };
    foot.appendChild(mkBtn('重来', 'again', () => this.startPractice()));
    foot.appendChild(mkBtn('复练', 'retry', () => this.retryWrong()));
    foot.appendChild(mkBtn('返回', 'home', () => this.show('home')));
    container.appendChild(foot);
  },

  // 复练错题：仅保留做错的题目重新进入做题页（原题重做）
  retryWrong() {
    const wrong = this.state.questions.filter(q => q.correct !== true);
    if (!wrong.length) { App.Components.toast('本次全对，无需复练', 'info'); return; }
    this.state.questions = wrong.map(q => Object.assign({}, q, { user: '', correct: null, timeUsed: 0 }));
    this.state.idx = 0;
    this.state.startTime = Date.now();
    this.state.qStart = Date.now();
    this.state.currentInput = '';
    this.state.doodleData = null;
    this.state.autoNextTimer = null;
    if (this.state.raceTimerId) { clearInterval(this.state.raceTimerId); this.state.raceTimerId = null; }
    if (this.state.qTimerId) { clearInterval(this.state.qTimerId); this.state.qTimerId = null; }
    this.show('practice');
  },

  // v8.15.33 自定义练习显示标题：题型名 + 数字设置效果（如「自定义练习 五位数除三位数 450-850」）
  _customLabel(cs) {
    if (!cs) return '自定义练习';
    const sub = (cs.type && this.CUSTOM_TYPES[cs.type] && this.CUSTOM_TYPES[cs.type].name) ? this.CUSTOM_TYPES[cs.type].name : '';
    let num = '';
    if (cs.mode === 'range' && cs.rangeMin != null && cs.rangeMax != null) {
      num = cs.rangeMin + '-' + cs.rangeMax;
    } else if (cs.mode === 'fixed' && Array.isArray(cs.fixedNums) && cs.fixedNums.length) {
      num = '固定' + cs.fixedNums.slice().sort((a, b) => a - b).join('、');
    }
    return '自定义练习' + (sub ? ' ' + sub : '') + (num ? ' ' + num : '');
  },

  // v8.15.48 分段标题：自定义练习类标题 → { main:'自定义练习', sub:' 五位数除三位数 450-850' }
  //   历史记录胶囊标题 / 回看页摘要：main 保持原字号加粗，sub 缩小且不加粗；普通题型 sub 为空。
  _splitCustomTitle(name) {
    const s = String(name || '');
    if (s.indexOf('自定义练习') === 0 && s.length > 5) {
      return { main: '自定义练习', sub: s.slice(5) };
    }
    return { main: s, sub: '' };
  },

  // 题型/模式 → 图标符号（历史/统计页用）
  _scIcon(name) {
    const m = {
      '两位数加减':'±','三位数加法':'+','三位数减法':'−','三位数加减':'±',
      '两位数乘一位数':'×','三位数乘一位数':'×','三位数除一位数':'÷','五位数除三位数':'÷',
      '特殊分母练习':'%','零五十估算练习':'≈','基期练习':'📈','增量练习':'📊','资料分析实战':'📋',
      '自定义练习':'+','竞速':'⚡'
    };
    if (typeof name === 'string' && name.startsWith('自定义练习')) return '+';
    return m[name] || '•';
  },

  // v8.15.39 历史记录分组：
  //   1) 按具体日期降序分组（今天/昨天/M月D日）；
  //   2) 每个日期内部，按完成时间正序遍历，连续相同类型折叠为一个胶囊块；
  //      中途切换了类型再回来 → 拆成新的胶囊块（类型1→类型2→类型1 = 3 个块，类型1 出现两次）；
  //   3) 日期内的胶囊块按最近完成时间倒序（最新完成的块排最上面）。
  _groupHistory(list) {
    const now = new Date(); now.setHours(0, 0, 0, 0);
    const todayMs = now.getTime(), day = 86400000;
    const pad = (n) => (n < 10 ? '0' + n : '' + n);
    // 日期 → 友好标签：今天 / 昨天 / M月D日（更早）
    const labelOf = (ms) => {
      if (ms === todayMs) return '今天';
      if (ms === todayMs - day) return '昨天';
      const d = new Date(ms);
      return (d.getMonth() + 1) + '月' + d.getDate() + '日';
    };
    // 选项：题型显示名
    const tnameOf = (r) => (r.type === '自定义练习' && r.name) ? r.name
      : (r.type && r.type !== 'undefined' ? r.type : '速算练习');
    // 1) 按日期归集记录（保留每条时间戳供排序）
    const byDate = {};
    list.forEach((r) => {
      let d;
      try { d = new Date(r.date); } catch (e) { d = new Date(); }
      const ds = new Date(d); ds.setHours(0, 0, 0, 0);
      const keyMs = ds.getTime();
      if (!byDate[keyMs]) byDate[keyMs] = { keyMs: keyMs, label: labelOf(keyMs), records: [] };
      byDate[keyMs].records.push({ r: r, t: d.getTime() });
    });
    // 2) 日期降序；3) 日期内按时间正序 → 连续同类型折叠成块 → 块按最近完成倒序
    return Object.keys(byDate)
      .map((k) => Number(k))
      .sort((a, b) => b - a)
      .map((keyMs) => {
        const g = byDate[keyMs];
        const recs = g.records.slice().sort((a, b) => a.t - b.t);
        const blocks = [];
        recs.forEach(({ r }) => {
          const tname = tnameOf(r);
          const cc = r.correctCount !== undefined ? r.correctCount : (r.correct != null ? r.correct : 0);
          const tc = r.totalCount !== undefined ? r.totalCount : (r.count != null ? r.count : 0);
          const dur = r.duration !== undefined ? r.duration : (r.totalTime != null ? r.totalTime : 0);
          const last = blocks[blocks.length - 1];
          if (last && last.name === tname) {
            // 连续同类型：折叠进上一块
            last.countN++; last.correct += cc; last.total += tc; last.timeSum += dur;
            last.items.push({ date: r.date, correct: cc, total: tc, dur: dur, mode: r.mode, record: r });
          } else {
            // 类型切换（或首个）：新建一块
            blocks.push({
              name: tname, icon: this._scIcon(tname),
              countN: 1, correct: cc, total: tc, timeSum: dur,
              items: [{ date: r.date, correct: cc, total: tc, dur: dur, mode: r.mode, record: r }]
            });
          }
        });
        // v8.15.50 块内明细改为「最近的在最上面」：反转 items（原为正序：旧→新）
        blocks.forEach(b => b.items.reverse());
        // 最近完成的块排最上面
        blocks.reverse();
        return { key: String(keyMs), label: g.label, types: blocks };
      });
  },

  // ===== 视图：历史记录（设计稿：按时间分组 + 类型胶囊对比 + 点击展开明细）=====
  renderHistory(container) {
    const self = this;
    // v8.15.33 去掉右上角「⋯」「👁」，只保留返回
    this._topbar(container, '历史记录', () => this.show('home'), '', true);
    const body = document.createElement('div');
    body.className = 'sc-page sc-hist-page';

    const list = this.loadHistory();
    if (list.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'sc-empty';
      empty.textContent = '暂无练习记录，快去练一练吧';
      body.appendChild(empty);
    } else {
      const title = document.createElement('div');
      title.className = 'sc-hist-title';
      title.textContent = '按练习类型对比';
      body.appendChild(title);
      // 时间分组 + 类型胶囊
      const groups = this._groupHistory(list);
      groups.forEach((grp) => {
        const sec = document.createElement('div');
        sec.className = 'sc-hsec';
        const secTitle = document.createElement('div');
        secTitle.className = 'sc-hsec__title';
        secTitle.textContent = grp.label;
        sec.appendChild(secTitle);
        grp.types.forEach((T) => {
          const rate = T.total ? Math.round(T.correct / T.total * 100) : 0;
          const avgT = (T.countN ? T.timeSum / T.countN : 0);   // 单次平均用时(s)
          const wrap = document.createElement('div');
          wrap.className = 'sc-hcap-wrap';
          const cap = document.createElement('div');
          cap.className = 'sc-hcap';
          cap.setAttribute('role', 'button');
          // 标题行（固定在卡片顶部）
          const headRow = document.createElement('div');
          headRow.className = 'sc-hcap__row';
          // v8.15.48 自定义练习标题分段：main 原字号加粗，sub 缩小不加粗
          const titleParts = self._splitCustomTitle(T.name);
          headRow.innerHTML =
            '<div class="sc-hcap__icon">' + T.icon + '</div>' +
            '<div class="sc-hcap__info">' +
              '<div class="sc-hcap__name">' + esc(titleParts.main) +
                (titleParts.sub ? '<span class="sc-hcap__name-sub">' + esc(titleParts.sub) + '</span>' : '') +
              '</div>' +
              (T.countN > 1 ? '<div class="sc-hcap__sub">共 ' + T.countN + ' 次</div>' : '') +
            '</div>' +
            '<div class="sc-hcap__stat">' +
              '<div class="sc-hcap__rate" style="color:' + (rate >= 80 ? '#0066CC' : rate >= 60 ? '#EB8A3A' : '#E03131') + '">' + rate + '%</div>' +
              '<div class="sc-hcap__time">10题≈' + Math.round(avgT) + 's</div>' +
            '</div>' +
            '<div class="sc-hcap__arrow"><svg width="9" height="5" viewBox="0 0 9 5" fill="none"><path d="M1.5 1.2L4.5 4l3-2.8" stroke="#A1A1A6" stroke-width="1.6" stroke-linecap="round"/></svg></div>';
          cap.appendChild(headRow);
          // v8.15.40 每次记录明细：嵌入胶囊卡片内部（点击展开/收起），卡片整体统一样式
          // v8.15.47 每次记录行可点击 → 查看该次练习的完整结果（复用结果页样式，无底部按钮）
          const detail = document.createElement('div');
          detail.className = 'sc-hcap-detail';
          detail.style.display = 'none';
          T.items.forEach((it) => {
            const mini = document.createElement('div');
            mini.className = 'sc-hcap-detail__row sc-hcap-detail__row--link';
            const drate = it.total ? Math.round(it.correct / it.total * 100) : 0;
            mini.innerHTML =
              '<span class="sc-hcap-detail__t">' + fmtDate(it.date) + '</span>' +
              '<span class="sc-hcap-detail__c" style="color:' + (drate >= 80 ? '#0066CC' : drate >= 60 ? '#EB8A3A' : '#E03131') + '">正确 ' + (it.correct == null ? '-' : it.correct) + '/' + (it.total || 0) + '</span>' +
              '<span class="sc-hcap-detail__u">' + fmtClock(it.dur || 0) + '</span>' +
              '<span class="sc-hcap-detail__go">›</span>';
            // v8.15.47 点击明细行 → 历史回看该次练习（阻止冒泡，避免触发胶囊展开/收起）
            mini.addEventListener('click', (e) => {
              e.stopPropagation();
              self._viewHistoryRecord(it.record);
            });
            detail.appendChild(mini);
          });
          cap.appendChild(detail);
          cap.addEventListener('click', () => {
            const isOpen = detail.style.display !== 'none';
            detail.style.display = isOpen ? 'none' : 'block';
            cap.classList.toggle('open', !isOpen);
          });
          wrap.appendChild(cap);
          sec.appendChild(wrap);
        });
        body.appendChild(sec);
      });
    }

    const btnRow = document.createElement('div');
    btnRow.className = 'sc-btn-row';
    const backBtn = document.createElement('button');
    backBtn.type = 'button';
    backBtn.className = 'sc-btn sc-btn--outline';
    backBtn.textContent = '返回练习首页';
    backBtn.addEventListener('click', () => this.show('home'));
    btnRow.appendChild(backBtn);
    body.appendChild(btnRow);

    container.appendChild(body);
  },

  // v8.15.47 历史回看：点击某次记录 → 记住该 record 并进入回看视图（返回键回历史页）
  _viewHistoryRecord(record) {
    if (!record) { App.Components.toast('该记录数据缺失', 'error'); return; }
    this._historyViewing = record;
    this.show('historyDetail');
  },

  // v8.15.47 视图：历史单次练习回看（复用结果页样式：摘要 + 完整表格；无底部三按钮；返回键回历史页）
  renderHistoryDetail(container) {
    const self = this;
    const record = this._historyViewing;
    if (!record) { this.show('history'); return; }
    const fmTotal = (sec) => { sec = Math.max(0, Math.round(sec || 0)); const m = Math.floor(sec / 60), s = sec % 60; return m + ':' + (s < 10 ? '0' : '') + s; };
    const typeName = record.name || record.type || '速算练习';
    const details = Array.isArray(record.details) ? record.details : [];
    const totalTime = record.totalTime != null ? record.totalTime : (record.duration != null ? record.duration : 0);
    const correctCount = record.correctCount !== undefined ? record.correctCount : (record.correct != null ? record.correct : 0);
    const totalCount = record.totalCount !== undefined ? record.totalCount : (record.count != null ? record.count : 0);

    // 返回键回历史记录页（保持展开状态）；v8.15.48 右上角加 ✍️ 涂鸦（同结果页位置，独立涂鸦不关联做题数据）
    this._topbar(container, '练习回看', () => this.show('history'),
      '<button class="sc-topbar__icon" type="button" id="sc-doodle" title="涂鸦">✍️</button>', true);
    const doodleBtn = container.querySelector('#sc-doodle');
    if (doodleBtn) {
      doodleBtn.addEventListener('click', () => {
        App.Components.doodleOverlay({
          initial: null,
          onChange: () => {}
        });
      });
    }

    const body = document.createElement('div');
    body.className = 'sc-page';
    body.style.cssText = 'padding-bottom:24px;';

    // ===== 统计摘要区（与结果页一致；v8.15.48 不显示模式） =====
    const summary = document.createElement('div');
    summary.className = 'sc-result-summary';
    // v8.15.48 自定义练习标题分段：main 原字号加粗，sub 缩小不加粗
    const titleParts = this._splitCustomTitle(typeName);
    summary.innerHTML =
      '<div class="sc-result-summary__type">' + esc(titleParts.main) +
        (titleParts.sub ? '<span class="sc-result-summary__type-sub">' + esc(titleParts.sub) + '</span>' : '') +
      '</div>' +
      '<div class="sc-result-summary__time">本次练习用时:' + fmTotal(totalTime) + (totalCount ? (' · 正确 ' + correctCount + '/' + totalCount) : '') + '</div>';
    body.appendChild(summary);

    // ===== 题目明细表格（与结果页一致：题号/题目/正确答案/你的答案/误差/用时） =====
    if (details.length === 0) {
      // v8.15.47 旧记录无明细：仅展示统计摘要
      const empty = document.createElement('div');
      empty.style.cssText = 'text-align:center;color:var(--text-tertiary);font-size:13px;padding:28px 16px;';
      empty.textContent = '该条记录较早，未保存每道题明细，仅显示统计摘要';
      body.appendChild(empty);
    } else {
      const table = document.createElement('div');
      table.className = 'sc-result-table';
      const head = document.createElement('div');
      head.className = 'sc-result-table__head';
      head.innerHTML =
        '<div class="sc-rt-col">#</div>' +
        '<div class="sc-rt-col">题目</div>' +
        '<div class="sc-rt-col">正确答案</div>' +
        '<div class="sc-rt-col">你的答案</div>' +
        '<div class="sc-rt-col">误差</div>' +
        '<div class="sc-rt-col">用时</div>';
      table.appendChild(head);
      details.forEach((d, i) => {
        const isRight = d.isRight === true;
        const ua = d.user !== undefined && d.user !== '' ? d.user : '—';
        const answered = d.user !== undefined && d.user !== '';
        // 误差：优先用存储值，否则由 输入/答案 计算（保留1位小数）
        let errCell = '—';
        if (answered && d.correct != null) {
          const ans = parseFloat(d.correct);
          const uv = parseFloat(d.user);
          if (!isNaN(ans) && !isNaN(uv)) {
            const errAbs = Math.abs(uv - ans);
            const errPct = Math.abs(ans) < 1e-9 ? (errAbs > 1e-9 ? 999 : 0) : (errAbs / Math.abs(ans)) * 100;
            errCell = Math.round(errPct * 10) / 10 + '%';
          }
        }
        const row = document.createElement('div');
        row.className = 'sc-result-table__row' + (isRight ? '' : ' wrong');
        row.innerHTML =
          '<div class="sc-rt-col sc-rt-col--no">' + (i + 1) + '</div>' +
          '<div class="sc-rt-col sc-rt-col--q">' + esc(d.q) + '</div>' +
          '<div class="sc-rt-col sc-rt-col--ans">= ' + self.fmtAns(d.correct) + '</div>' +
          '<div class="sc-rt-col sc-rt-col--user ' + (isRight ? 'ok' : 'no') + '">' + esc(ua) + (isRight ? '✓' : '✗') + '</div>' +
          '<div class="sc-rt-col sc-rt-col--err ' + (isRight ? 'ok' : 'no') + '">' + errCell + '</div>' +
          '<div class="sc-rt-col sc-rt-col--t">' + (d.time || 0).toFixed(1) + 's</div>';
        table.appendChild(row);
      });
      body.appendChild(table);
    }

    container.appendChild(body);
  },

  // ===== 视图：速算统计（设计稿：热门类型 + 正确率趋势折线 + 用时分析条形）=====
  renderStats(container) {
    const self = this;
    this._topbar(container, '速算统计', () => this.show('home'));
    const body = document.createElement('div');
    body.className = 'sc-page sc-stats-page';

    const list = this.loadHistory();
    const byType = {};
    list.forEach((r) => {
      const tname = (r.type && r.type !== 'undefined' ? r.type : '速算练习');
      if (!byType[tname]) byType[tname] = { name: tname, icon: this._scIcon(tname), countN: 0, correct: 0, total: 0, timeSum: 0 };
      const T = byType[tname];
      const cc = r.correctCount !== undefined ? r.correctCount : (r.correct != null ? r.correct : 0);
      const tc = r.totalCount !== undefined ? r.totalCount : (r.count != null ? r.count : 0);
      const dur = r.duration !== undefined ? r.duration : (r.totalTime != null ? r.totalTime : 0);
      T.countN++; T.correct += cc; T.total += tc; T.timeSum += dur;
    });
    const types = Object.keys(byType).map((k) => byType[k]);
    const topType = types.slice().sort((a, b) => b.countN - a.countN)[0];

    // ===== 汇总卡：最近练习最多的类型 =====
    if (topType) {
      const rate = topType.total ? Math.round(topType.correct / topType.total * 100) : 0;
      const avgT10 = topType.countN ? Math.round(topType.timeSum / topType.countN) : 0;
      const hot = document.createElement('div');
      hot.className = 'sc-stats-hot';
      hot.innerHTML =
        '<div class="sc-stats-hot__label">最近练习最多</div>' +
        '<div class="sc-stats-hot__main">' +
          '<div class="sc-stats-hot__icon">' + topType.icon + '</div>' +
          '<div class="sc-stats-hot__name">' + esc(topType.name) + '</div>' +
        '</div>' +
        '<div class="sc-stats-hot__nums">' +
          '<div class="sc-stats-num"><span class="sc-stats-num__v">' + topType.countN + '</span><span class="sc-stats-num__l">练习次数</span></div>' +
          '<div class="sc-stats-num"><span class="sc-stats-num__v" style="color:#0066CC">' + rate + '%</span><span class="sc-stats-num__l">正确率</span></div>' +
          '<div class="sc-stats-num"><span class="sc-stats-num__v" style="color:#2E9E5B">' + avgT10 + 's</span><span class="sc-stats-num__l">10题用时</span></div>' +
        '</div>';
      body.appendChild(hot);
    }

    // ===== 正确率趋势卡：近7天折线 =====
    const days = [];
    for (let i = 6; i >= 0; i--) { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - i); days.push({ ms: d.getTime(), correct: 0, total: 0 }); }
    list.forEach((r) => {
      let d; try { d = new Date(r.date); } catch (e) { return; }
      const ds = new Date(d); ds.setHours(0, 0, 0, 0);
      const dayEl = days.find((x) => x.ms === ds.getTime());
      if (!dayEl) return;
      dayEl.correct += (r.correctCount !== undefined ? r.correctCount : (r.correct != null ? r.correct : 0));
      dayEl.total += (r.totalCount !== undefined ? r.totalCount : (r.count != null ? r.count : 0));
    });
    const labels = days.map((d) => { const dt = new Date(d.ms); return (dt.getMonth() + 1) + '/' + dt.getDate(); });
    const rates = days.map((d) => (d.total ? Math.round(d.correct / d.total * 100) : 0));
    // 折线坐标（viewBox 0 0 620 200）
    const VW = 620, padL = 46, padR = 14, padT = 16, padB = 28;
    const innerW = VW - padL - padR, chartH = 200 - padT - padB;
    const maxY = 100, minY = 40;
    const pts = rates.map((v, i) => {
      const x = padL + (rates.length > 1 ? innerW * i / (rates.length - 1) : innerW / 2);
      const y = padT + chartH * (1 - (v - minY) / (maxY - minY));
      return [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
    });
    const path = pts.map((p, i) => (i ? 'L' : 'M') + p[0] + ' ' + p[1]).join(' ');
    const trend = document.createElement('div');
    trend.className = 'sc-stats-card';
    trend.innerHTML =
      '<div class="sc-stats-card__head"><span class="sc-stats-card__title">正确率趋势</span><span class="sc-stats-card__hint">近7天</span></div>' +
      '<div class="sc-stats-card__chart">' +
        '<svg viewBox="0 0 620 200" width="100%" height="160" preserveAspectRatio="none">' +
          '<line x1="' + padL + '" y1="' + padT + '" x2="' + padL + '" y2="' + (200 - padB) + '" stroke="#EFEFF2"/>' +
          '<line x1="' + padL + '" y1="' + (200 - padB) + '" x2="' + (VW - padR) + '" y2="' + (200 - padB) + '" stroke="#EFEFF2"/>' +
          '<path d="' + path + '" stroke="#0066CC" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>' +
          pts.map((p) => '<circle cx="' + p[0] + '" cy="' + p[1] + '" r="3.5" fill="#0066CC"/>').join('') +
        '</svg>' +
        '<div class="sc-stats-card__x">' + labels.join('&nbsp;&nbsp;&nbsp;') + '</div>' +
      '</div>';
    body.appendChild(trend);

    // ===== 用时分析卡：各类型10题平均用时条形图（取前4）=====
    const top4 = types.slice().sort((a, b) => b.timeSum - a.timeSum).slice(0, 4);
    if (top4.length) {
      const tcard = document.createElement('div');
      tcard.className = 'sc-stats-card';
      const maxT = Math.max.apply(null, top4.map((t) => (t.countN ? t.timeSum / t.countN : 0)), 1);
      let barsHtml = '';
      top4.forEach((t) => {
        const avgT10 = t.countN ? Math.round(t.timeSum / t.countN) : 0;
        const w = t.countN ? Math.round((t.timeSum / t.countN) / maxT * 100) : 0;
        barsHtml +=
          '<div class="sc-stats-bar">' +
            '<span class="sc-stats-bar__lbl">' + esc(t.name) + '</span>' +
            '<span class="sc-stats-bar__track"><span class="sc-stats-bar__fill" style="width:' + Math.max(w, 6) + '%"></span></span>' +
            '<span class="sc-stats-bar__val">' + avgT10 + 's</span>' +
          '</div>';
      });
      tcard.innerHTML =
        '<div class="sc-stats-card__head"><span class="sc-stats-card__title">用时分析</span><span class="sc-stats-card__hint">10题用时</span></div>' +
        '<div class="sc-stats-bars">' + barsHtml + '</div>';
      body.appendChild(tcard);
    }

    container.appendChild(body);
  }
};
function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
function makeQ(expr, answer) {
  return { expr: expr, answer: answer, user: '', correct: null };
}
function fmtTime(sec) {
  sec = Math.max(0, sec || 0);
  var m = Math.floor(sec / 60);
  var s = sec % 60;
  return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
}
// v8.6.14 速算 100ms 计时显示格式（m:ss）
// v8.6.20 计时格式 M:SS:d（含十分位，100ms 刷新）
function fmtClock(sec) {
  sec = Math.max(0, sec || 0);
  var m = Math.floor(sec / 60);
  var s = Math.floor(sec % 60);
  var d = Math.floor((sec % 1) * 10);
  return m + ':' + (s < 10 ? '0' : '') + s + '.' + d;
}
function fmtDate(iso) {
  if (!iso) return '';
  var d = new Date(iso);
  var pad = function (n) { return (n < 10 ? '0' : '') + n; };
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}
function esc(str) {
  return String(str == null ? '' : str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
// 左滑显示删除按钮（滑动行，露出右侧删除钮；松开回弹/保持）
function bindSwipeDelete(row, listEl, onDelete) {
  var startX = 0, startY = 0, dx = 0, dragging = false;
  var DEL_W = 72;
  row.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) return;
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
    dragging = true;
    dx = 0;
    listEl.querySelectorAll('.sc-hist-row').forEach(function (r) {
      if (r !== row && r.classList.contains('open')) { r.classList.remove('open'); r.style.transform = ''; }
    });
  }, { passive: true });
  row.addEventListener('touchmove', function (e) {
    if (!dragging || e.touches.length !== 1) return;
    var x = e.touches[0].clientX;
    var y = e.touches[0].clientY;
    if (Math.abs(y - startY) > Math.abs(x - startX)) { dragging = false; return; }   // 纵向滚动不触发
    var cur = Math.min(0, Math.max(-DEL_W, x - startX + dx));
    row.style.transform = 'translateX(' + cur + 'px)';
    row.style.transition = 'none';
  }, { passive: true });
  row.addEventListener('touchend', function (e) {
    if (!dragging) return;
    dragging = false;
    var t = e.changedTouches[0].clientX - startX + dx;
    row.style.transition = 'transform 0.2s ease';
    if (t < -DEL_W / 2) {
      row.classList.add('open');
      row.style.transform = 'translateX(-' + DEL_W + 'px)';
      dx = -DEL_W;
    } else {
      row.classList.remove('open');
      row.style.transform = '';
      dx = 0;
    }
  }, { passive: true });
  var delBtn = row.querySelector('.sc-hist-del');
  if (delBtn) {
    delBtn.addEventListener('click', function () {
      onDelete();
    });
  }
}
