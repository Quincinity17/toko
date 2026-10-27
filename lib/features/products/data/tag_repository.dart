import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../domain/code_prefix.dart';
import '../domain/tag.dart';
import '../../sync/data/terminal_repository.dart';

class TagFailure implements Exception {
  const TagFailure(this.message);

  final String message;

  @override
  String toString() => 'TagFailure: $message';
}

/// Kelola tag jenis barang (khusus admin): tambah, ubah nama/warna, hapus.
/// Nama unik tanpa peduli huruf besar/kecil.
class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;

  Stream<List<Tag>> watchAll() => _db.tagsDao.watchAllWithCount().map(
    (rows) => [
      for (final (t, count) in rows)
        Tag(
          id: t.id,
          name: t.name,
          color: TagColor.of(t.color),
          productCount: count,
          codePrefix: t.codePrefix,
          codeDigits: t.codeDigits,
        ),
    ],
  );

  /// Membuat tag baru, atau mengubah tag [id].
  Future<Tag> save({
    required AppUser actor,
    int? id,
    required String name,
    required TagColor color,
    String? codePrefix,
    int? codeDigits,
  }) async {
    _requireAdmin(actor);
    await _requireMaster();
    final error = TagRules.name(name) ?? CodePrefix.validate(codePrefix);
    if (error != null) throw TagFailure(error);
    if (codeDigits != null && (codeDigits < 2 || codeDigits > 10)) {
      throw const TagFailure('Jumlah digit barcode 2–10.');
    }
    final n = name.trim();
    final prefix = CodePrefix.normalize(codePrefix);
    final dao = _db.tagsDao;
    return _db.transaction(() async {
      final same = await dao.findByName(n);
      if (same != null && same.id != id) {
        throw TagFailure('Kategori "${same.name}" sudah ada.');
      }
      if (prefix != null) {
        final owner = await dao.findByPrefix(prefix);
        if (owner != null && owner.id != id) {
          throw TagFailure(
            'Awalan $prefix sudah dipakai kategori "${owner.name}".',
          );
        }
      }
      final data = TagsCompanion(
        name: Value(n),
        color: Value(color.name),
        codePrefix: Value(prefix),
        codeDigits: Value(codeDigits),
      );
      if (id == null) {
        final newId = await dao.insertTag(data);
        return Tag(
          id: newId,
          name: n,
          color: color,
          codePrefix: prefix,
          codeDigits: codeDigits,
        );
      }
      if (await dao.findById(id) == null) {
        throw const TagFailure('Kategori tidak ditemukan.');
      }
      await dao.updateTag(id, data);
      return Tag(
        id: id,
        name: n,
        color: color,
        codePrefix: prefix,
        codeDigits: codeDigits,
      );
    });
  }

  /// Saran awalan barcode untuk kategori [name] (lihat
  /// [CodePrefix.suggest]). Awalan kategori lain dan awalan barcode barang
  /// di luar kategori ini tidak disarankan.
  Future<List<String>> suggestPrefixes(String name, {int? tagId}) async {
    final own = name.trim().isEmpty
        ? const <String>[]
        : await _db.productsDao.codesInTag(name);
    final ownSet = {for (final c in own) c.toUpperCase()};
    final taken = <String>{
      for (final t in await _db.select(_db.tags).get())
        if (t.id != tagId && t.codePrefix != null) t.codePrefix!,
      for (final c in await _db.productsDao.codesNewestFirst())
        if (!ownSet.contains(c.toUpperCase())) ?CodePrefix.of(c),
    };
    return CodePrefix.suggest(name, categoryCodes: own, taken: taken);
  }

  /// Menghapus tag; tag dilepas dari semua barang (barangnya tetap ada).
  Future<void> remove({required AppUser actor, required int id}) async {
    _requireAdmin(actor);
    await _requireMaster();
    return _db.tagsDao.deleteTag(id);
  }

  /// Data master hanya diubah di komputer server (lihat sinkron).
  Future<void> _requireMaster() async {
    final message = await TerminalRepository.masterLockMessage(_db);
    if (message != null) throw TagFailure(message);
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const TagFailure('Hanya admin yang bisa mengelola kategori.');
    }
  }
}

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(appDatabaseProvider)),
);

final tagsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll(),
);
