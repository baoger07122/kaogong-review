// ===== 考公笔试复盘系统 - 可复用 UI 组件 =====
window.App = window.App || {};

App.Components = {
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

      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) {
          overlay.remove();
          resolve(false);
        }
      });

      overlay.querySelector('.btn-cancel').addEventListener('click', () => {
        overlay.remove();
        resolve(false);
      });

      overlay.querySelector(isDanger ? '.btn-danger' : '.btn-confirm').addEventListener('click', () => {
        overlay.remove();
        resolve(true);
      });

      container.appendChild(overlay);
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

  // ===== 筛选标签栏 =====
  filterTags(items, selected, onChange, colorKey) {
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
  errorCard(error, onSwipeMaster, onSwipeDelete, onClick) {
    const card = document.createElement('div');
    card.className = 'error-card';
    card.style.position = 'relative';
    card.style.overflow = 'hidden';

    const subjectColor = App.Constants.getSubjectColor(error.subject);
    const statusType = error.status === '已掌握' ? 'success' : 'danger';
    const statusText = error.status || '未掌握';

    // 科目颜色映射到 tag 类型
    const subjectTagType = {
      '言语理解': 'primary', '数量关系': 'warning', '判断推理': 'success',
      '资料分析': 'purple', '常识判断': 'gold', '申论': 'teal'
    };

    // 显示考点标签（最多2个）
    const kpTags = (error.knowledgePoints || []).slice(0, 2)
      .map(kp => `<span class="tag tag--neutral">${kp}</span>`).join('');

    card.innerHTML = `
      <div class="error-card__header">
        <span class="tag tag--${subjectTagType[error.subject] || 'neutral'}">${error.subject}</span>
        <span class="tag tag--neutral">${error.module || ''}</span>
        ${kpTags}
        <span class="tag tag--neutral">${error.errorCause || ''}</span>
        <span class="tag tag--${statusType}">${statusText}</span>
      </div>
      <div class="error-card__body">${App.Utils.truncate(error.question, 60)}</div>
      <div class="error-card__footer">
        <span>收录于 ${App.Utils.formatDate(error.createdAt)}</span>
        <span>正确率 ${error.accuracy || 0}%</span>
        ${error.lastReviewDate ? `<span>${App.Utils.daysSince(error.lastReviewDate)}天前复习</span>` : ''}
      </div>
    `;

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
  tagInput(label, options, selectedList, onChange, max, allowCustom, placeholder, persist) {
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
    const optionSet = (options || []).slice();
    const maxCount = max || 0;

    // 已选标签 chips
    const chipsWrap = document.createElement('div');
    chipsWrap.className = 'tag-input__chips';

    // 预设建议标签
    const suggestWrap = document.createElement('div');
    suggestWrap.className = 'tag-input__suggestions';

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
        chipsWrap.appendChild(chip);
      });
    }

    function renderSuggestions() {
      suggestWrap.innerHTML = '';
      const suggestions = optionSet.filter(o => !selected.includes(o));
      if (suggestions.length === 0) {
        suggestWrap.style.display = 'none';
        return;
      }
      suggestWrap.style.display = 'flex';
      suggestions.forEach(opt => {
        const tag = document.createElement('span');
        tag.className = 'tag-input__suggestion';
        tag.textContent = opt;
        tag.addEventListener('click', () => addValue(opt));
        suggestWrap.appendChild(tag);
      });
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
        else if (persist === 'errorCause') App.Tags.addErrorCause(val);
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

    function renderAll() {
      renderChips();
      renderSuggestions();
    }

    return group;
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
  notionEditor(initialContent, placeholder, onChange) {
    const wrapper = document.createElement('div');
    wrapper.className = 'notion-editor';

    let blocks = [];
    if (initialContent) blocks = parseMarkdownToBlocks(initialContent);
    if (blocks.length === 0) blocks.push(createBlock('text', ''));

    let focusedBlockEl = null;
    let handleMenu = null;
    let slashMenu = null;
    let formatBar = null;

    const notifyChange = (() => {
      let t = null;
      return () => {
        clearTimeout(t);
        t = setTimeout(() => {
          if (typeof onChange === 'function') onChange(getContent());
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
      return t.replace(/\u200b/g, '').replace(/\u00a0/g, ' ');
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
      if (be) { const idx = parseInt(be.dataset.index); syncBlockData(be, blocks[idx]); }
      updateFooter(); notifyChange();
    }

    function hideAllMenus() {
      hideSlashMenu(); hideFormatBar(); hideHandleMenu();
    }
    function hideSlashMenu() { if (slashMenu) { slashMenu.remove(); slashMenu = null; } }
    function hideFormatBar() { if (formatBar) { formatBar.remove(); formatBar = null; } }
    function hideHandleMenu() { if (handleMenu) { handleMenu.remove(); handleMenu = null; } }

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
      { b: '标题', t: 'h1', title: '一级标题' },
      { b: '小标', t: 'h2', title: '二级标题' },
      { b: '副标', t: 'h3', title: '三级标题' },
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
    toolbar.appendChild(row1);

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
    const grpIndent = document.createElement('div');
    grpIndent.className = 'notion-toolbar__grp';
    [
      { b: '◀', action: 'outdent', title: '缩出' },
      { b: '▶', action: 'indent', title: '缩进' },
    ].forEach(x => {
      const btn = document.createElement('button');
      btn.className = 'notion-tool-btn';
      btn.textContent = x.b;
      btn.title = x.title;
      btn.addEventListener('click', () => {
          if (!focusedBlockEl) return;
          const idx = parseInt(focusedBlockEl.dataset.index);
          pushUndo();
          if (x.action === 'indent' && blocks[idx].indent < 6) blocks[idx].indent++;
          else if (x.action === 'outdent' && blocks[idx].indent > 0) blocks[idx].indent--;
          reRender(); notifyChange();
        const fe = blocksContainer.querySelector(`[data-index="${idx}"] .notion-editable`);
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
    toolbar.appendChild(row2);

    const blocksContainer = document.createElement('div');
    blocksContainer.className = 'notion-editor__blocks';

    // ===== 斜杠命令菜单 =====
    function showSlashMenu(blockEl, filter) {
      hideSlashMenu();
      slashMenu = document.createElement('div');
      slashMenu.className = 'notion-slash-menu';
      const items = [
        { type: 'text', icon: '📝', label: '文本', desc: '普通文本段落' },
        { type: 'h1', icon: 'H₁', label: '一级标题', desc: '大标题' },
        { type: 'h2', icon: 'H₂', label: '二级标题', desc: '中标题' },
        { type: 'h3', icon: 'H₃', label: '三级标题', desc: '小标题' },
        { type: 'h4', icon: 'H₄', label: '四级标题', desc: '更小标题' },
        { type: 'bullet', icon: '•', label: '无序列表', desc: '项目符号列表' },
        { type: 'numbered', icon: '1.', label: '有序列表', desc: '编号列表' },
        { type: 'todo', icon: '☐', label: '待办事项', desc: '带复选框的任务' },
        { type: 'quote', icon: '"', label: '引用', desc: '引用块' },
        { type: 'callout', icon: '💡', label: '高亮提示', desc: '带背景的提示框' },
        { type: 'toggle', icon: '▸', label: '折叠块', desc: '可展开/收起' },
        { type: 'divider', icon: '—', label: '分割线', desc: '水平分割线' },
        { type: 'code', icon: '</>', label: '代码块', desc: '等宽字体代码' },
        { type: 'table', icon: '⊞', label: '表格', desc: '两列简单表格' },
      ];
      const q = (filter || '').toLowerCase();
      items.forEach(item => {
        if (q && !item.label.includes(q) && !item.desc.includes(q)) return;
        const row = document.createElement('div');
        row.className = 'notion-slash-item';
        row.innerHTML = `<span class="notion-slash-icon">${item.icon}</span><div><span class="notion-slash-label">${item.label}</span><span class="notion-slash-desc">${item.desc}</span></div>`;
        row.addEventListener('click', () => { hideSlashMenu(); changeBlockType(blockEl, item.type); notifyChange(); });
        slashMenu.appendChild(row);
      });
      if (slashMenu.children.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'notion-slash-empty';
        empty.textContent = '没有匹配的块类型';
        slashMenu.appendChild(empty);
      }
      const rect = blockEl.getBoundingClientRect();
      wrapper.appendChild(slashMenu);
      slashMenu.style.top = (rect.bottom - wrapper.getBoundingClientRect().top + 4) + 'px';
      slashMenu.style.left = Math.min(rect.left - wrapper.getBoundingClientRect().left, window.innerWidth - 260) + 'px';
    }

    // ===== 选中文本的格式工具栏 =====
    function showFormatBar(range) {
      hideFormatBar();
      formatBar = document.createElement('div');
      formatBar.className = 'notion-format-bar';
      const fmtTools = [
        { cmd: 'bold', icon: '<b>B</b>', title: '加粗' },
        { cmd: 'italic', icon: '<i>I</i>', title: '斜体' },
        { cmd: 'underline', icon: '<u>U</u>', title: '下划线' },
        { cmd: 'strike', icon: '<s>S</s>', title: '删除线' },
        { cmd: 'code', icon: '<code>&lt;/&gt;</code>', title: '行内代码' },
        { cmd: 'bg-yellow', icon: '<span style="background:#FFE066;padding:0 2px;border-radius:2px;">A</span>', title: '高亮背景' },
        { cmd: 'color-red', icon: '<span style="color:#E03131">A</span>', title: '红色文字' },
        { cmd: 'color-blue', icon: '<span style="color:#1971C2">A</span>', title: '蓝色文字' },
        { cmd: 'color-green', icon: '<span style="color:#2B8A3E">A</span>', title: '绿色文字' },
        { cmd: 'highlight', icon: '<span style="background:#FFEC99;padding:0 2px;">A</span>', title: '黄色高亮' },
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
      try {
        const rect = range.getBoundingClientRect();
        formatBar.style.top = (rect.top - wrapper.getBoundingClientRect().top - 42) + 'px';
        formatBar.style.left = Math.max(0, (rect.left + rect.width / 2 - formatBar.offsetWidth / 2)) + 'px';
      } catch(e) { formatBar.style.top = '40px'; formatBar.style.left = '10px'; }
    }

    function applyFormat(cmd, range) {
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
        case 'color-blue': pushUndo(); wrapSelection(range, 'span', {style:'color:#1971C2'}); break;
        case 'color-green': pushUndo(); wrapSelection(range, 'span', {style:'color:#2B8A3E'}); break;
        case 'bg-yellow': pushUndo(); wrapSelection(range, 'span', {style:'background:#FFE066;padding:0 2px;border-radius:2px;'}); break;
        case 'highlight': pushUndo(); wrapSelection(range, 'mark', {}); break;
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

    // 块手柄菜单（上移/下移/删除/转为文本）
    function showHandleMenu(blockEl) {
      hideHandleMenu();
      handleMenu = document.createElement('div');
      handleMenu.className = 'notion-handle-menu';
      const idx = parseInt(blockEl.dataset.index);
      const actions = [
        { label: '⬆ 上移', fn: () => { moveBlock(idx, -1); } },
        { label: '⬇ 下移', fn: () => { moveBlock(idx, 1); } },
        { label: '🗑 删除', fn: () => { deleteBlock(idx); } },
        { label: '↺ 转为文本', fn: () => { changeBlockType(blockEl, 'text'); notifyChange(); } },
      ];
      if (idx === 0) actions[0].disabled = true;
      if (idx === blocks.length - 1) actions[1].disabled = true;
      actions.forEach(a => {
        const row = document.createElement('div');
        row.className = 'notion-handle-item' + (a.disabled ? ' disabled' : '');
        row.textContent = a.label;
        row.addEventListener('click', () => { hideHandleMenu(); if (!a.disabled) a.fn(); });
        handleMenu.appendChild(row);
      });
      const rect = blockEl.getBoundingClientRect();
      wrapper.appendChild(handleMenu);
      handleMenu.style.top = (rect.top - wrapper.getBoundingClientRect().top + 4) + 'px';
      handleMenu.style.left = (rect.left - wrapper.getBoundingClientRect().left + 18) + 'px';
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
        const idx = parseInt(target.dataset.index);
        pushUndo();
        if (type === 'divider') blocks.splice(idx + 1, 0, createBlock('divider', ''));
        else { const tb = createBlock('table', ''); tb.tableData = [['列1','列2'],['','']]; blocks.splice(idx + 1, 0, tb); }
        reRender(); notifyChange();
        return;
      }
      changeBlockType(target, type);
      notifyChange();
    }

    // ===== 创建块 DOM =====
    function renderBlock(block, index) {
      const el = document.createElement('div');
      el.className = 'notion-block notion-block--' + block.type;
      el.dataset.index = index;
      if (block.indent > 0) el.style.paddingLeft = (24 * block.indent) + 'px';

      const handle = document.createElement('div');
      handle.className = 'notion-block__handle';
      handle.innerHTML = `<svg width="14" height="14" viewBox="0 0 14 14"><circle cx="3" cy="3" r="1.5"/><circle cx="7" cy="3" r="1.5"/><circle cx="11" cy="3" r="1.5"/><circle cx="3" cy="7" r="1.5"/><circle cx="7" cy="7" r="1.5"/><circle cx="11" cy="7" r="1.5"/><circle cx="3" cy="11" r="1.5"/><circle cx="7" cy="11" r="1.5"/><circle cx="11" cy="11" r="1.5"/></svg>`;
      handle.addEventListener('click', (e) => { e.stopPropagation(); showHandleMenu(el); });
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
      } else if (block.type === 'toggle') {
        const box = document.createElement('div');
        box.className = 'notion-toggle';
        const arrow = document.createElement('span');
        arrow.className = 'notion-toggle__arrow';
        arrow.textContent = block.collapsed ? '▸' : '▾';
        const summary = document.createElement('div');
        summary.className = 'notion-toggle__summary';
        summary.setAttribute('placeholder', '折叠标题...');
        summary.textContent = block.summary || '';
        summary.contentEditable = true;
        summary.addEventListener('input', () => { block.summary = summary.textContent; notifyChange(); });
        summary.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); pushUndo(); block.collapsed = false; arrow.textContent = '▾'; detail.style.display = 'block'; const d = detail.querySelector('.notion-editable'); if (d) { d.focus(); placeCaretAtEnd(d); } } });
        arrow.addEventListener('click', () => {
          block.collapsed = !block.collapsed;
          arrow.textContent = block.collapsed ? '▸' : '▾';
          detail.style.display = block.collapsed ? 'none' : 'block';
          notifyChange();
        });
        const detail = document.createElement('div');
        detail.className = 'notion-toggle__detail';
        if (block.collapsed) detail.style.display = 'none';
        detail.appendChild(createEditable(block));
        box.appendChild(arrow);
        box.appendChild(summary);
        box.appendChild(detail);
        content.appendChild(box);
      } else {
        content.appendChild(createEditable(block));
      }

      el.appendChild(content);
      return el;
    }

    // ===== 行内 Markdown → HTML（支持 **bold** *italic* ~~strike~~ `code` ==highlight== [link](url) ）=====
    function renderInlineMarkdown(text) {
      if (!text) return '';
      let html = text
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')  // 先转义 HTML 实体
        // 行内代码（必须在最前面，避免内部格式被处理）
        .replace(/`([^`\n]+)`/g, '<code class="notion-inline-code">$1</code>')
        // 图片 ![alt](url)
        .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:100%;border-radius:4px;">')
        // 链接 [text](url)
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
        // 高亮 ==text==
        .replace(/==(.*?)==/g, '<mark class="notion-highlight">$1</mark>')
        // 删除线 ~~text~~
        .replace(/~~(.*?)~~/g, '<s>$1</s>')
        // 加粗 **text** 或 __text__
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/__(.+?)__/g, '<strong>$1</strong>')
        // 斜体 *text* 或 _text_（不与加粗重叠：排除已处理的 **）
        .replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>').replace(/(?<!_)_([^_]+)_(?!_)/g, '<em>$1</em>')
        // 块内换行（Enter 软回车）保留为 <br>
        .replace(/\n/g, '<br>');
      return html;
    }

    // ===== 粘贴拦截：将粘贴的 Markdown 文本解析为结构化块 + 行内渲染 =====
    function setupPasteHandler(el) {
      el.addEventListener('paste', (e) => {
        const clipboardData = e.clipboardData || window.clipboardData;
        if (!clipboardData) return;
        const text = clipboardData.getData('text/plain');
        if (!text) return;

        // 如果粘贴的是多行 Markdown（含块级语法），替换当前块为解析后的多块
        const lines = text.split('\n');
        if (lines.length > 1 || /^#{1,4}\s|^- \[[ x]\]|^- |^\d+\.\s|^> |^```|^---/.test(text.trim())) {
          e.preventDefault();
          const focused = focusedBlockEl ? focusedBlockEl.closest('.notion-block') : null;
          const insertIdx = focused ? parseInt(focused.dataset.index) : blocks.length - 1;
          const newBlocks = parseMarkdownToBlocks(text);
          if (newBlocks.length > 0) {
            // 对新块的 content 也做行内渲染
            newBlocks.forEach(b => { if (!b.html && b.content) b.html = renderInlineMarkdown(b.content); });
            pushUndo();
            blocks.splice(insertIdx, 1, ...newBlocks);
            reRender();
            // 聚焦到最后一个新插入的块
            const lastIdx = insertIdx + newBlocks.length - 1;
            const lastEl = wrapper.querySelector('.notion-block[data-index="' + lastIdx + '"] .notion-editable');
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
          const idx = parseInt(be.dataset.index);
          const editable = be.querySelector('.notion-editable');
          if (!editable) return;
          // 获取纯文本后用行内 Markdown 重新设置 innerHTML
          const plainText = editable.textContent || '';
          if (plainText !== (blocks[idx].content || '')) {
            blocks[idx].content = plainText;
            blocks[idx].html = renderInlineMarkdown(plainText);
            // 保存光标位置
            const sel = window.getSelection();
            let offset = 0;
            if (sel && sel.rangeCount > 0) {
              const range = sel.getRangeAt(0);
              const pre = range.startContainer;
              offset = pre.nodeType === 3 ? range.startOffset : 0;
            }
            editable.innerHTML = blocks[idx].html || '';
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
      div.dataset.placeholder = placeholder || '输入内容，输入 / 唤起命令...';
      if (block.html) div.innerHTML = block.html;
      else div.innerHTML = renderInlineMarkdown(block.content || '');

      div.addEventListener('focus', () => { focusedBlockEl = div.closest('.notion-block'); });
      div.addEventListener('input', () => {
        noteEditForUndo();
        const be = div.closest('.notion-block');
        syncBlockData(be, blocks[parseInt(be.dataset.index)]);
        updateFooter();
        notifyChange();
        const text = div.textContent;
        if (text.endsWith('/')) showSlashMenu(be, '');
        else if (slashMenu && slashMenu.parentElement) {
          const lastSlash = text.lastIndexOf('/');
          if (lastSlash >= 0) showSlashMenu(be, text.slice(lastSlash + 1));
          else hideSlashMenu();
        }
        setSaveStatus('编辑中…');
      });
      div.addEventListener('keydown', (e) => {
        const be = div.closest('.notion-block');
        const idx = parseInt(be.dataset.index);
        if (e.key === 'Enter' && !e.isComposing) {
          // Enter = 块内换行（软回车）；不再拆分块
          e.preventDefault();
          pushUndo();
          insertSoftBreak(div);
        }
        else if (e.key === 'Backspace') {
          if (div.textContent === '' || (window.getSelection().isCollapsed && div.textContent === '')) { e.preventDefault(); pushUndo(); deleteBlock(idx); }
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
        const idx = parseInt(be.dataset.index);
        const txt = getBlockText(div);
        if (txt !== (blocks[idx].content || '')) blocks[idx].content = txt;
        // 若块内已有富文本（粗体/链接/<br> 等），保留之，不再整体重渲染，避免破坏换行与格式
        if (!div.querySelector('strong,em,code,a,mark,s,br,img')) {
          const rendered = renderInlineMarkdown(txt);
          if (rendered !== div.innerHTML) { blocks[idx].html = rendered; div.innerHTML = rendered; }
        } else {
          blocks[idx].html = div.innerHTML;
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
      if (!block || block.type === 'divider' || block.type === 'table' || block.type === 'toggle') {
        // toggle 的细节由 detail editable 单独同步
        const det = blockEl.querySelector('.notion-toggle__detail .notion-editable');
        if (block.type === 'toggle' && det) { block.content = det.textContent; block.html = det.innerHTML; }
        return;
      }
      const editable = blockEl.querySelector('.notion-editable');
      if (!editable) return;
      block.content = getBlockText(editable);
      block.html = editable.innerHTML;
    }

    function changeBlockType(blockEl, newType) {
      const idx = parseInt(blockEl.dataset.index);
      pushUndo();
      const oldBlock = blocks[idx];
      const carry = (oldBlock.content || '').replace(/^\/\S*$/, '').trim();
      blocks[idx] = createBlock(newType, carry);
      blocks[idx].indent = oldBlock.indent;
      blocks[idx].checked = oldBlock.checked;
      if (newType === 'toggle') { blocks[idx].summary = carry; blocks[idx].content = ''; }
      reRender();
      const newEl = blocksContainer.querySelector(`[data-index="${idx}"] .notion-editable`);
      if (newEl) { newEl.focus(); placeCaretAtEnd(newEl); }
    }

    function splitBlock(idx, editable) {
      const sel = window.getSelection();
      let offset = 0;
      if (sel.rangeCount > 0) {
        const range = sel.getRangeAt(0);
        const preCaret = range.cloneRange();
        preCaret.selectNodeContents(editable);
        preCaret.setEnd(range.startContainer, range.startOffset);
        offset = preCaret.toString().length;
      }
      const block = blocks[idx];
      const text = editable.textContent || '';
      block.content = text.slice(0, offset);
      block.html = '';
      const newBlock = createBlock(block.type, text.slice(offset));
      newBlock.indent = block.indent;
      if (block.type === 'todo') newBlock.checked = false;
      blocks.splice(idx + 1, 0, newBlock);
      reRender();
      const newEl = blocksContainer.querySelector(`[data-index="${idx+1}"] .notion-editable`);
      if (newEl) { newEl.focus(); placeCaretAtEnd(newEl); }
    }

    function deleteBlock(idx) {
      if (blocks.length <= 1) return;
      pushUndo();
      blocks.splice(idx, 1);
      reRender();
      const focusIdx = Math.min(idx, blocks.length - 1);
      const focusEl = blocksContainer.querySelector(`[data-index="${focusIdx}"] .notion-editable`);
      if (focusEl) { focusEl.focus(); placeCaretAtEnd(focusEl); }
    }

    function moveBlock(idx, dir) {
      const ni = idx + dir;
      if (ni < 0 || ni >= blocks.length) return;
      pushUndo();
      const tmp = blocks[idx]; blocks[idx] = blocks[ni]; blocks[ni] = tmp;
      reRender(); notifyChange();
      const el = blocksContainer.querySelector(`[data-index="${ni}"] .notion-editable`);
      if (el) { el.focus(); placeCaretAtEnd(el); }
    }

    function reRender() {
      blocksContainer.innerHTML = '';
      blocks.forEach((block, i) => blocksContainer.appendChild(renderBlock(block, i)));
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
      return { type, content: content || '', html: '', indent: 0, color: '', checked: false, collapsed: false, emoji: '💡', summary: '' };
    }

    // Markdown → 块数组
    function parseMarkdownToBlocks(md) {
      const lines = md.split('\n');
      const result = [];
      let inCode = false, codeLines = [];
      lines.forEach(line => {
        if (inCode) {
          if (line.trim() === '```') { result.push({ type:'code', content: codeLines.join('\n'), html:'', indent:0, collapsed:false, emoji:'💡', summary:'' }); codeLines = []; inCode = false; }
          else codeLines.push(line);
          return;
        }
        if (line.trim() === '```') { inCode = true; return; }
        if (line.trim() === '---') { result.push({ type:'divider', content:'', html:'', indent:0, collapsed:false, emoji:'💡', summary:'' }); return; }

        let type = 'text', content = line, indent = 0;
        while (content.startsWith('  ') || content.startsWith('\t')) { indent++; content = content.replace(/^[ \t]+/, ''); }
        if (/^#{4}\s/.test(content)) { type='h4'; content = content.replace(/^#{4}\s/, ''); }
        else if (/^#{3}\s/.test(content)) { type='h3'; content = content.replace(/^#{3}\s/, ''); }
        else if (/^#{2}\s/.test(content)) { type='h2'; content = content.replace(/^#{2}\s/, ''); }
        else if (/^#\s/.test(content)) { type='h1'; content = content.replace(/^#\s/, ''); }
        else if (/^- \[[ x]\]/.test(content)) { type='todo'; content = content.replace(/^- \[[ x]\]\s?/, ''); }
        else if (/^- /.test(content)) { type='bullet'; content = content.replace(/^- /, ''); }
        else if (/^\d+\.\s/.test(content)) { type='numbered'; content = content.replace(/^\d+\.\s/, ''); }
        else if (/^> 💡\s?/.test(content)) { type='callout'; content = content.replace(/^> 💡\s?/, ''); }
        else if (/^> ▸\s?|^> ▾\s?/.test(content)) { type='toggle'; content = content.replace(/^> [▸▾]\s?/, ''); }
        else if (/^>\s?/.test(content)) { type='quote'; content = content.replace(/^>\s?/, ''); }
        result.push({ type, content, html:'', indent, color:'', checked: /\[x\]/.test(line), collapsed:false, emoji:'💡', summary:'' });
      });
      if (inCode) result.push({ type:'code', content: codeLines.join('\n'), html:'', indent:0, collapsed:false, emoji:'💡', summary:'' });
      return result;
    }

    // 块数组 → Markdown
    function exportToMarkdown() {
      const lines = [];
      let numCounter = 0;
      blocks.forEach(b => {
        const pad = '  '.repeat(b.indent);
        switch(b.type) {
          case 'h1': lines.push(pad + '# ' + stripHtml(b.html || b.content)); break;
          case 'h2': lines.push(pad + '## ' + stripHtml(b.html || b.content)); break;
          case 'h3': lines.push(pad + '### ' + stripHtml(b.html || b.content)); break;
          case 'h4': lines.push(pad + '#### ' + stripHtml(b.html || b.content)); break;
          case 'bullet': lines.push(pad + '- ' + stripHtml(b.html || b.content)); break;
          case 'numbered': numCounter++; lines.push(pad + numCounter + '. ' + stripHtml(b.html || b.content)); break;
          case 'todo': lines.push(pad + '- [' + (b.checked ? 'x' : ' ') + '] ' + stripHtml(b.html || b.content)); break;
          case 'quote': lines.push(pad + '> ' + stripHtml(b.html || b.content)); break;
          case 'callout': lines.push(pad + '> 💡 ' + stripHtml(b.html || b.content)); break;
          case 'toggle': lines.push(pad + '> ▸ ' + stripHtml(b.html || b.content)); break;
          case 'divider': lines.push('---'); break;
          case 'code': lines.push('```' + '\n' + (b.content || '') + '\n```'); break;
          case 'table': if (b.tableData) b.tableData.forEach(r => lines.push('| ' + r.join(' | ') + ' |')); break;
          default: lines.push(pad + stripHtml(b.html || b.content)); break;
        }
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
      blocks.forEach(b => {
        if (b.type === 'table') (b.tableData || []).forEach(r => r.forEach(c => chars += (c || '').length));
        else chars += (stripHtml(b.html || b.content) || '').length;
      });
      footer.innerHTML = `<span class="notion-foot-count">${chars} 字</span><span class="notion-foot-save" id="notion-save-status">就绪</span>`;
    }
    function setSaveStatus(text) {
      const el = footer.querySelector('#notion-save-status');
      if (el) el.textContent = text;
    }

    // 初始渲染
    wrapper.appendChild(toolbar);
    wrapper.appendChild(blocksContainer);
    wrapper.appendChild(footer);
    reRender();

    // 粘贴 Markdown 自动解析（多行→拆块，单行→行内渲染）
    setupPasteHandler(wrapper);

    document.addEventListener('click', (e) => {
      if (!wrapper.contains(e.target)) hideAllMenus();
    });

    const getContent = () => exportToMarkdown();
    const setContent = (val) => {
      blocks = val ? parseMarkdownToBlocks(val) : [createBlock('text', '')];
      reRender();
    };

    return { element: wrapper, getContent, setContent };
  },

  // ===== 底部弹出选择器 =====
  actionSheet(options, title) {
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');

      const overlay = document.createElement('div');
      overlay.className = 'actionsheet-overlay';

      const sheet = document.createElement('div');
      sheet.className = 'actionsheet';

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
          overlay.remove();
          resolve(opt.value !== undefined ? opt.value : opt.label);
        });
        sheet.appendChild(item);
      });

      const cancel = document.createElement('div');
      cancel.className = 'actionsheet__cancel';
      cancel.textContent = '取消';
      cancel.addEventListener('click', () => {
        overlay.remove();
        resolve(null);
      });
      sheet.appendChild(cancel);

      overlay.appendChild(sheet);
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) {
          overlay.remove();
          resolve(null);
        }
      });

      container.appendChild(overlay);
    });
  },

  // ===== 居中弹窗选择器（卡片式） =====
  centeredPicker(options, title, subtitle) {
    return new Promise((resolve) => {
      const container = document.getElementById('modal-container');

      const overlay = document.createElement('div');
      overlay.className = 'cp-overlay';

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
      closeBtn.addEventListener('click', () => { overlay.remove(); resolve(null); });
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
          overlay.remove();
          resolve(opt.value !== undefined ? opt.value : opt.label);
        });

        list.appendChild(item);
      });

      card.appendChild(list);

      // 底部取消按钮
      const cancelRow = document.createElement('div');
      cancelRow.className = 'cp-cancel-row';
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'cp-cancel-btn';
      cancelBtn.textContent = '取消';
      cancelBtn.addEventListener('click', () => { overlay.remove(); resolve(null); });
      cancelRow.appendChild(cancelBtn);
      card.appendChild(cancelRow);

      overlay.appendChild(card);
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) { overlay.remove(); resolve(null); }
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
  pageHeader(title, rightText, onRightClick) {
    const header = document.createElement('div');
    header.className = 'page-header';

    const backBtn = document.createElement('button');
    backBtn.className = 'page-header__back';
    backBtn.innerHTML = '<svg width="10" height="18" viewBox="0 0 10 18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 1L1 9l7 8"/></svg>';
    backBtn.addEventListener('click', () => App.Router.back());
    header.appendChild(backBtn);

    const titleEl = document.createElement('div');
    titleEl.className = 'page-header__title';
    titleEl.textContent = title;
    titleEl.style.flex = '1';
    titleEl.style.textAlign = 'center';
    titleEl.style.fontSize = 'var(--font-lg)';
    header.appendChild(titleEl);

    const rightEl = document.createElement('div');
    rightEl.className = 'page-header__right';
    if (rightText) {
      rightEl.textContent = rightText;
      if (onRightClick) {
        rightEl.style.cursor = 'pointer';
        rightEl.addEventListener('click', onRightClick);
      }
    }
    header.appendChild(rightEl);

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
