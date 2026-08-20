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

});
