import 'package:flutter/material.dart';

import '../../core/mock_data/mock_profiles.dart';
import '../../core/theme/app_theme.dart';
import '../app_ui/veyra_feature_screens.dart';
import '../discovery/discover_people_screen.dart';

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final _search = TextEditingController();
  String _filter = 'All';

  static const _chats = [
    _ChatPreview('Aisha Khan', 'That sounds perfect — see you then!', '10:42',
        0xFF315C51,
        unread: 2, pinned: true, online: true),
    _ChatPreview('Design Circle', 'Maya: I added the latest screens', '09:18',
        0xFF4E4667,
        group: true),
    _ChatPreview(
        'Omar Siddiqui', 'Voice message · 0:24', 'Yesterday', 0xFF69523B,
        unread: 1),
    _ChatPreview('Sana Ahmed', 'See you on Friday!', 'Monday', 0xFF355D75,
        online: true),
    _ChatPreview(
        'Leila Hassan', 'Thanks for sharing the photos', 'Sunday', 0xFF655044,
        muted: true),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _chats.where((chat) {
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
      appBar: AppBar(
        title: const Text('Veyra'),
        actions: [
          IconButton(
            tooltip: 'Discover people',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const DiscoverPeopleScreen())),
            icon: const Icon(Icons.person_search_outlined),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const NewChatScreen())),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search conversations…',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: ['All', 'Unread', 'Groups', 'Favorites']
                  .map((label) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == label,
                          onSelected: (_) => setState(() => _filter = label),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              children: [
                _InboxEntry(
                  icon: Icons.markunread_mailbox_outlined,
                  label: 'Message requests',
                  detail: '2 new introductions',
                  count: '2',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const VeyraRequestsScreen())),
                ),
                _InboxEntry(
                  icon: Icons.schedule_rounded,
                  label: 'Sent requests',
                  detail: 'Waiting for a reply',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const OutgoingRequestsScreen())),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 15, 8, 6),
                  child: Text('RECENT CONVERSATIONS',
                      style: TextStyle(
                          color: VeyraColors.muted,
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700)),
                ),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: Text('No conversations match your search.',
                            style: TextStyle(color: VeyraColors.muted))),
                  ),
                ...visible.map((chat) => _ChatRow(chat: chat)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New chat')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              readOnly: true,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const DiscoverPeopleScreen())),
              decoration: const InputDecoration(
                  hintText: 'Search people by name or @username',
                  prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1B3F35),
                  child: Icon(Icons.group_add_rounded,
                      color: VeyraColors.emerald)),
              title: const Text('New group',
                  style: TextStyle(color: VeyraColors.emerald)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const VeyraCreateGroupScreen())),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text('PEOPLE ON VEYRA',
                  style: TextStyle(
                      color: VeyraColors.muted,
                      fontSize: 11,
                      letterSpacing: 1.1)),
            ),
            ...discoverableProfiles
                .map((profile) => PublicProfileTile(profile: profile)),
          ],
        ),
      );
}

class OutgoingRequestsScreen extends StatelessWidget {
  const OutgoingRequestsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final pending =
        discoverableProfiles.where((person) => person.hasPendingRequest);
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
          ...pending.map((profile) => Card(
                color: VeyraColors.surface,
                child: ListTile(
                  leading: ProfileAvatar(profile: profile),
                  title: Text(profile.displayName),
                  subtitle: Text('@${profile.username} · Request pending'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              PublicProfileScreen(profile: profile))),
                ),
              )),
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
                        fontSize: radius * .84,
                        fontWeight: FontWeight.w700)),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: 11,
                height: 11,
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

class _ChatPreview {
  const _ChatPreview(this.name, this.preview, this.time, this.color,
      {this.unread = 0,
      this.pinned = false,
      this.group = false,
      this.online = false,
      this.muted = false});
  final String name, preview, time;
  final int color, unread;
  final bool pinned, group, online, muted;
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat});
  final _ChatPreview chat;
  @override
  Widget build(BuildContext context) => ListTile(
        minVerticalPadding: 7,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: VeyraAvatar(
            name: chat.name,
            color: chat.color,
            group: chat.group,
            online: chat.online),
        title: Row(children: [
          Flexible(
              child: Text(chat.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700))),
          if (chat.pinned)
            const Padding(
              padding: EdgeInsets.only(left: 5),
              child: Icon(Icons.push_pin_rounded,
                  size: 12, color: VeyraColors.muted),
            ),
          if (chat.muted)
            const Padding(
              padding: EdgeInsets.only(left: 5),
              child: Icon(Icons.notifications_off_rounded,
                  size: 12, color: VeyraColors.muted),
            ),
        ]),
        subtitle: Text(chat.preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: VeyraColors.muted, fontSize: 12)),
        trailing: SizedBox(
            width: 76,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(chat.time,
                    style: const TextStyle(
                        color: VeyraColors.muted, fontSize: 11)),
                if (chat.unread > 0) ...[
                  const SizedBox(height: 5),
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 19, minHeight: 19),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: const BoxDecoration(
                        color: VeyraColors.emerald, shape: BoxShape.circle),
                    child: Text('${chat.unread}',
                        style: const TextStyle(
                            color: VeyraColors.background,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            )),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => VeyraConversationScreen(
                    name: chat.name, group: chat.group))),
      );
}

class _InboxEntry extends StatelessWidget {
  const _InboxEntry(
      {required this.icon,
      required this.label,
      required this.detail,
      required this.onTap,
      this.count});
  final IconData icon;
  final String label, detail;
  final String? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          tileColor: VeyraColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: VeyraColors.border),
          ),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1B3F35),
            child: Icon(icon, color: VeyraColors.emerald, size: 21),
          ),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
          trailing: count == null
              ? const Icon(Icons.chevron_right_rounded,
                  color: VeyraColors.muted)
              : CircleAvatar(
                  radius: 11,
                  backgroundColor: VeyraColors.emerald,
                  child: Text(count!,
                      style: const TextStyle(
                          color: VeyraColors.background,
                          fontSize: 11,
                          fontWeight: FontWeight.w700))),
          onTap: onTap,
        ),
      );
}
