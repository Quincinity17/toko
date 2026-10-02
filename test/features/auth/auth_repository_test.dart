import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/seed.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/user_role.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late AuthRepository repo;

  setUp(() async {
    db = await createSeededDb();
    repo = AuthRepository(db, testHasher);
  });

  tearDown(() => db.close());

  test('seed membuat 1 admin dan 1 kasir dengan password ter-hash', () async {
    final rows = await db.select(db.users).get();
    expect(
      rows.map((r) => r.role),
      unorderedEquals([UserRole.admin, UserRole.kasir]),
    );
    for (final r in rows) {
      expect(r.passwordHash, startsWith(r'$2a$'));
      expect(r.passwordHash, isNot(contains('123')));
    }
  });

  test('seed tidak menggandakan user bila dipanggil ulang', () async {
    await DatabaseSeeder(db, testHasher).seed();
    expect(await db.usersDao.countUsers(), 2);
  });

  test('login admin dan kasir mengembalikan peran yang benar', () async {
    final admin = await repo.login('admin', 'admin123');
    final kasir = await repo.login('kasir', 'kasir123');
    expect(admin.role, UserRole.admin);
    expect(kasir.role, UserRole.kasir);
    expect(admin.lastLoginAt, isNotNull);
  });

  test('username tidak peka huruf besar/kecil', () async {
    final user = await repo.login('  Admin ', 'admin123');
    expect(user.username, 'admin');
  });

  test(
    'password salah dan user tidak dikenal ditolak dengan pesan sama',
    () async {
      Future<String?> msg(String u, String p) async {
        try {
          await repo.login(u, p);
          return null;
        } on AuthFailure catch (e) {
          return e.message;
        }
      }

      final wrongPassword = await msg('admin', 'salah');
      final unknownUser = await msg('tidakada', 'admin123');
      expect(wrongPassword, isNotNull);
      expect(wrongPassword, unknownUser);
    },
  );

  test('user nonaktif tidak bisa login', () async {
    await (db.update(db.users)..where((u) => u.username.equals('kasir'))).write(
      const UsersCompanion(isActive: Value(false)),
    );

    expect(() => repo.login('kasir', 'kasir123'), throwsA(isA<AuthFailure>()));
  });

  test('hak akses: kasir hanya halaman Kasir', () {
    expect(UserRole.kasir.canAccess('/kasir'), isTrue);
    expect(UserRole.kasir.canAccess('/dashboard'), isFalse);
    expect(UserRole.kasir.canAccess('/produk'), isFalse);
    expect(UserRole.kasir.canAccess('/pengaturan'), isFalse);
    expect(UserRole.admin.canAccess('/pengaturan'), isTrue);
  });
}
