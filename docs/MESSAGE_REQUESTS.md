# Message requests

Message requests enforce the first-contact boundary locally.

```text
new -> pending -> accepted
               -> declined
               -> blocked
               -> cancelled (sender only)
```

- A sender may create one pending introduction for a user with whom no direct
  conversation or non-cancelled request exists.
- While pending, a normal conversation does not exist, so additional messages,
  attachments, and calls are unavailable.
- Only the recipient may accept, decline, or block.
- Only the sender may cancel.
- Accepting runs in one transaction: the request becomes accepted, a direct
  conversation and both participants are created, and the introduction becomes
  the first message.
- Declining creates no conversation.
- Blocking prevents later local contact attempts in either direction.

The development account switcher in Settings can exercise the complete flow:
switch to Alex, send Sarah an introduction, switch to Sarah and accept it, then
switch back to Alex and continue in the persisted conversation.

