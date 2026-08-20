/* 涂鸦保护模块：以下实现只做模块封装，不改写功能逻辑。 */
Object.assign(App.Components, {
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

});
