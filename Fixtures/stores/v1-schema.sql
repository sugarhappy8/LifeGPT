CREATE TABLE session (
    id TEXT PRIMARY KEY,
    schema_version INTEGER NOT NULL,
    created_at REAL NOT NULL,
    last_played REAL NOT NULL,
    swing_dial INTEGER NOT NULL,
    reply_length_words INTEGER NOT NULL
);
CREATE TABLE character (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    birthplace TEXT NOT NULL,
    birth_year INTEGER NOT NULL,
    appearance TEXT NOT NULL,
    starting_age INTEGER NOT NULL,
    background TEXT,
    family_wealth_tier TEXT NOT NULL,
    birth_date TEXT NOT NULL,
    game_date TEXT NOT NULL
);
CREATE TABLE economy_card (
    version INTEGER PRIMARY KEY,
    json TEXT NOT NULL
);
CREATE TABLE ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    source_type TEXT NOT NULL,
    amount_minor INTEGER NOT NULL,
    reason TEXT NOT NULL,
    counterparty TEXT,
    balance_after_minor INTEGER NOT NULL,
    origin TEXT NOT NULL
);
CREATE INDEX ledger_source ON ledger (source_type, date);
CREATE TABLE income_streams (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE,
    kind TEXT NOT NULL,
    tier TEXT,
    monthly_minor INTEGER NOT NULL,
    started_on TEXT NOT NULL,
    ended_on TEXT
);
CREATE TABLE cast_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK (length(name) > 0),
    relation TEXT,
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'alive',
    first_met TEXT NOT NULL,
    last_seen TEXT NOT NULL
);
CREATE TABLE decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    summary TEXT NOT NULL,
    choice TEXT NOT NULL,
    importance TEXT NOT NULL
);
CREATE TABLE life_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    title TEXT NOT NULL,
    importance TEXT NOT NULL,
    uncanny INTEGER NOT NULL
);
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role TEXT NOT NULL,
    text TEXT NOT NULL,
    date TEXT NOT NULL
);
CREATE TABLE turn_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    fate INTEGER NOT NULL,
    rejections_json TEXT NOT NULL,
    repaired INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL
);
PRAGMA user_version = 1;
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
INSERT INTO grdb_migrations VALUES ('v1');
