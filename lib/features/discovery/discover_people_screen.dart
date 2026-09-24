import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/mock_data/mock_profiles.dart';
import '../../core/models/public_profile.dart';
import '../../core/theme/app_theme.dart';
import '../app_ui/veyra_feature_screens.dart';

class DiscoverPeopleScreen extends StatefulWidget {
  const DiscoverPeopleScreen({super.key});

  @override
  State<DiscoverPeopleScreen> createState() => _DiscoverPeopleScreenState();
}

class _DiscoverPeopleScreenState extends State<DiscoverPeopleScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  var _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    setState(() => _loading = value.trim().isNotEmpty);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  List<PublicProfile> get _results {
    final query =
        _searchController.text.trim().toLowerCase().replaceFirst('@', '');
    if (query.isEmpty) return discoverableProfiles.take(5).toList();
    return discoverableProfiles
        .where((person) =>
            person.displayName.toLowerCase().contains(query) ||
            person.username.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final results = _results;
    final isError = query.toLowerCase() == 'error';
    return Scaffold(
      appBar: AppBar(
          title: const Text('Discover people',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name or @username',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(child: _buildBody(query, results, isError)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String query, List<PublicProfile> results, bool isError) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (isError) {
      return const _DiscoveryState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t search right now',
        subtitle: 'Please check your connection and try again.',
      );
    }
    if (results.isEmpty) {
      return const _DiscoveryState(
        icon: Icons.person_search_outlined,
        title: 'No people found',
        subtitle: 'Try a different display name or username.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              query.isEmpty
                  ? 'SUGGESTED PEOPLE'
                  : '${results.length} RESULT${results.length == 1 ? '' : 'S'}',
              style: const TextStyle(
                  color: VeyraColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2),
            ),
          );
        }
        return PublicProfileTile(profile: results[index - 1]);
      },
    );
  }
}

class PublicProfileTile extends StatelessWidget {
  const PublicProfileTile({required this.profile, super.key});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PublicProfileScreen(profile: profile),
        )),
        contentPadding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        leading: ProfileAvatar(profile: profile),
        title: Text(profile.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@${profile.username}',
                style: const TextStyle(
                    color: VeyraColors.emerald, fontWeight: FontWeight.w600)),
            if (profile.bio != null)
              Text(profile.bio!, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        isThreeLine: profile.bio != null,
        trailing:
            const Icon(Icons.chevron_right_rounded, color: VeyraColors.muted),
      );
}

class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({required this.profile, super.key});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                ProfileAvatar(profile: profile, radius: 48),
                const SizedBox(height: 18),
                Text(profile.displayName,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('@${profile.username}',
                    style: const TextStyle(
                        color: VeyraColors.emerald,
                        fontWeight: FontWeight.w600)),
                if (profile.bio != null) ...[
                  const SizedBox(height: 16),
                  Text(profile.bio!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: VeyraColors.muted)),
                ],
                const Spacer(),
                if (profile.isContact)
                  const _ProfileStatus(
                      icon: Icons.chat_bubble_rounded, label: 'In your chats')
                else if (profile.hasPendingRequest)
                  const _ProfileStatus(
                      icon: Icons.schedule_rounded, label: 'Request pending')
                else
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            VeyraIntroComposerScreen(profile: profile),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Message'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                  ),
              ],
            ),
          ),
        ),
      );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.profile, this.radius = 25, super.key});
  final PublicProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: Color(profile.avatarColor),
        child: Text(profile.displayName.substring(0, 1),
            style:
                TextStyle(fontSize: radius * .8, fontWeight: FontWeight.w700)),
      );
}

class _ProfileStatus extends StatelessWidget {
  const _ProfileStatus({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: VeyraColors.elevated,
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: VeyraColors.emerald),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _DiscoveryState extends StatelessWidget {
  const _DiscoveryState(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: VeyraColors.muted),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: VeyraColors.muted)),
        ]),
      ));
}
