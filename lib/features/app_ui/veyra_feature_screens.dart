import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/public_profile.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/discover_people_screen.dart';
import '../chats/conversation_extras.dart';
import '../settings/settings_pages.dart';

class VeyraRequestsScreen extends StatefulWidget {
  const VeyraRequestsScreen({super.key});

  @override
  State<VeyraRequestsScreen> createState() => _VeyraRequestsScreenState();
}

class _VeyraRequestsScreenState extends State<VeyraRequestsScreen> {
  final _requests = <_Request>[
    const _Request(
        'Maya Chen',
        '@mayac',
        'I loved the direction you took on the last project. Would be great to connect.',
        '18 min ago',
        0xFF4E4667),
    const _Request(
        'Noor Fatima',
        '@noorf',
        'Hi! I saw we share a few interests and wanted to say hello.',
        'Yesterday',
        0xFF73544C)
  ];

  Future<void> _remove(_Request request, String action) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('$action ${request.name}?'),
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
    if (confirmed == true && mounted) {
      setState(() => _requests.remove(request));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'Accept'
              ? '${request.name} was added to Chats.'
              : 'Request $action.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Message requests',
                style: TextStyle(fontWeight: FontWeight.w700))),
        body: _requests.isEmpty
            ? const _EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No message requests',
                subtitle: 'Requests from new people will appear here.')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final request = _requests[index];
                  return _RequestCard(
                      request: request,
                      onAccept: () => _remove(request, 'Accept'),
                      onDecline: () => _remove(request, 'Decline'),
                      onBlock: () => _remove(request, 'Block'));
                },
              ),
      );
}

class VeyraIntroComposerScreen extends StatefulWidget {
  const VeyraIntroComposerScreen({required this.profile, super.key});
  final PublicProfile profile;
  @override
  State<VeyraIntroComposerScreen> createState() =>
      _VeyraIntroComposerScreenState();
}

class _VeyraIntroComposerScreenState extends State<VeyraIntroComposerScreen> {
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
                              : () {
                                  Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute<void>(
                                          builder: (_) =>
                                              VeyraConversationScreen(
                                                  name: widget
                                                      .profile.displayName,
                                                  pending: true)));
                                },
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Send request'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56))),
                    ]))),
      );
}

class VeyraConversationScreen extends StatefulWidget {
  const VeyraConversationScreen(
      {required this.name,
      this.group = false,
      this.pending = false,
      super.key});
  final String name;
  final bool group;
  final bool pending;
  @override
  State<VeyraConversationScreen> createState() =>
      _VeyraConversationScreenState();
}

class _VeyraConversationScreenState extends State<VeyraConversationScreen> {
  final _composer = TextEditingController();
  final _messages = <_Message>[
    const _Message('Hey! How is it going?', false, '9:12 PM'),
    const _Message(
        'It’s going great! I just finished the design.', true, '9:15 PM'),
    const _Message(
        'That looks amazing. Can you send me the file?', false, '9:16 PM')
  ];
  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message(text, true, 'Now'));
      _composer.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
                onTap: widget.group
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                GroupDetailsScreen(name: widget.name)))
                    : null,
                child: Row(children: [
                  CircleAvatar(
                      backgroundColor: const Color(0xFF315C51),
                      child: Text(widget.name[0])),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                            widget.pending
                                ? 'Request pending'
                                : widget.group
                                    ? '5 members'
                                    : 'online',
                            style: const TextStyle(
                                fontSize: 12, color: VeyraColors.muted))
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
                  icon: const Icon(Icons.videocam_outlined)),
              IconButton(
                  onPressed: widget.pending
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  VeyraCallScreen(name: widget.name))),
                  icon: const Icon(Icons.phone_outlined)),
              IconButton(
                  onPressed: () => _showChatMenu(context),
                  icon: const Icon(Icons.more_vert_rounded))
            ]),
        body: Column(children: [
          if (widget.pending)
            _PendingBanner(onCancel: () => Navigator.pop(context)),
          Expanded(
              child: Stack(children: [
            const Positioned.fill(child: _ChatWallpaper()),
            ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Center(
                        child: Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text('TODAY',
                                style: TextStyle(
                                    color: VeyraColors.muted,
                                    fontSize: 11,
                                    letterSpacing: 1.2))));
                  }
                  return _MessageBubble(message: _messages[index - 1]);
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
                              ? GroupDetailsScreen(name: widget.name)
                              : const GroupMediaScreen()));
                }),
            ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Mute notifications'),
                onTap: () => Navigator.pop(context))
          ])));
}

class VeyraGroupsScreen extends StatefulWidget {
  const VeyraGroupsScreen({super.key});
  @override
  State<VeyraGroupsScreen> createState() => _VeyraGroupsScreenState();
}

class _VeyraGroupsScreenState extends State<VeyraGroupsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
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
        ListTile(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const VeyraConversationScreen(
                        name: 'Design Circle', group: true))),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: VeyraColors.surface,
            leading: const CircleAvatar(
                backgroundColor: Color(0xFF4E4667),
                child: Icon(Icons.groups_rounded)),
            title: const Text('Design Circle',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Maya: I added the latest screens'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: VeyraColors.muted))
      ]));
}

class VeyraCreateGroupScreen extends StatefulWidget {
  const VeyraCreateGroupScreen({super.key});
  @override
  State<VeyraCreateGroupScreen> createState() => _VeyraCreateGroupScreenState();
}

class _VeyraCreateGroupScreenState extends State<VeyraCreateGroupScreen> {
  final _name = TextEditingController();
  final _members = <String>{};
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
            decoration: const InputDecoration(labelText: 'Group name')),
        const SizedBox(height: 22),
        const Text('ADD MEMBERS',
            style: TextStyle(
                color: VeyraColors.muted, fontSize: 12, letterSpacing: 1.2)),
        ...[
          'Aisha Khan',
          'Omar Siddiqui',
          'Maya Chen',
          'Noor Fatima'
        ].map((member) => CheckboxListTile(
            value: _members.contains(member),
            onChanged: (value) => setState(() =>
                value == true ? _members.add(member) : _members.remove(member)),
            title: Text(member),
            controlAffinity: ListTileControlAffinity.trailing)),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _name.text.trim().isEmpty || _members.isEmpty
                ? null
                : () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => VeyraConversationScreen(
                            name: _name.text, group: true))),
            child: const Text('Create group'))
      ]));
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

class VeyraCallsScreen extends StatelessWidget {
  const VeyraCallsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Calls',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.all(16), children: const [
        Text('RECENT',
            style: TextStyle(
                color: VeyraColors.muted, fontSize: 12, letterSpacing: 1.2)),
        SizedBox(height: 8),
        _CallTile(
            name: 'Aisha Khan',
            status: 'Outgoing · Today, 10:42 AM',
            icon: Icons.call_made_rounded),
        _CallTile(
            name: 'Omar Siddiqui',
            status: 'Missed · Yesterday',
            icon: Icons.call_received_rounded,
            missed: true),
        _CallTile(
            name: 'Design Circle',
            status: 'Group video · Monday',
            icon: Icons.videocam_outlined)
      ]));
}

class _CallTile extends StatelessWidget {
  const _CallTile(
      {required this.name,
      required this.status,
      required this.icon,
      this.missed = false});
  final String name, status;
  final IconData icon;
  final bool missed;
  @override
  Widget build(BuildContext context) => ListTile(
      onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => VeyraCallScreen(name: name))),
      leading: CircleAvatar(
          backgroundColor: const Color(0xFF315C51), child: Text(name[0])),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(status,
          style: TextStyle(
              color: missed ? VeyraColors.danger : VeyraColors.muted)),
      trailing: Icon(icon, color: VeyraColors.emerald));
}

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

class VeyraSettingsScreen extends StatelessWidget {
  const VeyraSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.person_outline_rounded, 'Profile', 'Name, username and bio'),
      (Icons.lock_outline_rounded, 'Privacy', 'Discoverability and requests'),
      (Icons.notifications_none_rounded, 'Notifications', 'Messages and calls'),
      (Icons.palette_outlined, 'Appearance', 'Theme and chat display'),
      (Icons.storage_outlined, 'Storage', 'Media and downloads'),
      (Icons.security_outlined, 'Security', 'Devices and recovery'),
      (Icons.info_outline_rounded, 'About Veyra', 'Version 0.1.0')
    ];
    return Scaffold(
        appBar: AppBar(
            title: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.w700))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const ListTile(
              leading: CircleAvatar(
                  radius: 27,
                  backgroundColor: Color(0xFF315C51),
                  child: Text('S')),
              title: Text('Shaheer Malik',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('@shaheer')),
          const SizedBox(height: 18),
          ...items.map((item) => ListTile(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(section: item.$2))),
              leading: Icon(item.$1, color: VeyraColors.emerald),
              title: Text(item.$2,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(item.$3),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: VeyraColors.muted)))
        ]));
  }
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(children: [
            IconButton(
                onPressed: onAttach,
                icon: const Icon(Icons.add_circle_outline_rounded)),
            Expanded(
                child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        hintText: 'Message…',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12)))),
            IconButton(
                tooltip: 'Voice message',
                onPressed: onVoice,
                icon:
                    const Icon(Icons.mic_rounded, color: VeyraColors.emerald)),
            IconButton.filled(
                onPressed: onSend, icon: const Icon(Icons.send_rounded))
          ])));
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({required this.message});
  final _Message message;

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
    }
  }

  @override
  Widget build(BuildContext context) => Align(
      alignment:
          widget.message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
          onLongPress: _showActions,
          child: Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 290),
              decoration: BoxDecoration(
                  color: widget.message.mine
                      ? VeyraColors.sent
                      : VeyraColors.elevated,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(15),
                    topRight: const Radius.circular(15),
                    bottomLeft: Radius.circular(widget.message.mine ? 15 : 4),
                    bottomRight: Radius.circular(widget.message.mine ? 4 : 15),
                  ),
                  border: Border.all(
                      color: widget.message.mine
                          ? const Color(0xFF207356)
                          : VeyraColors.border)),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(widget.message.text),
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_liked) ...[
                    const Icon(Icons.favorite_rounded,
                        size: 13, color: VeyraColors.danger),
                    const SizedBox(width: 5),
                  ],
                  Text(widget.message.time,
                      style: const TextStyle(
                          fontSize: 10, color: VeyraColors.muted)),
                  if (widget.message.mine) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all_rounded,
                        size: 15, color: Color(0xFF53A8FF)),
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
        colors: [Color(0xFF091011), Color(0xFF101A1A), Color(0xFF091011)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final ink = Paint()
      ..color = VeyraColors.emerald.withValues(alpha: .035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    const spacing = 86.0;
    for (double y = 22; y < size.height; y += spacing) {
      for (double x = 18; x < size.width; x += spacing) {
        final offset = ((y / spacing).round().isEven ? 0.0 : 42.0);
        final center = Offset(x + offset, y);
        canvas.drawCircle(center, 11, ink);
        canvas.drawArc(
          Rect.fromCircle(center: center + const Offset(18, 18), radius: 9),
          .25,
          2.2,
          false,
          ink,
        );
        canvas.drawLine(
          center + const Offset(-7, 24),
          center + const Offset(9, 36),
          ink,
        );
        canvas.drawCircle(center + const Offset(32, -13), 3, ink);
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
  const _Message(this.text, this.mine, this.time);
  final String text, time;
  final bool mine;
}

class _Request {
  const _Request(this.name, this.username, this.message, this.time, this.color);
  final String name, username, message, time;
  final int color;
}
