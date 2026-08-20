const express = require('express');
const db = require('./database');
const { ALLOWED, RESERVED } = require('./config');
const { requireAuth, register, login } = require('./auth');

const router = express.Router();

// ===== 认证 =====
router.post('/auth/register', register);
router.post('/auth/login', login);

// ===== 健康检查 =====
router.get('/health', (req, res) => {
  res.json({ ok: true, service: 'kaogong-cloud-api', time: new Date().toISOString() });
});

// ===== 导出 / 导入 =====
router.get('/export', requireAuth, (req, res) => {
  const out = {};
  for (const coll of ALLOWED) {
    const rows = db.prepare('SELECT data FROM records WHERE coll=? AND user_id=?').all(coll, req.userId);
    out[coll] = rows.map(row => JSON.parse(row.data));
  }
  const keyvalueRows = db.prepare('SELECT key,value FROM keyvalue WHERE user_id=?').all(req.userId);
  out.keyvalue = {};
  keyvalueRows.forEach(row => { out.keyvalue[row.key] = JSON.parse(row.value); });
  res.json(out);
});

router.post('/import', requireAuth, (req, res) => {
  const data = req.body || {};
  for (const coll of ALLOWED) {
    if (data[coll] !== undefined && !Array.isArray(data[coll])) {
      return res.status(400).json({ error: '集合 ' + coll + ' 必须是数组' });
    }
  }
  if (data.keyvalue !== undefined && (!data.keyvalue || typeof data.keyvalue !== 'object' || Array.isArray(data.keyvalue))) {
    return res.status(400).json({ error: 'keyvalue 必须是对象' });
  }

  // 导入是整库替换，必须在一个事务内完成；否则中途失败会留下半套数据。
  db.exec('BEGIN IMMEDIATE');
  try {
    db.prepare('DELETE FROM records WHERE user_id=?').run(req.userId);
    db.prepare('DELETE FROM keyvalue WHERE user_id=?').run(req.userId);
    const insertRecord = db.prepare('INSERT OR REPLACE INTO records(id,user_id,coll,data) VALUES(?,?,?,?)');
    const insertKeyvalue = db.prepare('INSERT OR REPLACE INTO keyvalue(user_id,key,value) VALUES(?,?,?)');

    for (const coll of ALLOWED) {
      (data[coll] || []).forEach(item => {
        if (item && typeof item === 'object' && item.id) {
          insertRecord.run(item.id, req.userId, coll, JSON.stringify(item));
        }
      });
    }
    if (data.keyvalue) {
      Object.entries(data.keyvalue).forEach(([key, value]) => {
        insertKeyvalue.run(req.userId, key, JSON.stringify(value));
      });
    }
    db.exec('COMMIT');
  } catch (e) {
    try { db.exec('ROLLBACK'); } catch (rollbackError) { /* ignore */ }
    console.error('[kaogong-cloud-api] import failed:', e);
    return res.status(400).json({ error: '导入失败，原数据未改变' });
  }
  res.json({ ok: true });
});

// ===== keyvalue（必须在通用 :coll 路由之前）=====
router.get('/keyvalue/:key', requireAuth, (req, res) => {
  const row = db.prepare('SELECT value FROM keyvalue WHERE user_id=? AND key=?').get(req.userId, req.params.key);
  res.json(row ? JSON.parse(row.value) : null);
});

router.put('/keyvalue/:key', requireAuth, (req, res) => {
  db.prepare('INSERT OR REPLACE INTO keyvalue(user_id,key,value) VALUES(?,?,?)')
    .run(req.userId, req.params.key, JSON.stringify(req.body));
  res.json({ ok: true });
});

// ===== 集合通用 CRUD =====
function validateCollection(req, res) {
  const coll = req.params.coll;
  if (RESERVED.has(coll) || !ALLOWED.has(coll)) {
    res.status(400).json({ error: '非法集合' });
    return null;
  }
  return coll;
}

router.get('/:coll', requireAuth, (req, res) => {
  const coll = validateCollection(req, res);
  if (!coll) return;
  const rows = db.prepare('SELECT data FROM records WHERE coll=? AND user_id=?').all(coll, req.userId);
  res.json(rows.map(row => JSON.parse(row.data)));
});

router.post('/:coll', requireAuth, (req, res) => {
  const coll = validateCollection(req, res);
  if (!coll) return;
  const item = req.body;
  if (!item || !item.id) return res.status(400).json({ error: '记录缺少 id' });
  db.prepare('INSERT OR REPLACE INTO records(id,user_id,coll,data) VALUES(?,?,?,?)')
    .run(item.id, req.userId, coll, JSON.stringify(item));
  res.json({ ok: true });
});

router.put('/:coll/:id', requireAuth, (req, res) => {
  const coll = validateCollection(req, res);
  if (!coll) return;
  const item = req.body;
  if (!item) return res.status(400).json({ error: '缺少内容' });
  item.id = req.params.id;
  db.prepare('INSERT OR REPLACE INTO records(id,user_id,coll,data) VALUES(?,?,?,?)')
    .run(item.id, req.userId, coll, JSON.stringify(item));
  res.json({ ok: true });
});

router.delete('/:coll/:id', requireAuth, (req, res) => {
  const coll = validateCollection(req, res);
  if (!coll) return;
  db.prepare('DELETE FROM records WHERE coll=? AND user_id=? AND id=?')
    .run(coll, req.userId, req.params.id);
  res.json({ ok: true });
});

module.exports = router;
