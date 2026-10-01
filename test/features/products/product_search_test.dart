import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/products/data/product_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository repo;

  setUp(() async {
    db = await createSeededDb();
    repo = ProductRepository(db);
  });

  tearDown(() => db.close());

  Future<List<String>> search(String q) async =>
      (await repo.search(q)).map((p) => p.name).toList();
  Future<List<String>> suggest(String q) async =>
      (await repo.suggest(q)).map((p) => p.name).toList();

  test('pencarian per kata, urutan bebas', () async {
    expect(await search('goreng indomie'), ['Indomie Goreng 85g']);
    expect(await search('botol'), [
      'Aqua Botol 600ml',
      'Teh Botol Sosro 450ml',
    ]);
  });

  test('karakter % dan _ tidak menjadi wildcard', () async {
    expect(await search('%'), isEmpty);
    expect(await search('_'), isEmpty);
  });

  test(
    'salah ketik tidak ketemu di pencarian biasa, tapi muncul di saran',
    () async {
      expect(await search('indomei'), isEmpty);
      expect((await suggest('indomei')).take(2), [
        'Indomie Goreng 85g',
        'Indomie Ayam Bawang 69g',
      ]);
      expect((await suggest('lifeboy')).first, 'Sabun Lifebuoy 110g');
      expect((await suggest('pantine')).first, 'Shampoo Pantene 170ml');
    },
  );

  test('barang nonaktif tidak disarankan', () async {
    await (db.update(db.products)..where((p) => p.code.equals('BRG009'))).write(
      const ProductsCompanion(isActive: Value(false)),
    );
    expect(await suggest('aqau'), isNot(contains('Aqua Botol 600ml')));
  });

  test('query pendek atau tidak mirip tidak memberi saran', () async {
    expect(await suggest('aq'), isEmpty);
    expect(await suggest('kulkas'), isEmpty);
  });
}
