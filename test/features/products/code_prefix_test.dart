import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/data/tag_repository.dart';
import 'package:toko/features/products/domain/code_prefix.dart';
import 'package:toko/features/products/domain/code_sequence.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/tag.dart';

import '../../helpers/test_app.dart';

void main() {
  group('CodePrefix', () {
    test('validasi: huruf di depan, tidak diakhiri angka', () {
      expect(CodePrefix.validate(null), isNull);
      expect(CodePrefix.validate(' bnk '), isNull);
      expect(CodePrefix.normalize(' bnk '), 'BNK');
      expect(CodePrefix.validate('B'), contains('minimal'));
      expect(CodePrefix.validate('BNK1'), contains('angka'));
      expect(CodePrefix.validate('1AB'), isNotNull);
      expect(CodePrefix.validate('ABCDEFGHI'), contains('maksimal'));
    });

    test('saran dari nama kategori', () {
      expect(CodePrefix.suggest('Boneka').first, 'BNK');
      expect(CodePrefix.suggest('Minuman').first, 'MNM');
      expect(CodePrefix.suggest('Alat Tulis Kantor').first, 'ATK');
      expect(CodePrefix.suggest('Kopi').first, 'KPO');
      expect(CodePrefix.suggest('Boneka'), hasLength(3));
      // Yang sudah dipakai dilewati.
      expect(CodePrefix.suggest('Boneka', taken: ['BNK']).first, 'BON');
      expect(CodePrefix.suggest(''), isEmpty);
    });

    test('saran pertama = awalan yang sudah dipakai barang kategori itu', () {
      expect(
        CodePrefix.suggest(
          'Boneka',
          categoryCodes: ['TOY01', 'TOY02', 'X9'],
        ).first,
        'TOY',
      );
    });
  });

  test('jumlah digit per kategori', () {
    expect(
      CodeSequence.next(['BRG001'], fixedPrefix: 'BNK', minWidth: 4)!.next,
      'BNK0001',
    );
    // Seri lama lebih pendek: nomor berikutnya memakai digit yang diatur.
    expect(
      CodeSequence.next(['BNK01'], fixedPrefix: 'BNK', minWidth: 4)!.next,
      'BNK0002',
    );
    // Seri lama lebih panjang: tetap mengikuti seri.
    expect(
      CodeSequence.next(['BNK00001'], fixedPrefix: 'BNK', minWidth: 4)!.next,
      'BNK00002',
    );
  });

  test('awalan tetap: nomor pertama, lalu isi celah', () {
    expect(CodeSequence.next(['BRG001'], fixedPrefix: 'BNK')!.next, 'BNK001');
    final r = CodeSequence.next(
      ['BNK001', 'BNK004', 'BRG020'],
      fixedPrefix: 'BNK',
      category: 'Boneka',
    )!;
    expect(r.next, 'BNK002');
    expect(r.note, 'Mengisi nomor kosong setelah BNK001 · kategori Boneka');
    expect(
      CodeSequence.next([], fixedPrefix: 'BNK', category: 'Boneka')!.note,
      'Nomor pertama · kategori Boneka',
    );
  });

  test('kategori dengan awalan: barcode otomatis + awalan unik', () async {
    final db = await createSeededDb();
    addTearDown(db.close);
    final admin = await AuthRepository(
      db,
      testHasher,
    ).login('admin', 'admin123');
    final tags = TagRepository(db);
    final boneka = await tags.save(
      actor: admin,
      name: 'Boneka',
      color: TagColor.pink,
      codePrefix: 'bnk',
    );
    expect(boneka.codePrefix, 'BNK');
    await expectLater(
      tags.save(
        actor: admin,
        id: boneka.id,
        name: 'Boneka',
        color: TagColor.pink,
        codePrefix: 'BNK',
        codeDigits: 1,
      ),
      throwsA(isA<TagFailure>()),
    );
    expect(
      () => tags.save(
        actor: admin,
        name: 'Mainan',
        color: TagColor.blue,
        codePrefix: 'BNK',
      ),
      throwsA(isA<TagFailure>()),
    );
    // Saran tidak menawarkan BNK (dipakai Boneka) atau BRG (barang contoh).
    final s = await tags.suggestPrefixes('Bonsai');
    expect(s, isNot(contains('BNK')));
    expect(s, isNot(contains('BRG')));

    final products = ProductRepository(db);
    final first = await products.nextCode(categories: ['boneka']);
    // Lebar digit mengikuti seri terbaru (BRG001 = 3 digit).
    expect(first?.next, 'BNK001');
    await products.save(
      actor: admin,
      draft: const ProductDraft(
        code: 'BNK001',
        name: 'Boneka Beruang',
        sellingPrice: 50000,
        tagNames: ['Boneka'],
      ),
    );
    expect((await products.nextCode(categories: ['Boneka']))?.next, 'BNK002');
  });

  test('v16 → v17: kolom awalan barcode kategori', () async {
    final schema = File('test/fixtures/schema_v16.sql').readAsStringSync();
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (Database raw) {
          for (final stmt in schema.split(';\n')) {
            if (stmt.trim().isNotEmpty) raw.execute(stmt);
          }
          raw.execute(
            "INSERT INTO tags (name, color, uuid) VALUES ('Lama', 'red', 't')",
          );
          raw.userVersion = 16;
        },
      ),
    );
    addTearDown(db.close);
    final tag = (await db.select(db.tags).get()).single;
    expect(tag.name, 'Lama');
    expect(tag.codePrefix, isNull);
  });

  test(
    'kategori dengan jumlah digit: barcode otomatis memakai lebarnya',
    () async {
      final db = await createSeededDb();
      addTearDown(db.close);
      final admin = await AuthRepository(
        db,
        testHasher,
      ).login('admin', 'admin123');
      await TagRepository(db).save(
        actor: admin,
        name: 'Alat Tulis',
        color: TagColor.blue,
        codePrefix: 'ATK',
        codeDigits: 5,
      );
      expect(
        (await ProductRepository(db).nextCode(categories: ['Alat Tulis']))
            ?.next,
        'ATK00001',
      );
    },
  );
}
