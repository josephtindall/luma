class CustomRolePermission {
  final String action;
  final String effect; // "allow" | "allow_cascade" | "deny"

  const CustomRolePermission({required this.action, required this.effect});

  factory CustomRolePermission.fromJson(Map<String, dynamic> j) =>
      CustomRolePermission(
        action: j['action'] as String,
        effect: j['effect'] as String,
      );
}

class CustomRoleRecord {
  final String id;
  final String name;
  final bool isSystem;
  final int? priority;
  final int userCount;
  final int groupCount;
  final List<CustomRolePermission> permissions;
  final DateTime createdAt;

  const CustomRoleRecord({
    required this.id,
    required this.name,
    required this.isSystem,
    this.priority,
    required this.userCount,
    required this.groupCount,
    required this.permissions,
    required this.createdAt,
  });

  factory CustomRoleRecord.fromJson(Map<String, dynamic> j) => CustomRoleRecord(
        id: j['id'] as String,
        name: j['name'] as String,
        isSystem: j['is_system'] as bool? ?? false,
        priority: j['priority'] as int?,
        userCount: j['user_count'] as int? ?? 0,
        groupCount: j['group_count'] as int? ?? 0,
        permissions: (j['permissions'] as List<dynamic>?)
                ?.map((e) =>
                    CustomRolePermission.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
