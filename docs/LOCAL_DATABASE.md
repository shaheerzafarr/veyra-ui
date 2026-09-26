# Local database

Veyra Phase 2 uses SQLite through `sqflite`. The database is opened by
`VeyraDatabase`, currently at schema version 1. It is created once, seeded in
the `onCreate` callback, and opened without reseeding on later launches.

## Schema

| Table | Purpose |
| --- | --- |
| `users` | Private account data plus public profile fields. UUID `id` is the primary key. |
| `app_state` | Device-local values, currently the active development account. |
| `settings` | One persistent preference row per user. |
| `contact_requests` | First-contact message and its state. |
| `conversations` | Direct and group conversation metadata. |
| `conversation_participants` | Many-to-many membership with member/admin/owner role. |
| `conversation_user_state` | Per-user pinned, muted, unread/read state. |
| `messages` | Paginated message history and simulated local delivery state. |

Foreign keys are enabled. Usernames are protected by a unique index on
`lower(username)`, while user IDs and message IDs are UUIDs. Message history is
indexed by `(conversation_id, created_at DESC)`. Widgets never issue SQL.

## Migrations

`VeyraDatabase.schemaVersion` controls versioning. Future schema changes must
be additive, sequential branches in `_migrate`; the database must not be
deleted to apply a migration.

## Future integration

Repository interfaces are the boundary above SQLite. A later encrypted local
store or remote synchronization repository can implement the same contracts.
The current database stores local plaintext only; it contains no encryption
keys and makes no encryption claim.

