import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class ConversationSearchScreen extends StatefulWidget {
  const ConversationSearchScreen({required this.name, super.key});
  final String name;
  @override
  State<ConversationSearchScreen> createState() =>
      _ConversationSearchScreenState();
}

class _ConversationSearchScreenState extends State<ConversationSearchScreen> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lines = [
      'Hey! How is it going?',
      'I just finished the design.',
      'Can you send me the file?',
      'That sounds perfect — see you then!',
    ];
    final results = lines
        .where((line) => line.toLowerCase().contains(_query.text.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('Search · ${widget.name}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: true,
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                hintText: 'Search messages…',
                prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        Expanded(
            child: results.isEmpty
                ? const Center(
                    child: Text('No matching messages',
                        style: TextStyle(color: VeyraColors.muted)))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) => ListTile(
                      leading: const Icon(Icons.chat_bubble_outline_rounded,
                          color: VeyraColors.emerald),
                      title: Text(results[index]),
                      subtitle: const Text('Today · 9:15 PM'),
                    ),
                  )),
      ]),
    );
  }
}

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({required this.name, super.key});
  final String name;
  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final _members = <String>[
    'Shaheer Malik',
    'Maya Chen',
    'Aisha Khan',
    'Omar Siddiqui'
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Group info')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const SizedBox(height: 12),
          const CircleAvatar(
              radius: 42,
              backgroundColor: Color(0xFF4E4667),
              child: Icon(Icons.groups_rounded,
                  size: 38, color: VeyraColors.text)),
          const SizedBox(height: 14),
          Text(widget.name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text(
              '${_members.length} members · Created for thoughtful conversations',
              textAlign: TextAlign.center,
              style: const TextStyle(color: VeyraColors.muted)),
          const SizedBox(height: 24),
          _InfoAction(
              icon: Icons.photo_library_outlined,
              label: 'Media, files and links',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const GroupMediaScreen()))),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(
                child: Text('MEMBERS',
                    style: TextStyle(
                        color: VeyraColors.muted,
                        fontSize: 12,
                        letterSpacing: 1.2))),
            TextButton.icon(
              onPressed: () async {
                final person = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: VeyraColors.surface,
                  builder: (context) => SafeArea(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            'Sana Ahmed',
                            'Leila Hassan',
                            'Noor Fatima'
                          ]
                              .map((name) => ListTile(
                                  title: Text(name),
                                  leading: const Icon(
                                      Icons.person_add_alt_1_rounded),
                                  onTap: () => Navigator.pop(context, name)))
                              .toList())),
                );
                if (person != null && mounted) {
                  setState(() => _members.add(person));
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
          ]),
          ..._members.map((person) => ListTile(
                leading: CircleAvatar(
                    backgroundColor: const Color(0xFF315C51),
                    child: Text(person[0])),
                title: Text(person),
                subtitle: person == 'Shaheer Malik'
                    ? const Text('Admin · You')
                    : null,
                trailing: person == 'Shaheer Malik'
                    ? null
                    : IconButton(
                        tooltip: 'Remove $person',
                        onPressed: () =>
                            setState(() => _members.remove(person)),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
              )),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                        title: const Text('Leave group?'),
                        content: const Text(
                            'You will no longer receive messages from this group.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Stay')),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              child: const Text('Leave',
                                  style: TextStyle(color: VeyraColors.danger))),
                        ])),
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('Leave group'),
          ),
        ]),
      );
}

class GroupMediaScreen extends StatelessWidget {
  const GroupMediaScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Media, files and links')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('SHARED MEDIA',
              style: TextStyle(
                  color: VeyraColors.muted, fontSize: 12, letterSpacing: 1.1)),
          const SizedBox(height: 12),
          SizedBox(
              height: 120,
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: List.generate(
                      4,
                      (index) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ImagePreviewScreen(index: index))),
                              child: Container(
                                  width: 120,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(13),
                                    gradient: LinearGradient(
                                        colors: [
                                          const Color(0xFF1F3C60),
                                          Color.lerp(const Color(0xFF132134),
                                              VeyraColors.emerald, index / 8)!,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight),
                                  ),
                                  child: const Icon(Icons.landscape_rounded,
                                      color: VeyraColors.text, size: 42)),
                            ),
                          )))),
          const SizedBox(height: 22),
          const Text('FILES',
              style: TextStyle(
                  color: VeyraColors.muted, fontSize: 12, letterSpacing: 1.1)),
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFF513F53),
                child: Icon(Icons.picture_as_pdf_rounded,
                    color: VeyraColors.text)),
            title: const Text('Project_Design.pdf'),
            subtitle: const Text('2.1 MB · Aug 12'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const DocumentPreviewScreen())),
          ),
        ]),
      );
}

class ImagePreviewScreen extends StatelessWidget {
  const ImagePreviewScreen({this.index = 0, super.key});
  final int index;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black, title: Text('${index + 1} of 4')),
        body: Column(children: [
          Expanded(
              child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
              Color(0xFF071322),
              Color(0xFF193450),
              Color(0xFF071322)
            ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            child: const Icon(Icons.landscape_rounded,
                color: Color(0xFF7A9AB5), size: 140),
          )),
          Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(
                              content: Text('Sharing is a mock preview'))),
                      tooltip: 'Share',
                      icon: const Icon(Icons.share_outlined)),
                  IconButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(
                              content:
                                  Text('Image saved in this mock gallery'))),
                      tooltip: 'Save',
                      icon: const Icon(Icons.download_rounded)),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded)),
                ],
              )),
        ]),
      );
}

class DocumentPreviewScreen extends StatelessWidget {
  const DocumentPreviewScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Document preview')),
        body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              const Icon(Icons.picture_as_pdf_rounded,
                  size: 88, color: VeyraColors.danger),
              const SizedBox(height: 20),
              const Text('Project_Design.pdf',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('2.1 MB · PDF document',
                  style: TextStyle(color: VeyraColors.muted)),
              const Spacer(),
              FilledButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Download preview complete'))),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52))),
            ])),
      );
}

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});
  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  bool _recording = true;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Record voice message')),
        body: SafeArea(
            child: Column(children: [
          const Spacer(),
          CircleAvatar(
              radius: 74,
              backgroundColor: const Color(0xFF103C30),
              child: Icon(
                  _recording
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
                  color: VeyraColors.emerald,
                  size: 62)),
          const SizedBox(height: 25),
          Text(_recording ? 'Recording…' : 'Paused',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('0:12 · Mock recording',
              style: TextStyle(color: VeyraColors.muted)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Discard'),
            IconButton.filled(
                onPressed: () => setState(() => _recording = !_recording),
                icon:
                    Icon(_recording ? Icons.pause_rounded : Icons.mic_rounded),
                tooltip: _recording ? 'Pause' : 'Resume'),
            IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded),
                tooltip: 'Done'),
          ]),
          const SizedBox(height: 35),
        ])),
      );
}

class _InfoAction extends StatelessWidget {
  const _InfoAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        tileColor: VeyraColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: VeyraColors.emerald),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
