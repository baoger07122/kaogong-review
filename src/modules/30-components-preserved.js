// ===== 考公笔试复盘系统 - 可复用 UI 组件 =====
window.App = window.App || {};

// ===== Notion 移动端底部工具栏：单例（只构建一次，所有编辑器实例共享） =====
App.Components = {
  _mobileToolbarBuilt: false,        // 是否已构建
  _activeMobileEditor: null,         // 当前活动编辑器实例（动作分发目标）
  _mobileToolbarEl: null,            // 工具栏 DOM

  // ===== 全局滚动锁（弹窗打开时锁定背景滚动，关闭时恢复；支持嵌套计数） =====
  // 背景：错题本/笔记等页面的弹窗打开后，底部背景仍可被滑动（滚动穿透），导致滑不动弹窗反而滚背景。
  // 通过「计数器 + body/html 滚动锁 + 页面容器滚动锁」统一解决，供 confirm/prompt/actionSheet/
  // pickerModal/centeredPicker/doodleOverlay 等所有弹窗复用。
  _scrollLockCount: 0,
  _scrollLockPrev: null,
  _lockScroll() {
    this._scrollLockCount++;
    if (this._scrollLockCount === 1) {
      // 找到当前处于 overflow 滚动的页面容器一并锁定（如 .page 主容器）
      const pageEl = document.querySelector('.page') || document.body;
      this._scrollLockPrev = {
        body: document.body.style.overflow,
        html: document.documentElement.style.overflow,
        page: pageEl.style.overflow
      };
      document.body.style.overflow = 'hidden';
      document.documentElement.style.overflow = 'hidden';
      pageEl.style.overflow = 'hidden';
    }
  },
  _unlockScroll() {
    if (this._scrollLockCount > 0) this._scrollLockCount--;
    if (this._scrollLockCount === 0 && this._scrollLockPrev) {
      document.body.style.overflow = this._scrollLockPrev.body;
      document.documentElement.style.overflow = this._scrollLockPrev.html;
      try {
        const pageEl = document.querySelector('.page');
        if (pageEl) pageEl.style.overflow = this._scrollLockPrev.page;
      } catch (e) {}
      this._scrollLockPrev = null;
    }
  },

  // 注册当前活动编辑器（notionEditor 创建时调用）
  _registerMobileEditor(inst) { this._activeMobileEditor = inst; },

  // 移动端单例工具栏显隐：默认隐藏，仅块编辑器聚焦时显示（由 notionEditor focusin/focusout 联动）
  _showMobileToolbar() {
    const bar = this._mobileToolbarEl;
    if (bar) bar.classList.add('is-visible');
  },
  _hideMobileToolbar() {
    const bar = this._mobileToolbarEl;
    if (bar) bar.classList.remove('is-visible');
  },

  // 底部导航可见性（由路由切换通知）：笔记详情/编辑页隐藏导航时，工具栏收起位置贴底而不是悬浮导航上方
  _navVisible: true,
  _setNavVisible(visible) {
    this._navVisible = visible;
    const bar = this._mobileToolbarEl;
    if (!bar) return;
    let kb = 0;
    try {
      if (window.visualViewport && window.innerHeight > window.visualViewport.height) {
        kb = window.innerHeight - window.visualViewport.height;
      }
    } catch (e) {}
    if (kb > 0) return;   // 键盘弹出中，位置由 updateToolbarBottom 按 kb+16 处理
    if (visible) {
      try {
        const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--nav-height'));
        bar.style.bottom = ((isNaN(v) ? 56 : v) + 10) + 'px';
      } catch (e) { bar.style.bottom = '66px'; }
    } else {
      bar.style.bottom = '16px';   // 无底部导航：工具栏贴底悬浮
    }
  },

  // 构建底部工具栏 DOM（惰性单例）
  _ensureMobileToolbar() {
    if (this._mobileToolbarBuilt) return this._mobileToolbarEl;
    this._mobileToolbarBuilt = true;
    const NM_ICONS = {
      plus: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
      textAa: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7V4h16v3M9 20h6M12 4v16"/></svg>',
      voice: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 17v4"/></svg>',
      image: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>',
      redo: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 8a9 9 0 1 0 1 4"/><polyline points="21 3 21 8 16 8"/></svg>',
      undo: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8a9 9 0 1 1-1 4"/><polyline points="3 3 3 8 8 8"/></svg>',
      comment: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>',
      mention: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-4 8"/></svg>',
      trash: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6h14z"/></svg>',
      indent: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h13M3 12h13M3 18h13M20 8l-4 4 4 4"/></svg>',
      outdent: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M16 6h5M16 12h5M16 18h5M7 8l-4 4 4 4"/></svg>',
      moveUp: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>',
      moveDown: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12l7 7 7-7"/></svg>',
      more: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
      dismiss: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="4" y="4" width="16" height="11" rx="2"/><path d="M9 21h6M12 15v6M8 10l3 3 3-3"/></svg>',
      // v8.6.4 段落格式按钮（¶）：与文字格式（A）拆分为两个独立入口
      paragraph: '<span style="font-size:20px;font-weight:700;line-height:1">¶</span>',
    };
    const btns = [
      { key: 'insert', icon: 'plus', title: '插入块', label: '插入' },
      { key: 'format', icon: 'textAa', title: '文本格式', label: 'Aa' },
      { key: 'blockfmt', icon: 'paragraph', title: '段落格式', label: '¶' },   // v8.6.4 段落格式独立按钮
      { key: 'voice', icon: 'voice', title: '语音输入', label: '语音' },
      { key: 'image', icon: 'image', title: '图片', label: '图片' },
      { key: 'redo', icon: 'redo', title: '重做', label: '重做' },
      { key: 'undo', icon: 'undo', title: '撤销', label: '撤销' },
      { key: 'comment', icon: 'comment', title: '评论', label: '评论' },
      { key: 'mention', icon: 'mention', title: '提及', label: '提及' },
      { key: 'delete', icon: 'trash', title: '删除块', label: '删除' },
      { key: 'indent', icon: 'indent', title: '增加缩进', label: '缩进' },
      { key: 'outdent', icon: 'outdent', title: '减少缩进', label: '缩出' },
      { key: 'moveUp', icon: 'moveUp', title: '块上移', label: '上移' },
      { key: 'moveDown', icon: 'moveDown', title: '块下移', label: '下移' },
      { key: 'more', icon: 'more', title: '更多', label: '更多' },
      { key: 'dismiss', icon: 'dismiss', title: '收起键盘', label: '收起' },
    ];
    const el = document.createElement('div');
    el.className = 'notion-mobile-toolbar';
    el.setAttribute('data-mobile-toolbar', '1');
    const scroll = document.createElement('div');
    scroll.className = 'notion-mobile-toolbar__scroll';
    btns.forEach(x => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'notion-mobile-tool-btn';
      btn.dataset.key = x.key;
      btn.title = x.title;
      btn.innerHTML = NM_ICONS[x.icon];   // 纯图标，无文字标签
      btn.addEventListener('mousedown', (e) => e.preventDefault());
      btn.addEventListener('click', (e) => {
        e.preventDefault(); e.stopPropagation();
        const inst = App.Components._activeMobileEditor;
        if (inst && typeof inst._onMobileToolbar === 'function') inst._onMobileToolbar(x.key);
      });
      // 长按显示功能提示（500ms），提升纯图标工具栏的可发现性
      let pressTimer = null;
      btn.addEventListener('touchstart', () => {
        pressTimer = setTimeout(() => {
          if (App.Components.toast && x.title) App.Components.toast(x.title, 'info');
        }, 500);
      }, { passive: true });
      btn.addEventListener('touchend', () => clearTimeout(pressTimer), { passive: true });
      btn.addEventListener('touchmove', () => clearTimeout(pressTimer), { passive: true });
      btn.addEventListener('touchcancel', () => clearTimeout(pressTimer), { passive: true });
      scroll.appendChild(btn);
    });
    const mL = document.createElement('div');
    mL.className = 'notion-mobile-toolbar__mask left';
    const mR = document.createElement('div');
    mR.className = 'notion-mobile-toolbar__mask right';
    el.appendChild(mL); el.appendChild(scroll); el.appendChild(mR);
    document.body.appendChild(el);
    this._mobileToolbarEl = el;

    // ===== 软键盘适配（单例级，只注册一次） =====
    // iOS Safari 键盘弹出时 visualViewport 高度缩小，同时键盘上方还有系统「上一条/下一条/完成」透明条
    // 悬浮卡片：键盘弹出时 bottom = 键盘高度 + 16px（悬浮在键盘上方），收起时 bottom = safe-bottom + 16px
    const isMob = window.innerWidth <= 768 || ('ontouchstart' in window);
    let baseInnerH = window.innerHeight;   // 缓存基准视口高度（键盘弹出后 innerHeight 也可能变化）
    let kbRaf = null;
    const SAFE_BOTTOM = (() => {
      // 读取 CSS 变量 --safe-bottom（若有），否则默认 0
      try {
        const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--safe-bottom'));
        return isNaN(v) ? 0 : v;
      } catch (e) { return 0; }
    })();
    const NAV_H = (() => {
      // 底部主导航高度（--nav-height，默认 56px）：工具栏收起时悬浮在导航上方，不与导航重叠
      try {
        const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--nav-height'));
        return isNaN(v) ? 56 : v;
      } catch (e) { return 56; }
    })();
    const updateToolbarBottom = () => {
      const bar = App.Components._mobileToolbarEl;
      if (!bar || !isMob) return;
      let kb = 0;
      if (window.visualViewport) {
        const vv = window.visualViewport;
        // 键盘+系统工具条高度 = 基准视口高 - 当前可视高（含 Safari 透明条占位）
        kb = Math.max(0, baseInnerH - vv.height);
        // 兼容旧版 iOS：offsetTop 表示可视区相对页面的下移量，也计入
        if (vv.offsetTop > kb) kb = vv.offsetTop;
      }
      // 悬浮卡片：键盘弹出 bottom = kb+16（键盘上方）；收起时——若当前页面隐藏了底部导航则贴底 16px，否则悬浮导航上方
      const hideNav = App.Components._navVisible === false;
      bar.style.bottom = (kb > 0 ? kb + 16 : (hideNav ? SAFE_BOTTOM + 16 : NAV_H + SAFE_BOTTOM + 10)) + 'px';
      // 同时告知当前活动编辑器，让浮动格式栏也能适配
      const inst = App.Components._activeMobileEditor;
      if (inst && typeof inst._onKeyboardChange === 'function') inst._onKeyboardChange(kb);
    };
    const scheduleKb = () => {
      if (kbRaf) return;
      kbRaf = requestAnimationFrame(() => { kbRaf = null; updateToolbarBottom(); });
    };
    if (isMob && window.visualViewport) {
      window.visualViewport.addEventListener('resize', scheduleKb, { passive: true });
      window.visualViewport.addEventListener('scroll', scheduleKb, { passive: true });
    } else if (isMob) {
      let _lastH = window.innerHeight;
      window.addEventListener('resize', () => {
        const dh = Math.abs(window.innerHeight - _lastH);
        _lastH = window.innerHeight;
        if (dh > 150) { baseInnerH = window.innerHeight + dh; scheduleKb(); }
        else { baseInnerH = window.innerHeight; scheduleKb(); }
      }, { passive: true });
    }
    // 聚焦时也刷新一次（键盘弹出可能不触发 resize）
    window.addEventListener('focusin', scheduleKb, { passive: true });
    window.addEventListener('focusout', () => {
      // 键盘收起：恢复到底部
      if (kbRaf) cancelAnimationFrame(kbRaf);
      kbRaf = null;
      baseInnerH = window.innerHeight;
      updateToolbarBottom();
    }, { passive: true });

    this._mobileToolbarEl = el;
    // 初始化定位（悬浮间距 16px）
    updateToolbarBottom();

    // ===== iPad 横屏/分屏自适应检测（单例级） =====
    // 分屏检测（方向感知）：iPad 横屏 Split View 分屏沿「长边」方向压缩，最多占到 ~75%（25/75 档）；
    // 横屏全屏时 w ≈ 屏幕长边。用「w < 长边×0.92」判定横屏分屏，同时覆盖 50% 与 75%(2/3) 分屏且全屏不误判。
    // 竖屏全屏 w ≈ 短边、竖屏上下分屏宽度不变，故竖屏沿用「w < 短边-80」兜底（Slide Over/窄窗口）。
    const detectIpadSplit = () => {
      const isIpad = /iPad/.test(navigator.userAgent) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
      if (!isIpad) { document.body.classList.remove('ipad-split'); return; }
      const w = window.innerWidth;
      const h = window.innerHeight;
      const sw = (screen && screen.width) || 0;
      const sh = (screen && screen.height) || 0;
      let isSplit = false;
      if (sw > 0 && sh > 0) {
        const longEdge = Math.max(sw, sh);
        const shortEdge = Math.min(sw, sh);
        if (w > h) {
          // 横屏：分屏沿长边压缩，阈值取长边×0.92（覆盖 25/75 档、排除全屏）
          isSplit = w < longEdge * 0.92;
        } else {
          // 竖屏：宽度方向 = 短边，窄窗口/Slide Over 才压缩
          isSplit = w < shortEdge - 80;
        }
      } else {
        isSplit = w < 1024;   // screen 不可用时兜底
      }
      if (isSplit) document.body.classList.add('ipad-split');
      else document.body.classList.remove('ipad-split');
    };
    let _splitTimer = null;
    const scheduleSplitDetect = () => {
      clearTimeout(_splitTimer);
      _splitTimer = setTimeout(detectIpadSplit, 100);   // 防抖，iPad 分屏动画约 300ms
    };
    window.addEventListener('resize', scheduleSplitDetect, { passive: true });
    window.addEventListener('orientationchange', () => setTimeout(detectIpadSplit, 300), { passive: true });
    detectIpadSplit();

    return el;
  },

  // ===== 涂鸦板（支持 Apple Pencil / 触摸 / 鼠标） =====
  sketchPad(opts) {
    opts = opts || {};
    const wrap = document.createElement('div');
    wrap.className = 'sketch-pad';

    const titleEl = document.createElement('div');
    titleEl.className = 'sketch-pad__title';
    titleEl.textContent = '✍️ 手写笔记';
    wrap.appendChild(titleEl);

    const toolbar = document.createElement('div');
    toolbar.className = 'sketch-pad__toolbar';

    const penBtn = document.createElement('button');
    penBtn.type = 'button'; penBtn.className = 'sketch-tool is-active'; penBtn.title = '画笔';
    penBtn.innerHTML = '✏️';
    const eraserBtn = document.createElement('button');
    eraserBtn.type = 'button'; eraserBtn.className = 'sketch-tool'; eraserBtn.title = '橡皮';
    eraserBtn.innerHTML = '🧽';
    const undoBtn = document.createElement('button');
    undoBtn.type = 'button'; undoBtn.className = 'sketch-tool'; undoBtn.title = '撤回';
    undoBtn.innerHTML = '↶';
    const clearBtn = document.createElement('button');
    clearBtn.type = 'button'; clearBtn.className = 'sketch-tool sketch-tool--danger'; clearBtn.title = '清空';
    clearBtn.innerHTML = '🗑️';

    const colorWrap = document.createElement('div');
    colorWrap.className = 'sketch-pad__colors';
    const colors = [ {n:'黑', v:'#000000'}, {n:'红', v:'#e53935'}, {n:'蓝', v:'#1e88e5'}, {n:'绿', v:'#43a047'} ];
    let currentColor = colors[0].v;
    const colorDots = [];
    colors.forEach((c, i) => {
      const dot = document.createElement('button');
      dot.type = 'button'; dot.className = 'sketch-color' + (i === 0 ? ' is-active' : '');
      dot.style.background = c.v; dot.title = c.n + '色';
      dot.addEventListener('click', () => {
        currentColor = c.v; setMode('pen');
        colorDots.forEach(d => d.classList.remove('is-active'));
        dot.classList.add('is-active');
      });
      colorDots.push(dot); colorWrap.appendChild(dot);
    });

    const sizeWrap = document.createElement('div');
    sizeWrap.className = 'sketch-pad__sizes';
    // v8.5.4：画笔三档；默认使用上次选择的档位（localStorage 记忆，跨页面/跨会话），无记录时默认细
    // v8.15.1 笔档位：细2/中3/粗4（用户定），并取消双描边
    const penSizes = [ {n:'细', v:2}, {n:'中', v:3}, {n:'粗', v:4} ];
    const eraserSizes = [ {n:'细', v:36}, {n:'中', v:60}, {n:'粗', v:90} ];
    const readLastPenSize = () => {
      let v = NaN;
      try { v = parseFloat(window.localStorage.getItem('doodle_pen_size')); } catch (e) { /* 忽略 */ }
      return penSizes.some(s => s.v === v) ? v : penSizes[0].v;   // 校验档位，脏数据/无记录回退细
    };
    let currentPenSize = readLastPenSize();
    let currentEraserSize = eraserSizes[0].v;
    let currentSize = currentPenSize;
    const sizeBtns = [];
    penSizes.forEach((s) => {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'sketch-size' + (s.v === currentPenSize ? ' is-active' : '');
      b.title = s.n + '笔'; b.textContent = s.n;
      b.addEventListener('click', () => {
        if (mode === 'eraser') currentEraserSize = s.v;
        else { currentPenSize = s.v; try { window.localStorage.setItem('doodle_pen_size', String(s.v)); } catch (e) { /* 忽略 */ } }
        currentSize = s.v;
        sizeBtns.forEach(x => x.classList.remove('is-active'));
        b.classList.add('is-active');
      });
      sizeBtns.push(b); sizeWrap.appendChild(b);
    });

    // 手指涂鸦开关：默认关闭（仅 Pencil/鼠标），点击后允许手指绘制
    const touchBtn = document.createElement('button');
    touchBtn.type = 'button'; touchBtn.className = 'sketch-tool'; touchBtn.title = '手指涂鸦（默认仅 Pencil 可画）';
    touchBtn.innerHTML = '👆';
    touchBtn.addEventListener('click', () => {
      touchEnabled = !touchEnabled;
      touchBtn.classList.toggle('is-active', touchEnabled);
    });

    toolbar.appendChild(penBtn); toolbar.appendChild(eraserBtn);
    toolbar.appendChild(undoBtn); toolbar.appendChild(clearBtn);
    toolbar.appendChild(colorWrap); toolbar.appendChild(sizeWrap);
    toolbar.appendChild(touchBtn);
    wrap.appendChild(toolbar);

    const canvasWrap = document.createElement('div');
    canvasWrap.className = 'sketch-pad__canvas-wrap';
    const canvas = document.createElement('canvas');
    canvas.className = 'sketch-pad__canvas';
    canvasWrap.appendChild(canvas);
    const cursor = document.createElement('div');
    cursor.className = 'sketch-pad__cursor';
    canvasWrap.appendChild(cursor);
    wrap.appendChild(canvasWrap);

    const ctx = canvas.getContext('2d');
    let mode = 'pen';
    let drawing = false;
    let points = [];
    let undoStack = [];
    let redoStack = [];
    let initialized = false;
    let baseHasContent = false;
    let touchEnabled = false; // 手指涂鸦开关：默认关闭，仅 Pencil/鼠标可画
    const MAX_HISTORY = 30;

    // v8.15.12 坐标统一改用 CSS 像素（ctx 已 scale(dpr)），不再需要 scaleFactor
    function getPos(e) {
      // v8.15.12 坐标直接用 CSS 像素（ctx 已 scale(dpr)，坐标系是 CSS 像素）
      const rect = canvas.getBoundingClientRect();
      return {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
      };
    }
    function snapshot() { return canvas.toDataURL('image/png'); }
    // v8.15.18 适配：应用场景是「横屏分屏、只有宽度变、高度不变」，因此**只做宽度方向缩放、高度 1:1**，
    // 且内容**左对齐（顶部对齐）**而非居中。这样宽度切换时内容不会等比缩放（等比会让高度也变、位置漂移），
    // 只在水平方向伸拉，垂直方向与位置保持稳定。
    function drawContain(img) {
      const cw = canvas.width / dprCache;    // 当前画布 CSS 宽
      const ch = canvas.height / dprCache;   // 当前画布 CSS 高
      // naturalWidth/Height 是物理像素（snapshot 用 toDataURL 导出），需 /dprCache 转成 CSS 像素
      const iw = (img.naturalWidth || img.width) / dprCache;
      const ih = (img.naturalHeight || img.height) / dprCache;
      if (iw <= 0 || ih <= 0) return;
      // 只做宽度缩放：宽度填满当前画布，高度保持原图 CSS 高度（1:1，不缩放）→ 高度不变、内容不变形
      ctx.clearRect(0, 0, cw, ch);
      // 左对齐 + 顶部对齐，保证宽度变化时内容位置稳定不漂移
      ctx.drawImage(img, 0, 0, cw, ih);
    }
    function restore(dataURL) {
      const img = new Image();
      img.onload = () => {
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.scale(dprCache, dprCache);
        drawContain(img);
      };
      img.src = dataURL;
    }
    function applySize() {
      const rect = canvas.getBoundingClientRect();
      // v8.15.11 布局未完成时跳过，避免 canvas 被设成极小尺寸后拉伸放大 → 满屏锯齿
      if (rect.width < 2 || rect.height < 2) return;
      const dpr = window.devicePixelRatio || 1;
      dprCache = dpr;
      const w = Math.max(2, Math.round(rect.width * dpr));
      const h = Math.max(2, Math.round(rect.height * dpr));
      if (w === canvas.width && h === canvas.height) return;
      const prev = initialized ? snapshot() : null;
      canvas.width = w; canvas.height = h;
      // v8.15.12 关键修复：ctx.scale(dpr) 让绘制坐标系回到 CSS 像素，
      // 消除「坐标×sf 与 lineWidth×sf 的非整数亚像素误差」——这正是 iPad 上线条边缘毛糙(锯齿)的根因。
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      if (prev) restore(prev);
    }
    function isEmpty() {
      return undoStack.length <= 1 && !baseHasContent;
    }
    function setMode(m) {
      mode = m;
      penBtn.classList.toggle('is-active', m === 'pen');
      eraserBtn.classList.toggle('is-active', m === 'eraser');
      if (m !== 'eraser') hideCursor();
      // v8.6.41 切回画笔重置压力（防橡皮擦后首笔残留异常）
      if (m === 'pen') lastPressure = 0.5;
      // 切换模式时同步 currentSize 并高亮对应按钮
      currentSize = (m === 'eraser') ? currentEraserSize : currentPenSize;
      const list = (m === 'eraser') ? eraserSizes : penSizes;
      sizeBtns.forEach((b, i) => {
        b.classList.toggle('is-active', list[i] && list[i].v === currentSize);
      });
    }
    function commit() {
      if (opts.onChange) opts.onChange(!isEmpty() ? snapshot() : null);
    }
    function pushHistory() {
      undoStack.push(snapshot());
      if (undoStack.length > MAX_HISTORY) undoStack.shift();
      redoStack = []; // 新动作后清空 redo
    }

    // 橡皮擦光标圈
    function showCursor() { cursor.style.display = 'block'; }
    function hideCursor() { cursor.style.display = 'none'; }
    function moveCursor(pos, radius) {
      // v8.15.12 pos 已是 CSS 像素，直接用于定位
      cursor.style.left = pos.x + 'px';
      cursor.style.top = pos.y + 'px';
      cursor.style.width = (radius * 2) + 'px';
      cursor.style.height = (radius * 2) + 'px';
    }

    // 画笔：采样去重 + 远距离插值 + One Euro 平滑 + 二次贝塞尔（中点法）+ 整笔连续 path 单次 stroke
    let lastX = 0, lastY = 0;
    let lastPressure = 0.5;
    let dprCache = 1;   // v8.15.12 缓存 devicePixelRatio，applySize 时更新
    // v8.15.12 恒宽画笔：线宽直接 = 逻辑档位（CSS 像素），ctx 已 scale(dpr) 由 GPU 负责映射到物理像素，
    // 消除「坐标×sf 与线宽×sf 各自取整不一致」导致的非整数亚像素 → iPad 线条边缘毛糙(锯齿)。
    function penWidth() {
      return Math.max(1, currentPenSize);
    }

    // 起笔前的画布快照（整笔重绘时用它同步恢复，避免叠加）
    let strokeBase = null;         // ImageData 快照

    // v8.15.15 终局简化：彻底移除 One Euro 滤波与复杂插值。
    // 回退原因：v8.15.14「插值点不滤波」后，dist>14 的快速移动产生直线折线段破坏曲线平滑(锯齿)，
    // 且与滤波/阈值组合交互脆弱，反复「画线锯齿 + 字不完整」。
    // 正确做法：采样点最简去重后直接进 points，靠「ctx.scale(dpr)」保证清晰(锯齿已根治)，
    // 靠「二次贝塞尔中点法」保证平滑，靠「不滤波不丢点」保证笔画完整与跟手。
    // 中间恢复(bug 已反复验证)：整笔一条连续 path 单次 stroke + putImageData 同步快照恢复。
    function drawSmoothStroke(newPos) {
      const lastPt = points.length ? points[points.length - 1] : null;
      if (lastPt) {
        const dx = newPos.x - lastPt.x;
        const dy = newPos.y - lastPt.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        // 仅做最小距离去重（<1px 的微小抖动跳过），不做任何滤波/插值
        if (dist < 1.0) return;
      }
      points.push({ x: newPos.x, y: newPos.y });
      renderStroke();
    }

    // 同步恢复起笔前快照 + 重画「完整当前一笔」（一条连续 path，仅 stroke 一次）
    function renderStroke() {
      const w = penWidth();

      // 1. 同步恢复起笔前快照
      if (strokeBase) {
        ctx.putImageData(strokeBase, 0, 0);
      } else {
        ctx.clearRect(0, 0, canvas.width / dprCache, canvas.height / dprCache);
      }

      // 2. 整笔一条连续 path（坐标为 CSS 像素，ctx 已 scale(dpr)）
      ctx.globalCompositeOperation = 'source-over';
      ctx.strokeStyle = currentColor;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.globalAlpha = 1;
      ctx.lineWidth = Math.max(1, w);

      if (points.length === 1) {
        const p0 = points[0];
        ctx.beginPath();
        ctx.arc(p0.x, p0.y, w / 2, 0, Math.PI * 2);
        ctx.fillStyle = currentColor;
        ctx.fill();
        return;
      }

      // 二次贝塞尔中点法：一条 path 从头画到尾，中间绝无接缝
      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);
      for (let i = 1; i < points.length - 1; i++) {
        const p = points[i];
        const nx = points[i + 1].x, ny = points[i + 1].y;
        const midX = (p.x + nx) / 2;
        const midY = (p.y + ny) / 2;
        ctx.quadraticCurveTo(p.x, p.y, midX, midY);
      }
      // 末段：连到最后一点（round cap 会让笔尾自然圆润收尾）
      const last = points[points.length - 1];
      ctx.lineTo(last.x, last.y);
      ctx.stroke();
    }

    // 橡皮擦：直接在主 canvas 上用 destination-out 擦除
    function eraseStroke(from, to) {
      const w = currentEraserSize;
      ctx.globalCompositeOperation = 'destination-out';
      ctx.strokeStyle = 'rgba(0,0,0,1)';
      ctx.lineWidth = Math.max(1, w);
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();
      ctx.globalCompositeOperation = 'source-over';
    }

    penBtn.addEventListener('click', () => setMode('pen'));
    eraserBtn.addEventListener('click', () => setMode('eraser'));
    undoBtn.addEventListener('click', () => {
      if (undoStack.length > 1) {
        redoStack.push(undoStack.pop());
        restore(undoStack[undoStack.length - 1]);
        commit();
      }
    });
    clearBtn.addEventListener('click', () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      undoStack = [ snapshot() ];
      redoStack = [];
      baseHasContent = false;
      commit();
    });

    canvas.addEventListener('pointerdown', (e) => {
      // 手指涂鸦默认关闭（仅 Pencil/鼠标可画）；开启手指开关后允许手指绘制
      if (e.pointerType === 'touch' && !touchEnabled) return;
      e.preventDefault();
      drawing = true;
      try { canvas.setPointerCapture(e.pointerId); } catch (_) {}
      const pos = getPos(e);
      // 起笔：记录落点，保存「起笔前快照」用于整笔重绘时同步恢复
      points = [ { x: pos.x, y: pos.y } ];
      lastX = pos.x; lastY = pos.y;
      strokeBase = ctx.getImageData(0, 0, canvas.width, canvas.height);   // 同步快照
      if (mode === 'eraser') {
        const r = currentEraserSize / 2;
        moveCursor(pos, r);
        showCursor();
      } else {
        // 起笔落墨：画一个点
        renderStroke();
      }
    });
    canvas.addEventListener('pointermove', (e) => {
      if (!drawing) return;
      e.preventDefault();
      const pos = getPos(e);
      if (mode === 'eraser') {
        const r = currentEraserSize / 2;
        moveCursor(pos, r);
        eraseStroke(points[points.length - 1], pos);
        points = [ pos ];
      } else {
        drawSmoothStroke(pos);
      }
    });
    function endDraw(e) {
      if (!drawing) return;
      drawing = false;
      hideCursor();
      try { canvas.releasePointerCapture(e.pointerId); } catch (_) {}
      points = [];
      strokeBase = null;
      lastPressure = 0.5;
      pushHistory();
      commit();
    }
    canvas.addEventListener('pointerup', endDraw);
    canvas.addEventListener('pointercancel', endDraw);
    canvas.addEventListener('contextmenu', (e) => { e.preventDefault(); return false; });

    function init() {
      applySize();
      // v8.15.11 布局兜底：多次重试 applySize，直到 canvas 尺寸正确（>2px）或有初始内容。
      // 之前若 init 时 rect=0，applySize 直接跳过，canvas 保持默认/极小尺寸被 CSS 拉伸 → 满屏锯齿。
      let retries = 0;
      const retrySize = () => {
        if (canvas.width >= 2 && canvas.height >= 2) return;
        applySize();
        if (++retries < 20) setTimeout(retrySize, 30);
      };
      retrySize();
      if (opts.initial) {
        const img = new Image();
        img.onload = () => {
          applySize();
          // v8.15.17 等比居中适配（不变形），解决分屏改变宽度后重新打开内容被拉伸/错位
          drawContain(img);
          undoStack = [ snapshot() ];
          redoStack = [];
          baseHasContent = true;
          initialized = true;
        };
        img.src = opts.initial;
      } else {
        undoStack = [ snapshot() ];
        redoStack = [];
        baseHasContent = false;
        initialized = true;
      }
    }
    if (window.ResizeObserver) {
      const ro = new ResizeObserver(() => { applySize(); });
      ro.observe(canvasWrap);
    } else {
      window.addEventListener('resize', () => { applySize(); });
    }
    requestAnimationFrame(() => requestAnimationFrame(init));

    return {
      element: wrap,
      getImage: () => (undoStack.length > 1 || baseHasContent ? snapshot() : null),
      loadImage: (dataURL) => {
        if (!dataURL) return;
        const img = new Image();
        img.onload = () => {
          // v8.15.17 等比居中适配
          drawContain(img);
          undoStack = [ snapshot() ];
          redoStack = [];
          baseHasContent = true;
        };
        img.src = dataURL;
      },
      clear: () => { ctx.clearRect(0, 0, canvas.width / dprCache, canvas.height / dprCache); undoStack = [ snapshot() ]; redoStack = []; baseHasContent = false; },
      undo: () => { if (undoStack.length > 1) { redoStack.push(undoStack.pop()); restore(undoStack[undoStack.length - 1]); } },
      redo: () => { if (redoStack.length > 0) { undoStack.push(redoStack.pop()); restore(undoStack[undoStack.length - 1]); } },
      setMode: (m) => setMode(m),
      setColor: (c) => { currentColor = c; },
      setTouchEnabled: (v) => { touchEnabled = !!v; if (touchBtn) touchBtn.classList.toggle('is-active', touchEnabled); },
      getTouchEnabled: () => touchEnabled,
      setSize: (s) => {
        if (mode === 'eraser') currentEraserSize = s;
        else currentPenSize = s;
        currentSize = s;
      },
      getMode: () => mode,
      getPenSizes: () => penSizes,
      getEraserSizes: () => eraserSizes,
      getCurrentSize: () => currentSize,
      isEmpty: () => undoStack.length <= 1 && !baseHasContent,
      _relayout: () => { if (initialized) applySize(); }
    };
  },
  // ===== 半透明涂鸦覆盖层（铅笔图标打开，底部工具栏滑上） =====
  doodleOverlay(opts) {
    opts = opts || {};
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');
      if (!container) { resolve(null); return; }

      const overlay = document.createElement('div');
      overlay.className = 'doodle-overlay';

      // 滚动锁：全屏涂鸦层打开时锁定背景；关闭时恢复
      App.Components._lockScroll();

      // 顶部栏：左上角退出，右上角工具
      const bar = document.createElement('div');
      bar.className = 'doodle-overlay__bar';
      const closeBtn = document.createElement('button');
      closeBtn.className = 'doodle-overlay__close';
      closeBtn.type = 'button';
      closeBtn.innerHTML = '✕';
      closeBtn.title = '退出';
      const tools = document.createElement('div');
      tools.className = 'doodle-overlay__tools';
      const ICONS = {
        eraser: '<svg viewBox="0 0 24 24"><path d="M20 20H7L3 16C2 15 2 13 3 12L13 2L22 11L12 21C11 22 9 22 8 21L4 17"/></svg>',
        undo: '<svg viewBox="0 0 24 24"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9H3"/></svg>',
        redo: '<svg viewBox="0 0 24 24"><path d="M21 7v6h-6"/><path d="M3 17a9 9 0 0 1 9-9h9"/></svg>',
        trash: '<svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>',
        touch: '<svg viewBox="0 0 24 24"><path d="M18 11V6a2 2 0 0 0-4 0v5"/><path d="M14 10V4a2 2 0 0 0-4 0v6"/><path d="M10 10.5V6a2 2 0 0 0-4 0v8"/><path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15"/></svg>'
      };
      function makeTool(iconHtml, title) {
        const b = document.createElement('button');
        b.type = 'button'; b.className = 'doodle-overlay__tool'; b.innerHTML = iconHtml; b.title = title;
        return b;
      }
      const eraserBtn = makeTool(ICONS.eraser, '橡皮擦');
      const undoBtn = makeTool(ICONS.undo, '撤销');
      const redoBtn = makeTool(ICONS.redo, '恢复');
      const clearBtn = makeTool(ICONS.trash, '清空');
      // 画笔调节图标：颜色 + 粗细收进此处，点击才展开底部面板
      const brushBtn = makeTool('<svg viewBox="0 0 24 24"><path d="M12 19l7-7 3 3-7 7-3-3z"/><path d="M18 13l-1.5-7.5L2 2l3.5 14.5L13 18l5-5z"/><circle cx="11" cy="11" r="2"/></svg>', '画笔颜色与粗细');
      // 手指涂鸦开关：默认关闭（仅 Pencil/鼠标可画），开启后允许手指绘制
      const touchBtn = makeTool(ICONS.touch, '手指涂鸦');
      // 退出按钮放在右上角工具栏最左侧，避免与 iPad 分屏状态/应用三点菜单冲突
      tools.appendChild(closeBtn);
      tools.appendChild(eraserBtn);
      tools.appendChild(undoBtn);
      tools.appendChild(redoBtn);
      tools.appendChild(clearBtn);
      tools.appendChild(brushBtn);
      tools.appendChild(touchBtn);
      bar.appendChild(tools);

      // 画板（透明背景，铺在整页上方）
      const pad = App.Components.sketchPad({ initial: opts.initial || null, onChange: opts.onChange });
      pad.element.classList.add('sketch-pad--overlay');
      // 手指涂鸦开关：默认关闭，开启后允许手指绘制
      touchBtn.addEventListener('click', () => {
        const v = !pad.getTouchEnabled();
        pad.setTouchEnabled(v);
        touchBtn.classList.toggle('is-active', v);
      });

      // 底部工具栏（从底部滑上）：颜色 + 笔触大小
      const sheet = document.createElement('div');
      sheet.className = 'doodle-overlay__sheet';
      const colors = [ {n:'黑', v:'#000000'}, {n:'红', v:'#e53935'}, {n:'蓝', v:'#1e88e5'}, {n:'绿', v:'#43a047'} ];
      let activeColor = colors[0].v;
      const colorWrap = document.createElement('div');
      colorWrap.className = 'doodle-overlay__colors';
      const colorDots = [];
      colors.forEach((c, i) => {
        const dot = document.createElement('button');
        dot.type = 'button'; dot.className = 'doodle-overlay__color' + (i === 0 ? ' is-active' : '');
        dot.style.background = c.v; dot.title = c.n + '色';
        dot.addEventListener('click', () => {
          activeColor = c.v; pad.setColor(c.v); pad.setMode('pen');
          colorDots.forEach(d => d.classList.remove('is-active'));
          dot.classList.add('is-active');
          eraserBtn.classList.remove('is-active');
          renderSizeBtns();
        });
        colorDots.push(dot); colorWrap.appendChild(dot);
      });
      // v8.5.4：画笔三档 2.6/2.8/3.0；与 sketch 共用 localStorage key 记忆上次档位，无记录默认细
      const penSizes = [ {n:'细', v:2}, {n:'中', v:3}, {n:'粗', v:4} ];
      const eraserSizes = [ {n:'细', v:36}, {n:'中', v:60}, {n:'粗', v:90} ];
      let lastPenSize = NaN;
      try { lastPenSize = parseFloat(window.localStorage.getItem('doodle_pen_size')); } catch (e) { /* 忽略 */ }
      if (!penSizes.some(s => s.v === lastPenSize)) lastPenSize = penSizes[0].v;
      let activePenSize = lastPenSize;
      let activeEraserSize = eraserSizes[0].v;
      const sizeWrap = document.createElement('div');
      sizeWrap.className = 'doodle-overlay__sizes';
      const sizeBtns = [];
      function renderSizeBtns() {
        const isEraser = pad.getMode() === 'eraser';
        const list = isEraser ? eraserSizes : penSizes;
        const active = isEraser ? activeEraserSize : activePenSize;
        sizeWrap.innerHTML = '';
        sizeBtns.length = 0;
        list.forEach((s, i) => {
          const b = document.createElement('button');
          b.type = 'button'; b.className = 'doodle-overlay__size' + (s.v === active ? ' is-active' : '');
          b.textContent = s.n; b.title = s.n + (isEraser ? '橡皮' : '笔');
          b.addEventListener('click', () => {
            if (isEraser) activeEraserSize = s.v;
            else { activePenSize = s.v; try { window.localStorage.setItem('doodle_pen_size', String(s.v)); } catch (e) { /* 忽略 */ } }
            pad.setSize(s.v);
            renderSizeBtns();
          });
          sizeBtns.push(b); sizeWrap.appendChild(b);
        });
      }
      renderSizeBtns();
      sheet.appendChild(colorWrap);
      sheet.appendChild(sizeWrap);

      overlay.appendChild(pad.element);
      overlay.appendChild(bar);
      overlay.appendChild(sheet);

      // 默认收起；点击画笔图标展开/收起底部调节面板
      let sheetOpen = false;
      brushBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        sheetOpen = !sheetOpen;
        sheet.classList.toggle('is-open', sheetOpen);
        brushBtn.classList.toggle('is-active', sheetOpen);
      });

      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        App.Components._unlockScroll();
        if (overlay.parentNode) overlay.remove();
        let img = null;
        try { img = pad.getImage(); } catch (e) { img = null; }
        resolve(img);
      };

      closeBtn.addEventListener('click', finish);
      eraserBtn.addEventListener('click', () => {
        // 橡皮按钮 toggle：再次点击切回画笔
        if (pad.getMode() === 'eraser') {
          pad.setMode('pen');
          eraserBtn.classList.remove('is-active');
          // 恢复画笔颜色高亮
          const cIdx = colors.findIndex(c => c.v === activeColor);
          colorDots.forEach((d, i) => d.classList.toggle('is-active', i === cIdx));
          renderSizeBtns();
        } else {
          pad.setMode('eraser');
          eraserBtn.classList.add('is-active');
          colorDots.forEach(d => d.classList.remove('is-active'));
          renderSizeBtns();
        }
      });
      undoBtn.addEventListener('click', () => pad.undo());
      redoBtn.addEventListener('click', () => pad.redo());
      clearBtn.addEventListener('click', () => pad.clear());

      container.appendChild(overlay);
      requestAnimationFrame(() => { if (pad._relayout) pad._relayout(); });
    });
  },
  // ===== 待办备注底部面板（平滑滑入，不重新渲染页面） =====
  todoNoteSheet(todo, opts) {
    opts = opts || {};
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');
      if (!container) { resolve(null); return; }

      const overlay = document.createElement('div');
      overlay.className = 'todo-note-sheet';
      overlay.innerHTML = `
        <div class='todo-note-sheet__backdrop'></div>
        <div class='todo-note-sheet__panel'>
          <div class='todo-note-sheet__header'>
            <div class='todo-note-sheet__title'>备注</div>
            <button class='todo-note-sheet__close' type='button'>完成</button>
          </div>
          <textarea class='todo-note-sheet__note' placeholder='添加备注...'></textarea>
          <div class='todo-note-sheet__actions'>
            <button class='todo-note-sheet__btn todo-note-sheet__btn--secondary todo-note-sheet__close' type='button'>完成</button>
            <button class='todo-note-sheet__btn todo-note-sheet__btn--danger todo-note-sheet__delete' type='button'>删除待办</button>
          </div>
        </div>
      `;

      const noteArea = overlay.querySelector('.todo-note-sheet__note');
      noteArea.value = todo.note || '';

      const closeSheet = (result) => {
        overlay.classList.remove('is-visible');
        setTimeout(() => {
          if (overlay.parentNode) overlay.remove();
          resolve(result);
        }, 280);
      };

      const saveNote = async () => {
        const note = noteArea.value.trim();
        if (note !== (todo.note || '')) {
          todo.note = note;
          await App.DB.updateTodo(todo);
        }
      };

      overlay.querySelectorAll('.todo-note-sheet__close').forEach(btn => {
        btn.addEventListener('click', async () => {
          await saveNote();
          closeSheet({ action: 'save', note: noteArea.value.trim() });
        });
      });

      overlay.querySelector('.todo-note-sheet__delete').addEventListener('click', async () => {
        const ok = await App.Components.confirm('删除待办', '确定删除这项待办？', '删除', '取消', true);
        if (!ok) return;
        await App.DB.remove('todos', todo.id);
        App.Components.toast('已删除', 'success');
        closeSheet({ action: 'delete' });
      });

      overlay.querySelector('.todo-note-sheet__backdrop').addEventListener('click', async () => {
        await saveNote();
        closeSheet({ action: 'save', note: noteArea.value.trim() });
      });

      noteArea.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
          saveNote().then(() => closeSheet({ action: 'save', note: noteArea.value.trim() }));
        }
      });

      container.appendChild(overlay);
      requestAnimationFrame(() => {
        overlay.classList.add('is-visible');
        noteArea.focus();
      });
    });
  },
  // ===== Toast 提示 =====
  toast(message, type) {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = 'toast' + (type ? ' toast--' + type : '');
    toast.textContent = message;
    container.appendChild(toast);

    setTimeout(() => {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 2500);
  },

  // ===== 确认对话框 =====
  confirm(title, message, confirmText, cancelText, isDanger) {
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');
      const overlay = document.createElement('div');
      overlay.className = 'modal-overlay';

      overlay.innerHTML = `
        <div class="modal-dialog">
          <div class="modal-dialog__header">
            <div class="modal-dialog__title">${title}</div>
          </div>
          <div class="modal-dialog__body">${message}</div>
          <div class="modal-dialog__actions">
            <button class="btn-cancel">${cancelText || '取消'}</button>
            <button class="${isDanger ? 'btn-danger' : 'btn-confirm'}">${confirmText || '确认'}</button>
          </div>
        </div>
      `;

      // 滚动锁：弹窗打开锁定背景，关闭/取消/确认时恢复
      App.Components._lockScroll();
      const closeOverlay = () => { App.Components._unlockScroll(); overlay.remove(); };

      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) {
          closeOverlay();
          resolve(false);
        }
      });

      overlay.querySelector('.btn-cancel').addEventListener('click', () => {
        closeOverlay();
        resolve(false);
      });

      overlay.querySelector(isDanger ? '.btn-danger' : '.btn-confirm').addEventListener('click', () => {
        closeOverlay();
        resolve(true);
      });

      container.appendChild(overlay);
    });
  },

  // ===== 文本输入弹窗（返回输入的字符串；取消返回 null）=====
  prompt(title, message, placeholder, confirmText) {
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');
      const overlay = document.createElement('div');
      overlay.className = 'modal-overlay';

      overlay.innerHTML = `
        <div class="modal-dialog">
          <div class="modal-dialog__header">
            <div class="modal-dialog__title">${title}</div>
          </div>
          <div class="modal-dialog__body">${message}</div>
          <div class="modal-dialog__input">
            <input type="text" placeholder="${placeholder || '请输入...'}" value="">
          </div>
          <div class="modal-dialog__actions">
            <button class="btn-cancel">取消</button>
            <button class="btn-confirm">${confirmText || '确认'}</button>
          </div>
        </div>
      `;

      const input = overlay.querySelector('.modal-dialog__input input');
      const confirmBtn = overlay.querySelector('.btn-confirm');
      const cancelBtn = overlay.querySelector('.btn-cancel');
      // 滚动锁
      App.Components._lockScroll();
      const finish = (val) => { App.Components._unlockScroll(); overlay.remove(); resolve(val); };
      const submit = () => { const v = input.value.trim(); if (v) finish(v); };
      setTimeout(() => { input.focus(); }, 0);
      overlay.addEventListener('click', (e) => { if (e.target === overlay) finish(null); });
      cancelBtn.addEventListener('click', () => finish(null));
      confirmBtn.addEventListener('click', submit);
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); e.stopPropagation(); });

      container.appendChild(overlay);
    });
  },

  // ===== 标签长按菜单：修改名称 / 删除标签（删除会同步清理所有引用）=====
  openTagMenu(opts) {
    // opts: { kind: 'kp'|'ec', module, name, onDone }
    const container = document.getElementById('modal-container');
    const overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.4);z-index:1200;display:flex;align-items:flex-end;justify-content:center;';
    const panel = document.createElement('div');
    panel.style.cssText = 'width:100%;max-width:520px;background:var(--bg-primary);border-radius:16px 16px 0 0;padding:16px;box-sizing:border-box;';
    const title = document.createElement('div');
    title.style.cssText = 'font-size:var(--font-md);font-weight:600;margin-bottom:12px;color:var(--text-primary);';
    title.textContent = (opts.kind === 'kp' ? '考点标签：' : '错因标签：') + opts.name;
    panel.appendChild(title);

    // 扁平科目（资料分析）：操作同步到该科目所有模块
    const flatSub = App.Constants.isFlatSubject(opts.module);
    const mods = flatSub ? App.Constants.getModules(opts.module) : [opts.module];

    const moveUpBtn = document.createElement('button');
    moveUpBtn.className = 'btn btn--outline btn--full';
    moveUpBtn.style.marginBottom = '8px';
    moveUpBtn.textContent = '⬆️ 上移';
    const moveDownBtn = document.createElement('button');
    moveDownBtn.className = 'btn btn--outline btn--full';
    moveDownBtn.style.marginBottom = '8px';
    moveDownBtn.textContent = '⬇️ 下移';
    const renameBtn = document.createElement('button');
    renameBtn.className = 'btn btn--outline btn--full';
    renameBtn.style.marginBottom = '8px';
    renameBtn.textContent = '✏️ 修改名称';
    const delBtn = document.createElement('button');
    delBtn.className = 'btn btn--danger btn--full';
    delBtn.style.marginBottom = '8px';
    delBtn.textContent = '🗑 删除标签';
    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'btn btn--ghost btn--full';
    cancelBtn.textContent = '取消';

    panel.appendChild(moveUpBtn);
    panel.appendChild(moveDownBtn);
    panel.appendChild(renameBtn);
    panel.appendChild(delBtn);
    panel.appendChild(cancelBtn);
    overlay.appendChild(panel);
    container.appendChild(overlay);

    const close = () => overlay.remove();
    overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
    cancelBtn.addEventListener('click', close);

    const doMove = async (dir) => {
      overlay.remove();
      if (opts.kind === 'kp') for (const m of mods) await App.Tags.moveKnowledgePoint(m, opts.name, dir);
      else for (const m of mods) await App.Tags.moveModuleErrorCause(m, opts.name, dir);
      App.Components.toast('已排序', 'success');
      if (opts.onDone) opts.onDone();
    };
    moveUpBtn.addEventListener('click', () => doMove(-1));
    moveDownBtn.addEventListener('click', () => doMove(1));

    renameBtn.addEventListener('click', async () => {
      overlay.remove();
      const nv = window.prompt('修改名称为：', opts.name);
      if (nv && nv.trim() && nv.trim() !== opts.name) {
        if (opts.kind === 'kp') for (const m of mods) await App.Tags.renameKnowledgePoint(m, opts.name, nv.trim());
        else for (const m of mods) await App.Tags.renameModuleErrorCause(m, opts.name, nv.trim());
        App.Components.toast('已修改', 'success');
        if (opts.onDone) opts.onDone();
      }
    });
    delBtn.addEventListener('click', async () => {
      overlay.remove();
      const ok = await App.Components.confirm(
        '删除标签',
        `确定删除标签「${opts.name}」？该标签会从所有相关错题 / 笔记中一并移除。`,
        '删除', '取消', true
      );
      if (ok) {
        if (opts.kind === 'kp') for (const m of mods) await App.Tags.purgeKnowledgePoint(m, opts.name);
        else for (const m of mods) await App.Tags.purgeModuleErrorCause(m, opts.name);
        App.Components.toast('已删除', 'success');
        if (opts.onDone) opts.onDone();
      }
    });
  },

  // 通用长按（移动端 500ms 长按 / 桌面右键），触发后抑制后续点击
  bindLongPress(el, cb) {
    let timer = null;
    let suppressClick = false;
    const trigger = (e) => {
      if (e) { e.preventDefault(); e.stopPropagation(); }
      suppressClick = true;
      setTimeout(() => { suppressClick = false; }, 500);
      cb();
    };
    el.addEventListener('touchstart', () => { timer = setTimeout(trigger, 500); }, { passive: true });
    el.addEventListener('touchend', () => clearTimeout(timer));
    el.addEventListener('touchmove', () => clearTimeout(timer));
    el.addEventListener('contextmenu', trigger);
    el.addEventListener('click', (e) => { if (suppressClick) { e.preventDefault(); e.stopPropagation(); } });
    el.style.cursor = 'pointer';
  },

  // 给标签元素绑定长按：打开标签菜单（修改 / 排序 / 删除）
  bindTagLongPress(el, kind, module, name, onDone) {
    App.Components.bindLongPress(el, () => {
      App.Components.openTagMenu({ kind, module, name, onDone });
    });
  },

  // ===== 空状态 =====
  emptyState(icon, title, desc, actionText, actionCallback) {
    const el = document.createElement('div');
    el.className = 'empty-state';
    el.innerHTML = `
      <div class="empty-state__icon">${icon || '📭'}</div>
      <div class="empty-state__title">${title || '暂无数据'}</div>
      ${desc ? `<div class="empty-state__desc">${desc}</div>` : ''}
    `;

    if (actionText && actionCallback) {
      const btn = document.createElement('button');
      btn.className = 'empty-state__action';
      btn.textContent = actionText;
      btn.addEventListener('click', actionCallback);
      el.appendChild(btn);
    }

    return el;
  },

  // ===== 科目选择网格 =====
  subjectGrid(selected, onChange, columns, dataCallback) {
    const container = document.createElement('div');
    container.className = 'subject-grid' + (columns === 2 ? ' subject-grid--2col' : '');

    App.Constants.SUBJECTS.forEach(subj => {
      const item = document.createElement('div');
      item.className = 'subject-grid-item';
      if (selected === subj.name) item.classList.add('selected');

      const count = dataCallback ? dataCallback(subj.name) : '';

      item.innerHTML = `
        <div class="subject-grid-item__icon">${subj.icon}</div>
        <div class="subject-grid-item__name">${subj.name}</div>
        ${count !== '' ? `<div class="subject-grid-item__count">${count}</div>` : ''}
      `;

      item.style.borderColor = selected === subj.name ? subj.color : 'transparent';
      item.addEventListener('click', () => onChange(subj.name));
      container.appendChild(item);
    });

    return container;
  },


  // ===== 标签下拉选择器（替代横向 filterTags）=====
  // ===== 标签下拉选择器 v2：原位展开 + 长按拖拽排序 =====
  tagSelect(items, selected, onChange, options) {
    options = options || {};
    const container = document.createElement('div');
    container.className = 'tag-select';

    const names = items.map(it => typeof it === 'string' ? it : it.name);
    const displayName = selected || '';
    const placeholder = options.placeholder || '选项';
    const searchPlaceholder = options.searchPlaceholder || ('搜索或创建「' + placeholder + '」');

    function escapeHtml(s) {
      return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    // 触发条固定展示（点击展开面板，输入框在面板顶部）
    const field = document.createElement('div');
    field.className = 'tag-select__field';

    const trigger = document.createElement('div');
    trigger.className = 'tag-select__trigger';
    trigger.innerHTML = `
      <span class="tag-select__trigger-text ${displayName ? '' : 'is-placeholder'}">${displayName ? escapeHtml(displayName) : escapeHtml(placeholder)}</span>
      <span class="tag-select__trigger-arrow">▼</span>
    `;
    field.appendChild(trigger);
    container.appendChild(field);

    // 下拉面板（原位置下方展开，顶部为搜索/创建输入框）
    const dropdown = document.createElement('div');
    dropdown.className = 'tag-select__dropdown';
    dropdown.innerHTML = `
      <div class="tag-select__dropdown-inner">
        <div class="tag-select__input-row">
          <input type="text" class="tag-select__input" placeholder="${escapeHtml(searchPlaceholder)}">
        </div>
        <div class="tag-select__options"></div>
      </div>
    `;
    container.appendChild(dropdown);

    const input = dropdown.querySelector('.tag-select__input');

    const optionsBox = dropdown.querySelector('.tag-select__options');

    function visibleRows() {
      return Array.from(optionsBox.children).filter(el =>
        el.classList.contains('tag-select__option') &&
        !el.classList.contains('tag-select__option--ghost') &&
        !el.classList.contains('tag-select__option--placeholder')
      );
    }

    function renderOptions() {
      const q = input.value.toLowerCase().trim();
      optionsBox.innerHTML = '';

      const matched = q ? names.filter(n => n.toLowerCase().includes(q)) : names.slice();

      matched.forEach(name => {
        const row = document.createElement('div');
        row.className = 'tag-select__option' + (name === selected ? ' is-selected' : '');
        row.dataset.name = name;
        row.innerHTML = `
          <span class="tag-select__option-tag">${escapeHtml(name)}</span>
          ${options.showMenu !== false && options.kind ? '<button class="tag-select__option-menu">⋮</button>' : ''}
          ${options.showMenu !== false && options.kind ? '<span class="tag-select__drag-handle">☰</span>' : ''}
        `;
        optionsBox.appendChild(row);

        if (options.showMenu !== false && options.kind) {
          const menuBtn = row.querySelector('.tag-select__option-menu');
          menuBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            App.Components.openTagEditSheet({
              kind: options.kind,
              module: options.module,
              name: name,
              onDone: () => {
                if (options.onDone) options.onDone();
                if (name === selected && onChange) onChange(null);
              }
            });
          });
          bindDrag(row, name);
        } else {
          row.addEventListener('click', () => {
            closeDropdown();
            if (onChange) onChange(name === selected ? null : name);
          });
        }
      });

      // 创建新标签（仅标签类筛选，创建后入库并立即筛选）
      if (q && options.kind && !names.some(n => n.toLowerCase() === q)) {
        const createRow = document.createElement('div');
        createRow.className = 'tag-select__create';
        createRow.textContent = '创建「' + input.value.trim() + '」';
        createRow.addEventListener('click', async () => {
          closeDropdown();
          const v = input.value.trim();
          if (!v) return;
          if (options.kind === 'kp' && options.module) await App.Tags.addKnowledgePoint(options.module, v);
          else if (options.kind === 'ec' && options.module) await App.Tags.addModuleErrorCause(options.module, v);
          if (onChange) onChange(v);
          if (options.onDone) options.onDone();
        });
        optionsBox.appendChild(createRow);
      } else if (!matched.length) {
        optionsBox.innerHTML = '<div class="tag-select__empty">暂无选项</div>';
      }

      // 管理入口：修改 / 删除 / 拖动排序
      if (options.showMenu !== false && options.kind) {
        const manageRow = document.createElement('div');
        manageRow.className = 'tag-select__manage';
        manageRow.textContent = '⚙ 管理标签（修改 / 删除 / 拖动排序）';
        manageRow.addEventListener('click', (e) => {
          e.stopPropagation();
          closeDropdown();
          App.Router.navigate('kpmanage');
        });
        optionsBox.appendChild(manageRow);
      }
    }

    // ===== 长按拖拽排序（替代编辑面板上移/下移）=====
    let dragCtx = null;

    function bindDrag(row, name) {
      // 仅「右侧把手 ☰」长按 500ms 触发拖拽排序；行点击 = 选择；⋮ = 编辑
      const handle = row.querySelector('.tag-select__drag-handle');
      if (!handle) return;
      let timer = null;
      let dragging = false;
      let pointerId = null;
      let lastY = 0;

      handle.addEventListener('pointerdown', (e) => {
        if (input.value.trim()) return;            // 过滤状态下不排序
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        e.preventDefault();
        e.stopPropagation();
        pointerId = e.pointerId;
        lastY = e.clientY;
        try { handle.setPointerCapture(e.pointerId); } catch (_) {}
        timer = setTimeout(() => {
          timer = null;
          if (!row.isConnected) return;
          dragging = true;
          row._suppressClick = true;
          activateDrag(row, e.clientY);
        }, 500);
      });

      // 拖拽 move/up/cancel 挂到 document：activateDrag 会移除 row（含 handle），
      // 原 handle 上的监听随 DOM 移除失效 → 长按后无法拖动；document 级监听不受影响
      const onMove = (ev) => {
        if (ev.pointerId !== pointerId) return;
        if (timer && Math.abs(ev.clientY - lastY) > 14) { clearTimeout(timer); timer = null; }
        if (dragging) moveDrag(ev.clientY);
      };
      const onEnd = (ev) => {
        if (ev.pointerId !== pointerId) return;
        clearTimeout(timer);
        document.removeEventListener('pointermove', onMove);
        document.removeEventListener('pointerup', onEnd);
        document.removeEventListener('pointercancel', onCancel);
        if (dragging) finishDrag();
      };
      const onCancel = (ev) => {
        if (ev.pointerId !== pointerId) return;
        clearTimeout(timer);
        document.removeEventListener('pointermove', onMove);
        document.removeEventListener('pointerup', onEnd);
        document.removeEventListener('pointercancel', onCancel);
        if (dragging) cancelDrag();
      };
      document.addEventListener('pointermove', onMove);
      document.addEventListener('pointerup', onEnd);
      document.addEventListener('pointercancel', onCancel);

      row.addEventListener('click', (e) => {
        if (row._suppressClick) { row._suppressClick = false; return; }
        if (e.target.closest('.tag-select__option-menu')) return;
        if (e.target.closest('.tag-select__drag-handle')) return;
        closeDropdown();
        if (onChange) onChange(name === selected ? null : name);
      });
    }

    function activateDrag(row, clientY) {
      const rows = visibleRows();
      const placeholder = document.createElement('div');
      placeholder.className = 'tag-select__option tag-select__option--placeholder';
      placeholder.style.height = row.offsetHeight + 'px';

      const ghost = row.cloneNode(true);
      ghost.classList.add('tag-select__option--ghost');
      ghost.style.width = row.offsetWidth + 'px';
      ghost.style.height = row.offsetHeight + 'px';
      const rect = row.getBoundingClientRect();
      const listRect = optionsBox.getBoundingClientRect();
      ghost.style.top = (rect.top - listRect.top) + 'px';
      ghost.style.left = (rect.left - listRect.left) + 'px';
      optionsBox.appendChild(ghost);

      row.classList.add('is-sorting-hidden');
      optionsBox.insertBefore(placeholder, row);
      row.remove();

      dragCtx = { row, placeholder, ghost, offsetY: clientY - rect.top };
      document.body.style.userSelect = 'none';
      document.body.style.webkitUserSelect = 'none';
    }

    function moveDrag(clientY) {
      if (!dragCtx) return;
      const ctx = dragCtx;
      const listRect = optionsBox.getBoundingClientRect();
      ctx.ghost.style.top = (clientY - ctx.offsetY - listRect.top) + 'px';

      const ph = ctx.placeholder;
      const ghostCenter = clientY - ctx.offsetY + ctx.ghost.offsetHeight / 2;
      const rows = visibleRows();
      let inserted = false;
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        if (r === ph) continue;
        const rc = r.getBoundingClientRect();
        if (ghostCenter < rc.top + rc.height / 2) {
          if (r !== ph) { optionsBox.insertBefore(ph, r); inserted = true; }
          break;
        }
        if (i === rows.length - 1) { if (r !== ph) { optionsBox.appendChild(ph); inserted = true; } }
      }
    }

    function finishDrag() {
      if (!dragCtx) return;
      const ctx = dragCtx;
      dragCtx = null;
      const order = visibleRows().map(r => r.dataset.name);
      ctx.placeholder.replaceWith(ctx.row);
      ctx.row.classList.remove('is-sorting-hidden');
      ctx.ghost.remove();
      document.body.style.userSelect = '';
      document.body.style.webkitUserSelect = '';
      ctx.row._suppressClick = true;
      setTimeout(() => { ctx.row._suppressClick = false; }, 350);
      if (order.length > 1 && options.kind) {
        App.Tags.setOrder(options.module, options.kind, order).then(() => {
          App.Components.toast('已排序', 'success');
          if (options.onDone) options.onDone();
        });
      }
    }

    function cancelDrag() {
      if (!dragCtx) return;
      const ctx = dragCtx;
      dragCtx = null;
      ctx.placeholder.replaceWith(ctx.row);
      ctx.row.classList.remove('is-sorting-hidden');
      ctx.ghost.remove();
      document.body.style.userSelect = '';
      document.body.style.webkitUserSelect = '';
    }

    // ===== 开关 =====
    function openDropdown() {
      // 同一行内已有其他打开的下拉时，先关闭
      const rowHost = container.closest('.tag-select-row');
      if (rowHost) {
        rowHost.querySelectorAll('.tag-select.is-open').forEach(el => {
          if (el !== container) {
            el.classList.remove('is-open');
            const dd = el.querySelector('.tag-select__dropdown');
            if (dd) dd.classList.remove('is-open');
          }
        });
        // 面板挂到行容器，跨整行展开（top 相对行容器计算）
        rowHost.appendChild(dropdown);
        dropdown.style.top = (container.offsetTop + container.offsetHeight + 6) + 'px';
      }
      container.classList.add('is-open');
      dropdown.classList.add('is-open');
      input.value = '';
      renderOptions();
      bindOutsideClick();
      container._tsClose = closeDropdown; // 供 Router 切页时统一关闭
    }

    function closeDropdown() {
      container.classList.remove('is-open');
      dropdown.classList.remove('is-open');
      unbindOutsideClick();
    }

    let outsideHandler = null;
    function bindOutsideClick() {
      outsideHandler = (e) => {
        if (container.contains(e.target) || dropdown.contains(e.target)) return;
        // 点击其他筛选器：只关闭自己，不拦截（让其正常展开）
        if (e.target.closest('.tag-select')) { closeDropdown(); return; }
        // 点击页面其他区域：关闭面板并拦截事件，避免穿透误触下方错题/笔记
        closeDropdown();
        e.stopPropagation();
        e.preventDefault();
      };
      document.addEventListener('click', outsideHandler, { capture: true });
    }
    function unbindOutsideClick() {
      if (outsideHandler) {
        document.removeEventListener('click', outsideHandler, { capture: true });
        outsideHandler = null;
      }
    }

    trigger.addEventListener('click', () => {
      if (container.classList.contains('is-open')) closeDropdown();
      else openDropdown();
    });

    input.addEventListener('input', () => renderOptions());
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        const q = input.value.trim();
        if (!q) return;
        const exact = names.find(n => n.toLowerCase() === q.toLowerCase());
        closeDropdown();
        if (exact) {
          if (onChange) onChange(exact === selected ? null : exact);
        } else {
          if (options.kind === 'kp' && options.module) App.Tags.addKnowledgePoint(options.module, q);
          else if (options.kind === 'ec' && options.module) App.Tags.addModuleErrorCause(options.module, q);
          if (onChange) onChange(q);
          if (options.onDone) options.onDone();
        }
      }
      if (e.key === 'Escape') closeDropdown();
    });

    return container;
  },

  // ===== 标签底部编辑面板（修改名称/删除；排序改为长按拖拽）=====
  openTagEditSheet(opts) {
    const container = document.getElementById('modal-container');
    const overlay = document.createElement('div');
    overlay.className = 'tag-sheet-overlay';

    const sheet = document.createElement('div');
    sheet.className = 'tag-sheet';
    sheet.innerHTML = `
      <div class="tag-sheet__handle"></div>
      <div class="tag-sheet__title">${opts.kind === 'kp' ? '考点标签' : '错因标签'}：${escapeHtml(opts.name)}</div>
      <div class="tag-sheet__hint">长按筛选列表中的标签并上下拖动，可直接调整排序</div>
      <button class="tag-sheet__btn" data-action="rename">✏️ 修改名称</button>
      <button class="tag-sheet__btn tag-sheet__btn--danger" data-action="delete">🗑 删除标签</button>
      <button class="tag-sheet__btn tag-sheet__btn--ghost" data-action="cancel">取消</button>
    `;
    overlay.appendChild(sheet);

    function escapeHtml(s) {
      return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    function close() {
      overlay.classList.remove('is-visible');
      setTimeout(() => overlay.remove(), 220);
    }

    overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

    sheet.querySelectorAll('[data-action]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const action = btn.getAttribute('data-action');
        if (action === 'cancel') { close(); return; }

        if (action === 'rename') {
          close();
          const nv = window.prompt('修改名称为：', opts.name);
          if (nv && nv.trim() && nv.trim() !== opts.name) {
            if (opts.kind === 'kp') await App.Tags.renameKnowledgePoint(opts.module, opts.name, nv.trim());
            else await App.Tags.renameModuleErrorCause(opts.module, opts.name, nv.trim());
            App.Components.toast('已修改', 'success');
            if (opts.onDone) opts.onDone();
          }
          return;
        }

        if (action === 'delete') {
          close();
          const ok = await App.Components.confirm(
            '删除标签',
            `确定删除标签「${opts.name}」？该标签会从所有相关错题 / 笔记中一并移除。`,
            '删除', '取消', true
          );
          if (ok) {
            if (opts.kind === 'kp') await App.Tags.purgeKnowledgePoint(opts.module, opts.name);
            else await App.Tags.purgeModuleErrorCause(opts.module, opts.name);
            App.Components.toast('已删除', 'success');
            if (opts.onDone) opts.onDone();
          }
        }
      });
    });

    container.appendChild(overlay);
    requestAnimationFrame(() => overlay.classList.add('is-visible'));
  },

  // ===== 标签管理面板（排序 / 修改 / 删除，供录入页等场景使用）=====
  tagManageSheet(opts) {
    const container = document.getElementById('modal-container');
    const overlay = document.createElement('div');
    overlay.className = 'tag-sheet-overlay';
    const sheet = document.createElement('div');
    sheet.className = 'tag-sheet';

    const kind = opts.kind || 'kp';
    const module = opts.module || '';
    const label = kind === 'kp' ? '考点' : '错因';
    // 扁平科目（资料分析）：显示该科目所有模块的合并标签，操作同步到所有模块
    const flatSub = App.Constants.isFlatSubject(module);
    const mods = flatSub ? App.Constants.getModules(module) : [module];
    let items = (kind === 'kp'
      ? (flatSub ? App.Tags.getSubjectKnowledgePoints(module) : App.Tags.getKnowledgePoints(module))
      : (flatSub ? App.Tags.getSubjectErrorCauses(module) : App.Tags.getModuleErrorCauses(module))).slice();

    function escapeHtml(s) {
      return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    const listWrap = document.createElement('div');
    listWrap.className = 'tag-manage-list';

    function renderList() {
      listWrap.innerHTML = '';
      if (items.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'tag-manage-empty';
        empty.textContent = '暂无' + label + '标签，可先在上方输入添加';
        listWrap.appendChild(empty);
        return;
      }
      items.forEach((name, i) => {
        const row = document.createElement('div');
        row.className = 'tag-manage-item';
        row.dataset.name = name;

        const up = document.createElement('button');
        up.type = 'button';
        up.className = 'tag-manage-item__arrow';
        up.textContent = '↑';
        up.disabled = i === 0;
        up.title = '上移';
        up.addEventListener('click', (e) => {
          e.stopPropagation();
          if (i > 0) { const t = items.splice(i, 1)[0]; items.splice(i - 1, 0, t); renderList(); }
        });

        const down = document.createElement('button');
        down.type = 'button';
        down.className = 'tag-manage-item__arrow';
        down.textContent = '↓';
        down.disabled = i === items.length - 1;
        down.title = '下移';
        down.addEventListener('click', (e) => {
          e.stopPropagation();
          if (i < items.length - 1) { const t = items.splice(i, 1)[0]; items.splice(i + 1, 0, t); renderList(); }
        });

        const nameEl = document.createElement('span');
        nameEl.className = 'tag-manage-item__name';
        nameEl.textContent = name;

        const editBtn = document.createElement('button');
        editBtn.type = 'button';
        editBtn.className = 'tag-manage-item__action';
        editBtn.textContent = '✏️';
        editBtn.title = '修改名称';
        editBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const nv = window.prompt('修改「' + name + '」为：', name);
          if (nv && nv.trim() && nv.trim() !== name) {
            if (kind === 'kp') for (const m of mods) await App.Tags.renameKnowledgePoint(m, name, nv.trim());
            else for (const m of mods) await App.Tags.renameModuleErrorCause(m, name, nv.trim());
            items[i] = nv.trim();
            App.Components.toast('已修改', 'success');
            renderList();
          }
        });

        const delBtn = document.createElement('button');
        delBtn.type = 'button';
        delBtn.className = 'tag-manage-item__action tag-manage-item__action--del';
        delBtn.textContent = '🗑';
        delBtn.title = '删除';
        delBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const ok = await App.Components.confirm(
            '删除' + label,
            '确定删除「' + name + '」？该标签会从相关错题 / 笔记中一并移除。',
            '删除', '取消', true
          );
          if (ok) {
            if (kind === 'kp') for (const m of mods) await App.Tags.removeKnowledgePoint(m, name);
            else for (const m of mods) await App.Tags.removeModuleErrorCause(m, name);
            items = items.filter(n => n !== name);
            App.Components.toast('已删除', 'success');
            renderList();
          }
        });

        row.appendChild(up);
        row.appendChild(down);
        row.appendChild(nameEl);
        row.appendChild(editBtn);
        row.appendChild(delBtn);
        listWrap.appendChild(row);
      });
    }

    sheet.innerHTML = `
      <div class="tag-sheet__handle"></div>
      <div class="tag-sheet__title">⚙ 管理${label}标签 · ${escapeHtml(module)}</div>
      <div class="tag-sheet__hint">↑ ↓ 调整排序 · ✏️ 修改名称 · 🗑 删除标签</div>
    `;
    sheet.appendChild(listWrap);

    const doneBtn = document.createElement('button');
    doneBtn.className = 'tag-sheet__btn tag-sheet__btn--ghost';
    doneBtn.textContent = '完成';
    doneBtn.addEventListener('click', async () => {
      if (items.length > 1) { for (const m of mods) await App.Tags.setOrder(m, kind, items); }
      if (opts.onDone) opts.onDone();
      close();
    });
    sheet.appendChild(doneBtn);
    overlay.appendChild(sheet);

    function close() {
      overlay.classList.remove('is-visible');
      setTimeout(() => overlay.remove(), 220);
    }
    overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

    container.appendChild(overlay);
    requestAnimationFrame(() => overlay.classList.add('is-visible'));
    renderList();
  },

  // ===== 筛选标签栏 =====
  filterTags(items, selected, onChange, colorKey, longPress) {
    const bar = document.createElement('div');
    bar.className = 'filter-bar';

    items.forEach(item => {
      const name = typeof item === 'string' ? item : item.name;
      const tag = document.createElement('span');
      tag.className = 'filter-tag';
      if (selected === name) {
        tag.classList.add('active');
        if (colorKey) tag.setAttribute('data-color', colorKey);
      }
      tag.textContent = name;
      tag.addEventListener('click', () => onChange(name));
      if (longPress && longPress.kind && (!longPress.exclude || longPress.exclude.indexOf(name) === -1)) {
        App.Components.bindTagLongPress(tag, longPress.kind, longPress.module, name, longPress.onDone);
      }
      bar.appendChild(tag);
    });

    return bar;
  },

  // ===== 标签 =====
  tag(text, type) {
    const span = document.createElement('span');
    span.className = 'tag';
    if (type) span.classList.add('tag--' + type);
    span.textContent = text;
    return span;
  },

  // ===== 科目卡片（首页矩阵） =====
  subjectCard(subject, stats) {
    const card = document.createElement('div');
    card.className = 'subject-card';
    card.addEventListener('click', () => {
      App.Router.navigate('workspace?subject=' + encodeURIComponent(subject.name));
    });

    const s = subject;
    card.innerHTML = `
      <div class="subject-card__header">
        <div class="subject-card__icon" style="background:${s.color}">${s.icon}</div>
        <div class="subject-card__name">${s.name}</div>
      </div>
      <div class="subject-card__stats">
        <div>今日复盘 <span class="subject-card__stat-value">${stats.todayReviews || 0}</span></div>
        <div>待掌握 <span class="subject-card__stat-value" style="color:var(--color-danger)">${stats.unmastered || 0}</span></div>
        <div>笔记 <span class="subject-card__stat-value">${stats.totalNotes || 0}</span></div>
      </div>
    `;

    return card;
  },

  // ===== 错题卡片 =====
  errorCard(error, onSwipeMaster, onSwipeDelete, onClick, onRefresh, index) {
    const card = document.createElement('div');
    card.className = 'error-card';
    card.style.position = 'relative';
    card.style.overflow = 'hidden';

    // 极简展示：数字标号 + 题目同一排，纯文字（最多两行），无图标无颜色
    const minLine = document.createElement('div');
    minLine.className = 'error-card__min';
    if (typeof index === 'number') {
      const idx = document.createElement('span');
      idx.className = 'error-card__min-idx';
      idx.textContent = (index + 1) + '.';
      minLine.appendChild(idx);
    }
    const text = document.createElement('span');
    text.className = 'error-card__min-text';
    text.textContent = error.question || '';
    minLine.appendChild(text);
    card.appendChild(minLine);

    if (onClick) {
      card.addEventListener('click', onClick);
    }

    // 左滑手势
    App.Utils.initSwipeable(card, {
      onSwipe: () => {
        // 显示滑动操作背景
        card.style.transform = 'translateX(-150px)';
        const swipeBg = document.createElement('div');
        swipeBg.style.cssText = `
          position: absolute; top: 0; right: 0; height: 100%; display: flex;
        `;
        swipeBg.innerHTML = `
          <div class="error-card__swipe-action error-card__swipe-action--master" id="swipe-master">已掌握</div>
          <div class="error-card__swipe-action error-card__swipe-action--delete" id="swipe-delete">删除</div>
        `;
        card.appendChild(swipeBg);

        swipeBg.querySelector('#swipe-master').addEventListener('click', (e) => {
          e.stopPropagation();
          if (onSwipeMaster) onSwipeMaster(error);
        });

        swipeBg.querySelector('#swipe-delete').addEventListener('click', (e) => {
          e.stopPropagation();
          if (onSwipeDelete) onSwipeDelete(error);
        });
      }
    });

    // 点击其他地方时重置滑动
    document.addEventListener('click', function resetSwipe(e) {
      if (!card.contains(e.target)) {
        App.Utils.resetSwipe(card);
        const bg = card.querySelector('[id^="swipe-"]');
        if (bg && bg.parentNode) bg.parentNode.remove();
      }
    });

    return card;
  },

  // ===== 错题画廊卡片（Notion 画廊模式）=====
  galleryErrorCard(error, onClick) {
    const card = document.createElement('div');
    card.className = 'error-gallery-card';

    // 图片（多张；位于题目上方；宽度自适应；最多显示前 3 张，其余 +N）
    const cardImages = (error.images && error.images.length) ? error.images : (error.image ? [error.image] : []);
    if (cardImages.length) {
      const imgWrap = document.createElement('div');
      imgWrap.className = 'error-gallery-card__imgwrap';
      const shown = cardImages.slice(0, 3);
      shown.forEach((src, i) => {
        const img = document.createElement('img');
        img.className = 'error-gallery-card__img';
        img.src = src;
        img.alt = '错题图片' + (i + 1);
        img.addEventListener('click', (e) => {
          e.stopPropagation();
          const overlay = document.createElement('div');
          overlay.className = 'notion-image-preview';
          const big = document.createElement('img');
          big.className = 'notion-image-preview__img';
          big.src = src;
          const close = () => overlay.remove();
          overlay.appendChild(big);
          overlay.addEventListener('click', (ev) => { if (ev.target === overlay || ev.target === big) close(); });
          document.getElementById('modal-container').appendChild(overlay);
          requestAnimationFrame(() => overlay.classList.add('is-visible'));
        });
        imgWrap.appendChild(img);
      });
      if (cardImages.length > 3) {
        const more = document.createElement('span');
        more.className = 'error-gallery-card__imgmore';
        more.textContent = '+' + (cardImages.length - 3);
        imgWrap.appendChild(more);
      }
      card.appendChild(imgWrap);
    }

    const question = document.createElement('div');
    question.className = 'error-gallery-card__question';
    question.textContent = error.question || '';
    card.appendChild(question);

    // 逻辑填空卡片仅展示已填写的辨析词语；多组横向排列，空间不足自动换行。
    const compareWords = (error.subject === '言语理解' && error.module === '逻辑填空' && Array.isArray(error.compareGroups))
      ? error.compareGroups.map(group => (group && group.words ? group.words.trim() : '')).filter(Boolean)
      : [];
    if (compareWords.length) {
      const compareRow = document.createElement('div');
      compareRow.className = 'error-gallery-card__compare-words';
      compareWords.forEach(words => {
        const tag = document.createElement('span');
        tag.className = 'error-gallery-card__compare-word';
        tag.textContent = words;
        compareRow.appendChild(tag);
      });
      card.appendChild(compareRow);
    }

    // 考点 + 错因 同一行（考点在前，错因在后，flex-wrap 自动换行）
    const tagRow = document.createElement('div');
    tagRow.className = 'error-gallery-card__tagrow';
    const kps = (error.knowledgePoints || []).slice(0, 4);
    kps.forEach(kp => {
      const t = document.createElement('span');
      t.className = 'tag tag--neutral';
      t.textContent = kp;
      tagRow.appendChild(t);
    });
    if (error.errorCause) {
      const ct = document.createElement('span');
      ct.className = 'tag tag--neutral tag--cause';
      ct.textContent = error.errorCause;
      tagRow.appendChild(ct);
    }
    card.appendChild(tagRow);
    // 思维误区单独一行，自动换行（用图标替代 ⛏ emoji，对齐画布 40:9）
    if (error.pitfall) {
      const pf = document.createElement('div');
      pf.className = 'error-gallery-card__pitfall';
      pf.innerHTML = '<svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path fill="currentColor" transform="matrix(1 0 0 1 1.5 1.5)" d="M1.6279 6.1693Q1.35 6.8319 1.35 8Q1.35 10.3403 3.0049 11.9951Q4.6597 13.65 7 13.65Q9.3403 13.65 10.9951 11.9951Q12.65 10.3403 12.65 8Q12.65 6.8319 12.3721 6.1693Q10.9967 3.3417 8.3778 1.4711Q8.2093 1.347 8 1.35Q7.7907 1.347 7.6222 1.4711Q5.0033 3.3417 3.6279 6.1693ZM4.9241 11.0759Q3.65 9.8018 3.65 8Q3.65 5.6873 5.7471 3.3307Q7.8833 1.4079 8 1.8066Q7.1167 3.4079 8.2529 5.3307Q9.35 6.6873 9.35 8Q9.35 9.8018 8.0759 11.0759Q6.8018 12.35 5 12.35Q3.1982 12.35 2.9241 11.0759Z" fill-rule="evenodd"/><path fill="currentColor" transform="matrix(1 0 0 1 9 10.75)" d="M1.75 -0.6Q0.5015 -0.6 -0.4243 0.3257Q-0.6072 0.4985 -0.6 0.75Q-0.6072 1.0015 -0.4243 1.1743Q-0.2515 1.3572 0 1.35Q0.2515 1.3572 0.4243 1.1743Q1.4985 0.6 1.75 0.6Q2.5015 0.6 3.5757 1.1743Q3.7485 1.3572 4 1.35Q4.2515 1.3572 4.4243 1.1743Q4.6072 1.0015 4.6 0.75Q4.6072 0.4985 4.4243 0.3257Q3.9985 -0.6 2.75 -0.6Z" fill-rule="evenodd"/></svg> ' + error.pitfall;
      card.appendChild(pf);
    }
    // 录入时间（年月日）——最后一行
    const dateEl = document.createElement('div');
    dateEl.className = 'error-gallery-card__date';
    if (error.createdAt) dateEl.textContent = App.Utils.formatDate(error.createdAt);
    card.appendChild(dateEl);

    card.addEventListener('click', onClick);
    return card;
  },

  // ===== JS 瀑布流容器（方案 B）=====
  // 核心：N 个 flex 列，卡片 append 到当前最矮列；resize 防抖重排列数（手机2/平板3/桌面4）
  masonryGrid(container, opts) {
    const o = opts || {};
    const build = () => {
      const wrap = document.createElement('div');
      wrap.className = 'error-masonry';
      container.appendChild(wrap);
      return wrap;
    };
    let wrap = build();
    let columns = 0;
    let colEls = [];
    let colHeights = [];
    let cards = [];   // 当前已渲染的卡片数据

    const getColumnCount = () => {
      const w = window.innerWidth;
      if (w >= 1024) return 4;
      if (w >= 768) return 3;
      return 2;
    };

    const initColumns = () => {
      wrap.innerHTML = '';
      colEls = [];
      colHeights = [];
      columns = getColumnCount();
      for (let i = 0; i < columns; i++) {
        const col = document.createElement('div');
        col.className = 'error-masonry__col';
        wrap.appendChild(col);
        colEls.push(col);
        colHeights.push(0);
      }
    };

    // 创建单张卡片（复用 galleryErrorCard 展示规则）
    const createCard = (error) => {
      const card = App.Components.galleryErrorCard(
        error,
        () => { if (o.onOpen) o.onOpen(error); }
      );
      card.classList.add('error-masonry__card');
      // 图片懒加载：首图 lazy（jsdom 用 setAttribute 确保属性可见）
      const imgs = card.querySelectorAll('img');
      imgs.forEach((img, i) => {
        if (i === 0) {
          try { img.setAttribute('loading', 'lazy'); } catch (e) { img.loading = 'lazy'; }
        }
      });
      return card;
    };

    // 追加卡片到最矮列
    const appendCard = (error) => {
      const card = createCard(error);
      const minH = Math.min.apply(null, colHeights);
      const idx = colHeights.indexOf(minH);
      colEls[idx].appendChild(card);
      // 估算高度：图片区(有图约240px) + 文字区(约90px) + 间距
      const cardImages = (error.images && error.images.length) ? error.images : (error.image ? [error.image] : []);
      const estH = (cardImages.length ? 220 : 0) + 96;
      colHeights[idx] += estH + 12;
      return card;
    };

    // 图片加载后校正列高（reflow 排序更准确）
    const recalc = () => {
      colHeights = colEls.map(c => c.offsetHeight || 0);
    };

    // 渲染（替换或追加）
    const render = (items, append) => {
      if (!append) { cards = items.slice(); initColumns(); }
      else { cards = cards.concat(items); }
      items.forEach(error => {
        const card = appendCard(error);
        // 图片加载完成校正高度
        const img = card.querySelector('img');
        if (img) {
          img.addEventListener('load', () => recalc(), { once: true });
          img.addEventListener('error', () => recalc(), { once: true });
        }
      });
      // 等待所有图加载后做一次校正，让卡片贴齐
      setTimeout(recalc, 300);
    };

    // 清空（筛选变化时重建）
    const clear = () => { cards = []; initColumns(); };

    // 窗口 resize 防抖重排
    let resizeTimer = null;
    const onResize = () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        const newCols = getColumnCount();
        if (newCols !== columns && cards.length) {
          render(cards, false);
        }
      }, 250);
    };
    window.addEventListener('resize', onResize);

    // 销毁（页面切换时解绑）
    const destroy = () => {
      window.removeEventListener('resize', onResize);
      clearTimeout(resizeTimer);
    };

    render([], false);
    return { render, clear, destroy, recalc, getColumnCount };
  },

  // ===== 套卷卡片 =====
  examCard(exam, onClick) {
    const card = document.createElement('div');
    card.className = 'card card--clickable';

    const subjectScoresHtml = (exam.subjectScores || []).map(s => {
      const subj = App.Constants.SUBJECTS.find(su => su.name === s.subject);
      const color = subj ? subj.color : '#4A90E2';
      const pct = s.totalScore ? Math.round((s.score || 0) / s.totalScore * 100) : 0;
      return `
        <div class="subject-score-item">
          <div class="subject-score-dot" style="background:${color}">${pct}%</div>
          <div class="subject-score-label">${s.subject ? s.subject.slice(0,2) : ''}</div>
        </div>
      `;
    }).join('');

    card.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
        <div>
          <div style="font-weight:600;font-size:var(--font-md);">${exam.name}</div>
          <div style="font-size:var(--font-xs);color:var(--text-tertiary);">${App.Utils.formatDate(exam.examDate)}</div>
        </div>
        <div style="text-align:right;">
          <div style="font-size:var(--font-xl);font-weight:700;color:var(--color-primary);">${exam.totalAccuracy || 0}%</div>
          <div style="font-size:var(--font-xs);color:var(--text-tertiary);">${exam.totalTime || 0}分钟</div>
        </div>
      </div>
      <div class="subject-scores">${subjectScoresHtml}</div>
      ${exam.linkedErrorIds && exam.linkedErrorIds.length > 0 ? `
        <div style="margin-top:8px;font-size:var(--font-xs);color:var(--text-tertiary);">
          关联错题 ${exam.linkedErrorIds.length} 道
        </div>
      ` : ''}
    `;

    if (onClick) {
      card.addEventListener('click', onClick);
    }

    return card;
  },

  // ===== Tab 切换栏 =====
  stickyTabs(tabs, activeIndex, onChange) {
    const container = document.createElement('div');
    container.className = 'tabs';

    tabs.forEach((tab, idx) => {
      const item = document.createElement('div');
      item.className = 'tab-item';
      if (idx === activeIndex) item.classList.add('active');
      item.textContent = tab.label;
      item.addEventListener('click', () => onChange(idx));
      container.appendChild(item);
    });

    return container;
  },

  // ===== 笔记树节点 =====
  noteTreeNode(label, icon, badge, isExpanded, children) {
    const node = document.createElement('div');
    node.className = 'note-tree-node';

    const header = document.createElement('div');
    header.className = 'note-tree-node__header';

    const arrow = document.createElement('span');
    arrow.className = 'note-tree-node__arrow';
    if (isExpanded) arrow.classList.add('expanded');
    arrow.textContent = '▶';

    header.innerHTML += `<span class="note-tree-node__icon">${icon || '📁'}</span>`;
    header.innerHTML += `<span class="note-tree-node__label">${label}</span>`;
    if (badge !== undefined && badge !== null) {
      header.innerHTML += `<span class="note-tree-node__badge">${badge}</span>`;
    }
    header.prepend(arrow);

    const childrenContainer = document.createElement('div');
    childrenContainer.className = 'note-tree-node__children';
    if (isExpanded) childrenContainer.classList.add('expanded');

    if (children && children.length > 0) {
      children.forEach(child => childrenContainer.appendChild(child));
    }

    header.addEventListener('click', () => {
      arrow.classList.toggle('expanded');
      childrenContainer.classList.toggle('expanded');
    });

    node.appendChild(header);
    node.appendChild(childrenContainer);

    return node;
  },

  // ===== 笔记条目 =====
  noteItem(note, onClick) {
    const item = document.createElement('div');
    item.className = 'note-item';
    item.innerHTML = `
      <div class="note-item__title">${App.Utils.truncate(note.title, 30)}</div>
      <div class="note-item__meta">
        <span>${App.Utils.formatDate(note.updatedAt, 'MM-DD HH:mm')}</span>
        ${note.linkedErrors && note.linkedErrors.length > 0
          ? `<span>关联错题 ${note.linkedErrors.length}</span>` : ''}
      </div>
    `;

    if (onClick) {
      item.addEventListener('click', () => onClick(note));
    }

    return item;
  },

  // ===== 表单选择器（预设选项，禁止自由输入） =====
  formSelector(label, options, selected, onChange, required) {
    const group = document.createElement('div');
    group.className = 'form-group';

    if (label) {
      const labelEl = document.createElement('label');
      labelEl.className = 'form-label';
      labelEl.innerHTML = label + (required ? '<span class="required">*</span>' : '');
      group.appendChild(labelEl);
    }

    const select = document.createElement('select');
    select.className = 'form-select';
    select.innerHTML = `<option value="">请选择${label || ''}</option>`;
    options.forEach(opt => {
      const val = typeof opt === 'string' ? opt : opt.name;
      const display = typeof opt === 'string' ? opt : (opt.name || opt);
      select.innerHTML += `<option value="${val}" ${selected === val ? 'selected' : ''}>${display}</option>`;
    });
    select.addEventListener('change', () => onChange(select.value));
    group.appendChild(select);

    return group;
  },

  // ===== 多选标签选择器 =====
  tagMultiSelect(label, options, selectedList, onChange, max, required) {
    const group = document.createElement('div');
    group.className = 'form-group';

    if (label) {
      const labelEl = document.createElement('label');
      labelEl.className = 'form-label';
      labelEl.innerHTML = label + (required ? '<span class="required">*</span>' : '') +
        ` <span style="font-weight:400;color:var(--text-tertiary);">（最多${max || 3}个）</span>`;
      group.appendChild(labelEl);
    }

    const tagsContainer = document.createElement('div');
    tagsContainer.className = 'filter-bar';
    tagsContainer.style.flexWrap = 'wrap';

    const maxCount = max || 3;
    const currentSelected = selectedList || [];

    options.forEach(opt => {
      const val = typeof opt === 'string' ? opt : opt.name;
      const tag = document.createElement('span');
      tag.className = 'filter-tag';
      if (currentSelected.includes(val)) {
        tag.classList.add('active');
        tag.setAttribute('data-color', 'primary');
      }
      tag.textContent = val;
      tag.addEventListener('click', () => {
        if (currentSelected.includes(val)) {
          const newList = currentSelected.filter(v => v !== val);
          onChange(newList);
        } else if (currentSelected.length < maxCount) {
          const newList = [...currentSelected, val];
          onChange(newList);
        } else {
          App.Components.toast('最多选择 ' + maxCount + ' 个', 'error');
        }
      });
      tagsContainer.appendChild(tag);
    });

    group.appendChild(tagsContainer);
    return group;
  },

  // ===== 可编辑标签输入（预设建议 + 自由输入 + 标签展示） =====
  // label: 标题；options: 预设建议字符串数组；selectedList: 已选数组
  // max: 最大数量(0=不限)；allowCustom: 是否允许自由输入
  // persist: 'knowledgePoint' | 'errorCause' | null —— 自定义值入库的类别
  tagInput(label, options, selectedList, onChange, max, allowCustom, placeholder, persist, longPress) {
    const group = document.createElement('div');
    group.className = 'form-group';

    if (label) {
      const labelEl = document.createElement('label');
      labelEl.className = 'form-label';
      labelEl.innerHTML = label + (max
        ? ` <span style="font-weight:400;color:var(--text-tertiary);">（最多${max}个）</span>`
        : '');
      group.appendChild(labelEl);
    }

    const selected = (selectedList || []).slice();
    let optionSet = (options || []).slice();
    const maxCount = max || 0;

    // 已选标签 chips
    const chipsWrap = document.createElement('div');
    chipsWrap.className = 'tag-input__chips';

    // 预设建议标签

    const suggestWrap = document.createElement('div');
    suggestWrap.className = 'tag-input__suggestions';

    // 已选 chip 长按：上移 / 下移 / 删除（调整录入顺序）
    const chipMenu = async (i) => {
      const items = [];
      if (i > 0) items.push({ label: '⬆️ 上移', value: 'up' });
      if (i < selected.length - 1) items.push({ label: '⬇️ 下移', value: 'down' });
      items.push({ label: '🗑 删除', value: 'del' });
      items.push({ label: '取消', value: 'cancel' });
      const act = await App.Components.actionSheet(items, '标签排序');
      if (act === 'up' && i > 0) {
        const v = selected.splice(i, 1)[0];
        selected.splice(i - 1, 0, v);
        renderAll();
        if (onChange) onChange(selected.slice());
      } else if (act === 'down' && i < selected.length - 1) {
        const v = selected.splice(i, 1)[0];
        selected.splice(i + 1, 0, v);
        renderAll();
        if (onChange) onChange(selected.slice());
      } else if (act === 'del') {
        selected.splice(i, 1);
        renderAll();
        if (onChange) onChange(selected.slice());
      }
    };

    function renderChips() {
      chipsWrap.innerHTML = '';
      if (selected.length === 0) {
        const hint = document.createElement('span');
        hint.className = 'tag-input__empty';
        hint.textContent = '尚未选择';
        chipsWrap.appendChild(hint);
        return;
      }
      selected.forEach((val, i) => {
        const chip = document.createElement('span');
        chip.className = 'tag-input__chip';
        const text = document.createElement('span');
        text.textContent = val;
        chip.appendChild(text);
        const x = document.createElement('span');
        x.className = 'tag-input__chip-remove';
        x.textContent = '×';
        x.addEventListener('click', () => {
          selected.splice(i, 1);
          renderAll();
          if (onChange) onChange(selected.slice());
        });
        chip.appendChild(x);
        if (longPress && longPress.kind) {
          App.Components.bindLongPress(chip, () => chipMenu(i));
        }
        chipsWrap.appendChild(chip);
      });
    }

    // 建议标签展开/折叠状态（超过 SUGGEST_COLLAPSE 个时默认折叠，点击展开）
    let suggestExpanded = false;
    const SUGGEST_COLLAPSE = 6;

    function renderSuggestions() {
      suggestWrap.innerHTML = '';
      const suggestions = optionSet.filter(o => !selected.includes(o));
      if (suggestions.length === 0) {
        suggestWrap.style.display = 'none';
        return;
      }
      suggestWrap.style.display = 'flex';
      const visible = suggestExpanded ? suggestions : suggestions.slice(0, SUGGEST_COLLAPSE);
      visible.forEach(opt => {
        const tag = document.createElement('span');
        tag.className = 'tag-input__suggestion';
        tag.textContent = opt;
        tag.addEventListener('click', () => addValue(opt));
        if (longPress && longPress.kind) {
          App.Components.bindTagLongPress(tag, longPress.kind, longPress.module, opt, () => {
            optionSet = (longPress.kind === 'kp'
              ? (App.Constants.isFlatSubject(longPress.module) ? App.Tags.getSubjectKnowledgePoints(longPress.module) : App.Tags.getKnowledgePoints(longPress.module))
              : (App.Constants.isFlatSubject(longPress.module) ? App.Tags.getSubjectErrorCauses(longPress.module) : App.Tags.getMergedErrorCauses(longPress.module))).slice();
            renderSuggestions();
          });
        }
        suggestWrap.appendChild(tag);
      });
      // 展开/收起按钮（标���多时折叠，避免挤压表单）
      if (suggestions.length > SUGGEST_COLLAPSE) {
        const more = document.createElement('span');
        more.className = 'tag-input__more';
        more.textContent = suggestExpanded
          ? '收起 ▲'
          : '展开全部（+' + (suggestions.length - SUGGEST_COLLAPSE) + '）▼';
        more.addEventListener('click', () => {
          suggestExpanded = !suggestExpanded;
          renderSuggestions();
        });
        suggestWrap.appendChild(more);
      }
    }

    function addValue(raw) {
      const val = (raw || '').trim();
      if (!val) return;

      // 已选则不再重复添加
      if (selected.includes(val)) {
        if (input) input.value = '';
        return;
      }

      // 数量限制
      if (maxCount === 1) {
        selected.length = 0; // 单选：替换
      } else if (maxCount > 1 && selected.length >= maxCount) {
        App.Components.toast('最多选择 ' + maxCount + ' 个', 'error');
        return;
      }

      // 自定义值入库（仅当不在预设中）
      if (allowCustom && !optionSet.includes(val)) {
        if (typeof persist === 'function') persist(val);
        else if (persist === 'knowledgePoint') App.Tags.addKnowledgePoint(val);
      }

      selected.push(val);
      if (input) input.value = '';
      renderAll();
      if (onChange) onChange(selected.slice());
    }

    renderChips();
    renderSuggestions();
    group.appendChild(chipsWrap);

    // 自由输入
    let input = null;
    if (allowCustom) {
      const inputRow = document.createElement('div');
      inputRow.className = 'tag-input__field-row';
      input = document.createElement('input');
      input.className = 'form-input';
      input.placeholder = placeholder || '输入自定义标签，回车添加';
      input.style.flex = '1';
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') { e.preventDefault(); addValue(input.value); }
      });
      const addBtn = document.createElement('button');
      addBtn.className = 'btn btn--outline btn--sm';
      addBtn.textContent = '添加';
      addBtn.type = 'button';
      addBtn.addEventListener('click', () => addValue(input.value));
      inputRow.appendChild(input);
      inputRow.appendChild(addBtn);
      group.appendChild(inputRow);
    }

    group.appendChild(suggestWrap);

    // 标签管理入口：排序 / 修改 / 删除（仅当传入 kind 时显示）
    if (longPress && longPress.kind) {
      const manageRow = document.createElement('div');
      manageRow.className = 'tag-input__manage';
      const manageBtn = document.createElement('button');
      manageBtn.type = 'button';
      manageBtn.className = 'tag-input__manage-btn';
      manageBtn.textContent = '⚙ 管理' + (longPress.kind === 'kp' ? '考点' : '错因') + '标签（排序 / 修改 / 删除）';
      manageBtn.addEventListener('click', () => {
        App.Components.tagManageSheet({
          kind: longPress.kind,
          module: longPress.module,
          onDone: () => {
            optionSet = (longPress.kind === 'kp'
              ? (App.Constants.isFlatSubject(longPress.module) ? App.Tags.getSubjectKnowledgePoints(longPress.module) : App.Tags.getKnowledgePoints(longPress.module))
              : (App.Constants.isFlatSubject(longPress.module) ? App.Tags.getSubjectErrorCauses(longPress.module) : App.Tags.getMergedErrorCauses(longPress.module))).slice();
            renderSuggestions();
            renderChips();
            if (longPress.onDone) longPress.onDone();
          }
        });
      });
      manageRow.appendChild(manageBtn);
      group.appendChild(manageRow);
    }

    function renderAll() {
      renderChips();
      renderSuggestions();
    }

    return group;
  },

  // ===== 【考点/错因标签管理组件】管理页用（折叠模块卡片 + 编辑模式拖拽排序/删除/添加）=====
  // opts: { title, kinds: ['kp','ec'], subtitle }  kinds 决定管理哪几类标签（考点 kp / 错因 ec，均按模块）
  // 数据对接 App.Tags（考点 App.Tags.getKnowledgePoints / 错因 App.Tags.getModuleErrorCauses），
  // 所有增删/排序操作即时持久化（复用 App.Tags 存储，与已录错题/笔记数据一致）
  tagManager(container, opts) {
    opts = opts || {};
    const kinds = opts.kinds && opts.kinds.length ? opts.kinds : ['kp'];
    // state: { edit, expanded: { 'sub:科目':bool, 'mod:科目|模块':bool }, editing: '科目|模块|kind|标签名' | null }
    const state = { edit: false, expanded: {}, editing: null };

    const KIND_META = {
      kp: {
        label: '📍 考点',
        get: (m) => App.Tags.getKnowledgePoints(m),
        add: (m, v) => App.Tags.addKnowledgePoint(m, v),
        remove: (m, v) => App.Tags.removeKnowledgePoint(m, v),
        rename: (m, o, n) => App.Tags.renameKnowledgePoint(m, o, n),
        setOrder: (m, arr) => App.Tags.setOrder(m, 'kp', arr),
        confirmText: '删除考点「{v}」？已录入错题 / 笔记中的该标签保留，仅从标签库移除。'
      },
      ec: {
        label: '⚠️ 错因',
        get: (m) => App.Tags.getModuleErrorCauses(m),
        add: (m, v) => App.Tags.addModuleErrorCause(m, v),
        remove: (m, v) => App.Tags.removeModuleErrorCause(m, v),
        rename: (m, o, n) => App.Tags.renameModuleErrorCause(m, o, n),
        setOrder: (m, arr) => App.Tags.setOrder(m, 'ec', arr),
        confirmText: '删除错因「{v}」？仅从该模块错因库移除。'
      }
    };

    // 【三级结构】科目 → 模块（来自 App.Constants.SUBJECTS）
    function collectSubjects() {
      return App.Constants.SUBJECTS.map(s => ({
        name: s.name,
        icon: s.icon || '',
        modules: App.Constants.getModules(s.name)
      }));
    }
    const subjects = collectSubjects();
    const subKey = (sub) => 'sub:' + sub;
    const modKey = (sub, mod) => 'mod:' + sub + '|' + mod;
    const editKey = (sub, mod, kind, name) => sub + '|' + mod + '|' + kind + '|' + name;
    // 科目：默认全部折叠；模块：默认全部折叠（v8.15.22 取消「第一个科目默认展开」）
    const isSubOpen = (sub, idx) => (state.expanded[subKey(sub.name)] === true);
    const isModOpen = (sub, mod) => state.expanded[modKey(sub, mod)] === true;
    // 【扁平科目】仅科目一层级，不显示模块细分（如资料分析：4 个模块标签相同，
    // 管理页合并展示，编辑操作同步到该科目所有模块，错题编辑页按模块选标签仍可见）
    const FLAT_SUBJECTS = ['资料分析'];
    const isFlatSub = (subName) => FLAT_SUBJECTS.indexOf(subName) !== -1;
    // 某科目某分类的标签集合：扁平科目 = 所有模块并集（保序去重）；普通科目 = 指定模块
    const getTags = (sub, mods, kind) => {
      const meta = KIND_META[kind];
      if (isFlatSub(sub.name)) {
        const out = [];
        mods.forEach(m => meta.get(m).forEach(n => { if (out.indexOf(n) === -1) out.push(n); }));
        return out;
      }
      return meta.get(mods[0]);
    };
    // 科目头部标签计数：扁平科目 = 合并去重后数量
    const tagCount = (sub) => {
      if (isFlatSub(sub.name)) {
        let n = 0;
        kinds.forEach(k => { n += getTags(sub, sub.modules, k).length; });
        return n;
      }
      let n = 0;
      sub.modules.forEach(m => kinds.forEach(k => { n += KIND_META[k].get(m).length; }));
      return n;
    };

    // 编辑/完成切换（若有正在编辑的标签先提交）
    function toggleEdit() {
      if (state.editing) commitEditFromDom();
      state.edit = !state.edit;
      render();
      if (!state.edit && opts.onDone) opts.onDone();
    }

    // 从 DOM 读取正在编辑的输入框并提交
    function commitEditFromDom() {
      const input = container.querySelector('.tag-pill.editing input');
      if (input && state.editing) {
        const parts = state.editing.split('|');
        commitEdit(parts[0], parts[1], parts[2], parts[3], input.value);
      } else {
        state.editing = null;
        render();
      }
    }

    // 提交改名：写入 App.Tags（即时持久化；扁平科目同步到该科目所有模块）
    function commitEdit(sub, mod, kind, oldName, newName) {
      state.editing = null;
      newName = (newName || '').trim();
      if (newName && newName !== oldName) {
        const meta = KIND_META[kind];
        const subObj = subjects.find(s => s.name === sub);
        const mods = subObj && isFlatSub(sub) ? subObj.modules : [mod];
        const exists = getTags({ name: sub, modules: subObj ? subObj.modules : [mod] }, mods, kind).includes(newName);
        if (exists) {
          App.Components.toast('已存在同名' + (kind === 'kp' ? '考点' : '错因'), 'error');
        } else {
          // 扁平科目：对所有含旧名的模块改名；普通科目：单模块
          mods.forEach(m => { if (meta.get(m).includes(oldName)) meta.rename(m, oldName, newName); });
        }
      }
      render();
    }

    function render() {
      container.innerHTML = '';
      container.className = 'tag-manager' + (state.edit ? ' edit-mode' : '');

      // 顶部标题栏：仅标题（v8.15.22 管理入口下放到每个模块内部，不再于顶部右侧统一放「编辑」按钮）
      const bar = document.createElement('div');
      bar.className = 'tag-manager__bar';
      const title = document.createElement('div');
      title.className = 'tag-manager__title';
      title.textContent = opts.title || '标签管理';
      bar.appendChild(title);
      container.appendChild(bar);

      // 科目折叠卡片
      subjects.forEach((sub, subIdx) => {
        const subEl = document.createElement('div');
        subEl.className = 'tag-subject';

        // 科目头部
        const subHead = document.createElement('div');
        subHead.className = 'tag-subject-header';
        const subLeft = document.createElement('div');
        subLeft.className = 'tag-subject-header__left';
        const subArrow = document.createElement('span');
        subArrow.className = 'tag-subject-arrow' + (isSubOpen(sub, subIdx) ? ' expanded' : '');
        subArrow.textContent = '▶';
        const subName = document.createElement('span');
        subName.className = 'tag-subject-name';
        subName.textContent = sub.icon ? sub.icon + ' ' + sub.name : sub.name;
        subLeft.appendChild(subArrow);
        subLeft.appendChild(subName);
        const subTotal = tagCount(sub);
        const subCount = document.createElement('span');
        subCount.className = 'tag-subject-count';
        subCount.textContent = subTotal + ' 个';
        subHead.appendChild(subLeft);
        // 右侧：计数 +（扁平科目时）管理按钮
        const subRight = document.createElement('div');
        subRight.className = 'tag-subject-header__right';
        subRight.appendChild(subCount);
        // 扁平科目（无模块细分）：在科目头部直接提供「管理」入口（普通科目在下层模块内）
        if (isFlatSub(sub.name)) {
          const subManage = document.createElement('button');
          subManage.type = 'button';
          subManage.className = 'tag-manager__manage' + (state.edit ? ' is-active' : '');
          subManage.textContent = state.edit ? '完成' : '管理';
          subManage.addEventListener('click', (e) => {
            e.stopPropagation();
            if (!state.edit) state.expanded[subKey(sub.name)] = true;
            toggleEdit();
          });
          subRight.appendChild(subManage);
        }
        subHead.appendChild(subRight);
        subHead.addEventListener('click', () => {
          state.expanded[subKey(sub.name)] = !isSubOpen(sub, subIdx);
          render();
        });
        subEl.appendChild(subHead);

        // 科目内容（模块列表）
        const subContent = document.createElement('div');
        subContent.className = 'tag-subject-content' + (isSubOpen(sub, subIdx) ? ' expanded' : '');
        if (sub.modules.length === 0) {
          const empty = document.createElement('div');
          empty.className = 'tag-cloud__empty';
          empty.style.padding = '16px';
          empty.textContent = '暂无模块';
          subContent.appendChild(empty);
        }

        if (isFlatSub(sub.name)) {
          // 【扁平科目】仅科目一层级：直接渲染考点/错因两个标签云（合并该科目所有模块的标签）
          kinds.forEach(kind => renderKindCloud(subContent, sub, sub.modules, kind));
        } else {
          sub.modules.forEach(mod => {
            const modEl = document.createElement('div');
            modEl.className = 'tag-module';

            // 模块头部
            const modHead = document.createElement('div');
            modHead.className = 'tag-module-header';
            const modLeft = document.createElement('div');
            modLeft.className = 'tag-module-header__left';
            const modArrow = document.createElement('span');
            modArrow.className = 'tag-module-arrow' + (isModOpen(sub.name, mod) ? ' expanded' : '');
            modArrow.textContent = '▶';
            const modName = document.createElement('span');
            modName.className = 'tag-module-name';
            modName.textContent = mod;
            modLeft.appendChild(modArrow);
            modLeft.appendChild(modName);
            const modCount = document.createElement('span');
            modCount.className = 'tag-module-count';
            let modTotal = 0;
            kinds.forEach(k => { modTotal += KIND_META[k].get(mod).length; });
            modCount.textContent = modTotal + ' 个';
            // 右侧：计数 + 「管理」按钮（v8.15.22 下放到每个模块内部）
            const modRight = document.createElement('div');
            modRight.className = 'tag-module-header__right';
            modRight.appendChild(modCount);
            const manageBtn = document.createElement('button');
            manageBtn.type = 'button';
            manageBtn.className = 'tag-manager__manage' + (state.edit ? ' is-active' : '');
            manageBtn.textContent = state.edit ? '完成' : '管理';
            manageBtn.addEventListener('click', (e) => {
              e.stopPropagation();
              // 从非编辑态进入编辑态时，同时展开本模块，便于直接看到可编辑的标签
              if (!state.edit) {
                state.expanded[subKey(sub.name)] = true;
                state.expanded[modKey(sub.name, mod)] = true;
              }
              toggleEdit();
            });
            modRight.appendChild(manageBtn);
            modHead.appendChild(modLeft);
            modHead.appendChild(modRight);
            modHead.addEventListener('click', () => {
              state.expanded[modKey(sub.name, mod)] = !isModOpen(sub.name, mod);
              render();
            });
            modEl.appendChild(modHead);

            // 模块内容（考点 + 错因 两个标签云）
            const modContent = document.createElement('div');
            modContent.className = 'tag-module-content' + (isModOpen(sub.name, mod) ? ' expanded' : '');

            kinds.forEach(kind => renderKindCloud(modContent, sub, [mod], kind));

            modEl.appendChild(modContent);
            subContent.appendChild(modEl);
          });
        }

        subEl.appendChild(subContent);
        container.appendChild(subEl);
      });

      // 编辑模式提示
      if (state.edit) {
        const hint = document.createElement('div');
        hint.className = 'tag-manager__hint';
        hint.textContent = '💡 点击标签文字可直接改名；按住 ⋮⋮ 拖动排序；点击 × 删除；+ 添加 新增（操作即时保存）';
        container.appendChild(hint);
      }
    }

    // 渲染一个分类（考点 / 错因）的标签云
    // container: 父容器；sub: 科目对象；mods: 目标模块数组（普通科目=[mod]，扁平科目=该科目所有模块）
    function renderKindCloud(container, sub, mods, kind) {
      const meta = KIND_META[kind];
      const flat = isFlatSub(sub.name);
      const tagNames = getTags(sub, mods, kind);
      const modRef = flat ? sub.name : mods[0];   // 扁平科目统一用科目名作 mod 引用（便于 commitEdit/bindDrag 识别）

      const catTitle = document.createElement('div');
      catTitle.className = 'tag-category-title';
      catTitle.textContent = meta.label;
      container.appendChild(catTitle);

      const cloud = document.createElement('div');
      cloud.className = 'tag-cloud';
      if (tagNames.length === 0) {
        const empty = document.createElement('span');
        empty.className = 'tag-cloud__empty';
        empty.textContent = '暂无' + (kind === 'kp' ? '考点' : '错因');
        cloud.appendChild(empty);
      } else {
        tagNames.forEach((name) => {
          const isEditing = state.editing === editKey(sub.name, modRef, kind, name);
          const pill = document.createElement('div');
          pill.className = 'tag-pill' + (isEditing ? ' editing' : '');
          pill.dataset.name = name;
          pill.dataset.kind = kind;
          pill.dataset.mod = modRef;
          pill.dataset.sub = sub.name;
          pill.draggable = state.edit && !isEditing;

          if (isEditing) {
            // 改名输入框
            const input = document.createElement('input');
            input.type = 'text';
            input.value = name;
            pill.appendChild(input);
            setTimeout(() => { input.focus(); input.select(); }, 0);
            let done = false;
            const save = () => {
              if (done) return;
              done = true;
              commitEdit(sub.name, modRef, kind, name, input.value);
            };
            input.addEventListener('blur', save);
            input.addEventListener('keydown', (e) => {
              if (e.key === 'Enter') { e.preventDefault(); save(); }
              else if (e.key === 'Escape') { e.preventDefault(); done = true; state.editing = null; render(); }
            });
          } else {
            const nameSpan = document.createElement('span');
            nameSpan.className = 'tag-pill__name' + (state.edit ? ' is-editable' : '');
            nameSpan.textContent = name;
            pill.appendChild(nameSpan);
            if (state.edit) {
              // 编辑模式：点击标签文字 → 改名
              nameSpan.addEventListener('click', (e) => {
                e.stopPropagation();
                if (state.editing) commitEditFromDom();
                state.editing = editKey(sub.name, modRef, kind, name);
                render();
              });
              const handle = document.createElement('span');
              handle.className = 'tag-drag-handle';
              handle.textContent = '⋮⋮';
              const delBtn = document.createElement('span');
              delBtn.className = 'tag-delete-btn';
              delBtn.textContent = '×';
              delBtn.addEventListener('click', async (e) => {
                e.stopPropagation();
                const ok = await App.Components.confirm(
                  '删除' + (kind === 'kp' ? '考点' : '错因'),
                  meta.confirmText.replace('{v}', name),
                  '删除', '取消', true
                );
                if (ok) { for (const m of mods) await meta.remove(m, name); render(); }
              });
              pill.appendChild(handle);
              pill.appendChild(delBtn);
              bindDrag(pill, kind, sub.name, mods, cloud);
            }
          }
          cloud.appendChild(pill);
        });
      }

      // 添加按钮（编辑模式） + 输入行
      if (state.edit) {
        const addBtn = document.createElement('div');
        addBtn.className = 'tag-add-btn';
        addBtn.textContent = '+ 添加';
        const inputRow = document.createElement('div');
        inputRow.className = 'tag-add-input-row';
        const input = document.createElement('input');
        input.type = 'text';
        input.placeholder = '输入' + (kind === 'kp' ? '考点' : '错因') + '名称，回车添加';
        const confirmBtn = document.createElement('button');
        confirmBtn.type = 'button';
        confirmBtn.textContent = '添加';
        const doAdd = async () => {
          const v = input.value.trim();
          if (!v) return;
          if (tagNames.includes(v)) { App.Components.toast('已存在同名' + (kind === 'kp' ? '考点' : '错因'), 'error'); return; }
          for (const m of mods) await meta.add(m, v);
          input.value = '';
          inputRow.classList.remove('show');
          addBtn.style.display = '';
          render();
        };
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); doAdd(); } });
        confirmBtn.addEventListener('click', doAdd);
        inputRow.appendChild(input);
        inputRow.appendChild(confirmBtn);
        addBtn.addEventListener('click', () => {
          inputRow.classList.add('show');
          addBtn.style.display = 'none';
          input.focus();
        });
        cloud.appendChild(addBtn);
        container.appendChild(inputRow);
      }
      container.appendChild(cloud);
    }

    // 同模块同类型内拖拽排序（HTML5 DnD；顺序即时持久化）
    // 拖拽数据用组件级共享变量传递（源 pill dragstart 写入、目标 pill drop 读取）
    let sharedDragData = null;
    function bindDrag(pill, kind, sub, mods, cloud) {
      const flat = isFlatSub(sub);
      pill.addEventListener('dragstart', (e) => {
        sharedDragData = { kind, mod: pill.dataset.mod, name: pill.dataset.name };
        try {
          e.dataTransfer.effectAllowed = 'move';
          e.dataTransfer.setData('text/plain', JSON.stringify(sharedDragData));
        } catch (err) { /* dataTransfer 不可用时忽略 */ }
        setTimeout(() => pill.classList.add('is-dragging'), 0);
      });
      pill.addEventListener('dragend', () => {
        pill.classList.remove('is-dragging');
        sharedDragData = null;
        cloud.querySelectorAll('.tag-pill').forEach(p => p.classList.remove('is-over'));
      });
      pill.addEventListener('dragover', (e) => {
        e.preventDefault();
        if (!sharedDragData) return;
        try { e.dataTransfer.dropEffect = 'move'; } catch (err) {}
        pill.classList.add('is-over');
      });
      pill.addEventListener('dragleave', () => pill.classList.remove('is-over'));
      pill.addEventListener('drop', async (e) => {
        e.preventDefault();
        e.stopPropagation();
        pill.classList.remove('is-over');
        const data = sharedDragData;
        sharedDragData = null;
        if (!data) return;
        // 禁止跨科目/跨类型；扁平科目内 mod 引用统一为科目名，天然同组
        if (data.kind !== kind || data.mod !== pill.dataset.mod || data.name === pill.dataset.name) return;
        const meta = KIND_META[kind];
        const arr = getTags({ name: sub, modules: mods }, mods, kind).slice();
        const from = arr.indexOf(data.name);
        const to = arr.indexOf(pill.dataset.name);
        if (from < 0 || to < 0 || from === to) return;
        arr.splice(from, 1);
        arr.splice(to, 0, data.name);
        for (const m of mods) await meta.setOrder(m, arr);
        render();
      });
    }

    render();
    return { getState: () => state };
  },

  // ===== 表单输入框 =====
  formInput(label, value, placeholder, onChange, type, required) {
    const group = document.createElement('div');
    group.className = 'form-group';

    if (label) {
      const labelEl = document.createElement('label');
      labelEl.className = 'form-label';
      labelEl.innerHTML = label + (required ? '<span class="required">*</span>' : '');
      group.appendChild(labelEl);
    }

    const input = document.createElement(type === 'textarea' ? 'textarea' : 'input');
    if (type === 'textarea') {
      input.className = 'form-textarea';
      input.style.minHeight = '100px';
    } else {
      input.className = 'form-input';
      input.type = type || 'text';
    }
    if (value !== undefined) input.value = value;
    if (placeholder) input.placeholder = placeholder;
    input.addEventListener('input', () => onChange(input.value));
    group.appendChild(input);

    return group;
  },

  // ===== Markdown 编辑器 =====
  markdownEditor(initialContent, placeholder) {
    const wrapper = document.createElement('div');
    wrapper.className = 'md-editor';

    const toolbar = document.createElement('div');
    toolbar.className = 'md-editor__toolbar';

    const tools = [
      { label: 'B', markdown: '**', title: '加粗' },
      { label: 'I', markdown: '*', title: '斜体' },
      { label: 'H2', markdown: '## ', title: '二级标题' },
      { label: 'H3', markdown: '### ', title: '三级标题' },
      { label: '•', markdown: '- ', title: '无序列表' },
      { label: '1.', markdown: '1. ', title: '有序列表' },
      { label: '>', markdown: '> ', title: '引用' },
      { label: '---', markdown: '\n---\n', title: '分割线' },
    ];

    const textarea = document.createElement('textarea');
    textarea.value = initialContent || '';
    textarea.placeholder = placeholder || '请输入内容...（支持 Markdown）';

    tools.forEach(tool => {
      const btn = document.createElement('button');
      btn.textContent = tool.label;
      btn.title = tool.title;
      btn.addEventListener('click', () => {
        const start = textarea.selectionStart;
        const end = textarea.selectionEnd;
        const text = textarea.value;
        const selected = text.substring(start, end);
        const md = tool.markdown;
        let replacement;

        if (md === '\n---\n') {
          replacement = md;
        } else if (md.endsWith(' ')) {
          replacement = md + selected;
        } else {
          replacement = md + selected + md;
        }

        textarea.value = text.substring(0, start) + replacement + text.substring(end);
        textarea.focus();
        textarea.setSelectionRange(start + md.length, start + md.length + (selected.length || 0));
      });
      toolbar.appendChild(btn);
    });

    wrapper.appendChild(toolbar);
    wrapper.appendChild(textarea);

    const getContent = () => textarea.value;
    const setContent = (val) => { textarea.value = val; };

    return { element: wrapper, getContent, setContent };
  },

  // ===== Notion 风格块编辑器（功能增强版） =====
  // 块类型：text/h1/h2/h3/h4/bullet/numbered/todo/quote/callout/toggle/divider/code/table
  // 第 5 参 _ext：{ inlinePadding: true } 用于「就地编辑」场景——底部留白最小化，避免切换页面高度突变
  // ===== v8.5.5 彻底去块：HTML 直通编辑器（单个连续富文本区，所见即所得直存）=====
  // opts: { initialHtml, onChange(html), placeholder, inlinePadding }
  // 格式：加粗/斜体/下划线/删除线/行内代码/颜色/高亮/标题1-3/正文/无序/有序/引用/公式/撤销/重做/软回车
  // 保存：getHtml() = 编辑区 innerHTML 原样直存，格式 100% 保真（不再 JSON 二次转换）
  htmlEditor(initialHtml, opts) {
    opts = opts || {};
    const wrapper = document.createElement('div');
    wrapper.className = 'html-editor';

    const area = document.createElement('div');
    area.className = 'html-editor__area';
    area.contentEditable = true;
    area.setAttribute('contenteditable', 'true');
    if (opts.placeholder !== false) area.dataset.placeholder = opts.placeholder || '输入内容…';
    area.innerHTML = (typeof initialHtml === 'string' ? initialHtml : '') || '';

    // ===== 选区保持（v8.4.17 机制）：工具栏点击不丢选区 =====
    let savedRange = null;
    const captureSel = () => {
      try {
        const sel = window.getSelection();
        if (!sel || sel.rangeCount === 0) return;
        const r = sel.getRangeAt(0);
        if (r && r.toString() && area.contains(r.commonAncestorContainer)) savedRange = r.cloneRange();
      } catch (e) { /* 忽略 */ }
    };
    area.addEventListener('mouseup', captureSel);
    area.addEventListener('keyup', captureSel);
    area.addEventListener('focusin', captureSel);
    area.addEventListener('input', () => { if (opts.onChange) opts.onChange(area.innerHTML); });

    // ===== v8.15.20 Markdown 粘贴自动转换：粘贴 md 语法 → 自动渲染成富文本格式 =====
    // 背景：笔记/错题笔记此前为 HTML 所见即所得直存，导致粘贴 Markdown 语法（#/**/- 等）不生效、原样显示。
    // 此处拦截粘贴：检测到 Markdown 块级/行内语法时，用 App.Utils.simpleMarkdown 渲染成 HTML 后以富文本插入，
    // 存储仍是 HTML → 详情页格式 100% 保真不丢失；老笔记（HTML）天然兼容无需转换。
    function detectMarkdown(text) {
      if (!text) return false;
      const t = text.trim();
      // 多行（含换行）默认可按块解析；单行需命中块级或行内 md 标记
      if (/\n/.test(text)) return true;
      return /^#{1,4}\s/.test(t) || /^[-*]\s/.test(t) || /^\d+\.\s/.test(t) || /^>\s?/.test(t)
        || /^```/.test(t) || /^\|.*\|$/.test(t) || /^---+$/.test(t) || /^\$\$/.test(t)
        || /\*\*.+\*\*/.test(t) || /__.+__/.test(t) || /\*.+\*/.test(t) || /`[^`]+`/.test(t)
        || /\[.+\]\(.+\)/.test(t) || /~~.+~~/.test(t) || /^>/.test(t);
    }
    area.addEventListener('paste', (e) => {
      const clipboardData = e.clipboardData || window.clipboardData;
      if (!clipboardData) return;
      // 若有图片文件，交默认处理（图片粘贴不走 markdown 转换）
      const imgFile = Array.from(clipboardData.items || []).map(it => it.kind === 'file' ? it.getAsFile() : null).find(Boolean);
      if (imgFile) return;
      let text = clipboardData.getData('text/plain');
      if (!text) return;
      // 未命中 md 语法 → 走默认粘贴（纯文本原样插入）
      if (!detectMarkdown(text)) return;

      // 命中 md 语法：阻止默认，转为 HTML 富文本插入
      e.preventDefault();
      try {
        const rendered = App.Utils.simpleMarkdown(text);
        if (!rendered) return;
        const r = ensureSelection();
        if (r) {
          r.deleteContents();
          // 将渲染 HTML 解析为节点插入
          const tmp = document.createElement('div');
          tmp.innerHTML = rendered;
          const frag = document.createDocumentFragment();
          let node;
          while ((node = tmp.firstChild)) frag.appendChild(node);
          r.insertNode(frag);
        } else {
          const tmp = document.createElement('div');
          tmp.innerHTML = rendered;
          let node;
          while ((node = tmp.firstChild)) area.appendChild(node);
        }
        if (opts.onChange) opts.onChange(area.innerHTML);
      } catch (err) {
        // 转换失败回退：按纯文本插入，不丢内容
        document.execCommand('insertText', false, text);
        if (opts.onChange) opts.onChange(area.innerHTML);
      }
    });

    // v8.6.13 快捷键：Tab = 缩进，Shift+Tab = 取消缩进（阻止默认焦点切换）
    area.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') {
        e.preventDefault();
        indentParagraph(e.shiftKey ? -1 : 1);
      }
    });
    // v8.5.6 移动端格式栏显示：旧显示逻辑只认 .notion-editable，htmlEditor 需自触发
    area.addEventListener('focusin', () => {
      if (App.Components._showMobileToolbar) App.Components._showMobileToolbar();
    });
    area.addEventListener('focusout', (e) => {
      const next = e.relatedTarget;
      if (next && wrapper.contains(next)) return;
      setTimeout(() => { if (App.Components._hideMobileToolbar) App.Components._hideMobileToolbar(); }, 220);
    });
    wrapper.addEventListener('mousedown', (e) => {
      const t = e.target;
      if (t && t.closest && t.closest('.notion-tool-btn, .notion-mobile-fmt-item')) e.preventDefault();
    }, true);

    function ensureSelection() {
      let sel = null;
      try { sel = window.getSelection(); } catch (e) { /* 忽略 */ }
      let r = (sel && sel.rangeCount > 0) ? sel.getRangeAt(0) : null;
      if (!r || !r.toString() || !area.contains(r.commonAncestorContainer)) {
        if (savedRange && area.contains(savedRange.commonAncestorContainer)) r = savedRange;
      }
      if (r && r.toString()) {
        try {
          const startNode = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentNode;
          const editable = startNode && startNode.closest ? startNode.closest('[contenteditable]') : null;
          if (editable && document.activeElement !== editable) {
            try { editable.focus({ preventScroll: true }); } catch (e2) { editable.focus(); }
          }
          if (sel) { sel.removeAllRanges(); sel.addRange(r); }
        } catch (e3) { /* 忽略 */ }
      }
      return r;
    }
    function placeCaretAtEnd(el) {
      try {
        el.focus();
        const sel = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(el);
        range.collapse(false);
        sel.removeAllRanges();
        sel.addRange(range);
      } catch (e) { /* 忽略 */ }
    }
    function wrapSelection(range, tag, attrs) {
      const el = document.createElement(tag);
      Object.keys(attrs || {}).forEach(k => el.setAttribute(k, attrs[k]));
      try { range.surroundContents(el); } catch (e) {
        const frag = range.extractContents();
        el.appendChild(frag);
        range.insertNode(el);
      }
    }

    // ===== 行内格式应用 =====
    function applyFormat(cmd) {
      const r = ensureSelection();
      if (!r || !r.toString()) {
        if (cmd === 'bold') document.execCommand('bold');
        else if (cmd === 'italic') document.execCommand('italic');
        else if (cmd === 'underline') document.execCommand('underline');
        else if (cmd === 'strike') document.execCommand('strikeThrough');
        return;
      }
      switch (cmd) {
        case 'bold': document.execCommand('bold'); break;
        case 'italic': document.execCommand('italic'); break;
        case 'underline': document.execCommand('underline'); break;
        case 'strike': document.execCommand('strikeThrough'); break;
        case 'code': {
          const t = r.toString();
          if (t) { const code = document.createElement('code'); code.className = 'notion-inline-code'; code.textContent = t; r.deleteContents(); r.insertNode(code); }
          break;
        }
        case 'color-red': wrapSelection(r, 'span', { style: 'color:#E03131' }); break;
        case 'color-blue': wrapSelection(r, 'span', { style: 'color:#1971C2' }); break;
        case 'color-green': wrapSelection(r, 'span', { style: 'color:#2B8A3E' }); break;
        case 'bg-yellow': wrapSelection(r, 'span', { style: 'background:#FFE066;padding:0 2px;border-radius:2px;' }); break;
        case 'highlight': wrapSelection(r, 'mark', {}); break;
      }
      if (opts.onChange) opts.onChange(area.innerHTML);
    }

    // ===== 段落块级格式（手动 DOM 包裹，不依赖 execCommand formatBlock，移动端可靠）=====
    function blockFormat(type) {
      const r = ensureSelection();
      const node = r ? (r.anchorNode || r.startContainer) : area;
      let el = node.nodeType === 1 ? node : (node.parentElement || area);
      while (el && el !== area && !/^(P|H[1-6]|LI|BLOCKQUOTE|PRE|DIV)$/.test(el.tagName)) el = el.parentElement;
      const map = { h1: 'H1', h2: 'H2', h3: 'H3', text: 'P', quote: 'BLOCKQUOTE' };
      const tag = map[type];
      if (!tag) return;
      // v8.6.4 兜底：光标不在任何段落（空行/编辑区顶部）→ 在光标处当行创建目标格式，绝不无反应
      if (!el || el === area || !el.parentNode) {
        const n = document.createElement(tag);
        n.innerHTML = '<br>';
        if (r && r.startContainer && area.contains(r.startContainer)) {
          try { r.deleteContents(); r.insertNode(n); } catch (e) { area.appendChild(n); }
        } else area.appendChild(n);
        placeCaretAtEnd(n);
        if (opts.onChange) opts.onChange(area.innerHTML);
        return;
      }
      if (el.tagName === tag) return;
      const n = document.createElement(tag);
      n.innerHTML = el.innerHTML;
      // 从列表项转换时，先移出列表容器
      if (el.tagName === 'LI') {
        const listParent = el.parentNode;
        listParent.parentNode.insertBefore(n, listParent);
        if (listParent.children.length === 0) listParent.parentNode.removeChild(listParent);
      } else {
        el.parentNode.replaceChild(n, el);
      }
      placeCaretAtEnd(n);
      if (opts.onChange) opts.onChange(area.innerHTML);
    }
    function toggleList(type) {
      ensureSelection();
      if (type === 'bullet') document.execCommand('insertUnorderedList');
      else if (type === 'numbered') document.execCommand('insertOrderedList');
      if (opts.onChange) opts.onChange(area.innerHTML);
    }
    // v8.6.13 段落缩进/取消缩进（margin-left 步进 20px；快捷键 Tab / Shift+Tab）
    // v8.6.15 修复「乱跑」：缩进是键盘快捷键场景（无选中文字），必须直接用当前光标位置，
    // 不能走 ensureSelection 的 savedRange 兜底（旧选区未更新会导致第二次起定位到旧段落）
    function indentParagraph(dir) {
      let node = null;
      try {
        const sel = window.getSelection();
        if (sel && sel.rangeCount > 0) {
          const r = sel.getRangeAt(0);
          node = r.anchorNode || r.startContainer;
          if (node && node.nodeType === 1) { if (!area.contains(node)) node = null; }
          else if (node && node.parentElement && !area.contains(node.parentElement)) node = null;
        }
      } catch (e) { /* 忽略 */ }
      if (!node) node = area;
      let el = node.nodeType === 1 ? node : (node.parentElement || area);
      while (el && el !== area && !/^(P|H[1-6]|LI|BLOCKQUOTE|PRE|DIV)$/.test(el.tagName)) el = el.parentElement;
      if (!el || el === area || !el.parentNode) {
        // 空行兜底：光标处插入带缩进的段落
        const n = document.createElement('P');
        n.style.marginLeft = (dir > 0 ? 20 : 0) + 'px';
        n.innerHTML = '<br>';
        try {
          const sel = window.getSelection();
          if (sel && sel.rangeCount > 0) {
            const r = sel.getRangeAt(0);
            if (r && r.startContainer && area.contains(r.startContainer)) { r.deleteContents(); r.insertNode(n); }
            else area.appendChild(n);
          } else area.appendChild(n);
        } catch (e2) { area.appendChild(n); }
        placeCaretAtEnd(n);
        if (opts.onChange) opts.onChange(area.innerHTML);
        return;
      }
      const cur = parseFloat(el.style.marginLeft) || 0;
      const next = Math.max(0, cur + (dir > 0 ? 20 : -20));
      el.style.marginLeft = next > 0 ? next + 'px' : '';
      placeCaretAtEnd(el);
      if (opts.onChange) opts.onChange(area.innerHTML);
    }

    // ===== 公式插入（prompt 输入 LaTeX → mformula 节点，源码保留可回源）=====
    function insertFormula() {
      let latex = null;
      try { latex = window.prompt('输入公式（LaTeX 语法）', ''); } catch (e) { latex = null; }
      if (!latex || !latex.trim()) return;
      const span = document.createElement('span');
      span.className = 'mformula';
      span.contentEditable = 'false';
      span.dataset.latex = encodeURIComponent(latex.trim());
      span.innerHTML = App.Utils.renderLatex(latex.trim());
      const r = ensureSelection();
      if (r) { r.deleteContents(); r.insertNode(span); }
      else area.appendChild(span);
      area.appendChild(document.createTextNode(' '));
      if (opts.onChange) opts.onChange(area.innerHTML);
    }
    function history(dir) { document.execCommand(dir === 'undo' ? 'undo' : 'redo'); }
    function softBreak() { document.execCommand('insertLineBreak'); }

    // ===== 桌面工具栏（复用 notion-toolbar 样式）=====
    const toolbar = document.createElement('div');
    toolbar.className = 'notion-toolbar html-editor__toolbar';
    const row = document.createElement('div');
    row.className = 'notion-toolbar__row';
    const grp = (items) => {
      const g = document.createElement('div');
      g.className = 'notion-toolbar__grp';
      items.forEach(x => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'notion-tool-btn' + (x.sm ? ' notion-tool-btn--sm' : '');
        if (x.html) b.innerHTML = x.html; else b.textContent = x.b;
        b.title = x.title;
        b.addEventListener('click', () => x.fn());
        g.appendChild(b);
      });
      return g;
    };
    row.appendChild(grp([
      { html: '<b>B</b>', title: '加粗', fn: () => applyFormat('bold') },
      { html: '<i>I</i>', title: '斜体', fn: () => applyFormat('italic') },
      { html: '<u>U</u>', title: '下划线', fn: () => applyFormat('underline') },
      { html: '<s>S</s>', title: '删除线', fn: () => applyFormat('strike') },
      { html: '<code>&lt;/&gt;</code>', title: '行内代码', fn: () => applyFormat('code') },
      { html: '<span style="background:#FFE066;padding:0 2px;">A</span>', title: '高亮', fn: () => applyFormat('highlight') },
      { html: '<span style="color:#E03131">A</span>', title: '红色', fn: () => applyFormat('color-red') },
      { html: '<span style="color:#1971C2">A</span>', title: '蓝色', fn: () => applyFormat('color-blue') },
      { html: '<span style="color:#2B8A3E">A</span>', title: '绿色', fn: () => applyFormat('color-green') }
    ]));
    row.appendChild(grp([
      { b: 'H1', title: '一级标题', fn: () => blockFormat('h1') },
      { b: 'H2', title: '二级标题', fn: () => blockFormat('h2') },
      { b: 'H3', title: '三级标题', fn: () => blockFormat('h3') },
      { b: '正文', title: '正文', fn: () => blockFormat('text') },
      { b: '•', title: '无序列表', fn: () => toggleList('bullet') },
      { b: '1.', title: '有序列表', fn: () => toggleList('numbered') },
      { b: '❝', title: '引用', fn: () => blockFormat('quote') },            // v8.6.15 图标
      { b: '⇥', title: '缩进 (Tab)', fn: () => indentParagraph(1) },        // v8.6.15 图标
      { b: '⇤', title: '取消缩进 (Shift+Tab)', fn: () => indentParagraph(-1) } // v8.6.15 图标
    ]));
    row.appendChild(grp([
      { b: 'ƒx', title: '插入公式', fn: insertFormula },
      { b: '↶', title: '撤销', fn: () => history('undo') },
      { b: '↷', title: '重做', fn: () => history('redo') }
    ]));
    toolbar.appendChild(row);
    wrapper.appendChild(toolbar);

    // ===== 移动端：注册到移动工具栏单例 + 底部格式面板 =====
    const isMobile = (typeof window !== 'undefined') && (window.innerWidth <= 768 || ('ontouchstart' in window));
    const mobileInst = { _onMobileToolbar: null };
    if (isMobile) {
      App.Components._ensureMobileToolbar();
      App.Components._registerMobileEditor(mobileInst);
    }
    // v8.5.7 Bottom Sheet（自包含：旧 openSheet 是 notionEditor 闭包，组件层不可用）
    let sheetEl = null, sheetOverlay = null;
    function closeSheet() {
      if (!sheetOverlay) return;
      const overlay = sheetOverlay, sheet = sheetEl;
      sheetOverlay = null; sheetEl = null;
      overlay.classList.add('closing');
      sheet && sheet.classList.add('closing');
      setTimeout(() => { if (overlay.parentNode) overlay.remove(); }, 260);
    }
    function openSheet(opts) {
      if (sheetOverlay && sheetOverlay.parentNode) { sheetOverlay.parentNode.removeChild(sheetOverlay); sheetOverlay = null; sheetEl = null; }
      const overlay = document.createElement('div');
      overlay.className = 'notion-mobile-sheet-overlay';
      const sheet = document.createElement('div');
      sheet.className = 'notion-mobile-sheet' + (opts.height ? ' ' + opts.height : '');
      const handleBar = document.createElement('div');
      handleBar.className = 'notion-mobile-sheet__handle';
      // v8.6.9 顶部横杠：按住向下拖 → 面板跟随位移，松手超过 80px 关闭
      let _dragStartY = 0;
      handleBar.addEventListener('touchstart', (e) => { _dragStartY = e.touches[0].clientY; }, { passive: true });
      handleBar.addEventListener('touchmove', (e) => {
        const dy = e.touches[0].clientY - _dragStartY;
        if (dy > 0) sheet.style.transform = 'translateY(' + Math.min(dy, 140) + 'px)';
      }, { passive: true });
      handleBar.addEventListener('touchend', (e) => {
        const dy = e.changedTouches[0].clientY - _dragStartY;
        sheet.style.transform = '';
        if (dy > 80) closeSheet();
      }, { passive: true });
      sheet.appendChild(handleBar);
      const content = document.createElement('div');
      content.className = 'notion-mobile-sheet__content';
      content.innerHTML = opts.bodyHtml;
      sheet.appendChild(content);
      overlay.addEventListener('click', (e) => { if (e.target === overlay) closeSheet(); });
      overlay.appendChild(sheet);
      document.body.appendChild(overlay);
      sheetEl = sheet; sheetOverlay = overlay;
      return { overlay, sheet };
    }
    // ===== v8.6.4 移动端格式栏三面板：A=文字格式（含调色板）、¶=段落格式、➕=插入 =====
    const rowItem = (icon, label, cmd) =>
      '<button class="notion-mobile-fmt-item" data-cmd="' + cmd + '">' +
      '<span class="notion-mobile-fmt-item__icon">' + icon + '</span>' +
      '<span class="notion-mobile-fmt-item__label">' + label + '</span></button>';
    const bindItems = (sheet, handler) => {
      sheet.querySelectorAll('.notion-mobile-fmt-item, .html-color-dot').forEach(item => {
        item.addEventListener('mousedown', (e) => e.preventDefault());
        item.addEventListener('click', () => handler(item));
      });
    };
    // 柔和调色板（贴合整体蓝白风格）
    const SOFT_COLORS = [
      { n: '黑', v: '#1A1A1A' }, { n: '深红', v: '#C92A2A' }, { n: '橙', v: '#E8590C' },
      { n: '黄', v: '#EAB308' }, { n: '绿', v: '#2B8A3E' }, { n: '蓝', v: '#1971C2' },
      { n: '紫', v: '#7048E8' }, { n: '粉', v: '#C2255C' }
    ];
    function applyColor(v) {
      const r = ensureSelection();
      if (r && r.toString()) wrapSelection(r, 'span', { style: 'color:' + v });
      else { try { document.execCommand('foreColor', false, v); } catch (e) {} }
      if (opts.onChange) opts.onChange(area.innerHTML);
    }
    // A：文字格式面板
    function openMobileTextSheet() {
      const bodyHtml =
        '<div class="notion-mobile-fmt-title">文字格式</div>' +
        '<div class="notion-mobile-fmt-grid">' +
          rowItem('<b>B</b>', '加粗', 'bold') +
          rowItem('<i>I</i>', '斜体', 'italic') +
          rowItem('<u>U</u>', '下划线', 'underline') +
          rowItem('<s>S</s>', '删除线', 'strike') +
          rowItem('<span style="background:#FFE066;padding:0 2px;border-radius:2px;">A</span>', '高亮', 'highlight') +
          rowItem('<span style="color:#E03131">A</span>', '颜色', 'color') +
        '</div>';
      const { sheet } = openSheet({ height: 'is-format', bodyHtml });
      bindItems(sheet, (item) => {
        const cmd = item.dataset.cmd;
        if (cmd === 'color') { openColorSheet(); return; }   // 颜色 → 弹调色板
        closeSheet();
        applyFormat(cmd);
      });
    }
    // 调色板（柔和色多选）
    function openColorSheet() {
      const dots = SOFT_COLORS.map(c =>
        '<button class="html-color-dot" data-cmd="' + c.v + '" style="background:' + c.v + '" title="' + c.n + '"></button>').join('');
      const bodyHtml =
        '<div class="notion-mobile-fmt-title">选择文字颜色</div>' +
        '<div class="html-color-row">' + dots + '</div>';
      const { sheet } = openSheet({ height: 'is-format', bodyHtml });
      bindItems(sheet, (item) => {
        closeSheet();
        applyColor(item.dataset.cmd);
      });
    }
    // ¶：段落格式面板（正文放最前）
    function openMobileBlockSheet() {
      const bodyHtml =
        '<div class="notion-mobile-fmt-title">段落格式</div>' +
        '<div class="notion-mobile-fmt-list">' +
          rowItem('文', '正文', 'text') +           // v8.6.15 图标
          rowItem('<b>H1</b>', '标题1', 'h1') +
          rowItem('<b>H2</b>', '标题2', 'h2') +
          rowItem('<b>H3</b>', '标题3', 'h3') +
          rowItem('•', '无序列表', 'bullet') +
          rowItem('1.', '有序列表', 'numbered') +
          rowItem('❝', '引用', 'quote') +           // v8.6.15 图标
          rowItem('⇥', '缩进', 'indent') +          // v8.6.15 图标
          rowItem('⇤', '取消缩进', 'outdent') +     // v8.6.15 图标
        '</div>';
      const { sheet } = openSheet({ height: 'is-format', bodyHtml });
      bindItems(sheet, (item) => {
        const cmd = item.dataset.cmd;
        closeSheet();
        if (cmd === 'text' || cmd === 'h1' || cmd === 'h2' || cmd === 'h3' || cmd === 'quote') blockFormat(cmd === 'text' ? 'text' : cmd);
        else if (cmd === 'indent') indentParagraph(1);
        else if (cmd === 'outdent') indentParagraph(-1);
        else toggleList(cmd);
      });
    }
    // ➕：插入面板（表格/分割线/标注/引用）
    function insertNodeAt(html) {
      const tmp = document.createElement('div');
      tmp.innerHTML = html;
      const n = tmp.firstChild;
      const r = ensureSelection();
      if (r && r.startContainer && area.contains(r.startContainer)) {
        try { r.deleteContents(); r.insertNode(n); } catch (e) { area.appendChild(n); }
      } else area.appendChild(n);
      if (opts.onChange) opts.onChange(area.innerHTML);
      return n;
    }
    function insertTable() {
      const n = insertNodeAt('<table><tbody><tr><td><br></td><td><br></td></tr><tr><td><br></td><td><br></td></tr></tbody></table>');
      const td = n && n.querySelector('td');
      if (td) placeCaretAtEnd(td);
    }
    function insertDivider() { insertNodeAt('<hr>'); }
    function insertCallout() {
      const n = insertNodeAt('<div class="html-callout"><br></div>');
      if (n) placeCaretAtEnd(n);
    }
    function insertQuoteBlock() {
      const n = insertNodeAt('<blockquote><br></blockquote>');
      if (n) placeCaretAtEnd(n);
    }
    function openMobileInsertSheet() {
      const bodyHtml =
        '<div class="notion-mobile-fmt-title">插入</div>' +
        '<div class="notion-mobile-fmt-grid">' +
          rowItem('⊞', '表格', 'table') +
          rowItem('—', '分割线', 'divider') +
          rowItem('💡', '标注', 'callout') +
          rowItem('"', '引用', 'quote-insert') +
        '</div>';
      const { sheet } = openSheet({ height: 'is-format', bodyHtml });
      bindItems(sheet, (item) => {
        const cmd = item.dataset.cmd;
        closeSheet();
        if (cmd === 'table') insertTable();
        else if (cmd === 'divider') insertDivider();
        else if (cmd === 'callout') insertCallout();
        else if (cmd === 'quote-insert') insertQuoteBlock();
      });
    }
    mobileInst._onMobileToolbar = (key) => {
      switch (key) {
        case 'insert': openMobileInsertSheet(); break;
        case 'format': openMobileTextSheet(); break;
        case 'blockfmt': openMobileBlockSheet(); break;
        case 'undo': history('undo'); break;
        case 'redo': history('redo'); break;
        default:
          // 简洁模式：删除/缩进/移动等块操作已随去块移除，给出提示避免「点了没反应」
          if (App.Components.toast) App.Components.toast('该功能在简洁编辑模式已移除', 'info');
      }
    };

    wrapper.appendChild(area);

    return {
      element: wrapper,
      getHtml: () => area.innerHTML,
      setHtml: (h) => { area.innerHTML = (typeof h === 'string' ? h : '') || ''; },
      focusAtEnd: () => placeCaretAtEnd(area),
      area
    };
  },

  notionEditor(initialContent, placeholder, onChange, dataMode, _ext) {
    const ext = _ext || {};
    const wrapper = document.createElement('div');
    wrapper.className = 'notion-editor';

    // ===== v8.4.17 格式栏选区保持：execCommand 依赖「当前选区」，
    // 点击工具栏按钮时浏览器默认行为会转移焦点并清掉编辑区选区，导致加粗/斜体等全部失效。
    // ① 记录编辑器内最近一次有效选区（savedRange）作兜底 ② 工具栏/格式条按钮 mousedown 阻止默认，保住焦点与选区 =====
    let savedRange = null;
    const captureSel = () => {
      try {
        const sel = window.getSelection();
        if (!sel || sel.rangeCount === 0) return;
        const r = sel.getRangeAt(0);
        if (r && r.toString() && wrapper.contains(r.commonAncestorContainer)) savedRange = r.cloneRange();
      } catch (e) { /* 忽略 */ }
    };
    wrapper.addEventListener('mouseup', captureSel);
    wrapper.addEventListener('keyup', captureSel);
    wrapper.addEventListener('focusin', captureSel);
    wrapper.addEventListener('mousedown', (e) => {
      const t = e.target;
      if (t && t.closest && t.closest('.notion-tool-btn, .notion-fmt-btn')) e.preventDefault();
    }, true);

    // ===== 类型映射：内部类型 ⇄ 对外 JSON type 名（供 initialData / getEditorData / setEditorData 使用）=====
    const TYPE_MAP_OUT = {
      text: 'text', h1: 'heading1', h2: 'heading2', h3: 'heading3', h4: 'heading4',
      bullet: 'bulletList', numbered: 'orderedList', todo: 'todo', toggle: 'toggle',
      quote: 'quote', divider: 'divider', code: 'code', callout: 'callout', table: 'table',
      image: 'image'
    };
    const TYPE_MAP_IN = {
      text: 'text', heading1: 'h1', heading2: 'h2', heading3: 'h3', heading4: 'h4',
      bulletList: 'bullet', orderedList: 'numbered', todo: 'todo', toggle: 'toggle',
      quote: 'quote', divider: 'divider', code: 'code', callout: 'callout', table: 'table',
      image: 'image'
    };

    // dataMode: 'md'（默认，回调 Markdown 字符串）| 'json'（回调 JSON 块数组）
    const mode = dataMode === 'json' ? 'json' : 'md';
    let onChangeCb = onChange;

    let blocks = [];
    if (initialContent) {
      // 支持直接传入 JSON 块数组
      if (Array.isArray(initialContent)) {
        blocks = initialContent.map(item => normalizeExternalBlock(item));
      } else {
        blocks = parseMarkdownToBlocks(initialContent);
      }
    }
    if (blocks.length === 0) blocks.push(createBlock('text', ''));
    migrateToggleBlocks(blocks);   // 【修复1】旧数据 toggle 迁移（补 children 字段）

    let focusedBlockEl = null;
    let handleMenu = null;
    let slashMenu = null;
    let formatBar = null;

    const notifyChange = (() => {
      let t = null;
      return () => {
        clearTimeout(t);
        t = setTimeout(() => {
          if (typeof onChangeCb === 'function') {
            onChangeCb(mode === 'json' ? getEditorData() : getContent());
          }
          setSaveStatus('已自动保存');
        }, 600);
      };
    })();

    // ===== 撤销 / 重做（基于块快照） =====
    let undoStack = [];
    let redoStack = [];
    let _lastEditTs = 0;
    function serializeBlocks() {
      try { return JSON.parse(JSON.stringify(blocks)); } catch (e) { return []; }
    }
    // 深拷贝单个块（含 children 递归），供复制块使用
    function serializeBlocksDeep(block) {
      try { return JSON.parse(JSON.stringify(block)); } catch (e) { return null; }
    }
    function restoreBlocks(snap) {
      blocks = JSON.parse(JSON.stringify(snap));
      reRender();
      notifyChange();
      // 撤销/重做后把焦点移回最后一个可编辑块，方便继续输入
      const all = blocksContainer.querySelectorAll('.notion-editable');
      if (all.length) { const last = all[all.length - 1]; last.focus(); placeCaretAtEnd(last); }
    }
    function pushUndo() {
      try {
        undoStack.push(serializeBlocks());
        if (undoStack.length > 120) undoStack.shift();
        redoStack = [];
      } catch (e) {}
    }
    function undo() {
      if (undoStack.length === 0) return;
      redoStack.push(serializeBlocks());
      restoreBlocks(undoStack.pop());
    }
    function redo() {
      if (redoStack.length === 0) return;
      undoStack.push(serializeBlocks());
      restoreBlocks(redoStack.pop());
    }
    // 连续输入合并：700ms 内的连续按键只记一次撤销点
    function noteEditForUndo() {
      const now = Date.now();
      if (now - _lastEditTs > 700) pushUndo();
      _lastEditTs = now;
    }

    // ===== 块文本提取（保留换行，去零宽字符） =====
    function getBlockText(el) {
      let t = '';
      try { t = (el.innerText != null ? el.innerText : el.textContent) || ''; } catch (e) { t = el.textContent || ''; }
      return t.replace(/\u200b/g, '').replace(/\u00a0/g, ' ').replace(/[\u2028\u2029]/g, '\n');
    }

    // ===== 块内软回车（Enter 换行） =====
    function insertSoftBreak(editable) {
      let ok = false;
      try { ok = document.execCommand('insertLineBreak'); } catch (e) { ok = false; }
      if (!ok) {
        const sel = window.getSelection();
        if (sel.rangeCount) {
          const range = sel.getRangeAt(0);
          range.deleteContents();
          const br = document.createElement('br');
          const zwsp = document.createTextNode('\u200b');
          range.insertNode(zwsp);
          range.insertNode(br);
          const after = document.createRange();
          after.setStart(zwsp, 0); after.collapse(true);
          sel.removeAllRanges(); sel.addRange(after);
        }
      }
      const be = editable.closest('.notion-block');
      if (be) { const ctx = getBlockCtx(be); if (ctx) syncBlockData(be, ctx.arr[ctx.idx]); }
      updateFooter(); notifyChange();
    }

    function hideAllMenus() {
      hideSlashMenu(); hideFormatBar(); hideHandleMenu();
    }
    function hideSlashMenu() { if (slashMenu) { slashMenu.remove(); slashMenu = null; } }
    function hideFormatBar() {
      if (formatBar) { formatBar.remove(); formatBar = null; }
    }
    function hideHandleMenu() { if (handleMenu) { handleMenu.remove(); handleMenu = null; } }

    // ===== 块手柄状态机（浏览→编辑→选择→菜单） =====
    // 状态 1 浏览：手柄隐藏；状态 2 编辑：手柄隐藏；状态 3 选择：手柄显示 + 蓝色竖条；状态 4 菜单：手柄旁弹菜单
    // 选中块：添加 .is-selected（手柄显示 + 视觉指示），取消其他块的选中
    function selectBlock(blockEl) {
      blocksContainer.querySelectorAll('.notion-block.is-selected').forEach(b => {
        if (b !== blockEl) b.classList.remove('is-selected');
      });
      if (blockEl) blockEl.classList.add('is-selected');
    }
    function clearSelected() {
      blocksContainer.querySelectorAll('.notion-block.is-selected').forEach(b => b.classList.remove('is-selected'));
    }
    // 进入编辑状态（状态 2）：取消选中，手柄隐藏
    function onBlockFocus(blockEl) {
      if (blockEl) blockEl.classList.remove('is-selected');
      hideHandleMenu();
    }
    // ESC 状态流转：菜单开→关(回状态3)；编辑中→退编辑(进状态3)；选中→取消(回状态1)
    function handleBlockEscape() {
      if (handleMenu && handleMenu.parentElement) { hideHandleMenu(); return true; }   // 状态 4→3
      const ae = document.activeElement;
      // 编辑中（contenteditable 或 table cell）：退编辑并选中所在块
      const editingEl = ae && (ae.isContentEditable || ae.closest && ae.closest('.notion-editable, .notion-table td'));
      if (editingEl) {
        const be = ae.closest ? ae.closest('.notion-block') : null;
        ae.blur();
        if (be) selectBlock(be);     // 状态 2→3：退编辑并选中
        return true;
      }
      if (blocksContainer.querySelector('.notion-block.is-selected')) { clearSelected(); return true; }  // 状态 3→1
      return false;
    }

    // ===== 顶部工具栏（苹果备忘录风格：两行分组） =====
    const toolbar = document.createElement('div');
    toolbar.className = 'notion-toolbar';

    // --- 第一行：块类型 + 行内格式 ---
    const row1 = document.createElement('div');
    row1.className = 'notion-toolbar__row';

    // 块类型组
    const grpBlock = document.createElement('div');
    grpBlock.className = 'notion-toolbar__grp';
    const blockBtns = [
      { b: 'H1', t: 'h1', title: '一级标题' },
      { b: 'H2', t: 'h2', title: '二级标题' },
      { b: 'H3', t: 'h3', title: '三级标题' },
      { b: 'H4', t: 'h4', title: '四级标题' },
      { b: '正文', t: 'text', title: '正文' },
      { b: '</>', t: 'code', title: '代码块' },
    ];
    blockBtns.forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn';
      btn.textContent = x.b;
      btn.title = x.title;
      btn.addEventListener('click', () => applyBlockTypeToFocused(x.t));
      grpBlock.appendChild(btn);
    });
    row1.appendChild(grpBlock);

    // 行内格式组
    const grpInline = document.createElement('div');
    grpInline.className = 'notion-toolbar__grp';
    const inlineBtns = [
      { cmd: 'bold', html: '<b>B</b>', title: '加粗' },
      { cmd: 'italic', html: '<i>I</i>', title: '斜体' },
      { cmd: 'underline', html: '<u>U</u>', title: '下划线' },
      { cmd: 'strike', html: '<s>S</s>', title: '删除线' },
      { cmd: 'code', html: '<code>&lt;/&gt;</code>', title: '行内代码' },
      { cmd: 'bg-yellow', html: '<span style="background:#FFE066;padding:0 2px;border-radius:2px;">A</span>', title: '高亮' },
      { cmd: 'color-red', html: '<span style="color:#E03131">A</span>', title: '红色' },
      { cmd: 'color-blue', html: '<span style="color:#1971C2">A</span>', title: '蓝色' },
    ];
    inlineBtns.forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn notion-tool-btn--sm';
      btn.innerHTML = x.html;
      btn.title = x.title;
      btn.addEventListener('click', () => {
        const sel = window.getSelection();
        const range = (sel && sel.rangeCount > 0) ? sel.getRangeAt(0) : null;
        applyFormat(x.cmd, range);
      });
      grpInline.appendChild(btn);
    });
    row1.appendChild(grpInline);

    // 撤销 / 重做
    const grpHistory = document.createElement('div');
    grpHistory.className = 'notion-toolbar__grp';
    [
      { b: '↶', cmd: 'undo', title: '撤销 (⌘Z)' },
      { b: '↷', cmd: 'redo', title: '重做 (⌘⇧Z)' }
    ].forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn';
      btn.type = 'button';
      btn.textContent = x.b;
      btn.title = x.title;
      btn.addEventListener('click', () => { if (x.cmd === 'undo') undo(); else redo(); });
      grpHistory.appendChild(btn);
    });
    row1.appendChild(grpHistory);

    // 本行换行（软回车）：在本行内添加内容，不跳转到下一行（等价 Shift+Enter）
    const grpNewline = document.createElement('div');
    grpNewline.className = 'notion-toolbar__grp';
    const newlineBtn = document.createElement('button');
    newlineBtn.className = 'notion-tool-btn notion-tool-btn--svg';
    newlineBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h16"/><path d="M4 12h10"/><path d="M4 18h6"/><path d="M17 14v6"/><path d="M17 14l-3 3 3 3"/></svg>';
    newlineBtn.title = '本行换行（不新建段落）';
    newlineBtn.addEventListener('click', () => {
      const ed = focusedBlockEl ? focusedBlockEl.querySelector('.notion-editable') : null;
      if (ed) { pushUndo(); insertSoftBreak(ed); ed.focus(); }
      else {
        // 无聚焦块：聚焦最后一个块的编辑区再软回车
        const all = blocksContainer.querySelectorAll('.notion-editable');
        if (all.length) { const last = all[all.length - 1]; last.focus(); placeCaretAtEnd(last); pushUndo(); insertSoftBreak(last); }
      }
    });
    grpNewline.appendChild(newlineBtn);
    row1.appendChild(grpNewline);

    // --- 第二行：列表 + 缩进 + 其他工具 ---
    const row2 = document.createElement('div');
    row2.className = 'notion-toolbar__row';

    // 列表组
    const grpList = document.createElement('div');
    grpList.className = 'notion-toolbar__grp';
    const listBtns = [
      { b: '••', t: 'bullet', title: '无序列表' },
      { b: '1.', t: 'numbered', title: '有序列表' },
      { b: '☐', t: 'todo', title: '待办' },
    ];
    listBtns.forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn';
      btn.textContent = x.b;
      btn.title = x.title;
      btn.addEventListener('click', () => applyBlockTypeToFocused(x.t));
      grpList.appendChild(btn);
    });
    row2.appendChild(grpList);

    // 缩进组（从每行左侧迁移过来）
    // 【修复】缩进/缩出图标明显区分：缩出 = 左箭头+右移块形；缩进 = 右箭头+左移块形
    const grpIndent = document.createElement('div');
    grpIndent.className = 'notion-toolbar__grp';
    const INDENT_ICONS = {
      outdent: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l-5 6 5 6"/><path d="M5 4v16"/><rect x="13" y="5" width="8" height="14" rx="1"/></svg>',
      indent: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 6l5 6-5 6"/><path d="M19 4v16"/><rect x="3" y="5" width="8" height="14" rx="1"/></svg>',
    };
    [
      { icon: INDENT_ICONS.outdent, action: 'outdent', title: '减少缩进（后退）' },
      { icon: INDENT_ICONS.indent, action: 'indent', title: '增加缩进' },
    ].forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn notion-tool-btn--svg';
      btn.innerHTML = x.icon;
      btn.title = x.title;
      btn.addEventListener('click', () => {
          if (!focusedBlockEl) return;
          const ctx = getBlockCtx(focusedBlockEl);
          if (!ctx) return;
          const idx = ctx.idx;
          pushUndo();
          if (x.action === 'indent' && ctx.arr[idx].indent < 3) ctx.arr[idx].indent++;
          else if (x.action === 'outdent' && ctx.arr[idx].indent > 0) ctx.arr[idx].indent--;
          reRender(); notifyChange();
        const fe = focusBlockEditable(ctx.parentIdx, idx);
        if (fe) fe.focus();
      });
      grpIndent.appendChild(btn);
    });
    row2.appendChild(grpIndent);

    // 其他工具组
    const grpExtra = document.createElement('div');
    grpExtra.className = 'notion-toolbar__grp';
    const extraBtns = [
      { b: '"', t: 'quote', title: '引用' },
      { b: '—', t: 'divider', title: '分割线' },
      { b: '⊞', t: 'table', title: '表格' },
    ];
    extraBtns.forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn';
      btn.textContent = x.b;
      btn.title = x.title;
      btn.addEventListener('click', () => applyBlockTypeToFocused(x.t));
      grpExtra.appendChild(btn);
    });
    row2.appendChild(grpExtra);

    // 底部悬浮格式栏：两行分组合并为一行（横向滚动），保持全部功能
    [grpBlock, grpInline, grpHistory, grpNewline, grpList, grpIndent, grpExtra].forEach(g => toolbar.appendChild(g));

    // ===== 【修复2】Notion 移动端：底部横向滑动工具栏（单例） + Bottom Sheet 菜单 =====
    // 桌面端使用底部悬浮格式栏（notion-toolbar）；移动端（<=768px 或触屏）用 Notion 风格底栏
    // 工具栏 DOM 为 App.Components 级单例（只构建一次），本实例注册为活动编辑器，按钮动作分发到 _onMobileToolbar
    const isMobile = (typeof window !== 'undefined') && (window.innerWidth <= 768 || ('ontouchstart' in window));
    let _mobileToolbar = null;
    // 实例句柄：闭包捕获本编辑器的动作分发，注册为「当前活动编辑器」
    const _mobileInst = { _onMobileToolbar: null };
    if (isMobile) {
      _mobileToolbar = App.Components._ensureMobileToolbar();
      App.Components._registerMobileEditor(_mobileInst);
    }

    // 实例暴露给单例工具栏的动作分发入口
    _mobileInst._onMobileToolbar = (key) => {
      switch (key) {
        case 'insert': openBlockSheet(); break;
        case 'format': case 'blockfmt': openFormatSheet(); break;   // v8.6.4 ¶ 与 A 复用旧格式面板
        case 'redo': redo(); break;
        case 'undo': undo(); break;
        case 'delete': if (focusedBlockEl) deleteBlock(0, focusedBlockEl); else if (blocks.length > 1) deleteBlock(blocks.length - 1); break;
        case 'indent': case 'outdent': {
          const target = focusedBlockEl || wrapper.querySelector('.notion-block:last-of-type .notion-editable');
          if (!target) return;
          const be = target.closest('.notion-block');
          if (!be) return;
          const ctx = getBlockCtx(be);
          if (!ctx) return;
          pushUndo();
          if (key === 'indent' && ctx.arr[ctx.idx].indent < 3) ctx.arr[ctx.idx].indent++;
          else if (key === 'outdent' && ctx.arr[ctx.idx].indent > 0) ctx.arr[ctx.idx].indent--;
          reRender(); notifyChange();
          const fe = focusBlockEditable(ctx.parentIdx, ctx.idx);
          if (fe) fe.focus();
          break;
        }
        case 'moveUp': case 'moveDown': {
          const be = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
          if (!be) return;
          const ctx = getBlockCtx(be);
          if (!ctx) return;
          moveBlock(ctx.idx, key === 'moveUp' ? -1 : 1, be);
          break;
        }
        case 'dismiss': if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); hideAllMenus(); break;
        case 'voice': App.Components.toast && App.Components.toast('语音输入将在后续版本支持', 'info'); break;
        case 'image': App.Components.toast && App.Components.toast('图片上传将在后续版本支持', 'info'); break;
        case 'comment': App.Components.toast && App.Components.toast('评论功能将在后续版本支持', 'info'); break;
        case 'mention': App.Components.toast && App.Components.toast('提及功能将在后续版本支持', 'info'); break;
        case 'more': App.Components.toast && App.Components.toast('更多操作即将上线', 'info'); break;
        default: break;
      }
    };

    // ===== 软键盘/系统工具条适配钩子 =====
    // 单例工具栏已在 App.Components 层监听 visualViewport（含 Safari 透明条），
    // 通过 _onKeyboardChange 回调通知本实例：kb > 0 表示键盘+透明条占位高度，用于浮动格式栏避让
    let _keyboardH = 0;
    _mobileInst._onKeyboardChange = (kb) => {
      _keyboardH = kb;
      // 编辑器容器底部留白：悬浮卡片高度(56) + 底部间距(16) + 键盘高度，避免内容被遮
      // 就地编辑模式（inlinePadding）只保留最小留白，避免切换瞬间高度突变导致页面重排
      try {
        const basePad = ext.inlinePadding ? 8 : (56 + 16 + 20);
        wrapper.style.paddingBottom = (basePad + kb) + 'px';
      } catch (e) {}
      // 格式栏打开时重新定位（避开 Safari「上/下/对号」透明条）
      if (formatBar && formatBar.parentElement) repositionFormatBar();
    };
    // 初始留白（无键盘时：56 + 16 + 20；就地编辑仅 8px，页面高度不突变）
    try { wrapper.style.paddingBottom = ext.inlinePadding ? '8px' : '92px'; } catch (e) {}
    // 键盘弹出时把聚焦块滚动到可视区
    const _vvScrollHandler = () => {
      if (_keyboardH > 0 && focusedBlockEl && focusedBlockEl.scrollIntoView) {
        focusedBlockEl.scrollIntoView({ block: 'center', behavior: 'auto' });
      }
    };
    if (isMobile && window.visualViewport) {
      window.visualViewport.addEventListener('scroll', _vvScrollHandler, { passive: true });
    }

    // ===== Bottom Sheet 通用：打开/关闭/下滑关闭 =====
    let sheetEl = null, sheetOverlay = null;
    function closeSheet() {
      if (!sheetOverlay) return;
      const overlay = sheetOverlay, sheet = sheetEl;
      sheetOverlay = null; sheetEl = null;
      overlay.classList.add('closing');
      sheet && sheet.classList.add('closing');
      setTimeout(() => { if (overlay.parentNode) overlay.remove(); }, 260);
    }
    function forceCloseSheet() {
      if (sheetOverlay) { sheetOverlay.remove(); sheetOverlay = null; sheetEl = null; }
    }
    function openSheet(opts) {
      forceCloseSheet();
      const overlay = document.createElement('div');
      overlay.className = 'notion-mobile-sheet-overlay';
      const sheet = document.createElement('div');
      sheet.className = 'notion-mobile-sheet' + (opts.height ? ' ' + opts.height : '');
      const handleBar = document.createElement('div');
      handleBar.className = 'notion-mobile-sheet__handle';
      // v8.6.9 顶部横杠：按住向下拖 → 面板跟随位移，松手超过 80px 关闭
      let _dragStartY = 0;
      handleBar.addEventListener('touchstart', (e) => { _dragStartY = e.touches[0].clientY; }, { passive: true });
      handleBar.addEventListener('touchmove', (e) => {
        const dy = e.touches[0].clientY - _dragStartY;
        if (dy > 0) sheet.style.transform = 'translateY(' + Math.min(dy, 140) + 'px)';
      }, { passive: true });
      handleBar.addEventListener('touchend', (e) => {
        const dy = e.changedTouches[0].clientY - _dragStartY;
        sheet.style.transform = '';
        if (dy > 80) closeSheet();
      }, { passive: true });
      sheet.appendChild(handleBar);
      const content = document.createElement('div');
      content.className = 'notion-mobile-sheet__content';
      content.innerHTML = opts.bodyHtml;
      sheet.appendChild(content);
      overlay.addEventListener('click', (e) => { if (e.target === overlay) closeSheet(); });
      let startY = 0;
      sheet.addEventListener('touchstart', (e) => { startY = e.touches[0].clientY; }, { passive: true });
      sheet.addEventListener('touchend', (e) => {
        const dy = e.changedTouches[0].clientY - startY;
        if (dy > 80) closeSheet();
      }, { passive: true });
      overlay.appendChild(sheet);
      document.body.appendChild(overlay);
      sheetEl = sheet; sheetOverlay = overlay;
      return { overlay, sheet };
    }

    // ===== 块插入菜单（Bottom Sheet，65vh，两列网格分类） =====
    function openBlockSheet() {
      const gridItem = (icon, label, type) =>
        '<button class="notion-mobile-sheet-item" data-type="' + type + '">' +
        '<span class="notion-mobile-sheet-item__icon">' + icon + '</span>' +
        '<span class="notion-mobile-sheet-item__label">' + label + '</span></button>';
      const headIcon = (text, cls) => '<span class="notion-mobile-sheet-icon ' + (cls || '') + '">' + text + '</span>';
      const bodyHtml =
        '<div class="notion-mobile-sheet-grid">' +
          '<div class="notion-mobile-sheet-section-title">基本区块</div>' +
          gridItem(headIcon('T', 't'), '文本', 'text') +
          gridItem(headIcon('H₁', 'h'), '标题 1', 'h1') +
          gridItem(headIcon('H₂', 'h'), '标题 2', 'h2') +
          gridItem(headIcon('H₃', 'h'), '标题 3', 'h3') +
          gridItem(headIcon('H₄', 'h'), '标题 4', 'h4') +
          gridItem(headIcon('•', 'b'), '项目符号列表', 'bullet') +
          gridItem(headIcon('1.', 'o'), '有序列表', 'numbered') +
          gridItem(headIcon('☐', 't'), '待办事项', 'todo') +
          gridItem(headIcon('▸', 't'), '折叠列表', 'toggle') +
          gridItem(headIcon('📄', 'p'), '页面', 'page') +
          gridItem(headIcon('💡', 'c'), '标注', 'callout') +
          gridItem(headIcon('"', 'q'), '引用', 'quote') +
          gridItem(headIcon('⊞', 'tb'), '表格', 'table') +
          gridItem(headIcon('—', 'd'), '分割线', 'divider') +
          gridItem(headIcon('🔗', 'l'), '链接到页面', 'link') +
          '<div class="notion-mobile-sheet-section-title">媒体</div>' +
          gridItem(headIcon('🖼', 'im'), '图片', 'image') +
          gridItem(headIcon('▶', 'v'), '视频', 'video') +
          gridItem(headIcon('🔊', 'a'), '音频', 'audio') +
          gridItem(headIcon('&lt;/&gt;', 'c'), '代码', 'code') +
          gridItem(headIcon('📎', 'f'), '文件', 'file') +
          gridItem(headIcon('🔖', 'b'), '网页书签', 'bookmark') +
        '</div>';
      const { sheet } = openSheet({ height: 'is-block', bodyHtml });
      sheet.querySelectorAll('.notion-mobile-sheet-item').forEach(item => {
        item.addEventListener('click', () => {
          const type = item.dataset.type;
          closeSheet();
          insertBlockFromSheet(type);
        });
      });
    }

    // 块插入逻辑：在当前聚焦块下方插入，无聚焦块则在末尾；插入后聚焦并 onChange
    function insertBlockFromSheet(type) {
      // v8.4.18 A：文字类格式 → 直接转换当前聚焦块（不跳行）；表格/分割线等块状元素仍插到当前行下方
      const convertTypes = { text:'text', h1:'h1', h2:'h2', h3:'h3', h4:'h4', bullet:'bullet', numbered:'numbered', todo:'todo', toggle:'toggle', quote:'quote', code:'code', callout:'callout' };
      if (convertTypes[type]) {
        const be = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
        if (be) { applyBlockTypeToFocused(type); return; }
      }
      let nb = null;
      const baseTypes = { text:'text', h1:'h1', h2:'h2', h3:'h3', h4:'h4', bullet:'bullet', numbered:'numbered', todo:'todo', toggle:'toggle', quote:'quote', divider:'divider', code:'code' };
      if (type === 'table') { nb = createBlock('table', ''); nb.tableData = [['列1','列2'],['','']]; }
      else if (type === 'callout') { nb = createBlock('callout', ''); }
      else if (baseTypes[type]) nb = createBlock(baseTypes[type], '');
      else { App.Components.toast && App.Components.toast('「' + type + '」将在后续版本支持', 'info'); return; }

      const be = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
      if (be) {
        const ctx = getBlockCtx(be);
        if (ctx) {
          pushUndo();
          ctx.arr.splice(ctx.idx + 1, 0, nb);
          reRender(); notifyChange();
          const el = focusBlockEditable(ctx.parentIdx, ctx.idx + 1);
          if (el) el.focus();
          return;
        }
      }
      pushUndo();
      blocks.push(nb);
      reRender(); notifyChange();
      const el = focusBlockEditable(null, blocks.length - 1);
      if (el) el.focus();
    }

    // ===== 文本格式菜单（Bottom Sheet，45vh，单列） =====
    function openFormatSheet() {
      const rowItem = (icon, label, cmd, swatch) =>
        '<button class="notion-mobile-fmt-item" data-cmd="' + cmd + '">' +
        '<span class="notion-mobile-fmt-item__icon">' + icon + '</span>' +
        '<span class="notion-mobile-fmt-item__label">' + label + '</span>' +
        (swatch ? '<span class="notion-mobile-fmt-item__swatch" style="background:' + swatch + '"></span>' : '') +
        '</button>';
      const bodyHtml =
        '<div class="notion-mobile-fmt-title">格式</div>' +
        '<div class="notion-mobile-fmt-list">' +
          rowItem('<b>B</b>', '加粗', 'bold') +
          rowItem('<i>I</i>', '斜体', 'italic') +
          rowItem('<u>U</u>', '下划线', 'underline') +
          rowItem('<s>S</s>', '删除线', 'strike') +
          rowItem('<code>&lt;/&gt;</code>', '行内代码', 'code') +
          rowItem('<span style="color:#E03131">A</span>', '文字颜色', 'color-red', '#E03131') +
          rowItem('<span style="background:#FFE066;padding:0 2px;">A</span>', '背景高亮', 'bg-yellow', '#FFE066') +
          rowItem('🔗', '添加链接', 'link') +
        '</div>';
      const { sheet } = openSheet({ height: 'is-format', bodyHtml });
      sheet.querySelectorAll('.notion-mobile-fmt-item').forEach(item => {
        // v8.4.17 面板是 body 级弹层（不在编辑器 wrapper 内），需单独阻止 mousedown 默认，避免清掉编辑区选区
        item.addEventListener('mousedown', (e) => e.preventDefault());
        item.addEventListener('click', () => {
          const cmd = item.dataset.cmd;
          closeSheet();
          const sel = window.getSelection();
          const range = (sel && sel.rangeCount > 0) ? sel.getRangeAt(0) : null;
          applyFormat(cmd, range);
          if (focusedBlockEl) {
            const ed = focusedBlockEl.querySelector('.notion-editable');
            if (ed) ed.focus();
          }
        });
      });
    }


    const blocksContainer = document.createElement('div');
    blocksContainer.className = 'notion-editor__blocks';

    // ===== 斜杠命令菜单 =====
    // 键盘导航状态：当前高亮项索引 + 当前过滤关键词
    let slashActiveIdx = 0;
    let slashItems = [];       // 当前可见的菜单项 DOM
    let slashFilter = '';      // 当前过滤词（不含 /）
    let slashTargetBlock = null; // 菜单所依附的块

    // 完整的斜杠命令项定义（菜单重建 / 过滤刷新共用）
    function buildSlashItems() {
      return [
        { type: 'text', icon: '📝', label: '文本', desc: '普通文本段落' },
        { type: 'h1', icon: 'H₁', label: '一级标题', desc: '大标题' },
        { type: 'h2', icon: 'H₂', label: '二级标题', desc: '中标题' },
        { type: 'h3', icon: 'H₃', label: '三级标题', desc: '小标题' },
        { type: 'h4', icon: 'H₄', label: '四级标题', desc: '更小标题' },
        { type: 'bullet', icon: '•', label: '无序列表', desc: '项目符号列表' },
        { type: 'numbered', icon: '1.', label: '有序列表', desc: '编号列表' },
        { type: 'todo', icon: '☐', label: '待办事项', desc: '带复选框的任务' },
        { type: 'toggle', icon: '▸', label: '折叠块', desc: '可展开/收起' },
        { type: 'quote', icon: '"', label: '引用', desc: '引用块' },
        { type: 'divider', icon: '—', label: '分割线', desc: '水平分割线' },
        { type: 'code', icon: '</>', label: '代码块', desc: '等宽字体代码' },
        { type: 'callout', icon: '💡', label: '高亮提示', desc: '带背景的提示框' },
        { type: 'table', icon: '⊞', label: '表格', desc: '两列简单表格' },
        { type: 'image', icon: '🖼️', label: '图片', desc: '上传或粘贴图片' },
        { type: 'link-note', icon: '🔗', label: '链接笔记', desc: '插入已有笔记链接' },
        { type: 'link-error', icon: '🔗', label: '链接错题', desc: '插入已有错题链接' },
      ];
    }

    // 仅刷新菜单内容（输入过滤时调用，不重建定位，避免闪烁）
    function refreshSlashMenu(filter) {
      if (!slashMenu) return;
      slashFilter = (filter || '');
      slashActiveIdx = 0;
      slashItems = [];
      slashMenu.innerHTML = '';
      const blockEl = slashTargetBlock;
      const items = buildSlashItems();
      const q = slashFilter.toLowerCase();
      items.forEach(item => {
        if (q && !item.label.toLowerCase().includes(q) && !item.desc.toLowerCase().includes(q) && !item.type.toLowerCase().includes(q)) return;
        const row = document.createElement('div');
        row.className = 'notion-slash-item';
        row.dataset.type = item.type;
        row.innerHTML = `<span class="notion-slash-icon">${item.icon}</span><div><span class="notion-slash-label">${item.label}</span><span class="notion-slash-desc">${item.desc}</span></div>`;
        row.addEventListener('click', () => {
          hideSlashMenu();
          if (item.type === 'link-note' || item.type === 'link-error') {
            insertInternalLink(blockEl, item.type === 'link-note' ? 'note' : 'error');
            return;
          }
          changeBlockType(blockEl, item.type); notifyChange();
        });
        slashItems.push(row);
        slashMenu.appendChild(row);
      });
      if (slashItems.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'notion-slash-empty';
        empty.textContent = '没有匹配的块类型';
        slashMenu.appendChild(empty);
      }
      updateSlashActive();
    }

    function showSlashMenu(blockEl, filter) {
      hideSlashMenu();
      slashTargetBlock = blockEl;
      slashFilter = (filter || '');
      slashActiveIdx = 0;
      slashItems = [];
      slashMenu = document.createElement('div');
      slashMenu.className = 'notion-slash-menu';
      wrapper.appendChild(slashMenu);
      refreshSlashMenu(slashFilter);
      const rect = blockEl.getBoundingClientRect();
      slashMenu.style.top = (rect.bottom - wrapper.getBoundingClientRect().top + 4) + 'px';
      slashMenu.style.left = Math.min(rect.left - wrapper.getBoundingClientRect().left, window.innerWidth - 260) + 'px';
    }

    // 高亮当前键盘选中的菜单项，并滚动到可见区域
    function updateSlashActive() {
      if (!slashMenu) return;
      slashItems.forEach((el, i) => {
        el.classList.toggle('ne-active', i === slashActiveIdx);
      });
      const cur = slashItems[slashActiveIdx];
      if (cur && typeof cur.scrollIntoView === 'function') cur.scrollIntoView({ block: 'nearest' });
    }

    // 键盘操作 slash 菜单：返回 true 表示已处理
    function handleSlashKey(e) {
      if (!slashMenu || !slashMenu.parentElement) return false;
      if (slashItems.length === 0) {
        // 无匹配项时按 Enter/Esc 关闭
        if (e.key === 'Enter' || e.key === 'Escape') { hideSlashMenu(); return true; }
        return false;
      }
      if (e.key === 'ArrowDown') { e.preventDefault(); slashActiveIdx = (slashActiveIdx + 1) % slashItems.length; updateSlashActive(); return true; }
      if (e.key === 'ArrowUp') { e.preventDefault(); slashActiveIdx = (slashActiveIdx - 1 + slashItems.length) % slashItems.length; updateSlashActive(); return true; }
      if (e.key === 'Enter') {
        e.preventDefault();
        const row = slashItems[slashActiveIdx];
        if (row) row.click();
        return true;
      }
      if (e.key === 'Escape') { e.preventDefault(); hideAllMenus(); return true; }
      return false;
    }

    // ===== 插入笔记/错题内部链接 =====
    async function insertInternalLink(blockEl, kind) {
      try {
        let list = [];
        if (kind === 'note') list = await App.DB.getNotes();
        else list = await App.DB.getErrors();
        if (!list || list.length === 0) {
          App.Components.toast('暂无' + (kind === 'note' ? '笔记' : '错题') + '可链接', 'error');
          return;
        }
        const options = list.map(x => ({
          label: App.Utils.truncate(kind === 'note' ? (x.title || '未命名笔记') : (x.question || '未命名错题'), 26),
          value: x.id
        }));
        const sel = await App.Components.actionSheet(options, '选择要链接的' + (kind === 'note' ? '笔记' : '错题'));
        if (!sel) return;
        const target = list.find(x => x.id === sel) || {};
        const label = kind === 'note'
          ? (target.title || '未命名笔记')
          : App.Utils.truncate(target.question || '未命名错题', 22);
        const editable = blockEl.querySelector('.notion-editable');
        if (editable) {
          editable.focus();
          const linkHtml = '<a href="' + kind + '://' + sel + '" class="notion-internal-link">🔗 ' + label + '</a>&nbsp;';
          try { document.execCommand('insertHTML', false, linkHtml); } catch (e) {}
          const be = editable.closest('.notion-block');
          if (be) { const ctx = getBlockCtx(be); if (ctx) syncBlockData(be, ctx.arr[ctx.idx]); }
          notifyChange();
        }
      } catch (e) { console.error('insertInternalLink failed', e); }
    }

    // ===== 选中文本的格式工具栏 =====
    // 浮动格式栏定位：避开 iOS Safari「上/下/对号」透明条（键盘上方约 44px 系统条）
    // 用 visualViewport 计算可视安全区，顶部空间不足时翻转到选区下方
    function repositionFormatBar() {
      if (!formatBar || !formatBar.parentElement) return;
      const range = formatBar._range;
      if (!range) return;
      try {
        const rect = range.getBoundingClientRect();
        const wRect = wrapper.getBoundingClientRect();
        // 可视安全区（屏幕坐标）：顶部 = 键盘/透明条顶部，底部 = 可视区底部
        let safeTop = 0, safeBottom = window.innerHeight;
        if (window.visualViewport) {
          const vv = window.visualViewport;
          safeTop = vv.offsetTop + (_keyboardH > 0 ? 48 : 0);   // Safari 透明条约 44px，留 4px 余量
          safeBottom = vv.offsetTop + vv.height;
        }
        const barH = formatBar.offsetHeight || 40;
        const preferTop = rect.top - barH - 10;   // 首选：选区上方
        const preferBottom = rect.bottom + 10;    // 备选：选区下方
        // 相对 wrapper 的 top
        let top;
        // 选区上方是否在安全区顶部以下（不被透明条/键盘遮挡）？
        if (preferTop >= safeTop) top = preferTop;
        else if (preferBottom + barH <= safeBottom) top = preferBottom;
        else top = Math.max(safeTop, preferTop);  // 都放不下时尽量贴安全区顶部
        formatBar.style.top = (top - wRect.top) + 'px';
        formatBar.style.left = Math.max(0, (rect.left + rect.width / 2 - formatBar.offsetWidth / 2)) + 'px';
      } catch(e) { formatBar.style.top = '40px'; formatBar.style.left = '10px'; }
    }

    function showFormatBar(range) {
      hideFormatBar();
      formatBar = document.createElement('div');
      formatBar.className = 'notion-format-bar';
      formatBar._range = range;
      const fmtTools = [
        { cmd: 'bold', icon: '<b>B</b>', title: '加粗' },
        { cmd: 'italic', icon: '<i>I</i>', title: '斜体' },
        { cmd: 'underline', icon: '<u>U</u>', title: '下划线' },
        { cmd: 'strike', icon: '<s>S</s>', title: '删除线' },
        { cmd: 'code', icon: '<code>&lt;/&gt;</code>', title: '行内代码' },
        { cmd: 'color-red', icon: '<span style="color:#E03131">A</span>', title: '红色文字' },
        { cmd: 'color-yellow', icon: '<span style="color:#F08C00">A</span>', title: '黄色文字' },
        { cmd: 'color-blue', icon: '<span style="color:#1971C2">A</span>', title: '蓝色文字' },
        { cmd: 'color-green', icon: '<span style="color:#2B8A3E">A</span>', title: '绿色文字' },
        { cmd: 'bg-yellow', icon: '<span style="background:#FFE066;padding:0 2px;border-radius:2px;">A</span>', title: '黄色高亮' },
        { cmd: 'bg-gray', icon: '<span style="background:#CED4DA;padding:0 2px;border-radius:2px;">A</span>', title: '灰色高亮' },
        { cmd: 'clear', icon: 'A̶', title: '清除格式' },
      ];
      fmtTools.forEach(t => {
        const btn = document.createElement('button');
        btn.className = 'notion-fmt-btn';
        btn.innerHTML = t.icon;
        btn.title = t.title;
        btn.addEventListener('click', (e) => { e.preventDefault(); applyFormat(t.cmd, range); hideFormatBar(); });
        formatBar.appendChild(btn);
      });
      wrapper.appendChild(formatBar);
      repositionFormatBar();
    }

    function applyFormat(cmd, range) {
      // v8.4.17 选区兜底：工具栏点击后浏览器可能已清掉当前选区，
      // 依次尝试 传入 range → 当前 selection → savedRange（编辑器内最近选区），重建后统一使用
      let sel = null;
      try { sel = window.getSelection(); } catch (e) { /* 忽略 */ }
      let r = range;
      if (!r || !r.toString()) {
        if (sel && sel.rangeCount > 0 && wrapper.contains(sel.getRangeAt(0).commonAncestorContainer)) r = sel.getRangeAt(0);
        else if (savedRange && wrapper.contains(savedRange.commonAncestorContainer)) r = savedRange;
      }
      if (r && r.toString()) {
        try {
          // execCommand 要求编辑区聚焦：移动端格式面板打开后编辑区可能已失焦，先恢复焦点再重建选区
          const startNode = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentNode;
          const editable = startNode && startNode.closest ? startNode.closest('.notion-editable') : null;
          if (editable && document.activeElement !== editable) {
            try { editable.focus({ preventScroll: true }); } catch (e2) { editable.focus(); }
          }
          if (sel) { sel.removeAllRanges(); sel.addRange(r); }
        } catch (e3) { /* 选区重建失败则按原路径处理 */ }
      }
      range = r;
      if (!range || !range.toString()) {
        // 无选区时退化为 execCommand（作用于当前光标）
        if (cmd === 'bold') document.execCommand('bold');
        else if (cmd === 'italic') document.execCommand('italic');
        else if (cmd === 'underline') document.execCommand('underline');
        else if (cmd === 'strike') document.execCommand('strikeThrough');
        syncFocusedBlock();
        notifyChange();
        return;
      }
      switch(cmd) {
        case 'bold': document.execCommand('bold'); break;
        case 'italic': document.execCommand('italic'); break;
        case 'underline': document.execCommand('underline'); break;
        case 'strike': document.execCommand('strikeThrough'); break;
        case 'code': {
          const selText = range.toString();
          if (selText) {
            const code = document.createElement('code');
            code.className = 'notion-inline-code';
            code.textContent = selText;
            range.deleteContents();
            range.insertNode(code);
          }
          break;
        }
        case 'color-red': pushUndo(); wrapSelection(range, 'span', {style:'color:#E03131'}); break;
        case 'color-yellow': pushUndo(); wrapSelection(range, 'span', {style:'color:#F08C00'}); break;
        case 'color-blue': pushUndo(); wrapSelection(range, 'span', {style:'color:#1971C2'}); break;
        case 'color-green': pushUndo(); wrapSelection(range, 'span', {style:'color:#2B8A3E'}); break;
        case 'bg-yellow': pushUndo(); wrapSelection(range, 'span', {style:'background:#FFE066;padding:0 2px;border-radius:2px;'}); break;
        case 'bg-gray': pushUndo(); wrapSelection(range, 'span', {style:'background:#CED4DA;padding:0 2px;border-radius:2px;'}); break;
        case 'highlight': pushUndo(); wrapSelection(range, 'mark', {}); break;
        // 清除格式：删除选中文本上的所有行内标签，仅保留纯文本
        case 'clear': {
          pushUndo();
          const text = range.toString();
          if (text) {
            range.deleteContents();
            const tn = document.createTextNode(text);
            range.insertNode(tn);
            const sel2 = window.getSelection();
            const r2 = document.createRange();
            r2.selectNodeContents(tn); r2.collapse(false);
            sel2.removeAllRanges(); sel2.addRange(r2);
          }
          break;
        }
      }
      syncFocusedBlock();
      notifyChange();
    }

    // 同步当前聚焦块的 html（部分格式路径不触发 input 事件）
    function syncFocusedBlock() {
      if (focusedBlockEl && wrapper.contains(focusedBlockEl)) {
        const fi = parseInt(focusedBlockEl.dataset.index);
        syncBlockData(focusedBlockEl, blocks[fi]);
      }
    }

    function wrapSelection(range, tag, attrs) {
      const el = document.createElement(tag);
      Object.keys(attrs).forEach(k => el.setAttribute(k, attrs[k]));
      try { range.surroundContents(el); } catch(e) {
        const frag = range.extractContents();
        el.appendChild(frag);
        range.insertNode(el);
      }
    }

    // 块手柄菜单（上移/下移/复制/删除/转换类型/缩进）
    function showHandleMenu(blockEl) {
      hideHandleMenu();
      handleMenu = document.createElement('div');
      handleMenu.className = 'notion-handle-menu';
      const ctx = getBlockCtx(blockEl);
      if (!ctx) return;
      const idx = ctx.idx;
      const arr = ctx.arr;
      const parentIdx = ctx.parentIdx;
      const curBlock = arr[idx];

      const addItem = (label, fn, disabled) => {
        const row = document.createElement('div');
        row.className = 'notion-handle-item' + (disabled ? ' disabled' : '');
        row.textContent = label;
        row.addEventListener('click', () => { hideHandleMenu(); if (!disabled) fn(); });
        handleMenu.appendChild(row);
        return row;
      };

      // 1) 转换类型：点击展开/收起子菜单
      const convertRow = document.createElement('div');
      convertRow.className = 'notion-handle-item ne-has-sub';
      convertRow.textContent = '⇄ 转换为…';
      convertRow.addEventListener('click', (e) => {
        e.stopPropagation();
        const sub = handleMenu.querySelector('.notion-convert-sub');
        if (sub) { sub.remove(); return; }
        const subEl = document.createElement('div');
        subEl.className = 'notion-convert-sub';
        const types = [
          { t: 'text', l: '📝 文本' }, { t: 'h1', l: 'H₁ 一级标题' }, { t: 'h2', l: 'H₂ 二级标题' },
          { t: 'h3', l: 'H₃ 三级标题' }, { t: 'h4', l: 'H₄ 四级标题' },
          { t: 'bullet', l: '• 无序列表' }, { t: 'numbered', l: '1. 有序列表' }, { t: 'todo', l: '☐ 待办' },
          { t: 'toggle', l: '▸ 折叠块' }, { t: 'quote', l: '" 引用' }, { t: 'code', l: '</> 代码块' },
          { t: 'image', l: '🖼️ 图片' },
        ];
        types.forEach(x => {
          const it = document.createElement('div');
          it.className = 'notion-handle-item' + (curBlock.type === x.t ? ' ne-current' : '');
          it.textContent = x.l;
          it.addEventListener('click', () => {
            hideHandleMenu();
            changeBlockType(blockEl, x.t); notifyChange();
          });
          subEl.appendChild(it);
        });
        // 子菜单位于转换项下方
        handleMenu.insertBefore(subEl, convertRow.nextSibling);
      });
      handleMenu.appendChild(convertRow);

      // 2) 上移 / 下移（子块在 children 数组内移动）
      addItem('⬆ 上移', () => moveBlock(idx, -1, blockEl), idx === 0);
      addItem('⬇ 下移', () => moveBlock(idx, 1, blockEl), idx === arr.length - 1);

      // 3) 复制块
      addItem('📋 复制块', () => {
        pushUndo();
        const copy = serializeBlocksDeep(curBlock);
        copy.id = genBlockId();
        arr.splice(idx + 1, 0, copy);
        reRender(); notifyChange();
        const el = focusBlockEditable(parentIdx, idx + 1);
        if (el) { el.focus(); placeCaretAtEnd(el); }
      });

      // 4) 缩进控制（子块缩进上限 3）
      addItem('→ 增加缩进', () => {
        pushUndo();
        if (arr[idx].indent < 3) arr[idx].indent++;
        reRender(); notifyChange();
        const fe = focusBlockEditable(parentIdx, idx);
        if (fe) fe.focus();
      });
      addItem('← 减少缩进', () => {
        pushUndo();
        if (arr[idx].indent > 0) arr[idx].indent--;
        reRender(); notifyChange();
        const fe = focusBlockEditable(parentIdx, idx);
        if (fe) fe.focus();
      });

      // 5) 删除块
      addItem('🗑 删除块', () => deleteBlock(idx, blockEl));

      const rect = blockEl.getBoundingClientRect();
      wrapper.appendChild(handleMenu);
      handleMenu.style.top = (rect.top - wrapper.getBoundingClientRect().top + 4) + 'px';
      handleMenu.style.left = (rect.left - wrapper.getBoundingClientRect().left + 18) + 'px';
    }

    // 生成块唯一 id
    function genBlockId() {
      return 'b' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    }

    function applyBlockTypeToFocused(type) {
      let target = focusedBlockEl;
      if (!target || !wrapper.contains(target)) {
        const all = blocksContainer.querySelectorAll('.notion-block');
        if (!all.length) return;
        target = all[all.length - 1];
        const ed = target.querySelector('.notion-editable');
        if (ed) ed.focus();
      }
      if (type === 'divider' || type === 'table') {
        const ctx = getBlockCtx(target);
        if (!ctx) return;
        const idx = ctx.idx;
        const arr = ctx.arr;
        pushUndo();
        if (type === 'divider') arr.splice(idx + 1, 0, createBlock('divider', ''));
        else { const tb = createBlock('table', ''); tb.tableData = [['列1','列2'],['','']]; arr.splice(idx + 1, 0, tb); }
        reRender(); notifyChange();
        return;
      }
      changeBlockType(target, type);
      notifyChange();
    }

    // ===== 创建块 DOM =====
    // ===== 【修复1】块定位工具：根据块 DOM 找到它在 blocks 树中的位置 =====
    // 顶层块：data-index 指向主 blocks 数组；toggle 子块：data-pidx 指向父 toggle 在主数组的索引，data-index 指向 children 内的索引
    function getBlockCtx(blockEl) {
      const el = blockEl.closest ? blockEl.closest('.notion-block') : blockEl;
      if (!el) return null;
      const pidx = parseInt(el.dataset.pidx);
      if (!isNaN(pidx) && blocks[pidx] && blocks[pidx].type === 'toggle') {
        const parent = blocks[pidx];
        if (!Array.isArray(parent.children)) parent.children = [];
        return { arr: parent.children, idx: parseInt(el.dataset.index), parent, el, isChild: true, parentIdx: pidx };
      }
      return { arr: blocks, idx: parseInt(el.dataset.index), parent: null, el, isChild: false, parentIdx: null };
    }
    // 聚焦指定位置的块（顶层：pidx=null；子块：pidx=父 toggle 索引）
    function focusBlockEditable(pidx, index) {
      const sel = (pidx === null || pidx === undefined)
        ? `.notion-block[data-index="${index}"] .notion-editable`
        : `.notion-block[data-pidx="${pidx}"][data-index="${index}"] .notion-editable`;
      const el = blocksContainer.querySelector(sel);
      if (el) { el.focus(); placeCaretAtEnd(el); }
      return el;
    }

    // v8.4.18 E：listStart=true 表示该 numbered 块是「列表段起点」（前一块不是 numbered，如空白行后），CSS 侧 counter-reset 重新从 1 编号
    function renderBlock(block, index, parentIdx, listStart) {
      const el = document.createElement('div');
      el.className = 'notion-block notion-block--' + block.type + (parentIdx !== undefined ? ' notion-block--child' : '') + (listStart ? ' is-list-start' : '');
      el.dataset.index = index;
      if (parentIdx !== undefined) el.dataset.pidx = parentIdx;   // 子块标记父 toggle
      if (block.indent > 0) el.style.paddingLeft = (24 * block.indent) + 'px';

      const handle = document.createElement('div');
      handle.className = 'notion-block__handle';
      // 循环形式图标（环形箭头）
      handle.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12a8 8 0 1 1-2.34-5.66"/><polyline points="21 3 21 8 16 8"/></svg>`;
      handle.addEventListener('click', (e) => {

        e.stopPropagation();
        // 刚拖拽过（本次按下发生过移动）：不弹菜单，由拖拽逻辑处理
        if (dragJustMoved) { dragJustMoved = false; return; }
        // 状态机：点击手柄 → 选中该块（状态 3）并切换菜单（状态 4 开/关）
        selectBlock(el);
        if (handleMenu && handleMenu.parentElement) {
          // 菜单已开：再点手柄 → 关闭菜单回到状态 3
          hideHandleMenu();
        } else {
          showHandleMenu(el);
        }
      });
      // 拖拽排序：按住手柄上下拖动，显示占位线，松开交换位置（仅顶层块；toggle 子块不支持拖拽）
      handle.addEventListener('pointerdown', (e) => {
        const ed = el.querySelector('.notion-editable');
        if (ed && document.activeElement === ed) return; // 输入中不拖拽
        if (e.button !== 0 && e.pointerType === 'mouse') return;
        if (parentIdx !== undefined) return;   // 子块：不拖拽（保持默认行为，弹菜单）
        e.preventDefault();
        e.stopPropagation();
        hideAllMenus();
        startBlockDrag(el, e);
      });
      el.appendChild(handle);

      const content = document.createElement('div');
      content.className = 'notion-block__content';

      if (block.type === 'divider') {
        content.innerHTML = '<hr class="notion-divider">';
      } else if (block.type === 'todo') {
        const cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.className = 'notion-todo-cb';
        cb.checked = !!block.checked;
        cb.addEventListener('change', () => { block.checked = cb.checked; syncBlockData(el, block); notifyChange(); });
        content.appendChild(cb);
        content.appendChild(createEditable(block));
      } else if (block.type === 'table') {
        renderTableBlock(content, block);
      } else if (block.type === 'code') {
        const pre = document.createElement('pre');
        pre.className = 'notion-code-block';
        const ce = createEditable(block);
        ce.className = 'notion-code-text';
        pre.appendChild(ce);
        content.appendChild(pre);
      } else if (block.type === 'callout') {
        const box = document.createElement('div');
        box.className = 'notion-callout';
        const emoji = document.createElement('span');
        emoji.className = 'notion-callout__emoji';
        emoji.textContent = block.emoji || '💡';
        emoji.title = '点击切换图标';
        emoji.addEventListener('click', () => {
          const pick = prompt('输入提示图标（emoji）：', emoji.textContent);
          if (pick && pick.trim()) { block.emoji = pick.trim().slice(0,2); emoji.textContent = block.emoji; notifyChange(); }
        });
        box.appendChild(emoji);
        box.appendChild(createEditable(block));
        content.appendChild(box);
      } else if (block.type === 'image') {
        renderImageBlock(content, block);
      } else if (block.type === 'toggle') {
        // 【修复1】toggle 折叠块：标题行 + 子块容器（children 递归渲染）
        const box = document.createElement('div');
        box.className = 'notion-toggle';
        // 数据迁移：旧数据无 children 时，把 html/content 作为文本子块兜底
        if (!Array.isArray(block.children)) {
          block.children = [];
          const legacyText = block.html ? stripHtml(block.html) : (block.content || '');
          if (legacyText && legacyText.trim()) {
            const nb = createBlock('text', legacyText);
            block.children.push(nb);
          }
          block.html = '';
          block.content = '';
        }
        // 标题行：箭头（左侧 24px 点击区）+ 可编辑标题
        const header = document.createElement('div');
        header.className = 'notion-toggle__header';
        const arrowZone = document.createElement('span');
        arrowZone.className = 'notion-toggle__arrow-zone';
        const arrow = document.createElement('span');
        arrow.className = 'notion-toggle__arrow';
        arrow.textContent = block.collapsed ? '▶' : '▼';   // 向右折叠 / 向下展开
        arrowZone.appendChild(arrow);
        const summary = document.createElement('div');
        summary.className = 'notion-toggle__summary';
        summary.setAttribute('placeholder', '折叠标题...');
        summary.textContent = block.summary || block.content || '';
        summary.contentEditable = true;
        summary.addEventListener('input', () => { block.summary = summary.textContent; notifyChange(); });
        summary.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && !e.isComposing) {
            e.preventDefault();
            if (e.shiftKey) { insertSoftBreak(summary); return; }   // Shift+Enter 标题内换行
            // 标题行 Enter：展开并在 children 末尾新建文本子块
            pushUndo();
            block.collapsed = false;
            arrow.textContent = '▼';
            childrenWrap.style.display = 'block';
            if (!Array.isArray(block.children)) block.children = [];
            const nb = createBlock('text', '');
            block.children.push(nb);
            reRender();
            const newEl = blocksContainer.querySelector(`[data-pidx="${index}"][data-index="${block.children.length - 1}"] .notion-editable`);
            if (newEl) { newEl.focus(); placeCaretAtEnd(newEl); }
            notifyChange();
          }
        });
        // 点击箭头区域（约 24px 宽）切换折叠/展开
        arrowZone.addEventListener('click', (e) => {
          e.stopPropagation();
          block.collapsed = !block.collapsed;
          arrow.textContent = block.collapsed ? '▶' : '▼';
          childrenWrap.style.display = block.collapsed ? 'none' : 'block';
          notifyChange();
        });
        header.appendChild(arrowZone);
        header.appendChild(summary);
        // 子块容器：左侧 24px 缩进 + 浅灰左边线
        const childrenWrap = document.createElement('div');
        childrenWrap.className = 'notion-toggle__children';
        if (block.collapsed) childrenWrap.style.display = 'none';
        // 递归渲染 children 中的每个子块（复用 renderBlock，带父索引标记）
        (block.children || []).forEach((child, ci) => {
          const cStart = child.type === 'numbered' && (ci === 0 || !block.children[ci - 1] || block.children[ci - 1].type !== 'numbered');
          childrenWrap.appendChild(renderBlock(child, ci, index, cStart));
        });
        box.appendChild(header);
        box.appendChild(childrenWrap);
        content.appendChild(box);
      } else {
        content.appendChild(createEditable(block));
      }

      el.appendChild(content);
      return el;
    }

    // ===== 图片块渲染（空占位 / 已加载 + caption + 对齐 + 双击预览 + 加载失败兜底） =====
    function renderImageBlock(content, block) {
      const wrap = document.createElement('div');
      wrap.className = 'notion-image';
      // 图片块无 contenteditable：自身可聚焦，支持 Enter 新建块 / Backspace 删除（选中态下）
      wrap.tabIndex = -1;
      wrap.addEventListener('keydown', (e) => {
        const be = wrap.closest('.notion-block');
        if (!be || !be.classList.contains('is-selected')) return;
        if (e.key === 'Enter' && !e.isComposing) {
          e.preventDefault();
          pushUndo();
          const ctx = getBlockCtx(be);
          if (ctx) {
            const nb = createBlock('text', '');
            nb.indent = ctx.arr[ctx.idx].indent || 0;
            ctx.arr.splice(ctx.idx + 1, 0, nb);
            reRender();
            const el = focusBlockEditable(ctx.parentIdx, ctx.idx + 1);
            if (el) el.focus();
          }
          notifyChange();
        } else if (e.key === 'Backspace' || e.key === 'Delete') {
          e.preventDefault();
          deleteBlock(parseInt(be.dataset.index), be);
        } else if (e.key === 'Escape') {
          e.preventDefault();
          clearSelected();
        }
      });
      // 点击图片块空白区域 → 选中（保持与其他块一致的选中交互）
      wrap.addEventListener('mousedown', (e) => {
        if (e.target.closest('.notion-image__url-input') || e.target.closest('.notion-image__url-btn')) return;
        if (e.target === wrap || e.target.closest('.notion-image__caption') || e.target.closest('.notion-image__align-bar')) {
          e.preventDefault();
          const be = wrap.closest('.notion-block');
          if (be) { selectBlock(be); wrap.focus(); }
        }
      });

      const data = block.imgData || {};
      if (!data.src) {
        // —— 空图片块：点击上传 / 拖入 / 粘贴 / 输入 URL ——
        const placeholder = document.createElement('div');
        placeholder.className = 'notion-image__placeholder';
        placeholder.innerHTML = `
          <div class="notion-image__ph-icon">🖼️</div>
          <div class="notion-image__ph-title">拖入图片、粘贴或点击上传</div>
          <div class="notion-image__ph-sub">支持 JPG、PNG、GIF、WebP</div>
          <div class="notion-image__ph-or">──────── 或 ────────</div>
        `;
        const urlRow = document.createElement('div');
        urlRow.className = 'notion-image__url-row';
        const urlInput = document.createElement('input');
        urlInput.type = 'text';
        urlInput.className = 'notion-image__url-input';
        urlInput.placeholder = '输入图片链接...';
        urlInput.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && !e.isComposing) {
            e.preventDefault();
            const v = urlInput.value.trim();
            if (!v) return;
            pushUndo();
            block.imgData = { src: v, alt: '', caption: '', width: '100%', align: 'center' };
            reRender(); notifyChange();
          }
        });
        const urlBtn = document.createElement('button');
        urlBtn.type = 'button';
        urlBtn.className = 'notion-image__url-btn';
        urlBtn.textContent = '嵌入';
        urlBtn.addEventListener('click', () => {
          const v = urlInput.value.trim();
          if (!v) return;
          pushUndo();
          block.imgData = { src: v, alt: '', caption: '', width: '100%', align: 'center' };
          reRender(); notifyChange();
        });
        urlRow.appendChild(urlInput);
        urlRow.appendChild(urlBtn);

        // 点击占位 → 唤起系统文件选择器（移动端自动调起相册/拍照）
        const fileInput = document.createElement('input');
        fileInput.type = 'file';
        fileInput.accept = 'image/*';
        fileInput.style.display = 'none';
        const pickFile = () => fileInput.click();
        placeholder.addEventListener('click', (e) => {
          e.stopPropagation();
          if (e.target.closest('.notion-image__url-input') || e.target.closest('.notion-image__url-btn')) return;
          pickFile();
        });
        fileInput.addEventListener('change', () => {
          const f = fileInput.files && fileInput.files[0];
          fileInput.value = '';
          if (f) handleImageFile(f, block);
        });
        wrap.appendChild(placeholder);
        wrap.appendChild(urlRow);
        wrap.appendChild(fileInput);
        content.appendChild(wrap);
        return;
      }

      // —— 已加载图片 ——
      // 对齐
      wrap.style.textAlign = data.align || 'center';
      // 图片容器（宽度控制 + 双击预览 + 拖拽角标）
      const imgBox = document.createElement('div');
      imgBox.className = 'notion-image__box' + (data.align === 'left' ? ' align-left' : data.align === 'right' ? ' align-right' : '');
      const imgWrap = document.createElement('div');
      imgWrap.className = 'notion-image__imgwrap';
      imgWrap.style.width = data.width || '100%';
      imgWrap.style.maxWidth = '100%';
      imgWrap.style.margin = data.align === 'left' ? '0 auto 0 0' : data.align === 'right' ? '0 0 0 auto' : '0 auto';

      const img = document.createElement('img');
      img.className = 'notion-image__img';
      img.src = data.src;
      img.alt = data.alt || '';
      img.draggable = false;   // 避免与块拖拽冲突
      // 加载失败：占位 + 重载 + 允许改链接
      img.addEventListener('error', () => {
        imgWrap.classList.add('is-error');
        imgWrap.innerHTML = `
          <div class="notion-image__err">
            <div class="notion-image__err-icon">🖼️</div>
            <div class="notion-image__err-text">图片加载失败</div>
            <div class="notion-image__err-url">${App.Utils._escapeHtml(data.src)}</div>
            <button type="button" class="notion-image__err-btn">重新加载</button>
          </div>
        `;
        const retryBtn = imgWrap.querySelector('.notion-image__err-btn');
        if (retryBtn) retryBtn.addEventListener('click', () => {
          imgWrap.classList.remove('is-error');
          imgWrap.innerHTML = '';
          imgWrap.appendChild(img);
          img.src = data.src;
        });
      });
      // 单击：选中块（不放大）
      img.addEventListener('click', (e) => {
        e.stopPropagation();
        const be = img.closest('.notion-block');
        if (be) selectBlock(be);
      });
      // 双击：全屏预览
      img.addEventListener('dblclick', (e) => {
        e.stopPropagation();
        e.preventDefault();
        openImagePreview(data.src, data.alt || '');
      });
      imgWrap.appendChild(img);
      imgBox.appendChild(imgWrap);

      // caption（图片下方说明，点击可编辑）
      const caption = document.createElement('div');
      caption.className = 'notion-image__caption';
      caption.textContent = data.caption || '';
      caption.contentEditable = true;
      caption.addEventListener('input', () => {
        block.imgData = block.imgData || {};
        block.imgData.caption = caption.textContent;
        notifyChange();
      });
      // 编辑 caption 时防止触发块拖拽/选中
      caption.addEventListener('mousedown', (e) => e.stopPropagation());
      imgBox.appendChild(caption);

      // 对齐切换（左/中/右）
      const alignBar = document.createElement('div');
      alignBar.className = 'notion-image__align-bar';
      [['left','⬅'],['center','⬌'],['right','➡']].forEach(([align, ic]) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'notion-image__align-btn' + ((data.align || 'center') === align ? ' is-active' : '');
        b.textContent = ic;
        b.title = align === 'left' ? '左对齐' : align === 'right' ? '右对齐' : '居中';
        b.addEventListener('click', (e) => {
          e.stopPropagation();
          pushUndo();
          block.imgData = block.imgData || {};
          block.imgData.align = align;
          reRender(); notifyChange();
        });
        alignBar.appendChild(b);
      });
      imgBox.appendChild(alignBar);

      content.appendChild(imgBox);
      content.appendChild(wrap);
    }

    // 处理选中的图片文件：大小校验 → Base64 → 写入块
    function handleImageFile(file, block) {
      if (!file || !/^image\//.test(file.type)) {
        App.Components.toast('仅支持图片格式', 'error');
        return;
      }
      // Base64 过大（>2MB）提示（localStorage 上限 5MB，留余量）
      if (file.size > 2 * 1024 * 1024) {
        App.Components.toast('图片过大（>2MB），建议压缩或使用图床链接', 'error');
        return;
      }
      const reader = new FileReader();
      reader.onload = () => {
        pushUndo();
        block.imgData = { src: reader.result, alt: '', caption: '', width: '100%', align: 'center' };
        reRender(); notifyChange();
      };
      reader.onerror = () => App.Components.toast('图片读取失败，请重试', 'error');
      reader.readAsDataURL(file);
    }

    // 全屏图片预览（遮罩 + 居中 + 点击关闭；双击图片触发）
    function openImagePreview(src, alt) {
      const overlay = document.createElement('div');
      overlay.className = 'notion-image-preview';
      const img = document.createElement('img');
      img.className = 'notion-image-preview__img';
      img.src = src;
      img.alt = alt || '';
      const close = () => overlay.remove();
      overlay.appendChild(img);
      overlay.addEventListener('click', (e) => { if (e.target === overlay || e.target === img) close(); });
      document.getElementById('modal-container').appendChild(overlay);
      requestAnimationFrame(() => overlay.classList.add('is-visible'));
    }


    function renderInlineMarkdown(text) {
      if (!text) return '';
      let html = text
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')  // 先转义 HTML 实体
        // 行内代码（必须在最前面，避免内部格式被处理）
        .replace(/`([^`\n]+)`/g, '<code class="notion-inline-code">$1</code>')
        // 块级公式 $$...$$
        .replace(/\$\$([\s\S]+?)\$\$/g, (m, latex) => '<div class="mformula mformula--block" contenteditable="false" data-latex="' + encodeURIComponent(latex) + '">' + App.Utils.renderLatex(latex) + '</div>')
        // 行内公式 $...$（至少 2 个字符，避免误伤货币/编号）
        .replace(/\$([^\$\n]{2,})\$/g, (m, latex) => '<span class="mformula" contenteditable="false" data-latex="' + encodeURIComponent(latex) + '">' + App.Utils.renderLatex(latex) + '</span>')
        // 图片 ![alt](url)
        .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:100%;border-radius:4px;">')
        // 链接 [text](url)
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
        // 高亮 ==text==
        .replace(/==(.*?)==/g, '<mark class="notion-highlight">$1</mark>')
        // 删除线 ~~text~~
        .replace(/~~(.*?)~~/g, '<s>$1</s>')
        // 下划线 [u]text[/u]
        .replace(/\[u\]([\s\S]*?)\[\/u\]/g, '<u>$1</u>')
        // 颜色 [c=#xxx]text[/c]
        .replace(/\[c=(#[0-9a-fA-F]{3,6}|rgb\([^)]+\))\]([\s\S]*?)\[\/c\]/g, '<span style="color:$1">$2</span>')
        // 加粗 **text** 或 __text__
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/__(.+?)__/g, '<strong>$1</strong>')
        // 斜体 *text* 或 _text_（不与加粗重叠：排除已处理的 **）
        .replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>').replace(/(?<![A-Za-z0-9_])_([^_\n]+)_(?![A-Za-z0-9_])/g, '<em>$1</em>')
        // 块内换行（Enter 软回车）保留为 <br>
        .replace(/\n/g, '<br>');
      return html;
    }

    // ===== 粘贴拦截：将粘贴的 Markdown 文本解析为结构化块 + 行内渲染 =====
    function setupPasteHandler(el) {
      el.addEventListener('paste', (e) => {
        const clipboardData = e.clipboardData || window.clipboardData;
        if (!clipboardData) return;
        let text = clipboardData.getData('text/plain');
        // iPad/富文本复制时 text/plain 可能为空：从 HTML 提取纯文本（保留块级换行）
        if (!text) {
          const htmlText = clipboardData.getData('text/html');
          if (htmlText) {
            const tmp = document.createElement('div');
            tmp.innerHTML = htmlText;
            tmp.querySelectorAll('br').forEach(br => br.replaceWith('\n'));
            tmp.querySelectorAll('p,div,li,h1,h2,h3,h4,h5,h6,tr,blockquote,pre').forEach(n => {
              n.appendChild(document.createTextNode('\n'));
            });
            text = (tmp.textContent || '').replace(/\u200b/g, '');
          }
        }
        // 剪贴板包含图片文件 → 在光标处创建图片块（优先于文本判断；非图片文件拒绝）
        const imgFile = Array.from(clipboardData.items || []).map(it => it.kind === 'file' ? it.getAsFile() : null).find(Boolean);
        if (imgFile) {
          e.preventDefault();
          if (!/^image\//.test(imgFile.type)) { App.Components.toast('仅支持图片格式', 'error'); return; }
          const focused = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
          const pctx = focused ? getBlockCtx(focused) : null;
          const arr = pctx ? pctx.arr : blocks;
          const insertIdx = pctx ? pctx.idx : blocks.length - 1;
          const parentIdx = pctx ? pctx.parentIdx : null;
          const nb = createBlock('image', '');
          if (parentIdx !== null) nb.indent = (arr[insertIdx] || {}).indent || 0;
          pushUndo();
          arr.splice(insertIdx, 0, nb);
          reRender();
          handleImageFile(imgFile, nb);
          return;
        }

        if (!text) return;

        // 如果粘贴的是多行 Markdown（含块级语法），替换当前块为解析后的多块
        const lines = text.split('\n');
        if (lines.length > 1 || /^#{1,4}\s|^- \[[ x]\]|^- |^\d+\.\s|^> |^```|^---/.test(text.trim())) {
          e.preventDefault();
          const focused = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
          const pctx = focused ? getBlockCtx(focused) : null;
          const arr = pctx ? pctx.arr : blocks;
          const insertIdx = pctx ? pctx.idx : blocks.length - 1;
          const parentIdx = pctx ? pctx.parentIdx : null;
          const newBlocks = parseMarkdownToBlocks(text);
          if (newBlocks.length > 0) {
            // 对新块的 content 也做行内渲染
            newBlocks.forEach(b => { if (!b.html && b.content) b.html = renderInlineMarkdown(b.content); });
            pushUndo();
            arr.splice(insertIdx, 1, ...newBlocks);
            reRender();
            // 聚焦到最后一个新插入的块
            const lastIdx = insertIdx + newBlocks.length - 1;
            const lastEl = wrapper.querySelector(
              (parentIdx === null ? '.notion-block[data-index="' : '.notion-block[data-pidx="' + parentIdx + '"][data-index="') + lastIdx + '"] .notion-editable'
            );
            if (lastEl) { lastEl.focus(); placeCaretAtEnd(lastEl); }
            notifyChange();
            updateFooter();
          }
          return;
        }

        // 单行粘贴：作为行内内容插入，渲染 Markdown 格式
        // 让浏览器先执行默认粘贴（到光标位置），然后在 input 事件中重新渲染
        // 通过延时在默认粘贴完成后重新渲染当前块
        setTimeout(() => {
          const be = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
          if (!be) return;
          const pctx = getBlockCtx(be);
          if (!pctx) return;
          const idx = pctx.idx;
          const arr = pctx.arr;
          const editable = be.querySelector('.notion-editable');
          if (!editable) return;
          // 获取纯文本后用行内 Markdown 重新设置 innerHTML
          const plainText = editable.textContent || '';
          if (plainText !== (arr[idx].content || '')) {
            arr[idx].content = plainText;
            arr[idx].html = renderInlineMarkdown(plainText);
            // 保存光标位置
            const sel = window.getSelection();
            let offset = 0;
            if (sel && sel.rangeCount > 0) {
              const range = sel.getRangeAt(0);
              const pre = range.startContainer;
              offset = pre.nodeType === 3 ? range.startOffset : 0;
            }
            editable.innerHTML = arr[idx].html || '';
            // 尝试恢复光标
            try {
              const newRange = document.createRange();
              const node = editable.firstChild || editable;
              newRange.setStart(node, Math.min(offset, node.textContent.length));
              newRange.collapse(true);
              sel.removeAllRanges();
              sel.addRange(newRange);
            } catch (err) { /* 光标恢复失败时静默 */ }
          }
          notifyChange();
          updateFooter();
        }, 10);
      });
    }

    function createEditable(block) {
      const div = document.createElement('div');
      div.className = 'notion-editable';
      div.contentEditable = true;
      if (placeholder !== false) div.dataset.placeholder = placeholder || '输入内容，输入 / 唤起命令...';
      if (block.html) div.innerHTML = block.html;
      else div.innerHTML = renderInlineMarkdown(block.content || '');

      div.addEventListener('focus', () => {
        focusedBlockEl = div.closest('.notion-block');
        if (focusedBlockEl) {
          focusedBlockEl.classList.add('is-editing');
          onBlockFocus(focusedBlockEl);   // 状态 2：进入编辑，取消选中（手柄隐藏）
        }
      });
      div.addEventListener('blur', () => {
        const be = div.closest('.notion-block');
        if (be) be.classList.remove('is-editing');
      });
      div.addEventListener('input', () => {
        noteEditForUndo();
        const be = div.closest('.notion-block');
        const ctx = getBlockCtx(be);
        if (ctx) syncBlockData(be, ctx.arr[ctx.idx]);
        updateFooter();
        notifyChange();
        const text = div.textContent;
        // 只要文本中存在「/」就唤起/刷新菜单，按「/」之后的输入过滤（支持块中间输入 /）
        const lastSlash = text.lastIndexOf('/');
        if (lastSlash >= 0) {
          const after = text.slice(lastSlash + 1);
          if (slashMenu && slashMenu.parentElement) refreshSlashMenu(after);
          else showSlashMenu(be, after);
        } else {
          hideSlashMenu();
        }
        setSaveStatus('编辑中…');
      });
      div.addEventListener('keydown', (e) => {
        const be = div.closest('.notion-block');
        const ctx = getBlockCtx(be);
        const idx = ctx ? ctx.idx : parseInt(be.dataset.index);
        // ESC：状态机流转（编辑→选择→取消）；先于斜杠菜单处理（菜单关闭后进入选择）
        if (e.key === 'Escape') {
          e.preventDefault();
          if (handleBlockEscape()) return;
        }
        // 斜杠菜单键盘导航优先（上下选择/回车确认/Esc 关闭）
        if (handleSlashKey(e)) return;
        // 【下键/上键】光标已到本块行尾（下键）或行首（上键）时，跳到下一块/上一块
        if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && !e.shiftKey) {
          let shouldJump = false;
          const sel = window.getSelection();
          if (sel && sel.rangeCount > 0) {
            const range = sel.getRangeAt(0);
            const caretOffset = range.startOffset;
            const totalLen = div.textContent.length;
            if (e.key === 'ArrowDown' && caretOffset >= totalLen) shouldJump = true;
            if (e.key === 'ArrowUp' && caretOffset <= 0) shouldJump = true;
          } else {
            // 无选区（jsdom/失焦边缘）：默认视为位于行尾，直接跳块
            shouldJump = true;
          }
          if (shouldJump) {
            e.preventDefault();
            // 计算目标：顶层块按 data-index，toggle 子块按 data-pidx/data-index
            const allEd = Array.from(blocksContainer.querySelectorAll('.notion-editable'));
            const cur = div;
            const pos = allEd.indexOf(cur);
            if (pos >= 0) {
              const target = e.key === 'ArrowDown' ? allEd[pos + 1] : allEd[pos - 1];
              if (target) { target.focus(); placeCaretAtEnd(target); }
            }
            return;
          }
          // 不在边界：交给默认行为（光标在行内上下移动）
        }
        if (e.key === 'Tab') {
          // Tab 增加缩进（子块/顶层块均有效），Shift+Tab 减少缩进
          e.preventDefault();
          if (ctx) {
            pushUndo();
            if (!e.shiftKey && ctx.arr[idx].indent < 3) ctx.arr[idx].indent++;
            else if (e.shiftKey && ctx.arr[idx].indent > 0) ctx.arr[idx].indent--;
            reRender(); notifyChange();
            const fe = focusBlockEditable(ctx.parentIdx, idx);
            if (fe) fe.focus();
          }
          return;
        }
        if (e.key === 'Enter' && !e.isComposing) {
          e.preventDefault();
          pushUndo();
          if (e.shiftKey) {
            // Shift+Enter = 块内软回车（插入 <br>）
            insertSoftBreak(div);
          } else {
            // Enter = 拆分/新建块（顶层与 toggle 子块通用）
            splitBlock(idx, div);
          }
        }
        else if (e.key === 'Backspace') {
          if (div.textContent === '') { e.preventDefault(); pushUndo(); deleteBlock(idx, be); return; }
          // v8.4.18 H：光标在块最前面 + 格式块（列表/标题/待办/引用）→ 按删除键降级为普通文本（内容保留）
          const selB = window.getSelection();
          const rgB = (selB && selB.rangeCount > 0) ? selB.getRangeAt(0) : null;
          const atStart = rgB && selB.isCollapsed && rgB.startOffset === 0 &&
            (rgB.startContainer === div || rgB.startContainer === div.firstChild);
          if (atStart && ctx && ['bullet','numbered','todo','quote','heading1','heading2','heading3','heading4'].indexOf(ctx.arr[idx].type) >= 0) {
            e.preventDefault(); pushUndo();
            ctx.arr[idx].type = 'text';
            reRender();
            const elB = focusBlockEditable(ctx.parentIdx, idx);
            if (elB) { elB.focus(); placeCaretAtEnd(elB); }
            notifyChange();
            return;
          }
        }
        else if (e.key === '/' && div.textContent === '') { setTimeout(() => showSlashMenu(be, ''), 10); }
        else if (e.key === 'Escape') { hideAllMenus(); div.blur(); }
        else if ((e.metaKey || e.ctrlKey) && (e.key === 'z' || e.key === 'Z')) {
          e.preventDefault();
          if (e.shiftKey) redo(); else undo();
        }
        else if ((e.metaKey || e.ctrlKey) && (e.key === 'y' || e.key === 'Y')) { e.preventDefault(); redo(); }
        else if ((e.metaKey || e.ctrlKey) && e.key === 'b') { e.preventDefault(); applyFormat('bold'); }
        else if ((e.metaKey || e.ctrlKey) && e.key === 'i') { e.preventDefault(); applyFormat('italic'); }
        else if ((e.metaKey || e.ctrlKey) && e.key === 'u') { e.preventDefault(); applyFormat('underline'); }
      });
      div.addEventListener('mouseup', () => {
        const sel = window.getSelection();
        if (sel && sel.rangeCount > 0 && !sel.isCollapsed && sel.toString().trim()) setTimeout(() => showFormatBar(sel.getRangeAt(0)), 50);
        else hideFormatBar();
      });
      div.addEventListener('blur', () => {
        setTimeout(() => { hideSlashMenu(); }, 150);
        const be = div.closest('.notion-block');
        if (!be) return;
        const ctx = getBlockCtx(be);
        const idx = ctx ? ctx.idx : parseInt(be.dataset.index);
        const txt = getBlockText(div);
        if (txt !== (ctx.arr[idx].content || '')) ctx.arr[idx].content = txt;
        // 若块内已有富文本（strong/em/span[style]/b/i/u/font/链接/<br> 等全部形态），保留原始 HTML，
        // 避免 iPad 用 <span style="..."> 实现的加粗/颜色/下划线/高亮在失焦时被 innerText 剥掉格式
        if (div.querySelector('strong,em,code,a,mark,s,br,img,b,i,u,font,span[style]')) {
          ctx.arr[idx].html = div.innerHTML;
        } else {
          const rendered = renderInlineMarkdown(txt);
          if (rendered !== div.innerHTML) { ctx.arr[idx].html = rendered; div.innerHTML = rendered; }
          else ctx.arr[idx].html = rendered;
        }
      });
      return div;
    }

    function renderTableBlock(container, block) {
      if (!block.tableData) block.tableData = [['列1','列2'],['','']];
      const tableWrap = document.createElement('div');
      tableWrap.className = 'notion-table-wrap';
      const table = document.createElement('table');
      table.className = 'notion-table';
      block.tableData.forEach((row, ri) => {
        const tr = document.createElement('tr');
        row.forEach((cell, ci) => {
          const td = document.createElement('td');
          td.contentEditable = true;
          td.textContent = cell || '';
          td.addEventListener('input', () => { block.tableData[ri][ci] = td.textContent; notifyChange(); });
          tr.appendChild(td);
        });
        const delRowBtn = document.createElement('button');
        delRowBtn.className = 'notion-table-btn';
        delRowBtn.textContent = '−';
        delRowBtn.title = '删除此行';
        delRowBtn.addEventListener('click', () => { if (block.tableData.length > 1) { block.tableData.splice(ri, 1); reRender(); notifyChange(); } });
        const delCell = document.createElement('td');
        delCell.appendChild(delRowBtn);
        tr.appendChild(delCell);
        table.appendChild(tr);
      });
      const addRowTr = document.createElement('tr');
      const addRowTd = document.createElement('td');
      addRowTd.colSpan = block.tableData[0].length + 1;
      const addRowBtn = document.createElement('button');
      addRowBtn.className = 'notion-table-add-btn';
      addRowBtn.textContent = '+ 新增一行';
      addRowBtn.addEventListener('click', () => { block.tableData.push(new Array(block.tableData[0].length).fill('')); reRender(); notifyChange(); });
      addRowTd.appendChild(addRowBtn);
      addRowTr.appendChild(addRowTd);
      table.appendChild(addRowTr);
      tableWrap.appendChild(table);
      container.appendChild(tableWrap);
    }

    function syncBlockData(blockEl, block) {
      if (!block) return;
      // toggle 本身：标题由 summary 单独同步，children 由子块各自同步
      if (block.type === 'toggle') return;
      if (block.type === 'divider' || block.type === 'table' || block.type === 'image') return;
      const editable = blockEl.querySelector('.notion-editable');
      if (!editable) return;
      block.content = getBlockText(editable);
      block.html = editable.innerHTML;
    }

    // v8.4.18 F：有序列表「新段起点」自动延续上一有序列表段的缩进
    // （空白行后重新开始的列表，缩进自动继承上一列表，无需手动按 Tab）
    function inheritListIndent(ctx, idx) {
      const arr = ctx.arr, b = arr[idx];
      if (!b || b.type !== 'numbered' || (b.indent || 0) > 0) return;   // 仅有序列表、且自身无缩进时
      const prev = arr[idx - 1];
      if (prev && prev.type === 'numbered') return;                     // 同段内（回车新建项）缩进已由 splitBlock 继承
      for (let i = idx - 1; i >= 0; i--) {                              // 新段起点：向前找最近的 numbered 块继承缩进
        const p = arr[i];
        if (p && p.type === 'numbered') { if (p.indent) b.indent = p.indent; break; }
      }
    }

    function changeBlockType(blockEl, newType) {
      const ctx = getBlockCtx(blockEl);
      if (!ctx) return;
      const idx = ctx.idx;
      const oldBlock = ctx.arr[idx];
      pushUndo();
      // 优先读取当前 DOM 文本，避免输入事件未同步导致内容丢失（生成空标题/空块）
      const _ed = blockEl.querySelector('.notion-editable');
      let carry = (_ed ? getBlockText(_ed) : (oldBlock.content || '')).replace(/^\/\S*$/, '');
      // 剥离已输入的 markdown 块级前缀，避免「### 标题」转 h3 后导出成「### ### 标题」
      carry = carry.replace(/^(#{1,4}|- |\* |\d+\. |> )\s*/, '').trim();
      ctx.arr[idx] = createBlock(newType, carry);
      ctx.arr[idx].id = oldBlock.id || ctx.arr[idx].id;   // 转换保留原 id
      ctx.arr[idx].indent = oldBlock.indent;
      ctx.arr[idx].checked = oldBlock.checked;
      if (newType === 'toggle') { ctx.arr[idx].summary = carry; ctx.arr[idx].content = ''; }
      // 图片块：丢弃文本，保留 caption 到 content（转换回文本时还原）
      if (newType === 'image') {
        ctx.arr[idx].content = '';
        ctx.arr[idx].html = '';
        ctx.arr[idx].imgData = null;
      }
      // 图片块转回文本：丢弃图片，保留 caption 文字
      if (oldBlock.type === 'image' && newType !== 'image') {
        ctx.arr[idx].content = (oldBlock.imgData && oldBlock.imgData.caption) || '';
        ctx.arr[idx].html = renderInlineMarkdown(ctx.arr[idx].content);
        ctx.arr[idx].imgData = null;
      }
      reRender();
      // v8.4.18 F：转换到有序列表且是新段起点时，自动延续上一有序列表段缩进
      if (newType === 'numbered') inheritListIndent(ctx, idx);
      const newEl = focusBlockEditable(ctx.parent ? ctx.parentIdx : null, idx);
      // v8.4.18 B：toggle 块没有 .notion-editable（标题是 .notion-toggle__summary），聚焦其标题行
      if (!newEl && ctx.arr[idx] && ctx.arr[idx].type === 'toggle') {
        const q = (ctx.parentIdx !== null)
          ? blocksContainer.querySelector('.notion-block--toggle[data-pidx="' + ctx.parentIdx + '"][data-index="' + idx + '"] .notion-toggle__summary')
          : blocksContainer.querySelector('.notion-block--toggle[data-index="' + idx + '"] .notion-toggle__summary');
        if (q) { q.focus(); placeCaretAtEnd(q); }
      }
    }

    function splitBlock(idx, editable) {
      // 用块定位工具找到真实数组（顶层 blocks 或 toggle children）
      const be = editable.closest('.notion-block');
      const ctx = getBlockCtx(be);
      if (!ctx) return;
      idx = ctx.idx;
      const arr = ctx.arr;
      const block = arr[idx];
      const parentIdx = ctx.parentIdx;
      const text = editable.textContent || '';

      // 空块直接在其下方新建一个空文本块并聚焦
      if (text === '') {
        // v8.4.18 G：空列表项（无序/有序）按回车 → 退出列表，当前块降级为普通文本（不新建块）
        if (block.type === 'bullet' || block.type === 'numbered') {
          block.type = 'text';
          block.html = '';
          reRender();
          const el = focusBlockEditable(parentIdx, idx);
          if (el) { el.focus(); placeCaretAtEnd(el); }
          notifyChange();
          return;
        }
        const newBlock = createBlock('text', '');
        newBlock.indent = block.indent;
        arr.splice(idx + 1, 0, newBlock);
        reRender();
        const newEl = focusBlockEditable(parentIdx, idx + 1);
        void newEl;
        notifyChange();
        return;
      }

      const sel = window.getSelection();
      let offset = text.length;
      if (sel.rangeCount > 0) {
        const range = sel.getRangeAt(0);
        const preCaret = range.cloneRange();
        preCaret.selectNodeContents(editable);
        preCaret.setEnd(range.startContainer, range.startOffset);
        offset = Math.min(preCaret.toString().length, text.length);
      }

      block.content = text.slice(0, offset);
      block.html = '';
      // v8.4.18 G：列表（无序/有序）行尾回车 → 新项保持列表类型（继续列表）；非列表行尾 → 普通文本；光标在中间 → 继承原类型
      let newType = block.type;
      if (text.slice(offset) === '') newType = (block.type === 'bullet' || block.type === 'numbered') ? block.type : 'text';
      const newBlock = createBlock(newType, text.slice(offset));
      newBlock.indent = block.indent;
      if (block.type === 'todo') newBlock.checked = false;
      arr.splice(idx + 1, 0, newBlock);
      reRender();
      const newEl2 = focusBlockEditable(parentIdx, idx + 1);
      void newEl2;
      notifyChange();
    }

    function deleteBlock(idx, be) {
      // be 可选：传入块元素时走 ctx（支持删除 toggle 子块）；否则按顶层 blocks 删除
      let arr = blocks, parentIdx = null;
      if (be) {
        const ctx = getBlockCtx(be);
        if (ctx) { arr = ctx.arr; idx = ctx.idx; parentIdx = ctx.parentIdx; }
      }
      if (arr.length <= 1) return;
      pushUndo();
      arr.splice(idx, 1);
      reRender();
      const focusIdx = Math.min(idx, arr.length - 1);
      const focusEl = focusBlockEditable(parentIdx, focusIdx);
      if (focusEl) { focusEl.focus(); placeCaretAtEnd(focusEl); }
    }

    function moveBlock(idx, dir, be) {
      let arr = blocks, parentIdx = null;
      if (be) {
        const ctx = getBlockCtx(be);
        if (ctx) { arr = ctx.arr; idx = ctx.idx; parentIdx = ctx.parentIdx; }
      }
      const ni = idx + dir;
      if (ni < 0 || ni >= arr.length) return;
      pushUndo();
      const tmp = arr[idx]; arr[idx] = arr[ni]; arr[ni] = tmp;
      reRender(); notifyChange();
      const el = focusBlockEditable(parentIdx, ni);
      if (el) { el.focus(); placeCaretAtEnd(el); }
    }

    // ===== 拖拽排序（手柄按住拖动，占位线提示，松开交换） =====
    let dragCtx = null;   // { srcIdx, placeholderEl, dragging, startY, startX }
    let dragJustMoved = false;   // 本次按下是否真的拖动过（防止拖拽后误触发 click 弹菜单）
    function startBlockDrag(blockEl, ev) {
      if (dragCtx) return;
      const idx = parseInt(blockEl.dataset.index);
      dragJustMoved = false;
      // 占位线：插入到当前块之后
      const ph = document.createElement('div');
      ph.className = 'notion-drag-placeholder';
      blockEl.after(ph);
      // 原块加拖拽中样式（视觉上微微透明）
      blockEl.classList.add('ne-dragging');
      dragCtx = { srcIdx: idx, placeholderEl: ph, dragging: false, startY: ev.clientY, startX: ev.clientX, blockEl };
      document.body.classList.add('ne-dragging-active');
      window.addEventListener('pointermove', onDragMove, { passive: true });
      window.addEventListener('pointerup', onDragEnd);
      window.addEventListener('pointercancel', onDragEnd);
    }
    function onDragMove(ev) {
      if (!dragCtx) return;
      // 距离超过阈值才判定为拖拽（轻点不算），阈值 6px
      if (!dragCtx.dragging) {
        const dx = Math.abs(ev.clientX - dragCtx.startX);
        const dy = Math.abs(ev.clientY - dragCtx.startY);
        if (dx + dy < 6) return;
        dragCtx.dragging = true;
        dragJustMoved = true;
      }
      const blocksEls = Array.from(blocksContainer.children); // .notion-block 列表
      // 找到鼠标当前所在的目标块（占位线不含）
      let target = null;
      for (const b of blocksEls) {
        if (b.classList.contains('notion-drag-placeholder')) continue;
        const r = b.getBoundingClientRect();
        if (ev.clientY < r.bottom && ev.clientY >= r.top - 4) { target = b; break; }
      }
      if (!target) {
        // 鼠标在所有块之外：放到列表头或尾
        const first = blocksEls[0], last = blocksEls[blocksEls.length - 1];
        if (first && ev.clientY < first.getBoundingClientRect().top) target = first;
        else if (last && ev.clientY > last.getBoundingClientRect().bottom) target = last;
      }
      if (!target) return;
      const tRect = target.getBoundingClientRect();
      const after = ev.clientY > tRect.top + tRect.height / 2;
      if (after) target.after(dragCtx.placeholderEl);
      else target.before(dragCtx.placeholderEl);
    }
    function onDragEnd() {
      if (!dragCtx) return;
      const ctx = dragCtx;
      dragCtx = null;
      window.removeEventListener('pointermove', onDragMove);
      window.removeEventListener('pointerup', onDragEnd);
      window.removeEventListener('pointercancel', onDragEnd);
      document.body.classList.remove('ne-dragging-active');
      ctx.blockEl.classList.remove('ne-dragging');
      // 轻点（未达到拖拽阈值）：回退为打开手柄菜单
      if (!ctx.dragging) {
        ctx.placeholderEl.remove();
        showHandleMenu(ctx.blockEl);
        return;
      }
      const ph = ctx.placeholderEl;
      const srcIdx = ctx.srcIdx;
      // 占位线在块列表中的位置（落在哪个块之前）
      let insertPos = -1;
      const all = Array.from(blocksContainer.children).filter(x => !x.classList.contains('notion-drag-placeholder'));
      for (let i = 0; i < all.length; i++) {
        // ph.compareDocumentPosition(b) & FOLLOWING => b 在 ph 之后 => 占位线位于 b 之前
        if (ph.compareDocumentPosition(all[i]) & Node.DOCUMENT_POSITION_FOLLOWING) { insertPos = i; break; }
      }
      ph.remove();
      // 未判定：保持不变
      if (insertPos < 0) insertPos = srcIdx;
      // 若占位线在原位（srcIdx 或 srcIdx+1 即未动），直接恢复
      if (insertPos === srcIdx || insertPos === srcIdx + 1) { reRender(); return; }
      pushUndo();
      const moved = blocks.splice(srcIdx, 1)[0];
      let target = insertPos;
      if (srcIdx < target) target -= 1;
      blocks.splice(target, 0, moved);
      reRender(); notifyChange();
      const el = focusBlockEditable(null, target);
      if (el) el.focus();
    }

    function reRender() {
      // 兜底：为历史数据补 id（旧格式没有 id 字段）
      blocks.forEach(b => { if (!b.id) b.id = genBlockId(); });
      migrateToggleBlocks(blocks);   // 【修复1】兜底迁移旧 toggle 数据
      blocksContainer.innerHTML = '';
      blocks.forEach((block, i) => {
        // v8.4.18 E：numbered 段起点 = 前一块不是 numbered（空白行/其他类型块会断开列表段）
        const isStart = block.type === 'numbered' && (i === 0 || !blocks[i - 1] || blocks[i - 1].type !== 'numbered');
        blocksContainer.appendChild(renderBlock(block, i, undefined, isStart));
      });
      updateFooter();
    }

    function placeCaretAtEnd(el) {
      el.focus();
      const sel = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(el);
      range.collapse(false);
      sel.removeAllRanges();
      sel.addRange(range);
    }


    function createBlock(type, content) {
      const b = { id: genBlockId(), type, content: content || '', html: '', indent: 0, color: '', checked: false, collapsed: false, emoji: '💡', summary: '' };
      // 【修复1】toggle 块默认带 children 子块数组（格式同主 blocks 数组）
      if (type === 'toggle') b.children = [];
      // 图片块：imgData = { src, alt, caption, width, align }
      if (type === 'image') b.imgData = null;
      return b;
    }

    // 【修复1】旧数据迁移：确保每个 toggle 都有 children 数组
    // 旧版 toggle 的 html/content 存的是详情内容，迁移时转成文本子块
    function migrateToggleBlocks(arr) {
      if (!Array.isArray(arr)) return;
      arr.forEach(b => {
        if (b && b.type === 'toggle') {
          if (!Array.isArray(b.children)) {
            b.children = [];
            const legacy = b.html ? stripHtml(b.html) : (b.content || '');
            if (legacy && legacy.trim()) {
              const nb = createBlock('text', legacy);
              b.children.push(nb);
            }
            b.html = '';
            b.content = '';
          }
          // 递归迁移子块
          b.children.forEach(c => {
            if (c && c.type === 'toggle') migrateToggleBlocks([c]);
          });
        }
      });
    }

    // Markdown → 块数组
    function parseMarkdownToBlocks(md) {
      md = App.Utils.normalizeMarkdownInput(md);
      // 单行智能修复：历史保存的「无换行」数据中，### 标题 / > 引用 标记被夹在句子中间，
      // 在标记前的空格处插入换行，让旧数据重新打开时恢复块结构，再保存即修复
      if (md && md.indexOf('\n') === -1 && /(#{1,4}\s|>\s)/.test(md)) {
        md = md.replace(/ {1,2}(?=#{1,4}\s|>\s)/g, '\n');
      }
      const lines = md.split('\n');
      const result = [];
      let inCode = false, codeLines = [];
      let tableRows = [];
      // 【修复1】toggle children 收集：当前打开的 toggle 块 + 其子行缓冲
      let curToggle = null;          // 正在收集 children 的 toggle 块（result 中的引用）
      let childLineBuf = [];         // toggle 后续连续的子行（已去除 > 前缀）

      function flushTable() {
        if (tableRows.length === 0) return;
        // 若第二行是分隔线（|---|---|）则丢弃
        const dataRows = tableRows.length > 1 && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(tableRows[1])
          ? tableRows.slice(2)
          : tableRows.slice(1);
        if (dataRows.length === 0) dataRows.push('');
        const cells = tableRows.map(r => r.split('|').map(c => c.trim()).filter(c => c !== ''));
        const headers = cells[0] || [];
        const body = cells.slice(tableRows.length > 1 && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(tableRows[1]) ? 2 : 1);
        result.push({ type:'table', content:'', html:'', tableData: [headers, ...body], indent:0, collapsed:false, emoji:'💡', summary:'' });
        tableRows = [];
      }

      function flushToggleChildren() {
        if (!curToggle) return;
        if (!Array.isArray(curToggle.children)) curToggle.children = [];
        // 缓冲的子行按行解析为子块（支持 - / 1. / [ ] 等前缀）
        childLineBuf.forEach(cl => {
          const sub = parseSingleLineToBlock(cl);
          curToggle.children.push(sub);
        });
        curToggle = null;
        childLineBuf = [];
      }

      function parseSingleLineToBlock(raw) {
        let type = 'text', content = raw, indent = 0;
        while (content.startsWith('  ') || content.startsWith('\t')) { indent++; content = content.replace(/^[ \t]+/, ''); }
        // 图片行 ![alt](url) → image 块
        const imgMatch = content.match(/^!\[([^\]]*)\]\(([^)]+)\)\s*$/);
        if (imgMatch) {
          const blk = createBlock('image', '');
          blk.indent = indent;
          blk.imgData = { src: imgMatch[2], alt: imgMatch[1] || '', caption: '', width: '100%', align: 'center' };
          return blk;
        }
        if (/^#{4}\s*/.test(content)) { type='h4'; content = content.replace(/^#{4}\s*/, ''); }
        else if (/^#{3}\s*/.test(content)) { type='h3'; content = content.replace(/^#{3}\s*/, ''); }
        else if (/^#{2}\s*/.test(content)) { type='h2'; content = content.replace(/^#{2}\s*/, ''); }
        else if (/^#\s*/.test(content)) { type='h1'; content = content.replace(/^#\s*/, ''); }
        else if (/^- \[[ x]\]/.test(content)) { type='todo'; content = content.replace(/^- \[[ x]\]\s?/, ''); }
        else if (/^- /.test(content)) { type='bullet'; content = content.replace(/^- /, ''); }
        else if (/^\d+\.\s/.test(content)) { type='numbered'; content = content.replace(/^\d+\.\s/, ''); }
        content = content.replace(/^(#{1,4}\s)+/, '');
        const blk = createBlock(type, content);
        blk.indent = indent;
        blk.checked = /\[x\]/.test(raw);
        blk.html = renderInlineMarkdown(content);
        return blk;
      }

      lines.forEach(line => {
        if (inCode) {
          if (line.trim() === '```') { result.push({ type:'code', content: codeLines.join('\n'), html:'', indent:0, collapsed:false, emoji:'💡', summary:'' }); codeLines = []; inCode = false; }
          else codeLines.push(line);
          return;
        }
        if (line.trim() === '```') { inCode = true; return; }

        // 表格行收集
        if (/^\s*\|.*\|\s*$/.test(line)) {
          tableRows.push(line);
          return;
        }
        flushTable();

        if (line.trim() === '---') { flushToggleChildren(); result.push({ type:'divider', content:'', html:'', indent:0, collapsed:false, emoji:'💡', summary:'' }); return; }
        // 空行：结束当前 toggle 子块收集，保留空白块
        if (line.trim() === '') { flushToggleChildren(); result.push(createBlock('text', '')); return; }
        // 纯 # 标记行（无文字）跳过
        if (/^#{1,4}\s*$/.test(line.trim())) return;

        // toggle 后续子行（> 前缀）：归入 curToggle.children（同时支持嵌套 > ▸ 开启新的子 toggle）
        const childMatch = /^\s*> (?![▸▾💡]).*/.test(line);
        if (curToggle && childMatch) {
          // 剥离 > 前缀后按行解析
          const stripped = line.replace(/^\s*>\s?/, '');
          // 支持子 toggle：> > ▸ xxx → children 里再放一个 toggle
          if (/^> ▸\s?|^> ▾\s?/.test(stripped)) {
            const nestedToggle = createBlock('toggle', stripped.replace(/^> [▸▾]\s?/, ''));
            nestedToggle.summary = nestedToggle.content;
            nestedToggle.content = '';
            nestedToggle.children = [];
            curToggle.children.push(nestedToggle);
          } else {
            childLineBuf.push(stripped);
          }
          return;
        }

        // 普通行解析前先收尾 toggle children
        flushToggleChildren();

        let type = 'text', content = line, indent = 0;
        while (content.startsWith('  ') || content.startsWith('\t')) { indent++; content = content.replace(/^[ \t]+/, ''); }
        // 图片行 ![alt](url) → image 块
        const imgMatch = content.match(/^!\[([^\]]*)\]\(([^)]+)\)\s*$/);
        if (imgMatch) {
          const imgBlk = createBlock('image', '');
          imgBlk.indent = indent;
          imgBlk.imgData = { src: imgMatch[2], alt: imgMatch[1] || '', caption: '', width: '100%', align: 'center' };
          result.push(imgBlk);
          return;
        }
        if (/^#{4}\s*/.test(content)) { type='h4'; content = content.replace(/^#{4}\s*/, ''); }
        else if (/^#{3}\s*/.test(content)) { type='h3'; content = content.replace(/^#{3}\s*/, ''); }
        else if (/^#{2}\s*/.test(content)) { type='h2'; content = content.replace(/^#{2}\s*/, ''); }
        else if (/^#\s*/.test(content)) { type='h1'; content = content.replace(/^#\s*/, ''); }
        else if (/^- \[[ x]\]/.test(content)) { type='todo'; content = content.replace(/^- \[[ x]\]\s?/, ''); }
        else if (/^- /.test(content)) { type='bullet'; content = content.replace(/^- /, ''); }
        else if (/^\d+\.\s/.test(content)) { type='numbered'; content = content.replace(/^\d+\.\s/, ''); }
        else if (/^> 💡\s?/.test(content)) { type='callout'; content = content.replace(/^> 💡\s?/, ''); }
        else if (/^> ▸\s?|^> ▾\s?/.test(content)) { type='toggle'; content = content.replace(/^> [▸▾]\s?/, ''); }
        else if (/^>\s?/.test(content)) { type='quote'; content = content.replace(/^>\s?/, ''); }
        // 双重前缀兜底：「### ### 标题」→「标题」
        content = content.replace(/^(#{1,4}\s)+/, '');
        const blk = { type, content, html: renderInlineMarkdown(content), indent, color:'', checked: /\[x\]/.test(line), collapsed:false, emoji:'💡', summary:'' };
        // toggle 开启 children 收集
        if (type === 'toggle') {
          blk.children = [];
          blk.summary = content;
          blk.content = '';
          result.push(blk);
          curToggle = blk;
          childLineBuf = [];
          return;
        }
        result.push(blk);
      });
      flushToggleChildren();
      flushTable();
      if (inCode) result.push({ type:'code', content: codeLines.join('\n'), html:'', indent:0, collapsed:false, emoji:'💡', summary:'' });
      return result;
    }

    // 块数组 → Markdown
    // HTML → 行内 Markdown（保存时保留加粗/斜体/下划线/删除线/代码/高亮/颜色/链接/图片）
    function htmlToInlineMarkdown(html) {
      const d = document.createElement('div');
      d.innerHTML = html || '';
      d.querySelectorAll('br').forEach(br => br.replaceWith('\n'));
      const walk = (node, isRoot) => {
        if (node.nodeType === 3) return node.textContent.replace(/\u200b/g, '');
        if (node.nodeType !== 1) return '';
        const tag = node.tagName.toLowerCase();
        const inner = Array.from(node.childNodes).map(n => walk(n, false)).join('');
        // 公式（$...$ 行内 / $$...$$ 块级）：从 data-latex 还原源码，保证 Markdown 往返不丢
        if (node.classList && node.classList.contains('mformula')) {
          const raw = node.getAttribute('data-latex');
          if (raw) {
            let latex;
            try { latex = decodeURIComponent(raw); } catch (e) { latex = raw; }
            return node.classList.contains('mformula--block') ? '$$' + latex + '$$' : '$' + latex + '$';
          }
        }
        // 块级标签（富文本粘贴产生的 <div>/<p>/<li> 等）：前后补换行，避免导出时合并成单行。
        // 根 div 除外——否则单块导出会多出前后换行，把 "### 标题" 拆成 "### " + "标题" 两行
        if (!isRoot && ['div','p','li','h1','h2','h3','h4','h5','h6','blockquote','pre','ul','ol','tr','td','th','section','article','header','footer'].indexOf(tag) !== -1) {
          return '\n' + inner + '\n';
        }
        switch (tag) {
          case 'b': case 'strong': return '**' + inner + '**';
          case 'i': case 'em': return '*' + inner + '*';
          case 'u': return '[u]' + inner + '[/u]';
          case 's': case 'strike': case 'del': return '~~' + inner + '~~';
          case 'code': return '`' + inner + '`';
          case 'mark': return '==' + inner + '==';
          case 'a': {
            const href = node.getAttribute('href') || '';
            return '[' + inner + '](' + href + ')';
          }
          case 'img': {
            const src = node.getAttribute('src') || '';
            const alt = node.getAttribute('alt') || '';
            return '![' + alt + '](' + src + ')';
          }
          case 'span': {
            const st = node.getAttribute('style') || '';
            const color = /(?:^|;)\s*color\s*:\s*(#[0-9a-fA-F]{3,6}|rgb\([^)]+\))/i.exec(st);
            const bg = /background(?:-color)?:\s*(#[0-9a-fA-F]{3,6}|rgb\([^)]+\))/i.exec(st);
            const fw = /\bfont-weight\s*:\s*(bold|bolder|[6-9]00)\b/i.test(st);
            const fi = /\bfont-style\s*:\s*italic\b/i.test(st);
            const fd = /\btext-decoration\s*:\s*underline\b/i.test(st);
            const fs = /\btext-decoration\s*:\s*line-through\b/i.test(st);
            let s = inner;
            if (fw) s = '**' + s + '**';
            if (fi) s = '*' + s + '*';
            if (fd) s = '[u]' + s + '[/u]';
            if (fs) s = '~~' + s + '~~';
            if (color) s = '[c=' + color[1] + ']' + s + '[/c]';
            else if (bg) s = '==' + s + '==';
            return s;
          }
          case 'font': {
            const fc = node.getAttribute('color');
            let s = inner;
            if (fc) s = '[c=' + fc + ']' + s + '[/c]';
            return s;
          }
          default: return inner;
        }
      };
      return walk(d, true).replace(/[\u2028\u2029]/g, '\n').replace(/\n{3,}/g, '\n\n');
    }

    function exportToMarkdown() {
      const lines = [];
      let numCounter = 0;
      // 【修复1】递归导出单个块（顶层 / toggle children 子块通用）
      const exportBlock = (b, pad, counter) => {
        const md = htmlToInlineMarkdown(b.html || b.content);
        switch(b.type) {
          case 'h1': if (md.trim()) lines.push(pad + '# ' + md.replace(/\s*\n+\s*/g, ' ').replace(/^(#{1,4}\s)+/, '').trim()); break;
          case 'h2': if (md.trim()) lines.push(pad + '## ' + md.replace(/\s*\n+\s*/g, ' ').replace(/^(#{1,4}\s)+/, '').trim()); break;
          case 'h3': if (md.trim()) lines.push(pad + '### ' + md.replace(/\s*\n+\s*/g, ' ').replace(/^(#{1,4}\s)+/, '').trim()); break;
          case 'h4': if (md.trim()) lines.push(pad + '#### ' + md.replace(/\s*\n+\s*/g, ' ').replace(/^(#{1,4}\s)+/, '').trim()); break;
          case 'bullet': lines.push(pad + '- ' + md); break;
          case 'numbered': counter.n++; lines.push(pad + counter.n + '. ' + md); break;
          case 'todo': lines.push(pad + '- [' + (b.checked ? 'x' : ' ') + '] ' + md); break;
          case 'quote': lines.push(pad + '> ' + md); break;
          case 'callout': lines.push(pad + '> 💡 ' + md); break;
          case 'toggle': {
            // 折叠块导出标题 + children 子块（前面加 > 引用缩进）
            lines.push(pad + '> ▸ ' + (b.summary || ''));
            if (Array.isArray(b.children)) {
              const childCounter = { n: 0 };
              b.children.forEach(c => exportBlock(c, pad + '> ', childCounter));
            }
            break;
          }
          case 'divider': lines.push('---'); break;
          case 'code': lines.push('```' + '\n' + (b.content || '') + '\n```'); break;
          case 'table': if (b.tableData) b.tableData.forEach(r => lines.push('| ' + r.join(' | ') + ' |')); break;
          case 'image': {
            // 图片块：![alt](src)，caption 作为下一行文本保留
            const d = b.imgData || {};
            if (d.src) {
              lines.push(pad + '![' + (d.alt || '') + '](' + d.src + ')');
              if (d.caption && d.caption.trim()) lines.push(pad + d.caption);
            } else {
              lines.push(pad + (d.caption || ''));
            }
            break;
          }
          default: lines.push(pad + md); break;
        }
      };
      blocks.forEach(b => {
        const pad = '  '.repeat(b.indent);
        const counter = { n: 0 };
        exportBlock(b, pad, counter);
      });
      return lines.join('\n');
    }

    function stripHtml(html) {
      const d = document.createElement('div');
      d.innerHTML = html || '';
      // 软回车 <br> 还原为换行，保证导出/再导入不丢换行
      d.querySelectorAll('br').forEach(br => br.replaceWith('\n'));
      return (d.textContent || '').replace(/\u200b/g, '');
    }

    // 字数 / 保存状态 页脚
    const footer = document.createElement('div');
    footer.className = 'notion-editor__footer';
    function updateFooter() {
      let chars = 0;
      // 【修复1】递归统计块字数（含 toggle children）
      const countBlock = (b) => {
        if (b.type === 'table') (b.tableData || []).forEach(r => r.forEach(c => chars += (c || '').length));
        else if (b.type === 'toggle') {
          chars += (b.summary || '').length;
          (b.children || []).forEach(countBlock);
        }
        else chars += (stripHtml(b.html || b.content) || '').length;
      };
      blocks.forEach(countBlock);
      footer.innerHTML = `<span class="notion-foot-count">${chars} 字</span><span class="notion-foot-save" id="notion-save-status">就绪</span>`;
    }
    function setSaveStatus(text) {
      const el = footer.querySelector('#notion-save-status');
      if (el) el.textContent = text;
    }

    // 初始渲染：格式栏悬浮在页面窗口最底部（导航栏上方），聚焦编辑器时浮出、失焦收起
    wrapper.appendChild(blocksContainer);
    wrapper.appendChild(footer);
    wrapper.appendChild(toolbar);
    let _toolbarTimer = null;
    wrapper.addEventListener('focusin', (e) => {
      if (e.target && e.target.closest && e.target.closest('.notion-editable, .notion-table td')) {
        clearTimeout(_toolbarTimer);
        toolbar.classList.add('is-visible');
        App.Components._showMobileToolbar();
      }
    });
    wrapper.addEventListener('focusout', (e) => {
      const next = e.relatedTarget;
      if (next && (toolbar.contains(next) || wrapper.contains(next))) return;
      clearTimeout(_toolbarTimer);
      _toolbarTimer = setTimeout(() => {
        toolbar.classList.remove('is-visible');
        App.Components._hideMobileToolbar();
      }, 220);
    });
    // 移动端点击编辑器区域外时，隐藏 Bottom Sheet（若打开）；同时取消块选中（状态 1）
    document.addEventListener('click', (e) => {
      if (!wrapper.contains(e.target)) {
        hideAllMenus();
        clearSelected();
      }
    });
    // 状态机：点击块 → 若块不在编辑态（光标不闪动）则选中（显示手柄）；编辑态点击 → 进入编辑并取消选中
    // 用户规则：手柄显示条件 = 块处于「非编辑态被点击选中」，而非必须按 ESC
    wrapper.addEventListener('mousedown', (e) => {
      const be = e.target.closest ? e.target.closest('.notion-block') : null;
      if (!be) { clearSelected(); return; }
      // 点击手柄不在此处理（手柄自身逻辑）
      if (e.target.closest('.notion-block__handle')) return;
      // 点击 contenteditable 文字区：交给 focus 处理（进入编辑态，手柄隐藏），不在这里选中避免闪烁
      const ed = be.querySelector('.notion-editable');
      if (ed && (e.target === ed || (ed.contains && ed.contains(e.target)))) return;
      if (be.classList.contains('is-editing')) {
        // 编辑态（光标闪动）：点击非文字区（如块左侧空白）取消选中隐藏手柄
        be.classList.remove('is-selected');
      } else {
        // 非编辑态（光标不闪动）：点击块的非文字区域 → 选中它（手柄显示 + 蓝色竖条）
        selectBlock(be);
      }
    });
    // 状态机：document 级 ESC（菜单外/非编辑态），处理 状态3→1 取消选中
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !e.defaultPrevented) {
        handleBlockEscape();
      }
    });
    reRender();

    // 粘贴 Markdown 自动解析（多行→拆块，单行→行内渲染）
    setupPasteHandler(wrapper);

    // ===== 拖拽上传图片：拖入编辑器区域 → 在释放位置创建图片块 =====
    let dragDepth = 0;
    wrapper.addEventListener('dragenter', (e) => {
      e.preventDefault();
      dragDepth++;
      wrapper.classList.add('ne-drag-over');
    });
    wrapper.addEventListener('dragover', (e) => {
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
    });
    wrapper.addEventListener('dragleave', () => {
      dragDepth = Math.max(0, dragDepth - 1);
      if (dragDepth === 0) wrapper.classList.remove('ne-drag-over');
    });
    wrapper.addEventListener('drop', (e) => {
      e.preventDefault();
      dragDepth = 0;
      wrapper.classList.remove('ne-drag-over');
      const files = e.dataTransfer && e.dataTransfer.files;
      if (!files || files.length === 0) return;
      const imgFile = Array.from(files).find(f => /^image\//.test(f.type));
      if (!imgFile) { App.Components.toast('仅支持图片格式', 'error'); return; }
      // 插入位置：拖放点所在块之后；无块则末尾
      let insertIdx = blocks.length - 1;
      const target = e.target && e.target.closest ? e.target.closest('.notion-block') : null;
      if (target) {
        const pctx = getBlockCtx(target);
        if (pctx) { insertIdx = pctx.idx; const nb = createBlock('image', ''); pushUndo(); pctx.arr.splice(pctx.idx + 1, 0, nb); reRender(); handleImageFile(imgFile, nb); return; }
      }
      pushUndo();
      const nb = createBlock('image', '');
      blocks.splice(insertIdx + 1, 0, nb);
      reRender();
      handleImageFile(imgFile, nb);
    });

    const getContent = () => exportToMarkdown();
    const setContent = (val) => {
      blocks = val ? parseMarkdownToBlocks(val) : [createBlock('text', '')];
      reRender();
    };

    // ===== JSON 数据接口（块数组） =====

    // 返回当前 JSON 块数组（对外格式）
    const getEditorData = () => blocks.map(b => blockToExternal(b));

    // 内部块对象 → 对外 JSON 块对象（递归 children）
    function blockToExternal(b) {
      const out = {
        id: b.id || genBlockId(),
        type: TYPE_MAP_OUT[b.type] || b.type,
        content: b.type === 'toggle' ? (b.summary || '') : stripHtml(b.html || b.content || ''),
        checked: !!b.checked,
        collapsed: !!b.collapsed,
        indent: b.indent || 0,
        props: { color: b.color || '', backgroundColor: '' }
      };
      // 保留富文本 HTML（内部专用，方便行内格式往返，导出 JSON 时可忽略）
      if (b.type !== 'toggle' && b.html) out.html = b.html;
      // 折叠块：详情 + children 递归
      if (b.type === 'toggle') {
        out.detail = b.content || '';
        if (b.html) out.detailHtml = b.html;
        out.children = (b.children || []).map(blockToExternal);
      }
      // 表格数据
      if (b.type === 'table') out.tableData = b.tableData || [['列1','列2'],['','']];
      // 高亮提示块图标
      if (b.type === 'callout') out.emoji = b.emoji || '💡';
      // 图片块数据
      if (b.type === 'image') out.imgData = b.imgData || null;
      return out;
    }

    // 用 JSON 块数组重建编辑器
    const setEditorData = (jsonArray) => {
      if (!Array.isArray(jsonArray)) { console.warn('[NotionEditor] setEditorData 需要传入块数组'); return; }
      const arr = (jsonArray || []).map(normalizeExternalBlock);
      if (arr.length === 0) arr.push(createBlock('text', ''));
      blocks = arr;
      reRender();
    };

    // 对外 JSON 块对象 → 内部块对象（供 initialData / setEditorData 使用，递归 children）
    function normalizeExternalBlock(item) {
      const b = createBlock(TYPE_MAP_IN[item.type] || item.type || 'text', '');
      if (item.id) b.id = item.id;
      b.content = (item.content || '');
      if (item.type === 'toggle') {
        b.summary = item.content || '';
        b.content = item.detail || '';
        b.html = item.detailHtml || '';
        if (Array.isArray(item.children)) {
          // 子块递归转换
          b.children = item.children.map(normalizeExternalBlock);
        } else {
          // 旧数据迁移：无 children 字段时，detail 内容作为文本子块兜底
          b.children = [];
          const legacy = item.detail || '';
          if (legacy && legacy.trim()) b.children.push(createBlock('text', legacy));
          b.content = '';
          b.html = '';
        }
      }
      if (item.html && item.type !== 'toggle') b.html = item.html;
      else if (b.content && !b.html && item.type !== 'toggle') b.html = renderInlineMarkdown(b.content);
      b.checked = !!item.checked;
      b.collapsed = !!item.collapsed;
      b.indent = Math.max(0, Math.min(3, parseInt(item.indent) || 0));
      if (item.props) { b.color = item.props.color || ''; }
      if (item.type === 'table') b.tableData = item.tableData || [['列1','列2'],['','']];
      if (item.type === 'callout') b.emoji = item.emoji || '💡';
      if (item.type === 'image') b.imgData = item.imgData || null;
      return b;
    }

    return {
      element: wrapper,
      getContent, setContent,
      getEditorData, setEditorData,
      // 便捷方法：让调用方可以注册自己的 onChange
      setOnChange: (fn) => { onChangeCb = fn; },
    };
  },

  // ===== 块编辑器统一入口（与 IndexedDB 对接） =====
  // 用法：
  //   const editor = App.Components.initEditor(document.getElementById('editor-container'), {
  //     initialData: await db.getNoteContent(id),   // 传 JSON 块数组，或 Markdown 字符串（兼容旧数据）
  //     dataMode: 'json',                            // 'json'：onChange 回调 JSON 数组；'md'（默认）：回调 Markdown
  //     placeholder: '输入内容，输入 / 唤起命令...',
  //     onChange: (data) => { db.saveNote(id, data); }
  //   });
  //   editor.getEditorData() / editor.setEditorData([...])  // 读/写 JSON 块数组
  //   editor.getContent() / editor.setContent('...')        // 读/写 Markdown 字符串（兼容旧接口）
  initEditor(container, options) {
    const opts = options || {};
    const editor = this.notionEditor(
      opts.initialData || '',
      opts.placeholder,
      opts.onChange,
      opts.dataMode === 'json' ? 'json' : 'md',
      { inlinePadding: !!opts.inlinePadding }
    );
    container.appendChild(editor.element);
    return editor;
  },

  // ===== Notion 移动端编辑器全局入口 =====
  // 用法（独立 HTML 接入）：
  //   const editor = window.initNotionMobileEditor('#editor-container', {
  //     initialBlocks: [ { type: 'text', content: '你好' } ],   // JSON 块数组
  //     onChange: (blocks) => { /* 保存 blocks 到你的存储 */ }
  //   });
  //   editor.getEditorData() / editor.setEditorData([...]) / editor.getContent() / editor.setContent()
  initNotionMobileEditor(containerSelector, options) {
    const opts = options || {};
    const container = typeof containerSelector === 'string'
      ? document.querySelector(containerSelector)
      : containerSelector;
    if (!container) { console.error('[initNotionMobileEditor] 容器不存在:', containerSelector); return null; }
    const editor = this.initEditor(container, {
      initialData: opts.initialBlocks || opts.initialData || '',
      dataMode: 'json',
      placeholder: opts.placeholder,
      onChange: opts.onChange,
    });
    return editor;
  },

  // ===== 底部弹出选择器 =====
  actionSheet(options, title) {
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');

      const overlay = document.createElement('div');
      overlay.className = 'actionsheet-overlay';

      const sheet = document.createElement('div');
      sheet.className = 'actionsheet';

      // 滚动锁：锁定背景，关闭时恢复
      App.Components._lockScroll();
      const closeOverlay = () => { App.Components._unlockScroll(); overlay.remove(); };

      if (title) {
        const titleEl = document.createElement('div');
        titleEl.style.cssText = 'text-align:center;padding:14px;font-size:var(--font-sm);color:var(--text-tertiary);border-bottom:1px solid var(--divider-color);';
        titleEl.textContent = title;
        sheet.appendChild(titleEl);
      }

      options.forEach(opt => {
        const item = document.createElement('div');
        item.className = 'actionsheet__item';
        item.textContent = opt.label;
        item.addEventListener('click', () => {
          closeOverlay();
          resolve(opt.value !== undefined ? opt.value : opt.label);
        });
        sheet.appendChild(item);
      });

      const cancel = document.createElement('div');
      cancel.className = 'actionsheet__cancel';
      cancel.textContent = '取消';
      cancel.addEventListener('click', () => {
        closeOverlay();
        resolve(null);
      });
      sheet.appendChild(cancel);

      overlay.appendChild(sheet);
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) {
          closeOverlay();
          resolve(null);
        }
      });

      container.appendChild(overlay);
    });
  },

  // ===== 便签编辑面板（底部滑出：内容 + 颜色 + 置顶） =====
  // opts: { title, initial: {content,color,pinned}, onSave(data) }
  stickySheet(opts) {
    const container = document.getElementById('modal-container');
    const overlay = document.createElement('div');
    overlay.className = 'sticky-sheet-overlay';

    const panel = document.createElement('div');
    panel.className = 'sticky-sheet';

    const COLORS = ['#FFFBEB', '#EFF6FF', '#ECFDF5', '#FDF2F8', '#F5F3FF', '#FFFFFF'];

    // 标题行
    const head = document.createElement('div');
    head.className = 'sticky-sheet__head';
    const t = document.createElement('div');
    t.className = 'sticky-sheet__title';
    t.textContent = opts.title || '新增便签';
    const close = document.createElement('button');
    close.className = 'sticky-sheet__close';
    close.type = 'button';
    close.textContent = '✕';
    close.addEventListener('click', () => overlay.remove());
    head.appendChild(t);
    head.appendChild(close);
    panel.appendChild(head);

    // 内容输入
    const ta = document.createElement('textarea');
    ta.className = 'sticky-sheet__input';
    ta.placeholder = '输入便签内容…';
    ta.value = (opts.initial && opts.initial.content) || '';
    panel.appendChild(ta);

    // v8.6.17 待办按钮：插入一行「[ ] 待办事项」（查看时显示方框可勾选，完成后划线并后移）
    const taskBtn = document.createElement('button');
    taskBtn.className = 'sticky-sheet__close sticky-sheet__taskbtn';
    taskBtn.type = 'button';
    taskBtn.textContent = '▢';
    taskBtn.title = '插入待办事项';
    taskBtn.style.cssText = 'margin-right:8px;font-size:15px;';
    taskBtn.addEventListener('click', () => {
      const cur = ta.value;
      const atEnd = !cur || /\n\s*$/.test(cur);
      ta.value = cur + (atEnd ? '' : '\n') + '[ ] ';
      ta.focus();
    });
    head.appendChild(taskBtn);

    // 颜色选择
    const colorRow = document.createElement('div');
    colorRow.className = 'sticky-sheet__row';
    const colorLabel = document.createElement('span');
    colorLabel.className = 'sticky-sheet__label';
    colorLabel.textContent = '选择颜色';
    colorRow.appendChild(colorLabel);
    const dots = document.createElement('div');
    dots.className = 'sticky-sheet__dots';
    let curColor = (opts.initial && opts.initial.color) || '#FFFBEB';
    COLORS.forEach(c => {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = 'sticky-sheet__dot' + (c === curColor ? ' is-active' : '');
      dot.style.background = c;
      dot.style.borderColor = c === '#FFFFFF' ? '#D9D9D9' : 'rgba(0,0,0,0.08)';
      dot.addEventListener('click', () => {
        curColor = c;
        dots.querySelectorAll('.sticky-sheet__dot').forEach(x => x.classList.remove('is-active'));
        dot.classList.add('is-active');
      });
      dots.appendChild(dot);
    });
    colorRow.appendChild(dots);
    panel.appendChild(colorRow);

    // 置顶开关
    const pinRow = document.createElement('div');
    pinRow.className = 'sticky-sheet__row';
    const pinLabel = document.createElement('span');
    pinLabel.className = 'sticky-sheet__label';
    pinLabel.textContent = '📌 置顶此便签';
    const pinSwitch = document.createElement('div');
    pinSwitch.className = 'sticky-sheet__switch' + ((opts.initial && opts.initial.pinned) ? ' is-on' : '');
    pinSwitch.addEventListener('click', () => pinSwitch.classList.toggle('is-on'));
    pinRow.appendChild(pinLabel);
    pinRow.appendChild(pinSwitch);
    panel.appendChild(pinRow);

    // 保存
    const saveBtn = document.createElement('button');
    saveBtn.className = 'sticky-sheet__save';
    saveBtn.textContent = '保存';
    saveBtn.addEventListener('click', () => {
      const content = ta.value.trim();
      if (!content) { App.Components.toast('便签内容不能为空', 'error'); return; }
      overlay.remove();
      if (typeof opts.onSave === 'function') {
        opts.onSave({ content: content, color: curColor, pinned: pinSwitch.classList.contains('is-on') });
      }
    });
    panel.appendChild(saveBtn);

    overlay.appendChild(panel);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
    container.appendChild(overlay);
    setTimeout(() => { ta.focus(); }, 60);
  },

  // ===== 便签卡片（瀑布流用；点击/长按弹操作菜单） =====
  // opts: { sticky, onRefresh }  onRefresh 在增删改后由调用方重渲染
  stickyCard(sticky, opts) {
    const card = document.createElement('div');
    card.className = 'sticky-card' + (sticky.pinned ? ' is-pinned' : '');
    card.style.background = sticky.color || '#FFFBEB';

    const content = document.createElement('div');
    content.className = 'sticky-card__content';
    // v8.6.17 待办渲染：`[ ] 事项`/`[x] 事项` 行 → 方框可勾选；完成后划线 + 显示后移（已完成的待办行排到末尾）
    const rawContent = sticky.content || '';
    const lines = String(rawContent).split('\n');
    const doneTasks = [];
    let html = '';
    const escTxt = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    lines.forEach((line) => {
      const m = line.match(/^\s*\[([ xX])\]\s+(.*)$/);
      if (m) {
        const isDone = m[1] !== ' ';
        const row = '<label class="sticky-task' + (isDone ? ' sticky-task--done' : '') + '">' +
          '<input type="checkbox" data-raw="' + escTxt(line) + '" ' + (isDone ? 'checked' : '') + '>' +
          '<span class="sticky-task__text">' + escTxt(m[2]) + '</span></label>';
        if (isDone) doneTasks.push(row);
        else html += row;
      } else {
        html += '<div>' + escTxt(line) + '</div>';
      }
    });
    html += doneTasks.join('');
    content.innerHTML = html;
    card.appendChild(content);
    // 待办勾选交互：切换 [ ] ↔ [x]，划线 + 重排（完成后自动后移）
    content.querySelectorAll('input[type=checkbox][data-raw]').forEach((cb) => {
      cb.addEventListener('change', async () => {
        const old = cb.dataset.raw;
        const pat = /^(\s*)\[[ xX]\]/;
        const repl = cb.checked ? '$1[x]' : '$1[ ]';
        const newContent = String(sticky.content || '').split('\n').map((l) => (l === old ? l.replace(pat, repl) : l)).join('\n');
        sticky.content = newContent;
        try { await App.DB.updateSticky(sticky); } catch (e) { /* 忽略 */ }
        if (opts.onRefresh) opts.onRefresh();
      });
    });

    const meta = document.createElement('div');
    meta.className = 'sticky-card__meta';
    meta.textContent = App.Utils.formatRelativeTime(sticky.updatedAt || sticky.createdAt);
    card.appendChild(meta);

    card.addEventListener('click', async () => {
      const action = await App.Components.actionSheet([
        { label: '✏️ 编辑', value: 'edit' },
        { label: '📋 复制内容', value: 'copy' },
        { label: '🗑️ 删除', value: 'delete' }
      ], (sticky.content || '').slice(0, 18));
      if (!action) return;

      if (action === 'edit') {
        App.Components.stickySheet({
          title: '编辑便签',
          initial: sticky,
          onSave: async (data) => {
            Object.assign(sticky, data);
            try { await App.DB.updateSticky(sticky); } catch (e) { App.Components.toast('保存失败', 'error'); return; }
            App.Components.toast('已保存 ✓', 'success');
            if (opts && typeof opts.onRefresh === 'function') opts.onRefresh();
          }
        });
      } else if (action === 'copy') {
        try {
          await navigator.clipboard.writeText(sticky.content || '');
          App.Components.toast('已复制到剪贴板', 'success');
        } catch (e) {
          App.Components.toast('复制失败', 'error');
        }
      } else if (action === 'delete') {
        const ok = await App.Components.confirm('删除便签', '确定删除这条便签？此操作不可撤销。', '删除', '取消', true);
        if (ok) {
          card.style.transition = 'transform 0.18s ease, opacity 0.18s ease';
          card.style.transform = 'scale(0.6)';
          card.style.opacity = '0';
          setTimeout(async () => {
            try { await App.DB.removeSticky(sticky.id); } catch (e) {}
            if (opts && typeof opts.onRefresh === 'function') opts.onRefresh();
          }, 170);
        }
      }
    });

    return card;
  },
  centeredPicker(options, title, subtitle, longPress) {
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');

      const overlay = document.createElement('div');
      overlay.className = 'cp-overlay';

      // 滚动锁：锁定背景，关闭/选中/取消时恢复
      App.Components._lockScroll();
      const closeOverlay = () => { App.Components._unlockScroll(); overlay.remove(); };

      const card = document.createElement('div');
      card.className = 'cp-card';

      // 标题行：标题 + 关闭按钮
      const headerRow = document.createElement('div');
      headerRow.className = 'cp-header';
      if (title) {
        const t = document.createElement('span');
        t.className = 'cp-title';
        t.textContent = title;
        headerRow.appendChild(t);
      }
      const closeBtn = document.createElement('button');
      closeBtn.className = 'cp-close';
      closeBtn.innerHTML = '✕';
      closeBtn.title = '关闭';
      closeBtn.addEventListener('click', () => { closeOverlay(); resolve(null); });
      headerRow.appendChild(closeBtn);
      card.appendChild(headerRow);

      // 副标题/描述文字
      if (subtitle) {
        const sub = document.createElement('div');
        sub.className = 'cp-subtitle';
        sub.textContent = subtitle;
        card.appendChild(sub);
      }

      // 选项列表
      const list = document.createElement('div');
      list.className = 'cp-list';

      options.forEach(opt => {
        const item = document.createElement('div');
        item.className = 'cp-item';

        if (opt.icon) {
          const iconWrap = document.createElement('span');
          iconWrap.className = 'cp-item-icon';
          iconWrap.innerHTML = opt.icon;
          item.appendChild(iconWrap);
        }

        const textWrap = document.createElement('div');
        textWrap.className = 'cp-item-text';

        const labelEl = document.createElement('div');
        labelEl.className = 'cp-item-label';
        labelEl.textContent = opt.label;
        textWrap.appendChild(labelEl);

        if (opt.desc) {
          const descEl = document.createElement('div');
          descEl.className = 'cp-item-desc';
          descEl.textContent = opt.desc;
          textWrap.appendChild(descEl);
        }

        item.appendChild(textWrap);

        item.addEventListener('click', () => {
          closeOverlay();
          resolve(opt.value !== undefined ? opt.value : opt.label);
        });

        // 长按标签：打开排序菜单，并在原列表就地重排
        if (longPress && longPress.kind && opt.value !== '__custom__') {
          App.Components.bindTagLongPress(item, longPress.kind, longPress.module, opt.label, () => {
            const lib = longPress.kind === 'kp'
              ? (App.Constants.isFlatSubject(longPress.module) ? App.Tags.getSubjectKnowledgePoints(longPress.module) : App.Tags.getKnowledgePoints(longPress.module))
              : (App.Constants.isFlatSubject(longPress.module) ? App.Tags.getSubjectErrorCauses(longPress.module) : App.Tags.getMergedErrorCauses(longPress.module));
            const rows = Array.from(list.children);
            rows.sort((a, b) => {
              const la = ((a.querySelector('.cp-item-label') || {}).textContent || '');
              const lb = ((b.querySelector('.cp-item-label') || {}).textContent || '');
              const ia = lib.indexOf(la); const ib = lib.indexOf(lb);
              return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib);
            });
            rows.forEach(r => list.appendChild(r));
          });
        }

        list.appendChild(item);
      });

      card.appendChild(list);

      // 底部取消按钮
      const cancelRow = document.createElement('div');
      cancelRow.className = 'cp-cancel-row';
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'cp-cancel-btn';
      cancelBtn.textContent = '取消';
      cancelBtn.addEventListener('click', () => { closeOverlay(); resolve(null); });
      cancelRow.appendChild(cancelBtn);
      card.appendChild(cancelRow);

      overlay.appendChild(card);
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) { closeOverlay(); resolve(null); }
      });

      container.appendChild(overlay);
    });
  },

  // ===== 加载指示器 =====
  loading() {
    const el = document.createElement('div');
    el.className = 'loading';
    el.textContent = '加载中...';
    return el;
  },

  // ===== 页面返回栏 =====
  // v8.6.31 扩展：opts.onBack 自定义返回回调；opts.rightHtml 右侧按钮组（HTML）
  // 速算练习等自建顶栏统一并入本体系，返回键位置/颜色/大小与全 App 完全一致
  pageHeader(title, rightText, onRightClick, opts) {
    opts = opts || {};
    const header = document.createElement('div');
    header.className = 'page-header';
    // 【iPad 横屏对齐】inner 容器：背景全宽，内容限宽居中（与编辑器/工具栏同宽）
    const inner = document.createElement('div');
    inner.className = 'page-header__inner';

    const backBtn = document.createElement('button');
    backBtn.className = 'page-header__back';
    backBtn.innerHTML = '<svg width="10" height="18" viewBox="0 0 10 18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 1L1 9l7 8"/></svg>';
    backBtn.addEventListener('click', () => (opts.onBack ? opts.onBack() : App.Router.back()));
    inner.appendChild(backBtn);

    const titleEl = document.createElement('div');
    titleEl.className = 'page-header__title';
    titleEl.textContent = title;
    titleEl.style.flex = '1';
    titleEl.style.textAlign = 'center';
    titleEl.style.fontSize = 'var(--font-lg)';
    inner.appendChild(titleEl);

    const rightEl = document.createElement('div');
    rightEl.className = 'page-header__right';
    if (opts.rightHtml) {
      rightEl.innerHTML = opts.rightHtml;
      rightEl.style.display = 'flex';
      rightEl.style.alignItems = 'center';
      rightEl.style.gap = '8px';
    } else if (rightText) {
      rightEl.textContent = rightText;
      if (onRightClick) {
        rightEl.style.cursor = 'pointer';
        rightEl.addEventListener('click', onRightClick);
      }
    }
    inner.appendChild(rightEl);

    header.appendChild(inner);
    return header;
  },

  // ===== 分割标题 =====
  sectionTitle(title, rightText, onRightClick) {
    const el = document.createElement('div');
    el.className = 'section-title';
    el.innerHTML = `<span>${title}</span>`;
    if (rightText) {
      el.innerHTML += `<span class="section-title__right">${rightText}</span>`;
      if (onRightClick) {
        el.querySelector('.section-title__right').addEventListener('click', onRightClick);
      }
    }
    return el;
  }
};

// v8.14.11 通用选择弹窗（对齐画布：选科目/选模块/选择考点/选择错因弹窗）
// opts:
//   title: 弹窗标题
//   mode: 'list' | 'chips'
//     'list'  → 选项横向列表（单选，选中浅蓝底）——科目/模块
//     'chips' → 输入行 + 已选chips + 建议chips（多选）——考点/错因
//   options: 可选项字符串数组（list 为全部选项；chips 为建议标签）
//   selected: 当前已选（list 为 string；chips 为 array/string）
//   max: chips 多选最大数量（0=不限）
//   allowCustom: chips 是否允许自定义输入
//   placeholder: 输入框占位
//   onAddCustom: 自定义值回调（添加时）
//   onDone(sel): 点「确定」回调（返回最终选中值）
App.Components.pickerModal = function (opts) {
  opts = opts || {};
  const container = document.getElementById('modal-container');
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';

  // 滚动锁：锁定背景，关闭/确定时恢复
  App.Components._lockScroll();
  const closeOverlay = () => { App.Components._unlockScroll(); overlay.remove(); };

  // 选中态
  let selected = opts.mode === 'list'
    ? (opts.selected || '')
    : (Array.isArray(opts.selected) ? opts.selected.slice() : (opts.selected ? [opts.selected] : []));
  const maxCount = opts.max || 0;
  // 归一化选项：兼容「字符串数组」与「{name:...}对象数组」
  const normOpts = (opts.options || []).map(function (o) { return typeof o === 'string' ? o : (o && o.name) || String(o); });
  opts.options = normOpts;

  const dialog = document.createElement('div');
  dialog.className = 'picker-modal';
  dialog.style.display = 'flex';
  dialog.style.flexDirection = 'column';
  dialog.style.gap = '14px';

  // 标题行
  const headRow = document.createElement('div');
  headRow.className = 'picker-modal__head';
  const titleEl = document.createElement('div');
  titleEl.className = 'picker-modal__title';
  titleEl.textContent = opts.title || '选择';
  headRow.appendChild(titleEl);
  // 占位：把标题推到左侧，管理/关闭按钮靠右
  const headSpacer = document.createElement('div');
  headSpacer.style.flex = '1';
  headRow.appendChild(headSpacer);
  // 管理按钮（可选）：opts.manage 为 { kind: 'kp'|'ec', module } 时，右上角显示「管理」，点击切换到标签管理视图
  if (opts.manage) {
    const manageBtn = document.createElement('button');
    manageBtn.type = 'button';
    manageBtn.className = 'picker-modal__manage';
    manageBtn.textContent = '管理';
    manageBtn.addEventListener('click', () => {
      renderManageView();
    });
    headRow.appendChild(manageBtn);
  }
  const closeBtn = document.createElement('button');
  closeBtn.type = 'button';
  closeBtn.className = 'picker-modal__close';
  closeBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M1 1l12 12M13 1L1 13" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
  closeBtn.addEventListener('click', () => closeOverlay());
  headRow.appendChild(closeBtn);
  dialog.appendChild(headRow);

  if (opts.mode === 'list') {
    // ===== 单项列表 =====
    const list = document.createElement('div');
    list.className = 'picker-modal__list';
    opts.options.forEach(opt => {
      const item = document.createElement('div');
      item.className = 'picker-modal__item';
      if (selected === opt) item.classList.add('active');
      item.textContent = opt;
      item.addEventListener('click', () => {
        selected = opt;
        list.querySelectorAll('.picker-modal__item').forEach(i => i.classList.remove('active'));
        item.classList.add('active');
      });
      list.appendChild(item);
    });
    dialog.appendChild(list);
  } else {
    // ===== chips：输入行 + 已选 + 建议 =====
    const inputRow = document.createElement('div');
    inputRow.className = 'picker-modal__inputrow';
    const input = document.createElement('input');
    input.className = 'picker-modal__input';
    input.placeholder = opts.placeholder || '输入自定义标签…';
    inputRow.appendChild(input);
    const addBtn = document.createElement('button');
    addBtn.type = 'button';
    addBtn.className = 'picker-modal__addbtn';
    addBtn.textContent = '添加';
    addBtn.addEventListener('click', () => addValue());
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addValue(); } });
    inputRow.appendChild(addBtn);
    dialog.appendChild(inputRow);

    // 已选 chips
    const selWrap = document.createElement('div');
    selWrap.className = 'picker-modal__chips';
    const renderSelected = () => {
      selWrap.innerHTML = '';
      selected.forEach((v, i) => {
        const chip = document.createElement('span');
        chip.className = 'picker-chip picker-chip--sel';
        chip.textContent = v;
        const x = document.createElement('span');
        x.className = 'picker-chip__x';
        x.textContent = '×';
        x.addEventListener('click', () => { selected.splice(i, 1); renderSelected(); });
        chip.appendChild(x);
        selWrap.appendChild(chip);
      });
    };
    renderSelected();
    dialog.appendChild(selWrap);

    // 建议 chips
    const sugWrap = document.createElement('div');
    sugWrap.className = 'picker-modal__chips';
    const suggestions = (opts.options || []).filter(o => !selected.includes(o));
    suggestions.forEach(sug => {
      const chip = document.createElement('span');
      chip.className = 'picker-chip';
      chip.textContent = sug;
      chip.addEventListener('click', () => {
        if (selected.includes(sug)) return;
        if (maxCount === 1) selected = [sug];
        else if (maxCount > 1 && selected.length >= maxCount) { App.Components.toast('最多选择 ' + maxCount + ' 个', 'error'); return; }
        else selected.push(sug);
        renderSelected();
      });
      sugWrap.appendChild(chip);
    });
    dialog.appendChild(sugWrap);

    function addValue() {
      const val = input.value.trim();
      if (!val) return;
      if (selected.includes(val)) { input.value = ''; return; }
      if (maxCount === 1) selected = [val];
      else if (maxCount > 1 && selected.length >= maxCount) { App.Components.toast('最多选择 ' + maxCount + ' 个', 'error'); return; }
      else selected.push(val);
      if (opts.onAddCustom) opts.onAddCustom(val);
      input.value = '';
      renderSelected();
    }
  }

  // 确定按钮
  const okBtn = document.createElement('button');
  okBtn.type = 'button';
  okBtn.className = 'picker-modal__ok';
  okBtn.textContent = '确定';
  okBtn.addEventListener('click', () => {
    const result = opts.mode === 'list' ? selected : selected.slice();
    closeOverlay();
    if (opts.onDone) opts.onDone(result);
  });
  dialog.appendChild(okBtn);

  overlay.appendChild(dialog);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) closeOverlay(); });
  container.appendChild(overlay);
  if (opts.mode === 'chips') {
    setTimeout(() => { const inp = overlay.querySelector('.picker-modal__input'); if (inp) inp.focus(); }, 0);
  }

  // ===== 管理视图：点击右上角「管理」后，把弹窗内容切换为考点/错因管理（与考点管理页 UI 一致）=====
  function renderManageView() {
    // 清空弹窗内容
    dialog.innerHTML = '';
    dialog.style.gap = '0';

    // 头部：标题 + 返回 + 关闭
    const mHead = document.createElement('div');
    mHead.className = 'picker-modal__head';
    const backBtn = document.createElement('button');
    backBtn.type = 'button';
    backBtn.className = 'picker-modal__manage';
    backBtn.textContent = '‹ 返回';
    backBtn.addEventListener('click', () => {
      // 返回选择视图：整弹窗重建（重新打开 pickerModal）
      const prevSelected = selected;
      closeOverlay();
      App.Components.pickerModal(Object.assign({}, opts, { selected: prevSelected }));
    });
    mHead.appendChild(backBtn);
    const mTitle = document.createElement('div');
    mTitle.className = 'picker-modal__title';
    mTitle.textContent = (opts.manage.kind === 'kp' ? '考点' : '错因') + '管理';
    mHead.appendChild(mTitle);
    const mSpacer = document.createElement('div');
    mSpacer.style.flex = '1';
    mHead.appendChild(mSpacer);
    const mClose = document.createElement('button');
    mClose.type = 'button';
    mClose.className = 'picker-modal__close';
    mClose.innerHTML = '<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M1 1l12 12M13 1L1 13" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
    mClose.addEventListener('click', () => closeOverlay());
    mHead.appendChild(mClose);
    dialog.appendChild(mHead);

    // 管理内容容器（可滚动）。注意：tagManager 会覆盖其挂载元素的 className，
    // 故用外层 .picker-modal__mgm 承载滚动，内层再给 tagManager，避免滚动样式被冲掉。
    const mgrWrap = document.createElement('div');
    mgrWrap.className = 'picker-modal__mgm';
    const mgrInner = document.createElement('div');
    mgrWrap.appendChild(mgrInner);
    dialog.appendChild(mgrWrap);

    // 复用考点管理页同款 tagManager 组件：考点(kp) 或 错因(ec) 单独管理
    App.Components.tagManager(mgrInner, {
      title: (opts.manage.kind === 'kp' ? '考点' : '错因') + '管理',
      kinds: [opts.manage.kind],
      onDone: () => {}
    });
  }

  return overlay;
};


