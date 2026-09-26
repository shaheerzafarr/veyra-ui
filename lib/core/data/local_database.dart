import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class VeyraDatabase {
  VeyraDatabase({DatabaseFactory? factory, String? path})
      : _factory = factory ?? databaseFactory,
        _explicitPath = path;

  static const schemaVersion = 2;
  final DatabaseFactory _factory;
  final String? _explicitPath;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path = _explicitPath ??
        p.join(await _factory.getDatabasesPath(), 'veyra_local.db');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await _createV1(db);
          await _seed(db);
        },
        onUpgrade: _migrate,
      ),
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> _migrate(Database db, int from, int to) async {
    // Additive, version-by-version migrations are added here. Never delete the
    // database to evolve the schema.
    if (from < 1) await _createV1(db);
    if (from < 2) {
      await db.execute('ALTER TABLE messages ADD COLUMN sender_device_id TEXT');
      await db
          .execute('ALTER TABLE messages ADD COLUMN server_received_at TEXT');
      await db.execute(
          'ALTER TABLE messages ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE messages ADD COLUMN next_retry_at TEXT');
      await db.execute(
        "CREATE INDEX messages_outbox ON messages(delivery_status, next_retry_at) WHERE delivery_status = 'sending'",
      );
    }
  }

  Future<void> _createV1(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        avatar TEXT,
        avatar_color INTEGER NOT NULL,
        bio TEXT,
        is_discoverable INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX users_username_ci ON users(lower(username))',
    );
    await db.execute(
      'CREATE INDEX users_discovery ON users(is_discoverable, display_name)',
    );
    await db.execute('''
      CREATE TABLE app_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        theme TEXT NOT NULL DEFAULT 'dark',
        notifications_enabled INTEGER NOT NULL DEFAULT 1,
        call_notifications_enabled INTEGER NOT NULL DEFAULT 1,
        read_receipts_enabled INTEGER NOT NULL DEFAULT 1,
        profile_photo_visibility TEXT NOT NULL DEFAULT 'everyone',
        request_audience TEXT NOT NULL DEFAULT 'everyone',
        wifi_only_downloads INTEGER NOT NULL DEFAULT 0,
        font_scale REAL NOT NULL DEFAULT 1.0
      )
    ''');
    await db.execute('''
      CREATE TABLE contact_requests (
        id TEXT PRIMARY KEY,
        sender_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        recipient_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        introductory_message TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN
          ('pending','accepted','declined','blocked','cancelled')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK(sender_user_id != recipient_user_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX contact_requests_parties
      ON contact_requests(sender_user_id, recipient_user_id, status)
    ''');
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK(type IN ('direct','group')),
        title TEXT,
        avatar TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_message_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE conversation_participants (
        conversation_id TEXT NOT NULL REFERENCES conversations(id)
          ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role TEXT NOT NULL CHECK(role IN ('member','admin','owner')),
        joined_at TEXT NOT NULL,
        PRIMARY KEY(conversation_id, user_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX conversation_participants_user
      ON conversation_participants(user_id, conversation_id)
    ''');
    await db.execute('''
      CREATE TABLE conversation_user_state (
        conversation_id TEXT NOT NULL REFERENCES conversations(id)
          ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_muted INTEGER NOT NULL DEFAULT 0,
        last_read_at TEXT,
        PRIMARY KEY(conversation_id, user_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL REFERENCES conversations(id)
          ON DELETE CASCADE,
        sender_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        sender_device_id TEXT,
        type TEXT NOT NULL CHECK(type IN
          ('text','image','video','document','audio','voice','system')),
        content TEXT NOT NULL,
        reply_to_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        server_received_at TEXT,
        delivery_status TEXT NOT NULL CHECK(delivery_status IN
          ('sending','sent','delivered','read','failed')),
        is_edited INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX messages_conversation_time
      ON messages(conversation_id, created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX messages_outbox
      ON messages(delivery_status, next_retry_at)
      WHERE delivery_status = 'sending'
    ''');
  }

  Future<void> _seed(Database db) async {
    const users = <List<Object?>>[
      [
        '00000000-0000-4000-8000-000000000001',
        'shaheer@example.com',
        'shaheer',
        'Shaheer Malik',
        0xFF315C51,
        'The quieter side of conversation'
      ],
      [
        '00000000-0000-4000-8000-000000000002',
        'alex@example.com',
        'alex',
        'Alex Morgan',
        0xFF315C51,
        'Building calm, useful things.'
      ],
      [
        '00000000-0000-4000-8000-000000000003',
        'sarah@example.com',
        'sarah',
        'Sarah Chen',
        0xFF4E4667,
        'Designer and weekend baker.'
      ],
      [
        '00000000-0000-4000-8000-000000000004',
        'david@example.com',
        'david',
        'David Kim',
        0xFF69523B,
        'Coffee, code, and long walks.'
      ],
      [
        '00000000-0000-4000-8000-000000000005',
        'emma@example.com',
        'emma',
        'Emma Wilson',
        0xFF355D75,
        'Writing about humane technology.'
      ],
      [
        '00000000-0000-4000-8000-000000000006',
        'james@example.com',
        'james',
        'James Patel',
        0xFF655044,
        'Photographer and occasional cook.'
      ],
      [
        '10000000-0000-4000-8000-000000000001',
        'aisha@example.com',
        'aisha',
        'Aisha Khan',
        0xFF315C51,
        'Product designer · Karachi'
      ],
      [
        '10000000-0000-4000-8000-000000000002',
        'maya@example.com',
        'mayac',
        'Maya Chen',
        0xFF4E4667,
        'Designing thoughtful systems.'
      ],
      [
        '10000000-0000-4000-8000-000000000003',
        'omar@example.com',
        'omars',
        'Omar Siddiqui',
        0xFF69523B,
        'Coffee, code, and good conversation.'
      ],
      [
        '10000000-0000-4000-8000-000000000004',
        'sana@example.com',
        'sanaahmed',
        'Sana Ahmed',
        0xFF355D75,
        'Writer and amateur film photographer.'
      ],
      [
        '10000000-0000-4000-8000-000000000005',
        'leila@example.com',
        'leilah',
        'Leila Hassan',
        0xFF655044,
        'Architect and weekend gardener.'
      ],
      [
        '10000000-0000-4000-8000-000000000006',
        'noor@example.com',
        'noorf',
        'Noor Fatima',
        0xFF73544C,
        'Researching humane technology.'
      ],
      [
        '10000000-0000-4000-8000-000000000007',
        'zara@example.com',
        'zarar',
        'Zara Rahman',
        0xFF476245,
        'Illustrator · learning ceramics.'
      ],
      [
        '10000000-0000-4000-8000-000000000008',
        'ibrahim@example.com',
        'ibrahimk',
        'Ibrahim Khan',
        0xFF4C596B,
        'Runner. Reader. Occasional cook.'
      ],
      [
        '10000000-0000-4000-8000-000000000009',
        'daniel@example.com',
        'dross',
        'Daniel Ross',
        0xFF3E6570,
        'Music, maps, and long walks.'
      ],
    ];
    final now = DateTime.now().toUtc();
    for (final user in users) {
      await db.insert('users', {
        'id': user[0],
        'email': user[1],
        'username': user[2],
        'display_name': user[3],
        'avatar_color': user[4],
        'bio': user[5],
        'is_discoverable': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('settings', {'user_id': user[0]});
    }
    await db.insert('app_state', {
      'key': 'active_user_id',
      'value': users.first[0],
    });

    Future<void> seedDirect(
      String id,
      String otherId,
      String incoming,
      String outgoing,
      Duration age,
    ) async {
      final at = now.subtract(age);
      await db.insert('conversations', {
        'id': id,
        'type': 'direct',
        'created_at': at.subtract(const Duration(days: 10)).toIso8601String(),
        'updated_at': at.toIso8601String(),
        'last_message_at': at.toIso8601String(),
      });
      for (final entry in [
        [users.first[0], 'member'],
        [otherId, 'member'],
      ]) {
        await db.insert('conversation_participants', {
          'conversation_id': id,
          'user_id': entry[0],
          'role': entry[1],
          'joined_at': at.toIso8601String(),
        });
        await db.insert('conversation_user_state', {
          'conversation_id': id,
          'user_id': entry[0],
          'last_read_at': otherId == users[6][0] && entry[0] == users.first[0]
              ? at.subtract(const Duration(days: 1)).toIso8601String()
              : at.toIso8601String(),
          'is_pinned':
              otherId == users[6][0] && entry[0] == users.first[0] ? 1 : 0,
        });
      }
      await _seedMessage(db, '$id-1', id, otherId, incoming,
          at.subtract(const Duration(minutes: 4)));
      await _seedMessage(
          db, '$id-2', id, users.first[0] as String, outgoing, at);
    }

    await seedDirect(
        '20000000-0000-4000-8000-000000000001',
        users[6][0] as String,
        'Hey! How is it going?',
        'That sounds perfect — see you there!',
        const Duration(minutes: 18));
    await seedDirect(
        '20000000-0000-4000-8000-000000000002',
        users[8][0] as String,
        'Can you review this later?',
        'Voice message · 0:24',
        const Duration(days: 1));
    await seedDirect(
        '20000000-0000-4000-8000-000000000003',
        users[9][0] as String,
        'Friday still works for me.',
        'See you on Friday!',
        const Duration(days: 3));
    await seedDirect(
        '20000000-0000-4000-8000-000000000004',
        users[10][0] as String,
        'I sent the reference.',
        'Alright, thanks!',
        const Duration(days: 5));

    const groupId = '20000000-0000-4000-8000-000000000005';
    final groupAt = now.subtract(const Duration(hours: 3));
    await db.insert('conversations', {
      'id': groupId,
      'type': 'group',
      'title': 'Design Circle',
      'created_at':
          groupAt.subtract(const Duration(days: 20)).toIso8601String(),
      'updated_at': groupAt.toIso8601String(),
      'last_message_at': groupAt.toIso8601String(),
    });
    for (final entry in [
      [users.first[0], 'owner'],
      [users[6][0], 'member'],
      [users[7][0], 'admin'],
      [users[8][0], 'member'],
    ]) {
      await db.insert('conversation_participants', {
        'conversation_id': groupId,
        'user_id': entry[0],
        'role': entry[1],
        'joined_at': groupAt.toIso8601String(),
      });
      await db.insert('conversation_user_state', {
        'conversation_id': groupId,
        'user_id': entry[0],
        'last_read_at': groupAt.toIso8601String(),
      });
    }
    await _seedMessage(db, '$groupId-1', groupId, users[7][0] as String,
        'I added the latest screens for review', groupAt);

    await _seedRequest(
        db,
        '30000000-0000-4000-8000-000000000001',
        users[7][0] as String,
        users.first[0] as String,
        'I loved the direction you took on the last project. Would be great to connect.',
        now.subtract(const Duration(minutes: 18)));
    await _seedRequest(
        db,
        '30000000-0000-4000-8000-000000000002',
        users[11][0] as String,
        users.first[0] as String,
        'Hi! I saw we share a few interests and wanted to say hello.',
        now.subtract(const Duration(days: 1)));
    await _seedRequest(
        db,
        '30000000-0000-4000-8000-000000000003',
        users.first[0] as String,
        users[12][0] as String,
        'Your illustrations are wonderful. I would love to connect.',
        now.subtract(const Duration(hours: 5)));
  }

  Future<void> _seedMessage(
          DatabaseExecutor db,
          String id,
          String conversationId,
          String senderId,
          String content,
          DateTime at) =>
      db.insert('messages', {
        'id': id,
        'conversation_id': conversationId,
        'sender_user_id': senderId,
        'type': content.startsWith('Voice message') ? 'voice' : 'text',
        'content': content,
        'created_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
        'delivery_status': 'read',
      });

  Future<void> _seedRequest(DatabaseExecutor db, String id, String senderId,
          String recipientId, String message, DateTime at) =>
      db.insert('contact_requests', {
        'id': id,
        'sender_user_id': senderId,
        'recipient_user_id': recipientId,
        'introductory_message': message,
        'status': 'pending',
        'created_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      });
}
