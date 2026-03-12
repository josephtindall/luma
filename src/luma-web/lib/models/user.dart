class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String avatarSeed;
  final String instanceRoleId;
  final bool mfaEnabled;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarSeed,
    required this.instanceRoleId,
    required this.mfaEnabled,
    required this.createdAt,
  });

  bool get isOwner => instanceRoleId == 'builtin:instance-owner';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: _str(json['id']),
      email: _str(json['email']),
      displayName: _str(json['display_name']),
      avatarSeed: _str(json['avatar_seed']),
      instanceRoleId: _str(json['instance_role_id']),
      mfaEnabled: _bool(json['mfa_enabled']),
      createdAt: _dt(json['created_at']),
    );
  }
}

class AdminUserRecord {
  final String id;
  final String email;
  final String displayName;
  final String avatarSeed;
  final String instanceRoleId;
  final bool mfaEnabled;
  final bool isLocked;
  final bool forcePasswordChange;
  final int totpCount;
  final int passkeyCount;
  final DateTime createdAt;

  const AdminUserRecord({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarSeed,
    required this.instanceRoleId,
    required this.mfaEnabled,
    required this.isLocked,
    required this.forcePasswordChange,
    required this.totpCount,
    required this.passkeyCount,
    required this.createdAt,
  });

  bool get isOwner => instanceRoleId == 'builtin:instance-owner';

  factory AdminUserRecord.fromJson(Map<String, dynamic> json) {
    return AdminUserRecord(
      id: _str(json['id']),
      email: _str(json['email']),
      displayName: _str(json['display_name']),
      avatarSeed: _str(json['avatar_seed']),
      instanceRoleId: _str(json['instance_role_id']),
      mfaEnabled: _bool(json['mfa_enabled']),
      isLocked: _bool(json['is_locked']),
      forcePasswordChange: _bool(json['force_password_change']),
      totpCount: (json['totp_count'] as int?) ?? 0,
      passkeyCount: (json['passkey_count'] as int?) ?? 0,
      createdAt: _dt(json['created_at']),
    );
  }
}

class PasswordResetLinkResult {
  final String token;
  final DateTime expiresAt;

  const PasswordResetLinkResult({required this.token, required this.expiresAt});

  factory PasswordResetLinkResult.fromJson(Map<String, dynamic> json) {
    return PasswordResetLinkResult(
      token: _str(json['token']),
      expiresAt: _dt(json['expires_at']),
    );
  }
}

class InvitationCreateResult {
  final String id;
  final String token; // raw token extracted from the auth service's join_url
  final DateTime expiresAt;

  const InvitationCreateResult({
    required this.id,
    required this.token,
    required this.expiresAt,
  });
}

class InvitationRecord {
  final String id;
  final String email;
  final String note;
  final String status; // "pending", "accepted", "revoked"
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  const InvitationRecord({
    required this.id,
    required this.email,
    required this.note,
    required this.status,
    required this.expiresAt,
    required this.acceptedAt,
    required this.revokedAt,
    required this.createdAt,
  });

  /// True if pending and the expiry time has not passed.
  bool get isPendingValid =>
      status == 'pending' && DateTime.now().isBefore(expiresAt);

  /// True if pending but the expiry time has passed.
  bool get isExpired =>
      status == 'pending' && DateTime.now().isAfter(expiresAt);

  bool get isAccepted => status == 'accepted';
  bool get isRevoked => status == 'revoked';

  /// Pending invites (valid or expired) can be revoked.
  bool get canRevoke => status == 'pending';

  factory InvitationRecord.fromJson(Map<String, dynamic> json) {
    return InvitationRecord(
      id: _str(json['id']),
      email: _str(json['email']),
      note: _str(json['note']),
      status: _str(json['status']),
      expiresAt: _dt(json['expires_at']),
      acceptedAt: _dtOpt(json['accepted_at']),
      revokedAt: _dtOpt(json['revoked_at']),
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

class TOTPApp {
  final String id;
  final String name;
  final DateTime createdAt;

  const TOTPApp({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory TOTPApp.fromJson(Map<String, dynamic> json) {
    return TOTPApp(
      id: _str(json['id']),
      name: _str(json['name']),
      createdAt: _dt(json['created_at']),
    );
  }
}

class Passkey {
  final String id;
  final String name;
  final DateTime createdAt;

  const Passkey({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Passkey.fromJson(Map<String, dynamic> json) {
    return Passkey(
      id: _str(json['id']),
      name: _str(json['name']),
      createdAt: _dt(json['created_at']),
    );
  }
}

class AuditEvent {
  final String id;
  final String event;
  final String ipAddress;
  final String userAgent;
  final String? userId;
  final String? userEmail;
  final String? userDisplayName;
  final Map<String, dynamic> metadata;
  final DateTime occurredAt;

  const AuditEvent({
    required this.id,
    required this.event,
    required this.ipAddress,
    required this.userAgent,
    this.userId,
    this.userEmail,
    this.userDisplayName,
    required this.metadata,
    required this.occurredAt,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    // New handler emits snake_case json tags; keep PascalCase fallback for
    // backward compatibility during any transition period.
    final meta = json['metadata'] ?? json['Metadata'];
    return AuditEvent(
      id: _str(json['id'] ?? json['ID']),
      event: _str(json['event'] ?? json['Event']),
      ipAddress: _str(json['ip_address'] ?? json['IPAddress']),
      userAgent: _str(json['user_agent'] ?? json['UserAgent']),
      userId: json['user_id'] as String?,
      userEmail: json['user_email'] as String?,
      userDisplayName: json['user_display_name'] as String?,
      metadata: (meta is Map<String, dynamic>) ? meta : const {},
      occurredAt: _dt(json['occurred_at'] ?? json['OccurredAt']),
    );
  }

  /// Best display name for this event's actor (admin view).
  String get actorLabel =>
      userDisplayName ?? userEmail ?? userId ?? '—';
}

class AuditPage {
  final List<AuditEvent> events;
  final int total;
  final int limit;
  final int offset;

  const AuditPage({
    required this.events,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory AuditPage.fromJson(Map<String, dynamic> json) {
    final items = json['events'] as List<dynamic>? ?? [];
    return AuditPage(
      events: items
          .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 10,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasMore => offset + events.length < total;
  int get totalPages => limit > 0 ? ((total + limit - 1) ~/ limit) : 1;
  int get currentPage => limit > 0 ? offset ~/ limit : 0;
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

/// Safely parses an optional DateTime (returns null if value is null/empty).
DateTime? _dtOpt(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
