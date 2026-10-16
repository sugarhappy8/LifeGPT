import GRDB

enum Schema {
    /// Stored in `PRAGMA user_version` so a file can be recognized before opening it.
    static let version = 4

    static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
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
                """)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                ALTER TABLE session ADD COLUMN settings_json TEXT NOT NULL DEFAULT '{}';
                ALTER TABLE session ADD COLUMN author_notes TEXT NOT NULL DEFAULT '';
                ALTER TABLE session ADD COLUMN choices_json TEXT NOT NULL DEFAULT '[]';
                ALTER TABLE session ADD COLUMN ended INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE session ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;
                CREATE TABLE place_time_brief (
                    version INTEGER PRIMARY KEY, date TEXT NOT NULL, location TEXT NOT NULL,
                    text TEXT NOT NULL
                );
                CREATE TABLE life_state_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL,
                    key TEXT NOT NULL, value TEXT NOT NULL
                );
                CREATE TABLE opportunity_paths (id TEXT PRIMARY KEY, json TEXT NOT NULL);
                CREATE TABLE story_threads (id TEXT PRIMARY KEY, json TEXT NOT NULL);
                CREATE TABLE chapter_summaries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, through_message_id INTEGER NOT NULL UNIQUE,
                    date TEXT NOT NULL, text TEXT NOT NULL
                );
                CREATE TABLE financial_positions (id TEXT PRIMARY KEY, json TEXT NOT NULL);
                CREATE INDEX messages_date ON messages(date);
                CREATE INDEX decisions_date ON decisions(date);
                UPDATE session SET schema_version = 2;
                PRAGMA user_version = 2;
                """)
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK (length(trim(name)) > 0),
                    kind TEXT NOT NULL CHECK (kind IN ('personal', 'business', 'savings'))
                );
                INSERT INTO accounts (id, name, kind) VALUES ('personal', 'Personal', 'personal');
                ALTER TABLE ledger ADD COLUMN account_id TEXT NOT NULL DEFAULT 'personal';
                ALTER TABLE income_streams ADD COLUMN account_id TEXT NOT NULL DEFAULT 'personal';
                ALTER TABLE income_streams ADD COLUMN path_id TEXT;
                CREATE INDEX ledger_account ON ledger(account_id, id);
                CREATE INDEX income_streams_active_name ON income_streams(name) WHERE ended_on IS NULL;
                UPDATE session SET schema_version = 3;
                PRAGMA user_version = 3;
                """)
        }
        migrator.registerMigration("v4") { db in
            try db.execute(sql: """
                CREATE TABLE simulation_records (key TEXT PRIMARY KEY, json TEXT NOT NULL);
                ALTER TABLE accounts RENAME TO accounts_v3;
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK (length(trim(name)) > 0),
                    kind TEXT NOT NULL CHECK (kind IN ('personal', 'business', 'savings', 'tax_reserve', 'custom'))
                );
                INSERT INTO accounts SELECT * FROM accounts_v3;
                DROP TABLE accounts_v3;
                UPDATE session SET schema_version = 4;
                PRAGMA user_version = 4;
                """)
        }
        try migrator.migrate(queue)
    }
}
