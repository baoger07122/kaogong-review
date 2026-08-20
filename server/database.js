const { DatabaseSync } = require('node:sqlite');
const { DB_PATH } = require('./config');

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

module.exports = db;
