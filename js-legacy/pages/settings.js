// ===== 考公笔试复盘系统 - 设置页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Settings = {
  // 折叠与管理状态持久化在实例上：每次重渲染(fold)都能保留
  _state: { expanded: {}, managed: false },
  render(params) {
    const container = document.getElementById('page-settings');
    container.innerHTML = '';

    // 页面标题
    const header = document.createElement('div');
    header.className = 'page-header';
    header.innerHTML = `<div class="page-header__title">设置</div>`;
    container.appendChild(header);

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) 0;';

    // ===== 云同步 =====
    const cloudGroup = document.createElement('div');
    cloudGroup.className = 'settings-group';
    const loggedIn = App.Cloud && App.Cloud.isLoggedIn();
    if (loggedIn) {
      cloudGroup.innerHTML = `
        <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">云同步</div>
        <div class="cloud-card">
          <div class="cloud-status">☁️ 已开启 · ${App.Cloud.getEmail()}</div>
          <div class="cloud-sub">上次同步：${App.Cloud.getLastSyncText()}</div>
          <div class="cloud-actions">
            <button class="btn btn--primary" id="cloud-sync" style="flex:1">立即同步</button>
            <button class="btn btn--outline" id="cloud-logout" style="flex:1">退出登录</button>
          </div>
          <div class="cloud-hint">保存即自动上传云端；换设备后点「立即同步」即可把云端数据合并到本机（按时间保留最新，不会覆盖未上传的内容）。</div>
        </div>
      `;
    } else {
      cloudGroup.innerHTML = `
        <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">云同步</div>
        <div class="cloud-card">
          <input class="form-input" id="cloud-email" type="email" inputmode="email" autocomplete="email" placeholder="邮箱（用作登录账号）">
          <input class="form-input" id="cloud-password" type="password" autocomplete="current-password" placeholder="密码（至少 6 位）">
          <div class="cloud-actions">
            <button class="btn btn--primary" id="cloud-login" style="flex:1">登录</button>
            <button class="btn btn--outline" id="cloud-register" style="flex:1">注册</button>
          </div>
          <div class="cloud-hint">登录后保存即自动上传云端，可跨设备访问；换设备时点「立即同步」即可把云端数据合并到本机，不会因清缓存或换网址而丢失。</div>
        </div>
      `;
    }
    content.appendChild(cloudGroup);

    const doCloudAuth = async (mode) => {
      const emailEl = cloudGroup.querySelector('#cloud-email');
      const pwdEl = cloudGroup.querySelector('#cloud-password');
      const email = (emailEl && emailEl.value || '').trim();
      const pwd = (pwdEl && pwdEl.value || '').trim();
      if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        App.Components.toast('请输入有效邮箱', 'error'); return;
      }
      if (!pwd || pwd.length < 6) {
        App.Components.toast('密码至少 6 位', 'error'); return;
      }
      try {
        if (mode === 'login') await App.Cloud.login(email, pwd);
        else await App.Cloud.register(email, pwd);
        App.Pages.Settings.render({});
      } catch (e) {
        App.Components.toast(e.message || '操作失败', 'error');
      }
    };

    if (loggedIn) {
      const syncBtn = cloudGroup.querySelector('#cloud-sync');
      const logoutBtn = cloudGroup.querySelector('#cloud-logout');
      if (syncBtn) syncBtn.addEventListener('click', () => App.Cloud.syncNow());
      if (logoutBtn) logoutBtn.addEventListener('click', () => App.Cloud.logout());
    } else {
      const loginBtn = cloudGroup.querySelector('#cloud-login');
      const regBtn = cloudGroup.querySelector('#cloud-register');
      if (loginBtn) loginBtn.addEventListener('click', () => doCloudAuth('login'));
      if (regBtn) regBtn.addEventListener('click', () => doCloudAuth('register'));
    }

    // ===== 外观设置 =====
    const appearanceGroup = document.createElement('div');
    appearanceGroup.className = 'settings-group';
    appearanceGroup.innerHTML = `
      <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">外观</div>
    `;

    const themeModes = [
      { label: '跟随系统', value: 'auto' },
      { label: '浅色模式', value: 'light' },
      { label: '深色模式', value: 'dark' }
    ];

    const currentTheme = App.Utils.Theme.get();
    themeModes.forEach(mode => {
      const item = document.createElement('div');
      item.className = 'settings-item';
      item.innerHTML = `
        <span class="settings-item__label">${mode.label}</span>
        <span class="settings-item__value">${currentTheme === mode.value ? '✓' : ''}</span>
      `;
      item.addEventListener('click', () => {
        App.Utils.Theme.set(mode.value);
        App.Components.toast('主题已切换', 'success');
        App.Pages.Settings.render({});
      });
      appearanceGroup.appendChild(item);
    });

    content.appendChild(appearanceGroup);

    // ===== 数据管理 =====
    const dataGroup = document.createElement('div');
    dataGroup.className = 'settings-group';
    dataGroup.innerHTML = `
      <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">数据管理</div>
    `;

    // 导出备份
    const exportItem = document.createElement('div');
    exportItem.className = 'settings-item';
    exportItem.innerHTML = `
      <span class="settings-item__label">导出备份</span>
      <span class="settings-item__value">JSON</span>
    `;
    exportItem.addEventListener('click', async () => {
      try {
        await App.DB.exportAll();
        App.Components.toast('备份文件已下载 ✓', 'success');
      } catch (e) {
        App.Components.toast('导出失败，请重试', 'error');
      }
    });
    dataGroup.appendChild(exportItem);

    // 导入恢复
    const importItem = document.createElement('div');
    importItem.className = 'settings-item';
    importItem.innerHTML = `
      <span class="settings-item__label">导入恢复</span>
      <span class="settings-item__value">从文件恢复 ›</span>
    `;
    importItem.addEventListener('click', () => {
      const fileInput = document.getElementById('import-file-input');
      fileInput.value = '';
      fileInput.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const confirmed = await App.Components.confirm(
          '导入数据',
          '导入将覆盖现有全部数据（错题、笔记、套卷、待办）。确定继续？',
          '确认导入', '取消', true
        );
        if (!confirmed) return;

        try {
          const text = await file.text();
          const data = JSON.parse(text);
          await App.DB.importAll(data);
          App.Components.toast('数据已恢复 ✓ 请刷新页面查看', 'success');
          setTimeout(() => location.reload(), 1500);
        } catch (e) {
          App.Components.toast('导入失败，请检查文件格式', 'error');
          console.error(e);
        }
      };
      fileInput.click();
    });
    dataGroup.appendChild(importItem);

    // 清空数据
    const clearItem = document.createElement('div');
    clearItem.className = 'settings-item';
    clearItem.innerHTML = `
      <span class="settings-item__label" style="color:var(--color-danger);">清空全部数据</span>
      <span class="settings-item__value"></span>
    `;
    clearItem.addEventListener('click', async () => {
      const confirmed = await App.Components.confirm(
        '清空全部数据',
        '此操作将永久删除所有错题、笔记、套卷和待办数据，不可恢复！\n\n建议先导出备份。',
        '确认清空', '取消', true
      );
      if (confirmed) {
        const stores = ['errors', 'notes', 'exams', 'todos', 'subject_reviews'];
        for (const store of stores) {
          await App.DB.clearStore(store);
        }
        App.Components.toast('全部数据已清空', 'success');
        setTimeout(() => location.reload(), 1000);
      }
    });
    dataGroup.appendChild(clearItem);

    content.appendChild(dataGroup);

    // ===== 考点管理（多级折叠列表 + 管理模式） =====
    // 折叠/管理状态保存在实例 _state 上，避免每次重渲染丢失
    const state = this._state;
    const expanded = state.expanded;
    let managed = state.managed;

    const tagSection = document.createElement('div');
    tagSection.style.cssText = 'padding:12px var(--spacing-md);';
    tagSection.innerHTML = `
      <div style="padding:0 0 4px;font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">考点管理</div>
      <div style="padding:0 0 10px;font-size:var(--font-xs);color:var(--text-tertiary);line-height:1.5;">考点按「科目 → 模块」分级，错因为全局。默认仅显示标题，点击展开查看标签；开启管理模式后可删除或修改标签。</div>
    `;

    // 管理模式开关
    const mgmtBar = document.createElement('div');
    mgmtBar.className = 'kp-mgmt-bar';
    mgmtBar.innerHTML = `
      <span class="kp-mgmt-bar__label">管理模式（删除 / 修改标签）</span>
      <label class="switch">
        <input type="checkbox" id="kp-mgmt-switch">
        <span class="switch__slider"></span>
      </label>
    `;
    tagSection.appendChild(mgmtBar);

    const tree = document.createElement('div');
    tree.className = 'kp-tree';
    tagSection.appendChild(tree);

    // 内联修改标签
    const startEdit = (chip, module, oldName, kind) => {
      chip.classList.add('kp-chip--editing');
      chip.innerHTML = '';
      const input = document.createElement('input');
      input.className = 'kp-edit-input';
      input.value = oldName;
      const saveBtn = document.createElement('button');
      saveBtn.className = 'kp-chip__btn kp-save';
      saveBtn.textContent = '保存';
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'kp-chip__btn kp-cancel';
      cancelBtn.textContent = '取消';
      saveBtn.addEventListener('click', async () => {
        const v = input.value.trim();
        if (!v) return;
        if (kind === 'kp') await App.Tags.renameKnowledgePoint(module, oldName, v);
        else await App.Tags.renameErrorCause(oldName, v);
        App.Pages.Settings.render({});
      });
      cancelBtn.addEventListener('click', () => App.Pages.Settings.render({}));
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') saveBtn.click();
        else if (e.key === 'Escape') cancelBtn.click();
      });
      chip.appendChild(input);
      chip.appendChild(saveBtn);
      chip.appendChild(cancelBtn);
      input.focus();
      input.select();
    };

    // 单个考点 chip
    const buildKpChip = (module, name) => {
      const chip = document.createElement('div');
      chip.className = 'kp-chip';
      const nameEl = document.createElement('span');
      nameEl.className = 'kp-chip__name';
      nameEl.textContent = name;
      chip.appendChild(nameEl);

      const actions = document.createElement('span');
      actions.className = 'kp-chip__actions';
      const editBtn = document.createElement('button');
      editBtn.className = 'kp-chip__btn kp-chip__edit';
      editBtn.textContent = '修改';
      editBtn.addEventListener('click', (e) => { e.stopPropagation(); startEdit(chip, module, name, 'kp'); });
      const delBtn = document.createElement('button');
      delBtn.className = 'kp-chip__btn kp-chip__del';
      delBtn.textContent = '删除';
      delBtn.addEventListener('click', async (e) => {
        e.stopPropagation();
        const ok = await App.Components.confirm(
          '删除考点',
          `确定删除考点「${name}」？已录入错题 / 笔记中的该标签也会一并移除。`,
          '删除', '取消', true
        );
        if (ok) { await App.Tags.removeKnowledgePoint(module, name); App.Pages.Settings.render({}); }
      });
      actions.appendChild(editBtn);
      actions.appendChild(delBtn);
      chip.appendChild(actions);
      return chip;
    };

    // 单个错因 chip
    const buildCauseChip = (name) => {
      const chip = document.createElement('div');
      chip.className = 'kp-chip';
      const nameEl = document.createElement('span');
      nameEl.className = 'kp-chip__name';
      nameEl.textContent = name;
      chip.appendChild(nameEl);

      const actions = document.createElement('span');
      actions.className = 'kp-chip__actions';
      const editBtn = document.createElement('button');
      editBtn.className = 'kp-chip__btn kp-chip__edit';
      editBtn.textContent = '修改';
      editBtn.addEventListener('click', (e) => { e.stopPropagation(); startEdit(chip, null, name, 'ec'); });
      const delBtn = document.createElement('button');
      delBtn.className = 'kp-chip__btn kp-chip__del';
      delBtn.textContent = '删除';
      delBtn.addEventListener('click', async (e) => {
        e.stopPropagation();
        const ok = await App.Components.confirm(
          '删除错因',
          `确定删除错因「${name}」？已录入错题中的该标签也会一并移除。`,
          '删除', '取消', true
        );
        if (ok) { await App.Tags.removeErrorCause(name); App.Pages.Settings.render({}); }
      });
      actions.appendChild(editBtn);
      actions.appendChild(delBtn);
      chip.appendChild(actions);
      return chip;
    };

    // 模块级：标题 + 考点 chips + 新增行
    const buildModuleBlock = (mod) => {
      const modEl = document.createElement('div');
      modEl.className = 'kp-module';
      if (expanded['m:' + mod]) modEl.classList.add('is-open');

      const modHead = document.createElement('div');
      modHead.className = 'kp-module__head';
      const kps = App.Tags.getKnowledgePoints(mod);
      modHead.innerHTML = `
        <span class="kp-arrow">▸</span>
        <span class="kp-module__title">${mod}</span>
        <span class="kp-count">${kps.length}</span>
      `;
      modHead.addEventListener('click', () => {
        expanded['m:' + mod] = !expanded['m:' + mod];
        App.Pages.Settings.render({});
      });
      modEl.appendChild(modHead);

      const modBody = document.createElement('div');
      modBody.className = 'kp-module__body';

      const chipsWrap = document.createElement('div');
      chipsWrap.className = 'kp-chips';
      if (kps.length === 0) {
        const empty = document.createElement('span');
        empty.className = 'kp-empty';
        empty.textContent = '暂无考点';
        chipsWrap.appendChild(empty);
      } else {
        kps.forEach(kp => chipsWrap.appendChild(buildKpChip(mod, kp)));
      }
      modBody.appendChild(chipsWrap);

      const addRow = document.createElement('div');
      addRow.className = 'kp-add-row';
      const addInput = document.createElement('input');
      addInput.className = 'form-input';
      addInput.placeholder = '新增考点...';
      addInput.style.flex = '1';
      const addBtn = document.createElement('button');
      addBtn.className = 'btn btn--outline btn--sm';
      addBtn.textContent = '添加';
      addBtn.type = 'button';
      addBtn.addEventListener('click', async () => {
        const v = addInput.value.trim();
        if (!v) return;
        await App.Tags.addKnowledgePoint(mod, v);
        App.Pages.Settings.render({});
      });
      addInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addBtn.click(); } });
      addRow.appendChild(addInput);
      addRow.appendChild(addBtn);
      modBody.appendChild(addRow);

      modEl.appendChild(modBody);
      return modEl;
    };

    // 科目级：标题 + 模块列表
    App.Constants.SUBJECTS.forEach(subject => {
      const subjEl = document.createElement('div');
      subjEl.className = 'kp-subject';
      if (expanded['s:' + subject.name]) subjEl.classList.add('is-open');

      const subjHead = document.createElement('div');
      subjHead.className = 'kp-subject__head';
      subjHead.innerHTML = `
        <span class="kp-arrow">▸</span>
        <span class="kp-subject__icon">${subject.icon}</span>
        <span class="kp-subject__title">${subject.name}</span>
      `;
      subjHead.addEventListener('click', () => {
        expanded['s:' + subject.name] = !expanded['s:' + subject.name];
        App.Pages.Settings.render({});
      });
      subjEl.appendChild(subjHead);

      const subjBody = document.createElement('div');
      subjBody.className = 'kp-subject__body';
      App.Constants.getModules(subject.name).forEach(mod => {
        subjBody.appendChild(buildModuleBlock(mod));
      });
      subjEl.appendChild(subjBody);
      tree.appendChild(subjEl);
    });

    // 错因级：全局，单独一组
    const causeEl = document.createElement('div');
    causeEl.className = 'kp-subject kp-subject--cause';
    if (expanded['c:cause']) causeEl.classList.add('is-open');

    const causeHead = document.createElement('div');
    causeHead.className = 'kp-subject__head';
    const causes = App.Tags.getErrorCauses();
    causeHead.innerHTML = `
      <span class="kp-arrow">▸</span>
      <span class="kp-subject__icon">⚠️</span>
      <span class="kp-subject__title">错因标签（全局）</span>
      <span class="kp-count">${causes.length}</span>
    `;
    causeHead.addEventListener('click', () => {
      expanded['c:cause'] = !expanded['c:cause'];
      App.Pages.Settings.render({});
    });
    causeEl.appendChild(causeHead);

    const causeBody = document.createElement('div');
    causeBody.className = 'kp-subject__body';
    const causeChipsWrap = document.createElement('div');
    causeChipsWrap.className = 'kp-chips';
    if (causes.length === 0) {
      const empty = document.createElement('span');
      empty.className = 'kp-empty';
      empty.textContent = '暂无错因';
      causeChipsWrap.appendChild(empty);
    } else {
      causes.forEach(ec => causeChipsWrap.appendChild(buildCauseChip(ec)));
    }
    causeBody.appendChild(causeChipsWrap);

    const causeAddRow = document.createElement('div');
    causeAddRow.className = 'kp-add-row';
    const causeInput = document.createElement('input');
    causeInput.className = 'form-input';
    causeInput.placeholder = '新增错因...';
    causeInput.style.flex = '1';
    const causeAddBtn = document.createElement('button');
    causeAddBtn.className = 'btn btn--outline btn--sm';
    causeAddBtn.textContent = '添加';
    causeAddBtn.type = 'button';
    causeAddBtn.addEventListener('click', async () => {
      const v = causeInput.value.trim();
      if (!v) return;
      await App.Tags.addErrorCause(v);
      App.Pages.Settings.render({});
    });
    causeInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); causeAddBtn.click(); } });
    causeAddRow.appendChild(causeInput);
    causeAddRow.appendChild(causeAddBtn);
    causeBody.appendChild(causeAddRow);

    causeEl.appendChild(causeBody);
    tree.appendChild(causeEl);

    if (managed) tree.classList.add('is-managed');

    // 管理模式开关行为：仅切换 class，保留折叠状态
    const switchEl = mgmtBar.querySelector('#kp-mgmt-switch');
    switchEl.checked = managed;
    switchEl.addEventListener('change', () => {
      state.managed = switchEl.checked;
      managed = state.managed;
      tree.classList.toggle('is-managed', managed);
    });

    content.appendChild(tagSection);

    // ===== 关于 =====
    const aboutGroup = document.createElement('div');
    aboutGroup.className = 'settings-group';
    aboutGroup.innerHTML = `
      <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">关于</div>
      <div class="settings-item">
        <span class="settings-item__label">版本</span>
        <span class="settings-item__value">1.0.0</span>
      </div>
      <div class="settings-item">
        <span class="settings-item__label">存储方式</span>
        <span class="settings-item__value">本地 IndexedDB</span>
      </div>
      <div style="padding:16px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);line-height:1.6;text-align:center;">
        数据存储于浏览器本地，清除浏览器数据可能导致数据丢失。<br>
        请定期使用「导出备份」功能保存数据。
      </div>
    `;
    content.appendChild(aboutGroup);

    container.appendChild(content);
  }
};
