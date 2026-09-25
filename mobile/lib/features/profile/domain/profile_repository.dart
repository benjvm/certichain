class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
  });
  final String id;
  final String fullName;
  final String role;
}

abstract interface class ProfileRepository {
  /// Null means the backend has no readable profile for this identity.
  Future<UserProfile?> readProfile(String userId);
}
