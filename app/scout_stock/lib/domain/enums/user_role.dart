enum UserRole {
  scout,
  admin;

  bool get isAdmin => this == UserRole.admin;

  static UserRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'scout':
      default:
        return UserRole.scout;
    }
  }

  String toJson() => name;
}
