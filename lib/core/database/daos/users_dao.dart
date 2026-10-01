import 'package:drift/drift.dart';

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

  /// User aktif, diurutkan: admin dulu, lalu nama.
  Future<List<UserRow>> activeUsers() {
    return (select(users)
          ..where((u) => u.isActive.equals(true))
          ..orderBy([
            (u) => OrderingTerm.asc(u.role),
            (u) => OrderingTerm.asc(u.fullName),
          ]))
        .get();
  }

  Future<int> insertUser(UsersCompanion user) => into(users).insert(user);

  Future<void> touchLastLogin(int id, DateTime at) {
    return (update(users)..where((u) => u.id.equals(id))).write(
      UsersCompanion(lastLoginAt: Value(at)),
    );
  }
}
