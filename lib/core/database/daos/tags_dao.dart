import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tags.dart';

part 'tags_dao.g.dart';

@DriftAccessor(tables: [Tags, ProductTags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.attachedDatabase);

  /// Semua tag (urut nama) beserta jumlah barang yang memakainya.
  Stream<List<(TagRow, int)>> watchAllWithCount() {
    final count = productTags.productId.count();
    final query =
        select(tags).join([
            leftOuterJoin(productTags, productTags.tagId.equalsExp(tags.id)),
          ])
          ..addColumns([count])
          ..groupBy([tags.id])
          ..orderBy([OrderingTerm.asc(tags.name.collate(Collate.noCase))]);
    return query.map((r) => (r.readTable(tags), r.read(count) ?? 0)).watch();
  }

  Future<TagRow?> findById(int id) =>
      (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Tanpa peduli huruf besar/kecil.
  Future<TagRow?> findByName(String name) =>
      (select(tags)
            ..where((t) => t.name.lower().equals(name.trim().toLowerCase())))
          .getSingleOrNull();

  Future<int> insertTag(TagsCompanion t) => into(tags).insert(t);

  Future<void> updateTag(int id, TagsCompanion t) =>
      (update(tags)..where((x) => x.id.equals(id))).write(t);

  /// Menghapus tag dan melepasnya dari semua barang.
  Future<void> deleteTag(int id) => transaction(() async {
    await (delete(productTags)..where((pt) => pt.tagId.equals(id))).go();
    await (delete(tags)..where((t) => t.id.equals(id))).go();
  });

  /// Mengganti semua tag barang [productId] dengan [tagIds].
  Future<void> setProductTags(int productId, Iterable<int> tagIds) =>
      transaction(() async {
        await (delete(
          productTags,
        )..where((pt) => pt.productId.equals(productId))).go();
        for (final id in tagIds.toSet()) {
          await into(productTags).insert(
            ProductTagsCompanion.insert(productId: productId, tagId: id),
          );
        }
      });

  /// Id tag dengan nama-nama itu; yang belum ada dibuat (warna [color]).
  Future<List<int>> idsForNames(
    Iterable<String> names, {
    String color = 'blue',
  }) async {
    final ids = <int>[];
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      final existing = await findByName(n);
      ids.add(
        existing?.id ??
            await insertTag(TagsCompanion.insert(name: n, color: Value(color))),
      );
    }
    return ids.toSet().toList();
  }
}
