import 'package:drift/drift.dart';

import '../../../features/auth/domain/user_role.dart';
import '../uuid.dart';

/// v14: hak akses per peran (Pengaturan › Hak Akses Peran). Satu baris = peran
/// [role] punya hak [permission] (nama `Permission`). Admin tidak disimpan
/// (selalu semua). Setiap baris disegel; baris tanpa segel yang cocok
/// (disisipkan di luar aplikasi) diabaikan.
@DataClassName('RolePermissionRow')
@TableIndex(name: 'idx_role_permissions_uuid', columns: {#uuid}, unique: true)
class RolePermissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get role => textEnum<UserRole>()();
  TextColumn get permission => text()();

  /// Segel (`Sealer`) atas role + permission.
  TextColumn get seal => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {role, permission},
  ];
}
