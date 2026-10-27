import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/audit/data/audit_repository.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/core/database/tables/audit.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/product_pricing.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/sync/data/sync_codec.dart';
import 'package:toko/features/sync/data/sync_service.dart';
import 'package:toko/features/sync/data/terminal_repository.dart';
import 'package:toko/server/server_store.dart';
import 'package:toko/server/toko_server.dart';
import 'package:toko/sync_protocol/sync_protocol.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  late ServerStore store;
  late TokoServer server;
  late AppDatabase master;
  late AppDatabase branch;
  late String address;

  setUp(() async {
    store = ServerStore(sqlite3.openInMemory());
    server = TokoServer(store, log: (_) {});
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    address = '127.0.0.1:${server.port}';
    master = await createSeededDb();
    branch = await createSeededDb();
  });

  tearDown(() async {
    await server.stop();
    store.close();
    await master.close();
    await branch.close();
  });

  Future<AppUser> login(AppDatabase db, String user, String pass) =>
      AuthRepository(db, testHasher).login(user, pass);

  Future<void> pairBoth() async {
    final admin = await login(master, 'admin', 'admin123');
    await SyncService(master).pair(
      actor: admin,
      address: address,
      code: store.pairingCode,
      role: SyncRole.master,
      name: 'Pusat',
    );
    final branchAdmin = await login(branch, 'admin', 'admin123');
    await TerminalRepository(branch).setCode(actor: branchAdmin, code: 'K02');
    await SyncService(branch).pair(
      actor: branchAdmin,
      address: address,
      code: store.pairingCode,
      role: SyncRole.client,
      name: 'Cabang',
    );
  }

  Future<CheckoutResult> sell(AppDatabase db, String code, double qty) async {
    final kasir = await login(db, 'kasir', 'kasir123');
    final p = (await ProductRepository(db)
        .findByCodeOrBarcode(code, storeId: kasir.storeId))!;
    final tunai = (await PaymentMethodRepository(
      db,
    ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
    return CheckoutService(db).checkout(
      cart: const Cart().add(p, qty: qty),
      cashier: kasir,
      storeId: kasir.storeId!,
      paymentMethodId: tunai.id,
      paid: 1000000,
    );
  }

  Future<double> stock(AppDatabase db, String code) async {
    final s = (await (db.select(db.stores)..limit(1)).getSingle()).id;
    return (await ProductRepository(
      db,
    ).findByCodeOrBarcode(code, storeId: s))!.stock;
  }

  test('pairing: cabang mengambil data master, kode pairing dicek', () async {
    final admin = await login(branch, 'admin', 'admin123');
    await expectLater(
      SyncService(branch).pair(
        actor: admin,
        address: address,
        code: '000000',
        role: SyncRole.client,
      ),
      throwsA(isA<SyncFailure>()),
    );
    // Master asli: buat barang khusus supaya terlihat di cabang.
    final mAdmin = await login(master, 'admin', 'admin123');
    await ProductRepository(master).save(
      actor: mAdmin,
      draft: const ProductDraft(
        code: 'PUSAT1',
        name: 'Barang Pusat',
        sellingPrice: 7000,
        tagNames: ['Khusus'],
      ),
    );
    await pairBoth();

    final branchProducts = ProductRepository(branch);
    final p = (await branchProducts.findByCodeOrBarcode('PUSAT1'))!;
    expect(p.name, 'Barang Pusat');
    expect(p.tags.single.name, 'Khusus');
    // Stok mengikuti riwayat stok dari master (BRG001 = 120 di master).
    expect(await stock(branch, 'BRG001'), await stock(master, 'BRG001'));
    expect(await branch.select(branch.products).get(), hasLength(21));
    // Akun dari master; password sama.
    expect((await login(branch, 'kasir', 'kasir123')).username, 'kasir');
    expect(store.terminals().map((t) => (t.code, t.role)), [
      ('K01', SyncRole.master),
      ('K02', SyncRole.client),
    ]);

    // Kode terminal kembar ditolak.
    final third = await createSeededDb();
    addTearDown(third.close);
    await expectLater(
      SyncService(third).pair(
        actor: await login(third, 'admin', 'admin123'),
        address: address,
        code: store.pairingCode,
        role: SyncRole.client,
      ),
      throwsA(
        isA<SyncFailure>().having((e) => e.message, 'message', contains('K01')),
      ),
    );
  });

  test('faktur cabang sampai ke master (stok ikut), harga dari master '
      'sampai ke cabang', () async {
    await pairBoth();
    final before = await stock(master, 'BRG001');

    final sale = await sell(branch, 'BRG001', 3);
    expect(sale.invoiceNo, startsWith('INV-K02-'));
    final sent = await SyncService(branch).syncNow();
    // Faktur + riwayat stok + catatan aktivitas (login, penjualan).
    expect(sent.sent, greaterThanOrEqualTo(2));
    expect(await branch.outboxDao.pending(), isEmpty);
    await SyncService(master).syncNow();

    final onMaster = await (master.select(
      master.sales,
    )..where((s) => s.invoiceNo.equals(sale.invoiceNo))).getSingle();
    expect(onMaster.total, sale.total);
    expect(await master.salesDao.itemsOf(onMaster.id), hasLength(1));
    expect(await stock(master, 'BRG001'), before - 3);

    // Kirim ulang tidak menggandakan.
    await SyncService(master).syncNow();
    expect(await master.select(master.sales).get(), hasLength(1));

    // Master mengubah harga → cabang ikut.
    final mAdmin = await login(master, 'admin', 'admin123');
    final repo = ProductRepository(master);
    final p = (await repo.findByCodeOrBarcode('BRG001'))!;
    await repo.save(
      actor: mAdmin,
      id: p.id,
      draft: ProductDraft(
        code: p.code,
        barcode: p.barcode,
        name: p.name,
        unitName: p.unitName,
        purchasePrice: p.purchasePrice,
        sellingPrice: 3800,
      ),
    );
    await SyncService(master).syncNow();
    await SyncService(branch).syncNow();
    expect(
      (await ProductRepository(branch).findByCodeOrBarcode('BRG001'))!
          .sellingPrice,
      3800,
    );

    // Penjualan master mengurangi stok di cabang.
    await sell(master, 'BRG001', 2);
    await SyncService(master).syncNow();
    await SyncService(branch).syncNow();
    expect(await stock(branch, 'BRG001'), before - 5);
    expect(await stock(master, 'BRG001'), before - 5);

    // Pemeriksaan keutuhan: faktur kiriman tercatat, tidak dianggap
    // disisipkan.
    final issues = (await IntegrityService(master).check()).issues;
    expect(issues.map((i) => i.title), isEmpty);
    expect((await IntegrityService(branch).check()).issues, isEmpty);
  });

  test('retur di cabang & data master dikunci di cabang', () async {
    await pairBoth();
    final sale = await sell(branch, 'BRG010', 2);
    final admin = await login(branch, 'admin', 'admin123');
    final item = (await branch.salesDao.itemsOf(sale.saleId)).single;
    await ReturnService(branch).create(
      actor: admin,
      saleId: sale.saleId,
      qtys: {item.id: 1},
      reason: 'Rusak',
    );
    await SyncService(branch).syncNow();
    await SyncService(master).syncNow();
    final ret = await (master.select(
      master.sales,
    )..where((s) => s.returnOfId.isNotNull())).getSingle();
    final original = await (master.select(
      master.sales,
    )..where((s) => s.id.equals(ret.returnOfId!))).getSingle();
    expect(original.invoiceNo, sale.invoiceNo);

    await expectLater(
      ProductRepository(branch).save(
        actor: admin,
        draft: const ProductDraft(
          code: 'CABANG1',
          name: 'Barang Cabang',
          sellingPrice: 1000,
        ),
      ),
      throwsA(
        isA<ProductFailure>().having(
          (e) => e.message,
          'message',
          contains('Komputer cabang'),
        ),
      ),
    );
  });

  test('cabang yang sudah punya transaksi tidak bisa jadi cabang', () async {
    await sell(branch, 'BRG001', 1);
    final admin = await login(branch, 'admin', 'admin123');
    await expectLater(
      SyncService(branch).pair(
        actor: admin,
        address: address,
        code: store.pairingCode,
        role: SyncRole.client,
      ),
      throwsA(isA<SyncFailure>()),
    );
  });

  test(
    'server: master kedua ditolak, cabang tidak boleh kirim data master',
    () async {
      await pairBoth();
      final other = await createSeededDb();
      addTearDown(other.close);
      final otherAdmin = await login(other, 'admin', 'admin123');
      await TerminalRepository(other).setCode(actor: otherAdmin, code: 'K03');
      await expectLater(
        SyncService(other).pair(
          actor: otherAdmin,
          address: address,
          code: store.pairingCode,
          role: SyncRole.master,
        ),
        throwsA(
          isA<SyncFailure>().having(
            (e) => e.message,
            'message',
            contains('sudah punya komputer master'),
          ),
        ),
      );
      final branchTerminal = store.terminals().firstWhere(
        (t) => t.code == 'K02',
      );
      expect(
        () => store.push(branchTerminal, [
          const SyncChange(entity: SyncEntity.product, uuid: 'x', data: {}),
        ]),
        throwsA(isA<ServerFailure>()),
      );
    },
  );

  test('catatan aktivitas cabang sampai ke master; yang dihapus di cabang '
      'ketahuan', () async {
    await pairBoth();
    final kasir = await login(branch, 'kasir', 'kasir123');
    final audit = AuditRepository(branch);
    await audit.record(AuditType.drawerOpened, 'Laci A', actor: kasir);
    await audit.record(AuditType.cartCleared, 'Batal B', actor: kasir);
    await audit.record(AuditType.drawerOpened, 'Laci C', actor: kasir);
    await SyncService(branch).syncNow();
    await SyncService(master).syncNow();

    final now = DateTime.now();
    final entries = await AuditRepository(master).between(
      now.subtract(const Duration(hours: 1)),
      now.add(const Duration(hours: 1)),
    );
    final fromBranch = entries.where((e) => e.terminalCode == 'K02');
    expect(
      fromBranch.map((e) => e.summary),
      containsAll(['Laci A', 'Batal B', 'Laci C']),
    );
    expect(
      fromBranch.firstWhere((e) => e.summary == 'Batal B').userName,
      kasir.fullName,
    );
    // Cabang tidak menerima catatan aktivitas komputer lain.
    expect(await branch.select(branch.remoteAuditLog).get(), isEmpty);
    expect(
      (await IntegrityService(master).check()).issues.map((i) => i.title),
      isNot(contains(contains('terputus'))),
    );

    // Catatan dihapus di cabang sebelum terkirim → rantai di master putus.
    await audit.record(AuditType.drawerOpened, 'Laci D', actor: kasir);
    await audit.record(AuditType.cartCleared, 'Batal E', actor: kasir);
    await audit.record(AuditType.drawerOpened, 'Laci F', actor: kasir);
    await branch.customStatement(
      "DELETE FROM audit_log WHERE summary = 'Batal E'",
    );
    await SyncService(branch).syncNow();
    await SyncService(master).syncNow();
    expect(
      (await IntegrityService(master).check()).issues.map((i) => i.title),
      contains('Catatan aktivitas komputer K02 terputus'),
    );
  });

  test('tarik per halaman: data yang rujukannya belum tiba ditunda', () async {
    final admin = await login(master, 'admin', 'admin123');
    await SyncService(master).pair(
      actor: admin,
      address: address,
      code: store.pairingCode,
      role: SyncRole.master,
    );
    // Barang + kategori, lalu barangnya diubah: di server barang (nomor
    // urut baru) ada SETELAH kategori barangnya.
    final repo = ProductRepository(master);
    final p = await repo.save(
      actor: admin,
      draft: const ProductDraft(
        code: 'URUT1',
        name: 'Barang Urut',
        sellingPrice: 1000,
        tagNames: ['Urutan'],
      ),
    );
    await repo.save(
      actor: admin,
      id: p.id,
      draft: const ProductDraft(
        code: 'URUT1',
        name: 'Barang Urut Baru',
        sellingPrice: 1200,
      ),
    );
    await SyncService(master).syncNow();

    final branchAdmin = await login(branch, 'admin', 'admin123');
    await TerminalRepository(branch).setCode(actor: branchAdmin, code: 'K02');
    await SyncService(branch, pageSize: 7).pair(
      actor: branchAdmin,
      address: address,
      code: store.pairingCode,
      role: SyncRole.client,
    );
    final got = (await ProductRepository(branch).findByCodeOrBarcode('URUT1'))!;
    expect(got.name, 'Barang Urut Baru');
    expect(got.tags.single.name, 'Urutan');
    expect(
      await branch.select(branch.products).get(),
      hasLength((await master.select(master.products).get()).length),
    );
    expect((await IntegrityService(branch).check()).issues, isEmpty);
  });

  test('kode terminal dikunci saat tersambung; sambung ulang tanpa '
      'kehilangan data', () async {
    await pairBoth();
    await sell(branch, 'BRG001', 1);
    final admin = await login(branch, 'admin', 'admin123');
    final terminals = TerminalRepository(branch);
    await expectLater(
      terminals.setCode(actor: admin, code: 'K09'),
      throwsA(isA<TerminalFailure>()),
    );
    await SyncService(branch).unpair(actor: admin);
    await terminals.setCode(actor: admin, code: 'K09');
    final replaced = await SyncService(branch).pair(
      actor: admin,
      address: address,
      code: store.pairingCode,
      role: SyncRole.client,
    );
    expect(replaced, isFalse);
    expect(await branch.select(branch.sales).get(), hasLength(1));
    expect(store.terminals().map((t) => t.code), containsAll(['K01', 'K09']));
    await sell(branch, 'BRG001', 1);
    await SyncService(branch).syncNow();
    await SyncService(master).syncNow();
    expect(await master.select(master.sales).get(), hasLength(2));
  });

  test('harga DUS & grosir khusus toko sampai ke cabang', () async {
    await pairBoth();
    final admin = await login(master, 'admin', 'admin123');
    final repo = ProductRepository(master);
    final p = (await repo.findByCodeOrBarcode('BRG001'))!;
    final storeId = (await (master.select(
      master.stores,
    )..limit(1)).getSingle()).id;
    await repo.save(
      actor: admin,
      id: p.id,
      draft: ProductDraft(
        code: p.code,
        barcode: p.barcode,
        name: p.name,
        unitName: p.unitName,
        purchasePrice: p.purchasePrice,
        sellingPrice: p.defaultSellingPrice,
        units: const [ProductUnit(name: 'DUS', factor: 24, price: 78000)],
        tiers: const [PriceTier(minQty: 10, price: 3300)],
      ),
      stores: [
        StoreProductValues(
          storeId: storeId,
          stock: (await repo.findByCodeOrBarcode(
            'BRG001',
            storeId: storeId,
          ))!.stock,
          unitPrices: const {'DUS': 76000},
          tiers: const [PriceTier(minQty: 6, price: 3250)],
        ),
      ],
    );
    await SyncService(master).syncNow();
    await SyncService(branch).syncNow();
    final branchStore = (await (branch.select(
      branch.stores,
    )..limit(1)).getSingle()).id;
    final got = (await ProductRepository(branch)
        .findByCodeOrBarcode('BRG001', storeId: branchStore))!;
    expect(got.units.single.price, 76000);
    expect(got.units.single.defaultPrice, 78000);
    expect(got.tiers, [const PriceTier(minQty: 6, price: 3250)]);
    expect((await IntegrityService(branch).check()).issues, isEmpty);
  });
}
