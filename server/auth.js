const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('./database');
const { JWT_SECRET, genId } = require('./config');

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return res.status(401).json({ error: '未登录' });
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub || payload.id;
    next();
  } catch (e) {
    return res.status(401).json({ error: '登录已失效，请重新登录' });
  }
}

function register(req, res) {
  const { email, password } = req.body || {};
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return res.status(400).json({ error: '请输入有效邮箱' });
  }
  if (!password || password.length < 6) {
    return res.status(400).json({ error: '密码至少 6 位' });
  }
  if (db.prepare('SELECT id FROM users WHERE email=?').get(email)) {
    return res.status(409).json({ error: '该邮箱已注册' });
  }
  const hash = bcrypt.hashSync(password, 10);
  const id = genId('u');
  db.prepare('INSERT INTO users(id,email,password_hash,created_at) VALUES(?,?,?,?)')
    .run(id, email, hash, new Date().toISOString());
  const token = jwt.sign({ sub: id, email }, JWT_SECRET, { expiresIn: '30d' });
  return res.json({ token, email });
}

function login(req, res) {
  const { email, password } = req.body || {};
  const user = db.prepare('SELECT * FROM users WHERE email=?').get(email);
  if (!user || !bcrypt.compareSync(password || '', user.password_hash)) {
    return res.status(401).json({ error: '邮箱或密码错误' });
  }
  const token = jwt.sign({ sub: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });
  return res.json({ token, email: user.email });
}

module.exports = { requireAuth, register, login };
