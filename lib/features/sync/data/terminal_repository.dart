import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/uuid.dart';
import '../../auth/domain/app_user.dart';
import '../domain/terminal.dart';

class TerminalFailure implements Exception {
  const TerminalFailure(this.message);

  final String message;

  @override
  String toString() => 'TerminalFailure: $message';
}

/// Identitas komputer ini, disimpan di tabel `settings`.
class TerminalRepository {
  TerminalRepository(this._db);

  final AppDatabase _db;

  static const _kId = 'terminal.id';
  static const kCode = 'terminal.code';
  static const _kMode = 'terminal.mode';

  /// Dipanggil sekali di `main()`: membuat ID terminal jika belum ada.
  Future<Terminal> ensureInitialized() async {
    final s = _db.settingsDao;
    if (await s.get(_kId) == null) await s.set(_kId, newUuid());
    if (await s.get(kCode) == null) await s.set(kCode, Terminal.defaultCode);
    if (await s.get(_kMode) == null) {
      await s.set(_kMode, TerminalMode.server.name);
    }
    return current();
  }

  Future<Terminal> current() async {
    final s = _db.settingsDao;
    return _build(await s.get(_kId), await s.get(kCode), await s.get(_kMode));
  }

  Stream<Terminal> watch() => _db.settingsDao
      .watchMany([_kId, kCode, _kMode])
      .map((v) => _build(v[_kId], v[kCode], v[_kMode]));

  /// Mengganti kode terminal. Hanya memengaruhi faktur berikutnya.
  Future<void> setCode({required AppUser actor, required String code}) async {
    if (!actor.isAdmin) {
      throw const TerminalFailure('Hanya admin yang bisa mengganti kode.');
    }
    final error = Terminal.validateCode(code);
    if (error != null) throw TerminalFailure(error);
    await _db.settingsDao.set(kCode, Terminal.normalizeCode(code));
  }

  Terminal _build(String? id, String? code, String? mode) => Terminal(
    id: id ?? '',
    code: code ?? Terminal.defaultCode,
    mode: TerminalMode.values.asNameMap()[mode] ?? TerminalMode.server,
  );
}

final terminalRepositoryProvider = Provider<TerminalRepository>(
  (ref) => TerminalRepository(ref.watch(appDatabaseProvider)),
);

final terminalProvider = StreamProvider<Terminal>(
  (ref) => ref.watch(terminalRepositoryProvider).watch(),
);

/// Jumlah transaksi yang menunggu dikirim ke server.
final pendingSyncCountProvider = StreamProvider<int>(
  (ref) => ref.watch(appDatabaseProvider).outboxDao.watchPendingCount(),
);
