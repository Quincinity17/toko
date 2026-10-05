import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/widgets/app_button.dart';
import 'package:toko/core/widgets/app_sidebar.dart';
import 'package:toko/core/widgets/large_title_page.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/user_role.dart';
import 'package:toko/features/backup/presentation/backup_section.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/receipt/data/printer_transport.dart';
import 'package:toko/features/receipt/data/receipt_renderer.dart';
import 'package:toko/features/receipt/data/receipt_settings_repository.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/products/domain/bulk_entry.dart';
import 'package:toko/features/products/presentation/product_bulk_entry_page.dart';
import 'package:toko/features/products/presentation/product_import_page.dart';

import 'helpers/app_harness.dart';
import 'helpers/fake_printer.dart';
import 'helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('Login membedakan admin dan kasir', (tester) async {
    await pumpApp(tester);

    // Tidak ada daftar akun di layar login.
    expect(find.text('Masuk ke Toko'), findsOneWidget);
    expect(find.text('Administrator'), findsNothing);
    expect(find.text('Kasir Satu'), findsNothing);
    expect(find.textContaining('admin123'), findsNothing);

    // Password salah: tetap di login dan muncul pesan.
    await login(tester, 'kasir', 'salah');
    expect(find.text('Username atau password salah.'), findsOneWidget);

    // Kasir masuk ke layar kasir; menu admin tidak tampil.
    await login(tester, 'kasir', 'kasir123');
    expect(find.text('Belum ada barang'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Produk'), findsNothing);
    expect(find.text('Pengaturan'), findsOneWidget); // versi ringkas

    // Keluar lewat menu user di sidebar.
    await tester.tap(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Kasir Satu'),
      ),
    );
    await settle(tester);
    expect(find.text('Ganti Password'), findsNothing); // khusus admin
    await tester.tap(find.text('Keluar'));
    await settle(tester);
    expect(find.text('Masuk ke Toko'), findsOneWidget);

    // Admin masuk ke dashboard dengan menu lengkap.
    await login(tester, 'admin', 'admin123');
    expect(find.text('Omzet hari ini'), findsOneWidget);
    expect(find.text('Produk'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Admin menambah akun kasir lalu akun itu bisa login', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');

    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await tester.tap(find.text('Kelola Akun'));
    await settle(tester);
    expect(find.text('Kasir Satu'), findsOneWidget);

    await tester.tap(find.text('Tambah Akun'));
    await settle(tester);
    await fill(tester, 'Nama lengkap', 'Siti Aminah');
    await fill(tester, 'Username', 'siti');
    await fill(tester, 'Password', 'rahasia1');
    await fill(tester, 'Ulangi password', 'rahasia1');
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Akun').last);
    await settle(tester);

    // Sheet tertutup dan akun baru muncul di daftar.
    expect(find.text('Akun Baru'), findsNothing);
    expect(find.text('Siti Aminah'), findsOneWidget);

    // Keluar, lalu masuk sebagai akun baru.
    await tester.tap(find.text('Administrator'));
    await settle(tester);
    await tester.tap(find.text('Keluar'));
    await settle(tester);
    await login(tester, 'siti', 'rahasia1');
    expect(find.text('Belum ada barang'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Kasir scan, bayar tunai dan QRIS', (tester) async {
    final db = await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');

    Future<void> scan(String code) async {
      await fill(tester, 'Barcode', code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
    }

    // Scan kode dan barcode; barang yang sama digabung.
    await scan('BRG001');
    await scan('brg001');
    final barcodeAqua = (await tester.runAsync(
      () => (db.select(
        db.products,
      )..where((p) => p.code.equals('BRG009'))).getSingle(),
    ))!.barcode!;
    await scan(barcodeAqua);

    expect(find.text('Indomie Goreng 85g'), findsOneWidget);
    expect(find.text('Aqua Botol 600ml'), findsOneWidget);
    // 2 × 3.500 + 3.500 = 10.500
    expect(find.text('Rp 10.500'), findsWidgets);

    // Fitur voucher sudah dihapus (F4 sekarang = tahan transaksi).
    expect(find.textContaining('Voucher'), findsNothing);

    // F2 membuka popup pembayaran; Tunai terpilih otomatis.
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    expect(find.text('Pembayaran'), findsOneWidget);
    expect(find.text('QRIS'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, '20000');
    await settle(tester);
    expect(find.text('Rp 9.500'), findsOneWidget); // kembalian
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('Transaksi Berhasil'), findsOneWidget);
    expect(find.textContaining('INV-'), findsOneWidget);
    await tester.tap(find.textContaining('Transaksi Baru  (Enter)'));
    await settle(tester);
    expect(find.text('Belum ada barang'), findsOneWidget);

    // Transaksi kedua dibayar QRIS (non-tunai, bayar pas).
    await scan('BRG010');
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    await tester.tap(find.text('QRIS'));
    await settle(tester);
    expect(find.textContaining('No. referensi'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'QR-77');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.textContaining('QRIS'), findsWidgets);
    await tester.tap(find.textContaining('Transaksi Baru  (Enter)'));
    await settle(tester);

    // Tab Hari Ini hanya berisi daftar (tanpa kartu ringkasan omzet).
    await tester.tap(find.text('Hari Ini'));
    await settle(tester);
    expect(find.textContaining('INV-'), findsNWidgets(2));
    expect(find.text('QRIS'), findsOneWidget);
    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('Omzet Hari Ini'), findsNothing);

    // Stok Toko Utama berkurang.
    final indomie = (await tester.runAsync(() async {
      final p = await (db.select(
        db.products,
      )..where((p) => p.code.equals('BRG001'))).getSingle();
      return db.storesDao.entry(await mainStoreId(db), p.id);
    }))!;
    expect(indomie.stock, 118);

    await unmount(tester);
  });

  testWidgets('Admin membatalkan faktur dari tab Hari Ini (nota retur)', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Kasir'),
      ),
    );
    // Toko admin (satu-satunya toko) dimuat async dari settings.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);

    await fill(tester, 'Barcode', 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done); // uang pas
    await settle(tester);
    await tester.tap(find.textContaining('Transaksi Baru  (Enter)'));
    await settle(tester);

    await tester.tap(find.text('Hari Ini'));
    await settle(tester);
    await tester.tap(find.textContaining('INV-'));
    await settle(tester);
    await tapVisible(tester, find.text('Retur / Batalkan'));
    await settle(tester);
    expect(find.textContaining('Terjual 1'), findsOneWidget);
    // Belum memilih barang: tombol simpan belum aktif.
    expect(find.text('Pilih barang'), findsOneWidget);

    await tester.tap(find.text('Batalkan Semua'));
    await settle(tester);
    await fill(tester, 'Alasan', 'Pelanggan batal');
    await settle(tester);
    await tester.tap(find.text('Kembalikan Rp 3.500'));
    await settle(tester);
    expect(find.text('Retur tersimpan'), findsOneWidget);
    expect(find.textContaining('RET-'), findsWidgets); // popup + daftar
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(find.text('Nota retur'), findsOneWidget);
    expect(find.text('Dibatalkan'), findsOneWidget);
    expect(find.text('-Rp 3.500'), findsOneWidget);
    final stock = (await tester.runAsync(() async {
      final p = await (db.select(
        db.products,
      )..where((p) => p.code.equals('BRG001'))).getSingle();
      return db.storesDao.entry(await mainStoreId(db), p.id);
    }))!;
    expect(stock.stock, 120); // kembali

    await unmount(tester);
  });

  testWidgets('Batal transaksi kasir tercatat di Laporan › Aktivitas', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');
    await fill(tester, 'Barcode', 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.tap(find.text('Batalkan Transaksi'));
    await settle(tester);
    await tester.tap(find.text('Batalkan').last);
    await settle(tester);
    expect(find.text('Belum ada barang'), findsOneWidget);

    // Admin memeriksa.
    await tester.tap(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Kasir Satu'),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Keluar'));
    await settle(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Laporan'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(LargeTitlePage),
        matching: find.text('Aktivitas'),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    expect(find.text('Data utuh'), findsOneWidget);
    expect(find.text('Kasir Satu'), findsWidgets);
    expect(find.textContaining('Batal transaksi: 1 barang'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Kasir menahan transaksi lalu melanjutkannya', (tester) async {
    final db = await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');

    Future<void> scan(String code) async {
      await fill(tester, 'Barcode', code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
    }

    String? heldCount() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('held-count')),
            matching: find.byType(Text),
          ),
        )
        .data;

    // Ibu A: 2 barang, lalu ditahan dengan catatan (F4).
    await scan('BRG001');
    await scan('BRG009');
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await settle(tester);
    expect(find.text('Tahan Transaksi'), findsWidgets);
    await fill(tester, 'Catatan (opsional)', 'Ibu A baju merah');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('Belum ada barang'), findsOneWidget);
    expect(heldCount(), '1');

    // Ibu B dilayani dulu, lalu daftar tertahan dibuka (F5) dan Ibu A
    // dilanjutkan: keranjang Ibu B ikut ditahan.
    await scan('BRG010');
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await settle(tester);
    expect(find.text('Ibu A baju merah'), findsOneWidget);
    expect(find.textContaining('Indomie Goreng 85g, Aqua'), findsOneWidget);
    await tester.tap(find.text('Lanjutkan'));
    await settle(tester);
    expect(find.text('Tahan keranjang sekarang?'), findsOneWidget);
    await tester.tap(find.text('Tahan & Lanjutkan'));
    await settle(tester);

    expect(find.text('Indomie Goreng 85g'), findsOneWidget);
    expect(find.text('Aqua Botol 600ml'), findsOneWidget);
    expect(heldCount(), '1');
    final held = (await tester.runAsync(() => db.select(db.heldCarts).get()))!;
    expect(held.single.note, isNull);
    expect(held.single.itemCount, 1);

    await unmount(tester);
  });

  testWidgets('Supervisor hanya Kasir + Stok, dan bisa menambah stok', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.runAsync(() async {
      final admin = await AuthRepository(
        db,
        testHasher,
      ).login('admin', 'admin123');
      await UserRepository(db, testHasher).create(
        actor: admin,
        username: 'budi',
        fullName: 'Budi Supervisor',
        role: UserRole.supervisor,
        storeId: await mainStoreId(db),
        password: 'rahasia1',
      );
    });
    await login(tester, 'budi', 'rahasia1');

    // Mulai di Kasir; menu hanya Kasir dan Stok, toko tampil di sidebar.
    expect(find.text('Barcode'), findsWidgets); // isian + kolom keranjang
    final sidebar = find.byType(AppSidebar);
    expect(
      find.descendant(of: sidebar, matching: find.text('Stok')),
      findsOneWidget,
    );
    expect(find.text('Produk'), findsNothing);
    expect(find.text('Laporan'), findsNothing);
    expect(
      find.descendant(of: sidebar, matching: find.text('Toko Utama')),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: sidebar, matching: find.text('Stok')));
    await settle(tester);
    expect(find.text('Indomie Goreng 85g'), findsOneWidget);
    expect(find.text('120 PCS'), findsOneWidget);

    // Barang masuk 10 → 130.
    await tester.tap(find.text('Indomie Goreng 85g'));
    await settle(tester);
    expect(find.text('Stok sekarang'), findsOneWidget);
    await fill(tester, 'Jumlah masuk (PCS)', '10');
    await fill(tester, 'Catatan (opsional)', 'kiriman supplier');
    await settle(tester);
    expect(find.text('Stok menjadi 130 PCS'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('Stok sekarang'), findsNothing);
    expect(find.text('130 PCS'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Nama salah ketik di kasir menampilkan saran yang mendekati', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');

    // Ketik nama (bukan kode) dengan salah ketik di kolom kode, lalu Enter.
    await fill(tester, 'Barcode', 'chitatoo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('Cari Barang'), findsOneWidget);
    expect(
      find.textContaining('Mungkin maksud Anda', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Chitato Sapi Panggang 68g'), findsOneWidget);

    // Enter memilih saran teratas dan memasukkannya ke keranjang.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.text('Cari Barang'), findsNothing);
    expect(find.text('Chitato Sapi Panggang 68g'), findsOneWidget);
    expect(find.text('Belum ada barang'), findsNothing);

    await unmount(tester);
  });

  testWidgets('Barang baru: barcode otomatis lanjut dari yang terakhir', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Tambah'));
    await settle(tester);

    await tester.tap(find.text('Otomatis (+1 dari barcode terakhir)'));
    await settle(tester);
    // Barang contoh terakhir: BRG020.
    expect(find.text('BRG021'), findsOneWidget);
    expect(find.text('Lanjutan dari BRG020'), findsOneWidget);

    // Untung % mengisi harga jual (dibulatkan ke atas ke Rp 100).
    final before = find.text('3.400').evaluate().length;
    await fill(tester, 'Harga beli (opsional)', '2800');
    await settle(tester);
    await fill(tester, 'Untung (%)', '20');
    await settle(tester);
    // Harga jual + placeholder harga per toko (= harga default).
    expect(find.text('3.400').evaluate().length, greaterThan(before));

    await unmount(tester);
  });

  testWidgets('Input Tabel: banyak barang sekaligus + barcode otomatis', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Input Tabel'));
    await settle(tester);

    final cells = find.descendant(
      of: find.byType(ProductBulkEntryPage),
      matching: find.byType(EditableText),
    );
    Future<void> type(int row, BulkColumn col, String text) async {
      await tester.enterText(
        cells.at(row * BulkColumn.values.length + col.index),
        text,
      );
      await tester.pump();
    }

    await type(0, BulkColumn.name, 'Boneka Beruang');
    await type(0, BulkColumn.purchasePrice, '20000');
    await type(0, BulkColumn.markup, '25');
    // Harga jual terisi dari Untung %.
    expect(find.text('25.000'), findsOneWidget);
    await type(1, BulkColumn.name, 'Mobil Remote');
    await type(1, BulkColumn.sellingPrice, '150000');

    await tester.tap(find.widgetWithText(AppButton, 'Barcode Otomatis'));
    await settle(tester);
    expect(find.text('BRG021'), findsOneWidget);
    expect(find.text('BRG022'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('2 barang tersimpan'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Boneka Beruang'), findsNothing); // tabel dikosongkan

    final saved = await tester.runAsync(
      () => ProductRepository(db).findByCodeOrBarcode('BRG021'),
    );
    expect(saved!.name, 'Boneka Beruang');
    expect(saved.sellingPrice, 25000);
    expect(saved.unitName, 'PCS');

    // Nama mirip barang yang sudah ada → peringatan sebelum menyimpan.
    await type(0, BulkColumn.name, 'Indomie Goreng');
    await type(0, BulkColumn.code, 'BMM0000001');
    await type(0, BulkColumn.sellingPrice, '3500');
    await tester.tap(find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('Nama mirip'), findsOneWidget);
    await tester.tap(find.text('Periksa Lagi'));
    await settle(tester);
    expect(
      find.text('Mirip dengan Indomie Goreng 85g (BRG001)'),
      findsOneWidget,
    );
    // Simpan lagi tanpa mengubah nama: tidak diperingatkan dua kali.
    await tester.tap(find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('1 barang tersimpan'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await settle(tester);

    // Keluar dengan isian belum disimpan → simpan sebagai draf → lanjutkan.
    await type(0, BulkColumn.name, 'Kereta Api Mainan');
    await tester.tap(
      find
          .descendant(
            of: find.byType(LargeTitlePage),
            matching: find.text('Produk'),
          )
          .first, // tombol kembali "‹ Produk"
    );
    await settle(tester);
    await tester.tap(find.text('Simpan sebagai Draf'));
    await settle(tester);
    expect(find.byType(ProductBulkEntryPage), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.tap(find.widgetWithText(AppButton, 'Input Tabel'));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
    expect(find.text('Kereta Api Mainan'), findsOneWidget);
    expect(find.text('Melanjutkan draf (1 baris)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Barang baru dengan nama mirip: diperingatkan saat simpan', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Tambah'));
    await settle(tester);
    await fill(tester, 'Nama barang', 'Aqua Botol 600 ml');
    await fill(tester, 'Barcode', 'BMM0000001');
    await fill(tester, 'Harga jual (Rp)', '3500');
    await tapVisible(tester, find.widgetWithText(AppButton, 'Simpan Barang'));
    await settle(tester);
    expect(find.text('Nama mirip'), findsOneWidget);
    expect(
      find.textContaining('Aqua Botol 600ml (BRG009)', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Tetap Simpan'));
    await settle(tester);
    expect(find.text('Barang Baru'), findsNothing); // form tertutup

    await unmount(tester);
  });

  testWidgets('Admin mengelola barang di halaman Produk', (tester) async {
    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);

    expect(find.textContaining('20 barang · '), findsOneWidget);
    expect(find.text('Indomie Goreng 85g'), findsOneWidget);

    // Cari (urutan kata bebas).
    await tester.enterText(find.byType(CupertinoSearchTextField), 'goreng');
    await settle(tester);
    expect(find.text('Indomie Goreng 85g'), findsOneWidget);
    expect(find.text('Minyak Goreng Bimoli 2L'), findsOneWidget);
    expect(find.text('Aqua Botol 600ml'), findsNothing);

    // Salah ketik → saran.
    await tester.enterText(find.byType(CupertinoSearchTextField), 'indomei');
    await settle(tester);
    expect(find.text('MUNGKIN MAKSUD ANDA'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoSearchTextField), '');
    await settle(tester);

    // Tambah barang baru.
    await tester.tap(find.widgetWithText(AppButton, 'Tambah'));
    await settle(tester);
    await fill(tester, 'Nama barang', 'Kecap Bango 220ml');
    await fill(tester, 'Barcode', 'BRG100');
    await fill(tester, 'Harga beli (opsional)', '9000');
    await fill(tester, 'Harga jual (Rp)', '11000');
    await fill(tester, 'Stok', '2');
    await fill(tester, 'Stok minimum (opsional)', '5');
    await settle(tester);
    expect(find.textContaining('Untung Rp 2.000'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Simpan Barang'));
    await settle(tester);
    expect(find.text('Barang Baru'), findsNothing);
    expect(find.textContaining('21 barang · '), findsOneWidget);

    // Filter stok menipis memuat barang baru (2 ≤ 5).
    await tester.tap(find.text('Stok menipis'));
    await settle(tester);
    expect(find.text('Kecap Bango 220ml'), findsOneWidget);
    expect(find.textContaining('4 barang · '), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Admin import barang dari file gaya iPOS', (tester) async {
    const csv =
        'Kode Item,Nama Item,Jenis,Satuan,Harga Pokok,Harga Jual 1,Stok\n'
        'BRG001,Indomie Goreng,Makanan,PCS,2900,3700,150\n'
        'IPOS1,Kopi Kenangan,Minuman,BTL,8000,10000,24\n'
        'IPOS2,Roti Aoka,Roti,PCS,1500,,10\n'
        'IPOS3,Aqua Botol 600 ml,Minuman,BTL,2800,3500,12\n';
    await pumpApp(
      tester,
      overrides: [
        pickImportFileProvider.overrideWithValue(
          () async => (Uint8List.fromList(utf8.encode(csv)), 'ipos.csv'),
        ),
      ],
    );
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Import'));
    await settle(tester);
    expect(find.text('Import Barang'), findsWidgets);

    // Pilih file (pembacaan file berjalan di isolate → butuh waktu nyata).
    await tester.tap(find.widgetWithText(AppButton, 'Pilih File'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await settle(tester);
    expect(find.text('COCOKKAN KOLOM'), findsOneWidget);
    expect(find.text('Kode Item'), findsOneWidget); // tebakan otomatis
    expect(find.text('Harga Jual 1'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(AppButton, 'Periksa Data'));
    await settle(tester);
    expect(find.text('Barang baru'), findsOneWidget);
    expect(find.text('Baris 4'), findsOneWidget); // harga jual kosong
    // Nama mirip barang yang sudah ada: peringatan, tetap di-import.
    expect(find.text('Mirip dengan Aqua Botol 600ml (BRG009)'), findsOneWidget);

    await tapVisible(tester, find.text('Update stok & harga saja'));
    await settle(tester);
    await tapVisible(tester, find.widgetWithText(AppButton, 'Import 3 barang'));
    await settle(tester);
    expect(find.text('Import selesai'), findsOneWidget);
    expect(find.text('3 barang tersimpan'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(AppButton, 'Lihat Produk'));
    await settle(tester);
    expect(find.textContaining('22 barang · '), findsOneWidget);
    expect(find.text('Kopi Kenangan'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Dashboard admin menampilkan transaksi dari kasir', (
    tester,
  ) async {
    await pumpApp(tester);

    // Kasir menjual 2 Indomie (Rp 7.000, laba 2 × 700).
    await login(tester, 'kasir', 'kasir123');
    await fill(tester, 'Barcode', 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await fill(tester, 'Barcode', 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done); // uang pas
    await settle(tester);
    await tester.tap(find.textContaining('Transaksi Baru  (Enter)'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Kasir Satu'),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Keluar'));
    await settle(tester);

    // Admin langsung melihatnya di dashboard.
    await login(tester, 'admin', 'admin123');
    expect(find.text('Rp 7.000'), findsWidgets);
    expect(find.text('Rp 1.400'), findsOneWidget); // laba kotor
    expect(find.text('Margin 20,0%'), findsOneWidget);
    expect(find.text('Indomie Goreng 85g'), findsOneWidget); // terlaris
    expect(find.text('Belum ada penjualan'), findsNothing);

    await unmount(tester);
  });

  testWidgets('Laporan: semua bagian tampil tanpa error', (tester) async {
    final db = await pumpApp(tester);
    // Satu transaksi supaya laporan tidak kosong.
    await tester.runAsync(() async {
      final kasir = await AuthRepository(
        db,
        testHasher,
      ).login('kasir', 'kasir123');
      final tunai = (await PaymentMethodRepository(db).watchAll().first).first;
      final indomie = (await ProductRepository(db)
          .findByCodeOrBarcode('BRG001'))!;
      await CheckoutService(db).checkout(
        cart: const Cart().add(indomie, qty: 3),
        cashier: kasir,
        storeId: await mainStoreId(db),
        paymentMethodId: tunai.id,
        paid: 20000,
      );
    });
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Laporan'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);

    expect(find.text('Omzet bersih'), findsOneWidget);
    expect(find.text('Rp 10.500'), findsWidgets);

    for (final section in [
      'Tren',
      'Produk',
      'Kategori',
      'Stok',
      'Pembayaran',
      'Kasir & Terminal',
      'Faktur',
    ]) {
      // Batasi ke halaman (bukan menu sidebar dengan nama sama, mis. Produk).
      await tester.tap(
        find.descendant(
          of: find.byType(LargeTitlePage),
          matching: find.text(section),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await settle(tester);
    }
    expect(find.textContaining('INV-K01-'), findsOneWidget);

    // Ganti rentang ke Hari Ini.
    await tester.tap(
      find.descendant(
        of: find.byType(LargeTitlePage),
        matching: find.text('Hari Ini'),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.textContaining('INV-K01-'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Admin mengubah template HTML struk: pratinjau ikut berubah', (
    tester,
  ) async {
    final transport = FakeTransport();
    final rasterizer = FakeRasterizer();
    final db = await pumpApp(
      tester,
      overrides: [
        printerTransportProvider.overrideWithValue(transport),
        receiptRasterizerProvider.overrideWithValue(rasterizer),
      ],
    );
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await tapVisible(tester, find.text('Struk & Printer'));
    await settle(tester);

    // Pratinjau template bawaan memakai data contoh.
    expect(
      find.textContaining('INV-K01-20261002-0001', findRichText: true),
      findsOneWidget,
    );

    final editor = find.descendant(
      of: find.byKey(const ValueKey('receipt-html-editor')),
      matching: find.byType(EditableText),
    );
    Future<void> typeTemplate(String html) async {
      await tester.enterText(editor, html);
      await settle(tester); // lewat jeda 400 ms
    }

    await typeTemplate(
      '<style>.t { font-weight: bold }</style>'
      '<p class="t">Halo {{kasir}} {{total}}</p>',
    );
    expect(
      find.textContaining('Halo Kasir 51.000', findRichText: true),
      findsOneWidget,
    );

    // Template rusak: pesan error, pratinjau terakhir tetap tampil.
    await typeTemplate('<p>{{#barang}}</p>');
    expect(find.textContaining('belum ditutup'), findsOneWidget);
    expect(
      find.textContaining('Halo Kasir 51.000', findRichText: true),
      findsOneWidget,
    );

    await typeTemplate('<p>Akhir {{faktur.no}}</p>');
    expect(find.textContaining('belum ditutup'), findsNothing);

    // Pilih printer terpasang lalu tes cetak memakai template itu.
    await tapCentered(tester, find.text('Terpasang (USB)'));
    await settle(tester);
    await tapCentered(tester, find.text('Pilih…'));
    await settle(tester);
    await tester.tap(find.text('Thermal 58'));
    await settle(tester);
    await tapCentered(tester, find.text('Tes Cetak'));
    await settle(tester);
    expect(find.text('Tes cetak terkirim.'), findsOneWidget);
    expect(transport.jobs, hasLength(1));
    expect(rasterizer.html.single, contains('Akhir INV-K01-20261002-0001'));

    final saved = (await tester.runAsync(() async {
      final repo = ReceiptSettingsRepository(db);
      return (
        await repo.templateFor(await mainStoreId(db)),
        await repo.printer(),
      );
    }))!;
    expect(saved.$1.html, '<p>Akhir {{faktur.no}}</p>');
    expect(saved.$2.connection, PrinterConnection.system);
    expect(saved.$2.printerName, 'Thermal 58');

    await unmount(tester);
  });

  testWidgets('Bayar tunai mencetak struk dan membuka laci', (tester) async {
    final transport = FakeTransport();
    final rasterizer = FakeRasterizer();
    final db = await pumpApp(
      tester,
      overrides: [
        printerTransportProvider.overrideWithValue(transport),
        receiptRasterizerProvider.overrideWithValue(rasterizer),
      ],
    );
    await tester.runAsync(
      () => db.settingsDao.set(
        ReceiptSettingsRepository.kPrinter,
        jsonEncode(
          const PrinterConfig(
            connection: PrinterConnection.system,
            printerName: 'Thermal 58',
          ).toJson(),
        ),
      ),
    );
    await login(tester, 'kasir', 'kasir123');
    await fill(tester, 'Barcode', 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    // Tombol buka laci tampil karena printer sudah diatur.
    expect(find.text('Buka Laci  (F6)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('Transaksi Berhasil'), findsOneWidget);
    expect(find.text('Struk dicetak'), findsOneWidget);
    expect(transport.jobs, hasLength(1));
    // ESC p (buka laci) ikut dikirim untuk pembayaran tunai.
    expect(transport.jobs.single.sublist(2, 4), [0x1B, 0x70]);
    expect(rasterizer.html.single, contains('Indomie Goreng 85g'));

    // Ctrl+P = cetak ulang.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(transport.jobs, hasLength(2));
    expect(rasterizer.html.last, contains('CETAK ULANG'));

    await unmount(tester);
  });

  testWidgets('Kasir mengatur printer nota dari layar Kasir', (tester) async {
    final transport = FakeTransport();
    final rasterizer = FakeRasterizer();
    final db = await pumpApp(
      tester,
      overrides: [
        printerTransportProvider.overrideWithValue(transport),
        receiptRasterizerProvider.overrideWithValue(rasterizer),
      ],
    );
    await login(tester, 'kasir', 'kasir123');
    // Printer diatur dari layar Kasir (bukan dari Pengaturan).
    await tester.tap(find.text('Atur Printer'));
    await settle(tester);
    expect(find.text('Printer Nota'), findsOneWidget);

    await tester.tap(find.text('Terpasang (USB)'));
    await settle(tester);
    await tester.tap(find.text('80 mm'));
    await settle(tester);
    await tester.tap(find.text('Pilih…'));
    await settle(tester);
    await tester.tap(find.text('Thermal 58'));
    await settle(tester);
    await tapVisible(tester, find.text('Tes Cetak'));
    await settle(tester);
    expect(find.text('Tes cetak terkirim.'), findsOneWidget);
    expect(transport.jobs, hasLength(1));
    expect(rasterizer.widths.single, PaperWidth.mm80);

    // Ganti ke printer Bluetooth (port COM) lalu cek sambungan.
    await tapVisible(tester, find.text('Bluetooth'));
    await settle(tester);
    await tapVisible(tester, find.text('Pilih port…'));
    await settle(tester);
    await tester.tap(find.text('COM5'));
    await settle(tester);
    await tapVisible(tester, find.text('Cek Sambungan'));
    await settle(tester);
    expect(find.textContaining('Printer tersambung (COM5'), findsOneWidget);
    expect(transport.checked.single.serialPort, 'COM5');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Printer Nota'), findsOneWidget); // label tombol

    final saved = (await tester.runAsync(
      () => ReceiptSettingsRepository(db).printer(),
    ))!;
    expect(saved.printerName, 'Thermal 58');
    expect(saved.paperWidth, PaperWidth.mm80);
    expect(saved.connection, PrinterConnection.serial);
    expect(saved.serialPort, 'COM5');

    await unmount(tester);
  });

  testWidgets('Admin membuat backup dari Pengaturan', (tester) async {
    /// Status backup membaca folder (I/O sungguhan): pompa waktu nyata
    /// sampai [finder] muncul.
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await waitFor(find.text('Backup otomatis'));
    expect(find.text('Backup otomatis'), findsOneWidget);
    expect(find.text('Belum pernah'), findsOneWidget);
    expect(find.text('7 hari'), findsOneWidget);
    expect(find.text('2 file'), findsOneWidget);

    // Simpan maksimal 2 → 3 file.
    await tapCentered(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('backup-keep')),
        matching: find.byIcon(CupertinoIcons.plus),
      ),
    );
    await waitFor(find.text('3 file'));
    expect(find.text('3 file'), findsOneWidget);

    await tapCentered(tester, find.text('Backup Sekarang'));
    await waitFor(find.text('Backup selesai'));
    expect(find.text('Backup selesai'), findsOneWidget);
    expect(find.textContaining('toko-database-'), findsWidgets);
    await tester.tap(find.text('OK'));
    await settle(tester);
    await waitFor(find.textContaining('toko-barang-'));
    expect(find.text('Belum pernah'), findsNothing);
    expect(find.textContaining('toko-barang-'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Admin memulihkan backup: disiapkan lalu aplikasi ditutup', (
    tester,
  ) async {
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    var exited = false;
    await pumpApp(
      tester,
      overrides: [exitAppProvider.overrideWithValue(() => exited = true)],
    );
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await waitFor(find.text('Backup Sekarang'));
    await tapCentered(tester, find.text('Backup Sekarang'));
    await waitFor(find.text('Backup selesai'));
    await tester.tap(find.text('OK'));
    await settle(tester);
    await waitFor(find.textContaining('toko-database-'));

    // Ketuk file backup database → ringkasan → Pulihkan.
    await tapVisible(tester, find.textContaining('toko-database-').last);
    await settle(tester);
    expect(find.text('Pulihkan data dari backup?'), findsOneWidget);
    expect(find.textContaining('20 barang'), findsOneWidget);
    await tester.tap(find.text('Pulihkan'));
    await waitFor(find.text('Siap dipulihkan'));
    expect(find.textContaining('toko-sebelum-pulih-'), findsOneWidget);
    await tester.tap(find.text('Tutup Aplikasi'));
    await settle(tester);
    expect(exited, isTrue);
    await waitFor(find.text('Pemulihan menunggu'));
    expect(find.text('Pemulihan menunggu'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Kasir membuka Pengaturan versi ringkas', (tester) async {
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await waitFor(find.text('Backup otomatis'));

    expect(find.text('Kode terminal'), findsOneWidget);
    expect(find.text('Backup otomatis'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Versi'), findsOneWidget);
    // Menu admin tidak tampil.
    expect(find.text('Kelola Akun'), findsNothing);
    expect(find.text('Kelola Kategori'), findsNothing);
    expect(find.text('Metode Pembayaran'), findsNothing);
    expect(find.text('Kelola Toko'), findsNothing);
    expect(find.text('Struk & Printer'), findsNothing);
    // Pengaturan backup hanya dilihat (tanpa tombol ubah).
    expect(find.byKey(const ValueKey('backup-keep')), findsNothing);
    expect(find.text('2 file'), findsOneWidget);
    expect(find.text('Backup Sekarang'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Admin membuat tag, memasangnya di barang, lalu memfilter', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.runAsync(() => clearSampleTags(db));
    await login(tester, 'admin', 'admin123');

    // Pengaturan › Kelola Tag › Tambah Tag.
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await tapCentered(tester, find.text('Kelola Kategori'));
    await settle(tester);
    expect(find.text('Belum ada kategori'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Kategori').first);
    await settle(tester);
    await fill(tester, 'Nama kategori', 'Mainan');
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Kategori').last);
    await settle(tester);
    expect(find.text('Mainan'), findsOneWidget);
    expect(find.text('0 barang'), findsOneWidget);

    // Produk › Indomie › Tag: pilih Mainan + buat "Promo" dari pemilih.
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(find.text('Indomie Goreng 85g'));
    await settle(tester);
    await tapCentered(tester, find.text('Tanpa kategori'));
    await settle(tester);
    expect(find.text('Kategori Barang'), findsOneWidget);
    await tester.tap(find.text('Mainan'));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(CupertinoSearchTextField).last,
        matching: find.byType(EditableText),
      ),
      'Promo',
    );
    await settle(tester);
    expect(find.text('Buat kategori "Promo"'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await tester.tap(find.text('Selesai (2 kategori)'));
    await settle(tester);
    await tapCentered(tester, find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    // Konfirmasi perubahan: tag kosong → Mainan, Promo.
    expect(find.text('Simpan perubahan?'), findsOneWidget);
    expect(
      find.textContaining('Tanpa kategori', findRichText: true),
      findsWidgets,
    );
    await tester.tap(find.widgetWithText(AppButton, 'Simpan').last);
    await settle(tester);

    // Chip tag tampil di daftar; filter per tag.
    expect(find.text('Mainan'), findsOneWidget);
    expect(find.text('Promo'), findsOneWidget);
    await tester.tap(find.text('Semua kategori'));
    await settle(tester);
    await tester.tap(find.text('Promo').last);
    await settle(tester);
    expect(find.textContaining('1 barang · '), findsOneWidget);
    expect(find.text('Indomie Goreng 85g'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Ubah barang: konfirmasi daftar perubahan sebelum disimpan', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);

    // Tanpa perubahan: Simpan langsung menutup form tanpa konfirmasi.
    await tester.tap(find.text('Indomie Goreng 85g'));
    await settle(tester);
    await tapCentered(tester, find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('Simpan perubahan?'), findsNothing);
    expect(find.text('Ubah Barang'), findsNothing);

    // Ubah harga jual → konfirmasi menampilkan harga lama dan baru.
    await tester.tap(find.text('Indomie Goreng 85g'));
    await settle(tester);
    await fill(tester, 'Harga jual (Rp)', '3700');
    await tapCentered(tester, find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('Simpan perubahan?'), findsOneWidget);
    expect(find.text('Harga jual'), findsWidgets);
    expect(find.textContaining('Rp 3.500', findRichText: true), findsWidgets);
    expect(find.textContaining('Rp 3.700', findRichText: true), findsWidgets);

    // Periksa Lagi: kembali ke form, belum tersimpan.
    await tester.tap(find.text('Periksa Lagi'));
    await settle(tester);
    expect(find.text('Ubah Barang'), findsOneWidget);
    Future<int> price() async => (await tester.runAsync(
      () async => (await (db.select(
        db.products,
      )..where((p) => p.code.equals('BRG001'))).getSingle()).sellingPrice,
    ))!;
    expect(await price(), 3500);

    await tapCentered(tester, find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Simpan').last);
    await settle(tester);
    expect(find.text('Ubah Barang'), findsNothing);
    expect(await price(), 3700);

    await unmount(tester);
  });

  testWidgets('Tag dengan warna kustom dari color wheel / kode hex', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await tapCentered(tester, find.text('Kelola Kategori'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Kategori').first);
    await settle(tester);
    await fill(tester, 'Nama kategori', 'Boneka');

    await tester.tap(find.byKey(const ValueKey('custom-color')));
    await settle(tester);
    expect(find.text('Warna Kategori'), findsOneWidget);
    // Geser di roda warna lalu ketik kode hex.
    await tester.tap(find.byKey(const ValueKey('color-wheel')));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('color-hex')),
        matching: find.byType(EditableText),
      ),
      'FF8800',
    );
    await settle(tester);
    await tester.tap(find.text('Pakai Warna'));
    await settle(tester);
    expect(find.text('Warna kustom #FF8800'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Tambah Kategori').last);
    await settle(tester);
    final tag = (await tester.runAsync(
      () => (db.select(
        db.tags,
      )..where((t) => t.name.equals('Boneka'))).getSingle(),
    ))!;
    expect(tag.color, '#FF8800');
    expect(find.text('#FF8800'), findsOneWidget); // subtitle di daftar tag

    await unmount(tester);
  });
}
