
# Veyra Development Instructions

## Project
Veyra is a private, invitation-only messaging application
designed initially for 100 registered users.

## Current phase
Phase 3: FastAPI authentication, user directory, message requests, and
device registration.

The Flutter application remains in this repository. The backend lives in the
sibling `veyra-backend` directory and uses FastAPI, PostgreSQL, SQLAlchemy 2.x,
Alembic, and Pydantic.

Do not implement real-time messaging, end-to-end encryption, WebRTC, push
notifications, media uploads, presence, or cloud-specific services during this
phase.

## Technology
- Flutter and Dart
- Material 3
- Riverpod
- GoRouter
- Reusable, feature-based components
- Realistic mock data and simulated interactions

## Visual design
Use design/veyra-reference.png as the primary visual reference.

Colors:
- Background: #0B0F10
- Primary surface: #151B1C
- Elevated surface: #202829
- Emerald accent: #34D399
- Primary text: #F3F6F5
- Secondary text: #94A3A0

Maintain a premium, minimalist dark theme.

## Account system
Every user has:
- A private email address used for login
- A unique, case-insensitive username
- A non-unique display name
- A profile picture
- An optional bio

Email addresses must not appear in public search results.

## User discovery
Users can search for other registered, discoverable users
by display name or username.

Search results must show:
- Profile picture
- Display name
- Unique username
- Optional bio

## Message requests
A user can send one introductory message to someone
they have never contacted.

The recipient can:
- Accept
- Decline
- Block

Until acceptance, the sender cannot send additional
messages, attachments or calls.

After acceptance, the request becomes a normal conversation.

Implement this entire workflow using mock local state.

## Required screens
- Splash and onboarding
- Login and registration
- Profile setup
- Chat list
- Individual chat
- Group chat
- Discover people
- Public user profile
- Incoming message requests
- Outgoing pending requests
- Call history
- Voice and video call mockups
- Group creation and management
- Attachment interfaces
- Settings and all relevant subpages

## Development rules
1. Implement one feature at a time.
2. Follow the existing architecture and design system.
3. Reuse widgets instead of duplicating code.
4. Do not modify unrelated files.
5. Keep every completed screen navigable.
6. Use local mock data and meaningful simulated interactions.
7. Do not present simulated encryption as real security.
8. Run Flutter analysis and relevant tests.
9. Report changed files, test results and blockers concisely.
