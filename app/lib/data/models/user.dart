import '../../core/constants/permissions.dart';
import '../../core/utils/json.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.phone,
    this.storeId,
    this.store,
    this.managedStores = const [],
    this.permissions = const [],
    this.lastLoginAt,
    this.createdAt,
    this.managedStoreCount = 0,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String status;
  final String? storeId;
  final Ref? store;
  final List<Ref> managedStores;
  final List<String> permissions;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final int managedStoreCount;

  bool get isAdmin => role == Roles.admin;
  bool get isManager => role == Roles.manager;
  bool get isStore => role == Roles.store;
  bool get isActive => status == 'ACTIVE';

  bool can(String permission) => isAdmin || permissions.contains(permission);

  String get roleLabel => switch (role) {
        Roles.admin => 'Administrator',
        Roles.manager => 'Manager',
        Roles.store => 'Store user',
        _ => role,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: asString(j['id']),
        name: asString(j['name']),
        email: asString(j['email']),
        phone: asStringOrNull(j['phone']),
        role: asString(j['role']),
        status: asString(j['status'], 'ACTIVE'),
        storeId: asStringOrNull(j['storeId']),
        store: Ref.fromJson(j['store']),
        managedStores: asList(j['managedStores']).map(Ref.fromJson).whereType<Ref>().toList(),
        permissions: asList(j['permissions']).map((e) => e.toString()).toList(),
        lastLoginAt: asDate(j['lastLoginAt']),
        createdAt: asDate(j['createdAt']),
        managedStoreCount: asInt(j['managedStoreCount'], asList(j['managedStores']).length),
      );
}
