import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/entities.dart';
import '../../core/state/veyra_controller.dart';
import '../../core/theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({required this.section, super.key});
  final String section;
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _discoverable = true;
  bool _readReceipts = true;
  bool _messageAlerts = true;
  bool _callAlerts = true;
  bool _wifiOnly = false;
  String _requestAudience = 'Everyone on Veyra';
  double _textScale = 1;
  String _displayName = 'Shaheer Malik';
  String _username = '@shaheer';
  String _bio = 'The quieter side of conversation';

  @override
  void initState() {
    super.initState();
    final controller = ref.read(veyraControllerProvider);
    final stored = controller.settings;
    final user = controller.activeUser;
    _discoverable = user.isDiscoverable;
    _readReceipts = stored.readReceiptsEnabled;
    _messageAlerts = stored.notificationsEnabled;
    _callAlerts = stored.callNotificationsEnabled;
    _wifiOnly = stored.wifiOnlyDownloads;
    _requestAudience = switch (stored.requestAudience) {
      'nobody' => 'Nobody',
      'discovered' => 'People I discover',
      _ => 'Everyone on Veyra',
    };
    _textScale = stored.fontScale;
    _displayName = user.displayName;
    _username = '@${user.username}';
    _bio = user.bio ?? '';
  }

  Future<void> _savePreferences() =>
      ref.read(veyraControllerProvider).updateSettings(AppSettings(
            userId: ref.read(veyraControllerProvider).activeUser.id,
            theme: 'dark',
            notificationsEnabled: _messageAlerts,
            callNotificationsEnabled: _callAlerts,
            readReceiptsEnabled: _readReceipts,
            requestAudience: switch (_requestAudience) {
              'Nobody' => 'nobody',
              'People I discover' => 'discovered',
              _ => 'everyone',
            },
            wifiOnlyDownloads: _wifiOnly,
            fontScale: _textScale,
          ));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.section)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.section == 'Profile') ..._profile(),
          if (widget.section == 'Privacy') ..._privacy(),
          if (widget.section == 'Notifications') ..._notifications(),
          if (widget.section == 'Appearance') ..._appearance(),
          if (widget.section == 'Storage') ..._storage(),
          if (widget.section == 'Security') ..._security(),
          if (widget.section == 'About Veyra') ..._about(),
        ]),
      );

  List<Widget> _profile() => [
        const Center(
            child: CircleAvatar(
                radius: 39,
                backgroundColor: Color(0xFF315C51),
                child: Text('S',
                    style:
                        TextStyle(fontSize: 32, fontWeight: FontWeight.w700)))),
        const SizedBox(height: 12),
        Center(
            child: Text(_displayName,
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w700))),
        Center(
            child: Text(_username,
                style: const TextStyle(color: VeyraColors.emerald))),
        const SizedBox(height: 20),
        _section('PUBLIC PROFILE'),
        _editable('Display name', _displayName, (value) async {
          final error = await ref
              .read(veyraControllerProvider)
              .updateProfile(displayName: value);
          if (error == null) setState(() => _displayName = value);
          return error;
        }),
        _editable('Username', _username, (value) async {
          final error = await ref
              .read(veyraControllerProvider)
              .updateProfile(username: value);
          if (error == null) {
            setState(
                () => _username = value.startsWith('@') ? value : '@$value');
          }
          return error;
        }),
        _editable('Bio', _bio, (value) async {
          final error =
              await ref.read(veyraControllerProvider).updateProfile(bio: value);
          if (error == null) setState(() => _bio = value);
          return error;
        }),
        const SizedBox(height: 20),
        _section('PRIVATE ACCOUNT'),
        _SettingRow(
            'Email address',
            ref.read(veyraControllerProvider).activeUser.email,
            Icons.mail_outline_rounded),
        const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
                'Your email is used for account access and never shown in public search.',
                style: TextStyle(color: VeyraColors.muted, fontSize: 12))),
      ];

  List<Widget> _privacy() => [
        _section('DISCOVERY'),
        SwitchListTile(
          title: const Text('Discoverable profile'),
          subtitle:
              const Text('Let registered users find your name and username'),
          value: _discoverable,
          onChanged: (value) async {
            setState(() => _discoverable = value);
            await ref
                .read(veyraControllerProvider)
                .updateProfile(isDiscoverable: value);
          },
        ),
        ListTile(
          title: const Text('Who can send requests'),
          subtitle: Text(_requestAudience),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final chosen = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: VeyraColors.surface,
              builder: (context) => SafeArea(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ['Everyone on Veyra', 'People I discover', 'Nobody']
                    .map((value) => ListTile(
                          title: Text(value),
                          trailing: value == _requestAudience
                              ? const Icon(Icons.check_rounded,
                                  color: VeyraColors.emerald)
                              : null,
                          onTap: () => Navigator.pop(context, value),
                        ))
                    .toList(),
              )),
            );
            if (chosen != null && mounted) {
              setState(() => _requestAudience = chosen);
              await _savePreferences();
            }
          },
        ),
        const SizedBox(height: 18),
        _section('CONVERSATIONS'),
        SwitchListTile(
            title: const Text('Read receipts'),
            subtitle: const Text('Show when you have read a message'),
            value: _readReceipts,
            onChanged: (value) {
              setState(() => _readReceipts = value);
              _savePreferences();
            }),
        ListTile(
            leading: const Icon(Icons.block_rounded, color: VeyraColors.danger),
            title: const Text('Blocked accounts'),
            subtitle: const Text('1 account'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const BlockedAccountsScreen()))),
      ];

  List<Widget> _notifications() => [
        _section('ALERTS'),
        SwitchListTile(
            title: const Text('Messages'),
            subtitle: const Text('New messages and requests'),
            value: _messageAlerts,
            onChanged: (value) {
              setState(() => _messageAlerts = value);
              _savePreferences();
            }),
        SwitchListTile(
            title: const Text('Calls'),
            subtitle: const Text('Incoming voice and video calls'),
            value: _callAlerts,
            onChanged: (value) {
              setState(() => _callAlerts = value);
              _savePreferences();
            }),
        const _SettingRow('Sound', 'Veyra default', Icons.music_note_outlined),
      ];

  List<Widget> _appearance() => [
        _section('THEME'),
        const _SettingRow('App theme', 'Dark', Icons.dark_mode_outlined),
        const SizedBox(height: 14),
        _section('CHAT DISPLAY'),
        const _SettingRow('Wallpaper', 'Midnight', Icons.wallpaper_outlined),
        ListTile(
            title: const Text('Text size'),
            subtitle: Slider(
                value: _textScale,
                min: .8,
                max: 1.3,
                divisions: 5,
                label: '${(_textScale * 100).round()}%',
                onChanged: (value) {
                  setState(() => _textScale = value);
                  _savePreferences();
                })),
        Center(
            child: Text('A calm place to talk.',
                textScaler: TextScaler.linear(_textScale),
                style: const TextStyle(color: VeyraColors.muted))),
      ];

  List<Widget> _storage() => [
        _section('STORAGE USAGE'),
        const Card(
            color: VeyraColors.surface,
            child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('256 MB',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700)),
                      SizedBox(height: 5),
                      Text('Mock media across all chats',
                          style: TextStyle(color: VeyraColors.muted)),
                      SizedBox(height: 16),
                      LinearProgressIndicator(
                          value: .4,
                          color: VeyraColors.emerald,
                          backgroundColor: VeyraColors.elevated),
                    ]))),
        const SizedBox(height: 16),
        SwitchListTile(
            title: const Text('Download on Wi-Fi only'),
            value: _wifiOnly,
            onChanged: (value) {
              setState(() => _wifiOnly = value);
              _savePreferences();
            }),
        const _SettingRow(
            'Photos and videos', '116 MB', Icons.photo_library_outlined),
        const _SettingRow('Documents', '74 MB', Icons.description_outlined),
        const _SettingRow('Voice messages', '66 MB', Icons.mic_none_rounded),
      ];

  List<Widget> _security() => [
        _section('ACCOUNT ACCESS'),
        const _SettingRow(
            'Change password', 'Local preview', Icons.password_rounded),
        const _SettingRow(
            'Linked devices', 'This device', Icons.devices_outlined),
        const SizedBox(height: 20),
        _section('BACKUP'),
        const Card(
            color: VeyraColors.surface,
            child: ListTile(
                leading: Icon(Icons.cloud_outlined, color: VeyraColors.emerald),
                title: Text('Backup preview'),
                subtitle:
                    Text('Backup is unavailable in this UI-only prototype.'))),
      ];

  List<Widget> _about() => [
        const SizedBox(height: 40),
        const Center(
            child: Icon(Icons.forum_rounded,
                size: 60, color: VeyraColors.emerald)),
        const SizedBox(height: 14),
        const Center(
            child: Text('Veyra',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
        const Center(
            child: Text('Version 0.1.0 · UI prototype',
                style: TextStyle(color: VeyraColors.muted))),
        const SizedBox(height: 30),
        const _SettingRow(
            'Privacy policy', 'Preview', Icons.privacy_tip_outlined),
        const _SettingRow(
            'Terms of service', 'Preview', Icons.description_outlined),
      ];

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Text(label,
            style: const TextStyle(
                color: VeyraColors.emerald,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
      );

  Widget _editable(String label, String value,
          Future<String?> Function(String) onSave) =>
      ListTile(
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () async {
          var updated = value;
          await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                    title: Text('Edit $label'),
                    content: TextFormField(
                        initialValue: value,
                        autofocus: true,
                        onChanged: (value) => updated = value,
                        decoration: InputDecoration(labelText: label)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () async {
                            final trimmed = updated.trim();
                            if (trimmed.isEmpty) return;
                            final error = await onSave(trimmed);
                            if (!context.mounted) return;
                            if (error == null) {
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                            }
                          },
                          child: const Text('Save')),
                    ],
                  ));
        },
      );
}

class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});
  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  bool _blocked = true;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Blocked accounts')),
        body: _blocked
            ? ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0xFF69523B), child: Text('D')),
                title: const Text('Daniel Ross'),
                subtitle: const Text('@dross'),
                trailing: TextButton(
                    onPressed: () => setState(() => _blocked = false),
                    child: const Text('Unblock')),
              )
            : const Center(
                child: Text('No blocked accounts',
                    style: TextStyle(color: VeyraColors.muted))),
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(this.title, this.detail, this.icon);
  final String title, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: VeyraColors.muted),
        title: Text(title),
        subtitle: Text(detail),
      );
}
