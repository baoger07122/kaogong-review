/* 弹窗、标签、卡片和表单组件 */
Object.assign(App.Components, {
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

});
