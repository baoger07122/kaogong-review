// ===== 考公笔试复盘系统 - IndexedDB 数据库层 =====
window.App = window.App || {};

App.DB = (function() {
  const DB_NAME = 'CivilExamReview';
  const DB_VERSION = 4;
  let db = null;

  function ensureDb() {
    if (!db) throw new Error('数据库尚未初始化');
    return db;
  }

  // 写入操作统一等事务真正提交后再 resolve。
  // 仅监听 request.onsuccess 会在配额不足/事务提交失败时误报“保存成功”。
  function writeTransaction(storeName, action) {
    return new Promise((resolve, reject) => {
      let tx;
      try {
        tx = ensureDb().transaction(storeName, 'readwrite');
      } catch (e) {
        reject(e);
        return;
      }

      let result;
      let failed = false;
      const fail = (error) => {
        if (failed) return;
        failed = true;
        reject(error || new Error('数据库事务失败'));
      };

      tx.oncomplete = () => {
        if (!failed) resolve(result);
      };
      tx.onerror = () => fail(tx.error || new Error('数据库事务失败'));
      tx.onabort = () => fail(tx.error || new Error('数据库事务已回滚'));

      try {
        result = action(tx.objectStore(storeName));
      } catch (e) {
        fail(e);
        try { tx.abort(); } catch (abortError) { /* ignore */ }
      }
    });
  }

  // ===== 初始化数据库 =====
  async function init() {
    return new Promise((resolve, reject) => {
      if (!window.indexedDB) {
        reject(new Error('浏览器不支持 IndexedDB'));
        return;
      }

      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onupgradeneeded = function(e) {
        const db = e.target.result;

        // 1. 错题表
        if (!db.objectStoreNames.contains('errors')) {
          const errorsStore = db.createObjectStore('errors', { keyPath: 'id' });
          errorsStore.createIndex('subject', 'subject', { unique: false });
          errorsStore.createIndex('module', 'module', { unique: false });
          errorsStore.createIndex('knowledgePoint', 'knowledgePoint', { unique: false });
          errorsStore.createIndex('status', 'status', { unique: false });
          errorsStore.createIndex('errorCause', 'errorCause', { unique: false });
          errorsStore.createIndex('createdAt', 'createdAt', { unique: false });
          errorsStore.createIndex('lastReviewDate', 'lastReviewDate', { unique: false });
          errorsStore.createIndex('sourceExamId', 'sourceExamId', { unique: false });
        }

        // 2. 笔记表
        if (!db.objectStoreNames.contains('notes')) {
          const notesStore = db.createObjectStore('notes', { keyPath: 'id' });
          notesStore.createIndex('subject', 'subject', { unique: false });
          notesStore.createIndex('module', 'module', { unique: false });
          notesStore.createIndex('knowledgePoint', 'knowledgePoint', { unique: false });
          notesStore.createIndex('updatedAt', 'updatedAt', { unique: false });
        }

        // 3. 套卷表
        if (!db.objectStoreNames.contains('exams')) {
          const examsStore = db.createObjectStore('exams', { keyPath: 'id' });
          examsStore.createIndex('examDate', 'examDate', { unique: false });
          examsStore.createIndex('totalAccuracy', 'totalAccuracy', { unique: false });
        }

        // 4. 今日待办表
        if (!db.objectStoreNames.contains('todos')) {
          const todosStore = db.createObjectStore('todos', { keyPath: 'id' });
          todosStore.createIndex('createdAt', 'createdAt', { unique: false });
          todosStore.createIndex('completed', 'completed', { unique: false });
        }

        // 5. 科目复盘任务表
        if (!db.objectStoreNames.contains('subject_reviews')) {
          const reviewsStore = db.createObjectStore('subject_reviews', { keyPath: 'id' });
          reviewsStore.createIndex('subject', 'subject', { unique: false });
          reviewsStore.createIndex('createdAt', 'createdAt', { unique: false });
        }

        // 6. 通用键值表（持久化自定义标签库等）
        if (!db.objectStoreNames.contains('keyvalue')) {
          db.createObjectStore('keyvalue', { keyPath: 'key' });
        }

        // 7. 词语库表（成语释义/辨析/实词释义/辨析）
        if (!db.objectStoreNames.contains('words')) {
          const wordsStore = db.createObjectStore('words', { keyPath: 'id' });
          wordsStore.createIndex('category', 'category', { unique: false });
          wordsStore.createIndex('module', 'module', { unique: false });
          wordsStore.createIndex('subject', 'subject', { unique: false });
          wordsStore.createIndex('name', 'name', { unique: false });
          wordsStore.createIndex('groupId', 'groupId', { unique: false });
          wordsStore.createIndex('sentiment', 'sentiment', { unique: false });
        }

        // 8. 便签表（首页便签）
        if (!db.objectStoreNames.contains('stickies')) {
          const stickiesStore = db.createObjectStore('stickies', { keyPath: 'id' });
          stickiesStore.createIndex('createdAt', 'createdAt', { unique: false });
          stickiesStore.createIndex('pinned', 'pinned', { unique: false });
        }
      };

      request.onsuccess = function(e) {
        db = e.target.result;
        // iPad 同时保留旧页面/从后台恢复时，版本切换可能阻塞新连接；收到通知后主动释放旧连接。
        db.onversionchange = function() { try { db.close(); } catch (err) {} };
        resolve(db);
      };

      // 原先未处理 blocked，iPad PWA 的旧 WebView 未释放数据库时 Promise 会一直悬挂，
      // 初始化流程随之永远停在空白页。
      request.onblocked = function() {
        reject(new Error('数据库正在被旧页面占用，请关闭旧页面后重试'));
      };

      request.onerror = function(e) {
        reject(new Error('数据库打开失败: ' + e.target.error.message));
      };
    });
  }

  // ===== 通用 CRUD 方法 =====
  async function add(storeName, item) {
    return writeTransaction(storeName, (store) => {
      store.add(item);
      return item;
    });
  }

  async function put(storeName, item) {
    return writeTransaction(storeName, (store) => {
      store.put(item);
      return item;
    });
  }

  // 云同步/导入使用单事务批量写入，避免每条记录都创建一个 IndexedDB 事务。
  async function putMany(storeName, items) {
    const list = Array.isArray(items) ? items : [];
    if (!list.length) return list;
    return writeTransaction(storeName, (store) => {
      list.forEach(item => store.put(item));
      return list;
    });
  }

  async function remove(storeName, id) {
    return writeTransaction(storeName, (store) => {
      store.delete(id);
      return undefined;
    });
  }

  async function get(storeName, id) {
    return new Promise((resolve, reject) => {
      let tx;
      try { tx = ensureDb().transaction(storeName, 'readonly'); }
      catch (e) { reject(e); return; }
      const store = tx.objectStore(storeName);
      const request = store.get(id);
      request.onsuccess = () => resolve(request.result || null);
      request.onerror = () => reject(request.error);
    });
  }

  async function getAll(storeName) {
    return new Promise((resolve, reject) => {
      let tx;
      try { tx = ensureDb().transaction(storeName, 'readonly'); }
      catch (e) { reject(e); return; }
      const store = tx.objectStore(storeName);
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  }

  async function clearStore(storeName) {
    return writeTransaction(storeName, (store) => {
      store.clear();
      return undefined;
    });
  }

  // 备份导入需要跨多个 object store 一起替换，保证任一 store 写入失败时整次导入回滚。
  function replaceStores(replacements) {
    return new Promise((resolve, reject) => {
      const entries = Object.entries(replacements);
      let tx;
      try {
        tx = ensureDb().transaction(entries.map(([storeName]) => storeName), 'readwrite');
      } catch (e) {
        reject(e);
        return;
      }

      let failed = false;
      const fail = (error) => {
        if (failed) return;
        failed = true;
        reject(error || new Error('备份导入事务失败'));
      };
      tx.oncomplete = () => { if (!failed) resolve(); };
      tx.onerror = () => fail(tx.error || new Error('备份导入事务失败'));
      tx.onabort = () => fail(tx.error || new Error('备份导入事务已回滚'));

      try {
        entries.forEach(([storeName, items]) => {
          const store = tx.objectStore(storeName);
          store.clear();
          items.forEach(item => store.put(item));
        });
      } catch (e) {
        fail(e);
        try { tx.abort(); } catch (abortError) { /* ignore */ }
      }
    });
  }

  // ===== 错题专用方法 =====
  async function addError(error) {
    if (!error.id) error.id = App.Utils.genId('err');
    error.knowledgePoint = (error.knowledgePoints && error.knowledgePoints.length > 0)
      ? error.knowledgePoints[0] : '';
    error.reviewCount = error.reviewCount || 0;
    error.status = error.status || '未掌握';
    error.createdAt = error.createdAt || new Date().toISOString();
    error.lastReviewDate = error.lastReviewDate || error.createdAt;
    error.updatedAt = error.updatedAt || new Date().toISOString();
    return add('errors', error);
  }

  async function updateError(error) {
    error.knowledgePoint = (error.knowledgePoints && error.knowledgePoints.length > 0)
      ? error.knowledgePoints[0] : '';
    error.updatedAt = new Date().toISOString();
    return put('errors', error);
  }

  async function getErrors(filters) {
    const all = await getAll('errors');
    if (!filters) return all.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    let results = all;
    if (filters.subject) results = results.filter(r => r.subject === filters.subject);
    if (filters.module) results = results.filter(r => r.module === filters.module);
    if (filters.knowledgePoint) results = results.filter(r =>
      r.knowledgePoint === filters.knowledgePoint ||
      (r.knowledgePoints && r.knowledgePoints.includes(filters.knowledgePoint))
    );
    if (filters.status) results = results.filter(r => r.status === filters.status);
    if (filters.errorCause) results = results.filter(r => r.errorCause === filters.errorCause);
    if (filters.sourceExamId) results = results.filter(r => r.sourceExamId === filters.sourceExamId);
    if (filters.search) {
      const kw = filters.search.toLowerCase();
      results = results.filter(r =>
        r.question.toLowerCase().includes(kw) ||
        (r.knowledgePoints && r.knowledgePoints.some(kp => kp.toLowerCase().includes(kw)))
      );
    }

    return results.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  // 获取待复习错题（未掌握 + 距上次复习超过3天）
  async function getReviewQueue() {
    const all = await getAll('errors');
    return all.filter(r => {
      if (r.status !== '未掌握') return false;
      const days = App.Utils.daysSince(r.lastReviewDate);
      return days >= 3;
    }).sort((a, b) => {
      const daysA = App.Utils.daysSince(a.lastReviewDate);
      const daysB = App.Utils.daysSince(b.lastReviewDate);
      return daysB - daysA; // 越久没复习的越靠前
    });
  }

  // ===== 笔记专用方法 =====
  async function addNote(note) {
    if (!note.id) note.id = App.Utils.genId('note');
    note.linkedErrors = note.linkedErrors || [];
    note.linkedReviews = note.linkedReviews || [];
    note.updatedAt = note.updatedAt || new Date().toISOString();
    return add('notes', note);
  }

  async function updateNote(note) {
    note.updatedAt = new Date().toISOString();
    return put('notes', note);
  }

  async function getNotes(filters) {
    const all = await getAll('notes');
    if (!filters) return all.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));

    let results = all;
    if (filters.subject) results = results.filter(r => r.subject === filters.subject);
    if (filters.module) results = results.filter(r => r.module === filters.module);
    if (filters.knowledgePoint) results = results.filter(r => r.knowledgePoint === filters.knowledgePoint);
    if (filters.search) {
      const kw = filters.search.toLowerCase();
      results = results.filter(r =>
        String(r.title || '').toLowerCase().includes(kw) ||
        (r.content != null && (Array.isArray(r.content)
          ? JSON.stringify(r.content)
          : String(r.content)).toLowerCase().includes(kw))
      );
    }

    return results.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
  }

  // ===== 便签专用方法 =====
  async function addSticky(sticky) {
    if (!sticky.id) sticky.id = App.Utils.genId('sticky');
    sticky.content = sticky.content || '';
    sticky.color = sticky.color || '#FFFBEB';
    sticky.pinned = !!sticky.pinned;
    sticky.createdAt = sticky.createdAt || new Date().toISOString();
    sticky.updatedAt = sticky.updatedAt || sticky.createdAt;
    return add('stickies', sticky);
  }

  async function updateSticky(sticky) {
    sticky.updatedAt = new Date().toISOString();
    return put('stickies', sticky);
  }

  async function removeSticky(id) {
    return remove('stickies', id);
  }

  async function getStickies() {
    const all = await getAll('stickies');
    // 置顶优先，其次按最近更新时间倒序
    return all.sort((a, b) => {
      if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
      return new Date(b.updatedAt || b.createdAt || 0) - new Date(a.updatedAt || a.createdAt || 0);
    });
  }

  // ===== 套卷专用方法 =====
  async function addExam(exam) {
    if (!exam.id) exam.id = App.Utils.genId('exam');
    exam.subjectScores = exam.subjectScores || [];
    exam.linkedErrorIds = exam.linkedErrorIds || [];
    exam.updatedAt = exam.updatedAt || new Date().toISOString();
    return add('exams', exam);
  }

  async function updateExam(exam) {
    exam.updatedAt = new Date().toISOString();
    return put('exams', exam);
  }

  async function getExams(filters) {
    const all = await getAll('exams');
    if (!filters) return all.sort((a, b) => new Date(b.examDate) - new Date(a.examDate));

    let results = all;
    if (filters.subject) {
      results = results.filter(r =>
        r.subjectScores && r.subjectScores.some(s => s.subject === filters.subject)
      );
    }
    if (filters.search) {
      const kw = filters.search.toLowerCase();
      results = results.filter(r => r.name.toLowerCase().includes(kw));
    }

    return results.sort((a, b) => new Date(b.examDate) - new Date(a.examDate));
  }

  // ===== 待办专用方法 =====
  async function addTodo(todo) {
    if (!todo.id) todo.id = App.Utils.genId('todo');
    todo.completed = todo.completed || false;
    todo.status = todo.status || (todo.completed ? 'completed' : 'pending');
    todo.note = todo.note || '';
    todo.type = todo.type || 'yanyu';
    todo.createdAt = todo.createdAt || new Date().toISOString();
    todo.updatedAt = todo.updatedAt || new Date().toISOString();
    todo.dailyTimes = todo.dailyTimes || {};   // v8.14.10 按日分段计时 { 'YYYY-MM-DD': ms }
    if (todo.completed && !todo.completedAt) todo.completedAt = todo.updatedAt;
    return add('todos', todo);
  }

  async function updateTodo(todo) {
    todo.updatedAt = new Date().toISOString();
    todo.status = todo.status || (todo.completed ? 'completed' : 'pending');
    todo.note = todo.note || '';
    todo.type = todo.type || 'yanyu';
    if (!todo.dailyTimes) todo.dailyTimes = {};
    if (todo.completed && !todo.completedAt) todo.completedAt = todo.updatedAt;
    if (!todo.completed) todo.completedAt = null;
    return put('todos', todo);
  }

  async function getTodos() {
    const all = await getAll('todos');
    // 未完成的在前，按创建时间降序
    return all.sort((a, b) => {
      if (a.completed !== b.completed) return a.completed ? 1 : -1;
      return new Date(b.createdAt) - new Date(a.createdAt);
    });
  }

  // ===== 科目复盘任务专用方法 =====
  async function addReviewTask(task) {
    if (!task.id) task.id = App.Utils.genId('review');
    task.reviewNote = task.reviewNote || '';
    task.createdAt = task.createdAt || new Date().toISOString();
    task.updatedAt = task.updatedAt || new Date().toISOString();
    return add('subject_reviews', task);
  }

  async function updateReviewTask(task) {
    task.updatedAt = new Date().toISOString();
    return put('subject_reviews', task);
  }

  async function getReviewTasks(subject) {
    const all = await getAll('subject_reviews');
    if (subject) {
      return all.filter(r => r.subject === subject).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }
    return all.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  // ===== 词语库 CRUD =====
  async function addWord(word) {
    if (!word.id) word.id = 'w_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
    if (!word.createdAt) word.createdAt = new Date().toISOString();
    if (!word.updatedAt) word.updatedAt = word.createdAt;
    return add('words', word);
  }

  async function updateWord(word) {
    word.updatedAt = new Date().toISOString();
    return put('words', word);
  }

  async function getWord(id) {
    return get('words', id);
  }

  async function getWords(filters) {
    const all = await getAll('words');
    let result = all;
    if (filters) {
      if (filters.category) result = result.filter(w => w.category === filters.category);
      if (filters.module) result = result.filter(w => w.module === filters.module);
      if (filters.subject) result = result.filter(w => w.subject === filters.subject);
      if (filters.sentiment) result = result.filter(w => w.sentiment === filters.sentiment);
      if (filters.groupId) result = result.filter(w => w.groupId === filters.groupId);
      if (filters.search) {
        const q = filters.search.toLowerCase();
        // 归一化：去声调符号、去空格、转小写，便于按拼音模糊检索
        const stripDiacritics = (s) => (s || '').normalize('NFD')
          .split('').filter(ch => ch.charCodeAt(0) < 0x300 || ch.charCodeAt(0) > 0x36f).join('');
        const normalize = (s) => stripDiacritics(s).toLowerCase().replace(/[^a-z0-9]/g, '');
        const qn = normalize(q);
        result = result.filter(w =>
          (w.name || '').toLowerCase().includes(q) ||
          (w.meaning || '').toLowerCase().includes(q) ||
          (w.pinyin || '').toLowerCase().includes(q) ||
          normalize(w.pinyin).includes(qn)
        );
      }
    }
    // 默认按名称排序
    result.sort((a, b) => (a.name || '').localeCompare(b.name || '', 'zh'));
    return result;
  }

  async function deleteWord(id) {
    return remove('words', id);
  }

  // ===== 统计方法 =====
  async function getStats() {
    const [errors, notes, exams, subjectReviews] = await Promise.all([
      getAll('errors'), getAll('notes'), getAll('exams'), getAll('subject_reviews')
    ]);
    const todayStr = new Date().toISOString().slice(0, 10);

    const subjectStats = {};
    App.Constants.SUBJECTS.forEach(s => {
      const subErrors = errors.filter(e => e.subject === s.name);
      const subNotes = notes.filter(n => n.subject === s.name);
      const subReviews = subjectReviews.filter(r => r.subject === s.name);
      subjectStats[s.name] = {
        totalErrors: subErrors.length,
        unmastered: subErrors.filter(e => e.status === '未掌握').length,
        mastered: subErrors.filter(e => e.status === '已掌握').length,
        todayReviews: subReviews.filter(r => String(r.createdAt || '').slice(0, 10) === todayStr).length,
        totalNotes: subNotes.length,
        todayNewErrors: subErrors.filter(e => String(e.createdAt || '').slice(0, 10) === todayStr).length
      };
    });

    const thisWeekStart = new Date();
    thisWeekStart.setDate(thisWeekStart.getDate() - thisWeekStart.getDay());
    const weekStartStr = thisWeekStart.toISOString().slice(0, 10);

    return {
      totalErrors: errors.length,
      unmasteredErrors: errors.filter(e => e.status === '未掌握').length,
      masteredErrors: errors.filter(e => e.status === '已掌握').length,
      todayNewErrors: errors.filter(e => String(e.createdAt || '').slice(0, 10) === todayStr).length,
      weekNewErrors: errors.filter(e => String(e.createdAt || '').slice(0, 10) >= weekStartStr).length,
      totalNotes: notes.length,
      totalExams: exams.length,
      thisWeekExams: exams.filter(e => e.examDate >= weekStartStr).length,
      totalTime: exams.reduce((sum, e) => sum + (e.totalTime || 0), 0),
      avgAccuracy: exams.length > 0
        ? Math.round(exams.reduce((sum, e) => sum + (e.totalAccuracy || 0), 0) / exams.length)
        : 0,
      subjectStats
    };
  }

  // ===== 导出数据 =====
  async function exportAll() {
    const [kv, errors, notes, exams, todos, subjectReviews, words, stickies] = await Promise.all([
      getAll('keyvalue'), getAll('errors'), getAll('notes'), getAll('exams'),
      getAll('todos'), getAll('subject_reviews'), getAll('words'), getAll('stickies')
    ]);
    const data = {
      version: 1,
      exportedAt: new Date().toISOString(),
      errors,
      notes,
      exams,
      todos,
      subjectReviews,
      keyvalue: kv.filter(r => !(r.key && r.key.indexOf('auto_backup_') === 0)),   // v8.6.6 排除自动备份包，防递归膨胀
      words,
      stickies
    };

    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    // 固定文件名，避免每天多次导出产生大量带日期的文件
    a.download = '考公备考系统-backup.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    return data;
  }

  // ===== 导入数据 =====
  async function importAll(jsonData) {
    if (!jsonData || !jsonData.version) {
      throw new Error('无效的备份文件格式');
    }

    const mappings = {
      'errors': 'errors',
      'notes': 'notes',
      'exams': 'exams',
      'todos': 'todos',
      'subjectReviews': 'subject_reviews',
      'keyvalue': 'keyvalue',
      'words': 'words',
      'stickies': 'stickies'
    };

    const replacements = {};
    for (const [jsonKey, storeName] of Object.entries(mappings)) {
      const items = jsonData[jsonKey] || [];
      if (!Array.isArray(items)) throw new Error('备份字段「' + jsonKey + '」格式错误');
      replacements[storeName] = items;
    }
    await replaceStores(replacements);
  }

  // ===== 构建备份数据包（供导出 / 云分享 / 自动备份复用）=====
  // v8.6.6 修复备份膨胀：keyvalue 排除 auto_backup_* 自动备份包——
  // 此前自动备份把完整包存进 keyvalue，导出时又被打包，指数级递归膨胀（实测 100 条笔记即达 17MB，导致 iOS 分享/下载失败「无法备份」）
  async function buildBackupData() {
    const [kv, errors, notes, exams, todos, subjectReviews, words, stickies] = await Promise.all([
      getAll('keyvalue'), getAll('errors'), getAll('notes'), getAll('exams'),
      getAll('todos'), getAll('subject_reviews'), getAll('words'), getAll('stickies')
    ]);
    return {
      version: 1,
      app: 'kaogong-review',
      exportedAt: new Date().toISOString(),
      errors,
      notes,
      exams,
      todos,
      subjectReviews,
      keyvalue: kv.filter(r => !(r.key && r.key.indexOf('auto_backup_') === 0)),
      words,
      stickies
    };
  }

  const BACKUP_FILE_NAME = '考公备考系统-backup.json';

  // ===== 分享备份到 iCloud（合并为一个文件）=====
  async function shareBackupToICloud() {
    const data = await buildBackupData();
    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const file = new File([blob], BACKUP_FILE_NAME, { type: 'application/json' });
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      // 只分享文件，不要加 title/text，否则 iOS 会把 title 当作文本项出现“2项”
      await navigator.share({ files: [file] });
    } else {
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = BACKUP_FILE_NAME;
      document.body.appendChild(a); a.click(); document.body.removeChild(a);
      URL.revokeObjectURL(url);
      App.Components.toast('已下载备份文件，可手动移入 iCloud 的「考公备考系统」文件夹', 'success');
    }
    await kvSet('last_icloud_backup', Date.now());
  }

  // v8.6.7 已移除自动备份功能（用户要求）：本地自动备份（autoBackup 等）与 iCloud 自动备份提醒
  // （getBackupInterval/setBackupInterval/isBackupDue）全部删除。历史遗留 keyvalue 中的 auto_backup_*
  // 键由 buildBackupData/exportAll 的过滤逻辑兜底（不进入导出），本地残留数据无害。

  // ===== 检查数据库是否可用 =====
  async function isAvailable() {
    try {
      if (!window.indexedDB) return false;
      await init();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===== 通用键值读写（自定义标签库等） =====
  async function kvGet(key) {
    const item = await get('keyvalue', key);
    return item ? item.value : null;
  }

  async function kvSet(key, value) {
    return put('keyvalue', { key, value });
  }

  return {
    init,
    add, put, putMany, remove, get, getAll, clearStore, replaceStores,
    addError, updateError, getErrors, getReviewQueue,
    addNote, updateNote, getNotes,
    addSticky, updateSticky, removeSticky, getStickies,
    addExam, updateExam, getExams,
    addTodo, updateTodo, getTodos,
    addReviewTask, updateReviewTask, getReviewTasks,
    addWord, updateWord, getWord, getWords, deleteWord,
    getStats,
    exportAll, importAll,
    buildBackupData, shareBackupToICloud,
    kvGet, kvSet,
    isAvailable
  };
})();

