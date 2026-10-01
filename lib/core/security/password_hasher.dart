import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hash dan verifikasi password dengan bcrypt. Dijalankan di isolate terpisah
/// karena bcrypt sengaja lambat dan akan membuat UI tersendat.
class PasswordHasher {
  const PasswordHasher({this.logRounds = 10});

  /// Biaya bcrypt (2^logRounds iterasi). Tes memakai nilai kecil agar cepat.
  final int logRounds;

  Future<String> hash(String password) {
    final rounds = logRounds;
    return Isolate.run(
      () => BCrypt.hashpw(password, BCrypt.gensalt(logRounds: rounds)),
    );
  }

  Future<bool> verify(String password, String hash) {
    return Isolate.run(() {
      try {
        return BCrypt.checkpw(password, hash);
      } on Object {
        // Hash rusak/bukan bcrypt: anggap password salah.
        return false;
      }
    });
  }
}

final passwordHasherProvider = Provider<PasswordHasher>(
  (ref) => const PasswordHasher(),
);
