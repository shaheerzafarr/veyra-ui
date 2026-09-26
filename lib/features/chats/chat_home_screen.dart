import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/entities.dart';
import '../../core/models/public_profile.dart';
import '../../core/state/veyra_controller.dart';
import '../../core/theme/app_theme.dart';
import '../app_ui/veyra_feature_screens.dart';
import '../discovery/discover_people_screen.dart';

class ChatHomeScreen extends ConsumerStatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  ConsumerState<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends ConsumerState<ChatHomeScreen> {
  final _search = TextEditingController();
  String _filter = 'All';

  static const _chats = [
    _ChatPreview('Aisha Khan', 'That sounds perfect — see you there!', '10:42',
        0xFF315C51,
        unread: 2, pinned: true, online: true),
    _ChatPreview('Design Circle', 'Maya: I added the latest screens for review',
        '09:18', 0xFF4E4667,
        group: true),
    _ChatPreview(
        'Omar Siddiqui', 'Voice message · 0:24', 'Yesterday', 0xFF69523B,
        unread: 1, voice: true),
    _ChatPreview('Sana Ahmed', 'See you on Friday!', 'Monday', 0xFF355D75,
        online: true),
    _ChatPreview('Leila Hassan', 'Alright, thanks!', 'Sunday', 0xFF655044,
        muted: true),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veyraControllerProvider);
    final chats = <_ChatPreview>[..._chats]
      ..clear()
      ..addAll(state.conversationSummaries.map(_ChatPreview.fromSummary));
    final query = _search.text.trim().toLowerCase();
    final visible = chats.where((chat) {
      final filterMatch = switch (_filter) {
        'Unread' => chat.unread > 0,
        'Groups' => chat.group,
        'Favorites' => chat.pinned,
        _ => true,
      };
      return filterMatch &&
          (query.isEmpty ||
              chat.name.toLowerCase().contains(query) ||
              chat.preview.toLowerCase().contains(query));
    }).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            _InboxHeader(
              onDiscover: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const DiscoverPeopleScreen()),
              ),
              onNewChat: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const NewChatScreen()),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search conversations, people…',
                prefixIcon: Icon(Icons.search_rounded, size: 27),
                suffixIcon: Icon(Icons.tune_rounded, size: 22),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filterIcons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final entry = _filterIcons.entries.elementAt(index);
                  final selected = _filter == entry.key;
                  return ChoiceChip(
                    showCheckmark: false,
                    selected: selected,
                    avatar: Icon(
                      selected ? Icons.check_rounded : entry.value,
                      size: 18,
                      color: selected ? VeyraColors.text : VeyraColors.muted,
                    ),
                    label: Text(entry.key),
                    labelStyle: TextStyle(
                      color: selected ? VeyraColors.text : VeyraColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onSelected: (_) => setState(() => _filter = entry.key),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            const _ConversationBanner(),
            const SizedBox(height: 14),
            _RequestsPanel(
              incomingCount: state.incomingRequests.length,
              outgoingCount: state.outgoingRequests.length,
              onIncoming: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const VeyraRequestsScreen()),
              ),
              onOutgoing: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const OutgoingRequestsScreen()),
              ),
            ),
            const SizedBox(height: 24),
            const _RecentHeading(),
            const SizedBox(height: 10),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('No conversations match your search.',
                      style: TextStyle(color: VeyraColors.muted)),
                ),
              ),
            ...visible.map((chat) => _ChatRow(chat: chat)),
          ],
        ),
      ),
    );
  }
}

const _filterIcons = <String, IconData>{
  'All': Icons.check_rounded,
  'Unread': Icons.mark_chat_unread_outlined,
  'Groups': Icons.groups_2_outlined,
  'Favorites': Icons.star_border_rounded,
};

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({required this.onDiscover, required this.onNewChat});

  final VoidCallback onDiscover;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Veyra',
                        style: TextStyle(
                            fontSize: 34,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.8)),
                    Padding(
                      padding: EdgeInsets.only(left: 6, top: 1),
                      child: CircleAvatar(
                          radius: 5, backgroundColor: VeyraColors.emerald),
                    ),
                  ],
                ),
                SizedBox(height: 7),
                Text('Connect · Chat · Stay Close',
                    style: TextStyle(color: VeyraColors.muted, fontSize: 13)),
              ],
            ),
          ),
          _HeaderAction(
              tooltip: 'Discover people',
              icon: Icons.person_search_outlined,
              onPressed: onDiscover),
          const SizedBox(width: 10),
          _HeaderAction(
              tooltip: 'New chat',
              icon: Icons.add_rounded,
              accent: true,
              onPressed: onNewChat),
        ],
      );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction(
      {required this.tooltip,
      required this.icon,
      required this.onPressed,
      this.accent = false});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 27,
        color: accent ? VeyraColors.emeraldBright : VeyraColors.text,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(54),
          backgroundColor: accent
              ? VeyraColors.emerald.withValues(alpha: .12)
              : VeyraColors.surface,
          side: BorderSide(
              color: accent
                  ? VeyraColors.emerald.withValues(alpha: .14)
                  : VeyraColors.border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
}

class _ConversationBanner extends StatelessWidget {
  const _ConversationBanner();

  @override
  Widget build(BuildContext context) => Container(
        height: 108,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VeyraColors.border),
          gradient: LinearGradient(colors: [
            VeyraColors.surface,
            VeyraColors.emeraldDeep.withValues(alpha: .16),
          ]),
        ),
        child: const Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your conversations\nin one place',
                        style: TextStyle(
                            fontSize: 18,
                            height: 1.18,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 8),
                    Text('Messages, groups and more',
                        style:
                            TextStyle(color: VeyraColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            SizedBox(width: 104, child: _BubbleArtwork()),
          ],
        ),
      );
}

class _BubbleArtwork extends StatelessWidget {
  const _BubbleArtwork();

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned(
            right: 2,
            top: 6,
            child: _MessageBubble(
                color: VeyraColors.emerald, alignment: Alignment.bottomRight),
          ),
          Positioned(
            left: 2,
            bottom: 4,
            child: _MessageBubble(
              color: VeyraColors.elevated,
              alignment: Alignment.bottomLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: CircleAvatar(
                        radius: 2.5, backgroundColor: VeyraColors.muted),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.color, required this.alignment, this.child});

  final Color color;
  final Alignment alignment;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
        width: 62,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft:
                Radius.circular(alignment == Alignment.bottomLeft ? 5 : 20),
            bottomRight:
                Radius.circular(alignment == Alignment.bottomRight ? 5 : 20),
          ),
        ),
        child: child,
      );
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel({
    required this.onIncoming,
    required this.onOutgoing,
    required this.incomingCount,
    required this.outgoingCount,
  });

  final VoidCallback onIncoming;
  final VoidCallback onOutgoing;
  final int incomingCount;
  final int outgoingCount;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: VeyraColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VeyraColors.border),
        ),
        child: Column(children: [
          _RequestRow(
              icon: Icons.markunread_mailbox_outlined,
              label: 'Message requests',
              detail: incomingCount == 1
                  ? '1 new introduction'
                  : '$incomingCount new introductions',
              count: incomingCount == 0 ? null : incomingCount,
              showPeople: true,
              onTap: onIncoming),
          const Divider(height: 1, indent: 72, endIndent: 18),
          _RequestRow(
              icon: Icons.schedule_rounded,
              label: 'Sent requests',
              detail: outgoingCount == 1
                  ? '1 waiting for a reply'
                  : '$outgoingCount waiting for a reply',
              onTap: onOutgoing),
        ]),
      );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow(
      {required this.icon,
      required this.label,
      required this.detail,
      required this.onTap,
      this.count,
      this.showPeople = false});

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final int? count;
  final bool showPeople;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: VeyraColors.emerald.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: VeyraColors.emerald, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(detail,
                      style: const TextStyle(
                          color: VeyraColors.muted, fontSize: 12)),
                ],
              ),
            ),
            if (showPeople) const _MiniPeople(),
            if (count != null) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: VeyraColors.emerald,
                child: Text('$count',
                    style: const TextStyle(
                        color: VeyraColors.background,
                        fontWeight: FontWeight.w800)),
              ),
            ],
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: VeyraColors.muted, size: 22),
          ]),
        ),
      );
}

class _MiniPeople extends StatelessWidget {
  const _MiniPeople();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 52,
        height: 32,
        child: Stack(children: [
          Positioned(
            left: 0,
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Color(0xFF315C51),
              child: Text('A', style: TextStyle(fontSize: 11)),
            ),
          ),
          Positioned(
            left: 20,
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Color(0xFF69523B),
              child: Text('S', style: TextStyle(fontSize: 11)),
            ),
          ),
        ]),
      );
}

class _RecentHeading extends StatelessWidget {
  const _RecentHeading();

  @override
  Widget build(BuildContext context) => const Row(children: [
        Expanded(
          child: Text('RECENT CONVERSATIONS',
              style: TextStyle(
                  color: VeyraColors.muted,
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800)),
        ),
        Text('View all',
            style: TextStyle(
                color: VeyraColors.emerald,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        SizedBox(width: 2),
        Icon(Icons.chevron_right_rounded, color: VeyraColors.emerald, size: 18),
      ]);
}

class _ChatPreview {
  const _ChatPreview(this.name, this.preview, this.time, this.color,
      {this.conversationId,
      this.unread = 0,
      this.pinned = false,
      this.group = false,
      this.online = false,
      this.muted = false,
      this.voice = false});

  final String? conversationId;
  final String name, preview, time;
  final int color, unread;
  final bool pinned, group, online, muted, voice;

  factory _ChatPreview.fromSummary(ConversationSummary summary) {
    final local = summary.conversation.lastMessageAt?.toLocal();
    final age = local == null ? null : DateTime.now().difference(local).inDays;
    final time = local == null
        ? ''
        : age == 0
            ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
            : age == 1
                ? 'Yesterday'
                : '${local.day}/${local.month}';
    final preview = summary.lastMessage ?? 'No messages yet';
    return _ChatPreview(
      summary.displayName,
      preview,
      time,
      summary.avatarColor,
      conversationId: summary.conversation.id,
      unread: summary.unreadCount,
      pinned: summary.isPinned,
      group: summary.conversation.type == ConversationType.group,
      muted: summary.isMuted,
      voice: preview.startsWith('Voice message'),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat});
  final _ChatPreview chat;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: VeyraColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: VeyraColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => VeyraConversationScreen(
                  name: chat.name,
                  group: chat.group,
                  conversationId: chat.conversationId,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(children: [
                VeyraAvatar(
                    name: chat.name,
                    color: chat.color,
                    radius: 27,
                    group: chat.group,
                    online: chat.online),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(chat.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                        if (chat.pinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 7),
                            child: Icon(Icons.push_pin_rounded,
                                size: 15, color: VeyraColors.muted),
                          ),
                        if (chat.muted)
                          const Padding(
                            padding: EdgeInsets.only(left: 7),
                            child: Icon(Icons.notifications_off_rounded,
                                size: 15, color: VeyraColors.muted),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (chat.voice) ...[
                          const Icon(Icons.mic_rounded,
                              size: 17, color: VeyraColors.muted),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(chat.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: VeyraColors.muted, fontSize: 13)),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(chat.time,
                        style: const TextStyle(
                            color: VeyraColors.muted, fontSize: 11)),
                    if (chat.unread > 0) ...[
                      const SizedBox(height: 7),
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: VeyraColors.emerald,
                        child: Text('${chat.unread}',
                            style: const TextStyle(
                                color: VeyraColors.background,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                    ] else
                      const SizedBox(height: 30),
                  ],
                ),
              ]),
            ),
          ),
        ),
      );
}

class NewChatScreen extends ConsumerWidget {
  const NewChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veyraControllerProvider);
    final profiles = state.allUsers
        .where((user) => user.id != state.activeUser.id && user.isDiscoverable)
        .map((user) => PublicProfile.fromUser(
              user,
              isContact: state.conversationWith(user.id) != null,
              hasPendingRequest: state.outgoingRequests
                  .any((request) => request.otherUser.id == user.id),
            ));
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            readOnly: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const DiscoverPeopleScreen()),
            ),
            decoration: const InputDecoration(
                hintText: 'Search people by name or @username',
                prefixIcon: Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF1B3F35),
              child: Icon(Icons.group_add_rounded, color: VeyraColors.emerald),
            ),
            title: const Text('New group',
                style: TextStyle(color: VeyraColors.emerald)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const VeyraCreateGroupScreen()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text('PEOPLE ON VEYRA',
                style: TextStyle(
                    color: VeyraColors.muted,
                    fontSize: 11,
                    letterSpacing: 1.1)),
          ),
          ...profiles.map((profile) => PublicProfileTile(profile: profile)),
        ],
      ),
    );
  }
}

class OutgoingRequestsScreen extends ConsumerWidget {
  const OutgoingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veyraControllerProvider);
    final pending = state.outgoingRequests;
    return Scaffold(
      appBar: AppBar(title: const Text('Sent requests')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
                'One introduction can be sent until your request is accepted.',
                style: TextStyle(color: VeyraColors.muted)),
          ),
          ...pending.map((view) {
            final profile = PublicProfile.fromUser(
              view.otherUser,
              hasPendingRequest: true,
            );
            return Card(
              color: VeyraColors.surface,
              child: ListTile(
                leading: ProfileAvatar(profile: profile),
                title: Text(profile.displayName),
                subtitle: Text('@${profile.username} · Request pending'),
                trailing: IconButton(
                  tooltip: 'Cancel request',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => ref
                      .read(veyraControllerProvider)
                      .cancelRequest(view.request.id),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => PublicProfileScreen(profile: profile)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class VeyraAvatar extends StatelessWidget {
  const VeyraAvatar(
      {required this.name,
      required this.color,
      this.radius = 24,
      this.online = false,
      this.group = false,
      super.key});

  final String name;
  final int color;
  final double radius;
  final bool online;
  final bool group;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: radius * 2 + 4,
        height: radius * 2 + 4,
        child: Stack(children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: Color(color),
            child: group
                ? const Icon(Icons.groups_rounded, color: VeyraColors.text)
                : Text(name[0],
                    style: TextStyle(
                        color: VeyraColors.text,
                        fontSize: radius * .74,
                        fontWeight: FontWeight.w700)),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: VeyraColors.emerald,
                  shape: BoxShape.circle,
                  border: Border.all(color: VeyraColors.background, width: 2),
                ),
              ),
            ),
        ]),
      );
}
