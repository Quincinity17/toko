import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../domain/tag.dart';

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
        ),
    ],
  );

  /// Membuat tag baru, atau mengubah tag [id].
  Future<Tag> save({
    required AppUser actor,
    int? id,
    required String name,
    required TagColor color,
  }) async {
    _requireAdmin(actor);
    final error = TagRules.name(name);
    if (error != null) throw TagFailure(error);
    final n = name.trim();
    final dao = _db.tagsDao;
    return _db.transaction(() async {
      final same = await dao.findByName(n);
      if (same != null && same.id != id) {
        throw TagFailure('Kategori "${same.name}" sudah ada.');
      }
      final data = TagsCompanion(name: Value(n), color: Value(color.name));
      if (id == null) {
        final newId = await dao.insertTag(data);
        return Tag(id: newId, name: n, color: color);
      }
      if (await dao.findById(id) == null) {
        throw const TagFailure('Kategori tidak ditemukan.');
      }
      await dao.updateTag(id, data);
      return Tag(id: id, name: n, color: color);
    });
  }

  /// Menghapus tag; tag dilepas dari semua barang (barangnya tetap ada).
  Future<void> remove({required AppUser actor, required int id}) {
    _requireAdmin(actor);
    return _db.tagsDao.deleteTag(id);
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
