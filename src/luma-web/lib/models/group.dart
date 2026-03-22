class GroupMemberRecord {
  final String memberType;
  final String memberId;
  final DateTime addedAt;

  const GroupMemberRecord({
    required this.memberType,
    required this.memberId,
    required this.addedAt,
  });

  factory GroupMemberRecord.fromJson(Map<String, dynamic> j) =>
      GroupMemberRecord(
        memberType: j['member_type'] as String,
        memberId: j['member_id'] as String,
        addedAt: DateTime.parse(j['added_at'] as String),
      );
}

class GroupRecord {
  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final bool noMemberControl;
  final bool hideFromSearch;
  final int memberCount;
  final List<String> roleIds;
  final List<GroupMemberRecord> members;
  final DateTime createdAt;

  const GroupRecord({
    required this.id,
    required this.name,
    this.description,
    required this.isSystem,
    this.noMemberControl = false,
    this.hideFromSearch = false,
    required this.memberCount,
    required this.roleIds,
    required this.members,
    required this.createdAt,
  });

  factory GroupRecord.fromJson(Map<String, dynamic> j) => GroupRecord(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        isSystem: j['is_system'] as bool? ?? false,
        noMemberControl: j['no_member_control'] as bool? ?? false,
        hideFromSearch: j['hide_from_search'] as bool? ?? false,
        memberCount: j['member_count'] as int? ?? 0,
        roleIds: (j['role_ids'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        members: (j['members'] as List<dynamic>?)
                ?.map((e) =>
                    GroupMemberRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
