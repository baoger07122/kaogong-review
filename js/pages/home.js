// ===== 考公笔试复盘系统 - 复盘首页 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Home = {
  async render(params) {
    const container = document.getElementById('page-home');
    container.innerHTML = '';

    // 获取统计数据
    let stats, reviewQueue, todos;
    try {
      [stats, reviewQueue, todos] = await Promise.all([
        App.DB.getStats(),
        App.DB.getReviewQueue(),
        App.DB.getTodos()
      ]);
    } catch (e) {
      console.error('数据加载失败:', e);
      stats = { subjectStats: {}, totalErrors: 0, unmasteredErrors: 0 };
      reviewQueue = [];
      todos = [];
    }

    // ===== 1. 顶部标题 + 搜索栏 =====
    const header = document.createElement('div');
    header.style.cssText = 'padding:var(--spacing-lg) var(--page-padding);padding-bottom:0;';
    header.innerHTML = `
      <div style="display:flex;align-items:center;gap:var(--spacing-sm);margin-bottom:var(--spacing-lg);">
        <div style="font-size:var(--font-3xl);font-weight:700;color:var(--text-primary);">复盘</div>
        <div class="search-bar" style="flex:1;margin:0;">
          <span class="search-bar__icon">🔍</span>
          <input type="text" placeholder="搜索错题 / 知识点" id="home-search"
            style="background:var(--bg-secondary);height:40px;">
        </div>
      </div>
    `;
    container.appendChild(header);

    // 搜索输入监听
    const searchInput = header.querySelector('#home-search');
    searchInput.addEventListener('input', App.Utils.debounce((e) => {
      if (e.target.value.trim()) {
        App.Router.navigate('errors?search=' + encodeURIComponent(e.target.value.trim()));
      }
    }, 500));

    // ===== 2. 功能图标网格 (5列) =====
    const featureGrid = document.createElement('div');
    featureGrid.className = 'feature-grid';

    const features = [
      { icon: '➕', label: '新建错题', color: '#4A90E2', action: () => App.Router.navigate('error-form') },
      { icon: '⭐', label: '错题收藏', color: '#FF9500', action: () => App.Router.navigate('errors') },
      { icon: '📋', label: '时政常识', color: '#F5A623', action: () => App.Router.navigate('notes?subject=' + encodeURIComponent('常识判断')) },
      { icon: '📝', label: '自我测试', color: '#4A90E2', action: () => App.Router.navigate('exams') },
      { icon: '📊', label: '学习周报', color: '#9B59B6', action: () => App.Router.navigate('workspace') }
    ];

    features.forEach(f => {
      const item = document.createElement('div');
      item.className = 'feature-grid-item';
      item.innerHTML = `
        <div class="feature-grid-item__icon" style="background:${f.color}">${f.icon}</div>
        <div class="feature-grid-item__name">${f.label}</div>
      `;
      item.addEventListener('click', f.action);
      featureGrid.appendChild(item);
    });
    container.appendChild(featureGrid);

    // ===== 3. 统计卡片区 (4列) =====
    const statsRow = document.createElement('div');
    statsRow.className = 'stats-row';
    statsRow.style.marginBottom = 'var(--spacing-xl)';

    const avgAccuracy = stats.totalExams > 0 ? stats.avgAccuracy : 0;
    const unmastered = stats.unmasteredErrors || 0;
    const weekNew = stats.weekNewErrors || 0;
    const totalNotes = stats.totalNotes || 0;

    statsRow.innerHTML = `
      <div class="stat-item">
        <div class="stat-item__value stat-item__value--primary">${avgAccuracy}<span style="font-size:var(--font-sm);">%</span></div>
        <div class="stat-item__label">正确率</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${weekNew}</div>
        <div class="stat-item__label">本周错题</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${unmastered}</div>
        <div class="stat-item__label">待掌握</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${totalNotes}</div>
        <div class="stat-item__label">笔记</div>
      </div>
    `;
    container.appendChild(statsRow);

    // ===== 4. 蓝色横幅 (继续上次练习) =====
    const banner = document.createElement('div');
    banner.className = 'banner-card';
    banner.innerHTML = `
      <div class="banner-card__left">
        <div class="banner-card__icon">▶</div>
        <div>
          <div class="banner-card__title">继续上次练习</div>
          <div class="banner-card__subtitle">错题复习 · 第 ${Math.min(reviewQueue.length, 1)}/${reviewQueue.length} 题</div>
        </div>
      </div>
      <div class="banner-card__right">${reviewQueue.length > 0 ? '5%' : '0%'}</div>
    `;
    if (reviewQueue.length > 0) {
      banner.addEventListener('click', () => {
        App.Router.navigate('error-detail?id=' + reviewQueue[0].id);
      });
    }
    container.appendChild(banner);

    // ===== 5. 最近错题列表 =====
    const recentErrorsTitle = document.createElement('div');
    recentErrorsTitle.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:0 var(--page-padding);margin-bottom:var(--spacing-md);';
    recentErrorsTitle.innerHTML = `
      <div style="font-size:var(--font-lg);font-weight:600;">最近错题</div>
    `;
    container.appendChild(recentErrorsTitle);

    // 获取最近错题（最多3条）
    const recentErrors = reviewQueue.slice(0, 3);
    if (recentErrors.length === 0) {
      const emptyCard = document.createElement('div');
      emptyCard.className = 'card';
      emptyCard.style.cssText = 'text-align:center;padding:var(--spacing-2xl);';
      emptyCard.innerHTML = `
        <div style="font-size:32px;margin-bottom:var(--spacing-md);opacity:0.3;">📋</div>
        <div style="font-size:var(--font-md);color:var(--text-secondary);margin-bottom:4px;">还没有错题</div>
        <div style="font-size:var(--font-sm);color:var(--text-tertiary);">做题后把错题记录到这里</div>
      `;
      container.appendChild(emptyCard);
    } else {
      recentErrors.forEach((error, idx) => {
        const card = document.createElement('div');
        card.className = 'list-card';
        card.addEventListener('click', () => App.Router.navigate('error-detail?id=' + error.id));

        const subjectColor = App.Constants.getSubjectColor(error.subject);
        const pct = error.accuracy || 0;

        card.innerHTML = `
          <div class="list-card__icon" style="background:${subjectColor}20;color:${subjectColor};">
            ${App.Constants.getSubjectIcon(error.subject)}
          </div>
          <div class="list-card__content">
            <div class="list-card__title">${App.Utils.truncate(error.question, 30)}</div>
            <div class="list-card__meta">
              <span>${error.module || ''}</span>
              <span class="highlight">${pct}%</span>
              <span>${error.errorCause || ''}</span>
            </div>
          </div>
          <div class="list-card__action">
            <button class="list-card__action-btn" id="continue-${error.id}">继续</button>
          </div>
        `;

        // 继续按钮点击
        card.querySelector('#continue-' + error.id).addEventListener('click', (e) => {
          e.stopPropagation();
          App.Router.navigate('error-detail?id=' + error.id);
        });

        container.appendChild(card);
      });
    }

    // ===== 6. 全部错题列表区 =====
    const allErrorsTitle = document.createElement('div');
    allErrorsTitle.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:var(--spacing-lg) var(--page-padding) var(--spacing-md);';
    allErrorsTitle.innerHTML = `
      <div style="font-size:var(--font-lg);font-weight:600;">全部错题 · ${stats.totalErrors || 0}</div>
      <div style="display:flex;gap:var(--spacing-md);align-items:center;">
        <span style="font-size:var(--font-sm);color:var(--text-tertiary);cursor:pointer;" id="new-folder-btn">📁 新建文件夹</span>
        <span style="font-size:var(--font-sm);color:var(--text-tertiary);cursor:pointer;" id="sort-btn">⇅ 排序</span>
      </div>
    `;
    container.appendChild(allErrorsTitle);

    // 按科目分组展示错题文件夹
    const subjectFolders = document.createElement('div');
    subjectFolders.style.cssText = 'padding:0 var(--page-padding);';

    App.Constants.SUBJECTS.forEach(subject => {
      const subStats = stats.subjectStats[subject.name] || {};
      const count = subStats.totalErrors || 0;
      if (count === 0) return;

      const folder = document.createElement('div');
      folder.className = 'list-card';
      folder.style.marginBottom = 'var(--spacing-md)';
      folder.addEventListener('click', () => {
        App.Router.navigate('errors?subject=' + encodeURIComponent(subject.name));
      });

      folder.innerHTML = `
        <div class="list-card__icon" style="background:${subject.color}20;color:${subject.color};">
          ${subject.icon}
        </div>
        <div class="list-card__content">
          <div class="list-card__title">${subject.name}错题集</div>
          <div class="list-card__meta">
            <span>${count} 题</span>
            <span style="color:var(--color-warning);font-weight:600;">${subStats.unmastered || 0} 待掌握</span>
          </div>
        </div>
        <div class="list-card__arrow">›</div>
      `;

      subjectFolders.appendChild(folder);
    });

    // 如果没有错题，显示空状态
    if (subjectFolders.children.length === 0) {
      const emptyFolder = document.createElement('div');
      emptyFolder.className = 'card';
      emptyFolder.style.cssText = 'text-align:center;padding:var(--spacing-xl);';
      emptyFolder.innerHTML = `
        <div style="font-size:var(--font-sm);color:var(--text-tertiary);">暂无错题记录</div>
        <div style="font-size:var(--font-xs);color:var(--text-light);margin-top:4px;">点击右上角 + 号添加错题</div>
      `;
      subjectFolders.appendChild(emptyFolder);
    }

    container.appendChild(subjectFolders);

    // ===== 7. 今日待办 =====
    const todoTitle = document.createElement('div');
    todoTitle.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:var(--spacing-xl) var(--page-padding) var(--spacing-md);';
    const completedCount = todos.filter(t => t.completed).length;
    const totalCount = todos.length;
    const pct = totalCount > 0 ? Math.round(completedCount / totalCount * 100) : 0;
    todoTitle.innerHTML = `
      <div style="font-size:var(--font-lg);font-weight:600;">今日待办 · ${totalCount} 项</div>
      <div style="font-size:var(--font-sm);color:var(--text-tertiary);">${pct}% 今日达成</div>
    `;
    container.appendChild(todoTitle);

    const todoCard = document.createElement('div');
    todoCard.className = 'card';
    todoCard.style.marginBottom = 'var(--spacing-xl)';

    if (todos.length === 0) {
      todoCard.innerHTML = `
        <div style="text-align:center;padding:var(--spacing-xl);">
          <div style="font-size:32px;margin-bottom:var(--spacing-md);opacity:0.3;">✅</div>
          <div style="font-size:var(--font-md);color:var(--text-secondary);margin-bottom:4px;">还没有待办事项</div>
          <div style="font-size:var(--font-sm);color:var(--text-tertiary);">点击下方添加按钮开始规划</div>
        </div>
      `;
    } else {
      todos.forEach(todo => {
        const item = document.createElement('div');
        item.className = 'todo-item';
        item.style.borderBottom = '1px solid var(--divider-color)';

        const checkbox = document.createElement('div');
        checkbox.className = 'todo-checkbox';
        if (todo.completed) {
          checkbox.classList.add('checked');
          checkbox.textContent = '✓';
        }
        checkbox.addEventListener('click', async () => {
          todo.completed = !todo.completed;
          await App.DB.updateTodo(todo);
          App.Components.toast(todo.completed ? '已完成' : '已恢复', 'success');
          App.Pages.Home.render({});
        });

        const text = document.createElement('span');
        text.className = 'todo-text';
        if (todo.completed) text.classList.add('completed');
        text.textContent = todo.text;

        const deleteBtn = document.createElement('button');
        deleteBtn.className = 'todo-delete';
        deleteBtn.textContent = '✕';
        deleteBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const confirmed = await App.Components.confirm('删除待办', '确定删除这项待办？', '删除', '取消', true);
          if (confirmed) {
            await App.DB.remove('todos', todo.id);
            App.Components.toast('已删除', 'success');
            App.Pages.Home.render({});
          }
        });

        item.appendChild(checkbox);
        item.appendChild(text);
        item.appendChild(deleteBtn);
        todoCard.appendChild(item);
      });
    }
    container.appendChild(todoCard);

    // 添加待办输入
    const addTodoRow = document.createElement('div');
    addTodoRow.style.cssText = 'display:flex;gap:var(--spacing-sm);padding:0 var(--page-padding);margin-bottom:var(--spacing-xl);';
    const input = document.createElement('input');
    input.className = 'form-input';
    input.placeholder = '添加待办事项...';
    input.style.flex = '1';
    const addBtn = document.createElement('button');
    addBtn.className = 'btn btn--primary btn--sm';
    addBtn.textContent = '添加';
    addBtn.addEventListener('click', async () => {
      const text = input.value.trim();
      if (!text) { App.Components.toast('请输入待办内容', 'error'); return; }
      await App.DB.addTodo({ text, completed: false, createdAt: new Date().toISOString() });
      input.value = '';
      App.Components.toast('已添加', 'success');
      App.Pages.Home.render({});
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') addBtn.click();
    });
    addTodoRow.appendChild(input);
    addTodoRow.appendChild(addBtn);
    container.appendChild(addTodoRow);

    // 底部留白
    const spacer = document.createElement('div');
    spacer.style.height = '80px';
    container.appendChild(spacer);
  }
};
