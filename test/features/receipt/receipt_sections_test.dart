import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/receipt/domain/default_receipt_html.dart';
import 'package:toko/features/receipt/domain/receipt.dart';
import 'package:toko/features/receipt/domain/receipt_html.dart';
import 'package:toko/features/receipt/domain/receipt_template.dart';
import 'package:toko/features/sales/domain/split_payment.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  const custom = '<div>{{toko.nama}}</div><div>TOTAL {{total}}</div>';

  ReceiptData data({bool isReturn = false, bool split = false}) => ReceiptData(
    storeName: 'Toko Utama',
    invoiceNo: isReturn ? 'RET-K01-20261016-0001' : 'INV-K01-20261016-0001',
    date: DateTime(2026, 10, 16, 10),
    cashierName: 'Kasir',
    items: const [],
    subtotal: isReturn ? -7000 : 21000,
    total: isReturn ? -7000 : 21000,
    paid: isReturn ? -7000 : 25000,
    change: isReturn ? 0 : 4000,
    paymentMethod: split ? 'Tunai + QRIS' : 'Tunai',
    returnOf: isReturn ? 'INV-K01-20261016-0009' : null,
    returnReason: isReturn ? 'Rusak' : null,
    payments: split
        ? const [
            SalePart(
              name: 'Tunai',
              amount: 6000,
              isCash: true,
              tendered: 10000,
            ),
            SalePart(name: 'QRIS', amount: 15000, isCash: false, ref: 'Q-1'),
          ]
        : const [],
  );

  test('bagian yang belum ada di template', () {
    expect(ReceiptSections.missing(defaultReceiptHtml), isEmpty);
    expect(ReceiptSections.missing(custom), ['nota retur', 'bayar terpisah']);
  });

  test('template buatan admin: nota retur diberi judul, bayar terpisah '
      'diberi rincian; struk biasa tidak berubah', () {
    String render(ReceiptData d) => ReceiptHtml.render(
      ReceiptSections.withFallbacks(custom),
      d.toTemplateValues(),
    );
    final normal = render(data());
    expect(normal, isNot(contains('NOTA RETUR')));
    expect(normal, isNot(contains('QRIS')));

    final ret = render(data(isReturn: true));
    expect(ret, contains('NOTA RETUR'));
    expect(ret, contains('INV-K01-20261016-0009'));
    expect(ret, contains('Rusak'));
    expect(ret, contains('7.000'));

    final split = render(data(split: true));
    expect(split, contains('QRIS'));
    expect(split, contains('15.000'));
    expect(split, contains('Ref: Q-1'));
    // Template yang sudah lengkap tidak diubah.
    expect(
      ReceiptSections.withFallbacks(defaultReceiptHtml),
      defaultReceiptHtml,
    );
  });

  test('v17 → v18: tabel catatan aktivitas komputer lain', () async {
    final schema = File('test/fixtures/schema_v17.sql').readAsStringSync();
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (Database raw) {
          for (final stmt in schema.split(';\n')) {
            if (stmt.trim().isNotEmpty) raw.execute(stmt);
          }
          raw.userVersion = 17;
        },
      ),
    );
    addTearDown(db.close);
    expect(await db.select(db.remoteAuditLog).get(), isEmpty);
  });
}
