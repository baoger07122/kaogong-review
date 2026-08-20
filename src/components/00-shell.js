/* App.Components 基础壳：滚动锁、移动工具栏和 iPad 布局 */
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
  _registerMobileEditor(inst) {
    this._activeMobileEditor = inst;
    if (this._setMobileToolbarMode) this._setMobileToolbarMode('default');
  },

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
    // 统一交给单例定位器处理，避免路由切换和 visualViewport 各自改写 bottom。
    if (typeof this._refreshMobileToolbarPosition === 'function') {
      this._refreshMobileToolbarPosition();
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
      addRow: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 5h16M4 11h16M4 17h16"/><path d="M18 14v7M14.5 17.5h7"/></svg>',
      addCol: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 4v16M11 4v16M17 4v16"/><path d="M14 18h7M17.5 14.5v7"/></svg>',
      deleteRow: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 5h16M4 11h16M4 17h16"/><path d="M16 14l5 6M21 14l-5 6"/></svg>',
      deleteCol: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 4v16M11 4v16M17 4v16"/><path d="M14 16l6 5M20 16l-6 5"/></svg>',
      header: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 9h16M8 4v5M12 4v5M16 4v5"/></svg>',
      align: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6h16M7 10h10M4 14h16M7 18h10"/></svg>',
      done: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l4 4L19 6"/></svg>',
      // v8.6.4 段落格式按钮（¶）：与文字格式（A）拆分为两个独立入口
      paragraph: '<span style="font-size:20px;font-weight:700;line-height:1">¶</span>',
    };
    const defaultBtns = [
      { key: 'undo', icon: 'undo', title: '撤销', label: '撤销' },
      { key: 'redo', icon: 'redo', title: '重做', label: '重做' },
      { key: 'format', icon: 'textAa', title: '文字格式', label: '文字' },
      { key: 'blockfmt', icon: 'paragraph', title: '段落格式', label: '段落' },
      { key: 'insert', icon: 'plus', title: '插入', label: '插入' },
      { key: 'dismiss', icon: 'dismiss', title: '收起键盘', label: '收起' },
    ];
    const tableBtns = [
      { key: 'table-add-row', icon: 'addRow', title: '增加行', label: '加行' },
      { key: 'table-add-col', icon: 'addCol', title: '增加列', label: '加列' },
      { key: 'table-delete-row', icon: 'deleteRow', title: '删除行', label: '删行' },
      { key: 'table-delete-col', icon: 'deleteCol', title: '删除列', label: '删列' },
      { key: 'table-header', icon: 'header', title: '切换表头', label: '表头' },
      { key: 'table-align', icon: 'align', title: '切换对齐', label: '对齐' },
      { key: 'table-delete', icon: 'trash', title: '删除表格', label: '删除' },
      { key: 'table-done', icon: 'done', title: '完成表格编辑', label: '完成' },
    ];
    const el = document.createElement('div');
    el.className = 'notion-mobile-toolbar';
    el.setAttribute('data-mobile-toolbar', '1');
    const scroll = document.createElement('div');
    scroll.className = 'notion-mobile-toolbar__scroll';
    const renderToolbarButtons = (items) => {
      scroll.innerHTML = '';
      items.forEach(x => {
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
    };
    renderToolbarButtons(defaultBtns);
    const mL = document.createElement('div');
    mL.className = 'notion-mobile-toolbar__mask left';
    const mR = document.createElement('div');
    mR.className = 'notion-mobile-toolbar__mask right';
    el.appendChild(mL); el.appendChild(scroll); el.appendChild(mR);
    document.body.appendChild(el);
    this._mobileToolbarEl = el;
    this._mobileToolbarMode = 'default';
    this._setMobileToolbarMode = (mode) => {
      const nextMode = mode === 'table' ? 'table' : 'default';
      if (this._mobileToolbarMode === nextMode) return;
      this._mobileToolbarMode = nextMode;
      el.dataset.mode = nextMode;
      renderToolbarButtons(nextMode === 'table' ? tableBtns : defaultBtns);
    };

    // ===== 软键盘适配（单例级，只注册一次） =====
    // iOS Safari 键盘弹出时 visualViewport 高度缩小。只在高度变化时重算位置；
    // 页面滚动会改变 offsetTop，但不应改变底部悬浮格式栏的位置。
    const isMob = window.innerWidth <= 768 || ('ontouchstart' in window);
    let baseInnerH = Math.max(window.innerHeight, window.visualViewport ? window.visualViewport.height : 0);
    let keyboardInset = 0;
    let kbRaf = null;
    let focusTimer = null;
    const KEYBOARD_THRESHOLD = 120;
    const isEditorFocused = () => {
      const active = document.activeElement;
      return !!(active && (active.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName)));
    };
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
    const getKeyboardInset = () => {
      const vv = window.visualViewport;
      if (!vv) return 0;

      // 键盘收起或仅发生 Safari 地址栏变化时，更新基准高度，避免把浏览器界面变化误判成键盘。
      const delta = baseInnerH - vv.height;
      if (delta < KEYBOARD_THRESHOLD) {
        // 编辑器仍聚焦时保留原始基准，防止 iOS 键盘动画同步改变 innerHeight 后丢失键盘高度。
        if (!isEditorFocused()) baseInnerH = Math.max(window.innerHeight, vv.height);
        return 0;
      }
      // 不再使用 vv.offsetTop：它会随页面滚动/浏览器界面变化，正是格式栏跳动的来源。
      return Math.round(delta);
    };
    const updateToolbarBottom = () => {
      const bar = App.Components._mobileToolbarEl;
      if (!bar || !isMob) return;
      const kb = getKeyboardInset();
      keyboardInset = kb;
      // 键盘/系统输入栏占用的可视区高度只在 resize 时更新；普通页面滚动保持此值不变。
      const hideNav = App.Components._navVisible === false;
      const bottom = kb > 0
        ? kb + 8
        : (hideNav ? SAFE_BOTTOM + 8 : NAV_H + SAFE_BOTTOM + 8);
      bar.style.bottom = bottom + 'px';
      // 同时告知当前活动编辑器，让浮动格式栏也能适配
      const inst = App.Components._activeMobileEditor;
      if (inst && typeof inst._onKeyboardChange === 'function') inst._onKeyboardChange(kb);
    };
    this._refreshMobileToolbarPosition = updateToolbarBottom;
    const scheduleKb = () => {
      if (kbRaf) return;
      kbRaf = requestAnimationFrame(() => { kbRaf = null; updateToolbarBottom(); });
    };
    if (isMob && window.visualViewport) {
      window.visualViewport.addEventListener('resize', scheduleKb, { passive: true });
    } else if (isMob) {
      let _lastH = window.innerHeight;
      window.addEventListener('resize', () => {
        const dh = Math.abs(window.innerHeight - _lastH);
        _lastH = window.innerHeight;
        if (dh > KEYBOARD_THRESHOLD && keyboardInset === 0) baseInnerH = window.innerHeight;
        scheduleKb();
      }, { passive: true });
    }
    // 聚焦时也刷新一次（键盘弹出可能不触发 resize）
    window.addEventListener('focusin', scheduleKb, { passive: true });
    window.addEventListener('focusout', () => {
      // 失焦后等待 Safari 完成键盘收起，再读取一次稳定视口；不在过渡中重置基准高度。
      clearTimeout(focusTimer);
      focusTimer = setTimeout(scheduleKb, 160);
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


};
