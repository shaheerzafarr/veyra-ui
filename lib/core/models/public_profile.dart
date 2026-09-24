class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.displayName,
    required this.username,
    required this.avatarColor,
    this.bio,
    this.isContact = false,
    this.hasPendingRequest = false,
  });

  final String id;
  final String displayName;
  final String username;
  final int avatarColor;
  final String? bio;
  final bool isContact;
  final bool hasPendingRequest;
}
