# Data models and architecture

The Phase 2 data path is:

```text
Flutter UI
  -> VeyraController / Riverpod
    -> repository interfaces
      -> LocalVeyraRepository
        -> VeyraDatabase / SQLite
```

Core entities live in `lib/core/models/entities.dart`:

- `AppUser`: immutable UUID identity, private email, case-insensitive unique
  username, public display name/avatar/bio, and discoverability.
- `Conversation`: direct or group metadata. Direct presentation is derived
  from participants rather than copied into the conversation.
- `ChatMessage`: UUID identity, sender/conversation references, content type,
  reply reference, timestamps, edit/delete flags, and local delivery state.
- `ContactRequest`: sender, recipient, single introduction, status, timestamps.
- `AppSettings`: persistent device-local preferences per development user.

`ConversationSummary` and `ContactRequestView` are read models used by the UI;
they do not duplicate persisted entities. Messages are loaded per conversation
with `limit` and `offset`, so long histories do not require loading the entire
message table.

The debug-only account switcher is guarded by `kDebugMode` and persists its
selected user in `app_state`. Seeded accounts include Shaheer, Alex, Sarah,
David, Emma, and James. It is not a production authentication system.

Future backend work should add remote repository implementations and a sync
coordinator. Transport ciphertext/envelopes should remain separate from the
local plaintext model, and private keys must not be stored in ordinary tables.

