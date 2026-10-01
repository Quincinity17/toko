import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/auth/domain/user_role.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late UserRepository users;
  late AuthRepository auth;
  late AppUser admin;
  late AppUser kasir;

  Matcher failsWith(String text) => throwsA(
    isA<AccountFailure>().having((e) => e.message, 'message', contains(text)),
  );

  setUp(() async {
    db = await createSeededDb();
    users = UserRepository(db, testHasher);
    auth = AuthRepository(db, testHasher);
    admin = await auth.login('admin', 'admin123');
    kasir = await auth.login('kasir', 'kasir123');
  });

  tearDown(() => db.close());

  group('tambah akun', () {
    test('akun baru bisa langsung login dengan perannya', () async {
      final created = await users.create(
        actor: admin,
        username: ' Siti ',
        fullName: 'Siti Aminah',
        role: UserRole.kasir,
        password: 'rahasia1',
      );
      expect(created.username, 'siti');

      final loggedIn = await auth.login('siti', 'rahasia1');
      expect(loggedIn.role, UserRole.kasir);
    });

    test('username duplikat ditolak', () {
      expect(
        users.create(
          actor: admin,
          username: 'KASIR',
          fullName: 'Lain',
          role: UserRole.kasir,
          password: 'rahasia1',
        ),
        failsWith('sudah dipakai'),
      );
    });

    test('username berspasi dan password pendek ditolak', () {
      expect(
        users.create(
          actor: admin,
          username: 'siti aminah',
          fullName: 'Siti',
          role: UserRole.kasir,
          password: 'rahasia1',
        ),
        failsWith('tanpa spasi'),
      );
      expect(
        users.create(
          actor: admin,
          username: 'siti',
          fullName: 'Siti',
          role: UserRole.kasir,
          password: '123',
        ),
        failsWith('minimal'),
      );
    });

    test('kasir tidak boleh menambah akun', () {
      expect(
        users.create(
          actor: kasir,
          username: 'baru',
          fullName: 'Baru',
          role: UserRole.admin,
          password: 'rahasia1',
        ),
        failsWith('Hanya admin'),
      );
    });
  });

  group('pengaman admin', () {
    test('admin tidak bisa menonaktifkan atau menurunkan diri sendiri', () {
      expect(
        users.update(
          actor: admin,
          id: admin.id,
          fullName: admin.fullName,
          role: UserRole.admin,
          isActive: false,
        ),
        failsWith('akun sendiri'),
      );
      expect(
        users.update(
          actor: admin,
          id: admin.id,
          fullName: admin.fullName,
          role: UserRole.kasir,
          isActive: true,
        ),
        failsWith('akun sendiri'),
      );
    });

    test('admin tidak bisa menghapus diri sendiri', () {
      expect(
        users.delete(actor: admin, id: admin.id),
        failsWith('akun sendiri'),
      );
    });

    test('dengan dua admin, admin lain boleh dinonaktifkan', () async {
      final second = await users.create(
        actor: admin,
        username: 'admin2',
        fullName: 'Admin Dua',
        role: UserRole.admin,
        password: 'rahasia1',
      );
      final updated = await users.update(
        actor: admin,
        id: second.id,
        fullName: second.fullName,
        role: UserRole.admin,
        isActive: false,
      );
      expect(updated.isActive, isFalse);
      expect(await db.usersDao.countActiveAdmins(), 1);
    });

    test('admin nonaktif tidak bisa login', () async {
      final second = await users.create(
        actor: admin,
        username: 'admin2',
        fullName: 'Admin Dua',
        role: UserRole.admin,
        password: 'rahasia1',
      );
      await users.update(
        actor: admin,
        id: second.id,
        fullName: second.fullName,
        role: UserRole.admin,
        isActive: false,
      );
      expect(auth.login('admin2', 'rahasia1'), throwsA(isA<AuthFailure>()));
    });
  });

  group('ubah dan hapus', () {
    test('ubah nama dan peran kasir menjadi admin', () async {
      final updated = await users.update(
        actor: admin,
        id: kasir.id,
        fullName: 'Kasir Senior',
        role: UserRole.admin,
        isActive: true,
      );
      expect(updated.fullName, 'Kasir Senior');
      expect(updated.role, UserRole.admin);
    });

    test('hapus akun kasir', () async {
      await users.delete(actor: admin, id: kasir.id);
      expect(await db.usersDao.findById(kasir.id), isNull);
    });
  });

  group('password', () {
    test('admin reset password kasir', () async {
      await users.resetPassword(
        actor: admin,
        id: kasir.id,
        newPassword: 'baru1234',
      );
      expect(auth.login('kasir', 'kasir123'), throwsA(isA<AuthFailure>()));
      expect((await auth.login('kasir', 'baru1234')).id, kasir.id);
    });

    test('kasir tidak bisa reset password orang lain', () {
      expect(
        users.resetPassword(actor: kasir, id: admin.id, newPassword: 'hack123'),
        failsWith('Hanya admin'),
      );
    });

    test('admin ganti password sendiri wajib benar password lama', () async {
      expect(
        users.changeOwnPassword(
          user: admin,
          currentPassword: 'salah',
          newPassword: 'baru1234',
        ),
        failsWith('Password lama salah'),
      );

      await users.changeOwnPassword(
        user: admin,
        currentPassword: 'admin123',
        newPassword: 'baru1234',
      );
      expect((await auth.login('admin', 'baru1234')).id, admin.id);
    });

    test('kasir tidak bisa mengganti password sendiri', () async {
      await expectLater(
        users.changeOwnPassword(
          user: kasir,
          currentPassword: 'kasir123',
          newPassword: 'baru1234',
        ),
        failsWith('Hanya admin'),
      );
      expect((await auth.login('kasir', 'kasir123')).id, kasir.id);
    });
  });
}
