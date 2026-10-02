import 'dart:convert';
import 'dart:io';

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
import 'package:toko/core/widgets/large_title_page.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/user_role.dart';
import 'package:toko/features/backup/data/backup_service.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/receipt/data/printer_transport.dart';
import 'package:toko/features/receipt/data/receipt_renderer.dart';
import 'package:toko/features/receipt/data/receipt_settings_repository.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/products/presentation/product_import_page.dart';

import 'helpers/fake_printer.dart';
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
  // Backup ke folder sementara (path_provider tidak ada di tes).
  final backupDir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('toko-backup-'),
  ))!;
  addTearDown(() => backupDir.deleteSync(recursive: true));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        passwordHasherProvider.overrideWithValue(const _SyncHasher()),
        backupServiceProvider.overrideWithValue(
          BackupService(db, defaultFolder: () async => backupDir),
        ),
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

/// Seperti [tapVisible], tetapi digulir ke tengah layar supaya tidak
/// tertutup toolbar kaca halaman panjang.
Future<void> tapCentered(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
}

/// Mengisi AppTextField berdasarkan labelnya. Label yang sama bisa muncul di
/// tempat lain (mis. "Stok" di sidebar), jadi dipilih label pertama yang
/// Column induknya berisi kolom isian.
Future<void> fill(WidgetTester tester, String label, String text) async {
  for (final candidate in find.text(label).evaluate()) {
    final field = find.descendant(
      of: find
          .ancestor(
            of: find.byWidget(candidate.widget),
            matching: find.byType(Column),
          )
          .first,
      matching: find.byType(EditableText),
    );
    if (field.evaluate().isNotEmpty) {
      await tester.enterText(field.first, text);
      await tester.pump();
      return;
    }
  }
  fail('Kolom isian "$label" tidak ditemukan.');
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

  testWidgets('Kasir scan, bayar tunai dan QRIS', (tester) async {
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

  testWidgets('Kasir menahan transaksi lalu melanjutkannya', (tester) async {
    final db = await pumpApp(tester);
    await login(tester, 'kasir', 'kasir123');

    Future<void> scan(String code) async {
      await fill(tester, 'Kode / Barcode', code);
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
    expect(find.text('Kode / Barcode'), findsOneWidget);
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
    expect(find.textContaining('21 barang · '), findsOneWidget);
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
    await fill(tester, 'Kode / Barcode', 'BRG001');
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
    // Kasir tidak bisa membuka Pengaturan, tapi bisa mengatur printer.
    expect(find.text('Pengaturan'), findsNothing);
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

  testWidgets('Admin membuat tag, memasangnya di barang, lalu memfilter', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.runAsync(() => clearSampleTags(db));
    await login(tester, 'admin', 'admin123');

    // Pengaturan › Kelola Tag › Tambah Tag.
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    await tapCentered(tester, find.text('Kelola Tag'));
    await settle(tester);
    expect(find.text('Belum ada tag'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Tag').first);
    await settle(tester);
    await fill(tester, 'Nama tag', 'Mainan');
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Tag').last);
    await settle(tester);
    expect(find.text('Mainan'), findsOneWidget);
    expect(find.text('0 barang'), findsOneWidget);

    // Produk › Indomie › Tag: pilih Mainan + buat "Promo" dari pemilih.
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(find.text('Indomie Goreng 85g'));
    await settle(tester);
    await tapCentered(tester, find.text('Tanpa tag'));
    await settle(tester);
    expect(find.text('Tag Barang'), findsOneWidget);
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
    expect(find.text('Buat tag "Promo"'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await tester.tap(find.text('Selesai (2 tag)'));
    await settle(tester);
    await tapCentered(tester, find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    // Konfirmasi perubahan: tag kosong → Mainan, Promo.
    expect(find.text('Simpan perubahan?'), findsOneWidget);
    expect(find.textContaining('Tanpa tag', findRichText: true), findsWidgets);
    await tester.tap(find.widgetWithText(AppButton, 'Simpan').last);
    await settle(tester);

    // Chip tag tampil di daftar; filter per tag.
    expect(find.text('Mainan'), findsOneWidget);
    expect(find.text('Promo'), findsOneWidget);
    await tester.tap(find.text('Semua tag'));
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
    await tapCentered(tester, find.text('Kelola Tag'));
    await settle(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Tambah Tag').first);
    await settle(tester);
    await fill(tester, 'Nama tag', 'Boneka');

    await tester.tap(find.byKey(const ValueKey('custom-color')));
    await settle(tester);
    expect(find.text('Warna Tag'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(AppButton, 'Tambah Tag').last);
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
