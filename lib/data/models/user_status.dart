enum UserStatus {
  unknown,
  active,
  banned,
  deleted,
}

extension UserStatusCode on UserStatus {
  String get code {
    switch (this) {
      case UserStatus.unknown:
        return 'UNKNOWN';
      case UserStatus.active:
        return 'ACTIVE';
      case UserStatus.banned:
        return 'BANNED';
      case UserStatus.deleted:
        return 'DELETED';
    }
  }
}
