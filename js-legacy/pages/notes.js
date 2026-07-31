// ===== 考公笔试复盘系统 - 笔记页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Notes = {
  state: {
    subject: null,
    module: null,
    knowledgePoint: null,
    search: '',
    allNotes: []
  },

  async render(params) {
    const container = document.getElementById('page-notes');
    container.innerHTML = '';

    // 左侧边栏（科目）+ 主内容区
    const layout = document.createElement('div');
    layout.className = 'with-sidebar';

    const sidebar = document.createElement('div');
    sidebar.className = 'sidebar';
    sidebar.id = 'note-sidebar';
    layout.appendChild(sidebar);

    const main = document.createElement('div');
    main.className = 'page-main';

    // 页面标题
    const header = document.createElement('div');
    header.className = 'page-header';
    header.innerHTML = `
      <div class="page-header__title">笔记</div>
      <div class="page-header__right" id="note-count">共 0 篇</div>
    `;
    main.appendChild(header);

    // 搜索栏
    const searchBar = document.createElement('div');
    searchBar.className = 'search-bar';
    searchBar.innerHTML = `
      <span class="search-bar__icon">🔍</span>
      <input type="text" placeholder="搜索笔记 / 知识点" id="note-search">
    `;
    main.appendChild(searchBar);

    searchBar.querySelector('input').addEventListener('input', App.Utils.debounce((e) => {
      this.state.search = e.target.value;
      this.refreshTree();
    }, 300));

    // 笔记树区
    const treeArea = document.createElement('div');
    treeArea.id = 'note-tree-area';
    main.appendChild(treeArea);

    layout.appendChild(main);
    container.appendChild(layout);

    // 加载数据
    await this.loadData();
    await this.renderSubjectGrid(sidebar);
    this.renderTree(treeArea);
  },

  async loadData() {
    this.state.allNotes = await App.DB.getNotes();
  },

  // 合并「本模块库 + 数据中已用值」得到可筛选的考点列表
  getDistinctKnowledgePoints(module) {
    const used = new Set();
    this.state.allNotes.forEach(n => {
      if (n.module === module && n.knowledgePoint) used.add(n.knowledgePoint);
    });
    const lib = App.Tags.getKnowledgePoints(module);
    return Array.from(new Set([...lib, ...used]));
  },

  async renderSubjectGrid(container) {
    const noteCounts = {};
    App.Constants.SUBJECTS.forEach(s => {
      noteCounts[s.name] = this.state.allNotes.filter(n => n.subject === s.name).length;
    });

    container.innerHTML = '';

    // 「全部」项
    const allItem = document.createElement('div');
    allItem.className = 'sidebar__item' + (this.state.subject === null ? ' active' : '');
    allItem.innerHTML = `
      <span class="sidebar__item-icon">📚</span>
      <span class="sidebar__item-name">全部</span>
    `;
    allItem.addEventListener('click', () => {
      this.state.subject = null;
      this.state.module = null;
      this.state.knowledgePoint = null;
      this.refreshAll();
    });
    container.appendChild(allItem);

    // 各科目
    App.Constants.SUBJECTS.forEach(s => {
      const item = document.createElement('div');
      item.className = 'sidebar__item' + (this.state.subject === s.name ? ' active' : '');
      const count = noteCounts[s.name];
      item.innerHTML = `
        <span class="sidebar__item-icon">${s.icon}</span>
        <span class="sidebar__item-name">${s.name}</span>
        ${count > 0 ? `<span class="sidebar__item-count">${count}</span>` : ''}
      `;
      item.addEventListener('click', () => {
        if (this.state.subject === s.name) {
          this.state.subject = null;
        } else {
          this.state.subject = s.name;
        }
        this.state.module = null;
        this.state.knowledgePoint = null;
        this.refreshAll();
      });
      container.appendChild(item);
    });
  },

  renderTree(container) {
    container.innerHTML = '';

    const subject = this.state.subject;
    if (!subject) {
      // 未选科目时显示引导
      container.appendChild(App.Components.emptyState(
        '📝',
        '选择科目查看笔记',
        '点击左侧科目标签开始浏览笔记'
      ));
      return;
    }

    // 过滤该科目笔记
    let notes = this.state.allNotes.filter(n => n.subject === subject);
    if (this.state.module) notes = notes.filter(n => n.module === this.state.module);
    if (this.state.knowledgePoint) notes = notes.filter(n => n.knowledgePoint === this.state.knowledgePoint);
    if (this.state.search) {
      const kw = this.state.search.toLowerCase();
      notes = notes.filter(n =>
        n.title.toLowerCase().includes(kw) ||
        (n.content && n.content.toLowerCase().includes(kw))
      );
    }

    // 更新计数
    const countEl = document.getElementById('note-count');
    if (countEl) countEl.textContent = '共 ' + notes.length + ' 篇';

    // 科目标题 + 展开/收起全部
    const subjectHeader = document.createElement('div');
    subjectHeader.style.cssText = 'display:flex;justify-content:space-between;align-items:center;padding:0 var(--page-padding);margin-bottom:var(--spacing-sm);';
    subjectHeader.innerHTML = `
      <div style="font-size:var(--font-lg);font-weight:600;display:flex;align-items:center;gap:8px;">
        <span>${App.Constants.getSubjectIcon(subject)}</span>
        <span>${subject}</span>
      </div>
    `;
    container.appendChild(subjectHeader);

    // 模块筛选标签（首项「全部」用于取消筛选，选中态如导航栏高亮）
    const modules = App.Constants.getModules(subject);
    const moduleItems = [{ name: '全部' }].concat(modules.map(m => ({ name: m })));
    const moduleBar = App.Components.filterTags(
      moduleItems,
      this.state.module || '全部',
      (mod) => {
        this.state.module = (mod === '全部') ? null : mod;
        this.state.knowledgePoint = null;
        this.refreshAll();
      },
      'primary'
    );
    container.appendChild(moduleBar);

    // 考点筛选
    if (this.state.module) {
      const kps = this.getDistinctKnowledgePoints(this.state.module);
      const kpItems = [{ name: '全部' }].concat(kps.map(k => ({ name: k })));
      const kpBar = App.Components.filterTags(
        kpItems,
        this.state.knowledgePoint || '全部',
        (kp) => {
          this.state.knowledgePoint = (kp === '全部') ? null : kp;
          this.refreshAll();
        },
        'primary'
      );
      container.appendChild(kpBar);
    }

    // 词语库入口：言语理解（逻辑填空）专属
    if (subject === '言语理解') {
      const wordDbEntry = document.createElement('div');
      wordDbEntry.className = 'notes-worddb-entry';
      wordDbEntry.innerHTML = `
        <span class="notes-worddb-entry__icon">📚</span>
        <span class="notes-worddb-entry__text">
          <span class="notes-worddb-entry__title">词语库</span>
          <span class="notes-worddb-entry__desc">成语 / 实词 释义与辨析 · 逻辑填空</span>
        </span>
        <span class="notes-worddb-entry__arrow">›</span>
      `;
      wordDbEntry.addEventListener('click', () => {
        App.Router.navigate('worddb?subject=' + encodeURIComponent(subject) + '&module=' + encodeURIComponent('逻辑填空'));
      });
      container.appendChild(wordDbEntry);
    }

    // 笔记树
    const treeContainer = document.createElement('div');
    treeContainer.className = 'note-tree';

    if (notes.length === 0) {
      treeContainer.appendChild(App.Components.emptyState(
        '📝',
        '暂无笔记',
        '点击右下角 + 号开始记录',
        '新建笔记',
        () => { App.Draft.clearForm('note'); App.Router.navigate('note-form?subject=' + encodeURIComponent(subject)); }
      ));
    } else {
      // 按模块-考点组织
      const treeData = {};
      notes.forEach(note => {
        const mod = note.module || '未分类';
        const kp = note.knowledgePoint || '未分类';
        if (!treeData[mod]) treeData[mod] = {};
        if (!treeData[mod][kp]) treeData[mod][kp] = [];
        treeData[mod][kp].push(note);
      });

      Object.entries(treeData).forEach(([modName, kps]) => {
        const kpNodes = [];
        Object.entries(kps).forEach(([kpName, kpNotes]) => {
          const noteItems = kpNotes.map(note =>
            App.Components.noteItem(note, (n) => App.Router.navigate('note-detail?id=' + n.id))
          );

          const kpNode = App.Components.noteTreeNode(
            kpName,
            '📌',
            kpNotes.length,
            true,
            noteItems
          );
          kpNodes.push(kpNode);
        });

        const modNode = App.Components.noteTreeNode(
          modName,
          '📁',
          Object.values(kps).reduce((sum, arr) => sum + arr.length, 0),
          true,
          kpNodes
        );
        treeContainer.appendChild(modNode);
      });
    }

    container.appendChild(treeContainer);
  },

  refreshAll() {
    const sidebar = document.getElementById('note-sidebar');
    const treeArea = document.getElementById('note-tree-area');
    if (sidebar) this.renderSubjectGrid(sidebar);
    if (treeArea) this.renderTree(treeArea);
  },

  // ===== 笔记详情页 =====
  async renderDetail(params) {
    const container = document.getElementById('page-note-detail');
    container.innerHTML = '';

    const noteId = params.id;
    if (!noteId) { App.Router.navigate('notes'); return; }

    const note = await App.DB.get('notes', noteId);
    if (!note) {
      App.Components.toast('笔记不存在', 'error');
      App.Router.navigate('notes');
      return;
    }

    // 返回栏 + 右上角三点菜单
    const header = App.Components.pageHeader('笔记详情', '⋮', () => this._showDetailMenu(note));
    const moreBtn = header.querySelector('.page-header__right');
    if (moreBtn) moreBtn.classList.add('note-detail-more');
    container.appendChild(header);

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) var(--page-padding);padding-bottom:var(--spacing-3xl);';

    // 面包屑
    const breadcrumb = document.createElement('div');
    breadcrumb.className = 'breadcrumb';
    breadcrumb.style.marginBottom = 'var(--spacing-md)';
    breadcrumb.innerHTML = `
      <span class="breadcrumb__item">${note.subject}</span>
      <span class="breadcrumb__sep">›</span>
      <span class="breadcrumb__item">${note.module}</span>
      <span class="breadcrumb__sep">›</span>
      <span class="breadcrumb__item">${note.knowledgePoint}</span>
    `;
    content.appendChild(breadcrumb);

    // 标题（点击进入编辑）
    const titleEl = document.createElement('div');
    titleEl.style.cssText = 'font-size:var(--font-xl);font-weight:700;margin-bottom:var(--spacing-md);cursor:pointer;';
    titleEl.textContent = note.title;
    titleEl.addEventListener('click', () => App.Router.navigate('note-form?id=' + note.id));
    content.appendChild(titleEl);

    // 正文（点击进入编辑）
    const bodyEl = document.createElement('div');
    bodyEl.className = 'card';
    bodyEl.setAttribute('data-tap-edit', '');
    bodyEl.style.cssText = 'margin:0 0 var(--spacing-md) 0;line-height:1.8;min-height:80px;';
    bodyEl.innerHTML = note.content
      ? App.Utils.simpleMarkdown(note.content)
      : '<span style="color:var(--text-tertiary);">暂无内容</span>';
    bodyEl.addEventListener('click', () => App.Router.navigate('note-form?id=' + note.id));
    content.appendChild(bodyEl);

    // 编辑时间
    const metaEl = document.createElement('div');
    metaEl.style.cssText = 'font-size:var(--font-xs);color:var(--text-tertiary);margin-bottom:var(--spacing-md);';
    metaEl.textContent = '最后编辑于 ' + App.Utils.formatDateTime(note.updatedAt);
    content.appendChild(metaEl);

    // 关联错题
    if (note.linkedErrors && note.linkedErrors.length > 0) {
      const linkedSection = document.createElement('div');
      linkedSection.className = 'linked-section';
      linkedSection.innerHTML = `<div class="linked-section__title">关联错题（${note.linkedErrors.length}）</div>`;
      for (const errId of note.linkedErrors) {
        try {
          const err = await App.DB.get('errors', errId);
          if (err) {
            const errItem = document.createElement('div');
            errItem.style.cssText = 'padding:8px;margin-bottom:4px;background:var(--bg-tertiary);border-radius:var(--radius-sm);font-size:var(--font-sm);cursor:pointer;';
            errItem.textContent = App.Utils.truncate(err.question, 50);
            errItem.addEventListener('click', () => App.Router.navigate('error-detail?id=' + err.id));
            linkedSection.appendChild(errItem);
          }
        } catch (e) {}
      }
      content.appendChild(linkedSection);
    }

    container.appendChild(content);
  },

  // ===== 详情页右上角三点菜单 =====
  async _showDetailMenu(note) {
    const action = await App.Components.actionSheet([
      { label: '📋 复制副本', value: 'duplicate' },
      { label: '📂 移动位置', value: 'move' },
      { label: '🗑️ 删除', value: 'delete' }
    ], note.title);
    if (!action) return;

    switch (action) {
      case 'delete': {
        const confirmed = await App.Components.confirm(
          '删除笔记',
          '确定删除「' + note.title + '」？此操作不可撤销。',
          '删除', '取消', true
        );
        if (confirmed) {
          await App.DB.remove('notes', note.id);
          App.Components.toast('已删除', 'success');
          App.Router.navigate('notes');
        }
        break;
      }
      case 'move': {
        // 级联选择：科目 → 模块 → 考点
        const sOpt = App.Constants.SUBJECTS.map(s => ({
          icon: '<span style="font-size:22px">' + s.icon + '</span>',
          label: s.name,
          desc: '选择「' + s.name + '」模块',
          value: s.name
        }));
        const newSubject = await App.Components.centeredPicker(sOpt, '移动到', '选择目标科目');
        if (!newSubject) return;

        const mods = App.Constants.getModules(newSubject);
        const mOpt = mods.map(m => ({ icon: '📂', label: m, desc: newSubject + ' — ' + m, value: m }));
        const newModule = await App.Components.centeredPicker(mOpt, '选择模块', '选择「' + newSubject + '」下的模块');
        if (!newModule) return;

        const kps = App.Tags.getKnowledgePointSuggestions(newModule);
        const kOpt = kps.map(k => ({ icon: '🏷️', label: k, desc: newModule + ' — ' + k, value: k }));
        kOpt.push({ icon: '✏️', label: '+ 自定义考点', desc: '手动输入新考点名称', value: '__custom__' });
        let newKp = await App.Components.centeredPicker(kOpt, '选择考点', '选择或自定义「' + newModule + '」的考点');
        if (newKp === '__custom__') {
          const name = prompt('输入自定义考点名称：');
          if (name && name.trim()) { newKp = name.trim(); App.Tags.addKnowledgePoint(newModule, name.trim()); }
        }
        if (!newKp) return;

        // 更新笔记分类
        note.subject = newSubject;
        note.module = newModule;
        note.knowledgePoint = newKp;
        note.updatedAt = Date.now();
        await App.DB.updateNote(note);
        App.Components.toast('已移动到 ' + newSubject + ' › ' + newModule + ' › ' + newKp, 'success');
        // 刷新当前页面以显示新分类
        this.renderDetail({ id: note.id });
        break;
      }
      case 'duplicate': {
        const copy = JSON.parse(JSON.stringify(note));
        delete copy.id;
        copy.title = (copy.title || '未命名笔记') + ' 副本';
        copy.createdAt = Date.now();
        copy.updatedAt = Date.now();
        const newId = await App.DB.addNote(copy);
        App.Components.toast('已创建副本', 'success');
        // 跳转到新副本的详情页
        App.Router.navigate('note-detail?id=' + newId);
        break;
      }
    }
  },

  // ===== 新建/编辑笔记表单 =====
  renderForm(params) {
    const container = document.getElementById('page-note-form');
    container.innerHTML = '';

    let isEdit = !!params.id;

    let formData = {
      subject: params.subject || '',
      module: '',
      knowledgePoint: '',
      title: '',
      content: '',
      linkedErrors: []
    };

    const loadAndRender = async () => {
      if (isEdit) {
        const note = await App.DB.get('notes', params.id);
        if (note) {
          formData = {
            subject: note.subject || '',
            module: note.module || '',
            knowledgePoint: note.knowledgePoint || '',
            title: note.title || '',
            content: note.content || '',
            linkedErrors: note.linkedErrors || [],
            id: note.id
          };
        }
        formData._formId = params.id;
      } else {
        // 新建/续编：仅当 sessionStorage 记录着「同一篇正在录入」的 id 时才续编；否则一律空白。
        const fid = App.Draft.getFormId('note');
        if (fid) {
          if (App.Draft.formIdIsTemp(fid)) {
            // 尚未建成 DB 记录：从 localStorage 草稿续编
            const d = App.Draft.loadForm('note', fid);
            if (d) Object.assign(formData, d);
            formData._formId = fid;
          } else {
            // 已是真实记录 id：从 DB 续编（权威，不会重复建记录）
            const note = await App.DB.get('notes', fid);
            if (note) {
              isEdit = true;
              formData = {
                subject: note.subject || '', module: note.module || '',
                knowledgePoint: note.knowledgePoint || '', title: note.title || '',
                content: note.content || '', linkedErrors: note.linkedErrors || [],
                id: note.id
              };
              formData._formId = fid;
            }
          }
        }
        if (!formData._formId) {
          formData._formId = App.Draft.newTempId();
          App.Draft.setFormId('note', formData._formId);
        }
        // URL 参数 subject 优先级高于草稿（用户从某科目点新建）
        if (params.subject) formData.subject = params.subject;
      }
      buildForm();
    };

    const buildForm = () => {
      // 重建前先把编辑器内容同步回 formData，避免重渲染丢失草稿
      if (formData._getContent) {
        try { formData.content = formData._getContent(); } catch (e) {}
      }
      container.innerHTML = '';

      container.appendChild(App.Components.pageHeader(
        isEdit ? '编辑笔记' : '新建笔记',
        '保存',
        async () => {
          if (!formData.subject || !formData.title.trim()) {
            App.Components.toast('请完成必填项', 'error');
            return;
          }
          await submitForm();
        }
      ));

      const form = document.createElement('div');
      form.className = 'form-page';

      // ===== 标题（普通输入框，无灰色占位） =====
      const titleInput = document.createElement('input');
      titleInput.type = 'text';
      titleInput.className = 'note-title-input';
      titleInput.placeholder = '请输入笔记标题…';
      titleInput.value = formData.title || '';
      titleInput.addEventListener('input', () => { formData.title = titleInput.value; });
      form.appendChild(titleInput);

      // ===== 单一分类选择框（科目 › 模块 › 考点 级联） =====
      const catSelector = document.createElement('button');
      catSelector.type = 'button';
      catSelector.className = 'note-cat-selector';
      const updateCatLabel = () => {
        const parts = [formData.subject, formData.module, formData.knowledgePoint].filter(Boolean);
        catSelector.innerHTML = parts.length
          ? `<span class="note-cat-icon">🏷️</span><span class="note-cat-text">${parts.join(' › ')}</span><span class="note-cat-clear" title="清除分类">✕</span>`
          : `<span class="note-cat-icon">🏷️</span><span class="note-cat-text note-cat-placeholder">+ 选择科目 / 模块 / 考点</span>`;
      };
      catSelector.addEventListener('click', async (e) => {
        if (e.target.classList.contains('note-cat-clear')) {
          formData.subject = ''; formData.module = ''; formData.knowledgePoint = '';
          updateCatLabel();
          return;
        }
        // 科目选择（居中弹窗）
        const sOpt = App.Constants.SUBJECTS.map(s => ({
          icon: '<span style="font-size:22px">' + s.icon + '</span>',
          label: s.name,
          desc: '选择「' + s.name + '」模块',
          value: s.name
        }));
        const s = await App.Components.centeredPicker(sOpt, '选择科目', '请先选择考试科目，再选择具体模块和考点');
        if (!s) return;
        formData.subject = s; formData.module = ''; formData.knowledgePoint = '';

        // 模块选择
        const mods = App.Constants.getModules(s);
        const mOpt = mods.map(m => ({
          icon: '📂',
          label: m,
          desc: s.name + ' — ' + m,
          value: m
        }));
        const m = await App.Components.centeredPicker(mOpt, '选择模块', '选择「' + s + '」下的知识模块');
        if (!m) { updateCatLabel(); return; }
        formData.module = m; formData.knowledgePoint = '';

        // 考点选择
        const kps = App.Tags.getKnowledgePointSuggestions(m);
        const kOpt = kps.map(k => ({
          icon: '🏷️',
          label: k,
          desc: m + ' — ' + k,
          value: k
        }));
        kOpt.push({ icon: '✏️', label: '+ 自定义考点', desc: '手动输入新考点名称', value: '__custom__' });
        const k = await App.Components.centeredPicker(kOpt, '选择考点', '选择或自定义「' + m + '」的考点');
        if (k === '__custom__') {
          const name = prompt('输入自定义考点名称：');
          if (name && name.trim()) { formData.knowledgePoint = name.trim(); App.Tags.addKnowledgePoint(m, name.trim()); }
        } else if (k) { formData.knowledgePoint = k; }
        updateCatLabel();
      });
      updateCatLabel();
      form.appendChild(catSelector);

      // ===== 正文块编辑器（带 onChange 自动保存到 DB）=====
      const editor = App.Components.notionEditor(formData.content, '输入笔记内容，输入 / 唤起命令...', function (content) {
        formData.content = content;
        debouncedSaveToDB();
      });
      form.appendChild(editor.element);
      formData._getContent = editor.getContent;

      // 关联错题
      const linkGroup = document.createElement('div');
      linkGroup.className = 'form-group';
      const linkLabel = document.createElement('label');
      linkLabel.className = 'form-label';
      linkLabel.textContent = '关联错题（可选）';
      linkGroup.appendChild(linkLabel);

      const linkBtn = document.createElement('button');
      linkBtn.className = 'btn btn--outline btn--sm';
      linkBtn.textContent = '选择错题';
      linkBtn.addEventListener('click', async () => {
        const errors = await App.DB.getErrors({ subject: formData.subject });
        if (errors.length === 0) {
          App.Components.toast('该科目暂无错题', 'error');
          return;
        }

        const options = errors.map(e => ({
          label: App.Utils.truncate(e.question, 30),
          value: e.id
        }));
        const selected = await App.Components.actionSheet(options, '选择关联错题');
        if (selected && !formData.linkedErrors.includes(selected)) {
          formData.linkedErrors.push(selected);
          buildForm();
        }
      });
      linkGroup.appendChild(linkBtn);

      // 显示已关联的错题
      if (formData.linkedErrors.length > 0) {
        const linkedList = document.createElement('div');
        linkedList.style.cssText = 'margin-top:8px;';
        for (const errId of formData.linkedErrors) {
          const row = document.createElement('div');
          row.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:4px 0;font-size:var(--font-sm);';
          row.innerHTML = `<span style="color:var(--text-secondary);">关联错题 ${errId.slice(-6)}</span>`;
          const removeBtn = document.createElement('button');
          removeBtn.className = 'btn--text';
          removeBtn.textContent = '移除';
          removeBtn.addEventListener('click', () => {
            formData.linkedErrors = formData.linkedErrors.filter(id => id !== errId);
            buildForm();
          });
          row.appendChild(removeBtn);
          linkedList.appendChild(row);
        }
        linkGroup.appendChild(linkedList);
      }

      form.appendChild(linkGroup);

      container.appendChild(form);

      // 草稿自动暂存（localStorage 兜底，按表单 id 隔离，避免旧草稿串入新笔记）
      App.Draft.autoSaveForm('note', formData._formId, container, function () {
        if (formData._getContent) { try { formData.content = formData._getContent(); } catch (e) {} }
        return JSON.parse(JSON.stringify(formData));
      });
    };

    // 防抖自动保存到 DB（2 秒无操作后执行）
    let _saveTimer = null;
    let _saving = false;
    function debouncedSaveToDB() {
      clearTimeout(_saveTimer);
      _saveTimer = setTimeout(async () => {
        if (_saving) return;
        if (!formData.subject || !formData.title.trim()) return;
        _saving = true;
        try { await submitFormInternal(); } catch (e) {}
        _saving = false;
      }, 2000);
    }

    // 核心保存逻辑
    const submitFormInternal = async () => {
      if (formData._getContent) formData.content = formData._getContent();
      if (!formData.subject || !formData.title.trim()) return;

      if (isEdit && formData.id) {
        const existing = await App.DB.get('notes', formData.id);
        await App.DB.updateNote({
          id: formData.id, subject: formData.subject, module: formData.module,
          knowledgePoint: formData.knowledgePoint, title: formData.title,
          content: formData.content, linkedErrors: formData.linkedErrors,
          linkedReviews: existing ? existing.linkedReviews || [] : [],
          updatedAt: new Date().toISOString()
        });
      } else {
        if (!formData.id) {
          formData.id = await App.DB.addNote({
            subject: formData.subject, module: formData.module,
            knowledgePoint: formData.knowledgePoint,
            title: formData.title || '未命名笔记', content: formData.content,
            linkedErrors: formData.linkedErrors, linkedReviews: [],
            updatedAt: new Date().toISOString()
          });
          isEdit = true;
        } else {
          await App.DB.updateNote({
            id: formData.id, subject: formData.subject, module: formData.module,
            knowledgePoint: formData.knowledgePoint, title: formData.title,
            content: formData.content, linkedErrors: formData.linkedErrors,
            linkedReviews: [], updatedAt: new Date().toISOString()
          });
        }
      }
    };

    // 手动/离开时强制保存
    const submitForm = async () => {
      clearTimeout(_saveTimer);
      if (formData._getContent) formData.content = formData._getContent();
      if (!formData.subject) { App.Components.toast('请选择科目', 'error'); return; }
      if (!formData.title.trim()) { App.Components.toast('请输入标题', 'error'); return; }
      try {
        await submitFormInternal();
        App.Components.toast('已保存 ✓', 'success');
        App.Draft.clearForm('note');
        App.Router.navigate('notes');
      } catch (e) { App.Components.toast('保存失败', 'error'); }
    };

    loadAndRender();
  }
};
