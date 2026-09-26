import 'entities.dart';

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

  factory PublicProfile.fromUser(
    AppUser user, {
    bool isContact = false,
    bool hasPendingRequest = false,
  }) =>
      PublicProfile(
        id: user.id,
        displayName: user.displayName,
        username: user.username,
        avatarColor: user.avatarColor,
        bio: user.bio,
        isContact: isContact,
        hasPendingRequest: hasPendingRequest,
      );
}
