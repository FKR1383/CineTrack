import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, 'cinetrack_simple.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
    );
    _database = db;
    return db;
  }

  Future<void> initialize() async => database;

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        email TEXT NOT NULL COLLATE NOCASE UNIQUE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        avatar_path TEXT,
        bio TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE password_reset_tokens (
        token TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE media_cache (
        media_id TEXT PRIMARY KEY,
        media_type TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        summary_json TEXT NOT NULL,
        detail_json TEXT,
        fetched_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE api_cache (
        cache_key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE user_media (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        media_id TEXT NOT NULL,
        watch_status TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, media_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE ratings (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        media_id TEXT NOT NULL,
        score INTEGER NOT NULL CHECK(score BETWEEN 1 AND 5),
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, media_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE comments (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        media_id TEXT NOT NULL,
        text TEXT NOT NULL,
        is_spoiler INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_lists (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT,
        is_public INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_list_items (
        list_id TEXT NOT NULL REFERENCES custom_lists(id) ON DELETE CASCADE,
        media_id TEXT NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (list_id, media_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE user_episodes (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        episode_id TEXT NOT NULL,
        media_id TEXT NOT NULL,
        season_number INTEGER NOT NULL,
        episode_number INTEGER NOT NULL,
        runtime_minutes INTEGER,
        watched INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, episode_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        media_id TEXT NOT NULL,
        media_title TEXT NOT NULL,
        media_type TEXT NOT NULL,
        detail TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE reports (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        comment_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_user_media_user ON user_media(user_id, updated_at DESC)');
    await db.execute('CREATE INDEX idx_comments_media ON comments(media_id, created_at DESC)');
    await db.execute('CREATE INDEX idx_activity_user ON activity(user_id, occurred_at DESC)');
    await db.execute('CREATE INDEX idx_user_episodes_media ON user_episodes(user_id, media_id)');
  }
}
