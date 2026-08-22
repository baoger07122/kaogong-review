/* Markdown、HTML 和 Notion 编辑器组件 */
Object.assign(App.Components, {
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
    let activeTable = null;
    let activeCell = null;
    const captureSel = () => {
      try {
        const sel = window.getSelection();
        if (!sel || sel.rangeCount === 0) return;
        const r = sel.getRangeAt(0);
        if (r && area.contains(r.commonAncestorContainer)) savedRange = r.cloneRange();
      } catch (e) { /* 忽略 */ }
    };
    area.addEventListener('mouseup', captureSel);
    area.addEventListener('keyup', captureSel);
    area.addEventListener('focusin', captureSel);
    area.addEventListener('input', () => {
      if (opts.onChange) opts.onChange(area.innerHTML);
      keepCaretVisible();
    });

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
        const cell = getCellFromNode(e.target) || getCellFromSelection();
        if (cell) moveTableCell(cell, e.shiftKey ? -1 : 1);
        else indentParagraph(e.shiftKey ? -1 : 1);
      }
    });
    // v8.5.6 移动端格式栏显示：旧显示逻辑只认 .notion-editable，htmlEditor 需自触发
    area.addEventListener('focusin', () => {
      if (App.Components._showMobileToolbar) App.Components._showMobileToolbar();
      keepCaretVisible();
    });
    area.addEventListener('focusout', (e) => {
      const next = e.relatedTarget;
      if (next && wrapper.contains(next)) return;
      setTimeout(() => {
        if (App.Components._hideMobileToolbar) App.Components._hideMobileToolbar();
        if (App.Components._setMobileToolbarMode) App.Components._setMobileToolbarMode('default');
      }, 220);
    });
    area.addEventListener('click', (e) => {
      const cell = getCellFromNode(e.target);
      if (cell) setActiveCell(cell);
      else setActiveCell(null);
    });
    wrapper.addEventListener('mousedown', (e) => {
      const t = e.target;
      if (t && t.closest && t.closest('.notion-tool-btn, .notion-mobile-fmt-item')) e.preventDefault();
    }, true);

    function ensureSelection() {
      let sel = null;
      try { sel = window.getSelection(); } catch (e) { /* 忽略 */ }
      let r = (sel && sel.rangeCount > 0) ? sel.getRangeAt(0) : null;
      if (!r || !area.contains(r.commonAncestorContainer)) {
        if (savedRange && area.contains(savedRange.commonAncestorContainer)) r = savedRange;
      }
      if (r && area.contains(r.commonAncestorContainer)) {
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
    function keepCaretVisible() {
      if (typeof window === 'undefined' || typeof window.requestAnimationFrame !== 'function') return;
      window.requestAnimationFrame(() => {
        try {
          const r = ensureSelection();
          if (!r) return;
          const node = r.startContainer && r.startContainer.nodeType === 1
            ? r.startContainer : (r.startContainer && r.startContainer.parentElement);
          const target = node && area.contains(node) ? (node.closest && node.closest('td,th,p,h1,h2,h3,li,blockquote,pre,div') || node) : area;
          if (!target || typeof target.getBoundingClientRect !== 'function') return;
          let rect = r.getBoundingClientRect ? r.getBoundingClientRect() : null;
          if (!rect || (!rect.height && !rect.width)) rect = target.getBoundingClientRect();
          const vv = window.visualViewport;
          const viewTop = vv ? vv.offsetTop : 0;
          const viewBottom = vv ? vv.offsetTop + vv.height : window.innerHeight;
          const bar = document.querySelector('.notion-mobile-toolbar.is-visible');
          const barTop = bar ? bar.getBoundingClientRect().top : viewBottom - 24;
          const safeBottom = Math.min(viewBottom - 12, barTop - 12);
          if (rect.bottom > safeBottom) window.scrollBy(0, rect.bottom - safeBottom);
          else if (rect.top < viewTop + 12) window.scrollBy(0, rect.top - (viewTop + 12));
        } catch (e) { /* 某些浏览器在选区变化瞬间没有可测量矩形，忽略即可 */ }
      });
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
      { b: '⊞', title: '插入表格', fn: () => insertTable(3, 3) },
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
    function insertNodeAt(html, options) {
      const opts2 = options || {};
      const tmp = document.createElement('div');
      tmp.innerHTML = html;
      const n = tmp.firstChild;
      const r = ensureSelection();
      if (r && r.startContainer && area.contains(r.startContainer)) {
        try {
          if (opts2.replaceSelection !== false && !r.collapsed) r.deleteContents();
          r.insertNode(n);
        } catch (e) { area.appendChild(n); }
      } else area.appendChild(n);
      if (opts.onChange) opts.onChange(area.innerHTML);
      return n;
    }
    function tableMarkup(rows, cols) {
      const r = Math.max(1, Math.min(6, parseInt(rows, 10) || 3));
      const c = Math.max(1, Math.min(6, parseInt(cols, 10) || 3));
      let html = '<table><tbody>';
      for (let y = 0; y < r; y++) {
        html += '<tr>';
        for (let x = 0; x < c; x++) html += '<td><br></td>';
        html += '</tr>';
      }
      return html + '</tbody></table>';
    }
    function insertTable(rows, cols) {
      const n = insertNodeAt(tableMarkup(rows, cols), { replaceSelection: false });
      const td = n && n.querySelector('td');
      if (td) {
        setActiveCell(td);
        placeCaretAtEnd(td);
        keepCaretVisible();
      }
    }
    function getCellFromNode(node) {
      if (!node) return null;
      const el = node.nodeType === 1 ? node : node.parentElement;
      return el && el.closest ? el.closest('td,th') : null;
    }
    function getCellFromSelection() {
      try {
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount) return null;
        return getCellFromNode(sel.getRangeAt(0).startContainer);
      } catch (e) { return null; }
    }
    function setActiveCell(cell) {
      area.querySelectorAll('td[data-table-active], th[data-table-active]').forEach(el => el.removeAttribute('data-table-active'));
      activeCell = cell && area.contains(cell) ? cell : null;
      activeTable = activeCell ? activeCell.closest('table') : null;
      if (activeCell) activeCell.setAttribute('data-table-active', 'true');
      if (App.Components._setMobileToolbarMode) App.Components._setMobileToolbarMode(activeCell ? 'table' : 'default');
    }
    function getCurrentTable() {
      const cell = activeCell || getCellFromSelection();
      return cell && area.contains(cell) ? cell.closest('table') : activeTable;
    }
    function focusTableCell(cell) {
      if (!cell) return;
      setActiveCell(cell);
      placeCaretAtEnd(cell);
      keepCaretVisible();
    }
    function moveTableCell(cell, direction) {
      const table = cell && cell.closest('table');
      if (!table) return;
      const cells = Array.from(table.rows).flatMap(row => Array.from(row.cells));
      const currentIndex = cells.indexOf(cell);
      if (currentIndex < 0) return;
      let nextIndex = currentIndex + direction;
      if (nextIndex < 0) nextIndex = 0;
      if (nextIndex >= cells.length) {
        if (direction > 0) {
          addTableRow(table, cell);
          return;
        }
        nextIndex = cells.length - 1;
      }
      focusTableCell(cells[nextIndex]);
    }
    function newTableCell() {
      const cell = document.createElement('td');
      cell.innerHTML = '<br>';
      return cell;
    }
    function addTableRow(table, referenceCell) {
      if (!table) return;
      const refRow = referenceCell && referenceCell.closest('tr');
      const count = refRow ? Math.max(1, refRow.cells.length) : Math.max(1, table.rows[0] ? table.rows[0].cells.length : 1);
      const row = document.createElement('tr');
      for (let i = 0; i < count; i++) row.appendChild(newTableCell());
      const refSection = refRow && refRow.parentNode;
      if (refSection && refSection.tagName === 'THEAD') {
        const body = table.tBodies[0] || table.appendChild(document.createElement('tbody'));
        body.insertBefore(row, body.firstChild || null);
      } else if (refRow && refRow.parentNode) {
        refRow.parentNode.insertBefore(row, refRow.nextSibling);
      } else {
        const body = table.tBodies[0] || table.appendChild(document.createElement('tbody'));
        body.appendChild(row);
      }
      if (opts.onChange) opts.onChange(area.innerHTML);
      focusTableCell(row.cells[0]);
    }
    function addTableColumn(table, referenceCell) {
      if (!table) return;
      const refRow = referenceCell && referenceCell.closest('tr');
      const index = refRow ? Math.max(0, referenceCell.cellIndex) : 0;
      Array.from(table.rows).forEach(row => {
        const cell = newTableCell();
        if (index >= row.cells.length) row.appendChild(cell);
        else row.insertBefore(cell, row.cells[index + 1] || null);
      });
      if (opts.onChange) opts.onChange(area.innerHTML);
      const targetRow = refRow || table.rows[0];
      if (targetRow) focusTableCell(targetRow.cells[Math.min(index + 1, targetRow.cells.length - 1)]);
    }
    function deleteTableRow(table, referenceCell) {
      if (!table || table.rows.length <= 1) {
        if (App.Components.toast) App.Components.toast('表格至少保留一行', 'info');
        return;
      }
      const row = (referenceCell && referenceCell.closest('tr')) || table.rows[table.rows.length - 1];
      const next = row.nextElementSibling || row.previousElementSibling;
      row.remove();
      if (opts.onChange) opts.onChange(area.innerHTML);
      focusTableCell(next && next.cells[0] ? next.cells[0] : table.rows[0].cells[0]);
    }
    function deleteTableColumn(table, referenceCell) {
      if (!table || !table.rows.length || table.rows[0].cells.length <= 1) {
        if (App.Components.toast) App.Components.toast('表格至少保留一列', 'info');
        return;
      }
      const index = referenceCell ? Math.max(0, referenceCell.cellIndex) : 0;
      Array.from(table.rows).forEach(row => { if (row.cells[index]) row.deleteCell(index); });
      if (opts.onChange) opts.onChange(area.innerHTML);
      const firstRow = table.rows[0];
      if (firstRow) focusTableCell(firstRow.cells[Math.min(index, firstRow.cells.length - 1)]);
    }
    function toggleTableHeader(table) {
      if (!table || !table.rows.length) return;
      if (table.tHead) {
        const headRow = table.tHead.rows[0];
        const body = table.tBodies[0] || table.appendChild(document.createElement('tbody'));
        Array.from(headRow.cells).forEach(cell => {
          if (cell.tagName === 'TH') {
            const td = document.createElement('td');
            td.innerHTML = cell.innerHTML;
            cell.replaceWith(td);
          }
        });
        body.insertBefore(headRow, body.firstChild || null);
        table.tHead.remove();
      } else {
        const firstRow = table.rows[0];
        const head = document.createElement('thead');
        Array.from(firstRow.cells).forEach(cell => {
          if (cell.tagName !== 'TH') {
            const th = document.createElement('th');
            th.innerHTML = cell.innerHTML;
            cell.replaceWith(th);
          }
        });
        head.appendChild(firstRow);
        table.insertBefore(head, table.firstChild);
      }
      if (opts.onChange) opts.onChange(area.innerHTML);
      const first = table.rows[0] && table.rows[0].cells[0];
      if (first) focusTableCell(first);
    }
    function cycleTableAlignment(cell) {
      if (!cell) return;
      const values = ['left', 'center', 'right'];
      const current = cell.style.textAlign || 'left';
      cell.style.textAlign = values[(values.indexOf(current) + 1) % values.length];
      if (opts.onChange) opts.onChange(area.innerHTML);
      focusTableCell(cell);
    }
    function deleteCurrentTable(table) {
      if (!table || !table.parentNode) return;
      const p = document.createElement('p');
      p.innerHTML = '<br>';
      table.parentNode.insertBefore(p, table.nextSibling);
      table.remove();
      setActiveCell(null);
      if (opts.onChange) opts.onChange(area.innerHTML);
      placeCaretAtEnd(p);
    }
    function openTableChooser() {
      let grid = '<div class="notion-mobile-fmt-title">选择表格大小</div><div class="html-table-picker">';
      for (let rows = 1; rows <= 6; rows++) {
        for (let cols = 1; cols <= 6; cols++) {
          grid += '<button type="button" class="html-table-picker__cell" data-rows="' + rows + '" data-cols="' + cols + '">' + rows + '×' + cols + '</button>';
        }
      }
      grid += '</div><div class="html-table-picker__hint">选择后可在表格模式中继续增加或删除行列</div>';
      const { sheet } = openSheet({ height: 'is-format', bodyHtml: grid });
      sheet.querySelectorAll('.html-table-picker__cell').forEach(btn => {
        btn.addEventListener('mousedown', (e) => e.preventDefault());
        btn.addEventListener('click', () => {
          const rows = parseInt(btn.dataset.rows, 10);
          const cols = parseInt(btn.dataset.cols, 10);
          closeSheet();
          insertTable(rows, cols);
        });
      });
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
        if (cmd === 'table') openTableChooser();
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
        case 'table-add-row': addTableRow(getCurrentTable(), activeCell); break;
        case 'table-add-col': addTableColumn(getCurrentTable(), activeCell); break;
        case 'table-delete-row': deleteTableRow(getCurrentTable(), activeCell); break;
        case 'table-delete-col': deleteTableColumn(getCurrentTable(), activeCell); break;
        case 'table-header': toggleTableHeader(getCurrentTable()); break;
        case 'table-align': cycleTableAlignment(activeCell); break;
        case 'table-delete': deleteCurrentTable(getCurrentTable()); break;
        case 'table-done': setActiveCell(null); break;
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

  // ===== 便签轻量富文本编辑器 =====
  // 便签只保留：加粗、减少/增加缩进、无序列表、有序列表。
  // 不注册全局移动格式栏，格式栏固定在便签居中弹窗内部，避免与 Safari 工具栏叠加。
  stickyRichEditor(initialContent, opts) {
    opts = opts || {};
    const wrapper = document.createElement('div');
    wrapper.className = 'sticky-rich-editor';
    const area = document.createElement('div');
    area.className = 'sticky-rich-editor__area';
    area.contentEditable = true;
    area.setAttribute('contenteditable', 'true');
    area.dataset.placeholder = opts.placeholder || '输入便签内容…';

    const esc = (value) => String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
    const plainToHtml = (value) => String(value || '').split('\n').map(line => {
      const task = line.match(/^\s*\[([ xX])\]\s+(.*)$/);
      if (task) return '<p data-sticky-task="' + (task[1] === ' ' ? 'pending' : 'done') + '">' + esc(task[2]) + '</p>';
      return '<p>' + (line ? esc(line) : '<br>') + '</p>';
    }).join('') || '<p><br></p>';
    const looksLikeHtml = (value) => /<\/?[a-z][\s\S]*>/i.test(String(value || ''));
    area.innerHTML = looksLikeHtml(initialContent) ? String(initialContent || '') : plainToHtml(initialContent);

    let savedRange = null;
    const captureSelection = () => {
      try {
        const sel = window.getSelection();
        if (sel && sel.rangeCount) {
          const range = sel.getRangeAt(0);
          if (area.contains(range.commonAncestorContainer)) savedRange = range.cloneRange();
        }
      } catch (e) {}
    };
    const restoreSelection = () => {
      try {
        area.focus({ preventScroll: true });
        if (savedRange && area.contains(savedRange.commonAncestorContainer)) {
          const sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(savedRange);
        }
      } catch (e) {}
    };
    const currentBlock = () => {
      const sel = window.getSelection();
      let node = sel && sel.rangeCount ? sel.getRangeAt(0).startContainer : area;
      if (node && node.nodeType !== 1) node = node.parentElement;
      while (node && node !== area && !/^(P|DIV|LI|H[1-6]|BLOCKQUOTE)$/.test(node.tagName)) node = node.parentElement;
      return node && node !== area ? node : null;
    };
    const INDENT_STEP = 10;
    const indent = (direction) => {
      restoreSelection();
      const block = currentBlock();
      if (!block) {
        const blank = document.createElement('p');
        blank.style.marginLeft = direction > 0 ? INDENT_STEP + 'px' : '';
        blank.innerHTML = '<br>';
        area.appendChild(blank);
        placeCaretAtEnd(blank);
        captureSelection();
        if (opts.onChange) opts.onChange(area.innerHTML);
        return;
      }
      // 统一使用段落左边距，普通文字、空白行及两种列表都能生效；步进缩短为原来的一半。
      const current = parseFloat(block.style.marginLeft) || 0;
      block.style.marginLeft = Math.max(0, current + (direction > 0 ? INDENT_STEP : -INDENT_STEP)) || '';
      captureSelection();
      if (opts.onChange) opts.onChange(area.innerHTML);
    };
    const apply = (command) => {
      restoreSelection();
      if (command === 'bold') document.execCommand('bold');
      else if (command === 'bullet') document.execCommand('insertUnorderedList');
      else if (command === 'numbered') document.execCommand('insertOrderedList');
      else if (command === 'indent') { indent(1); return; }
      else if (command === 'outdent') { indent(-1); return; }
      captureSelection();
      if (opts.onChange) opts.onChange(area.innerHTML);
    };

    const syncToolbarState = () => {
      toolbar.querySelectorAll('[data-command]').forEach(button => {
        let active = false;
        const command = button.dataset.command;
        try {
          if (command === 'bold') active = document.queryCommandState('bold');
          if (command === 'bullet') active = document.queryCommandState('insertUnorderedList');
          if (command === 'numbered') active = document.queryCommandState('insertOrderedList');
        } catch (e) {}
        const block = currentBlock();
        if (command === 'indent') active = !!(block && (parseFloat(block.style.marginLeft) || 0) > 0);
        button.classList.toggle('is-active', !!active);
      });
    };
    area.addEventListener('mouseup', () => { captureSelection(); syncToolbarState(); });
    area.addEventListener('keyup', () => { captureSelection(); syncToolbarState(); });
    area.addEventListener('focusin', captureSelection);
    area.addEventListener('input', () => { captureSelection(); syncToolbarState(); if (opts.onChange) opts.onChange(area.innerHTML); });
    area.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') { e.preventDefault(); indent(e.shiftKey ? -1 : 1); }
    });
    area.addEventListener('paste', (e) => {
      const data = e.clipboardData || window.clipboardData;
      const text = data && data.getData('text/plain');
      if (!text || !App.Utils.simpleMarkdown) return;
      const trimmed = text.trim();
      const isMarkdown = /\n/.test(text) || /^#{1,4}\s/.test(trimmed) || /^[-*]\s/.test(trimmed)
        || /^\d+\.\s/.test(trimmed) || /^>\s?/.test(trimmed) || /\*\*.+\*\*/.test(trimmed)
        || /`[^`]+`/.test(trimmed);
      if (!isMarkdown) return;
      e.preventDefault();
      restoreSelection();
      try { document.execCommand('insertHTML', false, App.Utils.simpleMarkdown(text)); }
      catch (err) { document.execCommand('insertText', false, text); }
      captureSelection();
      if (opts.onChange) opts.onChange(area.innerHTML);
    });

    const toolbar = document.createElement('div');
    toolbar.className = 'sticky-rich-editor__toolbar';
    [
      { label: '<b>B</b>', title: '加粗', command: 'bold' },
      { label: '⇤', title: '减少缩进', command: 'outdent' },
      { label: '⇥', title: '增加缩进', command: 'indent' },
      { label: '•', title: '无序列表', command: 'bullet' },
      { label: '1.', title: '有序列表', command: 'numbered' }
    ].forEach(item => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'sticky-rich-editor__tool';
      button.dataset.command = item.command;
      button.innerHTML = item.label;
      button.title = item.title;
      button.setAttribute('aria-label', item.title);
      button.addEventListener('mousedown', (e) => e.preventDefault());
      button.addEventListener('pointerdown', (e) => e.preventDefault());
      button.addEventListener('click', () => {
        button.classList.add('is-pressed');
        setTimeout(() => button.classList.remove('is-pressed'), 160);
        apply(item.command);
        syncToolbarState();
      });
      toolbar.appendChild(button);
    });
    wrapper.appendChild(area);
    wrapper.appendChild(toolbar);

    const sanitize = (html) => {
      const holder = document.createElement('div');
      holder.innerHTML = String(html || '');
      holder.querySelectorAll('script,style,iframe,object,embed,form').forEach(el => el.remove());
      holder.querySelectorAll('*').forEach(el => {
        Array.from(el.attributes).forEach(attr => {
          if (/^on/i.test(attr.name) || ['href', 'src', 'action', 'formaction'].includes(attr.name)) el.removeAttribute(attr.name);
        });
      });
      return holder.innerHTML;
    };
    const hasRichFormat = () => !!area.querySelector('strong,b,em,i,u,s,ul,ol,li,blockquote,pre,code,[style*="margin-left"]');
    const plainText = () => Array.from(area.querySelectorAll(':scope > p, :scope > div')).map(block => {
      const task = block.dataset && block.dataset.stickyTask;
      const value = String(block.innerText || block.textContent || '').replace(/\u00a0/g, '');
      return task ? '[' + (task === 'done' ? 'x' : ' ') + '] ' + value : value;
    }).join('\n') || String(area.innerText || area.textContent || '').replace(/\u00a0/g, '');

    return {
      element: wrapper,
      area,
      getHtml: () => sanitize(area.innerHTML),
      getContent: () => hasRichFormat() ? sanitize(area.innerHTML) : plainText().trim(),
      setContent: (value) => { area.innerHTML = looksLikeHtml(value) ? String(value || '') : plainToHtml(value); },
      focusAtEnd: () => {
        area.focus();
        const range = document.createRange();
        range.selectNodeContents(area);
        range.collapse(false);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        captureSelection();
      }
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
      // 编辑器容器底部留白：紧凑悬浮卡片高度(46) + 底部间距(8) + 键盘高度，避免内容被遮
      // 就地编辑模式（inlinePadding）只保留最小留白，避免切换瞬间高度突变导致页面重排
      try {
        const basePad = ext.inlinePadding ? 8 : (46 + 8 + 20);
        wrapper.style.paddingBottom = (basePad + kb) + 'px';
      } catch (e) {}
      if (kb > 0) _scrollFocusedBlockIntoView();
      // 格式栏打开时重新定位（避开 Safari「上/下/对号」透明条）
      if (formatBar && formatBar.parentElement) repositionFormatBar();
    };
    // 初始留白（无键盘时：46 + 8 + 20；就地编辑仅 8px，页面高度不突变）
    try { wrapper.style.paddingBottom = ext.inlinePadding ? '8px' : '74px'; } catch (e) {}
    // 键盘高度变化后把聚焦块滚动到可视区；页面普通滚动不再重复触发，避免与格式栏定位形成反馈。
    const _scrollFocusedBlockIntoView = () => {
      if (_keyboardH > 0 && focusedBlockEl && focusedBlockEl.scrollIntoView) {
        focusedBlockEl.scrollIntoView({ block: 'center', behavior: 'auto' });
      }
    };

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


});
