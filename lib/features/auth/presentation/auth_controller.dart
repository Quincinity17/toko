import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';

/// Sesi login saat ini (`null` = belum login). Hanya di memori: setiap aplikasi
/// dibuka, user harus login lagi.
class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  /// Melempar [AuthFailure] jika gagal.
  Future<void> login(String username, String password) async {
    state = await ref.read(authRepositoryProvider).login(username, password);
  }

  void logout() => state = null;
}

final authControllerProvider = NotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

/// Daftar akun untuk dipilih di layar login.
final loginUsersProvider = FutureProvider.autoDispose<List<AppUser>>(
  (ref) => ref.watch(authRepositoryProvider).activeUsers(),
);
