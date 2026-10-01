import '../../features/auth/domain/user_role.dart';
import '../security/password_hasher.dart';
import 'app_database.dart';

/// Data awal untuk database baru. Aman dipanggil setiap start: hanya mengisi
/// tabel yang masih kosong.
class DatabaseSeeder {
  DatabaseSeeder(this._db, this._hasher);

  final AppDatabase _db;
  final PasswordHasher _hasher;

  /// Akun bawaan. Password wajib diganti setelah fitur kelola user tersedia.
  static const defaultAccounts = [
    (
      username: 'admin',
      fullName: 'Administrator',
      password: 'admin123',
      role: UserRole.admin,
    ),
    (
      username: 'kasir',
      fullName: 'Kasir Satu',
      password: 'kasir123',
      role: UserRole.kasir,
    ),
  ];

  Future<void> seed() async {
    await _seedUsers();
  }

  Future<void> _seedUsers() async {
    if (await _db.usersDao.countUsers() > 0) return;

    final rows = [
      for (final a in defaultAccounts)
        UsersCompanion.insert(
          username: a.username,
          fullName: a.fullName,
          passwordHash: await _hasher.hash(a.password),
          role: a.role,
        ),
    ];
    await _db.batch((b) => b.insertAll(_db.users, rows));
  }
}
