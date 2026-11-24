class AppUser {
  const AppUser({
    required this.id,
    required this.uuid,
    required this.name,
    required this.role,
    this.permissions = const [],
    this.branchId,
  });

  final int id;
  final String uuid;
  final String name;
  final String role;
  final List<String> permissions;
  final int? branchId;

  bool can(String permission) => role == 'admin' || permissions.contains(permission);

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: (j['id'] as num).toInt(),
        uuid: j['uuid'] as String? ?? '',
        name: j['name'] as String? ?? '',
        role: j['role'] as String? ?? 'waiter',
        permissions: (j['permissions'] as List?)?.cast<String>() ?? const [],
        branchId: (j['branchId'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'name': name,
        'role': role,
        'permissions': permissions,
        'branchId': branchId,
      };
}
