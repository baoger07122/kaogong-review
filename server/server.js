// ===== 考公笔试复盘系统 - 云端存储后端（同时托管前端静态文件）=====
// Node.js + Express + node:sqlite(零原生依赖) + JWT 多用户认证
// 所有数据按 user_id 隔离；集合统一存于 records 表，keyvalue 单独表。
// 同一进程同时提供：前端静态文件（来自 /workspace）与 /api 接口。
require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { DatabaseSync } = require('node:sqlite');

const PORT = parseInt(process.env.PORT || '3000', 10);
const JWT_SECRET = process.env.JWT_SECRET || 'CHANGE_ME_TO_A_LONG_RANDOM_STRING';
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*'; // 逗号分隔的允许源，或 *
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'data.sqlite');
const WORKSPACE = path.join(__dirname, '..'); // /workspace（前端静态文件目录）

const db = new DatabaseSync(DB_PATH);
try { db.pragma('journal_mode = WAL'); } catch (e) { /* ignore */ }

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS records (
    id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    coll TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (coll, user_id, id)
  );
  CREATE TABLE IF NOT EXISTS keyvalue (
    key TEXT NOT NULL,
    user_id TEXT NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY (user_id, key)
  );
`);
db.prepare('CREATE INDEX IF NOT EXISTS idx_records_user ON records(user_id, coll)').run();

const ALLOWED = new Set(['errors', 'notes', 'exams', 'todos', 'subject_reviews', 'words']);
// 通用 /api/:coll 路由的保留字，避免与具体接口冲突（防御性）
const RESERVED = new Set(['auth', 'health', 'export', 'import', 'keyvalue']);
const genId = (p) => p + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);

const app = express();
const corsOrigins = CORS_ORIGIN === '*' ? true : CORS_ORIGIN.split(',').map(s => s.trim()).filter(Boolean);
app.use(cors({ origin: corsOrigins, credentials: true }));
app.use(express.json({ limit: '8mb' }));

// ===== 静态文件托管（前端单文件应用）=====
// 出于安全，屏蔽服务端源码与敏感目录
app.use((req, res, next) => {
  const u = req.path.toLowerCase();
  if (
    u.startsWith('/server') ||
    u.startsWith('/.git') ||
    u.startsWith('/node_modules') ||
    u.includes('.env') ||
    u.endsWith('/server/')
  ) return res.status(404).end();
  next();
});
app.use(express.static(WORKSPACE, { index: 'index.html' }));

function requireAuth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  if (!token) return res.status(401).json({ error: '未登录' });
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub || payload.id;
    next();
  } catch (e) {
    return res.status(401).json({ error: '登录已失效，请重新登录' });
  }
}

// ===== 认证（公开）=====
app.post('/api/auth/register', (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: '请输入有效邮箱' });
  if (!password || password.length < 6) return res.status(400).json({ error: '密码至少 6 位' });
  if (db.prepare('SELECT id FROM users WHERE email=?').get(email)) return res.status(409).json({ error: '该邮箱已注册' });
  const hash = bcrypt.hashSync(password, 10);
  const id = genId('u');
  db.prepare('INSERT INTO users(id,email,password_hash,created_at) VALUES(?,?,?,?)').run(id, email, hash, new Date().toISOString());
  const token = jwt.sign({ sub: id, email }, JWT_SECRET, { expiresIn: '30d' });
  res.json({ token, email });
});

app.post('/api/auth/login', (req, res) => {
  const { email, password } = req.body || {};
  const u = db.prepare('SELECT * FROM users WHERE email=?').get(email);
  if (!u || !bcrypt.compareSync(password || '', u.password_hash)) return res.status(401).json({ error: '邮箱或密码错误' });
  const token = jwt.sign({ sub: u.id, email: u.email }, JWT_SECRET, { expiresIn: '30d' });
  res.json({ token, email: u.email });
});

// ===== 健康检查（公开）=====
app.get('/api/health', (req, res) => res.json({ ok: true, service: 'kaogong-cloud-api', time: new Date().toISOString() }));

// ===== 导出 / 导入（整库迁移，需在通用 :coll 路由之前定义）=====
app.get('/api/export', requireAuth, (req, res) => {
  const out = {};
  for (const c of ALLOWED) {
    const rows = db.prepare('SELECT data FROM records WHERE coll=? AND user_id=?').all(c, req.userId);
    out[c] = rows.map(r => JSON.parse(r.data));
  }
  const kv = db.prepare('SELECT key,value FROM keyvalue WHERE user_id=?').all(req.userId);
  out.keyvalue = {};
  kv.forEach(r => { out.keyvalue[r.key] = JSON.parse(r.value); });
  res.json(out);
});

app.post('/api/import', requireAuth, (req, res) => {
  const data = req.body || {};
  db.prepare('DELETE FROM records WHERE user_id=?').run(req.userId);
  db.prepare('DELETE FROM keyvalue WHERE user_id=?').run(req.userId);
  for (const c of ALLOWED) {
    (data[c] || []).forEach(item => {
      if (item && item.id) db.prepare('INSERT OR REPLACE INTO records(id,user_id,coll,data) VALUES(?,?,?,?)').run(item.id, req.userId, c, JSON.stringify(item));
    });
  }
  if (data.keyvalue && typeof data.keyvalue === 'object') {
    Object.entries(data.keyvalue).forEach(([k, v]) => {
      db.prepare('INSERT OR REPLACE INTO keyvalue(user_id,key,value) VALUES(?,?,?)').run(req.userId, k, JSON.stringify(v));
    });
  }
  res.json({ ok: true });
});

// ===== keyvalue（需在通用 :coll 路由之前定义，否则会被 :coll 抢先匹配）=====
app.get('/api/keyvalue/:key', requireAuth, (req, res) => {
  const r = db.prepare('SELECT value FROM keyvalue WHERE user_id=? AND key=?').get(req.userId, req.params.key);
  res.json(r ? JSON.parse(r.value) : null);
});
app.put('/api/keyvalue/:key', requireAuth, (req, res) => {
  db.prepare('INSERT OR REPLACE INTO keyvalue(user_id,key,value) VALUES(?,?,?)').run(req.userId, req.params.key, JSON.stringify(req.body));
  res.json({ ok: true });
});

// ===== 集合通用 CRUD =====
app.get('/api/:coll', requireAuth, (req, res) => {
  const coll = req.params.coll;
  if (RESERVED.has(coll) || !ALLOWED.has(coll)) return res.status(400).json({ error: '非法集合' });
  const rows = db.prepare('SELECT data FROM records WHERE coll=? AND user_id=?').all(coll, req.userId);
  res.json(rows.map(r => JSON.parse(r.data)));
});

app.post('/api/:coll', requireAuth, (req, res) => {
  const coll = req.params.coll;
  if (RESERVED.has(coll) || !ALLOWED.has(coll)) return res.status(400).json({ error: '非法集合' });
  const item = req.body;
  if (!item || !item.id) return res.status(400).json({ error: '记录缺少 id' });
  db.prepare('INSERT OR REPLACE INTO records(id,user_id,coll,data) VALUES(?,?,?,?)').run(item.id, req.userId, coll, JSON.stringify(item));
  res.json({ ok: true });
});

app.put('/api/:coll/:id', requireAuth, (req, res) => {
  const coll = req.params.coll;
  if (RESERVED.has(coll) || !ALLOWED.has(coll)) return res.status(400).json({ error: '非法集合' });
  const item = req.body;
  if (!item) return res.status(400).json({ error: '缺少内容' });
  item.id = req.params.id;
  db.prepare('INSERT OR REPLACE INTO records(id,user_id,coll,data) VALUES(?,?,?,?)').run(item.id, req.userId, coll, JSON.stringify(item));
  res.json({ ok: true });
});

app.delete('/api/:coll/:id', requireAuth, (req, res) => {
  const coll = req.params.coll;
  if (RESERVED.has(coll) || !ALLOWED.has(coll)) return res.status(400).json({ error: '非法集合' });
  db.prepare('DELETE FROM records WHERE coll=? AND user_id=? AND id=?').run(coll, req.userId, req.params.id);
  res.json({ ok: true });
});

// ===== 兜底：SPA 直接返回首页（避免刷新 404）=====
app.get('/', (req, res) => {
  res.sendFile(path.join(WORKSPACE, 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('[kaogong-cloud-api] listening on :' + PORT + '  CORS=' + CORS_ORIGIN + '  static=' + WORKSPACE);
});
