import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/app.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/security/password_hasher.dart';
import 'package:toko/core/widgets/app_button.dart';
import 'package:toko/core/widgets/app_sidebar.dart';
import 'package:toko/features/products/presentation/product_import_page.dart';
import 'package:toko/features/vouchers/domain/voucher.dart';

import 'helpers/test_app.dart';

/// Hash/verifikasi bcrypt tanpa isolate, karena isolate tidak berjalan di dalam
/// waktu palsu (fake async) milik testWidgets.
class _SyncHasher extends PasswordHasher {
  const _SyncHasher() : super(logRounds: 4);

  @override
  Future<bool> verify(String password, String hash) async =>
      BCrypt.checkpw(password, hash);

  @override
  Future<String> hash(String password) async =>
      BCrypt.hashpw(password, BCrypt.gensalt(logRounds: logRounds));
}

/// Kursor teks berkedip terus, jadi pumpAndSettle tidak bisa dipakai.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> login(
  WidgetTester tester,
  String username,
  String password,
) async {
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), username);
  await tester.enterText(fields.at(1), password);
  await settle(tester); // tombol Masuk aktif setelah frame berikutnya
  await tester.tap(find.text('Masuk'));
  await settle(tester);
}

Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = (await tester.runAsync(createSeededDb))!;
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        passwordHasherProvider.overrideWithValue(const _SyncHasher()),
        ...overrides,
      ],
      child: const TokoApp(),
    ),
  );
  await settle(tester);
  return db;
}

/// Membongkar aplikasi di akhir tes supaya stream drift sempat ditutup
/// dan tidak ada timer yang tertinggal.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Gulir sampai [finder] terlihat, lalu ketuk.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Mengisi AppTextField berdasarkan labelnya.
Future<void> fill(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first,
    matching: find.byType(EditableText),
  );
  await tester.enterText(field, text);
  await tester.pump();
}

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
    expect(find.text('Pengaturan'), findsNothing);

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

  testWidgets('Kasir scan, pakai voucher, bayar tunai dan QRIS', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');

    Future<void> scan(String code) async {
      await fill(tester, 'Kode / Barcode', code);
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

    // F4: pasang voucher (dibuat admin sebelumnya).
    await tester.runAsync(
      () => db
          .into(db.vouchers)
          .insert(
            VouchersCompanion.insert(
              code: 'HEMAT1K',
              type: VoucherType.amount,
              value: 1000,
            ),
          ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await settle(tester);
    expect(find.text('Pakai Voucher'), findsWidgets);
    await tester.enterText(find.byType(EditableText).last, 'hemat1k');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('HEMAT1K'), findsOneWidget);
    expect(find.text('Rp 9.500'), findsWidgets); // 10.500 − 1.000

    // F2 membuka popup pembayaran; Tunai terpilih otomatis.
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    expect(find.text('Pembayaran'), findsOneWidget);
    expect(find.text('QRIS'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, '20000');
    await settle(tester);
    expect(find.text('Rp 10.500'), findsWidgets); // kembalian
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
    expect(find.textContaining('HEMAT1K'), findsOneWidget);
    expect(find.text('QRIS'), findsOneWidget);
    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('Omzet Hari Ini'), findsNothing);

    // Stok berkurang.
    final indomie = (await tester.runAsync(
      () => (db.select(
        db.products,
      )..where((p) => p.code.equals('BRG001'))).getSingle(),
    ))!;
    expect(indomie.stock, 118);

    await unmount(tester);
  });

  testWidgets('Nama salah ketik di kasir menampilkan saran yang mendekati', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');

    // Ketik nama (bukan kode) dengan salah ketik di kolom kode, lalu Enter.
    await fill(tester, 'Kode / Barcode', 'chitatoo');
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

  testWidgets('Admin mengelola barang di halaman Produk', (tester) async {
    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);

    expect(find.text('20 barang'), findsOneWidget);
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
    await fill(tester, 'Kode', 'BRG100');
    await fill(tester, 'Harga beli (Rp)', '9000');
    await fill(tester, 'Harga jual (Rp)', '11000');
    await fill(tester, 'Stok', '2');
    await fill(tester, 'Stok minimum (opsional)', '5');
    await settle(tester);
    expect(find.textContaining('Untung Rp 2.000'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Simpan Barang'));
    await settle(tester);
    expect(find.text('Barang Baru'), findsNothing);
    expect(find.text('21 barang'), findsOneWidget);

    // Filter stok menipis memuat barang baru (2 ≤ 5).
    await tester.tap(find.text('Stok menipis'));
    await settle(tester);
    expect(find.text('Kecap Bango 220ml'), findsOneWidget);
    expect(find.text('4 barang'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Admin import barang dari file gaya iPOS', (tester) async {
    const csv =
        'Kode Item,Nama Item,Jenis,Satuan,Harga Pokok,Harga Jual 1,Stok\n'
        'BRG001,Indomie Goreng,Makanan,PCS,2900,3700,150\n'
        'IPOS1,Kopi Kenangan,Minuman,BTL,8000,10000,24\n'
        'IPOS2,Roti Aoka,Roti,PCS,1500,,10\n';
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

    await tapVisible(tester, find.text('Update stok & harga saja'));
    await settle(tester);
    await tapVisible(tester, find.widgetWithText(AppButton, 'Import 2 barang'));
    await settle(tester);
    expect(find.text('Import selesai'), findsOneWidget);
    expect(find.text('2 barang tersimpan'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(AppButton, 'Lihat Produk'));
    await settle(tester);
    expect(find.text('21 barang'), findsOneWidget);
    expect(find.text('Kopi Kenangan'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Dashboard admin menampilkan transaksi dari kasir', (
    tester,
  ) async {
    await pumpApp(tester);

    // Kasir menjual 2 Indomie (Rp 7.000, laba 2 × 700).
    await login(tester, 'kasir', 'kasir123');
    await fill(tester, 'Kode / Barcode', 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await fill(tester, 'Kode / Barcode', 'BRG001');
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
}
