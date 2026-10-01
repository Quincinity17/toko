import 'package:drift/drift.dart';

import '../../../features/auth/domain/user_role.dart';

/// Akun login. Username disimpan dalam huruf kecil agar login tidak peka
/// huruf besar/kecil.
@DataClassName('UserRow')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 3, max: 32).unique()();
  TextColumn get fullName => text().withLength(min: 1, max: 100)();

  /// Hash bcrypt, tidak pernah password asli.
  TextColumn get passwordHash => text()();
  TextColumn get role => textEnum<UserRole>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
}
