import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/data/tag_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/tag.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late AppUser admin;
  late AppUser kasir;
  late TagRepository tags;
  late ProductRepository products;

  setUp(() async {
    db = await createSeededDb();
    final auth = AuthRepository(db, testHasher);
    admin = await auth.login('admin', 'admin123');
    kasir = await auth.login('kasir', 'kasir123');
    tags = TagRepository(db);
    products = ProductRepository(db);
  });

  tearDown(() => db.close());

  Future<Product> saveWithTags(String code, List<String>? tagNames) =>
      products.save(
        actor: admin,
        draft: ProductDraft(
          code: code,
          name: 'Barang $code',
          sellingPrice: 1000,
          tagNames: tagNames,
        ),
      );

  test('kelola tag: tambah, nama unik, ubah, hapus (khusus admin)', () async {
    expect(
      () => tags.save(actor: kasir, name: 'Mainan', color: TagColor.blue),
      throwsA(isA<TagFailure>()),
    );
    final mainan = await tags.save(
      actor: admin,
      name: ' Mainan ',
      color: TagColor.pink,
    );
    expect(mainan.name, 'Mainan');
    expect(
      () => tags.save(actor: admin, name: 'MAINAN', color: TagColor.blue),
      throwsA(isA<TagFailure>()),
    );
    expect(
      () => tags.save(actor: admin, name: 'A, B', color: TagColor.blue),
      throwsA(isA<TagFailure>()),
    );

    await tags.save(
      actor: admin,
      id: mainan.id,
      name: 'Mainan Anak',
      color: TagColor.green,
    );
    final list = await tags.watchAll().first;
    expect(list.single.name, 'Mainan Anak');
    expect(list.single.color, TagColor.green);
  });

  test(
    'barang dengan banyak tag; tag baru dibuat otomatis; urut nama',
    () async {
      await tags.save(actor: admin, name: 'Mainan', color: TagColor.pink);
      final p = await saveWithTags('T1', ['Mainan', 'Boneka', 'mainan']);
      expect(p.tags.map((t) => t.name), ['Boneka', 'Mainan']);
      expect(p.tags.last.color, TagColor.pink);

      // tagNames null = tag tidak diubah; list kosong = semua dilepas.
      final kept = await saveWithTags('T1X', null);
      expect(kept.tags, isEmpty);
      final again = await products.save(
        actor: admin,
        id: p.id,
        draft: const ProductDraft(
          code: 'T1',
          name: 'Barang T1',
          sellingPrice: 1,
        ),
      );
      expect(again.tags.map((t) => t.name), ['Boneka', 'Mainan']);
      final cleared = await products.save(
        actor: admin,
        id: p.id,
        draft: const ProductDraft(
          code: 'T1',
          name: 'Barang T1',
          sellingPrice: 1,
          tagNames: [],
        ),
      );
      expect(cleared.tags, isEmpty);
    },
  );

  test('filter per tag, jumlah barang per tag, hapus tag & barang', () async {
    await saveWithTags('A1', ['Mainan', 'Boneka']);
    await saveWithTags('A2', ['Mainan']);
    await saveWithTags('A3', ['Alat Tulis']);
    final all = await tags.watchAll().first;
    final byName = {for (final t in all) t.name: t};
    expect(all.map((t) => t.name), ['Alat Tulis', 'Boneka', 'Mainan']);
    expect(byName['Mainan']!.productCount, 2);

    final mainan = await products.allMatching(
      ProductFilter(tagId: byName['Mainan']!.id),
    );
    expect(mainan.map((p) => p.code).toSet(), {'A1', 'A2'});

    // Hapus tag: dilepas dari barang, barangnya tetap ada.
    await tags.remove(actor: admin, id: byName['Boneka']!.id);
    final a1 = (await products.findByCodeOrBarcode('A1'))!;
    expect(a1.tags.map((t) => t.name), ['Mainan']);

    // Hapus barang (belum terjual): tautan tag ikut terhapus.
    await products.remove(actor: admin, id: a1.id);
    final after = await tags.watchAll().first;
    expect(after.firstWhere((t) => t.name == 'Mainan').productCount, 1);
  });

  test('daftar barang ikut terbarui saat tag diganti nama', () async {
    final p = await saveWithTags('W1', ['Mainan']);
    final stream = products.watchPage(
      const ProductFilter(text: 'W1'),
      page: 0,
      pageSize: 10,
    );
    final names = <String>[];
    final sub = stream.listen(
      (list) => names.add(list.single.tags.single.name),
    );
    await pumpEventQueue();
    await tags.save(
      actor: admin,
      id: p.tags.single.id,
      name: 'Mainan Anak',
      color: TagColor.blue,
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(names, ['Mainan', 'Mainan Anak']);
  });

  test('TagRules.split memecah kolom Tag di file', () {
    expect(TagRules.split(' Mainan, Boneka ;Anak,, '), [
      'Mainan',
      'Boneka',
      'Anak',
    ]);
  });
}
