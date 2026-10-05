import 'package:drift/drift.dart';

import '../../../features/auth/domain/user_role.dart';
import '../app_database.dart';
import '../tables/users.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [Users])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.attachedDatabase);

  Future<int> countUsers() async {
    final count = users.id.count();
    final row = await (selectOnly(users)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<UserRow?> findByUsername(String username) {
    return (select(users)
          ..where((u) => u.username.equals(username.trim().toLowerCase())))
        .getSingleOrNull();
  }

  // Setiap penulisan menyegel ulang baris (lihat SealsDao).
  Future<int> insertUser(UsersCompanion user) async {
    final id = await into(users).insert(user);
    await attachedDatabase.sealsDao.resealUser(id);
    return id;
  }

  Future<void> touchLastLogin(int id, DateTime at) {
    return (update(users)..where((u) => u.id.equals(id))).write(
      UsersCompanion(lastLoginAt: Value(at)),
    );
  }

  /// Semua akun untuk halaman Kelola Akun: aktif dulu, lalu peran dan nama.
  Stream<List<UserRow>> watchAllUsers() {
    return (select(users)..orderBy([
          (u) => OrderingTerm.desc(u.isActive),
          (u) => OrderingTerm.asc(u.role),
          (u) => OrderingTerm.asc(u.fullName),
        ]))
        .watch();
  }

  Future<UserRow?> findById(int id) {
    return (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  }

  Future<int> countActiveAdmins() async {
    final count = users.id.count();
    final query = selectOnly(users)
      ..addColumns([count])
      ..where(
        users.isActive.equals(true) & users.role.equalsValue(UserRole.admin),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> updateUser(int id, UsersCompanion data) async {
    await (update(users)..where((u) => u.id.equals(id))).write(data);
    await attachedDatabase.sealsDao.resealUser(id);
  }

  Future<int> deleteUser(int id) {
    return (delete(users)..where((u) => u.id.equals(id))).go();
  }
}
