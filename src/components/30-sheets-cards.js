/* 底部面板、通用卡片和页面辅助组件 */
Object.assign(App.Components, {
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

  // ===== 便签编辑面板（居中弹窗：轻量富文本 + 颜色 + 置顶） =====
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
    let closed = false;
    const closeOverlay = () => {
      if (closed) return;
      closed = true;
      App.Components._unlockScroll();
      if (overlay.parentNode) overlay.remove();
    };
    close.addEventListener('click', closeOverlay);
    head.appendChild(t);
    head.appendChild(close);
    panel.appendChild(head);

    // 轻量富文本编辑器：不使用全局移动格式栏，避免与 Safari 原生工具栏重叠。
    const editor = App.Components.stickyRichEditor((opts.initial && opts.initial.content) || '', {
      placeholder: '输入便签内容…'
    });
    panel.appendChild(editor.element);

    // 便签标签：单个短标签，直接在编辑窗口内修改，避免再跳转页面。
    const tagField = document.createElement('label');
    tagField.className = 'sticky-sheet__tag-field';
    const tagLabel = document.createElement('span');
    tagLabel.className = 'sticky-sheet__label';
    tagLabel.textContent = '标签';
    const tagInput = document.createElement('input');
    tagInput.type = 'text';
    tagInput.className = 'sticky-sheet__tag-input';
    tagInput.maxLength = 16;
    tagInput.placeholder = '添加标签（可选）';
    tagInput.value = (opts.initial && opts.initial.tag) || '';
    tagField.appendChild(tagLabel);
    tagField.appendChild(tagInput);
    panel.appendChild(tagField);

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

    // 操作按钮：与新增待办居中弹窗保持一致。
    const actions = document.createElement('div');
    actions.className = 'sticky-sheet__actions';
    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'todo-modal__btn todo-modal__btn--cancel sticky-sheet__cancel';
    cancelBtn.textContent = '取消';
    cancelBtn.addEventListener('click', closeOverlay);
    const saveBtn = document.createElement('button');
    saveBtn.className = 'todo-modal__btn todo-modal__btn--ok sticky-sheet__save';
    saveBtn.textContent = '保存';
    saveBtn.addEventListener('click', () => {
      const content = editor.getContent();
      if (!content) { App.Components.toast('便签内容不能为空', 'error'); return; }
      closeOverlay();
      if (typeof opts.onSave === 'function') {
        opts.onSave({
          content: content,
          tag: tagInput.value.trim(),
          color: curColor,
          pinned: pinSwitch.classList.contains('is-on')
        });
      }
    });
    actions.appendChild(cancelBtn);
    actions.appendChild(saveBtn);
    panel.appendChild(actions);

    overlay.appendChild(panel);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) closeOverlay(); });
    App.Components._lockScroll();
    container.appendChild(overlay);
    setTimeout(() => { editor.focusAtEnd(); }, 60);
  },

  // ===== 便签卡片（直接编辑 + 左滑删除） =====
  // opts: { onRefresh }  onRefresh 在增删改后由调用方重渲染。
  stickyCard(sticky, opts) {
    opts = opts || {};
    const card = document.createElement('div');
    card.className = 'sticky-card' + (sticky.pinned ? ' is-pinned' : '');
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');

    const surface = document.createElement('div');
    surface.className = 'sticky-card__surface';
    surface.style.background = sticky.color || '#FFFBEB';

    const tag = String(sticky.tag || '').trim();
    if (tag) {
      const tagEl = document.createElement('span');
      tagEl.className = 'sticky-card__tag';
      tagEl.textContent = tag;
      surface.appendChild(tagEl);
    }

    const content = document.createElement('div');
    content.className = 'sticky-card__content';
    const rawContent = sticky.content || '';
    const escTxt = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const isRich = /<\/?(?:p|div|strong|b|em|i|u|ul|ol|li|blockquote|pre|code|span)[\s>]/i.test(String(rawContent));
    if (isRich) {
      const holder = document.createElement('div');
      holder.innerHTML = String(rawContent);
      holder.querySelectorAll('script,style,iframe,object,embed,form').forEach(el => el.remove());
      holder.querySelectorAll('*').forEach(el => {
        Array.from(el.attributes).forEach(attr => {
          if (/^on/i.test(attr.name) || ['href', 'src', 'action', 'formaction'].includes(attr.name)) el.removeAttribute(attr.name);
        });
      });
      content.classList.add('sticky-card__content--rich');
      content.innerHTML = holder.innerHTML;
    } else {
      // 兼容旧便签中的 [ ] / [x] 待办语法；新建便签已不再提供待办按钮。
      const lines = String(rawContent).split('\n');
      const doneTasks = [];
      let html = '';
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
      content.innerHTML = html + doneTasks.join('');
    }
    surface.appendChild(content);

    const meta = document.createElement('div');
    meta.className = 'sticky-card__meta';
    const created = new Date(sticky.createdAt || sticky.updatedAt || 0);
    meta.textContent = isNaN(created.getTime()) ? '' : (created.getMonth() + 1) + '月' + created.getDate() + '日';
    surface.appendChild(meta);
    card.appendChild(surface);

    const deleteBtn = document.createElement('button');
    deleteBtn.type = 'button';
    deleteBtn.className = 'sticky-card__delete';
    deleteBtn.setAttribute('aria-label', '删除便签');
    deleteBtn.textContent = '删除';
    card.appendChild(deleteBtn);

    const closeSwipe = () => {
      card.classList.remove('is-swipe-open', 'is-swiping');
      surface.style.transform = '';
    };
    const openEditor = () => {
      App.Components.stickySheet({
        title: '编辑便签',
        initial: sticky,
        onSave: async (data) => {
          Object.assign(sticky, data);
          try { await App.DB.updateSticky(sticky); } catch (e) { App.Components.toast('保存失败', 'error'); return; }
          App.Components.toast('已保存 ✓', 'success');
          if (typeof opts.onRefresh === 'function') opts.onRefresh();
        }
      });
    };
    const copyContent = async () => {
      try {
        const holder = document.createElement('div');
        holder.innerHTML = /<\/?[a-z][\s\S]*>/i.test(String(sticky.content || '')) ? String(sticky.content || '') : '';
        const copied = holder.innerHTML ? (holder.innerText || holder.textContent || '') : (sticky.content || '');
        await navigator.clipboard.writeText(copied);
        App.Components.toast('已复制到剪贴板', 'success');
      } catch (e) { App.Components.toast('复制失败', 'error'); }
    };
    const deleteSticky = async () => {
      const ok = await App.Components.confirm('删除便签', '确定删除这条便签？此操作不可撤销。', '删除', '取消', true);
      if (!ok) return;
      card.classList.add('is-deleting');
      setTimeout(async () => {
        try { await App.DB.removeSticky(sticky.id); } catch (e) {}
        if (typeof opts.onRefresh === 'function') opts.onRefresh();
      }, 170);
    };
    const showMenu = async () => {
      const action = await App.Components.actionSheet([
        { label: '📋 复制内容', value: 'copy' },
        { label: '🗑️ 删除', value: 'delete' }
      ], (sticky.content || '').slice(0, 18));
      if (action === 'copy') await copyContent();
      if (action === 'delete') await deleteSticky();
    };

    // 待办旧数据仍支持勾选，但阻止勾选事件误触发直接编辑。
    content.querySelectorAll('input[type=checkbox][data-raw]').forEach((cb) => {
      cb.addEventListener('click', (e) => e.stopPropagation());
      cb.addEventListener('change', async () => {
        const old = cb.dataset.raw;
        const pat = /^(\s*)\[[ xX]\]/;
        const repl = cb.checked ? '$1[x]' : '$1[ ]';
        sticky.content = String(sticky.content || '').split('\n').map((l) => (l === old ? l.replace(pat, repl) : l)).join('\n');
        try { await App.DB.updateSticky(sticky); } catch (e) { /* 忽略 */ }
        if (typeof opts.onRefresh === 'function') opts.onRefresh();
      });
    });

    deleteBtn.addEventListener('click', (e) => { e.stopPropagation(); closeSwipe(); deleteSticky(); });
    card.addEventListener('contextmenu', (e) => { e.preventDefault(); showMenu(); });

    let startX = null;
    let startY = null;
    let moved = false;
    let swiping = false;
    let suppressClick = false;
    let longPressFired = false;
    let pressTimer = null;
    const clearPress = () => { if (pressTimer) clearTimeout(pressTimer); pressTimer = null; };
    card.addEventListener('pointerdown', (e) => {
      if (e.target.closest && e.target.closest('button,input')) return;
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      startX = e.clientX; startY = e.clientY; moved = false; swiping = false;
      clearPress();
      pressTimer = setTimeout(() => { longPressFired = true; showMenu(); }, 550);
    });
    card.addEventListener('pointermove', (e) => {
      if (startX === null) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (Math.abs(dx) > 8 || Math.abs(dy) > 8) { moved = true; clearPress(); }
      if (dx < -8 && Math.abs(dx) > Math.abs(dy)) {
        swiping = true;
        card.classList.add('is-swiping');
        surface.style.transform = 'translateX(' + Math.max(-78, dx) + 'px)';
      }
    });
    const finishPointer = (e) => {
      clearPress();
      if (swiping) {
        const dx = e.clientX - startX;
        card.classList.toggle('is-swipe-open', dx < -44);
        surface.style.transform = '';
        card.classList.remove('is-swiping');
        suppressClick = true;
      } else if (moved) {
        suppressClick = true;
      }
      startX = null; startY = null;
      if (suppressClick) setTimeout(() => { suppressClick = false; }, 120);
    };
    card.addEventListener('pointerup', finishPointer);
    card.addEventListener('pointercancel', (e) => { clearPress(); if (swiping) closeSwipe(); startX = null; startY = null; });
    card.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.sticky-card__delete')) return;
      if (longPressFired) { longPressFired = false; return; }
      if (suppressClick) return;
      if (card.classList.contains('is-swipe-open')) { closeSwipe(); return; }
      openEditor();
    });
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openEditor(); }
    });
    return card;
  },

  // 按输入顺序左右分配，再各列向下排列，保证两列首张卡片同时从顶部开始。
  stickyMasonry(stickies, className, opts) {
    const wrap = document.createElement('div');
    wrap.className = className || 'sticky-masonry';
    const columns = [0, 1].map(() => {
      const col = document.createElement('div');
      col.className = 'sticky-masonry__column';
      return col;
    });
    (stickies || []).forEach((sticky, index) => {
      columns[index % 2].appendChild(this.stickyCard(sticky, opts || {}));
    });
    columns.forEach(col => wrap.appendChild(col));
    return wrap;
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

});
