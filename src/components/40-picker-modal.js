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

