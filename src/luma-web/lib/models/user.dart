class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String avatarSeed;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarSeed,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: _str(json['id']),
      email: _str(json['email']),
      displayName: _str(json['display_name']),
      avatarSeed: _str(json['avatar_seed']),
      createdAt: _dt(json['created_at']),
    );
  }
}

class UserPreferences {
  final String theme;
  final String timezone;
  final String dateFormat;
  final String timeFormat;
  final String language;
  final bool compactMode;
  final bool notifyOnLogin;
  final bool notifyOnRevoke;

  const UserPreferences({
    this.theme = 'system',
    this.timezone = 'UTC',
    this.dateFormat = 'YYYY-MM-DD',
    this.timeFormat = '24h',
    this.language = 'en',
    this.compactMode = false,
    this.notifyOnLogin = true,
    this.notifyOnRevoke = true,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: _str(json['theme'], 'system'),
      timezone: _str(json['timezone'], 'UTC'),
      dateFormat: _str(json['date_format'], 'YYYY-MM-DD'),
      timeFormat: _str(json['time_format'], '24h'),
      language: _str(json['language'], 'en'),
      compactMode: _bool(json['compact_mode']),
      notifyOnLogin: _bool(json['notify_on_login'], true),
      notifyOnRevoke: _bool(json['notify_on_revoke'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'timezone': timezone,
        'date_format': dateFormat,
        'time_format': timeFormat,
        'language': language,
        'compact_mode': compactMode,
        'notify_on_login': notifyOnLogin,
        'notify_on_revoke': notifyOnRevoke,
      };
}

class Device {
  final String id;
  final String name;
  final String platform;
  final String userAgent;
  final DateTime lastSeenAt;
  final DateTime createdAt;
  final bool isCurrent;

  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.userAgent,
    required this.lastSeenAt,
    required this.createdAt,
    required this.isCurrent,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    // The auth service's Device struct has no json tags, so Go marshals with
    // PascalCase field names (Name, Platform, UserAgent, etc.).
    // We check both PascalCase and snake_case for robustness.
    return Device(
      id: _str(_get(json, 'ID', 'id')),
      name: _str(_get(json, 'Name', 'name') ?? json['device_name']),
      platform: _str(_get(json, 'Platform', 'platform')),
      userAgent: _str(_get(json, 'UserAgent', 'user_agent')),
      lastSeenAt: _dt(_get(json, 'LastSeenAt', 'last_seen_at')),
      createdAt: _dt(_get(json, 'CreatedAt', 'created_at')),
      isCurrent: _bool(_get(json, 'IsCurrent', 'is_current')),
    );
  }
}

class AuditEvent {
  final String id;
  final String event;
  final String ipAddress;
  final String userAgent;
  final Map<String, dynamic> metadata;
  final DateTime occurredAt;

  const AuditEvent({
    required this.id,
    required this.event,
    required this.ipAddress,
    required this.userAgent,
    required this.metadata,
    required this.occurredAt,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    // The auth service's audit.Row struct has no json tags, so Go marshals with
    // PascalCase field names (Event, IPAddress, OccurredAt, etc.).
    final meta = _get(json, 'Metadata', 'metadata');
    return AuditEvent(
      id: _str(_get(json, 'ID', 'id')),
      event: _str(_get(json, 'Event', 'event')),
      ipAddress: _str(_get(json, 'IPAddress', 'ip_address')),
      userAgent: _str(_get(json, 'UserAgent', 'user_agent')),
      metadata: (meta is Map<String, dynamic>) ? meta : const {},
      occurredAt: _dt(_get(json, 'OccurredAt', 'occurred_at')),
    );
  }
}

/// Looks up a JSON key by trying the PascalCase name first (Go default when
/// no json tags are set), then the snake_case name.
dynamic _get(Map<String, dynamic> json, String pascalKey, String snakeKey) {
  return json[pascalKey] ?? json[snakeKey];
}

/// Safely extracts a String from a JSON value that might be int, null, etc.
String _str(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// Safely extracts a bool from a JSON value.
bool _bool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  return fallback;
}

/// Safely parses a DateTime from a JSON value.
DateTime _dt(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}
