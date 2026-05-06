/// Roles a user can hold within the UST E-Jeep Transit App.
enum UserRole {
  driver,
  student,
  anonymous,
}

/// Represents an authenticated (or anonymous) user of the app.
class User {
  final String uid;
  final String? email;
  final String? displayName;
  final UserRole role;

  /// Assigned route identifier — populated for drivers only.
  final String? routeId;

  const User({
    required this.uid,
    this.email,
    this.displayName,
    required this.role,
    this.routeId,
  });

  /// Deserialize from a Firestore / JSON map.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      uid: json['uid'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      role: UserRole.values.byName(json['role'] as String),
      routeId: json['routeId'] as String?,
    );
  }

  /// Serialize to a Firestore / JSON map.
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'routeId': routeId,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User &&
        other.uid == uid &&
        other.email == email &&
        other.displayName == displayName &&
        other.role == role &&
        other.routeId == routeId;
  }

  @override
  int get hashCode =>
      Object.hash(uid, email, displayName, role, routeId);

  @override
  String toString() {
    return 'User('
        'uid: $uid, '
        'email: $email, '
        'displayName: $displayName, '
        'role: ${role.name}, '
        'routeId: $routeId'
        ')';
  }
}
