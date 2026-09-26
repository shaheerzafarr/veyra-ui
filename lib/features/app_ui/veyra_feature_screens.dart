import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/entities.dart';
import '../../core/models/public_profile.dart';
import '../../core/state/veyra_controller.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/discover_people_screen.dart';
import '../chats/conversation_extras.dart';
import '../settings/settings_pages.dart';

class VeyraRequestsScreen extends ConsumerWidget {
  const VeyraRequestsScreen({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref,
      ContactRequestView view, String action) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('$action ${view.otherUser.displayName}?'),
              content: Text(action == 'Accept'
                  ? 'This will add the conversation to your chats.'
                  : 'This request will be removed from your inbox.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(action))
              ],
            ));
    if (confirmed == true && context.mounted) {
      final controller = ref.read(veyraControllerProvider);
      if (action == 'Accept') {
        await controller.acceptRequest(view.request.id);
      } else if (action == 'Decline') {
        await controller.declineRequest(view.request.id);
      } else {
        await controller.blockRequest(view.request.id);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'Accept'
              ? '${view.otherUser.displayName} was added to Chats.'
              : 'Request $action.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(veyraControllerProvider).incomingRequests;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Message requests',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: views.isEmpty
          ? const _EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No message requests',
              subtitle: 'Requests from new people will appear here.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: views.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final view = views[index];
                final request = _Request(
                  view.otherUser.displayName,
                  '@${view.otherUser.username}',
                  view.request.introductoryMessage,
                  _relativeTime(view.request.createdAt),
                  view.otherUser.avatarColor,
                );
                return _RequestCard(
                    request: request,
                    onAccept: () => _act(context, ref, view, 'Accept'),
                    onDecline: () => _act(context, ref, view, 'Decline'),
                    onBlock: () => _act(context, ref, view, 'Block'));
              },
            ),
    );
  }
}

class VeyraIntroComposerScreen extends ConsumerStatefulWidget {
  const VeyraIntroComposerScreen({required this.profile, super.key});
  final PublicProfile profile;
  @override
  ConsumerState<VeyraIntroComposerScreen> createState() =>
      _VeyraIntroComposerScreenState();
}

class _VeyraIntroComposerScreenState
    extends ConsumerState<VeyraIntroComposerScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('New message',
                style: TextStyle(fontWeight: FontWeight.w700))),
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        ProfileAvatar(profile: widget.profile),
                        const SizedBox(width: 12),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.profile.displayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text('@${widget.profile.username}',
                                  style: const TextStyle(
                                      color: VeyraColors.emerald))
                            ])
                      ]),
                      const SizedBox(height: 28),
                      const Text('INTRODUCE YOURSELF',
                          style: TextStyle(
                              color: VeyraColors.emerald,
                              letterSpacing: 1.2,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      const Text(
                          'You can send one message request. They can accept, decline, or block it before a conversation begins.',
                          style:
                              TextStyle(color: VeyraColors.muted, height: 1.4)),
                      const SizedBox(height: 22),
                      TextField(
                          controller: _controller,
                          maxLines: 5,
                          maxLength: 500,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              hintText: 'Write a thoughtful introduction…',
                              alignLabelWithHint: true)),
                      const Spacer(),
                      FilledButton.icon(
                          onPressed: _controller.text.trim().isEmpty
                              ? null
                              : () async {
                                  try {
                                    final request = await ref
                                        .read(veyraControllerProvider)
                                        .sendRequest(widget.profile.id,
                                            _controller.text.trim());
                                    if (!context.mounted) return;
                                    Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute<void>(
                                            builder: (_) =>
                                                VeyraConversationScreen(
                                                    name: widget
                                                        .profile.displayName,
                                                    pending: true,
                                                    pendingRequestId:
                                                        request.id)));
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$error')),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Send request'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56))),
                    ]))),
      );
}

class VeyraConversationScreen extends ConsumerStatefulWidget {
  const VeyraConversationScreen(
      {required this.name,
      this.group = false,
      this.pending = false,
      this.conversationId,
      this.pendingRequestId,
      super.key});
  final String name;
  final bool group;
  final bool pending;
  final String? conversationId;
  final String? pendingRequestId;
  @override
  ConsumerState<VeyraConversationScreen> createState() =>
      _VeyraConversationScreenState();
}

class _VeyraConversationScreenState
    extends ConsumerState<VeyraConversationScreen> {
  final _composer = TextEditingController();
  final _fallbackMessages = <_Message>[
    const _Message('Hey! How is it going?', false, '9:12 PM'),
    const _Message(
        'It’s going great! I just finished the design.', true, '9:15 PM'),
    const _Message(
        'That looks amazing. Can you send me the file?', false, '9:16 PM')
  ];

  @override
  void initState() {
    super.initState();
    final id = widget.conversationId;
    if (id != null) {
      Future<void>.microtask(
          () => ref.read(veyraControllerProvider).loadMessages(id));
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final id = widget.conversationId;
    if (id == null) {
      setState(() {
        _fallbackMessages.add(_Message(text, true, 'Now'));
        _composer.clear();
      });
      return;
    }
    _composer.clear();
    await ref.read(veyraControllerProvider).sendMessage(id, text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(veyraControllerProvider);
    final stored = widget.conversationId == null
        ? const <ChatMessage>[]
        : controller.messagesFor(widget.conversationId!);
    final messages = widget.conversationId == null
        ? _fallbackMessages
        : stored
            .map((message) => _Message(
                  message.isDeleted ? 'Message deleted' : message.content,
                  message.senderUserId == controller.activeUser.id,
                  _messageTime(message.createdAt),
                  id: message.id,
                  deliveryStatus: message.deliveryStatus,
                  isDeleted: message.isDeleted,
                  createdAt: message.createdAt,
                ))
            .toList();
    return Scaffold(
      appBar: AppBar(
          toolbarHeight: 82,
          leadingWidth: 46,
          titleSpacing: 0,
          title: InkWell(
              onTap: widget.group
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => GroupDetailsScreen(
                              name: widget.name,
                              conversationId: widget.conversationId)))
                  : null,
              child: Row(children: [
                Stack(children: [
                  CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF315C51),
                      child: Text(widget.name[0],
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600))),
                  if (!widget.group && !widget.pending)
                    Positioned(
                        right: 0,
                        bottom: 1,
                        child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                                color: VeyraColors.emerald,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: VeyraColors.background, width: 2))))
                ]),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(
                          widget.pending
                              ? 'Request pending'
                              : widget.group
                                  ? '5 members'
                                  : 'Online',
                          style: TextStyle(
                              fontSize: 13,
                              color: widget.pending
                                  ? VeyraColors.muted
                                  : VeyraColors.emerald))
                    ]))
              ])),
          actions: [
            IconButton(
                onPressed: widget.pending
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => VeyraCallScreen(
                                name: widget.name, video: true))),
                icon: const Icon(Icons.videocam_outlined, size: 27)),
            IconButton(
                onPressed: widget.pending
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                VeyraCallScreen(name: widget.name))),
                icon: const Icon(Icons.phone_outlined, size: 25)),
            IconButton(
                onPressed: () => _showChatMenu(context),
                icon: const Icon(Icons.more_vert_rounded, size: 25))
          ]),
      body: Column(children: [
        if (widget.pending)
          _PendingBanner(onCancel: () async {
            final requestId = widget.pendingRequestId;
            if (requestId != null) {
              await ref.read(veyraControllerProvider).cancelRequest(requestId);
            }
            if (context.mounted) Navigator.pop(context);
          }),
        Expanded(
            child: Stack(children: [
          const Positioned.fill(child: _ChatWallpaper()),
          ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final showDate = index == 0 ||
                    !_sameDay(messages[index - 1].createdAt, message.createdAt);
                return Column(children: [
                  if (showDate)
                    Center(
                        child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 17, vertical: 8),
                            decoration: BoxDecoration(
                                color:
                                    VeyraColors.elevated.withValues(alpha: .92),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: VeyraColors.border)),
                            child: Text(_dateLabel(message.createdAt),
                                style: const TextStyle(
                                    color: VeyraColors.text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)))),
                  _MessageBubble(
                    message: message,
                    onDelete: message.id == null ||
                            widget.conversationId == null
                        ? null
                        : () => ref
                            .read(veyraControllerProvider)
                            .deleteMessage(widget.conversationId!, message.id!),
                  ),
                ]);
              })
        ])),
        if (!widget.pending)
          _Composer(
              controller: _composer,
              onSend: _send,
              onVoice: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const VoiceRecorderScreen())),
              onAttach: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: VeyraColors.surface,
                  builder: (_) => const VeyraAttachmentPicker())),
      ]),
    );
  }

  void _showChatMenu(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: VeyraColors.surface,
      builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.search_rounded),
                title: const Text('Search conversation'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              ConversationSearchScreen(name: widget.name)));
                }),
            ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Chat information'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => widget.group
                              ? GroupDetailsScreen(
                                  name: widget.name,
                                  conversationId: widget.conversationId)
                              : const GroupMediaScreen()));
                }),
            ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(widget.conversationId != null &&
                        ref
                                .read(veyraControllerProvider)
                                .conversationById(widget.conversationId!)
                                ?.isMuted ==
                            true
                    ? 'Unmute notifications'
                    : 'Mute notifications'),
                onTap: () async {
                  final id = widget.conversationId;
                  if (id != null) {
                    await ref
                        .read(veyraControllerProvider)
                        .toggleConversationMuted(id);
                  }
                  if (context.mounted) Navigator.pop(context);
                })
          ])));
}

class VeyraGroupsScreen extends ConsumerWidget {
  const VeyraGroupsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref
        .watch(veyraControllerProvider)
        .conversationSummaries
        .where(
            (summary) => summary.conversation.type == ConversationType.group);
    return Scaffold(
        appBar: AppBar(
            title: const Text('Groups',
                style: TextStyle(fontWeight: FontWeight.w700))),
        floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const VeyraCreateGroupScreen())),
            child: const Icon(Icons.group_add_rounded)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ...groups.map((group) => ListTile(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => VeyraConversationScreen(
                          name: group.displayName,
                          conversationId: group.conversation.id,
                          group: true))),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              tileColor: VeyraColors.surface,
              leading: CircleAvatar(
                  backgroundColor: Color(group.avatarColor),
                  child: const Icon(Icons.groups_rounded)),
              title: Text(group.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(group.lastMessage ?? 'No messages yet'),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: VeyraColors.muted)))
        ]));
  }
}

class VeyraCreateGroupScreen extends ConsumerStatefulWidget {
  const VeyraCreateGroupScreen({super.key});
  @override
  ConsumerState<VeyraCreateGroupScreen> createState() =>
      _VeyraCreateGroupScreenState();
}

class _VeyraCreateGroupScreenState
    extends ConsumerState<VeyraCreateGroupScreen> {
  final _name = TextEditingController();
  final _members = <String>{};
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veyraControllerProvider);
    final candidates = state.allUsers
        .where((user) => user.id != state.activeUser.id && user.isDiscoverable);
    return Scaffold(
        appBar: AppBar(title: const Text('Create group')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const CircleAvatar(
              radius: 34,
              backgroundColor: VeyraColors.elevated,
              child:
                  Icon(Icons.add_a_photo_outlined, color: VeyraColors.emerald)),
          const SizedBox(height: 22),
          TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Group name')),
          const SizedBox(height: 22),
          const Text('ADD MEMBERS',
              style: TextStyle(
                  color: VeyraColors.muted, fontSize: 12, letterSpacing: 1.2)),
          ...candidates.map((member) => CheckboxListTile(
              value: _members.contains(member.id),
              onChanged: (value) => setState(() => value == true
                  ? _members.add(member.id)
                  : _members.remove(member.id)),
              title: Text(member.displayName),
              subtitle: Text('@${member.username}'),
              controlAffinity: ListTileControlAffinity.trailing)),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: _name.text.trim().isEmpty || _members.isEmpty
                  ? null
                  : () async {
                      final name = _name.text.trim();
                      final id = await ref
                          .read(veyraControllerProvider)
                          .createGroup(name, _members.toList());
                      if (!context.mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => VeyraConversationScreen(
                            name: name,
                            conversationId: id,
                            group: true,
                          ),
                        ),
                      );
                    },
              child: const Text('Create group'))
        ]));
  }
}

class VeyraAttachmentPicker extends StatelessWidget {
  const VeyraAttachmentPicker({super.key});
  @override
  Widget build(BuildContext context) {
    const options = [
      (Icons.camera_alt_outlined, 'Camera'),
      (Icons.photo_outlined, 'Gallery'),
      (Icons.insert_drive_file_outlined, 'Document'),
      (Icons.headphones_outlined, 'Audio'),
      (Icons.location_on_outlined, 'Location'),
      (Icons.person_outline_rounded, 'Contact')
    ];
    return Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
            spacing: 18,
            runSpacing: 20,
            children: options
                .map((option) => InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Widget page;
                      switch (option.$2) {
                        case 'Audio':
                          page = const VoiceRecorderScreen();
                        case 'Document':
                          page = const DocumentPreviewScreen();
                        case 'Camera':
                        case 'Gallery':
                          page = const ImagePreviewScreen();
                        default:
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  '${option.$2} shared in this mock conversation')));
                          return;
                      }
                      Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => page));
                    },
                    child: SizedBox(
                        width: 70,
                        child: Column(children: [
                          CircleAvatar(
                              radius: 25,
                              backgroundColor: VeyraColors.elevated,
                              child:
                                  Icon(option.$1, color: VeyraColors.emerald)),
                          const SizedBox(height: 7),
                          Text(option.$2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12))
                        ]))))
                .toList()));
  }
}

class VeyraCallsScreen extends StatefulWidget {
  const VeyraCallsScreen({super.key});

  @override
  State<VeyraCallsScreen> createState() => _VeyraCallsScreenState();
}

class _VeyraCallsScreenState extends State<VeyraCallsScreen> {
  String _filter = 'All';
  bool _cleared = false;

  static const _calls = [
    _CallHistory('Aisha Khan', 'Outgoing', 'Today, 10:42 AM', 0xFF315C51),
    _CallHistory('Omar Siddiqui', 'Missed', 'Yesterday, 6:21 PM', 0xFF69523B,
        missed: true),
    _CallHistory('Design Circle', 'Group video', 'Monday, 3:14 PM', 0xFF4E4667,
        video: true, group: true),
    _CallHistory('Sana Ahmed', 'Incoming', 'Mon, 11:03 AM', 0xFF355D75,
        incoming: true, recent: false),
    _CallHistory('Leila Hassan', 'Outgoing', 'Sun, 8:45 PM', 0xFF655044,
        recent: false),
    _CallHistory('Hasham Uddin', 'Missed', 'Sep 20, 2:18 PM', 0xFF5A3D70,
        missed: true, recent: false),
    _CallHistory('Team Sync', 'Incoming', 'Sep 18, 7:11 PM', 0xFF2D6E78,
        incoming: true, recent: false),
  ];

  List<_CallHistory> get _visibleCalls {
    if (_cleared) return const [];
    return _calls.where((call) {
      return switch (_filter) {
        'Missed' => call.missed,
        'Voice' => !call.video,
        'Video' => call.video,
        _ => true,
      };
    }).toList();
  }

  void _clearHistory() {
    setState(() => _cleared = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Call history cleared locally.'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => setState(() => _cleared = false),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final calls = _visibleCalls;
    final recent = calls.where((call) => call.recent).toList();
    final earlier = calls.where((call) => !call.recent).toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
          children: [
            _CallsHeader(
              onSearch: () => showSearch<void>(
                context: context,
                delegate: _CallSearchDelegate(_calls),
              ),
              onMore: () => _showCallsMenu(context),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _callFilterIcons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final entry = _callFilterIcons.entries.elementAt(index);
                  final selected = _filter == entry.key;
                  return ChoiceChip(
                    showCheckmark: false,
                    selected: selected,
                    avatar: Icon(entry.value,
                        size: 19,
                        color: entry.key == 'Missed' && !selected
                            ? VeyraColors.danger
                            : selected
                                ? VeyraColors.text
                                : VeyraColors.muted),
                    label: Text(entry.key),
                    labelStyle: TextStyle(
                        color: selected ? VeyraColors.text : VeyraColors.muted,
                        fontWeight: FontWeight.w700),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    onSelected: (_) => setState(() => _filter = entry.key),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            _CallLinkCard(onTap: () => _showCallLink(context)),
            const SizedBox(height: 24),
            _CallSectionHeading(
                title: 'Recent',
                action: recent.isEmpty && earlier.isEmpty ? null : 'Clear',
                onAction: _clearHistory),
            const SizedBox(height: 10),
            if (recent.isEmpty && earlier.isEmpty)
              const _EmptyCalls()
            else ...[
              ...recent.map((call) => _CallTile(call: call)),
              if (earlier.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _CallSectionHeading(title: 'Earlier'),
                const SizedBox(height: 10),
                ...earlier.map((call) => _CallTile(call: call)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showCallsMenu(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: VeyraColors.surface,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Create call link'),
              onTap: () {
                Navigator.pop(context);
                _showCallLink(this.context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear call history'),
              onTap: () {
                Navigator.pop(context);
                _clearHistory();
              },
            ),
          ]),
        ),
      );
}

const _callFilterIcons = <String, IconData>{
  'All': Icons.phone_rounded,
  'Missed': Icons.phone_missed_rounded,
  'Voice': Icons.phone_in_talk_outlined,
  'Video': Icons.videocam_outlined,
};

class _CallsHeader extends StatelessWidget {
  const _CallsHeader({required this.onSearch, required this.onMore});
  final VoidCallback onSearch;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(
          child: Text('Calls',
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8)),
        ),
        _CallsHeaderButton(
            tooltip: 'Search calls',
            icon: Icons.search_rounded,
            onPressed: onSearch),
        const SizedBox(width: 10),
        _CallsHeaderButton(
            tooltip: 'More call options',
            icon: Icons.more_vert_rounded,
            onPressed: onMore),
      ]);
}

class _CallsHeaderButton extends StatelessWidget {
  const _CallsHeaderButton(
      {required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 27,
        color: VeyraColors.text,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(52),
          backgroundColor: VeyraColors.surface,
          side: const BorderSide(color: VeyraColors.border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      );
}

class _CallLinkCard extends StatelessWidget {
  const _CallLinkCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: VeyraColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: VeyraColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: VeyraColors.emerald.withValues(alpha: .16),
                child: const Icon(Icons.link_rounded,
                    color: VeyraColors.emeraldBright, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create call link',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    SizedBox(height: 7),
                    Text('Share a link to start a call',
                        style:
                            TextStyle(color: VeyraColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: VeyraColors.muted),
            ]),
          ),
        ),
      );
}

class _CallSectionHeading extends StatelessWidget {
  const _CallSectionHeading({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        if (action != null)
          TextButton(
              onPressed: onAction,
              child: Text(action!,
                  style: const TextStyle(color: VeyraColors.emerald))),
      ]);
}

class _CallHistory {
  const _CallHistory(this.name, this.kind, this.time, this.color,
      {this.missed = false,
      this.incoming = false,
      this.video = false,
      this.group = false,
      this.recent = true});
  final String name, kind, time;
  final int color;
  final bool missed, incoming, video, group, recent;

  IconData get directionIcon => video
      ? Icons.videocam_outlined
      : missed
          ? Icons.phone_missed_rounded
          : incoming
              ? Icons.call_received_rounded
              : Icons.call_made_rounded;
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});
  final _CallHistory call;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
          decoration: BoxDecoration(
            color: VeyraColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: VeyraColors.border),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Color(call.color),
              child: call.group
                  ? const Icon(Icons.groups_rounded, color: VeyraColors.text)
                  : Text(call.name[0],
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Icon(call.directionIcon,
                size: 18,
                color: call.missed ? VeyraColors.danger : VeyraColors.emerald),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: call.kind,
                          style: TextStyle(
                              color: call.missed
                                  ? VeyraColors.danger
                                  : VeyraColors.muted)),
                      TextSpan(
                          text: ' · ${call.time}',
                          style: const TextStyle(color: VeyraColors.muted)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            _CallAction(
                tooltip: 'Voice call ${call.name}',
                icon: Icons.phone_rounded,
                onPressed: () => _openCall(context, call, false)),
            const SizedBox(width: 4),
            _CallAction(
                tooltip: 'Video call ${call.name}',
                icon: Icons.videocam_outlined,
                onPressed: () => _openCall(context, call, true)),
            IconButton(
                tooltip: 'Call options',
                onPressed: () => _showCallOptions(context, call),
                icon: const Icon(Icons.more_vert_rounded,
                    color: VeyraColors.muted),
                iconSize: 20),
          ]),
        ),
      );
}

class _CallAction extends StatelessWidget {
  const _CallAction(
      {required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 21,
        color: VeyraColors.emerald,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(40),
          backgroundColor: VeyraColors.emerald.withValues(alpha: .09),
        ),
      );
}

class _EmptyCalls extends StatelessWidget {
  const _EmptyCalls();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 52),
        child: Column(children: [
          Icon(Icons.phone_disabled_outlined,
              size: 44, color: VeyraColors.muted),
          SizedBox(height: 14),
          Text('No calls to show',
              style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Your call history will appear here.',
              style: TextStyle(color: VeyraColors.muted)),
        ]),
      );
}

class _CallSearchDelegate extends SearchDelegate<void> {
  _CallSearchDelegate(this.calls);
  final List<_CallHistory> calls;

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);
  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))
      ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded));
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  @override
  Widget buildResults(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final matches = calls
        .where((call) => call.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: matches.map((call) => _CallTile(call: call)).toList(),
    );
  }
}

void _openCall(BuildContext context, _CallHistory call, bool video) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => VeyraCallScreen(name: call.name, video: video)),
    );

void _showCallOptions(BuildContext context, _CallHistory call) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: VeyraColors.surface,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.phone_rounded),
              title: Text('Call ${call.name}'),
              onTap: () {
                Navigator.pop(context);
                _openCall(context, call, false);
              }),
          ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Start video call'),
              onTap: () {
                Navigator.pop(context);
                _openCall(context, call, true);
              }),
        ]),
      ),
    );

void _showCallLink(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Veyra call link'),
        content: const SelectableText('veyra.local/call/close-circle'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    const ClipboardData(text: 'veyra.local/call/close-circle'));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy link')),
        ],
      ),
    );

class VeyraCallScreen extends StatefulWidget {
  const VeyraCallScreen({required this.name, this.video = false, super.key});
  final String name;
  final bool video;
  @override
  State<VeyraCallScreen> createState() => _VeyraCallScreenState();
}

class _VeyraCallScreenState extends State<VeyraCallScreen> {
  var _video = false;
  var _muted = false;
  var _speaker = false;
  @override
  void initState() {
    super.initState();
    _video = widget.video;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Container(
          decoration: const BoxDecoration(
              gradient: RadialGradient(
            center: Alignment(0, -.2),
            radius: 1.1,
            colors: [Color(0xFF17332E), VeyraColors.background],
          )),
          child: SafeArea(
              child: Column(children: [
            const SizedBox(height: 36),
            const Text('Calling…', style: TextStyle(color: VeyraColors.muted)),
            const SizedBox(height: 8),
            Text(widget.name,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: VeyraColors.emerald.withValues(alpha: .14)),
                  boxShadow: [
                    BoxShadow(
                        color: VeyraColors.emerald.withValues(alpha: .08),
                        blurRadius: 45,
                        spreadRadius: 8)
                  ]),
              child: CircleAvatar(
                  radius: 70,
                  backgroundColor: const Color(0xFF315C51),
                  child: Text(widget.name[0],
                      style: const TextStyle(fontSize: 56))),
            ),
            const SizedBox(height: 22),
            const Text('00:12', style: TextStyle(color: VeyraColors.muted)),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _CallControl(
                  icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: 'Mute',
                  onTap: () => setState(() => _muted = !_muted)),
              _CallControl(
                  icon: _video
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: 'Video',
                  onTap: () => setState(() => _video = !_video)),
              _CallControl(
                  icon: _speaker
                      ? Icons.volume_up_rounded
                      : Icons.volume_mute_rounded,
                  label: 'Speaker',
                  onTap: () => setState(() => _speaker = !_speaker))
            ]),
            const SizedBox(height: 30),
            FloatingActionButton(
                backgroundColor: VeyraColors.danger,
                foregroundColor: VeyraColors.text,
                onPressed: () => Navigator.pop(context),
                child: const Icon(Icons.call_end_rounded)),
            const SizedBox(height: 40)
          ]))));
}

class _CallControl extends StatelessWidget {
  const _CallControl(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Column(children: [
        IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12))
      ]);
}

class VeyraSettingsScreen extends ConsumerWidget {
  const VeyraSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(veyraControllerProvider);
    const groups = [
      [
        _SettingsEntry(
            Icons.person_outline_rounded, 'Profile', 'Name, username and bio'),
        _SettingsEntry(Icons.lock_outline_rounded, 'Privacy',
            'Discoverability and requests'),
        _SettingsEntry(Icons.notifications_none_rounded, 'Notifications',
            'Messages and calls'),
      ],
      [
        _SettingsEntry(
            Icons.palette_outlined, 'Appearance', 'Theme and chat display'),
        _SettingsEntry(Icons.storage_rounded, 'Storage', 'Media and downloads'),
      ],
      [
        _SettingsEntry(
            Icons.shield_outlined, 'Security', 'Devices and recovery'),
        _SettingsEntry(
            Icons.info_outline_rounded, 'About Veyra', 'Version 0.1.0'),
      ],
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Row(children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                iconSize: 27,
              ),
              const SizedBox(width: 12),
              const Text('Settings',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8)),
            ]),
            const SizedBox(height: 24),
            _SettingsProfileCard(
                user: controller.activeUser,
                onTap: () => _openSettings(context, 'Profile')),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              Card(
                color: VeyraColors.surface,
                child: ListTile(
                  leading: const Icon(Icons.developer_mode_rounded,
                      color: VeyraColors.emerald),
                  title: const Text('Development account'),
                  subtitle: Text(
                      '${controller.activeUser.displayName} · @${controller.activeUser.username}'),
                  trailing: const Icon(Icons.swap_horiz_rounded),
                  onTap: () => _showAccountSwitcher(context, ref),
                ),
              ),
            ],
            const SizedBox(height: 18),
            for (final group in groups) ...[
              _SettingsGroup(entries: group),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _showAccountSwitcher(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(veyraControllerProvider);
  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: VeyraColors.surface,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Development account switcher'),
            subtitle: Text('Debug builds only · local data'),
          ),
          ...controller.allUsers.take(6).map((user) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(user.avatarColor),
                  child: Text(user.displayName[0]),
                ),
                title: Text(user.displayName),
                subtitle: Text('@${user.username}'),
                trailing: user.id == controller.activeUser.id
                    ? const Icon(Icons.check_rounded,
                        color: VeyraColors.emerald)
                    : null,
                onTap: () => Navigator.pop(context, user.id),
              )),
        ],
      ),
    ),
  );
  if (selected != null) await controller.switchAccount(selected);
}

void _openSettings(BuildContext context, String section) => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => SettingsPage(section: section)),
    );

class _SettingsEntry {
  const _SettingsEntry(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title, subtitle;
}

class _SettingsProfileCard extends StatelessWidget {
  const _SettingsProfileCard({required this.user, required this.onTap});
  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            height: 142,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: VeyraColors.border),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.topRight,
                colors: [
                  VeyraColors.surface,
                  VeyraColors.emeraldDeep.withValues(alpha: .24),
                  VeyraColors.surface,
                ],
              ),
            ),
            child: CustomPaint(
              painter: _SettingsProfilePainter(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: Color(user.avatarColor),
                        child: Text(user.displayName[0],
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w600)),
                      ),
                      Positioned(
                        right: -5,
                        bottom: -3,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: VeyraColors.elevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: VeyraColors.border),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: VeyraColors.text, size: 17),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('@${user.username}',
                            style: const TextStyle(
                                color: VeyraColors.muted, fontSize: 16)),
                        const SizedBox(height: 7),
                        Text(
                            user.bio?.isNotEmpty == true
                                ? user.bio!
                                : 'Available',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: VeyraColors.muted, fontSize: 14)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: VeyraColors.muted, size: 27),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _SettingsProfilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VeyraColors.emerald.withValues(alpha: .09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final upper = Path()
      ..moveTo(size.width * .45, -8)
      ..cubicTo(size.width * .68, size.height * .8, size.width * .78,
          -size.height * .2, size.width * 1.05, size.height * .28);
    final lower = Path()
      ..moveTo(size.width * .56, size.height * 1.08)
      ..cubicTo(size.width * .7, size.height * .14, size.width * .86,
          size.height * 1.12, size.width * 1.08, size.height * .36);
    canvas.drawPath(upper, paint);
    canvas.drawPath(lower, paint..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.entries});
  final List<_SettingsEntry> entries;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: VeyraColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VeyraColors.border),
        ),
        child: Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              _SettingsRow(
                entry: entries[index],
                onTap: () => _openSettings(context, entries[index].title),
              ),
              if (index != entries.length - 1)
                const Divider(height: 1, indent: 84, endIndent: 18),
            ],
          ],
        ),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.entry, required this.onTap});
  final _SettingsEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: VeyraColors.emerald.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(17),
              ),
              child:
                  Icon(entry.icon, color: VeyraColors.emeraldBright, size: 27),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(entry.subtitle,
                      style: const TextStyle(
                          color: VeyraColors.muted, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: VeyraColors.muted, size: 25),
          ]),
        ),
      );
}

class VeyraSettingsDetailScreen extends StatelessWidget {
  const VeyraSettingsDetailScreen(
      {required this.title, required this.subtitle, super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final rows = title == 'Privacy'
        ? ['Discoverability', 'Who can send requests', 'Blocked accounts']
        : title == 'Profile'
            ? [
                'Edit display name',
                'Manage username',
                'Bio and profile picture'
              ]
            : title == 'Appearance'
                ? ['Dark theme', 'Chat wallpaper', 'Text size']
                : ['Manage $title', 'Preferences', 'Learn more'];
    return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(subtitle, style: const TextStyle(color: VeyraColors.muted)),
          const SizedBox(height: 20),
          ...rows.map((row) => ListTile(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$row updated locally.'))),
              title: Text(row),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: VeyraColors.muted)))
        ]));
  }
}

class _Composer extends StatelessWidget {
  const _Composer(
      {required this.controller,
      required this.onSend,
      required this.onAttach,
      required this.onVoice});
  final TextEditingController controller;
  final VoidCallback onSend, onAttach, onVoice;
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                        hintText: 'Message…',
                        prefixIcon: IconButton(
                            tooltip: 'Emoji',
                            onPressed: () => ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Emoji picker is simulated locally.'))),
                            icon: const Icon(
                                Icons.sentiment_satisfied_alt_rounded)),
                        suffixIconConstraints:
                            const BoxConstraints(minWidth: 92),
                        suffixIcon:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: 'Attach',
                              onPressed: onAttach,
                              icon: const Icon(Icons.attach_file_rounded)),
                          IconButton(
                              tooltip: 'Camera',
                              onPressed: onAttach,
                              icon: const Icon(Icons.camera_alt_outlined)),
                        ]),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 15)))),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return IconButton(
                      tooltip: hasText ? 'Send message' : 'Voice message',
                      onPressed: hasText ? onSend : onVoice,
                      icon: Icon(
                          hasText ? Icons.send_rounded : Icons.mic_rounded),
                      iconSize: 28,
                      color: VeyraColors.text,
                      style: IconButton.styleFrom(
                          fixedSize: const Size.square(58),
                          backgroundColor: VeyraColors.emerald,
                          shape: const CircleBorder()));
                })
          ])));
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({required this.message, this.onDelete});
  final _Message message;
  final Future<void> Function()? onDelete;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _liked = false;

  Future<void> _showActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VeyraColors.surface,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading:
                const Icon(Icons.favorite_rounded, color: VeyraColors.danger),
            title: Text(_liked ? 'Remove reaction' : 'React with a heart'),
            onTap: () => Navigator.pop(context, 'react'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copy message'),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
          if (widget.message.mine && widget.onDelete != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: VeyraColors.danger),
              title: const Text('Delete message'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'react') {
      setState(() => _liked = !_liked);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: widget.message.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied')),
        );
      }
    } else if (action == 'delete') {
      await widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Align(
      alignment:
          widget.message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
          onLongPress: _showActions,
          child: Container(
              margin: const EdgeInsets.only(bottom: 13),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 300),
              decoration: BoxDecoration(
                  color: widget.message.mine
                      ? VeyraColors.sent
                      : VeyraColors.elevated,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(19),
                    topRight: const Radius.circular(19),
                    bottomLeft: Radius.circular(widget.message.mine ? 19 : 5),
                    bottomRight: Radius.circular(widget.message.mine ? 5 : 19),
                  ),
                  border: Border.all(
                      color: widget.message.mine
                          ? const Color(0xFF207356)
                          : VeyraColors.border)),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(widget.message.text,
                    style: const TextStyle(fontSize: 16, height: 1.28)),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_liked) ...[
                    const Icon(Icons.favorite_rounded,
                        size: 13, color: VeyraColors.danger),
                    const SizedBox(width: 5),
                  ],
                  Text(widget.message.time,
                      style: const TextStyle(
                          fontSize: 11, color: VeyraColors.muted)),
                  if (widget.message.mine && !widget.message.isDeleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      widget.message.deliveryStatus == DeliveryStatus.sending
                          ? Icons.schedule_rounded
                          : widget.message.deliveryStatus ==
                                  DeliveryStatus.failed
                              ? Icons.error_outline_rounded
                              : widget.message.deliveryStatus ==
                                          DeliveryStatus.delivered ||
                                      widget.message.deliveryStatus ==
                                          DeliveryStatus.read
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                      size: 17,
                      color:
                          widget.message.deliveryStatus == DeliveryStatus.failed
                              ? VeyraColors.danger
                              : const Color(0xFF27C8F3),
                    ),
                  ],
                ]),
              ]))));
}

class _ChatWallpaper extends StatelessWidget {
  const _ChatWallpaper();

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ChatWallpaperPainter(),
        child: const SizedBox.expand(),
      );
}

class _ChatWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF001511), Color(0xFF00241B), Color(0xFF00110E)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final ink = Paint()
      ..color = VeyraColors.emerald.withValues(alpha: .065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85;
    const spacing = 58.0;
    for (double y = 16; y < size.height; y += spacing) {
      for (double x = 12; x < size.width; x += spacing) {
        final offset = ((y / spacing).round().isEven ? 0.0 : 29.0);
        final center = Offset(x + offset, y);
        final motif = ((x / spacing).round() + (y / spacing).round()) % 4;
        if (motif == 0) {
          canvas.drawCircle(center, 10, ink);
          canvas.drawCircle(center + const Offset(-3, -2), 1.5, ink);
          canvas.drawCircle(center + const Offset(3, -2), 1.5, ink);
          canvas.drawArc(
              Rect.fromCircle(center: center + const Offset(0, 2), radius: 5),
              .25,
              2.6,
              false,
              ink);
        } else if (motif == 1) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: center, width: 25, height: 18),
                  const Radius.circular(4)),
              ink);
          canvas.drawLine(
              center + const Offset(-8, -4), center + const Offset(7, -4), ink);
          canvas.drawLine(
              center + const Offset(-8, 1), center + const Offset(3, 1), ink);
        } else if (motif == 2) {
          canvas.drawCircle(center, 9, ink);
          canvas.drawArc(
              Rect.fromCircle(center: center + const Offset(13, 12), radius: 7),
              .25,
              2.2,
              false,
              ink);
          canvas.drawCircle(center + const Offset(22, -10), 2.5, ink);
        } else {
          final star = Path()
            ..moveTo(center.dx, center.dy - 11)
            ..lineTo(center.dx + 3, center.dy - 3)
            ..lineTo(center.dx + 11, center.dy)
            ..lineTo(center.dx + 3, center.dy + 3)
            ..lineTo(center.dx, center.dy + 11)
            ..lineTo(center.dx - 3, center.dy + 3)
            ..lineTo(center.dx - 11, center.dy)
            ..lineTo(center.dx - 3, center.dy - 3)
            ..close();
          canvas.drawPath(star, ink);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.onCancel});
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: VeyraColors.elevated, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.schedule_rounded, color: VeyraColors.emerald),
        const SizedBox(width: 10),
        const Expanded(
            child: Text('Request pending. You can message after they accept.',
                style: TextStyle(fontSize: 12))),
        TextButton(onPressed: onCancel, child: const Text('Cancel'))
      ]));
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(
      {required this.request,
      required this.onAccept,
      required this.onDecline,
      required this.onBlock});
  final _Request request;
  final VoidCallback onAccept, onDecline, onBlock;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: VeyraColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              backgroundColor: Color(request.color),
              child: Text(request.name[0])),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(request.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(request.username,
                    style: const TextStyle(color: VeyraColors.emerald))
              ])),
          Text(request.time,
              style: const TextStyle(color: VeyraColors.muted, fontSize: 12))
        ]),
        const SizedBox(height: 14),
        Text(request.message,
            style: const TextStyle(color: VeyraColors.muted, height: 1.4)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: onDecline, child: const Text('Decline'))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
                  onPressed: onAccept, child: const Text('Accept')))
        ]),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: onBlock,
                child: const Text('Block',
                    style: TextStyle(color: VeyraColors.danger))))
      ]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: VeyraColors.muted, size: 46),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: VeyraColors.muted))
      ]));
}

class _Message {
  const _Message(this.text, this.mine, this.time,
      {this.id,
      this.deliveryStatus = DeliveryStatus.read,
      this.isDeleted = false,
      this.createdAt});
  final String text, time;
  final bool mine;
  final String? id;
  final DeliveryStatus deliveryStatus;
  final bool isDeleted;
  final DateTime? createdAt;
}

class _Request {
  const _Request(this.name, this.username, this.message, this.time, this.color);
  final String name, username, message, time;
  final int color;
}

String _messageTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
          ? local.hour - 12
          : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}

bool _sameDay(DateTime? first, DateTime? second) {
  final a = (first ?? DateTime.now()).toLocal();
  final b = (second ?? DateTime.now()).toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateLabel(DateTime? value) {
  final date = (value ?? DateTime.now()).toLocal();
  final now = DateTime.now();
  if (_sameDay(date, now)) return 'Today';
  if (_sameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${date.day}/${date.month}/${date.year}';
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes} min ago';
  if (difference.inDays < 1) return '${difference.inHours} hr ago';
  if (difference.inDays == 1) return 'Yesterday';
  return '${difference.inDays} days ago';
}
